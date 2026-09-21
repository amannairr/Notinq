import Foundation

struct RetentionSnapshot: Equatable, Sendable {
    let conceptID: String
    let retention: Double
    let daysUntilReview: Int
    let urgency: Double
    let predictedForgettingDate: Date
}

nonisolated final class RetentionEngine {
    private let studentConceptService: StudentConceptService
    private let calendar: Calendar
    private let nowProvider: @Sendable () -> Date
    private let forgettingThreshold = 0.5

    init(
        studentConceptService: StudentConceptService = .shared,
        calendar: Calendar = .current,
        nowProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.studentConceptService = studentConceptService
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    func retentionScore(for record: StudentConceptRecord) -> Double {
        let mastery = clamp(record.masteryScore)
        let confidence = clamp(record.confidenceScore)
        let stability = stabilityDays(for: record)
        let days = daysSinceReview(for: record)
        let base = (mastery * 0.7) + (confidence * 0.3)
        return clamp(base * exp(-days / stability))
    }

    func daysUntilReview(for record: StudentConceptRecord) -> Int {
        let predicted = predictedForgettingDate(for: record)
        let start = calendar.startOfDay(for: nowProvider())
        let target = calendar.startOfDay(for: predicted)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    func reviewUrgency(for record: StudentConceptRecord) -> Double {
        let retention = retentionScore(for: record)
        let dueWeight = daysUntilReview(for: record) <= 0 ? 0.25 : 0
        return clamp((1.0 - retention) + dueWeight)
    }

    func predictedForgettingDate(for record: StudentConceptRecord) -> Date {
        let base = max(0.05, (clamp(record.masteryScore) * 0.7) + (clamp(record.confidenceScore) * 0.3))
        let stability = stabilityDays(for: record)
        let daysUntilThreshold = max(0, stability * log(base / forgettingThreshold))
        let anchor = record.lastReviewed ?? record.updatedAt
        return calendar.date(byAdding: .day, value: Int(daysUntilThreshold.rounded(.down)), to: anchor) ?? anchor
    }

    @discardableResult
    func updateRetentionAfterReview(
        conceptID: String,
        noteID: UUID,
        outcome: StudentKnowledgeReviewOutcome,
        source: StudentKnowledgeReviewSource,
        reviewedAt: Date = Date()
    ) throws -> StudentConceptRecord {
        try studentConceptService.updateMastery(
            conceptID: conceptID,
            noteID: noteID,
            outcome: outcome,
            source: source,
            reviewedAt: reviewedAt
        )
    }

    func snapshot(for record: StudentConceptRecord) -> RetentionSnapshot {
        RetentionSnapshot(
            conceptID: record.conceptID,
            retention: retentionScore(for: record),
            daysUntilReview: daysUntilReview(for: record),
            urgency: reviewUrgency(for: record),
            predictedForgettingDate: predictedForgettingDate(for: record)
        )
    }

    private func daysSinceReview(for record: StudentConceptRecord) -> Double {
        let anchor = record.lastReviewed ?? record.updatedAt
        return max(0, nowProvider().timeIntervalSince(anchor) / 86_400)
    }

    private func stabilityDays(for record: StudentConceptRecord) -> Double {
        let mastery = clamp(record.masteryScore)
        let confidence = clamp(record.confidenceScore)
        let reviewBonus = log(Double(max(1, record.reviewCount)) + 1.0) * 4.0
        let confidenceBonus = confidence * 8.0
        let masteryBonus = mastery * 10.0
        let mistakePenalty = min(8.0, Double(record.mistakeCount) * 1.5)
        return max(2.0, 5.0 + reviewBonus + confidenceBonus + masteryBonus - mistakePenalty)
    }

    private func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
