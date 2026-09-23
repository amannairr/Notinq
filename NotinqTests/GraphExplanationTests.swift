import Foundation
import XCTest
@testable import Notinq

final class GraphExplanationTests: XCTestCase {
    private var databaseURL: URL!
    private var database: SQLiteDatabase!
    private var fixtureFolderID: UUID!
    private var studyRepository: StudyRepository!
    private var noteRepository: NoteRepository!
    private var knowledgeRepository: KnowledgeRepository!
    private var graphService: GraphExplanationService!
    private var studyPlanGenerator: StudyPlanGenerator!
    private var visualizationService: GraphVisualizationService!

    override func setUpWithError() throws {
        try super.setUpWithError()

        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notinq-graph-explanation-tests-")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        database = try SQLiteDatabase(url: databaseURL)
        fixtureFolderID = UUID()
        studyRepository = StudyRepository(database: database)
        noteRepository = NoteRepository(database: database, studyRepository: studyRepository, performMigration: false)
        knowledgeRepository = KnowledgeRepository(database: database)
        graphService = GraphExplanationService(repository: knowledgeRepository)
        studyPlanGenerator = StudyPlanGenerator(repository: knowledgeRepository, explanations: graphService)
        visualizationService = GraphVisualizationService(repository: knowledgeRepository)

        try database.execute(
            "INSERT INTO folders (id, title, sort_order) VALUES (?, ?, ?)",
            bindings: [
                .text(fixtureFolderID.uuidString),
                .text("Graph Tests"),
                .integer(0)
            ]
        )
    }

    override func tearDownWithError() throws {
        graphService = nil
        studyPlanGenerator = nil
        visualizationService = nil
        knowledgeRepository = nil
        noteRepository = nil
        studyRepository = nil
        fixtureFolderID = nil
        database = nil

        if let databaseURL {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        try super.tearDownWithError()
    }

    func testAliasResolutionUsesCanonicalConcepts() throws {
        try persistKnowledge(
            noteTitle: "ATP",
            concepts: [
                makeConcept(id: "atp", name: "ATP", aliases: ["Adenosine Triphosphate", "adenosine-triphosphate"])
            ],
            relationships: []
        )

        let atp = try XCTUnwrap(knowledgeRepository.canonicalConcept(named: "ATP"))
        let expanded = try XCTUnwrap(knowledgeRepository.canonicalConcept(named: "Adenosine Triphosphate"))
        let hyphenated = try XCTUnwrap(knowledgeRepository.canonicalConcept(named: "adenosine-triphosphate"))

        XCTAssertEqual(atp.id, expanded.id)
        XCTAssertEqual(atp.id, hyphenated.id)

        let explanation = graphService.explainConcept("adenosine-triphosphate")
        XCTAssertEqual(explanation.conceptName, "ATP")
        XCTAssertTrue(explanation.aliases.contains("Adenosine Triphosphate"))
    }

    func testFindPathReturnsShortestCanonicalRelationshipPathAcrossNotes() throws {
        try persistKnowledge(
            noteTitle: "ATP and Mitochondria",
            concepts: [
                makeConcept(id: "atp", name: "ATP", aliases: ["Adenosine Triphosphate"]),
                makeConcept(id: "mitochondria-a", name: "Mitochondria")
            ],
            relationships: [
                makeRelationship(id: "atp-mito", sourceID: "atp", targetID: "mitochondria-a", kind: .partOf)
            ]
        )
        try persistKnowledge(
            noteTitle: "Organelles",
            concepts: [
                makeConcept(id: "mitochondria-b", name: "mitochondria"),
                makeConcept(id: "organelle", name: "Organelle")
            ],
            relationships: [
                makeRelationship(id: "mito-organelle", sourceID: "mitochondria-b", targetID: "organelle", kind: .partOf)
            ]
        )

        let path = try XCTUnwrap(graphService.findPath(from: "ATP", to: "Organelle"))

        XCTAssertEqual(path.nodes.map(\.canonicalName), ["ATP", "Mitochondria", "Organelle"])
        XCTAssertEqual(path.relationships.map(\.relationType), [KnowledgeRelationshipKind.partOf.rawValue, KnowledgeRelationshipKind.partOf.rawValue])
    }

    func testPrerequisiteChainIsTopologicallyOrdered() throws {
        try persistKnowledge(
            noteTitle: "Calculus",
            concepts: [
                makeConcept(id: "limits", name: "Limits"),
                makeConcept(id: "derivatives", name: "Derivatives"),
                makeConcept(id: "integrals", name: "Integrals"),
                makeConcept(id: "differential-equations", name: "Differential Equations")
            ],
            relationships: [
                makeRelationship(id: "derivatives-require-limits", sourceID: "derivatives", targetID: "limits", kind: .requires),
                makeRelationship(id: "integrals-require-derivatives", sourceID: "integrals", targetID: "derivatives", kind: .requires),
                makeRelationship(id: "de-require-integrals", sourceID: "differential-equations", targetID: "integrals", kind: .requires)
            ]
        )

        XCTAssertEqual(
            graphService.prerequisiteChain(for: "Differential Equations"),
            ["Limits", "Derivatives", "Integrals"]
        )
    }

    func testCycleProtectionTerminatesPathAndPrerequisiteTraversal() throws {
        try persistKnowledge(
            noteTitle: "Cyclic Graph",
            concepts: [
                makeConcept(id: "a", name: "A"),
                makeConcept(id: "b", name: "B"),
                makeConcept(id: "c", name: "C")
            ],
            relationships: [
                makeRelationship(id: "a-b", sourceID: "a", targetID: "b", kind: .requires),
                makeRelationship(id: "b-c", sourceID: "b", targetID: "c", kind: .requires),
                makeRelationship(id: "c-a", sourceID: "c", targetID: "a", kind: .requires)
            ]
        )

        let path = try XCTUnwrap(graphService.findPath(from: "A", to: "C"))
        XCTAssertEqual(path.nodes.map(\.canonicalName), ["A", "C"])

        let chain = graphService.prerequisiteChain(for: "A")
        XCTAssertEqual(Set(chain), Set(["B", "C"]))
        XCTAssertLessThanOrEqual(chain.count, 2)
    }

    func testDescendantsReturnOutgoingCanonicalConcepts() throws {
        try persistKnowledge(
            noteTitle: "Cell Structure",
            concepts: [
                makeConcept(id: "cell", name: "Cell"),
                makeConcept(id: "mitochondria", name: "Mitochondria"),
                makeConcept(id: "ribosome", name: "Ribosome"),
                makeConcept(id: "atp-production", name: "ATP Production")
            ],
            relationships: [
                makeRelationship(id: "cell-mito", sourceID: "cell", targetID: "mitochondria", kind: .contains),
                makeRelationship(id: "cell-ribosome", sourceID: "cell", targetID: "ribosome", kind: .contains),
                makeRelationship(id: "mito-atp", sourceID: "mitochondria", targetID: "atp-production", kind: .produces)
            ]
        )

        XCTAssertEqual(
            graphService.descendants(of: "Cell"),
            ["Mitochondria", "Ribosome", "ATP Production"]
        )
    }

    func testKnowledgeGraphManagerReadsCanonicalSQLiteGraph() throws {
        let noteID = try persistKnowledge(
            noteTitle: "Graph Adapter",
            concepts: [
                makeConcept(id: "atp", name: "ATP"),
                makeConcept(id: "mitochondria", name: "Mitochondria")
            ],
            relationships: [
                makeRelationship(id: "atp-mito", sourceID: "atp", targetID: "mitochondria", kind: .requires)
            ]
        )

        let manager = KnowledgeGraphManager(repository: knowledgeRepository)
        let concepts = manager.concepts(for: noteID)
        let relationships = manager.relationships(for: noteID)

        XCTAssertEqual(concepts.map(\.name).sorted(), ["ATP", "Mitochondria"])
        XCTAssertEqual(relationships.count, 1)
        XCTAssertEqual(manager.prerequisites(of: try XCTUnwrap(concepts.first { $0.name == "ATP" })).map(\.name), ["Mitochondria"])
    }

    func testStudyPlanOrdersPrerequisitesBeforeWeakConceptAndDependents() throws {
        try persistKnowledge(
            noteTitle: "Calculus Plan",
            concepts: [
                makeConcept(id: "limits", name: "Limits"),
                makeConcept(id: "derivatives", name: "Derivatives"),
                makeConcept(id: "integrals", name: "Integrals"),
                makeConcept(id: "differential-equations", name: "Differential Equations")
            ],
            relationships: [
                makeRelationship(id: "derivatives-require-limits", sourceID: "derivatives", targetID: "limits", kind: .requires),
                makeRelationship(id: "integrals-require-derivatives", sourceID: "integrals", targetID: "derivatives", kind: .requires),
                makeRelationship(id: "de-require-integrals", sourceID: "differential-equations", targetID: "integrals", kind: .requires)
            ]
        )

        let plan = studyPlanGenerator.prerequisiteStudyPlan(
            for: "Differential Equations",
            masteryScores: ["Integrals": 0.2]
        )

        XCTAssertEqual(plan.map(\.conceptName), ["Limits", "Derivatives", "Integrals", "Differential Equations"])
        XCTAssertEqual(
            studyPlanGenerator.reviewDependencies(for: "Integrals").map(\.conceptName),
            ["Limits", "Derivatives"]
        )
    }

    func testBottleneckDetectionRanksHighCentralityConcepts() throws {
        try persistKnowledge(
            noteTitle: "Cell Bottlenecks",
            concepts: [
                makeConcept(id: "cell", name: "Cell"),
                makeConcept(id: "mitochondria", name: "Mitochondria"),
                makeConcept(id: "ribosome", name: "Ribosome"),
                makeConcept(id: "atp", name: "ATP")
            ],
            relationships: [
                makeRelationship(id: "mito-require-cell", sourceID: "mitochondria", targetID: "cell", kind: .requires),
                makeRelationship(id: "ribo-require-cell", sourceID: "ribosome", targetID: "cell", kind: .requires),
                makeRelationship(id: "atp-require-mito", sourceID: "atp", targetID: "mitochondria", kind: .requires)
            ]
        )

        let prep = studyPlanGenerator.graphBasedExamPreparation(limit: 2)

        XCTAssertEqual(prep.first?.conceptName, "Mitochondria")
        XCTAssertGreaterThanOrEqual(prep.first?.centrality ?? 0, 2)
    }

    func testLearningPathUsesTopologyBasedSequencing() throws {
        try persistKnowledge(
            noteTitle: "Calculus Path",
            concepts: [
                makeConcept(id: "limits", name: "Limits"),
                makeConcept(id: "derivatives", name: "Derivatives"),
                makeConcept(id: "integrals", name: "Integrals")
            ],
            relationships: [
                makeRelationship(id: "derivatives-require-limits", sourceID: "derivatives", targetID: "limits", kind: .requires),
                makeRelationship(id: "integrals-require-derivatives", sourceID: "integrals", targetID: "derivatives", kind: .requires)
            ]
        )

        let path = studyPlanGenerator.learningPath(for: "Integrals")

        XCTAssertEqual(path.beginner, ["Limits"])
        XCTAssertEqual(path.intermediate, ["Derivatives"])
        XCTAssertEqual(path.advanced, ["Integrals"])
    }

    func testVisualizationServiceBuildsCanonicalSubgraph() throws {
        try persistKnowledge(
            noteTitle: "Visualization",
            concepts: [
                makeConcept(id: "atp", name: "ATP", aliases: ["Adenosine Triphosphate"]),
                makeConcept(id: "mitochondria", name: "Mitochondria"),
                makeConcept(id: "organelle", name: "Organelle")
            ],
            relationships: [
                makeRelationship(id: "atp-mito", sourceID: "atp", targetID: "mitochondria", kind: .partOf),
                makeRelationship(id: "mito-organelle", sourceID: "mitochondria", targetID: "organelle", kind: .partOf)
            ]
        )

        let graph = visualizationService.graphForTopic("Adenosine Triphosphate")

        XCTAssertEqual(graph.nodes.map(\.title).sorted(), ["ATP", "Mitochondria", "Organelle"])
        XCTAssertEqual(graph.edges.map(\.relationshipType), [KnowledgeRelationshipKind.partOf.rawValue, KnowledgeRelationshipKind.partOf.rawValue])
    }

    @discardableResult
    private func persistKnowledge(
        noteTitle: String,
        concepts: [KnowledgeConcept],
        relationships: [KnowledgeRelationship]
    ) throws -> UUID {
        let noteID = UUID()
        var extraction = StructuredKnowledge(title: noteTitle)
        extraction.concepts = concepts
        extraction.relationships = relationships

        let timestamp = ISO8601DateFormatter().string(from: Date())
        try database.execute(
            """
            INSERT INTO notes (id, folder_id, title, content, created_at, updated_at, note_order, study_data_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(noteID.uuidString),
                .text(fixtureFolderID.uuidString),
                .text(noteTitle),
                .text(noteTitle),
                .text(timestamp),
                .text(timestamp),
                .integer(0),
                .text("{}")
            ]
        )

        try knowledgeRepository.persist(
            noteID: noteID,
            noteTitle: noteTitle,
            noteContent: noteTitle,
            chunks: [],
            extraction: extraction
        )
        return noteID
    }

    private func makeConcept(id: String, name: String, aliases: [String] = []) -> KnowledgeConcept {
        var concept = KnowledgeConcept()
        concept.id = id
        concept.name = name
        concept.definition = "\(name) definition"
        concept.aliases = aliases
        concept.importance = 0.8
        concept.confidence = 0.9
        concept.category = "concept"
        return concept
    }

    private func makeRelationship(
        id: String,
        sourceID: String,
        targetID: String,
        kind: KnowledgeRelationshipKind
    ) -> KnowledgeRelationship {
        var relationship = KnowledgeRelationship()
        relationship.id = id
        relationship.sourceID = sourceID
        relationship.targetID = targetID
        relationship.relationKind = kind
        relationship.relation = kind.rawValue
        relationship.confidence = 0.9
        return relationship
    }
}
