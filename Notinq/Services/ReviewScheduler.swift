import Foundation

struct ScheduledReview: Identifiable, Equatable, Sendable {
    var id: String { conceptID }
    let conceptID: String
    let conceptName: String
    let retention: Double
    let urgency: Double
    let dueDate: Date
    let daysUntilDue: Int

    var statusText: String {
        if daysUntilDue < 0 { return "Overdue \(abs(daysUntilDue)) days" }
        if daysUntilDue == 0 { return "Due today" }
        if daysUntilDue == 1 { return "Tomorrow" }
        return "Due in \(daysUntilDue) days"
    }

    var riskText: String {
        if retention < 0.35 { return "High Risk" }
        if retention < 0.65 { return "Medium Risk" }
        return "Low Risk"
    }
}

nonisolated final class ReviewScheduler {
    private let studentConceptService: StudentConceptService
    private let knowledgeRepository: KnowledgeRepository
    private let retentionEngine: RetentionEngine
    private let calendar: Calendar
    private let nowProvider: @Sendable () -> Date

    init(
        studentConceptService: StudentConceptService = .shared,
        knowledgeRepository: KnowledgeRepository = .shared,
        retentionEngine: RetentionEngine? = nil,
        calendar: Calendar = .current,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.studentConceptService = studentConceptService
        self.knowledgeRepository = knowledgeRepository
        self.retentionEngine = retentionEngine ?? RetentionEngine(
            studentConceptService: studentConceptService,
            calendar: calendar,
            nowProvider: nowProvider
        )
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    func dueToday(limit: Int = 12) -> [ScheduledReview] {
        scheduledReviews(limit: max(limit * 3, limit))
            .filter { $0.daysUntilDue == 0 }
            .prefix(limit)
            .map { $0 }
    }

    func dueThisWeek(limit: Int = 24) -> [ScheduledReview] {
        scheduledReviews(limit: max(limit * 3, limit))
            .filter { $0.daysUntilDue >= 0 && $0.daysUntilDue <= 7 }
            .prefix(limit)
            .map { $0 }
    }

    func overdue(limit: Int = 12) -> [ScheduledReview] {
        scheduledReviews(limit: max(limit * 3, limit))
            .filter { $0.daysUntilDue < 0 }
            .prefix(limit)
            .map { $0 }
    }

    func scheduleNextReview(for record: StudentConceptRecord) -> Date {
        retentionEngine.predictedForgettingDate(for: record)
    }

    func scheduledReviews(limit: Int = 32) -> [ScheduledReview] {
        masteryRecords(limit: max(limit, 32)).compactMap { record in
            let dueDate = scheduleNextReview(for: record)
            let start = calendar.startOfDay(for: nowProvider())
            let dueDay = calendar.startOfDay(for: dueDate)
            let daysUntilDue = calendar.dateComponents([.day], from: start, to: dueDay).day ?? 0
            return ScheduledReview(
                conceptID: record.conceptID,
                conceptName: conceptName(for: record.conceptID) ?? record.conceptID,
                retention: retentionEngine.retentionScore(for: record),
                urgency: retentionEngine.reviewUrgency(for: record),
                dueDate: dueDate,
                daysUntilDue: daysUntilDue
            )
        }
        .sorted(by: reviewSort)
        .prefix(limit)
        .map { $0 }
    }

    private func masteryRecords(limit: Int) -> [StudentConceptRecord] {
        let due = (try? studentConceptService.conceptsNeedingReview(limit: limit)) ?? []
        let weak = (try? studentConceptService.weakestConcepts(limit: limit)) ?? []
        let recent = (try? studentConceptService.recentlyReviewedConcepts(limit: limit)) ?? []
        var recordsByID: [String: StudentConceptRecord] = [:]
        for record in due + weak + recent {
            recordsByID[record.conceptID] = record
        }
        return Array(recordsByID.values)
            .sorted(by: masteryRecordReviewSort)
            .prefix(limit)
            .map { $0 }
    }

    private func masteryRecordReviewSort(_ lhs: StudentConceptRecord, _ rhs: StudentConceptRecord) -> Bool {
        let lhsDays = retentionEngine.daysUntilReview(for: lhs)
        let rhsDays = retentionEngine.daysUntilReview(for: rhs)
        if lhsDays != rhsDays {
            return lhsDays < rhsDays
        }

        let lhsUrgency = retentionEngine.reviewUrgency(for: lhs)
        let rhsUrgency = retentionEngine.reviewUrgency(for: rhs)
        if lhsUrgency != rhsUrgency {
            return lhsUrgency > rhsUrgency
        }

        return lhs.conceptID.localizedCaseInsensitiveCompare(rhs.conceptID) == .orderedAscending
    }

    private func conceptName(for conceptID: String) -> String? {
        if let concept = try? knowledgeRepository.concept(for: conceptID) {
            return concept.canonicalName
        }
        if let canonical = try? knowledgeRepository.canonicalConcept(named: conceptID) {
            return canonical.canonicalName
        }
        return nil
    }

    private func reviewSort(_ lhs: ScheduledReview, _ rhs: ScheduledReview) -> Bool {
        if lhs.daysUntilDue != rhs.daysUntilDue {
            return lhs.daysUntilDue < rhs.daysUntilDue
        }
        if lhs.urgency != rhs.urgency {
            return lhs.urgency > rhs.urgency
        }
        return lhs.conceptName.localizedCaseInsensitiveCompare(rhs.conceptName) == .orderedAscending
    }
}
