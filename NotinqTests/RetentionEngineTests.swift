import XCTest
@testable import Notinq

final class RetentionEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testRetentionDecaySlowsWithRecentAndRepeatedReviews() {
        let engine = RetentionEngine(nowProvider: { self.now })
        let oldSingleReview = record(
            mastery: 0.8,
            confidence: 0.8,
            reviewCount: 1,
            mistakeCount: 0,
            lastReviewed: now.addingTimeInterval(-30 * 86_400)
        )
        let recentRepeatedReview = record(
            mastery: 0.8,
            confidence: 0.8,
            reviewCount: 8,
            mistakeCount: 0,
            lastReviewed: now.addingTimeInterval(-2 * 86_400)
        )

        XCTAssertLessThan(engine.retentionScore(for: oldSingleReview), engine.retentionScore(for: recentRepeatedReview))
        XCTAssertGreaterThan(engine.daysUntilReview(for: recentRepeatedReview), engine.daysUntilReview(for: oldSingleReview))
    }

    func testRetentionUpdateAfterReviewDelegatesToStudentConceptService() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.atpID,
            masteryScore: 0.4,
            confidenceScore: 0.4,
            reviewCount: 0,
            mistakeCount: 0,
            lastReviewed: nil
        )
        let studentConceptService = StudentConceptService(
            repository: StudentConceptRepository(studyRepository: fixture.studyRepository)
        )
        let engine = RetentionEngine(studentConceptService: studentConceptService, nowProvider: { self.now })

        let updated = try engine.updateRetentionAfterReview(
            conceptID: graph.atpID,
            noteID: graph.noteID,
            outcome: .correct,
            source: .flashcard,
            reviewedAt: now
        )

        XCTAssertEqual(updated.reviewCount, 1)
        XCTAssertGreaterThan(updated.masteryScore, 0.4)
        XCTAssertEqual(updated.lastReviewed, now)
    }

    func testForgettingPredictionMovesLaterForStrongerMemory() {
        let engine = RetentionEngine(nowProvider: { self.now })
        let weak = record(mastery: 0.35, confidence: 0.35, reviewCount: 1, mistakeCount: 2, lastReviewed: now)
        let strong = record(mastery: 0.9, confidence: 0.9, reviewCount: 8, mistakeCount: 0, lastReviewed: now)

        XCTAssertLessThan(engine.predictedForgettingDate(for: weak), engine.predictedForgettingDate(for: strong))
        XCTAssertGreaterThan(engine.reviewUrgency(for: weak), engine.reviewUrgency(for: strong))
    }

    private func record(
        mastery: Double,
        confidence: Double,
        reviewCount: Int,
        mistakeCount: Int,
        lastReviewed: Date?
    ) -> StudentConceptRecord {
        StudentConceptRecord(
            conceptID: UUID().uuidString,
            masteryScore: mastery,
            confidenceScore: confidence,
            lastReviewed: lastReviewed,
            mistakeCount: mistakeCount,
            reviewCount: reviewCount,
            createdAt: now.addingTimeInterval(-40 * 86_400),
            updatedAt: lastReviewed ?? now.addingTimeInterval(-40 * 86_400)
        )
    }
}
