import XCTest
@testable import Notinq

@MainActor
final class ReviewSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testOverdueDetection() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.atpID,
            masteryScore: 0.3,
            confidenceScore: 0.3,
            reviewCount: 1,
            mistakeCount: 2,
            lastReviewed: now.addingTimeInterval(-20 * 86_400)
        )
        let scheduler = makeScheduler(fixture: fixture)

        let overdue = scheduler.overdue(limit: 4)

        XCTAssertTrue(overdue.contains { $0.conceptName == "ATP" && $0.daysUntilDue < 0 })
    }

    func testDueTodayDetection() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.respirationID,
            masteryScore: 0.5,
            confidenceScore: 0.5,
            reviewCount: 1,
            mistakeCount: 0,
            lastReviewed: now
        )
        let scheduler = makeScheduler(fixture: fixture)

        let dueToday = scheduler.dueToday(limit: 4)

        XCTAssertTrue(dueToday.contains { $0.conceptName == "Cellular Respiration" && $0.statusText == "Due today" })
    }

    func testNextReviewGeneration() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let scheduler = makeScheduler(fixture: fixture)
        let record = StudentConceptRecord(
            conceptID: "Limits",
            masteryScore: 0.9,
            confidenceScore: 0.9,
            lastReviewed: now,
            mistakeCount: 0,
            reviewCount: 6,
            createdAt: now,
            updatedAt: now
        )

        XCTAssertGreaterThan(scheduler.scheduleNextReview(for: record), now)
    }

    private func makeScheduler(fixture: AdaptiveGraphTestFixture) -> ReviewScheduler {
        let studentConceptService = StudentConceptService(
            repository: StudentConceptRepository(studyRepository: fixture.studyRepository)
        )
        return ReviewScheduler(
            studentConceptService: studentConceptService,
            knowledgeRepository: fixture.knowledgeRepository,
            retentionEngine: RetentionEngine(studentConceptService: studentConceptService, nowProvider: { self.now }),
            nowProvider: { self.now }
        )
    }
}
