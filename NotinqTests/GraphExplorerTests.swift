import XCTest
@testable import Notinq

@MainActor
final class GraphExplorerTests: XCTestCase {
    func testSearchAliasResolutionSelectsCanonicalNode() throws {
        let fixture = try AdaptiveGraphTestFixture()
        try fixture.persist(
            title: "ATP Alias",
            content: "ATP stores energy.",
            concepts: [
                fixture.concept(id: "atp", name: "ATP", aliases: ["Adenosine Triphosphate", "adenosine-triphosphate"])
            ],
            relationships: []
        )
        let viewModel = makeViewModel(fixture: fixture)

        viewModel.searchQuery = "adenosine-triphosphate"
        viewModel.searchConcepts()

        XCTAssertEqual(viewModel.selectedNode?.name, "ATP")
        XCTAssertEqual(viewModel.searchResults.first?.canonicalName, "ATP")
    }

    func testNodeSelectionLoadsExplanationAndStudyRecommendations() throws {
        let fixture = try AdaptiveGraphTestFixture()
        _ = try fixture.seedATPGraph()
        let viewModel = makeViewModel(fixture: fixture)

        viewModel.selectConcept("ATP")

        XCTAssertEqual(viewModel.selectedNode?.name, "ATP")
        XCTAssertTrue(viewModel.nodes.contains { $0.name == "Mitochondria" })
        XCTAssertTrue(viewModel.explanation.prerequisites.contains("Cellular Respiration"))
        XCTAssertTrue(viewModel.studyRecommendations.contains("Cellular Respiration"))
    }

    func testPathExplanationUsesGraphExplanationService() throws {
        let fixture = try AdaptiveGraphTestFixture()
        _ = try fixture.seedATPGraph()
        let viewModel = makeViewModel(fixture: fixture)

        viewModel.selectConcept("ATP")
        viewModel.targetQuery = "Organelle"
        viewModel.findConnection()

        XCTAssertEqual(viewModel.pathResult?.conceptNames, ["ATP", "Mitochondria", "Organelle"])
        XCTAssertEqual(viewModel.pathResult?.relationshipTypes, [KnowledgeRelationshipKind.partOf.rawValue, KnowledgeRelationshipKind.partOf.rawValue])
    }

    func testBottleneckRankingLoadsImportantConcepts() throws {
        let fixture = try AdaptiveGraphTestFixture()
        _ = try fixture.persist(
            title: "Bottlenecks",
            content: "Mitochondria connects many concepts.",
            concepts: [
                fixture.concept(id: "cell", name: "Cell"),
                fixture.concept(id: "mitochondria", name: "Mitochondria"),
                fixture.concept(id: "atp", name: "ATP"),
                fixture.concept(id: "respiration", name: "Cellular Respiration")
            ],
            relationships: [
                fixture.relationship(id: "mito-cell", sourceID: "mitochondria", targetID: "cell", kind: .requires),
                fixture.relationship(id: "atp-mito", sourceID: "atp", targetID: "mitochondria", kind: .requires),
                fixture.relationship(id: "respiration-mito", sourceID: "respiration", targetID: "mitochondria", kind: .requires)
            ]
        )
        let viewModel = makeViewModel(fixture: fixture)

        viewModel.loadInitialGraph()

        XCTAssertEqual(viewModel.bottlenecks.first?.conceptName, "Mitochondria")
        XCTAssertGreaterThanOrEqual(viewModel.bottlenecks.first?.centrality ?? 0, 3)
    }

    func testFilteringSupportsMasteryGapsConfidenceAndTextQuery() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.atpID,
            masteryScore: 0.9,
            confidenceScore: 0.9,
            reviewCount: 3,
            mistakeCount: 0,
            lastReviewed: Date()
        )
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.respirationID,
            masteryScore: 0.2,
            confidenceScore: 0.3,
            reviewCount: 2,
            mistakeCount: 2,
            lastReviewed: nil
        )
        let viewModel = makeViewModel(fixture: fixture)

        viewModel.selectConcept("ATP")
        viewModel.filterState = GraphExplorerFilterState(
            masteryStates: [.struggling],
            gapStatuses: [.active],
            minimumConfidence: 0,
            textQuery: "respiration"
        )

        XCTAssertEqual(viewModel.filteredNodes.map(\.name), ["Cellular Respiration"])
        XCTAssertTrue(viewModel.filteredEdges.allSatisfy { $0.confidence >= 0 })

        viewModel.filterState.minimumConfidence = 0.95

        XCTAssertTrue(viewModel.filteredEdges.isEmpty)
    }

    func testNodeProvenanceSummarizesSourceNoteAndExcerpt() throws {
        let fixture = try AdaptiveGraphTestFixture()
        _ = try fixture.seedATPGraph()
        let viewModel = makeViewModel(fixture: fixture)

        viewModel.selectConcept("ATP")

        XCTAssertEqual(viewModel.selectedNode?.provenance.sourceCount, 1)
        XCTAssertEqual(viewModel.selectedNode?.provenance.references.first?.title, "ATP Notes")
        XCTAssertTrue(viewModel.selectedNode?.provenance.references.first?.excerpt.contains("ATP is produced") == true)
    }

    func testEdgeSelectionPublishesRelationshipDetailModel() throws {
        let fixture = try AdaptiveGraphTestFixture()
        _ = try fixture.seedATPGraph()
        let viewModel = makeViewModel(fixture: fixture)

        viewModel.selectConcept("ATP")
        let edge = try XCTUnwrap(viewModel.edges.first)
        viewModel.selectEdge(edge.id)

        XCTAssertNil(viewModel.selectedNode)
        XCTAssertEqual(viewModel.selectedEdge?.id, edge.id)
        XCTAssertEqual(viewModel.selectedEdge?.relationshipType, edge.relationshipType)
    }

    func testViewportAndFiltersPersistAcrossViewModels() throws {
        let suiteName = "GraphExplorerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let fixture = try AdaptiveGraphTestFixture()

        let first = makeViewModel(fixture: fixture, userDefaults: defaults)
        first.updateViewport(scale: 2.2, offsetX: 42, offsetY: -12)
        first.filterState = GraphExplorerFilterState(
            masteryStates: [.mastered, .familiar],
            gapStatuses: [.resolved],
            minimumConfidence: 0.65,
            textQuery: "ATP"
        )

        let second = makeViewModel(fixture: fixture, userDefaults: defaults)

        XCTAssertEqual(second.viewport, GraphExplorerViewport(offsetX: 42, offsetY: -12, scale: 2.2))
        XCTAssertEqual(second.filterState, first.filterState)
    }

    private func makeViewModel(
        fixture: AdaptiveGraphTestFixture,
        userDefaults: UserDefaults = UserDefaults(suiteName: "GraphExplorerTests-\(UUID().uuidString)") ?? .standard
    ) -> KnowledgeGraphExplorerViewModel {
        let studentConceptService = StudentConceptService(
            repository: StudentConceptRepository(studyRepository: fixture.studyRepository)
        )
        return KnowledgeGraphExplorerViewModel(
            repository: fixture.knowledgeRepository,
            visualizationService: GraphVisualizationService(repository: fixture.knowledgeRepository),
            explanationService: GraphExplanationService(repository: fixture.knowledgeRepository),
            recommendationEngine: LearningRecommendationEngine(
                repository: fixture.knowledgeRepository,
                studentConceptService: studentConceptService
            ),
            studentConceptService: studentConceptService,
            userDefaults: userDefaults
        )
    }
}
