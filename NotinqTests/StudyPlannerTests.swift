import XCTest
@testable import Notinq

@MainActor
final class StudyPlannerTests: XCTestCase {
    func testPrerequisiteOrderingPlacesFoundationsBeforeWeakConcept() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let noteID = try seedCalculusGraph(fixture)
        try fixture.studyRepository.upsertStudentConcept(
            noteID: noteID,
            conceptID: try XCTUnwrap(fixture.knowledgeRepository.canonicalConcept(named: "Integrals")?.id),
            masteryScore: 0.15,
            confidenceScore: 0.3,
            reviewCount: 1,
            mistakeCount: 1,
            lastReviewed: nil
        )
        let planner = makePlanner(fixture: fixture)

        let concepts = planner.dailyPlan(maxMinutes: 45).tasks.map(\.concept)

        XCTAssertEqual(concepts.prefix(3).map { $0 }, ["Limits", "Derivatives", "Integrals"])
    }

    func testWeakConceptPrioritizationCreatesWeakConceptTask() throws {
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
        let planner = makePlanner(fixture: fixture)

        let tasks = planner.dailyPlan(maxMinutes: 30).tasks

        XCTAssertTrue(tasks.contains { $0.concept == "Cellular Respiration" && $0.reason == .weakConcept })
    }

    func testExamPreparationPlanSplitsTopologyAcrossDays() throws {
        let fixture = try AdaptiveGraphTestFixture()
        try seedCalculusGraph(fixture)
        let planner = makePlanner(fixture: fixture)

        let plan = planner.examPreparationPlan(
            targetConcepts: ["Differential Equations"],
            daysRemaining: 4,
            minutesPerDay: 15
        )

        XCTAssertEqual(plan.sessions.map { $0.tasks.first?.concept }, ["Limits", "Derivatives", "Integrals", "Differential Equations"])
        XCTAssertEqual(plan.sessions.last?.tasks.first?.reason, .examPreparation)
    }

    func testReviewPlanUsesDueReviewConcepts() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.respirationID,
            masteryScore: 0.2,
            confidenceScore: 0.3,
            reviewCount: 0,
            mistakeCount: 1,
            lastReviewed: nil
        )
        let planner = makePlanner(fixture: fixture)

        let reviewTasks = planner.reviewPlan(limit: 4).tasks

        XCTAssertTrue(reviewTasks.contains { $0.concept == "Cellular Respiration" && $0.reason == .reviewDue })
    }

    @discardableResult
    private func seedCalculusGraph(_ fixture: AdaptiveGraphTestFixture) throws -> UUID {
        try fixture.persist(
            title: "Calculus",
            content: "Limits support derivatives, integrals, and differential equations.",
            concepts: [
                fixture.concept(id: "limits", name: "Limits"),
                fixture.concept(id: "derivatives", name: "Derivatives"),
                fixture.concept(id: "integrals", name: "Integrals"),
                fixture.concept(id: "differential-equations", name: "Differential Equations")
            ],
            relationships: [
                fixture.relationship(id: "derivatives-limits", sourceID: "derivatives", targetID: "limits", kind: .requires),
                fixture.relationship(id: "integrals-derivatives", sourceID: "integrals", targetID: "derivatives", kind: .requires),
                fixture.relationship(id: "de-integrals", sourceID: "differential-equations", targetID: "integrals", kind: .requires)
            ]
        )
    }

    private func makePlanner(fixture: AdaptiveGraphTestFixture) -> StudyPlannerService {
        let studentConceptService = StudentConceptService(
            repository: StudentConceptRepository(studyRepository: fixture.studyRepository)
        )
        let recommendationEngine = LearningRecommendationEngine(
            repository: fixture.knowledgeRepository,
            studentConceptService: studentConceptService
        )
        return StudyPlannerService(
            studentKnowledgeService: StudentKnowledgeService(
                knowledgeRepository: fixture.knowledgeRepository,
                studentConceptService: studentConceptService,
                studyRepository: fixture.studyRepository
            ),
            recommendationEngine: recommendationEngine,
            graphExplanationService: GraphExplanationService(repository: fixture.knowledgeRepository),
            repository: fixture.knowledgeRepository
        )
    }
}
