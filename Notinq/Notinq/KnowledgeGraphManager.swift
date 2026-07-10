import Foundation
import Combine
import SwiftUI

final class KnowledgeGraphManager: ObservableObject {
    static let shared = KnowledgeGraphManager()

    @Published private(set) var graphsByNoteID: [UUID: KnowledgeGraph] = [:]
    @Published private(set) var generationStateByNoteID: [UUID: KnowledgeGraphStatusSnapshot] = [:]

    private let store = KnowledgeGraphStore()
    private let extractionService = ConceptExtractionService()
    private let processingQueue = DispatchQueue(label: "notinq.knowledge-graph.processing", qos: .userInitiated)
    private var snapshot: KnowledgeGraphStoreSnapshot
    private var pendingRequestIDByNoteID: [UUID: UUID] = [:]
    private var pendingDebounceByNoteID: [UUID: DispatchWorkItem] = [:]

    private init() {
        snapshot = store.loadSnapshot()
        rebuildGraphCache()
    }

    func generateGraph(note: NoteFile) {
        updateGraph(note: note)
    }

    func updateGraph(note: NoteFile) {
        let trimmedContent = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            deleteGraph(noteID: note.id)
            return
        }

        let noteInput = KnowledgeGraphNoteInput(
            noteID: note.id,
            title: note.title,
            text: trimmedContent,
            updatedAt: note.updatedAt
        )

        pendingDebounceByNoteID[note.id]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.performExtraction(for: noteInput)
        }
        pendingDebounceByNoteID[note.id] = workItem
        processingQueue.asyncAfter(deadline: .now() + 0.01, execute: workItem)
    }

    func deleteGraph(noteID: UUID) {
        pendingDebounceByNoteID[noteID]?.cancel()
        pendingDebounceByNoteID[noteID] = nil
        pendingRequestIDByNoteID[noteID] = nil
        generationStateByNoteID[noteID] = nil

        snapshot.graphs.removeAll { $0.noteID == noteID }
        for index in snapshot.registry.indices {
            snapshot.registry[index].noteIDs.removeAll { $0 == noteID }
        }
        snapshot.registry.removeAll { $0.noteIDs.isEmpty }
        store.saveSnapshot(snapshot)
        rebuildGraphCache()
    }

    func concepts(for noteID: UUID) -> [Concept] {
        graphsByNoteID[noteID]?.concepts ?? []
    }

    func relationships(for noteID: UUID) -> [ConceptRelationship] {
        graphsByNoteID[noteID]?.relationships ?? []
    }

    func relatedConcepts(of concept: Concept) -> [Concept] {
        guard let graph = graphsByNoteID[concept.noteID] ?? graph(containing: concept.id) else {
            return []
        }

        var relatedIDs = Set<UUID>()
        for relationship in graph.relationships where relationship.sourceConceptID == concept.id || relationship.destinationConceptID == concept.id {
            relatedIDs.insert(relationship.sourceConceptID)
            relatedIDs.insert(relationship.destinationConceptID)
        }
        relatedIDs.remove(concept.id)

        return graph.concepts.filter { relatedIDs.contains($0.id) }
    }

    func prerequisites(of concept: Concept) -> [Concept] {
        guard let graph = graphsByNoteID[concept.noteID] ?? graph(containing: concept.id) else {
            return []
        }

        let ids = graph.relationships.compactMap { relationship -> UUID? in
            guard RelationshipBuilder.isPrerequisiteRelation(relationship.type) else { return nil }
            guard relationship.destinationConceptID == concept.id else { return nil }
            return relationship.sourceConceptID
        }

        return graph.concepts.filter { ids.contains($0.id) }
    }

    func dependentConcepts(of concept: Concept) -> [Concept] {
        guard let graph = graphsByNoteID[concept.noteID] ?? graph(containing: concept.id) else {
            return []
        }

        let ids = graph.relationships.compactMap { relationship -> UUID? in
            guard RelationshipBuilder.isPrerequisiteRelation(relationship.type) else { return nil }
            guard relationship.sourceConceptID == concept.id else { return nil }
            return relationship.destinationConceptID
        }

        return graph.concepts.filter { ids.contains($0.id) }
    }

    func searchConcept(_ query: String = "") -> [Concept] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = snapshot.registry.filter { entry in
            guard !trimmed.isEmpty else { return true }
            let normalizedQuery = RelationshipBuilder.normalizedKey(for: trimmed)
            return entry.name.localizedCaseInsensitiveContains(trimmed)
                || entry.aliases.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) })
                || RelationshipBuilder.semanticSimilarityPlaceholder(lhs: entry.name, rhs: trimmed) > 0.45
                || RelationshipBuilder.normalizedKey(for: entry.name).contains(normalizedQuery)
        }

        return candidates.map { snapshot(for: $0, noteID: $0.primaryNoteID) }
    }

    func mergeDuplicateConcepts() {
        var mergedRegistry: [ConceptRegistryEntry] = []
        let entries = snapshot.registry.sorted { $0.updatedDate > $1.updatedDate }

        for entry in entries {
            if let index = mergedRegistry.firstIndex(where: { existing in
                RelationshipBuilder.aliasMatch(existing, candidateName: entry.name, candidateAliases: entry.aliases)
                    || RelationshipBuilder.semanticSimilarityPlaceholder(lhs: existing.name, rhs: entry.name) > 0.88
            }) {
                mergedRegistry[index] = merge(mergedRegistry[index], with: entry)
            } else {
                mergedRegistry.append(entry)
            }
        }

        snapshot.registry = mergedRegistry
        rebuildGraphCache()
        store.saveSnapshot(snapshot)
    }

    private func performExtraction(for note: KnowledgeGraphNoteInput) {
        pendingDebounceByNoteID[note.noteID] = nil
        pendingRequestIDByNoteID[note.noteID] = UUID()
        let requestID = pendingRequestIDByNoteID[note.noteID]

        generationStateByNoteID[note.noteID] = KnowledgeGraphStatusSnapshot(isGenerating: true, message: "Updating knowledge graph...", lastUpdated: snapshot.graphs.first(where: { $0.noteID == note.noteID })?.lastUpdated)
        extractionService.cancelCurrentExtraction()

        extractionService.extractGraph(from: note) { [weak self] result in
            guard let self else { return }

            self.processingQueue.async {
                guard self.pendingRequestIDByNoteID[note.noteID] == requestID else { return }

                switch result {
                case .success(let payload):
                    let graph = self.reconcile(note: note, payload: payload)
                    DispatchQueue.main.async {
                        self.snapshot.graphs.removeAll { $0.noteID == note.noteID }
                        self.snapshot.graphs.append(graph)
                        self.store.saveSnapshot(self.snapshot)
                        self.rebuildGraphCache()
                        self.generationStateByNoteID[note.noteID] = KnowledgeGraphStatusSnapshot(
                            isGenerating: false,
                            message: "Knowledge graph updated.",
                            lastUpdated: graph.lastUpdated
                        )
                    }

                case .failure(let error):
                    DispatchQueue.main.async {
                        self.generationStateByNoteID[note.noteID] = KnowledgeGraphStatusSnapshot(
                            isGenerating: false,
                            message: error.localizedDescription,
                            lastUpdated: self.snapshot.graphs.first(where: { $0.noteID == note.noteID })?.lastUpdated
                        )
                    }
                }
            }
        }
    }

    private func reconcile(note: KnowledgeGraphNoteInput, payload: KnowledgeGraphExtractionPayload) -> KnowledgeGraph {
        let existingGraph = snapshot.graphs.first(where: { $0.noteID == note.noteID })
        let existingConceptIDs = Set(existingGraph?.concepts.map(\.id) ?? [])

        var resolvedConcepts: [Concept] = []
        var resolvedIDs = Set<UUID>()

        for extractedConcept in payload.concepts {
            let registryEntry = resolveRegistryEntry(
                for: extractedConcept,
                noteID: note.noteID
            )
            resolvedIDs.insert(registryEntry.id)
            resolvedConcepts.append(snapshot(for: registryEntry, noteID: note.noteID))
        }

        if existingGraph != nil {
            let removedIDs = existingConceptIDs.subtracting(resolvedIDs)
            for removedID in removedIDs {
                remove(noteID: note.noteID, fromConceptID: removedID)
            }
        }

        let nameToID = Dictionary(uniqueKeysWithValues: resolvedConcepts.map { (RelationshipBuilder.normalizedKey(for: $0.name), $0.id) })

        let relationships = dedupeRelationships(
            payload.relationships.compactMap { relationship -> ConceptRelationship? in
                guard
                    let sourceID = resolveConceptID(for: relationship.source, nameLookup: nameToID),
                    let destinationID = resolveConceptID(for: relationship.target, nameLookup: nameToID)
                else {
                    return nil
                }
                return ConceptRelationship(
                    sourceConceptID: sourceID,
                    destinationConceptID: destinationID,
                    type: relationship.type,
                    confidence: relationship.confidence
                )
            }
        )

        return KnowledgeGraph(
            noteID: note.noteID,
            concepts: resolvedConcepts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            relationships: relationships,
            lastUpdated: note.updatedAt
        )
    }

    private func resolveConceptID(for name: String, nameLookup: [String: UUID]) -> UUID? {
        let normalized = RelationshipBuilder.normalizedKey(for: name)
        if let exact = nameLookup[normalized] {
            return exact
        }

        if let registryEntry = snapshot.registry.first(where: { entry in
            RelationshipBuilder.aliasMatch(entry, candidateName: name, candidateAliases: [])
                || RelationshipBuilder.semanticSimilarityPlaceholder(lhs: entry.name, rhs: name) > 0.7
        }) {
            return registryEntry.id
        }

        return nil
    }

    private func resolveRegistryEntry(for concept: KnowledgeGraphExtractionConcept, noteID: UUID) -> ConceptRegistryEntry {
        let candidate = snapshot.registry.first(where: { entry in
            RelationshipBuilder.aliasMatch(entry, candidateName: concept.name, candidateAliases: concept.aliases)
                || RelationshipBuilder.semanticSimilarityPlaceholder(lhs: entry.name, rhs: concept.name) > 0.8
        })

        if var existing = candidate {
            existing = merge(existing, with: concept, noteID: noteID)
            snapshot.registry.removeAll { $0.id == existing.id }
            snapshot.registry.append(existing)
            return existing
        }

        let entry = ConceptRegistryEntry(
            id: UUID(),
            name: concept.name,
            description: concept.description,
            aliases: concept.aliases,
            primaryNoteID: noteID,
            noteIDs: [noteID],
            confidence: concept.importance,
            createdDate: Date(),
            updatedDate: Date(),
            embeddingID: nil,
            importanceScore: concept.importance,
            difficultyScore: concept.difficulty
        )
        snapshot.registry.append(entry)
        return entry
    }

    private func merge(_ existing: ConceptRegistryEntry, with concept: KnowledgeGraphExtractionConcept, noteID: UUID) -> ConceptRegistryEntry {
        var merged = existing
        merged.name = concept.name.isEmpty ? existing.name : concept.name
        merged.description = concept.description.isEmpty ? existing.description : concept.description
        merged.aliases = dedupeStrings(existing.aliases + concept.aliases)
        merged.confidence = max(existing.confidence, concept.importance)
        merged.updatedDate = Date()
        merged.importanceScore = max(existing.importanceScore, concept.importance)
        merged.difficultyScore = max(0, min(1, (existing.difficultyScore + concept.difficulty) / 2))
        if !merged.noteIDs.contains(noteID) {
            merged.noteIDs.append(noteID)
        }
        return merged
    }

    private func merge(_ existing: ConceptRegistryEntry, with incoming: ConceptRegistryEntry) -> ConceptRegistryEntry {
        var merged = existing
        merged.name = existing.name.count >= incoming.name.count ? existing.name : incoming.name
        merged.description = existing.description.count >= incoming.description.count ? existing.description : incoming.description
        merged.aliases = dedupeStrings(existing.aliases + incoming.aliases + [incoming.name, existing.name])
        merged.noteIDs = Array(Set(existing.noteIDs + incoming.noteIDs))
        merged.confidence = max(existing.confidence, incoming.confidence)
        merged.updatedDate = max(existing.updatedDate, incoming.updatedDate)
        merged.importanceScore = max(existing.importanceScore, incoming.importanceScore)
        merged.difficultyScore = max(existing.difficultyScore, incoming.difficultyScore)
        if merged.primaryNoteID == incoming.primaryNoteID {
            merged.primaryNoteID = existing.primaryNoteID
        }
        return merged
    }

    private func remove(noteID: UUID, fromConceptID conceptID: UUID) {
        guard let index = snapshot.registry.firstIndex(where: { $0.id == conceptID }) else { return }
        snapshot.registry[index].noteIDs.removeAll { $0 == noteID }
        if snapshot.registry[index].noteIDs.isEmpty {
            snapshot.registry.remove(at: index)
            for graphIndex in snapshot.graphs.indices {
                snapshot.graphs[graphIndex].concepts.removeAll { $0.id == conceptID }
                snapshot.graphs[graphIndex].relationships.removeAll {
                    $0.sourceConceptID == conceptID || $0.destinationConceptID == conceptID
                }
            }
        }
    }

    private func snapshot(for entry: ConceptRegistryEntry, noteID: UUID) -> Concept {
        Concept(
            id: entry.id,
            name: entry.name,
            description: entry.description,
            aliases: entry.aliases,
            noteID: noteID,
            confidence: entry.confidence,
            createdDate: entry.createdDate,
            updatedDate: entry.updatedDate,
            embeddingID: entry.embeddingID,
            importanceScore: entry.importanceScore,
            difficultyScore: entry.difficultyScore
        )
    }

    private func dedupeRelationships(_ relationships: [ConceptRelationship]) -> [ConceptRelationship] {
        var seen = Set<String>()
        return relationships.compactMap { relationship in
            let key = RelationshipBuilder.relationshipKey(relationship)
            guard seen.insert(key).inserted else { return nil }
            return relationship
        }
    }

    private func dedupeStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = RelationshipBuilder.normalizedKey(for: trimmed)
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private func graph(containing conceptID: UUID) -> KnowledgeGraph? {
        graphsByNoteID.values.first(where: { graph in
            graph.concepts.contains(where: { $0.id == conceptID })
        })
    }

    private func rebuildGraphCache() {
        var cache: [UUID: KnowledgeGraph] = [:]
        for graph in snapshot.graphs {
            let concepts = graph.concepts.map { concept -> Concept in
                var resolved = concept
                if let registryEntry = snapshot.registry.first(where: { $0.id == concept.id }) {
                    resolved = snapshot(for: registryEntry, noteID: graph.noteID)
                }
                return resolved
            }
            cache[graph.noteID] = KnowledgeGraph(
                noteID: graph.noteID,
                concepts: concepts,
                relationships: graph.relationships,
                lastUpdated: graph.lastUpdated
            )
        }
        graphsByNoteID = cache
    }
}
