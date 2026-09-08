import Foundation

protocol NoteRepositoryProtocol {
    func loadFolders() throws -> [NoteFolder]
    func replaceFolders(_ folders: [NoteFolder]) throws
    func saveFolders(_ folders: [NoteFolder]) throws
}

final class NoteRepository: NoteRepositoryProtocol {
    static let shared = NoteRepository()

    private let database: SQLiteDatabase
    private let migrationManager: MigrationManager
    private let studyRepository: StudyRepository

    init(
        database: SQLiteDatabase = SQLiteDatabase.makeDefault(),
        migrationManager: MigrationManager = .shared,
        studyRepository: StudyRepository? = nil,
        performMigration: Bool = true
    ) {
        self.database = database
        self.migrationManager = migrationManager
        self.studyRepository = studyRepository ?? StudyRepository(database: database)
        try? createSchemaIfNeeded()
        if performMigration {
            try? migrationManager.migrateIfNeeded(database: database)
        }
    }

    func loadFolders() throws -> [NoteFolder] {
        try createSchemaIfNeeded()

        let folderRows = try database.fetch("SELECT id, title, sort_order FROM folders ORDER BY sort_order ASC")
        let noteRows = try database.fetch("SELECT id, folder_id, title, content, created_at, updated_at, study_data_json, note_order FROM notes ORDER BY note_order ASC")

        let notesByFolder = Dictionary(grouping: noteRows, by: { $0.string("folder_id") ?? "" })
        return folderRows.enumerated().map { index, folderRow in
            let folderID = UUID(uuidString: folderRow.string("id") ?? "") ?? UUID()
            let folderTitle = folderRow.string("title") ?? "Folder \(index + 1)"
            let folderNotes = notesByFolder[folderRow.string("id") ?? "", default: []].map { note(from: $0) }
            return NoteFolder(id: folderID, title: folderTitle, notes: folderNotes)
        }
    }

    func replaceFolders(_ folders: [NoteFolder]) throws {
        try saveFolders(folders)
    }

    func saveFolders(_ folders: [NoteFolder]) throws {
        try createSchemaIfNeeded()
        try database.transaction {
            try database.execute("DELETE FROM notes")
            try database.execute("DELETE FROM folders")

            for (folderIndex, folder) in folders.enumerated() {
                try database.execute(
                    "INSERT INTO folders (id, title, sort_order) VALUES (?, ?, ?)",
                    bindings: [
                        .text(folder.id.uuidString),
                        .text(folder.title),
                        .integer(Int64(folderIndex))
                    ]
                )

                for (noteIndex, note) in folder.notes.enumerated() {
                    let studyDataJSON = (try? Self.encodeStudyData(note.studyData)) ?? "{}"
                    try database.execute(
                        "INSERT INTO notes (id, folder_id, title, content, created_at, updated_at, note_order, study_data_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                        bindings: [
                            .text(note.id.uuidString),
                            .text(folder.id.uuidString),
                            .text(note.title),
                            .text(note.content),
                            .text(Self.string(from: note.updatedAt)),
                            .text(Self.string(from: note.updatedAt)),
                            .integer(Int64(noteIndex)),
                            .text(studyDataJSON)
                        ]
                    )
                }
            }
        }

        try rebuildNotesFTS()

        for folder in folders {
            for note in folder.notes {
                try? studyRepository.persist(noteID: note.id, noteTitle: note.title, studyData: note.studyData)
            }
        }
    }

    func searchNotes(query: String, limit: Int = 12) throws -> [NoteSearchRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return try recentNotes(limit: limit)
        }

        return try database.fetch(
            """
            SELECT n.id, n.folder_id, n.title, n.content, n.updated_at, f.title AS folder_title, bm25(notes_fts) AS rank
            FROM notes_fts
            JOIN notes n ON n.id = notes_fts.note_id
            JOIN folders f ON f.id = n.folder_id
            WHERE notes_fts MATCH ?
            ORDER BY rank ASC
            LIMIT ?
            """,
            bindings: [.text(trimmed), .integer(Int64(limit))]
        ).compactMap { row in
            guard
                let noteID = UUID(uuidString: row.string("id") ?? ""),
                let folderID = UUID(uuidString: row.string("folder_id") ?? ""),
                let folderTitle = row.string("folder_title"),
                let noteTitle = row.string("title")
            else { return nil }

            let content = row.string("content") ?? ""
            let rawScore = row.double("rank") ?? 0
            return NoteSearchRecord(
                noteID: noteID,
                folderID: folderID,
                folderTitle: folderTitle,
                noteTitle: noteTitle,
                snippet: Self.snippet(from: content, query: trimmed),
                content: content,
                updatedAt: Self.date(from: row.string("updated_at")) ?? Date(),
                rank: -rawScore
            )
        }
    }

    func recentNotes(limit: Int = 12) throws -> [NoteSearchRecord] {
        try database.fetch(
            """
            SELECT n.id, n.folder_id, n.title, n.content, n.updated_at, f.title AS folder_title
            FROM notes n
            JOIN folders f ON f.id = n.folder_id
            ORDER BY n.updated_at DESC
            LIMIT ?
            """,
            bindings: [.integer(Int64(limit))]
        ).compactMap { row in
            guard
                let noteID = UUID(uuidString: row.string("id") ?? ""),
                let folderID = UUID(uuidString: row.string("folder_id") ?? ""),
                let folderTitle = row.string("folder_title"),
                let noteTitle = row.string("title")
            else { return nil }

            let content = row.string("content") ?? ""
            return NoteSearchRecord(
                noteID: noteID,
                folderID: folderID,
                folderTitle: folderTitle,
                noteTitle: noteTitle,
                snippet: Self.snippet(from: content, query: ""),
                content: content,
                updatedAt: Self.date(from: row.string("updated_at")) ?? Date(),
                rank: 0.1
            )
        }
    }

    private func createSchemaIfNeeded() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS folders (
            id TEXT PRIMARY KEY NOT NULL,
            title TEXT NOT NULL,
            sort_order INTEGER NOT NULL DEFAULT 0
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY NOT NULL,
            folder_id TEXT NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            note_order INTEGER NOT NULL DEFAULT 0,
            study_data_json TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY(folder_id) REFERENCES folders(id) ON DELETE CASCADE
        )
        """)

        try database.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
            note_id UNINDEXED,
            title,
            content
        )
        """)
    }

    private func rebuildNotesFTS() throws {
        try database.execute("DELETE FROM notes_fts")
        let rows = try database.fetch("SELECT id, title, content FROM notes ORDER BY updated_at ASC")
        for row in rows {
            guard let noteID = row.string("id") else { continue }
            try database.execute(
                "INSERT INTO notes_fts (note_id, title, content) VALUES (?, ?, ?)",
                bindings: [
                    .text(noteID),
                    .text(row.string("title") ?? ""),
                    .text(row.string("content") ?? "")
                ]
            )
        }
    }

    private func note(from row: SQLiteRow) -> NoteFile {
        let noteID = UUID(uuidString: row.string("id") ?? "") ?? UUID()
        let title = row.string("title") ?? "Untitled Note"
        let content = row.string("content") ?? ""
        let updatedAt = Self.date(from: row.string("updated_at")) ?? Date()
        let studyDataJSON = row.string("study_data_json")
        let repositoryStudyData = try? studyRepository.studyData(for: noteID, noteTitle: title)
        let studyData = repositoryStudyData?.hasMaterials == true
            ? repositoryStudyData!
            : Self.decodeStudyData(studyDataJSON)
        return NoteFile(id: noteID, title: title, content: content, updatedAt: updatedAt, studyData: studyData)
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

    private static func encodeStudyData(_ studyData: NoteStudyData) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(studyData)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeStudyData(_ json: String?) -> NoteStudyData {
        guard let json, let data = json.data(using: .utf8) else { return NoteStudyData() }
        return (try? JSONDecoder().decode(NoteStudyData.self, from: data)) ?? NoteStudyData()
    }

    private static func snippet(from content: String, query: String) -> String {
        let sanitized = content.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return "Empty note" }
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

    private static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }
}
