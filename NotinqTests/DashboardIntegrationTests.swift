import XCTest
@testable import Notinq

@MainActor
final class DashboardIntegrationTests: XCTestCase {
    func testDashboardLoadsFromGraphAndUpdatesAfterReviewEvent() async throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        let studentConceptService = StudentConceptService(repository: StudentConceptRepository(studyRepository: fixture.studyRepository))
        let studentService = StudentKnowledgeService(
            knowledgeRepository: fixture.knowledgeRepository,
            studentConceptService: studentConceptService,
            studyRepository: fixture.studyRepository
        )
        let recommendationEngine = LearningRecommendationEngine(
            repository: fixture.knowledgeRepository,
            studentConceptService: studentConceptService
        )
        let viewModel = LearningDashboardViewModel(
            studentKnowledgeService: studentService,
            recommendationEngine: recommendationEngine
        )

        try fixture.studyRepository.upsertStudentConcept(noteID: graph.noteID, conceptID: graph.atpID, masteryScore: 0.25, confidenceScore: 0.4, reviewCount: 1, mistakeCount: 1, lastReviewed: nil)
        await viewModel.loadNow()
        let initialMastery = viewModel.masteryScore
        XCTAssertTrue(viewModel.weakTopics.contains("ATP"))
        XCTAssertEqual(viewModel.graphStatistics.relationshipCount, 4)

        try studentConceptService.updateMastery(
            conceptID: graph.atpID,
            noteID: graph.noteID,
            outcome: .correct,
            source: .flashcard,
            reviewedAt: Date()
        )
        await viewModel.loadNow()

        XCTAssertGreaterThan(viewModel.masteryScore, initialMastery)
    }
}
