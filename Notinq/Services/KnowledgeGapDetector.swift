import Foundation

final class KnowledgeGapDetector {
    private let repository: KnowledgeRepository

    init(repository: KnowledgeRepository = .shared) {
        self.repository = repository
    }

    func detectGaps(
        concepts: [Concept],
        relationships: [ConceptRelationship],
        mastery: [StudentConceptRecord]
    ) -> [KnowledgeGap] {
        let conceptsByID = Dictionary(concepts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let conceptsByName = Dictionary(concepts.map { (normalizedKey($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        let masteryByID = Dictionary(mastery.map { ($0.conceptID, $0.effectiveMasteryScore) }, uniquingKeysWith: max)
        let masteryByName = Dictionary(mastery.map { (normalizedKey($0.conceptID), $0.effectiveMasteryScore) }, uniquingKeysWith: max)
        var gapsByID: [UUID: KnowledgeGap] = [:]

        func masteryScore(for concept: Concept) -> Double {
            masteryByID[concept.id.uuidString] ?? masteryByName[normalizedKey(concept.name)] ?? 0.5
        }

        func recordGap(concept: Concept, reason: String, severity: Double, missingPrerequisites: [Concept] = []) {
            let existing = gapsByID[concept.id]
            let shouldPreferReason = existing?.reason == "Low mastery" && reason == "Weak prerequisite for mastered dependent concept"
            if existing == nil || severity > (existing?.severity ?? 0) || shouldPreferReason {
                gapsByID[concept.id] = KnowledgeGap(
                    concept: concept,
                    reason: reason,
                    severity: max(existing?.severity ?? 0, max(0, min(1, severity))),
                    missingPrerequisites: missingPrerequisites
                )
            }
        }

        for concept in concepts {
            let score = masteryScore(for: concept)
            if score < 0.5 {
                recordGap(
                    concept: concept,
                    reason: "Low mastery",
                    severity: 1.0 - score
                )
            }
        }

        for record in mastery where record.mistakeCount > 0 && record.effectiveMasteryScore < 0.65 {
            if let concept = UUID(uuidString: record.conceptID).flatMap({ conceptsByID[$0] }) ?? conceptsByName[normalizedKey(record.conceptID)] {
                recordGap(
                    concept: concept,
                    reason: "Frequently missed in review",
                    severity: min(1.0, 0.45 + Double(record.mistakeCount) * 0.12)
                )
            }
        }

        for relationship in relationships where isPrerequisiteRelationship(relationship) {
            guard
                let dependent = conceptsByID[relationship.sourceConceptID],
                let prerequisite = conceptsByID[relationship.destinationConceptID]
            else { continue }

            let dependentMastery = masteryScore(for: dependent)
            let prerequisiteMastery = masteryScore(for: prerequisite)
            if dependentMastery >= 0.8 && prerequisiteMastery < 0.5 {
                recordGap(
                    concept: prerequisite,
                    reason: "Weak prerequisite for mastered dependent concept",
                    severity: min(1.0, dependentMastery - prerequisiteMastery),
                    missingPrerequisites: [prerequisite]
                )
            }
        }

        return gapsByID.values.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.concept.name.localizedCaseInsensitiveCompare($1.concept.name) == .orderedAscending
        }
    }

    private func isPrerequisiteRelationship(_ relationship: ConceptRelationship) -> Bool {
        relationship.type == .prerequisite || relationship.type == .dependsOn
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}
