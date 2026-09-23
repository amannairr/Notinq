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

    private func makeViewModel(fixture: AdaptiveGraphTestFixture) -> KnowledgeGraphExplorerViewModel {
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
            studentConceptService: studentConceptService
        )
    }
}
