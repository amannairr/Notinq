import Foundation

struct SearchRequest: Sendable {
    let query: String
    let currentNoteID: UUID?
    let folders: [NoteFolder]
}

final class SearchService {
    static let shared = SearchService()

    private let retriever: HybridRetriever

    init(retriever: HybridRetriever = .shared) {
        self.retriever = retriever
    }

    func search(_ request: SearchRequest) -> [SearchResult] {
        let folderLookup = Dictionary(uniqueKeysWithValues: request.folders.map { ($0.id, $0.title) })
        let hits = retriever.retrieve(query: request.query, limit: 32)
        let filtered = request.currentNoteID.map { currentID in
            hits.filter { $0.noteID == currentID }
        } ?? hits

        return filtered.compactMap { hit in
            SearchResult(
                retrievalHit: hit,
                folderTitle: hit.folderTitle ?? folderLookup[hit.folderID ?? UUID()] ?? folderLookup.first?.value ?? "General"
            )
        }
        .sorted {
            let lhsDirectNoteMatch = Self.isDirectNoteMatch($0, query: request.query)
            let rhsDirectNoteMatch = Self.isDirectNoteMatch($1, query: request.query)
            if lhsDirectNoteMatch != rhsDirectNoteMatch { return lhsDirectNoteMatch }
            if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private static func isDirectNoteMatch(_ result: SearchResult, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard result.sourceKind == .note, normalizedQuery.isEmpty == false else { return false }
        return result.title.lowercased().contains(normalizedQuery)
            || result.content.lowercased().contains(normalizedQuery)
            || result.preview.lowercased().contains(normalizedQuery)
    }
}
