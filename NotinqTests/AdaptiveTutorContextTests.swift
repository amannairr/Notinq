import XCTest
@testable import Notinq

@MainActor
final class AdaptiveTutorContextTests: XCTestCase {
    func testContextBuilderReturnsGraphMasteryGapsAndRetrievedNotes() async throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.atpID,
            masteryScore: 0.9,
            confidenceScore: 0.9,
            reviewCount: 2,
            mistakeCount: 0,
            lastReviewed: Date()
        )
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.respirationID,
            masteryScore: 0.2,
            confidenceScore: 0.3,
            reviewCount: 3,
            mistakeCount: 2,
            lastReviewed: Date()
        )

        let lexical = LexicalRetriever(noteRepository: fixture.noteRepository, knowledgeRepository: fixture.knowledgeRepository)
        let graphRetriever = GraphRetriever(knowledgeRepository: fixture.knowledgeRepository)
        let hybrid = HybridRetriever(
            lexicalRetriever: lexical,
            graphRetriever: graphRetriever,
            vectorRetriever: .shared,
            studentConceptService: StudentConceptService(repository: StudentConceptRepository(studyRepository: fixture.studyRepository))
        )
        let builder = ContextBuilderV2(
            retriever: hybrid,
            repository: fixture.knowledgeRepository,
            studentConceptService: StudentConceptService(repository: StudentConceptRepository(studyRepository: fixture.studyRepository)),
            studyRepository: fixture.studyRepository,
            graphExpansion: GraphExpansionService(repository: fixture.knowledgeRepository),
            graphContextBuilder: GraphContextBuilder(repository: fixture.knowledgeRepository),
            gapDetector: KnowledgeGapDetector(repository: fixture.knowledgeRepository)
        )

        let context = try await builder.buildAdaptiveContext(question: "What is ATP?", noteID: graph.noteID)
        let conceptNames = Set(context.relevantConcepts.map(\.name))

        XCTAssertFalse(context.retrievedNotes.isEmpty)
        XCTAssertTrue(conceptNames.contains("ATP"))
        XCTAssertTrue(conceptNames.contains("Mitochondria"))
        XCTAssertFalse(context.relationships.isEmpty)
        XCTAssertTrue(context.masteryMap.keys.contains(UUID(uuidString: graph.atpID)!))
        XCTAssertTrue(context.knowledgeGaps.contains { $0.name == "Cellular Respiration" })
        XCTAssertTrue(context.studyPlanRecommendations.contains { $0.contains("Cellular Respiration") })
        XCTAssertFalse(context.graphContext.isEmpty)
        XCTAssertFalse(context.prerequisites.isEmpty)
        XCTAssertFalse(context.weakConcepts.isEmpty)
        XCTAssertLessThanOrEqual(context.relevantConcepts.count, 20)
        XCTAssertLessThanOrEqual(context.relationships.count, 64)
    }
}
