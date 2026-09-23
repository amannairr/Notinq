import XCTest
@testable import Notinq

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testViewModelPublishesWeakStrongReviewsAndGraphStats() async throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(noteID: graph.noteID, conceptID: graph.atpID, masteryScore: 0.9, confidenceScore: 0.9, reviewCount: 4, mistakeCount: 0, lastReviewed: Date())
        try fixture.studyRepository.upsertStudentConcept(noteID: graph.noteID, conceptID: graph.respirationID, masteryScore: 0.2, confidenceScore: 0.3, reviewCount: 2, mistakeCount: 2, lastReviewed: nil)
        let studentService = StudentKnowledgeService(
            knowledgeRepository: fixture.knowledgeRepository,
            studentConceptService: StudentConceptService(repository: StudentConceptRepository(studyRepository: fixture.studyRepository)),
            studyRepository: fixture.studyRepository
        )
        let recommendationEngine = LearningRecommendationEngine(
            repository: fixture.knowledgeRepository,
            studentConceptService: StudentConceptService(repository: StudentConceptRepository(studyRepository: fixture.studyRepository))
        )
        let viewModel = LearningDashboardViewModel(
            studentKnowledgeService: studentService,
            recommendationEngine: recommendationEngine
        )

        await viewModel.loadNow()

        XCTAssertGreaterThan(viewModel.masteryScore, 0)
        XCTAssertTrue(viewModel.weakTopics.contains("Cellular Respiration"))
        XCTAssertTrue(viewModel.strongTopics.contains("ATP"))
        XCTAssertTrue(viewModel.recommendedReviews.contains { $0.concept == "Cellular Respiration" })
        XCTAssertEqual(viewModel.graphStatistics.conceptCount, 5)
    }
}
