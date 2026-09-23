import SwiftUI
import AppKit

struct EditorView: View {
    @EnvironmentObject private var appState: AppState
    var onAnalyzeLecture: () -> Void
    var onUpdateKnowledgeGraph: () -> Void
    var onGenerateStudyMaterials: () -> Void
    private let proposalGenerator: any AIProposalGenerating
    private let learningSignalRecorder: LearningSignalRecorder
    @State private var styleState = TextStyleState()
    @State private var bridge = TextViewBridge()
    @State private var selectedText = ""
    @State private var selectedRange = NSRange(location: 0, length: 0)
    @State private var activeSelectionAction: AIAction?
    @State private var activeEditorAction: AIEditorAction?
    @State private var activeProposalRequestID: UUID?
    @State private var activeProposalTask: Task<Void, Never>?
    @State private var pendingProposal: AIProposal?
    @State private var acceptedAdaptiveProposal: AIProposal?
    @State private var editedProposalText = ""
    @ObservedObject private var knowledgeGraphManager = KnowledgeGraphManager.shared

    init(
        onAnalyzeLecture: @escaping () -> Void = {},
        onUpdateKnowledgeGraph: @escaping () -> Void = {},
        onGenerateStudyMaterials: @escaping () -> Void = {},
        proposalGenerator: any AIProposalGenerating = LiveAIProposalGenerator(),
        learningSignalRecorder: LearningSignalRecorder = LearningSignalRecorder()
    ) {
        self.onAnalyzeLecture = onAnalyzeLecture
        self.onUpdateKnowledgeGraph = onUpdateKnowledgeGraph
        self.onGenerateStudyMaterials = onGenerateStudyMaterials
        self.proposalGenerator = proposalGenerator
        self.learningSignalRecorder = learningSignalRecorder
    }

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
                .frame(minHeight: 58)
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
                        areProposalActionsDisabled: pendingProposal != nil,
                        onSummarize: { performSelectionAction(.summarize) },
                        onExpand: { performEditorAction(.expand) },
                        onSimplify: { performEditorAction(.simplify) },
                        onRewrite: { performSelectionAction(.rewrite) },
                        onExplain: { performEditorAction(.explain) },
                        onExample: { performEditorAction(.example) },
                        onAnalogy: { performEditorAction(.analogy) },
                        onDontUnderstand: { performEditorAction(.dontUnderstand) },
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

                    if let pendingProposal {
                        AIProposalPreviewView(
                            proposal: pendingProposal,
                            editedText: $editedProposalText,
                            onEdit: { newText in
                                if let proposal = self.pendingProposal {
                                    self.pendingProposal = bridge.editAIProposal(proposal, generatedText: newText)
                                }
                            },
                            onAccept: {
                                acceptPendingProposal()
                            },
                            onReject: {
                                rejectPendingProposal()
                            }
                        )
                        .padding(18)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }

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

                    if let activeEditorAction {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(editorActionTitle(for: activeEditorAction))
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }

                    if let acceptedAdaptiveProposal {
                        AdaptiveExplanationFeedbackView(
                            proposal: acceptedAdaptiveProposal,
                            onHelpful: {
                                recordAdaptiveFeedback(.markedHelpful)
                            },
                            onStillConfused: {
                                recordAdaptiveFeedback(.markedStillConfused)
                            }
                        )
                        .padding(18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
        .onChange(of: selectedNoteID) { _ in
            clearProposalState(invalidateRequest: true)
        }
    }

    private func performSelectionAction(_ action: AIAction) {
        guard let selection = bridge.selectedTextAndRange() ?? selectedSelection() else { return }
        guard !selection.text.isEmpty else { return }
        guard let noteID = selectedNoteID else { return }
        guard activeSelectionAction == nil else { return }

        let noteContext = appState.noteContent(for: noteID)
        activeSelectionAction = action

        AIService.shared.directEdit(action: action, selectedText: selection.text, noteContext: noteContext, noteID: noteID) { response in
            DispatchQueue.main.async {
                bridge.insertAIResult(action: action, response: response, selectionRange: selection.range)
                activeSelectionAction = nil
            }
        }
    }

    private func performEditorAction(_ action: AIEditorAction) {
        guard let selection = bridge.selectedTextAndRange() ?? selectedSelection() else { return }
        guard !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let noteID = selectedNoteID else { return }
        guard activeSelectionAction == nil, pendingProposal == nil else { return }

        let noteContext = bridge.textView?.string ?? appState.noteContent(for: noteID)
        let sourceRange = selection.range
        let requestID = UUID()
        let documentSnapshot = DocumentSnapshot(noteID: noteID, content: noteContext)
        activeProposalTask?.cancel()
        activeProposalRequestID = requestID
        activeEditorAction = action
        acceptedAdaptiveProposal = nil

        activeProposalTask = proposalGenerator.generate(
            action: action,
            selectedText: selection.text,
            noteContext: noteContext,
            noteID: noteID,
            requestID: requestID
        ) { completedRequestID, response in
            DispatchQueue.main.async {
                guard activeProposalRequestID == completedRequestID,
                      selectedNoteID == noteID,
                      pendingProposal == nil else {
                    return
                }
                activeProposalTask = nil
                let adaptiveContext = response.adaptiveExplanationContext ?? (action == .dontUnderstand ? .unavailable() : nil)
                guard let proposal = bridge.makeAIProposal(
                    action: action,
                    response: response.generatedText,
                    selectionRange: sourceRange,
                    originatingNoteID: noteID,
                    originatingRequestID: completedRequestID,
                    documentSnapshot: documentSnapshot,
                    provenance: AIProposalProvenance(sourceNoteRange: sourceRange),
                    adaptiveExplanationContext: adaptiveContext
                ) else {
                    if activeProposalRequestID == completedRequestID {
                        clearProposalState(invalidateRequest: true)
                    }
                    return
                }

                pendingProposal = proposal
                editedProposalText = proposal.generatedText
                bridge.restoreSelection(for: proposal)
                activeEditorAction = nil
            }
        }
    }

    private func acceptPendingProposal() {
        guard let proposal = pendingProposal else { return }
        guard proposal.originatingNoteID == selectedNoteID,
              proposal.originatingRequestID == activeProposalRequestID else {
            pendingProposal = proposal.updating(state: .invalidated)
            activeEditorAction = nil
            activeProposalRequestID = nil
            return
        }
        if let originalSnapshot = proposal.documentSnapshot,
           let currentSnapshot = currentDocumentSnapshot(),
           !originalSnapshot.matches(currentSnapshot) {
            pendingProposal = proposal.updating(state: .stale)
            activeEditorAction = nil
            return
        }
        let editedText = editedProposalText == proposal.generatedText ? nil : editedProposalText
        let accepted = bridge.acceptAIProposal(proposal, editedText: editedText)
        learningSignalRecorder.recordAccepted(proposal: proposal, finalText: accepted.generatedText)
        acceptedAdaptiveProposal = AdaptiveExplanationFeedbackView.isVisible(for: accepted) ? accepted : nil
        activeProposalRequestID = nil
        pendingProposal = nil
        editedProposalText = ""
    }

    private func rejectPendingProposal() {
        guard let proposal = pendingProposal else { return }
        activeProposalTask?.cancel()
        activeProposalTask = nil
        let rejected = bridge.rejectAIProposal(proposal)
        learningSignalRecorder.recordRejected(proposal: rejected)
        bridge.restoreSelection(for: rejected)
        clearProposalState(invalidateRequest: true)
    }

    private func recordAdaptiveFeedback(_ type: LearningSignalType) {
        guard let proposal = acceptedAdaptiveProposal else { return }
        switch type {
        case .markedHelpful:
            learningSignalRecorder.recordHelpful(proposal: proposal)
        case .markedStillConfused:
            learningSignalRecorder.recordStillConfused(proposal: proposal)
        default:
            return
        }
        acceptedAdaptiveProposal = nil
    }

    private func clearProposalState(invalidateRequest: Bool) {
        if invalidateRequest {
            activeProposalTask?.cancel()
            activeProposalTask = nil
            activeProposalRequestID = nil
        }
        activeEditorAction = nil
        acceptedAdaptiveProposal = nil
        pendingProposal = nil
        editedProposalText = ""
    }

    private func currentDocumentSnapshot() -> DocumentSnapshot? {
        guard let selectedNoteID else { return nil }
        let content = bridge.textView?.string ?? appState.noteContent(for: selectedNoteID)
        return DocumentSnapshot(noteID: selectedNoteID, content: content)
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

    private func editorActionTitle(for action: AIEditorAction) -> String {
        action.progressTitle
    }

    private func copySelectedText() {
        let text = bridge.selectedTextAndRange()?.text ?? selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct AIProposalPreviewView: View {
    let proposal: AIProposal
    @Binding var editedText: String
    let onEdit: (String) -> Void
    let onAccept: () -> Void
    let onReject: () -> Void
    @FocusState private var expandedEditorFocused: Bool

    static let actionLabels = ["Accept", "Edit", "Reject"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(proposal.action.displayTitle) Proposal")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)

            if proposal.state == .stale {
                Text("Proposal generated from an older version of this note.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            proposalSection(title: "ORIGINAL", text: proposal.originalText)

            if let adaptiveContext = proposal.adaptiveExplanationContext {
                adaptedUsingSection(lines: Self.adaptedUsingLines(from: adaptiveContext))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(proposal.action == .dontUnderstand ? "EXPLANATION" : proposal.action.previewTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary)

                TextEditor(
                    text: Binding(
                        get: { editedText },
                        set: { newValue in
                            editedText = newValue
                            onEdit(newValue)
                        }
                    )
                )
                .font(.system(size: 13))
                .frame(minHeight: 120)
                .focused($expandedEditorFocused)
                .scrollContentBackground(.hidden)
                .background(Color.bgEditor.opacity(0.64))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.borderSubtle.opacity(0.65), lineWidth: 0.6)
                )
            }

            HStack {
                Button("Reject", action: onReject)
                    .buttonStyle(.borderless)

                Spacer()

                Button("Edit") {
                    expandedEditorFocused = true
                }
                .buttonStyle(.borderless)

                Button("Accept", action: onAccept)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .background(Color.bgEditor.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.borderSubtle.opacity(0.8), lineWidth: 0.7)
        )
    }

    static func adaptedUsingLines(from context: AdaptiveExplanationContext) -> [String] {
        var lines: [String] = []

        if let prerequisite = context.missingPrerequisites.first {
            lines.append("Missing prerequisite:\n\(prerequisite)")
        }
        if let weakConcept = context.weakConcepts.first {
            lines.append("Weak concept:\n\(weakConcept)")
        }
        if let strongConcept = context.strongConcepts.first {
            lines.append("Known concept:\n\(strongConcept)")
        }
        if !context.identifiedKnowledgeGaps.isEmpty {
            lines.append("Knowledge gaps:\n\(context.identifiedKnowledgeGaps.joined(separator: "\n"))")
        } else {
            lines.append("Knowledge gaps:\nKnowledge gaps unavailable")
        }
        let sourceTitles = context.retrievedNoteSources
            .filter { !$0.groundingText.isEmpty }
            .prefix(3)
            .map { source in
                source.sectionTitle.map { "\(source.noteTitle) — \($0)" } ?? source.noteTitle
            }
        if !sourceTitles.isEmpty {
            lines.append("Sources:\n\(sourceTitles.joined(separator: "\n"))")
        } else {
            lines.append("Sources:\nSource grounding unavailable")
        }
        if !context.historicallyHelpfulConcepts.isEmpty || !context.historicallyConfusingConcepts.isEmpty {
            var history: [String] = []
            if !context.historicallyHelpfulConcepts.isEmpty {
                history.append("Previously helpful: \(context.historicallyHelpfulConcepts.joined(separator: ", "))")
            }
            if !context.historicallyConfusingConcepts.isEmpty {
                history.append("Previously confusing: \(context.historicallyConfusingConcepts.joined(separator: ", "))")
            }
            lines.append("Learning history:\n\(history.joined(separator: "\n"))")
        } else {
            lines.append("Learning history:\nLearning history unavailable")
        }
        if !context.masteryStates.isEmpty {
            let masteryLines = context.masteryStates
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .prefix(3)
                .map { "\($0.key) — \($0.value.displayTitle)" }
            lines.append("Mastery:\n\(masteryLines.joined(separator: "\n"))")
        } else {
            lines.append("Mastery:\nMastery unavailable")
        }
        lines.append("Learner level:\n\(context.inferredLearnerLevel)")

        if context.confidence > 0 {
            lines.append("Confidence:\n\(Self.confidenceLabel(context.confidence))")
        } else if !context.hasEvidence {
            lines.append("Adaptive data unavailable")
        }

        return lines
    }

    private static func confidenceLabel(_ confidence: Double) -> String {
        switch confidence {
        case ..<0.34:
            return "Low"
        case ..<0.67:
            return "Medium"
        default:
            return "High"
        }
    }

    private func proposalSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.hoverWarm.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func adaptedUsingSection(lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ADAPTED USING")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text("• \(line)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .background(Color.hoverWarm.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct AdaptiveExplanationFeedbackView: View {
    let proposal: AIProposal
    let onHelpful: () -> Void
    let onStillConfused: () -> Void

    static func isVisible(for proposal: AIProposal?) -> Bool {
        proposal?.action == .dontUnderstand
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Was this explanation helpful?")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Button("Helpful", action: onHelpful)
                .buttonStyle(.borderless)

            Button("Still Confused", action: onStillConfused)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .background(Color.bgEditor.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.borderSubtle.opacity(0.8), lineWidth: 0.7)
        )
    }
}
