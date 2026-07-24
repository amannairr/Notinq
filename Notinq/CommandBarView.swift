//
//  CommandBarView.swift
//  Notinq
//
//  Created by Aman Nair on 21/04/26.
//

import SwiftUI

struct CommandBarView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isVisible: Bool

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var queryFocused: Bool

    private var actions: [CommandPaletteAction] {
        CommandPaletteAction.defaultActions
    }

    private var filteredActions: [CommandPaletteAction] {
        Self.filteredActions(for: query, actions: actions)
    }

    private var selectedAction: CommandPaletteAction? {
        guard !filteredActions.isEmpty else { return nil }
        return filteredActions[min(selectedIndex, filteredActions.count - 1)]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { closePalette() }

            VStack(spacing: 0) {
                header

                Divider()
                    .overlay(Color.borderSubtle.opacity(0.7))

                actionList
                    .frame(maxWidth: .infinity, maxHeight: 360)

                footer
            }
            .frame(width: 680)
            .background(.ultraThinMaterial)
            .background(Color.bgElevated.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.borderSubtle, lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.22), radius: 36, x: 0, y: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .onAppear {
            queryFocused = true
            selectedIndex = 0
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                query = ""
                selectedIndex = 0
                queryFocused = true
            }
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: filteredActions.map(\.id)) { _, _ in
            selectedIndex = min(selectedIndex, max(0, filteredActions.count - 1))
        }
        .onSubmit {
            executeSelectedAction()
        }
        .onExitCommand {
            closePalette()
        }
        .onMoveCommand(perform: moveSelection)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 34)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.25, green: 0.48, blue: 0.60),
                                Color(red: 0.32, green: 0.56, blue: 0.38)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Command Palette")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Text("Search actions, switch modes, and jump into study workflows.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 0)

                Text("Esc to close")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textTertiary)

                TextField("Ask AI or run a command...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($queryFocused)
                    .submitLabel(.go)

                if !query.isEmpty {
                    Button {
                        query = ""
                        selectedIndex = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.bgEditor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.borderSubtle, lineWidth: 0.8)
            )
        }
        .padding(20)
    }

    private var actionList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if filteredActions.isEmpty {
                    emptyState
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                } else {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        quickActionHeader
                    }

                    ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, action in
                        commandRow(action: action, isSelected: index == selectedIndex) {
                            selectedIndex = index
                            execute(action)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }

    private var quickActionHeader: some View {
        HStack {
            Text("Quick Actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No matching commands")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Try a shorter phrase or use one of the built-in quick actions.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.bgEditor)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 0.8)
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                shortcutPill("Return")
                Text("Run")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 6) {
                shortcutPill("↑↓")
                Text("Navigate")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 6) {
                shortcutPill("Esc")
                Text("Close")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer(minLength: 0)

            Text("\(filteredActions.count) actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.bgElevated.opacity(0.88))
    }

    private func shortcutPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.bgEditor)
            .clipShape(Capsule())
    }

    private func commandRow(action: CommandPaletteAction, isSelected: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: action.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : action.tint)
                    .frame(width: 30, height: 30)
                    .background(isSelected ? action.tint : action.tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if let shortcut = action.shortcut {
                    Text(shortcut)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? action.tint.opacity(0.16) : Color.bgEditor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? action.tint.opacity(0.30) : Color.borderSubtle, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityHint(action.accessibilityHint)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !filteredActions.isEmpty else { return }

        switch direction {
        case .up:
            selectedIndex = max(0, selectedIndex - 1)
        case .down:
            selectedIndex = min(filteredActions.count - 1, selectedIndex + 1)
        default:
            break
        }
    }

    private func executeSelectedAction() {
        guard let selectedAction else { return }
        execute(selectedAction)
    }

    private func execute(_ action: CommandPaletteAction) {
        action.perform(appState)
        closePalette()
    }

    private func closePalette() {
        isVisible = false
        appState.closeCommandBar()
    }

    static func filteredActions(for query: String, actions: [CommandPaletteAction]) -> [CommandPaletteAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return actions
        }

        return actions
            .compactMap { action -> (CommandPaletteAction, Double)? in
                let score = action.score(for: trimmed)
                guard score > 0 else { return nil }
                return (action, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.title < rhs.0.title
            }
            .map { $0.0 }
    }
}

struct CommandPaletteAction: Identifiable {
    var id: String { title }
    let title: String
    let subtitle: String
    let icon: String
    let shortcut: String?
    let keywords: [String]
    let tint: Color
    let accessibilityLabel: String
    let accessibilityHint: String
    let perform: (AppState) -> Void

    func score(for query: String) -> Double {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return 1 }

        let searchSpace = [
            title.lowercased(),
            subtitle.lowercased(),
            keywords.joined(separator: " ").lowercased()
        ]
        .joined(separator: " ")

        var score: Double = 0
        let terms = normalizedQuery
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }

        if searchSpace.contains(normalizedQuery) {
            score += 40
        }

        if title.lowercased().hasPrefix(normalizedQuery) {
            score += 30
        }

        for term in terms {
            if title.lowercased().contains(term) {
                score += 18
            } else if subtitle.lowercased().contains(term) {
                score += 10
            } else if keywords.contains(where: { $0.lowercased().contains(term) }) {
                score += 12
            } else if searchSpace.containsFuzzySubsequence(term) {
                score += 6
            }
        }

        return score
    }

    static var defaultActions: [CommandPaletteAction] {
        [
            CommandPaletteAction(
                title: "New Note",
                subtitle: "Create a note in the selected folder and start editing.",
                icon: "square.and.pencil",
                shortcut: "⌘N",
                keywords: ["new", "note", "create"],
                tint: Color(red: 0.25, green: 0.48, blue: 0.60),
                accessibilityLabel: "Create a new note",
                accessibilityHint: "Adds a note to the current folder and opens it."
            ) { appState in
                appState.createNoteInSelectedFolder()
                appState.selectedMode = .notes
            },
            CommandPaletteAction(
                title: "Open Notes",
                subtitle: "Return to the notes workspace.",
                icon: "note.text",
                shortcut: "⌘1",
                keywords: ["notes", "workspace"],
                tint: Color(red: 0.24, green: 0.49, blue: 0.59),
                accessibilityLabel: "Open notes",
                accessibilityHint: "Switches back to the notes editor."
            ) { appState in
                appState.selectedMode = .notes
            },
            CommandPaletteAction(
                title: "Open AI",
                subtitle: "Jump to the AI workspace.",
                icon: "sparkles",
                shortcut: "⌘2",
                keywords: ["ai", "assistant"],
                tint: Color(red: 0.54, green: 0.38, blue: 0.61),
                accessibilityLabel: "Open AI workspace",
                accessibilityHint: "Switches to the AI assistant view."
            ) { appState in
                appState.selectedMode = .ai
            },
            CommandPaletteAction(
                title: "Open Study",
                subtitle: "Jump into flashcards, quizzes, and insights.",
                icon: "book.pages",
                shortcut: "⌘3",
                keywords: ["study", "flashcards", "quiz"],
                tint: Color(red: 0.31, green: 0.58, blue: 0.39),
                accessibilityLabel: "Open study workspace",
                accessibilityHint: "Switches to the study workspace."
            ) { appState in
                appState.selectedMode = .study
            },
            CommandPaletteAction(
                title: "Open Search",
                subtitle: "Search titles, headings, and note content.",
                icon: "magnifyingglass",
                shortcut: "⌘4",
                keywords: ["search", "find"],
                tint: Color(red: 0.60, green: 0.45, blue: 0.20),
                accessibilityLabel: "Open search",
                accessibilityHint: "Switches to the search workspace."
            ) { appState in
                appState.selectedMode = .search
            },
            CommandPaletteAction(
                title: "Open Learning Insights",
                subtitle: "Compare notes against lecture sources.",
                icon: "chart.line.uptrend.xyaxis",
                shortcut: "⌘⇧I",
                keywords: ["learning", "insights", "analysis"],
                tint: Color(red: 0.23, green: 0.47, blue: 0.59),
                accessibilityLabel: "Open learning insights",
                accessibilityHint: "Shows the lecture comparison panel for the active note."
            ) { appState in
                appState.openLearningInsights()
                appState.selectedMode = .notes
            },
            CommandPaletteAction(
                title: "Generate Study Materials",
                subtitle: "Build flashcards, quizzes, and summaries from the active note.",
                icon: "books.vertical",
                shortcut: "⌘⇧G",
                keywords: ["generate", "materials", "flashcards", "quiz"],
                tint: Color(red: 0.32, green: 0.56, blue: 0.38),
                accessibilityLabel: "Generate study materials",
                accessibilityHint: "Creates study content and opens the study workspace."
            ) { appState in
                appState.requestStudyGeneration()
            },
            CommandPaletteAction(
                title: "Open Settings",
                subtitle: "Review preferences and AI behavior.",
                icon: "gearshape",
                shortcut: "⌘,",
                keywords: ["settings", "preferences"],
                tint: Color(red: 0.46, green: 0.32, blue: 0.21),
                accessibilityLabel: "Open settings",
                accessibilityHint: "Shows the settings overlay."
            ) { appState in
                appState.isSettingsOpen = true
            }
        ]
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
