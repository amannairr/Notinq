import XCTest
@testable import Notinq

final class GraphExpansionTests: XCTestCase {
    func testATPExpansionIncludesGraphNeighborsPrerequisitesAndDependents() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        let atp = try XCTUnwrap(try fixture.knowledgeRepository.concept(for: graph.atpID).map(concept(from:)))

        let expansion = GraphExpansionService(repository: fixture.knowledgeRepository)
            .expand(question: "What is ATP?", seedConcepts: [atp])
        let names = Set(expansion.map(\.name))

        XCTAssertTrue(names.contains("ATP"))
        XCTAssertTrue(names.contains("Mitochondria"))
        XCTAssertTrue(names.contains("Cellular Respiration"))
        XCTAssertTrue(names.contains("Energy Production"))
        XCTAssertLessThanOrEqual(expansion.count, 25)
    }

    func testExpansionIsCycleSafe() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let a = UUID().uuidString
        let b = UUID().uuidString
        let c = UUID().uuidString
        try fixture.persist(
            title: "Cycle",
            content: "A depends on B, B depends on C, and C depends on A.",
            concepts: [
                fixture.concept(id: a, name: "A"),
                fixture.concept(id: b, name: "B"),
                fixture.concept(id: c, name: "C")
            ],
            relationships: [
                fixture.relationship(id: "a-b", sourceID: a, targetID: b, kind: .requires),
                fixture.relationship(id: "b-c", sourceID: b, targetID: c, kind: .requires),
                fixture.relationship(id: "c-a", sourceID: c, targetID: a, kind: .requires)
            ]
        )
        let seed = try XCTUnwrap(try fixture.knowledgeRepository.concept(for: a).map(concept(from:)))

        let expansion = GraphExpansionService(repository: fixture.knowledgeRepository)
            .expand(question: "A", seedConcepts: [seed])

        XCTAssertEqual(Set(expansion.map(\.name)), Set(["A", "B", "C"]))
    }

    private func concept(from record: CanonicalConceptRecord) -> Concept {
        Concept(
            id: UUID(uuidString: record.id) ?? UUID(),
            name: record.canonicalName,
            description: record.description,
            aliases: record.aliases,
            noteID: record.sourceReferences.compactMap(UUID.init(uuidString:)).first ?? UUID(),
            confidence: record.confidence,
            embeddingID: record.id,
            importanceScore: record.confidence,
            difficultyScore: 1.0 - record.confidence
        )
    }
}
