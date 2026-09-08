import Foundation

struct NoteSearchRecord: Codable, Equatable, Sendable {
    var noteID: UUID
    var folderID: UUID
    var folderTitle: String
    var noteTitle: String
    var snippet: String
    var content: String
    var updatedAt: Date
    var rank: Double
}

struct ChunkSearchRecord: Codable, Equatable, Sendable {
    var noteID: UUID
    var noteTitle: String
    var chunkID: String
    var sectionName: String
    var content: String
    var snippet: String
    var updatedAt: Date
    var rank: Double
}

struct ConceptSearchRecord: Codable, Equatable, Sendable {
    var conceptID: String
    var canonicalName: String
    var description: String
    var aliases: [String]
    var noteIDs: [UUID]
    var rank: Double
}

final class KnowledgeRepository {
    static let shared = KnowledgeRepository()

    private let database: SQLiteDatabase
    private let queue = DispatchQueue(label: "notinq.knowledge.repository", qos: .userInitiated)

    init(database: SQLiteDatabase = SQLiteDatabase.makeDefault()) {
        self.database = database
        try? createSchemaIfNeeded()
    }

    func persist(noteID: UUID, noteTitle: String, noteContent: String, chunks: [SemanticChunk], extraction: StructuredKnowledge?) throws {
        try queue.sync {
            try database.transaction {
                try deleteExistingData(noteID: noteID)
                try insertDocument(noteID: noteID, noteTitle: noteTitle, noteContent: noteContent)
                try insertChunks(noteID: noteID, noteTitle: noteTitle, chunks: chunks)

                if let extraction {
                    try insertExtraction(noteID: noteID, extraction: extraction)
                }
            }

            try rebuildFTSIndexes()
        }
    }

    func remove(noteID: UUID) throws {
        try queue.sync {
            try database.transaction {
                try deleteExistingData(noteID: noteID)
            }
            try rebuildFTSIndexes()
        }
    }

    func chunks(for noteID: UUID) throws -> [KnowledgeChunkRecord] {
        try queue.sync {
            let rows = try database.fetch(
                "SELECT id, note_id, document_id, chunk_index, section_name, chunk_text, start_offset, end_offset FROM chunks WHERE note_id = ? ORDER BY chunk_index ASC",
                bindings: [.text(noteID.uuidString)]
            )
            return rows.compactMap { row in
                guard
                    let id = row.string("id"),
                    let noteID = UUID(uuidString: row.string("note_id") ?? ""),
                    let documentID = row.string("document_id"),
                    let sectionName = row.string("section_name"),
                    let content = row.string("chunk_text")
                else { return nil }

                return KnowledgeChunkRecord(
                    id: id,
                    noteID: noteID,
                    documentID: documentID,
                    chunkIndex: row.int("chunk_index") ?? 0,
                    sectionName: sectionName,
                    content: content,
                    startLine: row.int("start_offset") ?? 0,
                    endLine: row.int("end_offset") ?? 0,
                    provenanceNoteID: noteID
                )
            }
        }
    }

    func concepts(for noteID: UUID) throws -> [CanonicalConceptRecord] {
        try queue.sync {
            let rows = try database.fetch(
                "SELECT id, canonical_name, description, confidence FROM concepts WHERE source_note_id = ? ORDER BY confidence DESC, canonical_name ASC",
                bindings: [.text(noteID.uuidString)]
            )

            return rows.compactMap { row in
                guard let id = row.string("id"), let canonicalName = row.string("canonical_name") else { return nil }
                return CanonicalConceptRecord(
                    id: id,
                    canonicalName: canonicalName,
                    aliases: (try? aliasesForConceptID(id)) ?? [],
                    sourceReferences: [noteID.uuidString],
                    confidence: row.double("confidence") ?? 0,
                    description: row.string("description") ?? ""
                )
            }
        }
    }

    func relationships(for noteID: UUID) throws -> [KnowledgeRelationshipRecord] {
        try queue.sync {
            let rows = try database.fetch(
                "SELECT id, source_concept_id, target_concept_id, relation_type, confidence, provenance_json FROM relationships WHERE source_note_id = ? ORDER BY confidence DESC",
                bindings: [.text(noteID.uuidString)]
            )
            return rows.compactMap { row in
                guard
                    let id = row.string("id"),
                    let source = row.string("source_concept_id"),
                    let target = row.string("target_concept_id"),
                    let relationType = row.string("relation_type")
                else { return nil }

                return KnowledgeRelationshipRecord(
                    id: id,
                    sourceConceptID: source,
                    targetConceptID: target,
                    relationType: relationType,
                    confidence: row.double("confidence") ?? 0,
                    provenance: Self.decodeStringArray(row.string("provenance_json"))
                )
            }
        }
    }

    func searchChunks(query: String, limit: Int = 10) throws -> [ChunkSearchRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try recentChunks(limit: limit)
        }

        return try queue.sync {
            let rows = try database.fetch(
                """
                SELECT c.id, c.note_id, c.section_name, c.chunk_text, c.created_at AS updated_at, n.title AS note_title, bm25(chunks_fts) AS rank
                FROM chunks_fts
                JOIN chunks c ON c.id = chunks_fts.chunk_id
                JOIN notes n ON n.id = c.note_id
                WHERE chunks_fts MATCH ?
                ORDER BY rank ASC
                LIMIT ?
                """,
                bindings: [.text(trimmed), .integer(Int64(limit))]
            )

            return rows.compactMap { row in
                guard
                    let noteID = UUID(uuidString: row.string("note_id") ?? ""),
                    let chunkID = row.string("id"),
                    let noteTitle = row.string("note_title")
                else { return nil }

                let rawScore = row.double("rank") ?? 0
                return ChunkSearchRecord(
                    noteID: noteID,
                    noteTitle: noteTitle,
                    chunkID: chunkID,
                    sectionName: row.string("section_name") ?? "",
                    content: row.string("chunk_text") ?? "",
                    snippet: Self.snippet(from: row.string("chunk_text") ?? "", query: trimmed),
                    updatedAt: Self.date(from: row.string("updated_at")) ?? Date(),
                    rank: -rawScore
                )
            }
        }
    }

    func searchConcepts(query: String, limit: Int = 10) throws -> [ConceptSearchRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try recentConcepts(limit: limit)
        }

        return try queue.sync {
            let rows = try database.fetch(
                """
                SELECT c.id, c.canonical_name, c.description, c.confidence, bm25(concepts_fts) AS rank
                FROM concepts_fts
                JOIN concepts c ON c.id = concepts_fts.concept_id
                WHERE concepts_fts MATCH ?
                ORDER BY rank ASC
                LIMIT ?
                """,
                bindings: [.text(trimmed), .integer(Int64(limit))]
            )

            return rows.compactMap { row in
                guard let conceptID = row.string("id"), let canonicalName = row.string("canonical_name") else { return nil }
                let rawScore = row.double("rank") ?? 0
                return ConceptSearchRecord(
                    conceptID: conceptID,
                    canonicalName: canonicalName,
                    description: row.string("description") ?? "",
                    aliases: (try? aliasesForConceptID(conceptID)) ?? [],
                    noteIDs: (try? noteIDsForConceptID(conceptID)) ?? [],
                    rank: -rawScore
                )
            }
        }
    }

    func noteConceptIDs(for noteID: UUID) throws -> [String] {
        try queue.sync {
            let rows = try database.fetch(
                "SELECT concept_id FROM note_concepts WHERE note_id = ? ORDER BY confidence DESC",
                bindings: [.text(noteID.uuidString)]
            )
            return rows.compactMap { $0.string("concept_id") }
        }
    }

    func noteIDs(forConceptID conceptID: String) throws -> [UUID] {
        try queue.sync {
            let rows = try database.fetch(
                "SELECT note_id FROM note_concepts WHERE concept_id = ? ORDER BY confidence DESC",
                bindings: [.text(conceptID)]
            )
            return rows.compactMap { UUID(uuidString: $0.string("note_id") ?? "") }
        }
    }

    func searchRecentChunks(limit: Int = 10) throws -> [ChunkSearchRecord] {
        try recentChunks(limit: limit)
    }

    func searchRecentConcepts(limit: Int = 10) throws -> [ConceptSearchRecord] {
        try recentConcepts(limit: limit)
    }

    func noteTitle(for noteID: UUID) throws -> String? {
        try queue.sync {
            let rows = try database.fetch(
                "SELECT title FROM notes WHERE id = ? LIMIT 1",
                bindings: [.text(noteID.uuidString)]
            )
            return rows.first?.string("title")
        }
    }

    func concept(for conceptID: String) throws -> CanonicalConceptRecord? {
        try queue.sync {
            let rows = try database.fetch(
                "SELECT id, canonical_name, description, confidence, source_note_id FROM concepts WHERE id = ? LIMIT 1",
                bindings: [.text(conceptID)]
            )
            guard let row = rows.first, let id = row.string("id"), let canonicalName = row.string("canonical_name") else {
                return nil
            }

            let noteID = UUID(uuidString: row.string("source_note_id") ?? "")
            return CanonicalConceptRecord(
                id: id,
                canonicalName: canonicalName,
                aliases: (try? aliasesForConceptID(id)) ?? [],
                sourceReferences: noteID.map { [$0.uuidString] } ?? [],
                confidence: row.double("confidence") ?? 0,
                description: row.string("description") ?? ""
            )
        }
    }

    func relationships(containing conceptID: String, limit: Int = 20) throws -> [KnowledgeRelationshipRecord] {
        try queue.sync {
            let rows = try database.fetch(
                """
                SELECT id, source_concept_id, target_concept_id, relation_type, confidence, provenance_json
                FROM relationships
                WHERE source_concept_id = ? OR target_concept_id = ?
                ORDER BY confidence DESC
                LIMIT ?
                """,
                bindings: [.text(conceptID), .text(conceptID), .integer(Int64(limit))]
            )

            return rows.compactMap { row in
                guard
                    let id = row.string("id"),
                    let source = row.string("source_concept_id"),
                    let target = row.string("target_concept_id"),
                    let relationType = row.string("relation_type")
                else { return nil }

                return KnowledgeRelationshipRecord(
                    id: id,
                    sourceConceptID: source,
                    targetConceptID: target,
                    relationType: relationType,
                    confidence: row.double("confidence") ?? 0,
                    provenance: Self.decodeStringArray(row.string("provenance_json"))
                )
            }
        }
    }

    private func createSchemaIfNeeded() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS documents (
            id TEXT PRIMARY KEY NOT NULL,
            note_id TEXT NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS chunks (
            id TEXT PRIMARY KEY NOT NULL,
            document_id TEXT NOT NULL,
            note_id TEXT NOT NULL,
            chunk_index INTEGER NOT NULL,
            section_name TEXT NOT NULL,
            chunk_text TEXT NOT NULL,
            start_offset INTEGER NOT NULL,
            end_offset INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            provenance_json TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE,
            FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS concepts (
            id TEXT PRIMARY KEY NOT NULL,
            source_note_id TEXT NOT NULL,
            canonical_name TEXT NOT NULL,
            description TEXT NOT NULL,
            confidence REAL NOT NULL DEFAULT 0.0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            provenance_json TEXT NOT NULL DEFAULT '{}'
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS concept_aliases (
            id TEXT PRIMARY KEY NOT NULL,
            note_id TEXT NOT NULL,
            concept_id TEXT NOT NULL,
            alias TEXT NOT NULL,
            provenance_json TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY(concept_id) REFERENCES concepts(id) ON DELETE CASCADE
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS note_concepts (
            note_id TEXT NOT NULL,
            concept_id TEXT NOT NULL,
            concept_title TEXT NOT NULL,
            confidence REAL NOT NULL DEFAULT 0.0,
            provenance_json TEXT NOT NULL DEFAULT '{}',
            PRIMARY KEY (note_id, concept_id),
            FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE,
            FOREIGN KEY(concept_id) REFERENCES concepts(id) ON DELETE CASCADE
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS relationships (
            id TEXT PRIMARY KEY NOT NULL,
            source_note_id TEXT NOT NULL,
            source_concept_id TEXT NOT NULL,
            target_concept_id TEXT NOT NULL,
            relation_type TEXT NOT NULL,
            confidence REAL NOT NULL DEFAULT 0.0,
            provenance_json TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY(source_concept_id) REFERENCES concepts(id) ON DELETE CASCADE,
            FOREIGN KEY(target_concept_id) REFERENCES concepts(id) ON DELETE CASCADE
        )
        """)

        try database.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
            chunk_id UNINDEXED,
            note_id UNINDEXED,
            note_title,
            section_name,
            chunk_text
        )
        """)

        try database.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS concepts_fts USING fts5(
            concept_id UNINDEXED,
            canonical_name,
            description,
            aliases
        )
        """)
    }

    private func deleteExistingData(noteID: UUID) throws {
        let noteIDString = noteID.uuidString
        try database.execute("DELETE FROM chunks WHERE note_id = ?", bindings: [.text(noteIDString)])
        try database.execute("DELETE FROM note_concepts WHERE note_id = ?", bindings: [.text(noteIDString)])
        try database.execute("DELETE FROM concept_aliases WHERE note_id = ?", bindings: [.text(noteIDString)])
        try database.execute("DELETE FROM relationships WHERE source_note_id = ?", bindings: [.text(noteIDString)])
        try database.execute("DELETE FROM concepts WHERE source_note_id = ?", bindings: [.text(noteIDString)])
        try database.execute("DELETE FROM documents WHERE note_id = ?", bindings: [.text(noteIDString)])
    }

    private func insertDocument(noteID: UUID, noteTitle: String, noteContent: String) throws {
        let timestamp = Self.string(from: Date())
        try database.execute(
            "INSERT INTO documents (id, note_id, title, content, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(noteID.uuidString),
                .text(noteID.uuidString),
                .text(noteTitle),
                .text(noteContent),
                .text(timestamp),
                .text(timestamp)
            ]
        )
    }

    private func insertChunks(noteID: UUID, noteTitle: String, chunks: [SemanticChunk]) throws {
        let timestamp = Self.string(from: Date())
        for chunk in chunks {
            try database.execute(
                "INSERT INTO chunks (id, document_id, note_id, chunk_index, section_name, chunk_text, start_offset, end_offset, created_at, provenance_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(chunk.id),
                    .text(noteID.uuidString),
                    .text(noteID.uuidString),
                    .integer(Int64(chunk.chunkIndex)),
                    .text(chunk.sectionName),
                    .text(chunk.content),
                    .integer(Int64(chunk.startLine)),
                    .integer(Int64(chunk.endLine)),
                    .text(timestamp),
                    .text(Self.encodeDictionary([
                        "noteID": noteID.uuidString,
                        "noteTitle": noteTitle,
                        "chunkIndex": String(chunk.chunkIndex)
                    ]))
                ]
            )
        }
    }

    private func insertExtraction(noteID: UUID, extraction: StructuredKnowledge) throws {
        let timestamp = Self.string(from: Date())
        try database.execute("DELETE FROM note_concepts WHERE note_id = ?", bindings: [.text(noteID.uuidString)])
        try database.execute("DELETE FROM concept_aliases WHERE note_id = ?", bindings: [.text(noteID.uuidString)])
        try database.execute("DELETE FROM relationships WHERE source_note_id = ?", bindings: [.text(noteID.uuidString)])
        try database.execute("DELETE FROM concepts WHERE source_note_id = ?", bindings: [.text(noteID.uuidString)])

        for concept in extraction.concepts {
            let conceptID = concept.id.isEmpty ? UUID().uuidString : concept.id
            try database.execute(
                "INSERT INTO concepts (id, source_note_id, canonical_name, description, confidence, created_at, updated_at, provenance_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(conceptID),
                    .text(noteID.uuidString),
                    .text(concept.name),
                    .text(concept.definition),
                    .real(concept.confidence),
                    .text(timestamp),
                    .text(timestamp),
                    .text(Self.encodeDictionary([
                        "noteID": noteID.uuidString,
                        "section": concept.section,
                        "source": concept.source,
                        "category": concept.category
                    ]))
                ]
            )

            try database.execute(
                "INSERT OR REPLACE INTO note_concepts (note_id, concept_id, concept_title, confidence, provenance_json) VALUES (?, ?, ?, ?, ?)",
                bindings: [
                    .text(noteID.uuidString),
                    .text(conceptID),
                    .text(concept.name),
                    .real(concept.confidence),
                    .text(Self.encodeDictionary([
                        "noteID": noteID.uuidString,
                        "source": concept.source,
                        "concept": concept.name
                    ]))
                ]
            )

            for alias in concept.aliases where alias.isEmpty == false {
                try database.execute(
                    "INSERT INTO concept_aliases (id, note_id, concept_id, alias, provenance_json) VALUES (?, ?, ?, ?, ?)",
                    bindings: [
                        .text(UUID().uuidString),
                        .text(noteID.uuidString),
                        .text(conceptID),
                        .text(alias),
                        .text(Self.encodeDictionary([
                            "noteID": noteID.uuidString,
                            "conceptID": conceptID,
                            "alias": alias
                        ]))
                    ]
                )
            }
        }

        for relationship in extraction.relationships {
            let relationType = relationship.relation.isEmpty ? KnowledgeRelationshipKind.relatedTo.rawValue : relationship.relation
            try database.execute(
                "INSERT INTO relationships (id, source_note_id, source_concept_id, target_concept_id, relation_type, confidence, provenance_json) VALUES (?, ?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(relationship.id.isEmpty ? UUID().uuidString : relationship.id),
                    .text(noteID.uuidString),
                    .text(relationship.sourceID),
                    .text(relationship.targetID),
                    .text(relationType),
                    .real(relationship.confidence),
                    .text(Self.encodeDictionary([
                        "noteID": noteID.uuidString,
                        "source": relationship.sourceID,
                        "target": relationship.targetID
                    ]))
                ]
            )
        }
    }

    private func rebuildFTSIndexes() throws {
        try database.execute("DELETE FROM chunks_fts")
        try database.execute("DELETE FROM concepts_fts")

        let chunkRows = try database.fetch(
            "SELECT c.id, c.note_id, c.section_name, c.chunk_text, n.title AS note_title FROM chunks c JOIN notes n ON n.id = c.note_id ORDER BY c.created_at ASC"
        )
        for row in chunkRows {
            guard
                let chunkID = row.string("id"),
                let noteID = row.string("note_id"),
                let noteTitle = row.string("note_title")
            else { continue }

            try database.execute(
                "INSERT INTO chunks_fts (chunk_id, note_id, note_title, section_name, chunk_text) VALUES (?, ?, ?, ?, ?)",
                bindings: [
                    .text(chunkID),
                    .text(noteID),
                    .text(noteTitle),
                    .text(row.string("section_name") ?? ""),
                    .text(row.string("chunk_text") ?? "")
                ]
            )
        }

        let conceptRows = try database.fetch(
            "SELECT c.id, c.canonical_name, c.description, GROUP_CONCAT(a.alias, ' ') AS aliases FROM concepts c LEFT JOIN concept_aliases a ON a.concept_id = c.id GROUP BY c.id ORDER BY c.updated_at ASC"
        )
        for row in conceptRows {
            guard let conceptID = row.string("id") else { continue }
            try database.execute(
                "INSERT INTO concepts_fts (concept_id, canonical_name, description, aliases) VALUES (?, ?, ?, ?)",
                bindings: [
                    .text(conceptID),
                    .text(row.string("canonical_name") ?? ""),
                    .text(row.string("description") ?? ""),
                    .text(row.string("aliases") ?? "")
                ]
            )
        }
    }

    private func recentChunks(limit: Int) throws -> [ChunkSearchRecord] {
        try queue.sync {
            let rows = try database.fetch(
                """
                SELECT c.id, c.note_id, c.section_name, c.chunk_text, c.created_at, n.title AS note_title
                FROM chunks c
                JOIN notes n ON n.id = c.note_id
                ORDER BY c.created_at DESC
                LIMIT ?
                """,
                bindings: [.integer(Int64(limit))]
            )

            return rows.compactMap { row in
                guard
                    let noteID = UUID(uuidString: row.string("note_id") ?? ""),
                    let chunkID = row.string("id"),
                    let noteTitle = row.string("note_title")
                else { return nil }

                return ChunkSearchRecord(
                    noteID: noteID,
                    noteTitle: noteTitle,
                    chunkID: chunkID,
                    sectionName: row.string("section_name") ?? "",
                    content: row.string("chunk_text") ?? "",
                    snippet: Self.snippet(from: row.string("chunk_text") ?? "", query: ""),
                    updatedAt: Self.date(from: row.string("created_at")) ?? Date(),
                    rank: 0.1
                )
            }
        }
    }

    private func recentConcepts(limit: Int) throws -> [ConceptSearchRecord] {
        try queue.sync {
            let rows = try database.fetch(
                "SELECT id, canonical_name, description, confidence FROM concepts ORDER BY updated_at DESC LIMIT ?",
                bindings: [.integer(Int64(limit))]
            )
            return rows.compactMap { row in
                guard let conceptID = row.string("id"), let canonicalName = row.string("canonical_name") else { return nil }
                return ConceptSearchRecord(
                    conceptID: conceptID,
                    canonicalName: canonicalName,
                    description: row.string("description") ?? "",
                    aliases: (try? aliasesForConceptID(conceptID)) ?? [],
                    noteIDs: (try? noteIDsForConceptID(conceptID)) ?? [],
                    rank: row.double("confidence") ?? 0.1
                )
            }
        }
    }

    private func aliases(forConceptID conceptID: String) throws -> [String] {
        try queue.sync {
            try aliasesForConceptID(conceptID)
        }
    }

    private func aliasesForConceptID(_ conceptID: String) throws -> [String] {
        let rows = try database.fetch(
            "SELECT alias FROM concept_aliases WHERE concept_id = ? ORDER BY alias ASC",
            bindings: [.text(conceptID)]
        )
        return rows.compactMap { $0.string("alias") }
    }

    private func noteIDsForConceptID(_ conceptID: String) throws -> [UUID] {
        let rows = try database.fetch(
            "SELECT note_id FROM note_concepts WHERE concept_id = ? ORDER BY confidence DESC",
            bindings: [.text(conceptID)]
        )
        return rows.compactMap { UUID(uuidString: $0.string("note_id") ?? "") }
    }

    private static func snippet(from content: String, query: String) -> String {
        let sanitized = content.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return "Empty result" }
        guard !query.isEmpty else {
            return String(sanitized.prefix(180)) + (sanitized.count > 180 ? "..." : "")
        }

        guard let range = sanitized.lowercased().range(of: query.lowercased()) else {
            return String(sanitized.prefix(180)) + (sanitized.count > 180 ? "..." : "")
        }

        let lowerBound = sanitized.distance(from: sanitized.startIndex, to: range.lowerBound)
        let start = max(0, lowerBound - 48)
        let end = min(sanitized.count, lowerBound + 132)
        let snippet = String(sanitized[sanitized.index(sanitized.startIndex, offsetBy: start)..<sanitized.index(sanitized.startIndex, offsetBy: end)])
        return (start > 0 ? "..." : "") + snippet + (end < sanitized.count ? "..." : "")
    }

    private static func encodeDictionary(_ dictionary: [String: String]) -> String {
        let data = (try? JSONEncoder().encode(dictionary)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeStringArray(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
}
