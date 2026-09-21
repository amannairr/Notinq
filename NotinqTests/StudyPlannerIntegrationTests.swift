import XCTest
@testable import Notinq

@MainActor
final class StudyPlannerIntegrationTests: XCTestCase {
    func testDashboardPublishesTodayPlanFromGraphAndMastery() async throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.respirationID,
            masteryScore: 0.2,
            confidenceScore: 0.3,
            reviewCount: 1,
            mistakeCount: 1,
            lastReviewed: nil
        )
        let services = makeServices(fixture: fixture)
        let viewModel = LearningDashboardViewModel(
            studentKnowledgeService: services.knowledge,
            recommendationEngine: services.recommendations,
            studyPlannerService: services.planner
        )

        await viewModel.loadNow()

        XCTAssertTrue(viewModel.todaysPlan.contains { $0.concept == "Cellular Respiration" })
    }

    func testGraphExplorerPublishesStudyNextForSelectedConcept() throws {
        let fixture = try AdaptiveGraphTestFixture()
        _ = try fixture.seedATPGraph()
        let services = makeServices(fixture: fixture)
        let viewModel = KnowledgeGraphExplorerViewModel(
            repository: fixture.knowledgeRepository,
            visualizationService: GraphVisualizationService(repository: fixture.knowledgeRepository),
            explanationService: GraphExplanationService(repository: fixture.knowledgeRepository),
            recommendationEngine: services.recommendations,
            studyPlannerService: services.planner,
            studentConceptService: services.studentConcepts
        )

        viewModel.selectConcept("ATP")

        XCTAssertTrue(viewModel.studyNextTasks.contains { $0.concept == "Cellular Respiration" })
    }

    private func makeServices(
        fixture: AdaptiveGraphTestFixture
    ) -> (
        studentConcepts: StudentConceptService,
        knowledge: StudentKnowledgeService,
        recommendations: LearningRecommendationEngine,
        planner: StudyPlannerService
    ) {
        let studentConceptService = StudentConceptService(
            repository: StudentConceptRepository(studyRepository: fixture.studyRepository)
        )
        let knowledgeService = StudentKnowledgeService(
            knowledgeRepository: fixture.knowledgeRepository,
            studentConceptService: studentConceptService,
            studyRepository: fixture.studyRepository
        )
        let explanationService = GraphExplanationService(repository: fixture.knowledgeRepository)
        let recommendationEngine = LearningRecommendationEngine(
            repository: fixture.knowledgeRepository,
            studentConceptService: studentConceptService
        )
        let planner = StudyPlannerService(
            studentKnowledgeService: knowledgeService,
            recommendationEngine: recommendationEngine,
            graphExplanationService: explanationService,
            repository: fixture.knowledgeRepository
        )
        return (studentConceptService, knowledgeService, recommendationEngine, planner)
    }
}
