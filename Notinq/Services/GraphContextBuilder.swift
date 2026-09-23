import Foundation

struct GraphContext: Codable, Equatable, Sendable {
    var concepts: [CanonicalConceptRecord]
    var relationships: [KnowledgeRelationshipRecord]
    var prerequisiteChains: [[String]]
    var paths: [GraphPath]
    var explanations: [ConceptExplanation]

    static let empty = GraphContext(
        concepts: [],
        relationships: [],
        prerequisiteChains: [],
        paths: [],
        explanations: []
    )

    var isEmpty: Bool {
        concepts.isEmpty && relationships.isEmpty && prerequisiteChains.isEmpty && paths.isEmpty && explanations.isEmpty
    }

    func graphPromptRepresentation(maxRelationships: Int = 24, maxChains: Int = 8, maxPaths: Int = 8) -> String {
        guard isEmpty == false else { return "" }

        let nameByID = Dictionary(concepts.map { ($0.id, $0.canonicalName) }, uniquingKeysWith: { first, _ in first })
        var lines: [String] = ["Knowledge Graph"]

        let grouped = Dictionary(grouping: relationships.prefix(maxRelationships), by: \.sourceConceptID)
        for concept in concepts {
            guard let outgoing = grouped[concept.id], outgoing.isEmpty == false else { continue }
            lines.append("")
            lines.append(concept.canonicalName)
            for relationship in outgoing.sorted(by: relationshipSort) {
                let target = nameByID[relationship.targetConceptID] ?? relationship.targetConceptID
                lines.append("  \(relationship.relationType.uppercased()) -> \(target)")
            }
        }

        let chains = prerequisiteChains
            .filter { $0.count > 1 }
            .prefix(maxChains)
        if chains.isEmpty == false {
            lines.append("")
            lines.append("Prerequisite Chains")
            for chain in chains {
                lines.append(chain.joined(separator: " -> "))
            }
        }

        let renderedPaths = paths
            .filter { $0.nodes.count > 1 }
            .prefix(maxPaths)
        if renderedPaths.isEmpty == false {
            lines.append("")
            lines.append("Shortest Paths")
            for path in renderedPaths {
                lines.append(renderPath(path))
            }
        }

        let explanationLines = explanations.prefix(8).map { explanation -> String in
            let prerequisites = explanation.prerequisites.isEmpty ? "none" : explanation.prerequisites.joined(separator: ", ")
            let dependents = explanation.dependents.isEmpty ? "none" : explanation.dependents.joined(separator: ", ")
            return "\(explanation.conceptName): prerequisites [\(prerequisites)]; dependents [\(dependents)]"
        }
        if explanationLines.isEmpty == false {
            lines.append("")
            lines.append("Concept Explanations")
            lines.append(contentsOf: explanationLines)
        }

        return lines.joined(separator: "\n")
    }

    private func renderPath(_ path: GraphPath) -> String {
        guard let first = path.nodes.first else { return "" }
        var parts: [String] = [first.canonicalName]
        for (index, relationship) in path.relationships.enumerated() {
            guard index + 1 < path.nodes.count else { continue }
            let next = path.nodes[index + 1]
            let arrow = relationship.sourceConceptID == path.nodes[index].id ? "->" : "<-"
            parts.append("\(relationship.relationType.uppercased()) \(arrow) \(next.canonicalName)")
        }
        return parts.joined(separator: " ")
    }

    private func relationshipSort(_ lhs: KnowledgeRelationshipRecord, _ rhs: KnowledgeRelationshipRecord) -> Bool {
        if lhs.sourceConceptID != rhs.sourceConceptID { return lhs.sourceConceptID < rhs.sourceConceptID }
        if lhs.relationType != rhs.relationType { return lhs.relationType < rhs.relationType }
        if lhs.targetConceptID != rhs.targetConceptID { return lhs.targetConceptID < rhs.targetConceptID }
        return lhs.id < rhs.id
    }
}

final class GraphContextBuilder {
    private let repository: KnowledgeRepository
    private let explanations: GraphExplanationService

    init(
        repository: KnowledgeRepository = .shared,
        explanations: GraphExplanationService? = nil
    ) {
        self.repository = repository
        self.explanations = explanations ?? GraphExplanationService(repository: repository)
    }

    func buildContext(
        query: String,
        maxConcepts: Int = 20
    ) -> GraphContext {
        let boundedLimit = max(1, min(maxConcepts, 64))
        let seeds = seedConcepts(for: query, limit: boundedLimit)
        guard seeds.isEmpty == false else { return .empty }

        var conceptByID: [String: CanonicalConceptRecord] = [:]
        var relationshipsByID: [String: KnowledgeRelationshipRecord] = [:]
        var prerequisiteChains: [[String]] = []
        var paths: [GraphPath] = []
        var explanationByName: [String: ConceptExplanation] = [:]

        func add(_ concept: CanonicalConceptRecord) {
            conceptByID[concept.id] = concept
        }

        for seed in seeds {
            add(seed)
            let explanation = explanations.explainConcept(seed.canonicalName)
            explanationByName[normalizedKey(explanation.conceptName)] = explanation

            let prerequisiteChain = explanations.prerequisiteChain(for: seed.canonicalName) + [seed.canonicalName]
            if prerequisiteChain.count > 1 {
                prerequisiteChains.append(prerequisiteChain)
            }

            let expanded = (
                ((try? repository.neighbors(of: seed.id, limit: 8)) ?? []) +
                ((try? repository.ancestors(of: seed.id, depth: 3, limit: 8)) ?? []) +
                ((try? repository.descendants(of: seed.id, depth: 3, limit: 8)) ?? [])
            )
            for concept in expanded.prefix(boundedLimit) {
                add(concept)
            }

            for relationship in ((try? repository.relationships(containing: seed.id, limit: 32)) ?? []) {
                relationshipsByID[relationship.id] = relationship
                if let source = try? repository.concept(for: relationship.sourceConceptID) {
                    add(source)
                }
                if let target = try? repository.concept(for: relationship.targetConceptID) {
                    add(target)
                }
            }
        }

        let concepts = conceptByID.values
            .sorted { $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending }
            .prefix(boundedLimit)
            .map { $0 }

        for concept in concepts {
            let explanation = explanations.explainConcept(concept.canonicalName)
            explanationByName[normalizedKey(explanation.conceptName)] = explanation
            for relationship in explanation.incomingRelationships + explanation.outgoingRelationships {
                relationshipsByID[relationship.id] = relationship
            }
        }

        let selectedConcepts = Array(concepts.prefix(8))
        for source in selectedConcepts {
            for target in selectedConcepts where source.id < target.id {
                if let path = explanations.findPath(from: source.canonicalName, to: target.canonicalName),
                   path.nodes.count > 1 {
                    paths.append(path)
                    for relationship in path.relationships {
                        relationshipsByID[relationship.id] = relationship
                    }
                }
            }
        }

        return GraphContext(
            concepts: concepts,
            relationships: relationshipsByID.values.sorted(by: relationshipSort),
            prerequisiteChains: dedupeChains(prerequisiteChains),
            paths: dedupePaths(paths),
            explanations: explanationByName.values.sorted {
                $0.conceptName.localizedCaseInsensitiveCompare($1.conceptName) == .orderedAscending
            }
        )
    }

    private func seedConcepts(for query: String, limit: Int) -> [CanonicalConceptRecord] {
        let terms = candidateTerms(from: query)
        var records: [CanonicalConceptRecord] = []
        var seen: Set<String> = []

        for term in terms {
            if let canonical = try? repository.canonicalConcept(named: term),
               let record = try? repository.concept(for: canonical.id),
               seen.insert(record.id).inserted {
                records.append(record)
            }
        }

        let searchRecords = ((try? repository.searchConcepts(query: query, limit: limit)) ?? [])
        for searchRecord in searchRecords {
            guard let record = try? repository.concept(for: searchRecord.conceptID),
                  seen.insert(record.id).inserted else { continue }
            records.append(record)
        }

        if records.isEmpty {
            for searchRecord in ((try? repository.searchRecentConcepts(limit: limit)) ?? []) {
                guard let record = try? repository.concept(for: searchRecord.conceptID),
                      seen.insert(record.id).inserted else { continue }
                records.append(record)
            }
        }

        return Array(records.prefix(limit))
    }

    private func candidateTerms(from query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        var terms: [String] = [trimmed]
        let separators = CharacterSet(charactersIn: "\n,.?!:;()[]{}")
        terms.append(contentsOf: trimmed.components(separatedBy: separators).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        terms.append(contentsOf: trimmed.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 2 })
        return terms.filter { $0.isEmpty == false }.dedupedByNormalizedKey()
    }

    private func relationshipSort(_ lhs: KnowledgeRelationshipRecord, _ rhs: KnowledgeRelationshipRecord) -> Bool {
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.sourceConceptID != rhs.sourceConceptID { return lhs.sourceConceptID < rhs.sourceConceptID }
        if lhs.relationType != rhs.relationType { return lhs.relationType < rhs.relationType }
        if lhs.targetConceptID != rhs.targetConceptID { return lhs.targetConceptID < rhs.targetConceptID }
        return lhs.id < rhs.id
    }

    private func dedupeChains(_ chains: [[String]]) -> [[String]] {
        var seen: Set<String> = []
        return chains.filter { chain in
            seen.insert(chain.map(normalizedKey).joined(separator: "->")).inserted
        }
    }

    private func dedupePaths(_ paths: [GraphPath]) -> [GraphPath] {
        var seen: Set<String> = []
        return paths.filter { path in
            let key = path.nodes.map(\.id).joined(separator: "->")
            return seen.insert(key).inserted
        }
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}

private extension Array where Element == String {
    func dedupedByNormalizedKey() -> [String] {
        var seen: Set<String> = []
        return filter { value in
            let key = value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.isEmpty == false }
                .joined(separator: " ")
            return seen.insert(key).inserted
        }
    }
}
