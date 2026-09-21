import Foundation

struct GraphPath: Codable, Equatable, Sendable {
    let nodes: [CanonicalConceptRecord]
    let relationships: [KnowledgeRelationshipRecord]
}

struct ConceptExplanation: Codable, Equatable, Sendable {
    let conceptName: String
    let aliases: [String]
    let prerequisites: [String]
    let dependents: [String]
    let relatedConcepts: [String]
    let incomingRelationships: [KnowledgeRelationshipRecord]
    let outgoingRelationships: [KnowledgeRelationshipRecord]
}

final class GraphExplanationService {
    private let repository: KnowledgeRepository
    private let maxPathDepth = 10
    private let relationshipLimit = 128

    init(repository: KnowledgeRepository = .shared) {
        self.repository = repository
    }

    func findPath(from source: String, to target: String) -> GraphPath? {
        guard
            let sourceConcept = resolveConcept(source),
            let targetConcept = resolveConcept(target)
        else { return nil }

        if sourceConcept.id == targetConcept.id {
            return GraphPath(nodes: [sourceConcept], relationships: [])
        }

        var frontier: [(conceptID: String, nodeIDs: [String], relationships: [KnowledgeRelationshipRecord])] = [
            (sourceConcept.id, [sourceConcept.id], [])
        ]
        var visited: Set<String> = [sourceConcept.id]

        while frontier.isEmpty == false {
            let current = frontier.removeFirst()
            guard current.relationships.count < maxPathDepth else { continue }

            for relationship in relationshipsTouching(current.conceptID) {
                guard let nextID = nextConceptID(from: current.conceptID, relationship: relationship) else { continue }
                guard visited.insert(nextID).inserted else { continue }

                let nextNodeIDs = current.nodeIDs + [nextID]
                let nextRelationships = current.relationships + [relationship]

                if nextID == targetConcept.id {
                    let nodes = nextNodeIDs.compactMap { conceptRecord(for: $0) }
                    guard nodes.count == nextNodeIDs.count else { return nil }
                    return GraphPath(nodes: nodes, relationships: nextRelationships)
                }

                frontier.append((nextID, nextNodeIDs, nextRelationships))
            }
        }

        return nil
    }

    func explainConcept(_ concept: String) -> ConceptExplanation {
        guard let resolvedConcept = resolveConcept(concept) else {
            return ConceptExplanation(
                conceptName: concept,
                aliases: [],
                prerequisites: [],
                dependents: [],
                relatedConcepts: [],
                incomingRelationships: [],
                outgoingRelationships: []
            )
        }

        let relationships = relationshipsTouching(resolvedConcept.id)
        let incoming = relationships
            .filter { $0.targetConceptID == resolvedConcept.id }
            .sorted(by: relationshipSort)
        let outgoing = relationships
            .filter { $0.sourceConceptID == resolvedConcept.id }
            .sorted(by: relationshipSort)

        let prerequisites = outgoing
            .filter(isPrerequisiteRelationship)
            .compactMap { conceptRecord(for: $0.targetConceptID)?.canonicalName }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let dependents = incoming
            .filter(isPrerequisiteRelationship)
            .compactMap { conceptRecord(for: $0.sourceConceptID)?.canonicalName }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let relatedConcepts = relationships
            .compactMap { relationship -> String? in
                nextConceptID(from: resolvedConcept.id, relationship: relationship)
                    .flatMap { conceptRecord(for: $0)?.canonicalName }
            }
            .uniqued()
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        return ConceptExplanation(
            conceptName: resolvedConcept.canonicalName,
            aliases: resolvedConcept.aliases.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
            prerequisites: prerequisites,
            dependents: dependents,
            relatedConcepts: relatedConcepts,
            incomingRelationships: incoming,
            outgoingRelationships: outgoing
        )
    }

    func prerequisiteChain(for concept: String) -> [String] {
        guard let resolvedConcept = resolveConcept(concept) else { return [] }

        var ordered: [String] = []
        var visited: Set<String> = []
        var visiting: Set<String> = []

        func visit(_ conceptID: String) {
            guard visited.contains(conceptID) == false, visiting.contains(conceptID) == false else { return }
            visiting.insert(conceptID)

            let prerequisiteIDs = relationshipsTouching(conceptID)
                .filter { $0.sourceConceptID == conceptID && isPrerequisiteRelationship($0) }
                .compactMap { conceptRecord(for: $0.targetConceptID) }
                .sorted { $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending }
                .map(\.id)

            for prerequisiteID in prerequisiteIDs {
                visit(prerequisiteID)
            }

            visiting.remove(conceptID)
            visited.insert(conceptID)

            if conceptID != resolvedConcept.id, let concept = conceptRecord(for: conceptID) {
                ordered.append(concept.canonicalName)
            }
        }

        visit(resolvedConcept.id)
        return ordered
    }

    func descendants(of concept: String) -> [String] {
        guard let resolvedConcept = resolveConcept(concept) else { return [] }

        var result: [String] = []
        var visited: Set<String> = [resolvedConcept.id]
        var frontier: [(conceptID: String, depth: Int)] = [(resolvedConcept.id, 0)]

        while frontier.isEmpty == false {
            let current = frontier.removeFirst()
            guard current.depth < maxPathDepth else { continue }

            let outgoing = relationshipsTouching(current.conceptID)
                .filter { $0.sourceConceptID == current.conceptID }

            for relationship in outgoing {
                let nextID = relationship.targetConceptID
                guard visited.insert(nextID).inserted else { continue }
                guard let nextConcept = conceptRecord(for: nextID) else { continue }

                result.append(nextConcept.canonicalName)
                frontier.append((nextID, current.depth + 1))
            }
        }

        return result.uniqued()
    }

    private func resolveConcept(_ name: String) -> CanonicalConceptRecord? {
        guard let canonicalConcept = try? repository.canonicalConcept(named: name),
              let record = conceptRecord(for: canonicalConcept.id)
        else { return nil }
        return record
    }

    private func conceptRecord(for conceptID: String) -> CanonicalConceptRecord? {
        try? repository.concept(for: conceptID)
    }

    private func relationshipsTouching(_ conceptID: String) -> [KnowledgeRelationshipRecord] {
        ((try? repository.relationships(containing: conceptID, limit: relationshipLimit)) ?? [])
            .sorted(by: relationshipSort)
    }

    private func nextConceptID(from conceptID: String, relationship: KnowledgeRelationshipRecord) -> String? {
        if relationship.sourceConceptID == conceptID { return relationship.targetConceptID }
        if relationship.targetConceptID == conceptID { return relationship.sourceConceptID }
        return nil
    }

    private func isPrerequisiteRelationship(_ relationship: KnowledgeRelationshipRecord) -> Bool {
        let relation = relationship.relationType.lowercased()
        return relationship.relationType == KnowledgeRelationshipKind.requires.rawValue
            || relation.contains("require")
            || relation.contains("depend")
            || relation.contains("prereq")
    }

    private func relationshipSort(_ lhs: KnowledgeRelationshipRecord, _ rhs: KnowledgeRelationshipRecord) -> Bool {
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.relationType != rhs.relationType { return lhs.relationType < rhs.relationType }
        if lhs.sourceConceptID != rhs.sourceConceptID { return lhs.sourceConceptID < rhs.sourceConceptID }
        if lhs.targetConceptID != rhs.targetConceptID { return lhs.targetConceptID < rhs.targetConceptID }
        return lhs.id < rhs.id
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}
