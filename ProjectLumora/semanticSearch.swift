//
//  semanticSearch.swift
//  ProjectLumora
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
        .map {
            SearchResult(
                title: "Semantic Result",
                preview: $0.0.text,
                content: $0.0.text
            )
        }
}
