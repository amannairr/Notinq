import XCTest
@testable import Notinq

final class GraphVisualizationTests: XCTestCase {
    func testNeighborhoodGenerationIncludesOneHopNodesAndEdges() throws {
        let fixture = try AdaptiveGraphTestFixture()
        _ = try fixture.seedATPGraph()
        let service = GraphVisualizationService(repository: fixture.knowledgeRepository)

        let graph = service.graphForTopic("ATP")

        XCTAssertTrue(graph.nodes.contains { $0.title == "ATP" })
        XCTAssertTrue(graph.nodes.contains { $0.title == "Mitochondria" })
        XCTAssertTrue(graph.nodes.contains { $0.title == "Cellular Respiration" })
        XCTAssertTrue(graph.edges.contains { $0.relationshipType == KnowledgeRelationshipKind.partOf.rawValue })
        XCTAssertTrue(graph.edges.contains { $0.relationshipType == KnowledgeRelationshipKind.requires.rawValue })
    }

    func testSubgraphGenerationExpandsByRadius() throws {
        let fixture = try AdaptiveGraphTestFixture()
        _ = try fixture.seedATPGraph()
        let service = GraphVisualizationService(repository: fixture.knowledgeRepository)
        let atp = try XCTUnwrap(fixture.knowledgeRepository.canonicalConcept(named: "ATP"))

        let oneHop = service.subgraphAroundConcept(atp.id, radius: 1)
        let twoHop = service.subgraphAroundConcept(atp.id, radius: 2)

        XCTAssertTrue(oneHop.nodes.contains { $0.title == "Mitochondria" })
        XCTAssertFalse(oneHop.nodes.contains { $0.title == "Organelle" })
        XCTAssertTrue(twoHop.nodes.contains { $0.title == "Organelle" })
        XCTAssertGreaterThanOrEqual(twoHop.edges.count, oneHop.edges.count)
    }

    func testRelationshipRenderingDataContainsSourceTargetAndType() throws {
        let fixture = try AdaptiveGraphTestFixture()
        _ = try fixture.seedATPGraph()
        let service = GraphVisualizationService(repository: fixture.knowledgeRepository)

        let graph = service.graphForTopic("Adenosine Triphosphate")
        let atp = try XCTUnwrap(graph.nodes.first { $0.title == "ATP" })
        let mitochondria = try XCTUnwrap(graph.nodes.first { $0.title == "Mitochondria" })
        let edge = try XCTUnwrap(graph.edges.first { edge in
            edge.sourceID == atp.id && edge.targetID == mitochondria.id
        })

        XCTAssertEqual(edge.relationshipType, KnowledgeRelationshipKind.partOf.rawValue)
        XCTAssertGreaterThan(edge.confidence, 0)
    }
}
