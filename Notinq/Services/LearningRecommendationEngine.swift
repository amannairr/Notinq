import Foundation

struct LearningGapVisualizationItem: Identifiable, Equatable, Sendable {
    var id: String { weakConcept }
    let weakConcept: String
    let blockedTopics: [String]
}

nonisolated final class LearningRecommendationEngine {
    private let repository: KnowledgeRepository
    private let studentConceptService: StudentConceptService
    private let studyPlanGenerator: StudyPlanGenerator
    private let maxItems: Int

    init(
        repository: KnowledgeRepository = .shared,
        studentConceptService: StudentConceptService = .shared,
        studyPlanGenerator: StudyPlanGenerator? = nil,
        maxItems: Int = 12
    ) {
        self.repository = repository
        self.studentConceptService = studentConceptService
        self.studyPlanGenerator = studyPlanGenerator ?? StudyPlanGenerator(repository: repository)
        self.maxItems = max(1, min(maxItems, 32))
    }

    func recommendedReviews(limit: Int = 8) -> [String] {
        let boundedLimit = bounded(limit)
        let reviewRecords = (try? studentConceptService.conceptsNeedingReview(limit: boundedLimit)) ?? []
        return conceptNames(for: reviewRecords).prefix(boundedLimit).map { $0 }
    }

    func recommendedPrerequisites(for concept: String, masteryScores: [String: Double] = [:], limit: Int = 8) -> [String] {
        studyPlanGenerator.reviewDependencies(for: concept, masteryScores: masteryScores)
            .prefix(bounded(limit))
            .map(\.conceptName)
    }

    func recommendedNextTopics(limit: Int = 8) -> [String] {
        let boundedLimit = bounded(limit)
        let strongRecords = (try? studentConceptService.strongestConcepts(limit: boundedLimit)) ?? []
        var topics: [String] = []
        var seen: Set<String> = []

        for record in strongRecords {
            guard let concept = conceptRecord(for: record.conceptID) else { continue }
            let dependents = (try? repository.ancestors(of: concept.id, depth: 2, limit: boundedLimit)) ?? []
            for dependent in dependents where seen.insert(dependent.id).inserted {
                topics.append(dependent.canonicalName)
                if topics.count >= boundedLimit { return topics }
            }
        }

        return topics
    }

    func recommendedWeakAreas(limit: Int = 8) -> [String] {
        let boundedLimit = bounded(limit)
        let weakRecords = (try? studentConceptService.weakestConcepts(limit: boundedLimit)) ?? []
        return conceptNames(for: weakRecords).prefix(boundedLimit).map { $0 }
    }

    func learningGaps(limit: Int = 6, blockedTopicLimit: Int = 6) -> [LearningGapVisualizationItem] {
        let boundedLimit = bounded(limit)
        let weakRecords = (try? studentConceptService.weakestConcepts(limit: boundedLimit)) ?? []
        return weakRecords.compactMap { record in
            guard let concept = conceptRecord(for: record.conceptID) else { return nil }
            let blocked = blockedTopics(for: concept, limit: blockedTopicLimit)
            guard blocked.isEmpty == false else { return nil }
            return LearningGapVisualizationItem(weakConcept: concept.canonicalName, blockedTopics: blocked)
        }
    }

    func importantConcepts(limit: Int = 8) -> [GraphExamPreparationItem] {
        studyPlanGenerator.graphBasedExamPreparation(limit: bounded(limit))
    }

    private func blockedTopics(for concept: CanonicalConceptRecord, limit: Int) -> [String] {
        let boundedLimit = bounded(limit)
        let dependents = (try? repository.ancestors(of: concept.id, depth: 4, limit: boundedLimit)) ?? []
        return dependents
            .map(\.canonicalName)
            .filter { $0.localizedCaseInsensitiveCompare(concept.canonicalName) != .orderedSame }
            .prefix(boundedLimit)
            .map { $0 }
    }

    private func conceptNames(for records: [StudentConceptRecord]) -> [String] {
        records.compactMap { conceptRecord(for: $0.conceptID)?.canonicalName }
    }

    private func conceptRecord(for identifier: String) -> CanonicalConceptRecord? {
        if let concept = try? repository.concept(for: identifier) {
            return concept
        }
        guard let canonical = try? repository.canonicalConcept(named: identifier) else { return nil }
        return try? repository.concept(for: canonical.id)
    }

    private func bounded(_ limit: Int) -> Int {
        max(1, min(limit, maxItems))
    }
}
