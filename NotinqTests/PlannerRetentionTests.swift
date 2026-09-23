import XCTest
@testable import Notinq

@MainActor
final class PlannerRetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testOverdueReviewsArePrioritizedBeforeWeakConcepts() throws {
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
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.respirationID,
            masteryScore: 0.2,
            confidenceScore: 0.3,
            reviewCount: 1,
            mistakeCount: 1,
            lastReviewed: nil
        )
        let planner = makePlanner(fixture: fixture)

        let tasks = planner.dailyPlan(maxMinutes: 30).tasks

        XCTAssertEqual(tasks.first?.concept, "ATP")
        XCTAssertEqual(tasks.first?.reason, .reviewDue)
        XCTAssertTrue(tasks.contains { $0.concept == "Cellular Respiration" })
    }

    private func makePlanner(fixture: AdaptiveGraphTestFixture) -> StudyPlannerService {
        let studentConceptService = StudentConceptService(
            repository: StudentConceptRepository(studyRepository: fixture.studyRepository)
        )
        let knowledgeService = StudentKnowledgeService(
            knowledgeRepository: fixture.knowledgeRepository,
            studentConceptService: studentConceptService,
            studyRepository: fixture.studyRepository
        )
        let recommendationEngine = LearningRecommendationEngine(
            repository: fixture.knowledgeRepository,
            studentConceptService: studentConceptService
        )
        let retentionEngine = RetentionEngine(studentConceptService: studentConceptService, nowProvider: { self.now })
        return StudyPlannerService(
            studentKnowledgeService: knowledgeService,
            recommendationEngine: recommendationEngine,
            graphExplanationService: GraphExplanationService(repository: fixture.knowledgeRepository),
            reviewScheduler: ReviewScheduler(
                studentConceptService: studentConceptService,
                knowledgeRepository: fixture.knowledgeRepository,
                retentionEngine: retentionEngine,
                nowProvider: { self.now }
            ),
            repository: fixture.knowledgeRepository
        )
    }
}
