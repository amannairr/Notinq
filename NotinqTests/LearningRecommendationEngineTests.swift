import XCTest
@testable import Notinq

@MainActor
final class LearningRecommendationEngineTests: XCTestCase {
    func testRecommendedReviewsAndWeakAreasUseMasteryRecords() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.respirationID,
            masteryScore: 0.2,
            confidenceScore: 0.3,
            reviewCount: 2,
            mistakeCount: 1,
            lastReviewed: nil
        )
        let engine = LearningRecommendationEngine(
            repository: fixture.knowledgeRepository,
            studentConceptService: StudentConceptService(repository: StudentConceptRepository(studyRepository: fixture.studyRepository))
        )

        XCTAssertTrue(engine.recommendedReviews().contains("Cellular Respiration"))
        XCTAssertTrue(engine.recommendedWeakAreas().contains("Cellular Respiration"))
    }

    func testRecommendedPrerequisitesUseGraphOrdering() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        let engine = LearningRecommendationEngine(
            repository: fixture.knowledgeRepository,
            studentConceptService: StudentConceptService(repository: StudentConceptRepository(studyRepository: fixture.studyRepository))
        )

        let prerequisites = engine.recommendedPrerequisites(
            for: "ATP",
            masteryScores: [
                graph.respirationID: 0.2,
                "Cellular Respiration": 0.2
            ]
        )

        XCTAssertTrue(prerequisites.contains("Cellular Respiration"))
    }

    func testLearningGapVisualizationShowsBlockedTopics() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.respirationID,
            masteryScore: 0.2,
            confidenceScore: 0.3,
            reviewCount: 2,
            mistakeCount: 1,
            lastReviewed: Date()
        )
        let engine = LearningRecommendationEngine(
            repository: fixture.knowledgeRepository,
            studentConceptService: StudentConceptService(repository: StudentConceptRepository(studyRepository: fixture.studyRepository))
        )

        let gaps = engine.learningGaps()

        XCTAssertTrue(gaps.contains { item in
            item.weakConcept == "Cellular Respiration" && item.blockedTopics.contains("ATP")
        })
    }

    func testRecommendedNextTopicsFollowDependentsOfStrongConcepts() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.mitochondriaID,
            masteryScore: 0.92,
            confidenceScore: 0.9,
            reviewCount: 4,
            mistakeCount: 0,
            lastReviewed: Date()
        )
        let engine = LearningRecommendationEngine(
            repository: fixture.knowledgeRepository,
            studentConceptService: StudentConceptService(repository: StudentConceptRepository(studyRepository: fixture.studyRepository))
        )

        XCTAssertTrue(engine.recommendedNextTopics().contains("ATP"))
    }
}
