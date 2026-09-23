import Foundation

struct KnowledgeExtractionCacheEntry: Codable, Equatable, Sendable {
    var signature: String
    var updatedAt: Date
    var knowledge: StructuredKnowledge
}

final class KnowledgeExtractionCache {
    static let shared = KnowledgeExtractionCache()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let cacheURL: URL
    private let queue = DispatchQueue(label: "notinq.ai.knowledge.cache", qos: .utility)
    private var memoryCache: [String: KnowledgeExtractionCacheEntry] = [:]

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = baseURL.appendingPathComponent("Notinq", isDirectory: true).appendingPathComponent("AI", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheURL = directory.appendingPathComponent("knowledge-extraction-cache.json")
        loadCache()
    }

    func cachedKnowledge(for signature: String) -> StructuredKnowledge? {
        queue.sync {
            if let entry = memoryCache[signature] {
                guard entry.knowledge.hasContent else {
                    memoryCache.removeValue(forKey: signature)
                    return nil
                }
                return entry.knowledge
            }
            guard let data = try? Data(contentsOf: cacheURL),
                  let stored = try? decoder.decode([String: KnowledgeExtractionCacheEntry].self, from: data),
                  let entry = stored[signature] else {
                return nil
            }
            guard entry.knowledge.hasContent else {
                return nil
            }
            memoryCache[signature] = entry
            return entry.knowledge
        }
    }

    func store(_ knowledge: StructuredKnowledge, for signature: String) {
        guard knowledge.hasContent else { return }
        queue.sync {
            let entry = KnowledgeExtractionCacheEntry(signature: signature, updatedAt: Date(), knowledge: knowledge)
            memoryCache[signature] = entry
            var stored: [String: KnowledgeExtractionCacheEntry] = [:]
            if let data = try? Data(contentsOf: cacheURL),
               let existing = try? decoder.decode([String: KnowledgeExtractionCacheEntry].self, from: data) {
                stored = existing
            }
            stored[signature] = entry
            if let data = try? encoder.encode(stored) {
                try? data.write(to: cacheURL, options: [.atomic])
            }
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
              let stored = try? decoder.decode([String: KnowledgeExtractionCacheEntry].self, from: data) else {
            return
        }
        memoryCache = stored
    }
}
