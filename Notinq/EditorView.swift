import SwiftUI
import AppKit

struct EditorView: View {
    @EnvironmentObject private var appState: AppState
    var onAnalyzeLecture: () -> Void = {}
    var onUpdateKnowledgeGraph: () -> Void = {}
    @State private var styleState = TextStyleState()
    @State private var bridge = TextViewBridge()
    @State private var selectedText = ""
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var activeSelectionAction: AIAction?
    @ObservedObject private var knowledgeGraphManager = KnowledgeGraphManager.shared

    private var selectedNoteID: UUID? {
        appState.selectedNoteID
    }

    private var noteTitle: String {
        guard let selectedNoteID else { return "Untitled Note" }
        return appState.noteTitle(for: selectedNoteID)
    }

    private var noteContentBinding: Binding<String> {
        Binding(
            get: {
                guard let selectedNoteID else { return "" }
                return appState.noteContent(for: selectedNoteID)
            },
            set: { newValue in
                guard let selectedNoteID else { return }
                appState.updateNoteContent(newValue, for: selectedNoteID)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorTopBar(
                bridge: bridge,
                styleState: $styleState,
                onAskAI: {
                    appState.selectedMode = .ai
                },
                onGenerateStudyMaterials: {
                    appState.selectedMode = .study
                },
                onAnalyzeLecture: {
                    onAnalyzeLecture()
                },
                onUpdateKnowledgeGraph: {
                    triggerKnowledgeGraphUpdate()
                },
                isGeneratingStudyMaterials: false,
                isKnowledgeGraphGenerating: selectedNoteID.flatMap { knowledgeGraphManager.generationStateByNoteID[$0]?.isGenerating } ?? false,
                canGenerateStudyMaterials: selectedNoteID != nil,
                canUpdateKnowledgeGraph: selectedNoteID != nil
            )
            .background(Color.bgEditor)
            .zIndex(2)

            Divider()
                .opacity(0.08)

            VStack(alignment: .leading, spacing: 14) {

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(noteTitle)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                    }

                    Spacer()
                }

                if let selectedNoteID {

                    ZStack(alignment: .topLeading) {

                        AITextView(
                            documentID: selectedNoteID,
                            documentText: noteContentBinding.wrappedValue,
                            onDebouncedTextChange: { newText in
                                appState.updateNoteContent(newText, for: selectedNoteID)
                            },
                            onSelectionChange: { text, range in
                                selectedText = text
                                selectedRange = range
                            },
                            onReady: { newBridge in
                                bridge = newBridge
                            },
                            onSummarize: { performSelectionAction(.summarize) },
                            onRewrite: { performSelectionAction(.rewrite) },
                            onExplain: { performSelectionAction(.explain) },
                            onAdd: { performSelectionAction(.ask) },
                            onStyleChange: { styleState = $0 },
                            onAIBlockFollowUp: { followUp, block in
                                performAIBlockFollowUp(followUp, block: block)
                            }
                        )

                        if let activeSelectionAction {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(selectionActionTitle(for: activeSelectionAction))
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.borderSubtle, lineWidth: 0.5)
                            )
                            .padding(14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        }

                    }
                    .background(Color.white)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                        .stroke(
                            Color.black.opacity(0.06),
                            lineWidth: 1
                        )
                    )

                } else {

                    VStack(alignment: .leading, spacing: 8) {
                        Text("No note selected")
                            .font(.headline)

                        Text("Choose a note from the sidebar to begin editing.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .background(Color.white.opacity(0.75))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 18,
                            style: .continuous
                        )
                    )
                }
            }
            .padding(20)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(Color.bgEditor)
        .clipped()
        .animation(.easeInOut(duration: 0.18), value: activeSelectionAction != nil)
    }

    private func performSelectionAction(_ action: AIAction) {
        guard let selection = bridge.selectedTextAndRange() ?? selectedSelection() else { return }
        guard !selection.text.isEmpty else { return }
        guard let noteID = selectedNoteID else { return }
        guard activeSelectionAction == nil else { return }

        let noteContext = appState.noteContent(for: noteID)
        let prompt = prompt(for: action, selectedText: selection.text, noteContext: noteContext)
        let requestKind = requestKind(for: action, selectedText: selection.text)
        activeSelectionAction = action

        AIService.shared.run(prompt: prompt, contextLength: noteContext.count, kind: requestKind) { response in
            DispatchQueue.main.async {
                bridge.insertAIResult(action: action, response: response, selectionRange: selection.range)
                activeSelectionAction = nil
            }
        }
    }

    private func performAIBlockFollowUp(_ followUp: AIBlockFollowUp, block: AIBlockSelection) {
        guard let textView = bridge.textView else { return }
        let prompt = """
        \(followUp.title) the following generated passage while preserving the note's context:

        \(block.content)
        """
        bridge.beginAIStreaming(title: followUp.title, selectionRange: block.contentRange)
        AIService.shared.runStreaming(
            prompt: prompt,
            contextLength: textView.string.count,
            kind: .followUp,
            onToken: { token in
                bridge.appendAIStreamingToken(token)
            },
            completion: {
                bridge.finishAIStreaming()
            }
        )
    }

    private func selectedSelection() -> (text: String, range: NSRange)? {
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (selectedText, selectedRange)
    }

    private func prompt(for action: AIAction, selectedText: String, noteContext: String) -> String {
        let instruction: String
        switch action {
        case .summarize:
            instruction = "Summarize the selected passage in three concise bullet points."
        case .rewrite:
            instruction = "Rewrite the selected passage for clarity and flow while preserving meaning."
        case .explain:
            instruction = "Explain the selected passage in simple language with note-aware context."
        case .add:
            instruction = "Continue the selected passage in a natural way."
        case .ask:
            instruction = "Answer the user's question about the selected passage and nearby note context."
        }

        return """
        You are helping edit a student note.

        Note context:
        \(noteContext)

        Selected text:
        \(selectedText)

        Instruction:
        \(instruction)
        """
    }

    private func requestKind(for action: AIAction, selectedText: String) -> AIRequestKind {
        switch action {
        case .summarize:
            return .summarize
        case .rewrite:
            return .rewrite(sourceLength: selectedText.count)
        case .explain:
            return .explain
        case .add:
            return .add(sourceLength: selectedText.count)
        case .ask:
            return .ask
        }
    }

    private func triggerKnowledgeGraphUpdate() {
        guard let noteID = selectedNoteID else { return }
        let liveText = bridge.textView?.string ?? noteContentBinding.wrappedValue
        let trimmed = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            appState.updateNoteContent("", for: noteID)
            return
        }

        if appState.noteContent(for: noteID) != liveText {
            appState.updateNoteContent(liveText, for: noteID)
            return
        }

        let snapshot = NoteFile(
            id: noteID,
            title: noteTitle,
            content: liveText,
            updatedAt: appState.noteUpdatedAt(for: noteID) ?? Date()
        )
        KnowledgeGraphManager.shared.generateGraph(note: snapshot)
    }

    private func selectionActionTitle(for action: AIAction) -> String {
        switch action {
        case .summarize:
            return "Summarizing"
        case .rewrite:
            return "Rewriting"
        case .explain:
            return "Explaining"
        case .add:
            return "Adding"
        case .ask:
            return "Thinking"
        }
    }
}
