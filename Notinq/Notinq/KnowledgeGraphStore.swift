import Foundation

struct KnowledgeGraphStoreSnapshot: Codable, Equatable, Sendable {
    var graphs: [KnowledgeGraph] = []
    var registry: [ConceptRegistryEntry] = []
}

struct ConceptRegistryEntry: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var description: String
    var aliases: [String]
    var primaryNoteID: UUID
    var noteIDs: [UUID]
    var confidence: Double
    var createdDate: Date
    var updatedDate: Date
    var embeddingID: String?
    var importanceScore: Double
    var difficultyScore: Double
}

final class KnowledgeGraphStore {
    private let fileName = "knowledge-graphs.json"
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func loadSnapshot() -> KnowledgeGraphStoreSnapshot {
        do {
            let data = try Data(contentsOf: storageURL)
            return try decoder.decode(KnowledgeGraphStoreSnapshot.self, from: data)
        } catch {
            return KnowledgeGraphStoreSnapshot()
        }
    }

    func saveSnapshot(_ snapshot: KnowledgeGraphStoreSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save knowledge graph store: \(error)")
        }
    }

    private var storageURL: URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = baseURL.appendingPathComponent("Notinq", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(fileName)
    }
}

