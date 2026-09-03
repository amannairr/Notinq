//
//  ContentView.swift
//  Notinq
//
//  Created by Aman Nair on 11/04/26.
//

import SwiftUI
import AppKit

struct MainContainerView: View {

    @ObservedObject var appState: AppState
    @State private var studyPanelWidth: CGFloat = 410

    // Panel widths
    @State private var sidebarWidth: CGFloat = 230
    @State private var listWidth: CGFloat = 328

    @State private var sidebarLastDragX: CGFloat?
    @State private var listLastDragX: CGFloat?
    @State private var isSidebarCollapsed = false
    @State private var isNotesCollapsed = false

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 0) {

                    ModeBarView(selectedMode: $appState.selectedMode)
                        .frame(width: 80)

                    if isSidebarCollapsed {
                        collapsedBar(
                            icon: "sidebar.right",
                            tooltip: "Show sidebar",
                            colors: [Color.bgSidebar, Color.bgSidebar]
                        ) {
                            isSidebarCollapsed = false
                        }
                    } else {
                        SidebarView(isCollapsed: $isSidebarCollapsed)
                            .frame(width: sidebarWidth)
                    }

                    // 🔥 HANDLE 1
                    if !isSidebarCollapsed {
                        resizeHandle(
                            onDragChanged: { currentX in
                                if sidebarLastDragX == nil {
                                    sidebarLastDragX = currentX
                                }
                                if let lastX = sidebarLastDragX {
                                    let delta = currentX - lastX
                                    withTransaction(Transaction(animation: nil)) {
                                        sidebarWidth = clamp(sidebarWidth + delta, min: 196, max: 320)
                                    }
                                    sidebarLastDragX = currentX
                                }
                            },
                            onEnd: {
                                sidebarLastDragX = nil
                            },
                            onDoubleClick: {
                                sidebarWidth = 230
                            }
                        )
                    }

                    if isNotesCollapsed {
                        collapsedBar(
                            icon: "sidebar.right",
                            tooltip: "Show notes list",
                            colors: [Color.bgNotesPane, Color.bgNotesPane]
                        ) {
                            isNotesCollapsed = false
                        }
                    } else {
                        NotesListView(isCollapsed: $isNotesCollapsed)
                            .frame(width: listWidth)
                            .background(Color.clear)
                    }

                    // 🔥 HANDLE 2
                    if !isNotesCollapsed {
                        resizeHandle(
                            onDragChanged: { currentX in
                                if listLastDragX == nil {
                                    listLastDragX = currentX
                                }
                                if let lastX = listLastDragX {
                                    let delta = currentX - lastX
                                    withTransaction(Transaction(animation: nil)) {
                                        listWidth = clamp(listWidth + delta, min: 260, max: 420)
                                    }
                                    listLastDragX = currentX
                                }
                            },
                            onEnd: {
                                listLastDragX = nil
                            },
                            onDoubleClick: {
                                listWidth = 328
                            }
                        )
                    }

                    GeometryReader { editorProxy in
                        ZStack {
                            switch appState.selectedMode {
                            case .notes, .study:
                                if appState.selectedMode == .study {
                                    StudyView(
                                        noteID: currentNoteID,
                                        noteTitle: currentNoteTitle,
                                        noteText: currentNoteText,
                                        selectedText: "",
                                        lastUpdatedAt: currentNoteUpdatedAt,
                                        noteHasContent: !currentNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                        studyData: currentStudyData,
                                        autoGenerateStudyMaterialsRequestID: appState.pendingStudyGenerationRequestID,
                                        isGenerating: false,
                                        generationStatus: "Generating study materials...",
                                        generationSummary: nil,
                                        statusMessage: nil,
                                        statusTone: .neutral,
                                        onGenerateMaterials: {
                                            appState.requestStudyGeneration()
                                        },
                                        onAutoGenerateStudyMaterialsConsumed: {
                                            appState.consumeStudyGenerationRequest()
                                        },
                                        onClose: { appState.selectedMode = .notes },
                                        onExplainSimply: { insertStudyContentIntoCurrentNote(explainCurrentNoteSimply()) },
                                        onGiveExample: { insertStudyContentIntoCurrentNote(explainCurrentNoteExample()) },
                                        onCompareConcepts: { insertStudyContentIntoCurrentNote(explainCurrentNoteComparison()) },
                                        onCreateAnalogy: { insertStudyContentIntoCurrentNote(explainCurrentNoteAnalogy()) },
                                        onMarkFlashcardReviewed: { card in markFlashcardReviewed(card) },
                                        onRecordQuizAttempt: { quizSet, score, totalQuestions in
                                            recordQuizAttempt(quizSet: quizSet, score: score, totalQuestions: totalQuestions)
                                        },
                                        onEvaluateTestMe: { question, answer, completion in
                                            evaluateTestMe(question: question, answer: answer, completion: completion)
                                        },
                                        onRecordTestMeSession: { score, totalQuestions, concepts in
                                            recordTestMeSession(score: score, totalQuestions: totalQuestions, concepts: concepts)
                                        },
                                        onInsertContent: { text in insertStudyContentIntoCurrentNote(text) },
                                        panelWidth: $studyPanelWidth
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                } else {
                                    EditorView(
                                        onAnalyzeLecture: analyzeLecture,
                                        onUpdateKnowledgeGraph: updateCurrentKnowledgeGraph,
                                        onGenerateStudyMaterials: {
                                            appState.requestStudyGeneration()
                                        }
                                    )
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                }
                            case .ai:
                                AIWorkspaceView(
                                    noteTitle: currentNoteTitle,
                                    noteText: currentNoteText,
                                    lastUpdatedAt: currentNoteUpdatedAt
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            case .search:
                                SearchView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.bgEditor)
                        .shadow(color: .black.opacity(0.045), radius: 22, x: -10, y: 0)
                        .animation(.easeInOut(duration: 0.15), value: appState.selectedMode)
                        .overlay(alignment: .trailing) {
                            if appState.isLearningInsightsOpen, let currentNoteID {
                                Color.black.opacity(0.18)
                                    .frame(width: editorProxy.size.width, height: editorProxy.size.height)
                                    .onTapGesture {
                                        appState.closeLearningInsights()
                                    }

                                LearningInsightsWorkspaceView(
                                    noteTitle: currentNoteTitle,
                                    studentNotes: currentNoteText,
                                    initialAnalysis: currentStudyData.learningInsights.hasResults ? currentStudyData.learningInsights : nil,
                                    onSaveAnalysis: { result in
                                        appState.updateLearningInsights(result, for: currentNoteID)
                                    },
                                    onInsertIntoNote: { text in
                                        insertStudyContentIntoCurrentNote(text)
                                    },
                                    onClose: {
                                        appState.closeLearningInsights()
                                    }
                                )
                                .frame(
                                    width: Self.learningInsightsPanelSize(for: editorProxy.size).width,
                                    height: Self.learningInsightsPanelSize(for: editorProxy.size).height
                                )
                                .padding(.trailing, 18)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .zIndex(20)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if appState.isCommandBarOpen {
                    CommandBarView(isVisible: Binding(
                        get: { appState.isCommandBarOpen },
                        set: { appState.isCommandBarOpen = $0 }
                    ))
                }

                if appState.isSettingsOpen {
                    SettingsOverlayView()
                        .environmentObject(appState)
                        .transition(.opacity)
                        .zIndex(10)
                }

            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(Color.bgPrimary)
            .environmentObject(appState)
            .onAppear {
                setupKeyboardShortcuts()
            }
        }
    }

    private func analyzeLecture() {
        appState.openLearningInsights()
    }

    private func updateCurrentKnowledgeGraph() {
        guard let currentNoteID else { return }
        let note = NoteFile(
            id: currentNoteID,
            title: currentNoteTitle,
            content: currentNoteText,
            updatedAt: currentNoteUpdatedAt ?? Date()
        )
        KnowledgeGraphManager.shared.generateGraph(note: note)
    }

    static func learningInsightsPanelSize(for editorSize: CGSize) -> CGSize {
        let preferredWidth = min(max(editorSize.width * 0.74, 860), 1160)
        let preferredHeight = min(editorSize.height - 24, 840)
        return CGSize(
            width: min(preferredWidth, max(0, editorSize.width - 36)),
            height: max(0, preferredHeight)
        )
    }

    private var currentNoteID: UUID? {
        appState.selectedNoteID
    }

    private var currentNoteTitle: String {
        guard let currentNoteID else { return "Untitled Note" }
        return appState.noteTitle(for: currentNoteID)
    }

    private var currentNoteText: String {
        guard let currentNoteID else { return "" }
        return appState.noteContent(for: currentNoteID)
    }

    private var currentNoteUpdatedAt: Date? {
        guard let currentNoteID else { return nil }
        return appState.noteUpdatedAt(for: currentNoteID)
    }

    private var currentStudyData: NoteStudyData {
        guard let currentNoteID else { return NoteStudyData() }
        return appState.studyData(for: currentNoteID)
    }

    private func insertStudyContentIntoCurrentNote(_ text: String) {
        guard let currentNoteID else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = currentNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedText: String
        if existing.isEmpty {
            updatedText = trimmed
        } else {
            updatedText = currentNoteText + "\n\n" + trimmed
        }

        appState.updateNoteContent(updatedText, for: currentNoteID)
    }

    private func currentStudyConcepts(limit: Int = 4) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted
        let tokens = currentNoteText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 4 }

        var seen = Set<String>()
        return tokens.compactMap { token in
            let key = token.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return token.prefix(1).uppercased() + token.dropFirst()
        }
        .prefix(limit)
        .map { $0 }
    }

    private func explainCurrentNoteSimply() -> String {
        let concepts = currentStudyConcepts(limit: 3)
        let topic = concepts.first ?? currentNoteTitle
        return [
            "Simple explanation",
            "\(topic) is the central idea in \(currentNoteTitle).",
            "In plain language, the note is describing how \(currentNoteText.isEmpty ? "the topic" : topic.lowercased()) works in context.",
            "Key takeaway",
            "Focus on the main definition, the example, and the relationship to nearby concepts."
        ].joined(separator: "\n")
    }

    private func explainCurrentNoteExample() -> String {
        let concepts = currentStudyConcepts(limit: 3)
        let topic = concepts.first ?? currentNoteTitle
        return [
            "Concrete example",
            "If \(topic.lowercased()) feels abstract, think about a real situation where it appears in the note.",
            "Example",
            "A student applying \(topic.lowercased()) would identify the definition, then test it against the scenario described in the note.",
            "What to insert",
            "Add one specific example from class, practice, or a worked problem."
        ].joined(separator: "\n")
    }

    private func explainCurrentNoteComparison() -> String {
        let concepts = currentStudyConcepts(limit: 4)
        let left = concepts.first ?? currentNoteTitle
        let right = concepts.dropFirst().first ?? "a related idea"
        return [
            "Comparison",
            "\(left) and \(right) are related, but they serve different roles in the note.",
            "\(left) is the core term.",
            "\(right) is the nearby concept that helps define or contrast it.",
            "Use this comparison to separate definition from application."
        ].joined(separator: "\n")
    }

    private func explainCurrentNoteAnalogy() -> String {
        let concepts = currentStudyConcepts(limit: 2)
        let topic = concepts.first ?? currentNoteTitle
        let anchor = concepts.dropFirst().first ?? "a familiar system"
        return [
            "Analogy",
            "\(topic) works like \(anchor) because both organize information into something easier to understand.",
            "Analogy",
            "Think of the note as a map: \(topic) tells you what matters, and the supporting details show how the pieces fit together."
        ].joined(separator: "\n")
    }

    private func markFlashcardReviewed(_ card: StudyFlashcard) {
        guard let currentNoteID else { return }
        let concept = inferConcept(from: card.front) ?? inferConcept(from: card.back) ?? card.type.title
        appState.mutateStudyData(for: currentNoteID) { studyData in
            studyData.progress.flashcardsReviewed += 1
            if let index = studyData.learningMemory.firstIndex(where: { normalizedStudyConceptKey($0.concept) == normalizedStudyConceptKey(concept) }) {
                studyData.learningMemory[index].reviewHistory.append(Date())
                studyData.learningMemory[index].lastReviewedAt = Date()
                studyData.learningMemory[index].masteredCount += 1
                studyData.learningMemory[index].lastOutcome = .correct
            } else {
                studyData.learningMemory.append(
                    StudyMemoryEntry(
                        concept: concept,
                        masteredCount: 1,
                        missedCount: 0,
                        reviewHistory: [Date()],
                        lastReviewedAt: Date(),
                        lastOutcome: .correct
                    )
                )
            }
            studyData.streaks.flashcardsCompleted += 1
            studyData.streaks.studySessions += 1
            studyData.streaks.lastStudiedAt = Date()
            studyData.lastGeneratedAt = Date()
        }
    }

    private func recordQuizAttempt(quizSet: StudyQuizSet, score: Int, totalQuestions: Int) {
        guard let currentNoteID else { return }
        let questions = max(totalQuestions, 1)
        let percentage = Double(score) / Double(questions) * 100
        appState.mutateStudyData(for: currentNoteID) { studyData in
            studyData.progress.quizAttempts.insert(
                StudyQuizAttempt(
                    quizSetID: quizSet.id,
                    quizTitle: quizSet.title,
                    score: score,
                    totalQuestions: questions,
                    percentage: percentage
                ),
                at: 0
            )
            studyData.streaks.quizzesCompleted += 1
            studyData.streaks.studySessions += 1
            studyData.streaks.lastStudiedAt = Date()
            studyData.lastGeneratedAt = Date()
        }
    }

    private func evaluateTestMe(question: StudyTutorQuestion, answer: String, completion: @escaping (StudyTutorEvaluation) -> Void) {
        let normalizedExpected = normalizeText(question.expectedAnswer)
        let normalizedAnswer = normalizeText(answer)
        let expectedWords = Set(normalizedExpected.split(separator: " ").map(String.init))
        let answerWords = Set(normalizedAnswer.split(separator: " ").map(String.init))
        let overlap = Double(expectedWords.intersection(answerWords).count)
        let denominator = Double(max(expectedWords.count, 1))
        let matchScore = overlap / denominator

        let verdict: StudyTutorVerdict
        if matchScore > 0.75 {
            verdict = .correct
        } else if matchScore > 0.35 {
            verdict = .almost
        } else {
            verdict = .incorrect
        }

        let evaluation = StudyTutorEvaluation(
            verdict: verdict,
            feedback: verdict == .correct ? "Strong recall." : verdict == .almost ? "Close, but add one more detail." : "Review the concept again and focus on the definition.",
            explanation: question.explanation.isEmpty ? "Compare your answer with the expected answer and add missing context." : question.explanation,
            modelAnswer: question.expectedAnswer,
            awardedPoint: verdict == .correct ? 1 : 0
        )
        completion(evaluation)
    }

    private func recordTestMeSession(score: Int, totalQuestions: Int, concepts: [String]) {
        guard let currentNoteID else { return }
        let questions = max(totalQuestions, 1)
        appState.mutateStudyData(for: currentNoteID) { studyData in
            studyData.progress.testMeSessions.append(
                StudyTestMeSessionRecord(
                    score: score,
                    totalQuestions: questions,
                    concepts: concepts
                )
            )
            studyData.streaks.studySessions += 1
            studyData.streaks.quizzesCompleted += 1
            studyData.streaks.lastStudiedAt = Date()
            studyData.lastGeneratedAt = Date()
        }
    }

    private func inferConcept(from text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "Question", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Correct answer", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Concept prompt", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Definition prompt", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Explanation", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Supporting context", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }
        return cleaned
            .split(separator: "\n")
            .map(String.init)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private func normalizeText(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func normalizedStudyConceptKey(_ value: String) -> String {
        normalizeText(value)
    }
}

//////////////////////////////////////////////////////////////
// MARK: - RESIZE HANDLE
//////////////////////////////////////////////////////////////

extension MainContainerView {

    func resizeHandle(
        onDragChanged: @escaping (CGFloat) -> Void,
        onEnd: @escaping () -> Void,
        onDoubleClick: @escaping () -> Void
    ) -> some View {

        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 1)

            Rectangle()
                .fill(Color.clear)
                .frame(width: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    onDragChanged(value.location.x)
                }
                .onEnded { _ in
                    onEnd()
                }
        )
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
    }

    func collapsedBar(
        icon: String,
        tooltip: String,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 18, height: 34)
                    .background(Color.hoverWarm)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help(tooltip)
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(minWidth: 32, idealWidth: 32, maxWidth: 32, minHeight: 0, idealHeight: nil, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        )
    }
}

//////////////////////////////////////////////////////////////
// MARK: - HELPERS
//////////////////////////////////////////////////////////////

extension MainContainerView {

    func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }

}

//////////////////////////////////////////////////////////////
// MARK: - Keyboard Shortcuts
//////////////////////////////////////////////////////////////

extension MainContainerView {

    func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let shortcut = Self.shortcutAction(for: event) {
                switch shortcut {
                case .notes:
                    appState.selectedMode = .notes
                case .ai:
                    appState.selectedMode = .ai
                case .study:
                    appState.selectedMode = .study
                case .search:
                    appState.selectedMode = .search
                case .commandBar:
                    appState.toggleCommandBar()
                case .settings:
                    appState.isSettingsOpen = true
                case .learningInsights:
                    appState.openLearningInsights()
                case .newNote:
                    appState.createNoteInSelectedFolder()
                    appState.selectedMode = .notes
                case .generateStudyMaterials:
                    appState.requestStudyGeneration()
                }
            }

            return event
        }
    }

    static func shortcutAction(
        forCharacters characters: String,
        modifiers: NSEvent.ModifierFlags
    ) -> ShortcutAction? {
        let normalized = characters.lowercased()
        let hasCommand = modifiers.contains(.command)
        let hasShift = modifiers.contains(.shift)

        guard hasCommand else { return nil }

        switch (normalized, hasShift) {
        case ("1", false):
            return .notes
        case ("2", false):
            return .ai
        case ("3", false):
            return .study
        case ("4", false):
            return .search
        case ("k", false):
            return .commandBar
        case (",", false):
            return .settings
        case ("i", true):
            return .learningInsights
        case ("n", false):
            return .newNote
        case ("g", true):
            return .generateStudyMaterials
        default:
            return nil
        }
    }

    enum ShortcutAction: Equatable {
        case notes
        case ai
        case study
        case search
        case commandBar
        case settings
        case learningInsights
        case newNote
        case generateStudyMaterials
    }

    static func shortcutAction(for event: NSEvent) -> ShortcutAction? {
        shortcutAction(
            forCharacters: event.charactersIgnoringModifiers ?? "",
            modifiers: event.modifierFlags
        )
    }
}
