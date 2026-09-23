import Foundation
@testable import Notinq

final class AdaptiveGraphTestFixture {
    let databaseURL: URL
    let database: SQLiteDatabase
    let folderID = UUID()
    let studyRepository: StudyRepository
    let noteRepository: NoteRepository
    let knowledgeRepository: KnowledgeRepository

    init() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notinq-adaptive-graph-tests-")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        database = try SQLiteDatabase(url: databaseURL)
        studyRepository = StudyRepository(database: database)
        noteRepository = NoteRepository(database: database, studyRepository: studyRepository, performMigration: false)
        knowledgeRepository = KnowledgeRepository(database: database)
        try database.execute(
            "INSERT INTO folders (id, title, sort_order) VALUES (?, ?, ?)",
            bindings: [.text(folderID.uuidString), .text("Adaptive"), .integer(0)]
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: databaseURL)
    }

    @discardableResult
    func persist(
        title: String,
        content: String,
        concepts: [KnowledgeConcept],
        relationships: [KnowledgeRelationship]
    ) throws -> UUID {
        let noteID = UUID()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try database.execute(
            """
            INSERT INTO notes (id, folder_id, title, content, created_at, updated_at, note_order, study_data_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(noteID.uuidString),
                .text(folderID.uuidString),
                .text(title),
                .text(content),
                .text(timestamp),
                .text(timestamp),
                .integer(0),
                .text("{}")
            ]
        )

        let chunk = SemanticChunk(
            id: "chunk-\(noteID.uuidString)",
            documentID: noteID.uuidString,
            chunkIndex: 0,
            sectionName: title,
            paragraphIDs: ["p1"],
            content: content,
            startLine: 0,
            endLine: 0
        )
        var extraction = StructuredKnowledge(title: title)
        extraction.concepts = concepts
        extraction.relationships = relationships
        try knowledgeRepository.persist(
            noteID: noteID,
            noteTitle: title,
            noteContent: content,
            chunks: [chunk],
            extraction: extraction
        )
        return noteID
    }

    func concept(id: String, name: String, aliases: [String] = []) -> KnowledgeConcept {
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

    func relationship(id: String, sourceID: String, targetID: String, kind: KnowledgeRelationshipKind) -> KnowledgeRelationship {
        var relationship = KnowledgeRelationship()
        relationship.id = id
        relationship.sourceID = sourceID
        relationship.targetID = targetID
        relationship.relationKind = kind
        relationship.relation = kind.rawValue
        relationship.confidence = 0.9
        return relationship
    }

    func seedATPGraph() throws -> (noteID: UUID, atpID: String, mitochondriaID: String, respirationID: String, energyID: String, organelleID: String) {
        let atpID = UUID().uuidString
        let mitochondriaID = UUID().uuidString
        let respirationID = UUID().uuidString
        let energyID = UUID().uuidString
        let organelleID = UUID().uuidString
        let noteID = try persist(
            title: "ATP Notes",
            content: "ATP is produced by mitochondria during cellular respiration for energy production.",
            concepts: [
                concept(id: atpID, name: "ATP", aliases: ["Adenosine Triphosphate"]),
                concept(id: mitochondriaID, name: "Mitochondria"),
                concept(id: respirationID, name: "Cellular Respiration"),
                concept(id: energyID, name: "Energy Production"),
                concept(id: organelleID, name: "Organelle")
            ],
            relationships: [
                relationship(id: "atp-mito", sourceID: atpID, targetID: mitochondriaID, kind: .partOf),
                relationship(id: "atp-respiration", sourceID: atpID, targetID: respirationID, kind: .requires),
                relationship(id: "atp-energy", sourceID: atpID, targetID: energyID, kind: .produces),
                relationship(id: "mito-organelle", sourceID: mitochondriaID, targetID: organelleID, kind: .partOf)
            ]
        )
        return (noteID, atpID, mitochondriaID, respirationID, energyID, organelleID)
    }
}
