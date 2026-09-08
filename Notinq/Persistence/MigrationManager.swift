import Foundation

final class MigrationManager {
    static let shared = MigrationManager()

    private let defaults = UserDefaults.standard
    private let migrationKey = "notinq.sqlite.legacyNotesMigrated"

    private init() {}

    func migrateIfNeeded(database: SQLiteDatabase) throws {
        guard defaults.bool(forKey: migrationKey) == false else { return }

        let legacyURL = legacyNotesURL()
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        let data = try Data(contentsOf: legacyURL)
        let decoder = JSONDecoder()
        let payload = try decoder.decode(LegacyNotesStoragePayload.self, from: data)
        let repository = NoteRepository(
            database: database,
            migrationManager: self,
            studyRepository: StudyRepository(database: database),
            performMigration: false
        )
        try repository.replaceFolders(payload.folders)
        for folder in payload.folders {
            for note in folder.notes {
                KnowledgeService.shared.ingest(note: KnowledgeIngestionRequest(
                    noteID: note.id,
                    title: note.title,
                    content: note.content,
                    updatedAt: note.updatedAt
                ))
            }
        }
        defaults.set(true, forKey: migrationKey)
    }

    func markMigrationComplete() {
        defaults.set(true, forKey: migrationKey)
    }

    private func legacyNotesURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Notinq", isDirectory: true)
            .appendingPathComponent("lumora-notes.json", isDirectory: false)
    }
}

private struct LegacyNotesStoragePayload: Codable {
    var folders: [NoteFolder]
    var selectedFolderID: UUID?
    var selectedNoteID: UUID?
}
