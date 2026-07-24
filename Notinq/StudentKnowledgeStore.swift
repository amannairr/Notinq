import Foundation

protocol StudentKnowledgeStoring {
    func loadSnapshot() -> StudentKnowledgeStoreSnapshot
    func saveSnapshot(_ snapshot: StudentKnowledgeStoreSnapshot)
}

final class StudentKnowledgeStore: StudentKnowledgeStoring {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func loadSnapshot() -> StudentKnowledgeStoreSnapshot {
        do {
            let data = try Data(contentsOf: storageURL)
            return try decodeSnapshot(from: data)
        } catch {
            return StudentKnowledgeStoreSnapshot()
        }
    }

    func saveSnapshot(_ snapshot: StudentKnowledgeStoreSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save student knowledge store: \(error)")
        }
    }

    private func decodeSnapshot(from data: Data) throws -> StudentKnowledgeStoreSnapshot {
        if let current = try? decoder.decode(StudentKnowledgeStoreSnapshot.self, from: data) {
            return current
        }

        if let legacy = try? decoder.decode(LegacyStudentKnowledgeStoreSnapshot.self, from: data) {
            return StudentKnowledgeStoreSnapshot(version: 1, metadata: StudentKnowledgeStoreMetadata(), concepts: legacy.concepts)
        }

        if let legacyConcepts = try? decoder.decode([StudentKnowledgeConceptRecord].self, from: data) {
            return StudentKnowledgeStoreSnapshot(version: 1, metadata: StudentKnowledgeStoreMetadata(), concepts: legacyConcepts)
        }

        return StudentKnowledgeStoreSnapshot()
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return fileManager.temporaryDirectory.appendingPathComponent("student-knowledge.json")
        }

        let directory = baseURL.appendingPathComponent("Notinq", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("student-knowledge.json")
    }
}
