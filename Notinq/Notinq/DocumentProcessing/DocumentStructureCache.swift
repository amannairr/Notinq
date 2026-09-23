import Foundation

protocol DocumentStructureCaching: AnyObject {
    func cachedStructure(for contentHash: String) -> DocumentStructure?
    func store(_ structure: DocumentStructure, for contentHash: String)
    func removeStructure(for contentHash: String)
    func clear()
}

struct DocumentStructureCacheEntry: Codable, Equatable, Sendable {
    var contentHash: String
    var updatedAt: Date
    var structure: DocumentStructure
}

final class DocumentStructureCache: DocumentStructureCaching {
    static let shared = DocumentStructureCache()

    private let queue = DispatchQueue(label: "notinq.document.structure.cache", qos: .utility)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let cacheURL: URL
    private var memoryCache: [String: DocumentStructureCacheEntry] = [:]

    init(cacheURL: URL? = nil) {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .secondsSince1970

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .secondsSince1970

        if let cacheURL {
            self.cacheURL = cacheURL
        } else {
            let fileManager = FileManager.default
            let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
            let directory = baseDirectory.appendingPathComponent("Notinq", isDirectory: true).appendingPathComponent("DocumentProcessing", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            self.cacheURL = directory.appendingPathComponent("document-structure-cache.json")
        }

        loadCache()
    }

    func cachedStructure(for contentHash: String) -> DocumentStructure? {
        queue.sync {
            memoryCache[contentHash]?.structure
        }
    }

    func store(_ structure: DocumentStructure, for contentHash: String) {
        queue.sync {
            let entry = DocumentStructureCacheEntry(contentHash: contentHash, updatedAt: Date(), structure: structure)
            memoryCache[contentHash] = entry
            persistLocked()
        }
    }

    func removeStructure(for contentHash: String) {
        queue.sync {
            memoryCache.removeValue(forKey: contentHash)
            persistLocked()
        }
    }

    func clear() {
        queue.sync {
            memoryCache.removeAll()
            try? FileManager.default.removeItem(at: cacheURL)
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let stored = try? decoder.decode([String: DocumentStructureCacheEntry].self, from: data) else {
            return
        }
        memoryCache = stored
    }

    private func persistLocked() {
        if let data = try? encoder.encode(memoryCache) {
            try? data.write(to: cacheURL, options: [.atomic])
        }
    }
}
