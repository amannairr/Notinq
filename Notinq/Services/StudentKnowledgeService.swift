import Foundation

struct StudentKnowledgeSummary: Equatable, Sendable {
    var overallMastery: Double
    var retentionScore: Double
    var confidenceScore: Double
    var examReadiness: Double
    var conceptMastery: [String: Double]
    var topicMastery: [String: Double]
    var studyStreak: Int
    var weakTopics: [String]
    var strongTopics: [String]
}

struct KnowledgeGraphStatistics: Equatable, Sendable {
    var conceptCount: Int
    var relationshipCount: Int
    var connectedComponents: Int
    var averageDegree: Double
}

nonisolated final class StudentKnowledgeService {
    private let knowledgeRepository: KnowledgeRepository
    private let studentConceptService: StudentConceptService
    private let studyRepository: StudyRepository
    private let maxConceptScan: Int

    var conceptService: StudentConceptService {
        studentConceptService
    }

    init(
        knowledgeRepository: KnowledgeRepository = .shared,
        studentConceptService: StudentConceptService = .shared,
        studyRepository: StudyRepository = .shared,
        maxConceptScan: Int = 1_000
    ) {
        self.knowledgeRepository = knowledgeRepository
        self.studentConceptService = studentConceptService
        self.studyRepository = studyRepository
        self.maxConceptScan = max(100, min(maxConceptScan, 2_000))
    }

    func overallMastery() -> Double {
        average(masteryRecords(limit: maxConceptScan).map(\.effectiveMasteryScore))
    }

    func conceptMastery(limit: Int = 1_000) -> [String: Double] {
        var result: [String: Double] = [:]
        for record in masteryRecords(limit: limit) {
            let name = conceptName(for: record.conceptID) ?? record.conceptID
            result[name] = record.effectiveMasteryScore
        }
        return result
    }

    func topicMastery(limit: Int = 1_000) -> [String: Double] {
        conceptMastery(limit: limit)
    }

    func retentionScore() -> Double {
        let records = masteryRecords(limit: maxConceptScan)
        guard records.isEmpty == false else { return 0 }
        let retained = records.map { record -> Double in
            guard let lastReviewed = record.lastReviewed else { return record.effectiveMasteryScore * 0.65 }
            let days = max(0, Date().timeIntervalSince(lastReviewed) / 86_400)
            let recency = max(0.35, min(1.0, 1.0 - (days / 45.0)))
            return record.effectiveMasteryScore * recency
        }
        return average(retained)
    }

    func confidenceScore() -> Double {
        average(masteryRecords(limit: maxConceptScan).map(\.confidenceScore))
    }

    func examReadiness() -> Double {
        let mastery = overallMastery()
        let retention = retentionScore()
        let confidence = confidenceScore()
        let weakPenalty = min(0.25, Double(weakConcepts(limit: 20).count) * 0.0125)
        return clamp((mastery * 0.45) + (retention * 0.30) + (confidence * 0.25) - weakPenalty)
    }

    func studyStreak() -> Int {
        let events = recentReviewEvents(limit: 300)
        guard events.isEmpty == false else { return 0 }
        let calendar = Calendar.current
        let days = Set(events.map { calendar.startOfDay(for: $0.timestamp) })
        var currentDay = calendar.startOfDay(for: Date())
        var streak = 0
        while days.contains(currentDay) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: currentDay) else { break }
            currentDay = previous
        }
        return streak
    }

    func weakConcepts(limit: Int = 8) -> [String] {
        conceptNames(from: (try? studentConceptService.weakestConcepts(limit: limit)) ?? [])
    }

    func strongConcepts(limit: Int = 8) -> [String] {
        conceptNames(from: (try? studentConceptService.strongestConcepts(limit: limit)) ?? [])
    }

    func summary() -> StudentKnowledgeSummary {
        StudentKnowledgeSummary(
            overallMastery: overallMastery(),
            retentionScore: retentionScore(),
            confidenceScore: confidenceScore(),
            examReadiness: examReadiness(),
            conceptMastery: conceptMastery(limit: maxConceptScan),
            topicMastery: topicMastery(limit: maxConceptScan),
            studyStreak: studyStreak(),
            weakTopics: weakConcepts(limit: 8),
            strongTopics: strongConcepts(limit: 8)
        )
    }

    func graphStatistics() -> KnowledgeGraphStatistics {
        let concepts = ((try? knowledgeRepository.searchRecentConcepts(limit: maxConceptScan)) ?? [])
            .compactMap { try? knowledgeRepository.concept(for: $0.conceptID) }
        let conceptIDs = Set(concepts.map(\.id))
        var adjacency: [String: Set<String>] = Dictionary(uniqueKeysWithValues: conceptIDs.map { ($0, Set<String>()) })
        var relationships: [String: KnowledgeRelationshipRecord] = [:]

        for conceptID in conceptIDs {
            let touching = (try? knowledgeRepository.relationships(containing: conceptID, limit: 256)) ?? []
            for relationship in touching {
                relationships[relationship.id] = relationship
                if conceptIDs.contains(relationship.sourceConceptID), conceptIDs.contains(relationship.targetConceptID) {
                    adjacency[relationship.sourceConceptID, default: []].insert(relationship.targetConceptID)
                    adjacency[relationship.targetConceptID, default: []].insert(relationship.sourceConceptID)
                }
            }
        }

        let degreeTotal = adjacency.values.reduce(0) { $0 + $1.count }
        return KnowledgeGraphStatistics(
            conceptCount: concepts.count,
            relationshipCount: relationships.count,
            connectedComponents: connectedComponents(in: adjacency),
            averageDegree: concepts.isEmpty ? 0 : Double(degreeTotal) / Double(concepts.count)
        )
    }

    private func masteryRecords(limit: Int) -> [StudentConceptRecord] {
        let weak = (try? studentConceptService.weakestConcepts(limit: limit)) ?? []
        let strong = (try? studentConceptService.strongestConcepts(limit: limit)) ?? []
        let recent = (try? studentConceptService.recentlyReviewedConcepts(limit: limit)) ?? []
        var byID: [String: StudentConceptRecord] = [:]
        for record in weak + strong + recent {
            byID[record.conceptID] = record
        }
        return Array(byID.values)
    }

    private func recentReviewEvents(limit: Int) -> [ReviewEvent] {
        masteryRecords(limit: limit)
            .flatMap { record -> [ReviewEvent] in
                guard let noteID = noteID(for: record.conceptID) else { return [] }
                return (try? studyRepository.reviewEvents(for: noteID)) ?? []
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func conceptNames(from records: [StudentConceptRecord]) -> [String] {
        records.compactMap { conceptName(for: $0.conceptID) ?? $0.conceptID }
    }

    private func conceptName(for conceptID: String) -> String? {
        if let record = try? knowledgeRepository.concept(for: conceptID) {
            return record.canonicalName
        }
        if let canonical = try? knowledgeRepository.canonicalConcept(named: conceptID) {
            return canonical.canonicalName
        }
        return nil
    }

    private func noteID(for conceptID: String) -> UUID? {
        guard let concept = try? knowledgeRepository.concept(for: conceptID) else { return nil }
        return concept.sourceReferences.compactMap(UUID.init(uuidString:)).first
    }

    private func connectedComponents(in adjacency: [String: Set<String>]) -> Int {
        var visited: Set<String> = []
        var count = 0
        for node in adjacency.keys.sorted() where visited.contains(node) == false {
            count += 1
            var queue = [node]
            visited.insert(node)
            while queue.isEmpty == false {
                let current = queue.removeFirst()
                for next in adjacency[current, default: []] where visited.insert(next).inserted {
                    queue.append(next)
                }
            }
        }
        return count
    }

    private func average(_ values: [Double]) -> Double {
        guard values.isEmpty == false else { return 0 }
        return clamp(values.reduce(0, +) / Double(values.count))
    }

    private func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
