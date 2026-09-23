import Foundation
import Combine
import SwiftUI

final class KnowledgeGraphManager: ObservableObject {
    static let shared = KnowledgeGraphManager()

    @Published private(set) var graphsByNoteID: [UUID: KnowledgeGraph] = [:]
    @Published private(set) var generationStateByNoteID: [UUID: KnowledgeGraphStatusSnapshot] = [:]

    private let repository: KnowledgeRepository
    private var canonicalIDByConceptID: [UUID: String] = [:]
    private var conceptIDByCanonicalID: [String: UUID] = [:]

    init(repository: KnowledgeRepository = .shared) {
        self.repository = repository
    }

    func generateGraph(note: NoteFile) {
        updateGraph(note: note)
    }

    func updateGraph(note: NoteFile) {
        generationStateByNoteID[note.id] = KnowledgeGraphStatusSnapshot(
            isGenerating: false,
            message: "Knowledge graph loaded from SQLite.",
            lastUpdated: note.updatedAt
        )
        refreshGraph(noteID: note.id, updatedAt: note.updatedAt)
        NotificationCenter.default.post(name: .knowledgeGraphDidChange, object: note.id)
    }

    func deleteGraph(noteID: UUID) {
        graphsByNoteID.removeValue(forKey: noteID)
        generationStateByNoteID.removeValue(forKey: noteID)
        NotificationCenter.default.post(name: .knowledgeGraphDidChange, object: noteID)
    }

    func concepts(for noteID: UUID) -> [Concept] {
        refreshGraph(noteID: noteID)
        return graphsByNoteID[noteID]?.concepts ?? []
    }

    func relationships(for noteID: UUID) -> [ConceptRelationship] {
        refreshGraph(noteID: noteID)
        return graphsByNoteID[noteID]?.relationships ?? []
    }

    func relatedConcepts(of concept: Concept) -> [Concept] {
        guard let canonicalID = canonicalIDByConceptID[concept.id] else { return [] }
        let related = (try? repository.relatedConcepts(of: canonicalID, depth: 1, limit: 32)) ?? []
        return related.map { adapterConcept(from: $0, noteID: concept.noteID) }
    }

    func prerequisites(of concept: Concept) -> [Concept] {
        guard let canonicalID = canonicalIDByConceptID[concept.id] else { return [] }
        let relationships = (try? repository.relationships(containing: canonicalID, limit: 128)) ?? []
        return relationships
            .filter { $0.sourceConceptID == canonicalID && isPrerequisiteRelationship($0) }
            .compactMap { try? repository.concept(for: $0.targetConceptID) }
            .map { adapterConcept(from: $0, noteID: concept.noteID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func dependentConcepts(of concept: Concept) -> [Concept] {
        guard let canonicalID = canonicalIDByConceptID[concept.id] else { return [] }
        let relationships = (try? repository.relationships(containing: canonicalID, limit: 128)) ?? []
        return relationships
            .filter { $0.targetConceptID == canonicalID && isPrerequisiteRelationship($0) }
            .compactMap { try? repository.concept(for: $0.sourceConceptID) }
            .map { adapterConcept(from: $0, noteID: concept.noteID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func searchConcept(_ query: String = "") -> [Concept] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let records: [ConceptSearchRecord]
        if trimmed.isEmpty {
            records = (try? repository.searchRecentConcepts(limit: 64)) ?? []
        } else {
            records = (try? repository.searchConcepts(query: trimmed, limit: 64)) ?? []
        }

        return records.map { record in
            adapterConcept(
                from: CanonicalConceptRecord(
                    id: record.conceptID,
                    canonicalName: record.canonicalName,
                    aliases: record.aliases,
                    sourceReferences: record.noteIDs.map(\.uuidString),
                    confidence: min(1.0, max(0.0, record.rank)),
                    description: record.description
                ),
                noteID: record.noteIDs.first ?? UUID()
            )
        }
    }

    func mergeDuplicateConcepts() {
        // Canonical merging is handled by KnowledgeRepository during SQLite persistence.
        refreshVisibleGraphs()
    }

    private func refreshGraph(noteID: UUID, updatedAt: Date = Date()) {
        let concepts = ((try? repository.concepts(for: noteID)) ?? [])
            .map { adapterConcept(from: $0, noteID: noteID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let relationships = ((try? repository.relationships(for: noteID)) ?? [])
            .map(adapterRelationship(from:))

        graphsByNoteID[noteID] = KnowledgeGraph(
            noteID: noteID,
            concepts: concepts,
            relationships: relationships,
            lastUpdated: updatedAt
        )
    }

    private func refreshVisibleGraphs() {
        for noteID in graphsByNoteID.keys {
            refreshGraph(noteID: noteID, updatedAt: graphsByNoteID[noteID]?.lastUpdated ?? Date())
        }
    }

    private func adapterConcept(from record: CanonicalConceptRecord, noteID: UUID) -> Concept {
        let id = adapterID(forCanonicalID: record.id)
        return Concept(
            id: id,
            name: record.canonicalName,
            description: record.description,
            aliases: record.aliases,
            noteID: noteID,
            confidence: record.confidence,
            createdDate: Date(),
            updatedDate: Date(),
            embeddingID: nil,
            importanceScore: min(1.0, max(0.0, record.confidence)),
            difficultyScore: max(0.0, min(1.0, 1.0 - record.confidence))
        )
    }

    private func adapterRelationship(from record: KnowledgeRelationshipRecord) -> ConceptRelationship {
        ConceptRelationship(
            sourceConceptID: adapterID(forCanonicalID: record.sourceConceptID),
            destinationConceptID: adapterID(forCanonicalID: record.targetConceptID),
            type: adapterRelationshipType(from: record.relationType),
            confidence: record.confidence
        )
    }

    private func adapterID(forCanonicalID canonicalID: String) -> UUID {
        if let existing = conceptIDByCanonicalID[canonicalID] {
            return existing
        }
        let id = UUID()
        conceptIDByCanonicalID[canonicalID] = id
        canonicalIDByConceptID[id] = canonicalID
        return id
    }

    private func adapterRelationshipType(from relationType: String) -> ConceptRelationshipType {
        switch relationType {
        case KnowledgeRelationshipKind.requires.rawValue:
            return .dependsOn
        case KnowledgeRelationshipKind.partOf.rawValue:
            return .partOf
        case KnowledgeRelationshipKind.exampleOf.rawValue:
            return .exampleOf
        case KnowledgeRelationshipKind.causes.rawValue:
            return .causes
        case KnowledgeRelationshipKind.uses.rawValue:
            return .applicationOf
        default:
            return .relatedTo
        }
    }

    private func isPrerequisiteRelationship(_ relationship: KnowledgeRelationshipRecord) -> Bool {
        let relation = relationship.relationType.lowercased()
        return relationship.relationType == KnowledgeRelationshipKind.requires.rawValue
            || relation.contains("require")
            || relation.contains("depend")
            || relation.contains("prereq")
    }
}
