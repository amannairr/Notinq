//
//  semanticSearch.swift
//  Notinq
//
//  Created by Aman Nair on 01/05/26.
//

import Foundation

func semanticSearch(queryEmbedding: [Float], notes: [EmbeddedNote]) -> [SearchResult] {
    notes
        .map { note in
            (note, cosineSimilarity(queryEmbedding, note.embedding))
        }
        .sorted { $0.1 > $1.1 }
        .prefix(10)
        .compactMap { item in
            let note = NoteFile(title: "Semantic Result", content: item.0.text)
            let folder = NoteFolder(title: "Semantic Search", notes: [note])
            return SearchResult(folder: folder, note: note, query: "")
        }
}
