import SwiftUI

struct AIWorkspaceView: View {
    let noteTitle: String
    let noteText: String
    let lastUpdatedAt: Date?

    @State private var inputText: String = ""
    @State private var messages: [AIWorkspaceMessage] = []
    @State private var isSending = false

    private let actionColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 1120

            VStack(spacing: 18) {
                headerCard

                Group {
                    if isWide {
                        HStack(alignment: .top, spacing: 18) {
                            conversationColumn
                                .frame(maxWidth: .infinity)

                            contextPanel
                                .frame(width: min(320, proxy.size.width * 0.28))
                        }
                    } else {
                        VStack(spacing: 18) {
                            conversationColumn
                            contextPanel
                        }
                    }
                }

                suggestedActionsSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(backgroundGradient.ignoresSafeArea())
            .onAppear {
                if messages.isEmpty {
                    messages = [
                        AIWorkspaceMessage(
                            role: .assistant,
                            text: assistantGreeting,
                            timestamp: Date()
                        )
                    ]
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Assistant")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Current Note: \(currentNoteLabel)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Context-aware help tied to the active note.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            noteMetaPillGroup
        }
        .padding(18)
        .background(glassSurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 0.8)
        )
    }

    private var currentNoteLabel: String {
        noteTitle.isEmpty ? "Untitled Note" : noteTitle
    }

    private var noteMetaPillGroup: some View {
        VStack(alignment: .trailing, spacing: 8) {
            metaPill(
                title: "Word Count",
                value: "\(wordCount)",
                tint: Color(red: 0.23, green: 0.47, blue: 0.59)
            )
            metaPill(
                title: "Reading Time",
                value: readingTimeLabel,
                tint: Color(red: 0.32, green: 0.56, blue: 0.38)
            )
        }
    }

    private var conversationColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            conversationCard
            inputCard
        }
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conversation")
                        .font(.headline)
                    Text("Ask for summaries, rewrites, explanations, or study tools.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        messageBubble(message)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .frame(minHeight: 320, maxHeight: 440)
        }
        .padding(18)
        .background(glassSurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 0.8)
        )
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask something about this note")
                .font(.headline)

            TextEditor(text: $inputText)
                .frame(minHeight: 92)
                .padding(12)
                .background(Color.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Text("The assistant uses the current note for context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    sendMessage(inputText)
                } label: {
                    HStack(spacing: 8) {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                        }
                        Text("Send")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.22, green: 0.44, blue: 0.58))
                .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .background(glassSurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 0.8)
        )
    }

    private var suggestedActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Suggested Actions")
                    .font(.headline)
                Spacer()
            }

            LazyVGrid(columns: actionColumns, spacing: 12) {
                actionCard(
                    title: "Summarize",
                    subtitle: "Condense the note into a tight overview.",
                    icon: "doc.text",
                    tint: Color(red: 0.23, green: 0.47, blue: 0.59)
                ) {
                    runPresetAction(.summarize)
                }

                actionCard(
                    title: "Rewrite",
                    subtitle: "Improve clarity while keeping meaning.",
                    icon: "pencil.and.outline",
                    tint: Color(red: 0.46, green: 0.32, blue: 0.21)
                ) {
                    runPresetAction(.rewrite)
                }

                actionCard(
                    title: "Explain",
                    subtitle: "Break down a hard concept simply.",
                    icon: "lightbulb",
                    tint: Color(red: 0.32, green: 0.56, blue: 0.38)
                ) {
                    runPresetAction(.explain)
                }

                actionCard(
                    title: "Create Flashcards",
                    subtitle: "Turn key ideas into memory cues.",
                    icon: "rectangle.stack",
                    tint: Color(red: 0.54, green: 0.38, blue: 0.61)
                ) {
                    runPresetAction(.flashcards)
                }

                actionCard(
                    title: "Generate Quiz",
                    subtitle: "Check understanding with questions.",
                    icon: "checklist",
                    tint: Color(red: 0.60, green: 0.45, blue: 0.20)
                ) {
                    runPresetAction(.quiz)
                }

                actionCard(
                    title: "Extract Key Points",
                    subtitle: "Find the terms worth reviewing first.",
                    icon: "tray.full",
                    tint: Color(red: 0.27, green: 0.43, blue: 0.55)
                ) {
                    runPresetAction(.keyPoints)
                }
            }
        }
        .padding(18)
        .background(glassSurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 0.8)
        )
    }

    private var contextPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Context")
                        .font(.headline)
                    Text("Note details and quick stats.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            contextMetric(title: "Current Note", value: noteTitle.isEmpty ? "Untitled Note" : noteTitle)
            contextMetric(title: "Word Count", value: "\(wordCount)")
            contextMetric(title: "Reading Time", value: readingTimeLabel)
            contextMetric(title: "Last Updated", value: lastUpdatedLabel)

            VStack(alignment: .leading, spacing: 8) {
                Text("Note Preview")
                    .font(.headline)
                Text(notePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(18)
        .background(glassSurface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 0.8)
        )
    }

    private func messageBubble(_ message: AIWorkspaceMessage) -> some View {
        HStack {
            if message.role == .assistant { Spacer(minLength: 0) }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(message.role == .user ? "You" : "Assistant")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(message.role == .user ? Color.white.opacity(0.9) : Color.textSecondary)

                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(message.role == .user ? Color.white.opacity(0.7) : Color.textTertiary)
                }

                renderedMessageText(message.text)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? Color.white : Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
            .padding(16)
            .frame(maxWidth: 620, alignment: .leading)
            .background {
                if message.role == .user {
                    userBubbleBackground
                } else {
                    assistantBubbleBackground
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(message.role == .user ? Color.white.opacity(0.08) : Color.borderSubtle, lineWidth: 0.6)
            )

            if message.role == .user { Spacer(minLength: 0) }
        }
    }

    private func actionCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .background(tint.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color.bgElevated, tint.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.borderSubtle, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func runPresetAction(_ preset: AIWorkspacePreset) {
        let prompt = PromptRegistry.shared.workspacePresetRequest(for: preset)
        inputText = prompt
        sendMessage(prompt)
    }

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        messages.append(
            AIWorkspaceMessage(role: .user, text: trimmed, timestamp: Date())
        )
        inputText = ""
        isSending = true

        AIService.shared.chat(noteTitle: noteTitle, noteText: truncate(noteText, limit: 4000), userRequest: trimmed) { response in
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
            messages.append(
                AIWorkspaceMessage(
                    role: .assistant,
                    text: cleaned.isEmpty ? "I could not generate a response for that request." : cleaned,
                    timestamp: Date()
                )
            )
            isSending = false
        }
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n[Context truncated]"
    }

    private func metaPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 120, alignment: .leading)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func contextMetric(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var notePreview: String {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No note content yet. Add text to give the assistant context." }
        return String(trimmed.prefix(220)) + (trimmed.count > 220 ? "..." : "")
    }

    private var wordCount: Int {
        noteText.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var readingTimeLabel: String {
        let minutes = max(1, Int(ceil(Double(wordCount) / 220.0)))
        return "\(minutes) min"
    }

    private var lastUpdatedLabel: String {
        guard let lastUpdatedAt else { return "Unknown" }
        return lastUpdatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var assistantGreeting: String {
        let noteName = noteTitle.isEmpty ? "this note" : noteTitle
        return "I’m ready to help with \(noteName). Try summarize, rewrite, explain, or turn it into study tools."
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.bgEditor.opacity(0.96),
                Color.bgPrimary.opacity(0.98),
                Color.bgEditor.opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glassSurface: some View {
        Color.bgElevated
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
    }

    private var userBubbleBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.20, green: 0.40, blue: 0.56),
                Color(red: 0.18, green: 0.48, blue: 0.54)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var assistantBubbleBackground: some View {
        Color.bgElevated
    }

    @ViewBuilder
    private func renderedMessageText(_ text: String) -> some View {
        if let attributed = text.markdownAttributedString() {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}

struct AIWorkspaceMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date
}
