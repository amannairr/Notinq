import Foundation

final class GraphExpansionService {
    private let repository: KnowledgeRepository
    private let explanations: GraphExplanationService
    private let maxDepth: Int
    private let maxNodes: Int

    init(
        repository: KnowledgeRepository = .shared,
        explanations: GraphExplanationService? = nil,
        maxDepth: Int = 2,
        maxNodes: Int = 25
    ) {
        self.repository = repository
        self.explanations = explanations ?? GraphExplanationService(repository: repository)
        self.maxDepth = max(1, min(maxDepth, 4))
        self.maxNodes = max(1, min(maxNodes, 64))
    }

    func expand(question: String, seedConcepts: [Concept]) -> [Concept] {
        var conceptsByID: [UUID: Concept] = [:]
        var frontier: [(concept: Concept, depth: Int)] = []

        func add(_ concept: Concept, depth: Int) {
            guard conceptsByID[concept.id] == nil, conceptsByID.count < maxNodes else { return }
            conceptsByID[concept.id] = concept
            frontier.append((concept, depth))
        }

        let seeds = seedConcepts.isEmpty ? conceptsMatching(question, limit: 8) : seedConcepts
        for seed in seeds {
            add(seed, depth: 0)
        }

        while frontier.isEmpty == false, conceptsByID.count < maxNodes {
            let current = frontier.removeFirst()
            guard current.depth < maxDepth else { continue }

            for concept in directExpansion(for: current.concept) where conceptsByID.count < maxNodes {
                add(concept, depth: current.depth + 1)
            }
        }

        return conceptsByID.values.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func relationships(for concepts: [Concept], limit: Int = 64) -> [ConceptRelationship] {
        var relationshipsByID: [UUID: ConceptRelationship] = [:]
        for concept in concepts {
            let relationships = (try? repository.relationships(containing: canonicalID(for: concept), limit: limit)) ?? []
            for relationship in relationships {
                let converted = conceptRelationship(from: relationship)
                relationshipsByID[converted.id] = converted
            }
        }
        return relationshipsByID.values.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            if $0.sourceConceptID != $1.sourceConceptID { return $0.sourceConceptID.uuidString < $1.sourceConceptID.uuidString }
            if $0.destinationConceptID != $1.destinationConceptID { return $0.destinationConceptID.uuidString < $1.destinationConceptID.uuidString }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func prerequisites(for concepts: [Concept], limit: Int = 25) -> [Concept] {
        var resultByID: [UUID: Concept] = [:]
        for concept in concepts {
            for name in explanations.prerequisiteChain(for: concept.name) {
                guard let canonical = try? repository.canonicalConcept(named: name),
                      let record = try? repository.concept(for: canonical.id)
                else { continue }
                let converted = self.concept(from: record)
                resultByID[converted.id] = converted
            }
        }
        return Array(resultByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }.prefix(limit))
    }

    private func directExpansion(for concept: Concept) -> [Concept] {
        let conceptID = canonicalID(for: concept)
        let neighbors = ((try? repository.neighbors(of: conceptID, limit: 8)) ?? []).map(concept(from:))
        let prerequisites = ((try? repository.descendants(of: conceptID, depth: 1, limit: 8)) ?? []).map(concept(from:))
        let dependents = ((try? repository.ancestors(of: conceptID, depth: 1, limit: 8)) ?? []).map(concept(from:))
        return dedupe(neighbors + prerequisites + dependents)
    }

    private func conceptsMatching(_ question: String, limit: Int) -> [Concept] {
        let searched = ((try? repository.searchConcepts(query: question, limit: limit)) ?? [])
            .compactMap { try? repository.concept(for: $0.conceptID) }
            .map(concept(from:))
        if searched.isEmpty == false {
            return searched
        }
        return candidateTerms(from: question).compactMap { term in
            guard let canonical = try? repository.canonicalConcept(named: term),
                  let record = try? repository.concept(for: canonical.id)
            else { return nil }
            return concept(from: record)
        }
    }

    private func candidateTerms(from text: String) -> [String] {
        let cleaned = text.replacingOccurrences(of: "?", with: " ")
        let words = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
        var terms = [cleaned.trimmingCharacters(in: .whitespacesAndNewlines)]
        terms.append(contentsOf: words)
        for windowSize in [3, 2] where words.count >= windowSize {
            for index in 0...(words.count - windowSize) {
                terms.append(words[index..<(index + windowSize)].joined(separator: " "))
            }
        }
        return terms.uniqued().filter { $0.isEmpty == false }
    }

    private func dedupe(_ concepts: [Concept]) -> [Concept] {
        var seen: Set<UUID> = []
        return concepts.filter { seen.insert($0.id).inserted }
    }

    private func concept(from record: CanonicalConceptRecord) -> Concept {
        Concept(
            id: stableUUID(for: record.id),
            name: record.canonicalName,
            description: record.description,
            aliases: record.aliases,
            noteID: record.sourceReferences.compactMap(UUID.init(uuidString:)).first ?? stableUUID(for: "note-\(record.id)"),
            confidence: record.confidence,
            createdDate: Date(),
            updatedDate: Date(),
            embeddingID: record.id,
            importanceScore: record.confidence,
            difficultyScore: 1.0 - record.confidence
        )
    }

    private func conceptRelationship(from record: KnowledgeRelationshipRecord) -> ConceptRelationship {
        ConceptRelationship(
            id: stableUUID(for: record.id),
            sourceConceptID: stableUUID(for: record.sourceConceptID),
            destinationConceptID: stableUUID(for: record.targetConceptID),
            type: relationshipType(from: record.relationType),
            confidence: record.confidence
        )
    }

    private func canonicalID(for concept: Concept) -> String {
        concept.embeddingID ?? concept.id.uuidString
    }

    private func relationshipType(from relationType: String) -> ConceptRelationshipType {
        switch relationType {
        case KnowledgeRelationshipKind.requires.rawValue:
            return .prerequisite
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

    private func stableUUID(for value: String) -> UUID {
        if let uuid = UUID(uuidString: value) {
            return uuid
        }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let suffix = String(format: "%012llx", hash & 0x0000ffffffffffff)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)") ?? UUID()
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}
