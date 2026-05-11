//
//  SearchView.swift
//  ProjectLumora
//
//  Created by Aman Nair on 01/05/26.
//

import SwiftUI

struct SearchView: View {
    
    @EnvironmentObject var appState: AppState
    
    @State private var query: String = ""
    @State private var aiQuery: String = ""
    @State private var selectedResult: SearchResult? = nil
    @State private var searchCurrentNoteOnly = false
    
    @State private var results: [SearchResult] = []
    
    var body: some View {
        HStack(spacing: 0) {
            
            // 🔹 LEFT PANEL
            VStack(spacing: 0) {
                
                // 🔍 SEARCH BAR
                HStack {
                    Image(systemName: "magnifyingglass")
                    
                    TextField("Search notes, PDFs, anything...", text: $query)
                        .textFieldStyle(.plain)
                        .onChange(of: query) {
                            performSearch()
                        }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                
                Divider()
                
                // 🔹 FILTERS + TOGGLE
                VStack(spacing: 8) {
                    
                    HStack(spacing: 10) {
                        FilterChip(title: "Notes")
                        FilterChip(title: "PDFs")
                        FilterChip(title: "Images")
                    }
                    
                    Toggle("Current Note", isOn: $searchCurrentNoteOnly)
                        .toggleStyle(.switch)
                }
                .padding(10)
                
                Divider()
                
                // 🔹 RESULTS LIST
                ScrollView {
                    VStack(spacing: 6) {
                        
                        ForEach(results) { result in
                            SearchRow(
                                result: result,
                                query: query,
                                isSelected: selectedResult?.id == result.id
                            ) {
                                selectedResult = result
                                
                                // 🔥 OPEN IN EDITOR
                                appState.selectedNoteContent = result.content
                                appState.selectedMode = .notes
                            }
                        }
                    }
                    .padding(8)
                    
                    // 🔥 ASK AI BOX (IMPORTANT)
                    VStack(spacing: 8) {
                        
                        TextField("Ask about results...", text: $aiQuery)
                        
                        Button("Ask AI") {
                            askAI()
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 10)
                }
            }
            .frame(width: 340)
            
            Divider()
            
            // 🔹 RIGHT PREVIEW PANEL
            ZStack {
                
                if let selectedResult {
                    SearchPreview(result: selectedResult)
                } else {
                    Text("Select a result")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - SEARCH LOGIC
    
    func performSearch() {
        if query.isEmpty {
            results = []
            return
        }
        
        if searchCurrentNoteOnly {
            let content = appState.selectedNoteContent
            
            if content.localizedCaseInsensitiveContains(query) {
                results = [
                    SearchResult(
                        title: "Current Note",
                        preview: content,
                        content: content
                    )
                ]
            } else {
                results = []
            }
            
        } else {
            results = (0..<10).map { i in
                SearchResult(
                    title: "Result \(i)",
                    preview: "Match for '\(query)' in your notes...",
                    content: "Full content of result \(i) containing \(query)..."
                )
            }
        }
    }
    
    // MARK: - AI
    
    func askAI() {
        
        let combinedContext = results.map { $0.content }.joined(separator: "\n\n")
        
        let prompt = """
        Based on the following notes:
        
        \(combinedContext)
        
        Answer:
        \(aiQuery)
        """
        
        print(prompt)
        
        // 👉 Replace with Gemini later
    }
    
    // MARK: - HIGHLIGHT FUNCTION
    
    func highlightText(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        
        guard !query.isEmpty else { return attributed }
        
        let lowerText = text.lowercased()
        let lowerQuery = query.lowercased()
        
        var searchRange = lowerText.startIndex..<lowerText.endIndex
        
        while let range = lowerText.range(of: lowerQuery, range: searchRange) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].font = .system(size: 11, weight: .bold)
            }
            searchRange = range.upperBound..<lowerText.endIndex
        }
        
        return attributed
    }
}

// MARK: - MODELS

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let preview: String
    let content: String
}

// MARK: - ROW

struct SearchRow: View {
    
    let result: SearchResult
    let query: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var hover = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                
                Text(result.title)
                    .font(.system(size: 13, weight: .semibold))
                
                Text(highlightText(result.preview, query: query))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                ? Color.accentSoft
                : (hover ? Color.hoverWarm : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - PREVIEW

struct SearchPreview: View {
    
    let result: SearchResult
    
    var body: some View {
        ScrollView {
            
            VStack(alignment: .leading, spacing: 16) {
                
                Text(result.title)
                    .font(.system(size: 22, weight: .bold))
                
                Text(result.content)
                    .font(.system(size: 14))
            }
            .padding(24)
            .frame(maxWidth: 700, alignment: .leading)
        }
    }
}

// MARK: - FILTER CHIP

struct FilterChip: View {
    
    let title: String
    @State private var selected = true
    
    var body: some View {
        Button {
            selected.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selected
                    ? Color.accentSoft
                    : Color.hoverWarm
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
