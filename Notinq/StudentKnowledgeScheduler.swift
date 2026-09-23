import Foundation

protocol StudentKnowledgeScheduling {
    func schedule(record: StudentKnowledgeConceptRecord, outcome: StudentKnowledgeReviewOutcome, reviewedAt: Date) -> StudentKnowledgeConceptRecord
}

struct StudentKnowledgeSchedulerConfiguration: Sendable {
    var learningInterval: TimeInterval = 60 * 30
    var reviewInterval: TimeInterval = 60 * 60 * 24 * 2
    var relearningInterval: TimeInterval = 60 * 60 * 3
    var forgottenInterval: TimeInterval = 60 * 20
    var maximumEaseFactor: Double = 3.1
    var minimumEaseFactor: Double = 1.3
}

struct DefaultStudentKnowledgeScheduler: StudentKnowledgeScheduling {
    var configuration = StudentKnowledgeSchedulerConfiguration()

    func schedule(record: StudentKnowledgeConceptRecord, outcome: StudentKnowledgeReviewOutcome, reviewedAt: Date) -> StudentKnowledgeConceptRecord {
        var updated = record
        let priorReviewCount = max(updated.reviewCount, 0)

        updated.reviewCount += 1
        updated.lastReviewedAt = reviewedAt
        updated.updatedAt = reviewedAt
        updated.isArchived = false
        updated.archivedAt = nil
        updated.familiarity = clamp(updated.familiarity + familiarityDelta(for: outcome, priorReviewCount: priorReviewCount), lower: 0, upper: 1)
        updated.confidence = clamp(updated.confidence + confidenceDelta(for: outcome), lower: 0, upper: 1)

        switch outcome {
        case .easy:
            updated.correctAnswerCount += 1
            updated.streak += 1
            updated.masteryLevel = clamp(updated.masteryLevel + 0.14, lower: 0, upper: 1)
            updated.easeFactor = clamp(updated.easeFactor + 0.12, lower: configuration.minimumEaseFactor, upper: configuration.maximumEaseFactor)
            updated.learningStatus = priorReviewCount == 0 ? .firstLearning : .review
            updated.nextReviewDate = reviewedAt.addingTimeInterval(configuration.reviewInterval * max(1, Double(updated.streak + 1)))
        case .correct:
            updated.correctAnswerCount += 1
            updated.streak += 1
            updated.masteryLevel = clamp(updated.masteryLevel + 0.08, lower: 0, upper: 1)
            updated.easeFactor = clamp(updated.easeFactor + 0.04, lower: configuration.minimumEaseFactor, upper: configuration.maximumEaseFactor)
            updated.learningStatus = priorReviewCount == 0 ? .firstLearning : .review
            updated.nextReviewDate = reviewedAt.addingTimeInterval(priorReviewCount == 0 ? configuration.learningInterval : configuration.reviewInterval)
        case .hard:
            updated.correctAnswerCount += 1
            updated.streak = 0
            updated.masteryLevel = clamp(updated.masteryLevel + 0.02, lower: 0, upper: 1)
            updated.easeFactor = clamp(updated.easeFactor - 0.08, lower: configuration.minimumEaseFactor, upper: configuration.maximumEaseFactor)
            updated.learningStatus = priorReviewCount == 0 ? .firstLearning : .relearning
            updated.nextReviewDate = reviewedAt.addingTimeInterval(configuration.relearningInterval)
        case .partial:
            updated.correctAnswerCount += 1
            updated.streak = 0
            updated.masteryLevel = clamp(updated.masteryLevel + 0.03, lower: 0, upper: 1)
            updated.easeFactor = clamp(updated.easeFactor - 0.02, lower: configuration.minimumEaseFactor, upper: configuration.maximumEaseFactor)
            updated.learningStatus = priorReviewCount == 0 ? .firstLearning : .review
            updated.nextReviewDate = reviewedAt.addingTimeInterval(configuration.learningInterval)
        case .incorrect:
            updated.incorrectAnswerCount += 1
            updated.streak = 0
            updated.masteryLevel = clamp(updated.masteryLevel - 0.12, lower: 0, upper: 1)
            updated.easeFactor = clamp(updated.easeFactor - 0.18, lower: configuration.minimumEaseFactor, upper: configuration.maximumEaseFactor)
            updated.learningStatus = .forgotten
            updated.nextReviewDate = reviewedAt.addingTimeInterval(configuration.forgottenInterval)
        }

        updated.reviewHistory.insert(
            StudentKnowledgeReviewEvent(
                reviewedAt: reviewedAt,
                outcome: outcome,
                source: .manual,
                noteID: nil,
                graphConceptID: updated.graphConceptIDs.first,
                score: nil,
                wasCorrect: outcome != .incorrect
            ),
            at: 0
        )
        return updated
    }

    private func familiarityDelta(for outcome: StudentKnowledgeReviewOutcome, priorReviewCount: Int) -> Double {
        switch outcome {
        case .easy:
            return priorReviewCount == 0 ? 0.28 : 0.16
        case .correct:
            return priorReviewCount == 0 ? 0.18 : 0.1
        case .hard:
            return 0.04
        case .partial:
            return 0.02
        case .incorrect:
            return -0.12
        }
    }

    private func confidenceDelta(for outcome: StudentKnowledgeReviewOutcome) -> Double {
        switch outcome {
        case .easy:
            return 0.18
        case .correct:
            return 0.08
        case .hard:
            return -0.04
        case .partial:
            return 0.01
        case .incorrect:
            return -0.12
        }
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
