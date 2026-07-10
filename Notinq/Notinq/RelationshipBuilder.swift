import Foundation

enum RelationshipBuilder {
    static func normalizedKey(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func aliasMatch(_ lhs: ConceptRegistryEntry, candidateName: String, candidateAliases: [String]) -> Bool {
        let normalizedCandidate = normalizedKey(for: candidateName)
        guard !normalizedCandidate.isEmpty else { return false }

        if normalizedKey(for: lhs.name) == normalizedCandidate {
            return true
        }

        if lhs.aliases.contains(where: { normalizedKey(for: $0) == normalizedCandidate }) {
            return true
        }

        if candidateAliases.contains(where: { normalizedKey(for: $0) == normalizedKey(for: lhs.name) }) {
            return true
        }

        return false
    }

    static func semanticSimilarityPlaceholder(lhs: String, rhs: String) -> Double {
        let left = normalizedKey(for: lhs)
        let right = normalizedKey(for: rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }

        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))
        let intersection = Double(leftTokens.intersection(rightTokens).count)
        let union = Double(max(leftTokens.union(rightTokens).count, 1))
        let tokenScore = intersection / union

        if left.contains(right) || right.contains(left) {
            return max(tokenScore, 0.82)
        }

        return tokenScore
    }

    static func relationshipCount(for conceptID: UUID, in relationships: [ConceptRelationship]) -> Int {
        relationships.reduce(into: 0) { result, relationship in
            if relationship.sourceConceptID == conceptID || relationship.destinationConceptID == conceptID {
                result += 1
            }
        }
    }

    static func relationshipKey(_ relationship: ConceptRelationship) -> String {
        "\(relationship.sourceConceptID.uuidString)-\(relationship.destinationConceptID.uuidString)-\(relationship.type.rawValue)"
    }

    static func isPrerequisiteRelation(_ type: ConceptRelationshipType) -> Bool {
        type == .prerequisite || type == .dependsOn
    }

    static func displayDistance(for text: String) -> Int {
        max(1, min(5, Int((1.0 - semanticSimilarityPlaceholder(lhs: text, rhs: text)) * 5.0)))
    }
}

