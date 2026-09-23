import Foundation

struct StudyPlanStep: Equatable, Sendable {
    let conceptID: String
    let conceptName: String
    let masteryScore: Double
    let graphDistance: Int
    let reason: String
}

struct DependencyReviewItem: Equatable, Sendable {
    let conceptID: String
    let conceptName: String
    let reason: String
}

struct GraphExamPreparationItem: Equatable, Sendable {
    let conceptID: String
    let conceptName: String
    let centrality: Int
    let downstreamCount: Int
    let prerequisiteCount: Int
}

struct GraphLearningPath: Equatable, Sendable {
    let beginner: [String]
    let intermediate: [String]
    let advanced: [String]
}

final class StudyPlanGenerator {
    private let repository: KnowledgeRepository
    private let explanations: GraphExplanationService
    private let maxDepth = 10

    init(
        repository: KnowledgeRepository = .shared,
        explanations: GraphExplanationService? = nil
    ) {
        self.repository = repository
        self.explanations = explanations ?? GraphExplanationService(repository: repository)
    }

    func prerequisiteStudyPlan(
        for concept: String,
        masteryScores: [String: Double] = [:]
    ) -> [StudyPlanStep] {
        guard let target = resolveConcept(concept) else { return [] }
        let prerequisiteNames = explanations.prerequisiteChain(for: target.canonicalName)
        let orderedNames = (prerequisiteNames + [target.canonicalName]).uniquedForGraphPlanning()

        return orderedNames.enumerated().compactMap { index, name in
            guard let record = resolveConcept(name) else { return nil }
            let mastery = masteryScore(for: record, masteryScores: masteryScores)
            return StudyPlanStep(
                conceptID: record.id,
                conceptName: record.canonicalName,
                masteryScore: mastery,
                graphDistance: max(0, orderedNames.count - index - 1),
                reason: mastery < 0.65
                    ? "Review this concept before moving downstream."
                    : "Use this concept to support downstream topics."
            )
        }
    }

    func reviewDependencies(
        for weakConcept: String,
        masteryScores: [String: Double] = [:]
    ) -> [DependencyReviewItem] {
        prerequisiteStudyPlan(for: weakConcept, masteryScores: masteryScores)
            .dropLast()
            .filter { $0.masteryScore < 0.75 }
            .map {
                DependencyReviewItem(
                    conceptID: $0.conceptID,
                    conceptName: $0.conceptName,
                    reason: "Review \($0.conceptName)"
                )
            }
    }

    func graphBasedExamPreparation(limit: Int = 12) -> [GraphExamPreparationItem] {
        let concepts = (try? repository.searchRecentConcepts(limit: max(limit * 4, 24))) ?? []
        return concepts.compactMap { searchRecord in
            guard let record = try? repository.concept(for: searchRecord.conceptID) else { return nil }
            let relationships = (try? repository.relationships(containing: record.id, limit: 256)) ?? []
            let downstream = (try? repository.descendants(of: record.id, depth: maxDepth, limit: 256)) ?? []
            let prerequisites = explanations.prerequisiteChain(for: record.canonicalName)
            return GraphExamPreparationItem(
                conceptID: record.id,
                conceptName: record.canonicalName,
                centrality: relationships.count,
                downstreamCount: downstream.count,
                prerequisiteCount: prerequisites.count
            )
        }
        .sorted {
            if $0.centrality != $1.centrality { return $0.centrality > $1.centrality }
            if $0.downstreamCount != $1.downstreamCount { return $0.downstreamCount > $1.downstreamCount }
            return $0.conceptName.localizedCaseInsensitiveCompare($1.conceptName) == .orderedAscending
        }
        .prefix(limit)
        .map { $0 }
    }

    func learningPath(for concept: String) -> GraphLearningPath {
        let plan = prerequisiteStudyPlan(for: concept)
        guard plan.isEmpty == false else {
            return GraphLearningPath(beginner: [], intermediate: [], advanced: [])
        }

        let names = plan.map(\.conceptName)
        let targetName = names.last.map { [$0] } ?? []
        let prerequisiteNames = Array(names.dropLast())
        let splitIndex = max(1, prerequisiteNames.count / 2)

        return GraphLearningPath(
            beginner: Array(prerequisiteNames.prefix(splitIndex)),
            intermediate: Array(prerequisiteNames.dropFirst(splitIndex)),
            advanced: targetName
        )
    }

    private func resolveConcept(_ concept: String) -> CanonicalConceptRecord? {
        if let record = try? repository.concept(for: concept) {
            return record
        }
        guard let canonical = try? repository.canonicalConcept(named: concept) else { return nil }
        return try? repository.concept(for: canonical.id)
    }

    private func masteryScore(for concept: CanonicalConceptRecord, masteryScores: [String: Double]) -> Double {
        masteryScores[concept.id]
            ?? masteryScores[concept.canonicalName]
            ?? masteryScores[concept.canonicalName.lowercased()]
            ?? 0.5
    }
}

private extension Array where Element == String {
    func uniquedForGraphPlanning() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
