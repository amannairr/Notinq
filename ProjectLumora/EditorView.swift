import SwiftUI
import AppKit

struct EditorView: View {

    @EnvironmentObject var appState: AppState

    @State private var text: String = ""

    @State private var selectedText: String = ""
    @State private var selectedRange: NSRange? = nil

    @State private var isLoadingAI = false
    @State private var textBridge: TextViewBridge?

    @State private var showAssistant = false
    @State private var aiInput = ""
    @State private var styleState = TextStyleState()
    @State private var flashcards: [Flashcard] = []
    @State private var currentFlashcardIndex = 0
    @State private var isFlashcardRevealed = false

    var body: some View {
        GeometryReader { geo in
            ZStack {

                // 🔹 MAIN CONTENT
                VStack(spacing: 0) {

                    EditorTopBar(
                        bridge: textBridge,
                        styleState: $styleState,
                        onAskAI: {
                            withAnimation(.easeOut(duration: 0.16)) {
                                showAssistant = true
                            }
                        }
                    )
                    Divider().overlay(Color.borderSubtle.opacity(0.65))

                    VStack(spacing: 0) {

                        ZStack {
                            Color.clear
                            .ignoresSafeArea()

                            HStack {
                                Spacer(minLength: 18)

                                AITextView(
                                    text: $text,
                                    onSelectionChange: { selected, range in
                                        selectedText = selected
                                        selectedRange = range
                                    },
                                    onReady: { bridge in
                                        textBridge = bridge
                                    },
                                    onSummarize: {
                                        runAI(action: .summarize)
                                    },
                                    onRewrite: {
                                        runAI(action: .rewrite)
                                    },
                                    onExplain: {
                                        runAI(action: .explain)
                                    },
                                    onAdd: {
                                        runAI(action: .add)
                                    },
                                    onStyleChange: { style in
                                        styleState = style
                                    },
                                    onAIBlockFollowUp: { followUp, block in
                                        runAIBlockFollowUp(followUp, block: block)
                                    }
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)

                                Spacer(minLength: 18)
                            }
                        }
                    }
                }

                // 🔹 LOADING
                if isLoadingAI {
                    ProgressView()
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .position(x: geo.size.width / 2, y: geo.size.height - 60)
                }

                if showAssistant {
                    AskAIPanel(
                        text: $aiInput,
                        isLoading: isLoadingAI,
                        onSubmit: runAskAI,
                        onClose: {
                            withAnimation(.easeOut(duration: 0.14)) {
                                showAssistant = false
                            }
                        }
                    )
                    .frame(width: min(520, geo.size.width - 80))
                    .position(x: geo.size.width / 2, y: 106)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(5)
                }

                if appState.selectedMode == .study {
                    FlashcardStudyOverlay(
                        flashcards: flashcards,
                        currentIndex: $currentFlashcardIndex,
                        isRevealed: $isFlashcardRevealed,
                        isGenerating: isLoadingAI,
                        onGenerate: generateFlashcards
                    )
                    .frame(width: min(520, geo.size.width - 96))
                    .position(x: geo.size.width / 2, y: min(geo.size.height - 210, max(260, geo.size.height * 0.48)))
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(4)
                }
            }
        }
        .onChange(of: appState.selectedMode) { _, mode in
            if mode == .ai {
                withAnimation(.easeOut(duration: 0.16)) {
                    showAssistant = true
                }
            } else {
                showAssistant = false
            }
        }
        .onChange(of: appState.selectedNoteContent) { _, newValue in
            if text != newValue {
                text = newValue
            }
        }
        .onChange(of: text) { _, newValue in
            appState.updateSelectedNoteContent(newValue)
        }
        .onAppear {
            text = appState.selectedNoteContent
        }
    }

    // MARK: - MODE HEADER

    func modeHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.bgEditor.opacity(0.85))
    }

    // MARK: - AI

    func runAI(action: AIAction) {
        guard let bridge = textBridge else { return }
        guard let selection = bridge.selectedTextAndRange() else { return }
        let prompt = generatePrompt(action: action, selectedText: selection.text)
        let contextLength = selection.text.count
        isLoadingAI = true
        bridge.beginAIStreaming(action: action, selectionRange: selection.range)
        AIService.shared.runStreaming(
            prompt: prompt,
            contextLength: contextLength,
            kind: requestKind(for: action, sourceLength: selection.text.count),
            onToken: { token in
                bridge.appendAIStreamingToken(token)
            },
            completion: {
                bridge.finishAIStreaming()
                self.isLoadingAI = false
                self.selectedText = ""
                self.selectedRange = nil
            }
        )
    }

    func runAIFinal(action: AIAction) {
        guard let bridge = textBridge else { return }
        guard let selection = bridge.selectedTextAndRange() else { return }
        let prompt = generatePrompt(action: action, selectedText: selection.text)
        let contextLength = selection.text.count
        isLoadingAI = true
        AIService.shared.run(prompt: prompt, contextLength: contextLength, kind: requestKind(for: action, sourceLength: selection.text.count)) { response in
            if !response.isEmpty {
                bridge.insertAIResult(action: action, response: response, selectionRange: selection.range)
            }
            self.isLoadingAI = false
            self.selectedText = ""
            self.selectedRange = nil
        }
    }

    func runAIBlockFollowUp(_ followUp: AIBlockFollowUp, block: AIBlockSelection) {
        guard let bridge = textBridge else { return }
        let prompt = generateFollowUpPrompt(followUp, block: block)
        let contextLength = block.content.count
        isLoadingAI = true

        let didPrepareBlock: Bool
        switch followUp {
        case .continueWriting:
            didPrepareBlock = bridge.beginAIBlockContinuation(block)
        case .regenerate, .shorter, .moreDetailed:
            didPrepareBlock = bridge.beginAIBlockRewrite(block)
        }

        guard didPrepareBlock else {
            isLoadingAI = false
            return
        }

        AIService.shared.runStreaming(
            prompt: prompt,
            contextLength: contextLength,
            kind: .followUp,
            onToken: { token in
                bridge.appendAIStreamingToken(token)
            },
            completion: {
                bridge.finishAIStreaming()
                self.isLoadingAI = false
            }
        )
    }

    func runAskAI() {
        guard let bridge = textBridge else { return }
        let question = aiInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        let context = bridge.selectedTextOrDocumentContext(fallback: appState.selectedNoteContent)
        guard !context.text.isEmpty else { return }

        let prompt = generateAskPrompt(question: question, context: context.text)
        aiInput = ""
        showAssistant = false
        isLoadingAI = true
        bridge.beginAIStreaming(title: "Ask AI", selectionRange: context.range)

        AIService.shared.runStreaming(
            prompt: prompt,
            contextLength: context.text.count + question.count,
            kind: .ask,
            onToken: { token in
                bridge.appendAIStreamingToken(token)
            },
            completion: {
                bridge.finishAIStreaming()
                self.isLoadingAI = false
            }
        )
    }

    func generateFlashcards() {
        guard let bridge = textBridge else { return }
        let context = bridge.selectedTextOrDocumentContext(fallback: appState.selectedNoteContent)
        guard !context.text.isEmpty else { return }

        isLoadingAI = true
        let prompt = generateFlashcardPrompt(context: context.text)
        AIService.shared.run(
            prompt: prompt,
            contextLength: context.text.count,
            kind: .flashcards
        ) { response in
            self.flashcards = parseFlashcards(from: response)
            self.currentFlashcardIndex = 0
            self.isFlashcardRevealed = false
            self.isLoadingAI = false
        }
    }

    func requestKind(for action: AIAction, sourceLength: Int) -> AIRequestKind {
        switch action {
        case .summarize:
            return .summarize
        case .rewrite:
            return .rewrite(sourceLength: sourceLength)
        case .explain:
            return .explain
        case .add:
            return .add(sourceLength: sourceLength)
        }
    }

    func generatePrompt(action: AIAction, selectedText: String) -> String {
        let instruction = """
        You are an editorial writing assistant inside a document editor.
        Respond with plain text only. Be concise, natural, and non-repetitive.
        Preserve the writer's tone and avoid generic AI phrasing.

        """
        switch action {
        case .summarize:
            return instruction + "Summarize the following text in 2-3 concise sentences while preserving the key ideas.\n\n\(selectedText)"
        case .rewrite:
            return instruction + "Rewrite the following text to improve clarity, flow, and readability. Keep the meaning and voice intact. Return only the rewritten passage.\n\n\(selectedText)"
        case .explain:
            return instruction + "Explain the following text clearly in a short paragraph. Avoid over-explaining.\n\n\(selectedText)"
        case .add:
            return instruction + "Continue the following text naturally in the same tone and writing style. Add only the next short passage, not a summary.\n\n\(selectedText)"
        }
    }

    func generateAskPrompt(question: String, context: String) -> String {
        """
        You are a document-centered writing and study assistant.
        Answer the user's request using the provided note context.
        Be concise, useful, and specific. If the user asks for writing help, return polished prose they can keep.
        Respond with plain text only.

        User request:
        \(question)

        Note context:
        \(context)
        """
    }

    func generateFlashcardPrompt(context: String) -> String {
        """
        Create 6 to 10 study flashcards from the note context.
        Extract key concepts, definitions, important relationships, and likely exam questions.
        Keep answers clear and concise.
        Use exactly this format for each card:
        Front: question or concept
        Back: answer or explanation

        Note context:
        \(context)
        """
    }

    func parseFlashcards(from response: String) -> [Flashcard] {
        let normalized = response.replacingOccurrences(of: "\r\n", with: "\n")
        let chunks = normalized.components(separatedBy: "Front:")
        let cards = chunks.compactMap { chunk -> Flashcard? in
            let parts = chunk.components(separatedBy: "Back:")
            guard parts.count >= 2 else { return nil }
            let front = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let back = parts.dropFirst().joined(separator: "Back:").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { return nil }
            return Flashcard(front: front, back: back)
        }

        if !cards.isEmpty {
            return cards
        }

        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return stride(from: 0, to: lines.count - 1, by: 2).map {
            Flashcard(front: lines[$0], back: lines[$0 + 1])
        }
    }

    func generateFollowUpPrompt(_ followUp: AIBlockFollowUp, block: AIBlockSelection) -> String {
        let instruction = """
        You are refining generated writing inside a document.
        Respond with plain text only. Keep the result concise, readable, and natural.
        Do not mention that you are an AI.

        """

        switch followUp {
        case .regenerate:
            return instruction + "Regenerate this \(block.actionTitle.lowercased()) with a cleaner, more natural phrasing while preserving its intent.\n\n\(block.content)"
        case .shorter:
            return instruction + "Make this shorter without losing the essential meaning.\n\n\(block.content)"
        case .moreDetailed:
            return instruction + "Add useful detail while keeping the result focused and not verbose.\n\n\(block.content)"
        case .continueWriting:
            return instruction + "Continue this passage in the same tone. Write only the next short continuation.\n\n\(block.content)"
        }
    }
}

struct Flashcard: Identifiable, Equatable {
    let id = UUID()
    let front: String
    let back: String
}

struct AskAIPanel: View {
    @Binding var text: String
    let isLoading: Bool
    let onSubmit: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.textSecondary)
                TextField("Ask AI about this note...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...3)
                    .onSubmit(onSubmit)
                Button(action: onSubmit) {
                    Image(systemName: isLoading ? "hourglass" : "arrow.up")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.hoverWarm)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.textTertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text("Uses the selection when available, otherwise the current note.")
                    .font(.system(size: 11))
                    .foregroundColor(Color.textTertiary)
                Spacer()
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .background(Color.bgEditor.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderSubtle.opacity(0.75), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.07), radius: 18, x: 0, y: 8)
    }
}

struct FlashcardStudyOverlay: View {
    let flashcards: [Flashcard]
    @Binding var currentIndex: Int
    @Binding var isRevealed: Bool
    let isGenerating: Bool
    let onGenerate: () -> Void

    private var currentCard: Flashcard? {
        guard flashcards.indices.contains(currentIndex) else { return nil }
        return flashcards[currentIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Study")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.textPrimary)
                    Text(flashcards.isEmpty ? "Generate flashcards from this note" : "\(currentIndex + 1) of \(flashcards.count)")
                        .font(.system(size: 11))
                        .foregroundColor(Color.textTertiary)
                }
                Spacer()
                Button(isGenerating ? "Generating..." : "Generate Flashcards", action: onGenerate)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.textSecondary)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.hoverWarm)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .disabled(isGenerating)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isRevealed.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(isRevealed ? "Back" : "Front")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.textTertiary)
                    Text(currentCard.map { isRevealed ? $0.back : $0.front } ?? "Select text or use the current note to create a calm study set.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Color.textPrimary)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                }
                .padding(18)
                .background(Color.bgEditor.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.borderSubtle.opacity(0.8), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .rotation3DEffect(.degrees(isRevealed ? 1 : 0), axis: (x: 0, y: 1, z: 0))

            HStack(spacing: 8) {
                Button {
                    move(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(flashcards.isEmpty)

                Button(isRevealed ? "Hide answer" : "Reveal answer") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isRevealed.toggle()
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.hoverWarm)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .disabled(flashcards.isEmpty)

                Button {
                    move(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 30, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(flashcards.isEmpty)

                Spacer()
            }
            .foregroundColor(Color.textSecondary)
            .font(.system(size: 13, weight: .medium))
        }
        .padding(14)
        .background(.thinMaterial)
        .background(Color.bgNotesPane.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderSubtle.opacity(0.7), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 10)
    }

    private func move(by delta: Int) {
        guard !flashcards.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            currentIndex = min(max(0, currentIndex + delta), flashcards.count - 1)
            isRevealed = false
        }
    }
}
