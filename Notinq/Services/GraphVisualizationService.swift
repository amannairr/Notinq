import Foundation

struct GraphVisualizationNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let aliases: [String]
    let description: String
}

struct GraphVisualizationEdge: Identifiable, Equatable, Sendable {
    let id: String
    let sourceID: String
    let targetID: String
    let relationshipType: String
    let confidence: Double
}

struct GraphVisualizationGraph: Equatable, Sendable {
    let nodes: [GraphVisualizationNode]
    let edges: [GraphVisualizationEdge]
}

final class GraphVisualizationService {
    private let repository: KnowledgeRepository
    private let maxRadius = 5

    init(repository: KnowledgeRepository = .shared) {
        self.repository = repository
    }

    func graphForConcept(_ conceptID: String) -> GraphVisualizationGraph {
        subgraphAroundConcept(conceptID, radius: 1)
    }

    func graphForTopic(_ topic: String) -> GraphVisualizationGraph {
        if let concept = resolveConcept(topic) {
            return subgraphAroundConcept(concept.id, radius: 2)
        }

        let hits = (try? repository.searchConcepts(query: topic, limit: 1)) ?? []
        guard let first = hits.first else {
            return GraphVisualizationGraph(nodes: [], edges: [])
        }
        return subgraphAroundConcept(first.conceptID, radius: 2)
    }

    func subgraphAroundConcept(_ conceptID: String, radius: Int) -> GraphVisualizationGraph {
        guard let root = resolveConcept(conceptID) else {
            return GraphVisualizationGraph(nodes: [], edges: [])
        }

        let boundedRadius = max(0, min(radius, maxRadius))
        var nodeIDs: Set<String> = [root.id]
        var edgesByID: [String: KnowledgeRelationshipRecord] = [:]
        var frontier: [(conceptID: String, depth: Int)] = [(root.id, 0)]

        while frontier.isEmpty == false {
            let current = frontier.removeFirst()
            guard current.depth < boundedRadius else { continue }

            let relationships = ((try? repository.relationships(containing: current.conceptID, limit: 128)) ?? [])
                .sorted(by: relationshipSort)
            for relationship in relationships {
                edgesByID[relationship.id] = relationship
                let candidates = [relationship.sourceConceptID, relationship.targetConceptID]
                for candidate in candidates where nodeIDs.insert(candidate).inserted {
                    frontier.append((candidate, current.depth + 1))
                }
            }
        }

        let nodes = nodeIDs
            .compactMap { try? repository.concept(for: $0) }
            .map { GraphVisualizationNode(id: $0.id, title: $0.canonicalName, aliases: $0.aliases, description: $0.description) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let edges = edgesByID.values
            .filter { nodeIDs.contains($0.sourceConceptID) && nodeIDs.contains($0.targetConceptID) }
            .sorted(by: relationshipSort)
            .map {
                GraphVisualizationEdge(
                    id: $0.id,
                    sourceID: $0.sourceConceptID,
                    targetID: $0.targetConceptID,
                    relationshipType: $0.relationType,
                    confidence: $0.confidence
                )
            }

        return GraphVisualizationGraph(nodes: nodes, edges: edges)
    }

    private func resolveConcept(_ concept: String) -> CanonicalConceptRecord? {
        if let record = try? repository.concept(for: concept) {
            return record
        }
        guard let canonical = try? repository.canonicalConcept(named: concept) else { return nil }
        return try? repository.concept(for: canonical.id)
    }

    private func relationshipSort(_ lhs: KnowledgeRelationshipRecord, _ rhs: KnowledgeRelationshipRecord) -> Bool {
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.relationType != rhs.relationType { return lhs.relationType < rhs.relationType }
        if lhs.sourceConceptID != rhs.sourceConceptID { return lhs.sourceConceptID < rhs.sourceConceptID }
        if lhs.targetConceptID != rhs.targetConceptID { return lhs.targetConceptID < rhs.targetConceptID }
        return lhs.id < rhs.id
    }
}
