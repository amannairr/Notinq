import SwiftUI
import AppKit

struct EditorView: View {
    @EnvironmentObject private var appState: AppState
    var onAnalyzeLecture: () -> Void = {}
    var onUpdateKnowledgeGraph: () -> Void = {}
    var onGenerateStudyMaterials: () -> Void = {}
    @State private var styleState = TextStyleState()
    @State private var bridge = TextViewBridge()
    @State private var selectedText = ""
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var activeSelectionAction: AIAction?
    @ObservedObject private var knowledgeGraphManager = KnowledgeGraphManager.shared

    private var selectedNoteID: UUID? {
        appState.selectedNoteID
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
            if !appState.isLearningInsightsOpen {
                EditorTopBar(
                    bridge: bridge,
                    styleState: $styleState,
                    onAskAI: {
                        appState.selectedMode = .ai
                    },
                    onGenerateStudyMaterials: {
                        onGenerateStudyMaterials()
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
                .frame(height: 58)
                .background(Color.bgEditor)
                .zIndex(2)

                Divider()
                    .opacity(0.08)
            }

            ZStack(alignment: .topLeading) {
                if let selectedNoteID {
                    AITextView(
                        documentID: selectedNoteID,
                        documentText: noteContentBinding.wrappedValue,
                        onDebouncedTextChange: { newText in
                            Task { @MainActor in
                                appState.updateNoteContent(newText, for: selectedNoteID)
                            }
                        }, 
                        onSelectionChange: { text, range in
                            Task { @MainActor in
                                guard text != selectedText || range != selectedRange else { return }
                                selectedText = text
                                selectedRange = range
                            }
                        },
                        onReady: { newBridge in
                            Task { @MainActor in
                                bridge.textView = newBridge.textView
                            }
                        },
                        onSummarize: { performSelectionAction(.summarize) },
                        onSimplify: { performSelectionAction(.simplify) },
                        onRewrite: { performSelectionAction(.rewrite) },
                        onExplain: { performSelectionAction(.explain) },
                        onFlashcards: {
                            Task { @MainActor in
                                appState.selectedMode = .study
                            }
                        },
                        onQuiz: {
                            Task { @MainActor in
                                appState.selectedMode = .study
                            }
                        },
                        onAdd: { performSelectionAction(.ask) },
                        onCopy: { copySelectedText() },
                        onStyleChange: { styleState = $0 },
                onAIBlockFollowUp: { followUp, block in
                            performAIBlockFollowUp(followUp, block: block)
                        }
                    )
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

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
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No note selected")
                            .font(.headline)

                        Text("Choose a note from the sidebar to begin editing.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgEditor)
        .animation(.easeInOut(duration: 0.18), value: activeSelectionAction != nil)
    }

    private func performSelectionAction(_ action: AIAction) {
        guard let selection = bridge.selectedTextAndRange() ?? selectedSelection() else { return }
        guard !selection.text.isEmpty else { return }
        guard let noteID = selectedNoteID else { return }
        guard activeSelectionAction == nil else { return }

        let noteContext = appState.noteContent(for: noteID)
        activeSelectionAction = action

        AIService.shared.directEdit(action: action, selectedText: selection.text, noteContext: noteContext) { response in
            DispatchQueue.main.async {
                bridge.insertAIResult(action: action, response: response, selectionRange: selection.range)
                activeSelectionAction = nil
            }
        }
    }

    private func performAIBlockFollowUp(_ followUp: AIBlockFollowUp, block: AIBlockSelection) {
        guard let textView = bridge.textView else { return }
        let noteContext = textView.string
        bridge.beginAIStreaming(title: followUp.title, selectionRange: block.contentRange)
        AIService.shared.streamFollowUp(
            noteContext: noteContext,
            followUpTitle: followUp.title,
            blockContent: block.content,
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
            title: appState.noteTitle(for: noteID),
            content: liveText,
            updatedAt: appState.noteUpdatedAt(for: noteID) ?? Date()
        )
        KnowledgeGraphManager.shared.generateGraph(note: snapshot)
    }

    private func selectionActionTitle(for action: AIAction) -> String {
        switch action {
        case .summarize:
            return "Summarizing"
        case .simplify:
            return "Simplifying"
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

    private func copySelectedText() {
        let text = bridge.selectedTextAndRange()?.text ?? selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
