import Foundation
import XCTest
@testable import Notinq

final class GraphContextBuilderTests: XCTestCase {
    private var databaseURL: URL!
    private var database: SQLiteDatabase!
    private var folderID: UUID!
    private var noteRepository: NoteRepository!
    private var knowledgeRepository: KnowledgeRepository!
    private var builder: GraphContextBuilder!

    override func setUpWithError() throws {
        try super.setUpWithError()
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notinq-graph-context-tests-")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        database = try SQLiteDatabase(url: databaseURL)
        folderID = UUID()
        noteRepository = NoteRepository(database: database, studyRepository: StudyRepository(database: database), performMigration: false)
        knowledgeRepository = KnowledgeRepository(database: database)
        builder = GraphContextBuilder(repository: knowledgeRepository)
        try database.execute(
            "INSERT INTO folders (id, title, sort_order) VALUES (?, ?, ?)",
            bindings: [.text(folderID.uuidString), .text("Graph Context"), .integer(0)]
        )
    }

    override func tearDownWithError() throws {
        builder = nil
        knowledgeRepository = nil
        noteRepository = nil
        database = nil
        folderID = nil
        if let databaseURL {
            try? FileManager.default.removeItem(at: databaseURL)
        }
        try super.tearDownWithError()
    }

    func testBuildContextExpandsAliasesPrerequisitesDependentsAndPaths() throws {
        try persistKnowledge(
            title: "ATP Energy",
            concepts: [
                makeConcept(id: "atp", name: "ATP", aliases: ["Adenosine Triphosphate", "adenosine-triphosphate"]),
                makeConcept(id: "mitochondria-a", name: "Mitochondria")
            ],
            relationships: [
                makeRelationship(id: "atp-mito", sourceID: "atp", targetID: "mitochondria-a", kind: .produces)
            ]
        )
        try persistKnowledge(
            title: "Organelles",
            concepts: [
                makeConcept(id: "mitochondria-b", name: "mitochondria"),
                makeConcept(id: "organelle", name: "Organelle")
            ],
            relationships: [
                makeRelationship(id: "mito-organelle", sourceID: "mitochondria-b", targetID: "organelle", kind: .partOf)
            ]
        )
        try persistKnowledge(
            title: "Cell Structure",
            concepts: [
                makeConcept(id: "cell", name: "Cell Structure"),
                makeConcept(id: "mitochondria-c", name: "Mitochondria"),
                makeConcept(id: "organelle-prereq", name: "Organelle")
            ],
            relationships: [
                makeRelationship(id: "mito-requires-organelle", sourceID: "mitochondria-c", targetID: "organelle-prereq", kind: .requires)
            ]
        )

        let context = builder.buildContext(query: "Explain Adenosine Triphosphate", maxConcepts: 10)
        let names = context.concepts.map(\.canonicalName)

        XCTAssertTrue(names.contains("ATP"))
        XCTAssertTrue(names.contains("Mitochondria"))
        XCTAssertTrue(names.contains("Organelle"))
        XCTAssertTrue(context.relationships.contains { $0.relationType == KnowledgeRelationshipKind.produces.rawValue })
        XCTAssertTrue(context.prerequisiteChains.contains { $0.contains("Organelle") && $0.contains("Mitochondria") })
        XCTAssertTrue(context.paths.contains { path in
            path.nodes.map(\.canonicalName).contains("ATP")
                && path.nodes.map(\.canonicalName).contains("Organelle")
        })
        XCTAssertEqual(context.explanations.first { $0.conceptName == "ATP" }?.aliases.contains("Adenosine Triphosphate"), true)
    }

    func testGraphPromptRepresentationIsStructuredTextNotJSON() throws {
        try persistKnowledge(
            title: "ATP",
            concepts: [
                makeConcept(id: "atp", name: "ATP"),
                makeConcept(id: "mitochondria", name: "Mitochondria")
            ],
            relationships: [
                makeRelationship(id: "atp-mito", sourceID: "atp", targetID: "mitochondria", kind: .produces)
            ]
        )

        let context = builder.buildContext(query: "ATP", maxConcepts: 4)
        let rendered = context.graphPromptRepresentation()

        XCTAssertTrue(rendered.contains("Knowledge Graph"))
        XCTAssertTrue(rendered.contains("ATP"))
        XCTAssertTrue(rendered.contains("PRODUCES -> Mitochondria"))
        XCTAssertFalse(rendered.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"))
    }

    func testContextBuilderInjectsGraphContextIntoKnowledgeContext() throws {
        try persistKnowledge(
            title: "ATP",
            concepts: [
                makeConcept(id: "atp", name: "ATP", aliases: ["Adenosine Triphosphate"]),
                makeConcept(id: "mitochondria", name: "Mitochondria")
            ],
            relationships: [
                makeRelationship(id: "atp-mito", sourceID: "atp", targetID: "mitochondria", kind: .produces)
            ]
        )
        let contextBuilder = ContextBuilder(
            knowledgeRepository: knowledgeRepository,
            studyRepository: StudyRepository(database: database),
            studentConceptService: StudentConceptService(repository: StudentConceptRepository(studyRepository: StudyRepository(database: database))),
            hybridRetriever: HybridRetriever(
                lexicalRetriever: LexicalRetriever(noteRepository: noteRepository, knowledgeRepository: knowledgeRepository),
                graphRetriever: GraphRetriever(knowledgeRepository: knowledgeRepository),
                vectorRetriever: VectorRetriever.shared
            ),
            graphContextBuilder: builder
        )

        let context = contextBuilder.build(title: "ATP", text: "Explain ATP")

        XCTAssertEqual(context.graphContext?.concepts.contains { $0.canonicalName == "ATP" }, true)
        XCTAssertTrue(context.graphPromptRepresentation().contains("Knowledge Graph"))
    }

    @discardableResult
    private func persistKnowledge(title: String, concepts: [KnowledgeConcept], relationships: [KnowledgeRelationship]) throws -> UUID {
        let noteID = UUID()
        let now = ISO8601DateFormatter().string(from: Date())
        try database.execute(
            """
            INSERT INTO notes (id, folder_id, title, content, created_at, updated_at, note_order, study_data_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(noteID.uuidString),
                .text(folderID.uuidString),
                .text(title),
                .text(title),
                .text(now),
                .text(now),
                .integer(0),
                .text("{}")
            ]
        )

        var extraction = StructuredKnowledge(title: title)
        extraction.concepts = concepts
        extraction.relationships = relationships
        try knowledgeRepository.persist(
            noteID: noteID,
            noteTitle: title,
            noteContent: title,
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

    private func makeRelationship(id: String, sourceID: String, targetID: String, kind: KnowledgeRelationshipKind) -> KnowledgeRelationship {
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
