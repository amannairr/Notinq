//
//  SearchView.swift
//  Notinq
//
//  Created by Aman Nair on 01/05/26.
//

import SwiftUI
import AppKit

struct SearchView: View {
    @EnvironmentObject var appState: AppState

    @State private var query: String = ""
    @State private var selectedResultID: UUID?
    @State private var searchCurrentNoteOnly = false
    @State private var results: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var queryFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(388, max(320, proxy.size.width * 0.33))

            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)

                Divider()

                previewPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.bgEditor)
            .onAppear {
                queryFocused = true
                scheduleSearch(immediately: true)
            }
            .onChange(of: query) {
                scheduleSearch()
            }
            .onChange(of: searchCurrentNoteOnly) {
                scheduleSearch(immediately: true)
            }
            .onChange(of: appState.selectedNoteID) { _, _ in
                if searchCurrentNoteOnly {
                    scheduleSearch(immediately: true)
                }
            }
            .onSubmit {
                selectCurrentResult()
            }
            .onMoveCommand(perform: moveSelection)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider().opacity(0.6)
            searchFilters
            Divider().opacity(0.6)
            searchResultsList
        }
        .background(Color.bgNotesPane)
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textTertiary)

                TextField("Search notes, headings, and content", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($queryFocused)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.borderSubtle, lineWidth: 0.6)
            )
        }
        .padding(18)
        .background(Color.bgNotesPane)
    }

    private var searchFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SearchFilterChip(title: "All Notes", isSelected: !searchCurrentNoteOnly) {
                    searchCurrentNoteOnly = false
                }
                SearchFilterChip(title: "Current Note", isSelected: searchCurrentNoteOnly) {
                    searchCurrentNoteOnly = true
                }
            }

            Toggle("Only current note", isOn: $searchCurrentNoteOnly)
                .toggleStyle(.switch)
                .font(.subheadline)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.bgNotesPane)
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if results.isEmpty {
                    emptyState
                        .padding(.top, 16)
                        .padding(.horizontal, 18)
                } else {
                    ForEach(results) { result in
                        SearchResultCard(
                            result: result,
                            query: query,
                            isSelected: selectedResultID == result.id
                        ) {
                            select(result)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
            }
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
    }

    private var previewPane: some View {
        Group {
            if let selectedResult = selectedResult {
                SearchPreview(result: selectedResult, query: query)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(query.isEmpty ? "Recent notes" : "No results")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(query.isEmpty ? "Start typing to narrow the list or browse recent notes." : "Try a different keyword or search all notes.")
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
                .background(Color.bgEditor)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(query.isEmpty ? "Recent notes will appear here" : "No matching notes")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text(query.isEmpty ? "Use search to find titles, snippets, and note content." : "Try a different term or broaden the search scope.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 0.5)
        )
    }

    private var selectedResult: SearchResult? {
        guard let selectedResultID else { return results.first }
        return results.first(where: { $0.id == selectedResultID }) ?? results.first
    }

    private func select(_ result: SearchResult) {
        selectedResultID = result.id
        appState.selectNote(result.noteID)
    }

    private func scheduleSearch(immediately: Bool = false) {
        searchTask?.cancel()

        searchTask = Task { @MainActor in
            if !immediately {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }

            guard !Task.isCancelled else { return }
            performSearch()
        }
    }

    private func performSearch() {
        let updatedResults = Self.searchResults(
            query: query,
            folders: appState.folders,
            currentNoteOnly: searchCurrentNoteOnly,
            selectedNoteID: appState.selectedNoteID
        )
        results = updatedResults

        if let currentSelectedID = selectedResultID, !updatedResults.contains(where: { $0.id == currentSelectedID }) {
            self.selectedResultID = updatedResults.first?.id
        } else if selectedResultID == nil {
            self.selectedResultID = updatedResults.first?.id
        }
    }

    private func selectCurrentResult() {
        guard let selected = selectedResult ?? results.first else { return }
        select(selected)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard let nextIndex = Self.selectedResultIndex(
            currentIndex: results.firstIndex(where: { $0.id == selectedResultID }),
            direction: direction,
            resultCount: results.count
        ) else {
            return
        }

        selectedResultID = results[nextIndex].id
        appState.selectNote(results[nextIndex].noteID)
    }

    static func searchResults(
        query: String,
        folders: [NoteFolder],
        currentNoteOnly: Bool,
        selectedNoteID: UUID?
    ) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateNotes: [(folder: NoteFolder, note: NoteFile)] = folders.flatMap { folder in
            folder.notes.map { (folder: folder, note: $0) }
        }

        let scopedNotes: [(folder: NoteFolder, note: NoteFile)] = currentNoteOnly
            ? candidateNotes.filter { $0.note.id == selectedNoteID }
            : candidateNotes

        guard !scopedNotes.isEmpty else { return [] }

        if trimmed.isEmpty {
            return scopedNotes
                .sorted { $0.note.updatedAt > $1.note.updatedAt }
                .prefix(12)
                .compactMap { SearchResult(folder: $0.folder, note: $0.note, query: trimmed) }
        }

        let terms = trimmed
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }

        return scopedNotes
            .compactMap { SearchResult(folder: $0.folder, note: $0.note, query: trimmed, terms: terms) }
            .sorted { lhs, rhs in
                if lhs.relevance != rhs.relevance {
                    return lhs.relevance > rhs.relevance
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(24)
            .map { $0 }
    }

    static func selectedResultIndex(
        currentIndex: Int?,
        direction: MoveCommandDirection,
        resultCount: Int
    ) -> Int? {
        guard resultCount > 0 else { return nil }

        let resolvedIndex = currentIndex ?? 0
        switch direction {
        case .up:
            return max(0, resolvedIndex - 1)
        case .down:
            return min(resultCount - 1, resolvedIndex + 1)
        default:
            return nil
        }
    }
}

struct SearchResult: Identifiable, Equatable {
    enum SourceKind: String {
        case note = "Note"

        var iconName: String {
            "note.text"
        }
    }

    let id: UUID
    let noteID: UUID
    let title: String
    let folderTitle: String
    let sourceKind: SourceKind
    let preview: String
    let content: String
    let updatedAt: Date
    let relevance: Double

    init?(folder: NoteFolder, note: NoteFile, query: String, terms: [String] = []) {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerTitle = title.lowercased()
        let lowerContent = content.lowercased()
        let lowerFolder = folder.title.lowercased()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredQuery = normalizedQuery.lowercased()

        let titleMatch = lowerTitle.contains(loweredQuery)
        let contentMatch = lowerContent.contains(loweredQuery)
        let folderMatch = !normalizedQuery.isEmpty && lowerFolder.contains(loweredQuery)

        let termMatches = terms.reduce(into: 0.0) { score, term in
            if lowerTitle.contains(term) {
                score += 3
            } else if lowerContent.contains(term) {
                score += 4
            } else if lowerFolder.contains(term) {
                score += 1.5
            } else if [lowerTitle, lowerContent, lowerFolder].contains(where: { $0.containsFuzzySubsequence(term) }) {
                score += 1.25
            }
        }

        let recencyBoost = max(0, 1.0 - min(1.0, Date().timeIntervalSince(note.updatedAt) / (60 * 60 * 24 * 14)))
        let baseScore: Double

        if normalizedQuery.isEmpty {
            baseScore = recencyBoost
        } else {
            guard titleMatch || contentMatch || folderMatch || termMatches > 0 else { return nil }
            baseScore = termMatches + (titleMatch ? 4 : 0) + (contentMatch ? 3 : 0) + (folderMatch ? 1 : 0) + recencyBoost
        }

        id = note.id
        noteID = note.id
        self.title = title.isEmpty ? "Untitled Note" : title
        folderTitle = folder.title
        sourceKind = .note
        preview = Self.snippet(from: content, query: normalizedQuery)
        self.content = note.content
        updatedAt = note.updatedAt
        relevance = baseScore
    }

    private static func snippet(from content: String, query: String) -> String {
        let sanitized = content.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return "Empty note" }

        guard !query.isEmpty, let range = sanitized.lowercased().range(of: query.lowercased()) else {
            return String(sanitized.prefix(180)) + (sanitized.count > 180 ? "..." : "")
        }

        let lowerBound = sanitized.distance(from: sanitized.startIndex, to: range.lowerBound)
        let start = max(0, lowerBound - 48)
        let end = min(sanitized.count, lowerBound + 132)
        let snippet = String(sanitized[sanitized.index(sanitized.startIndex, offsetBy: start)..<sanitized.index(sanitized.startIndex, offsetBy: end)])
        return (start > 0 ? "..." : "") + snippet + (end < sanitized.count ? "..." : "")
    }
}

struct SearchResultCard: View {
    let result: SearchResult
    let query: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: result.sourceKind.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(isSelected ? Color.accentColor : Color.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            labelPill(result.sourceKind.rawValue)
                            labelPill(result.folderTitle)
                        }
                    }

                    Spacer(minLength: 0)

                    Text(Self.relevanceLabel(result.relevance))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }

                highlightedSnippet

                HStack {
                    Text(result.updatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text("Preview")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.32) : Color.borderSubtle, lineWidth: isSelected ? 1.0 : 0.6)
            )
            .shadow(color: .black.opacity(isSelected ? 0.08 : 0.03), radius: isSelected ? 12 : 8, x: 0, y: isSelected ? 6 : 3)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var background: some View {
        Group {
            if isSelected {
                LinearGradient(
                    colors: [Color.noteCardSelected, Color.noteCard.opacity(0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if hover {
                Color.bgElevated
            } else {
                Color.noteCard
            }
        }
    }

    private var highlightedSnippet: Text {
        Self.highlightedText(result.preview, query: query)
    }

    private func labelPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.bgElevated)
            .clipShape(Capsule())
    }

    private static func highlightedText(_ text: String, query: String) -> Text {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Text(text).font(.subheadline).foregroundStyle(Color.textSecondary)
        }

        let lowerText = text.lowercased()
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else {
            return Text(text).font(.subheadline).foregroundStyle(Color.textSecondary)
        }

        var segments: [(String, Bool)] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            var nextMatchRange: Range<String.Index>?
            var nextMatchTerm: String?

            for term in terms {
                if let range = lowerText.range(of: term, range: cursor..<text.endIndex) {
                    if nextMatchRange == nil || range.lowerBound < nextMatchRange!.lowerBound {
                        nextMatchRange = range
                        nextMatchTerm = term
                    }
                }
            }

            guard let matchRange = nextMatchRange else {
                segments.append((String(text[cursor..<text.endIndex]), false))
                break
            }

            if matchRange.lowerBound > cursor {
                segments.append((String(text[cursor..<matchRange.lowerBound]), false))
            }

            segments.append((String(text[matchRange]), true))
            cursor = matchRange.upperBound
            _ = nextMatchTerm
        }

        var attributed = AttributedString()

        for segment in segments {
            var piece = AttributedString(segment.0)
            piece.foregroundColor = segment.1 ? Color.accentColor : Color.textSecondary
            if segment.1 {
                piece.inlinePresentationIntent = .stronglyEmphasized
            }
            attributed += piece
        }

        return Text(attributed)
    }

    static func relevanceLabel(_ relevance: Double) -> String {
        let percent = min(100, max(0, Int((relevance / 10.0) * 100)))
        return "\(percent)% match"
    }
}

struct SearchPreview: View {
    let result: SearchResult
    let query: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                contentCard
            }
            .padding(24)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Color.bgEditor)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: result.sourceKind.iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                    Text(result.folderTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                metadataPill(title: result.sourceKind.rawValue, value: nil)
                metadataPill(title: "Updated", value: result.updatedAt.formatted(date: .abbreviated, time: .omitted))
                metadataPill(title: "Match", value: SearchResultCard.relevanceLabel(result.relevance))
            }
        }
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            if let attributed = result.content.markdownAttributedString() {
                Text(attributed)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(result.content)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 0.6)
        )
    }

    private func metadataPill(title: String, value: String?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            if let value {
                Text(value)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.bgElevated)
        .clipShape(Capsule())
    }
}

struct SearchFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color.bgElevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.borderSubtle, lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
    }
}

private extension String {
    func containsFuzzySubsequence(_ pattern: String) -> Bool {
        guard !pattern.isEmpty else { return true }

        var searchIndex = startIndex
        for character in pattern {
            guard let foundIndex = self[searchIndex...].firstIndex(of: character) else {
                return false
            }
            searchIndex = index(after: foundIndex)
        }

        return true
    }
}
