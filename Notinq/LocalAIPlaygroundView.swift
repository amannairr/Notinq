import SwiftUI

#if DEBUG
struct LocalAIPlaygroundView: View {
    @State private var promptText = "Explain cell respiration in three concise bullets."
    @State private var responseText = ""
    @State private var statusText = "Idle"
    @State private var isStreaming = true
    @State private var temperature = 0.6
    @State private var topP = 0.9
    @State private var maxTokens = 256.0
    @State private var latency: TimeInterval = 0
    @State private var isGenerating = false
    @State private var loadedModel: LocalModel?

    private let provider = LocalAIProvider.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            modelSummary
            controls
            promptEditor
            responseEditor
            footer
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 760)
        .onAppear {
            refreshModelInfo()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Local AI Playground")
                .font(.system(size: 22, weight: .semibold))
            Text("Developer-only GGUF runtime surface.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var modelSummary: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(title: "Loaded model", value: loadedModel?.name ?? "Not loaded")
                summaryRow(title: "Path", value: loadedModel?.path ?? "Unavailable")
                summaryRow(title: "Context", value: loadedModel.map { "\($0.contextLength)" } ?? "Unavailable")
                summaryRow(title: "Quantization", value: loadedModel?.quantization ?? "Unavailable")
                summaryRow(title: "Memory", value: loadedModel.map { Self.formatBytes($0.size) } ?? "Unavailable")
                summaryRow(title: "Latency", value: latency > 0 ? String(format: "%.2fs", latency) : "Unavailable")
                summaryRow(title: "Status", value: statusText)
            }
        } label: {
            Text("Runtime")
        }
    }

    private var controls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Streaming", isOn: $isStreaming)
                    .onChange(of: isStreaming) { _, _ in syncConfiguration() }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.2f", temperature))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $temperature, in: 0.0...1.5, step: 0.05)
                        .onChange(of: temperature) { _, _ in syncConfiguration() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Top P")
                        Spacer()
                        Text(String(format: "%.2f", topP))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $topP, in: 0.0...1.0, step: 0.01)
                        .onChange(of: topP) { _, _ in syncConfiguration() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Max Tokens")
                        Spacer()
                        Text("\(Int(maxTokens))")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $maxTokens, in: 32...1024, step: 16)
                        .onChange(of: maxTokens) { _, _ in syncConfiguration() }
                }

                HStack {
                    Button(isGenerating ? "Generating..." : "Generate") {
                        Task { await generate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Cancel") {
                        provider.cancel()
                        statusText = "Cancelled"
                        isGenerating = false
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isGenerating)

                    Spacer()
                }
            }
        } label: {
            Text("Controls")
        }
    }

    private var promptEditor: some View {
        GroupBox {
            TextEditor(text: $promptText)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 150)
        } label: {
            Text("Prompt")
        }
    }

    private var responseEditor: some View {
        GroupBox {
            TextEditor(text: $responseText)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 220)
        } label: {
            Text("Response")
        }
    }

    private var footer: some View {
        Text(statusText)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
    }

    private func syncConfiguration() {
        provider.updateConfiguration(
            AIConfiguration(
                defaultTemperature: temperature,
                defaultTopP: topP,
                defaultTopK: 40,
                defaultRepeatPenalty: 1.1,
                defaultMaxTokens: Int(maxTokens),
                defaultContextSize: 2_048,
                streamingEnabled: isStreaming
            )
        )
    }

    @MainActor
    private func refreshModelInfo() {
        loadedModel = provider.modelInfo()
        syncConfiguration()
    }

    @MainActor
    private func generate() async {
        isGenerating = true
        responseText = ""
        statusText = "Loading model..."
        refreshModelInfo()

        let request = InferenceRequest(
            systemPrompt: "You are a deterministic local writing assistant.",
            userPrompt: promptText,
            temperature: temperature,
            topP: topP,
            topK: 40,
            repeatPenalty: 1.1,
            maxTokens: Int(maxTokens),
            stream: isStreaming
        )

        let started = Date()
        do {
            try await provider.loadModel()
            loadedModel = provider.modelInfo()
            statusText = isStreaming ? "Streaming..." : "Generating..."
            if isStreaming {
                let response = try await provider.generateStream(request) { token in
                    Task { @MainActor in
                        responseText += token
                    }
                }
                responseText = response.text.isEmpty ? responseText : response.text
                latency = response.latency
            } else {
                let response = try await provider.generate(request)
                responseText = response.text
                latency = response.latency
            }
            let elapsed = Date().timeIntervalSince(started)
            statusText = String(format: "Completed in %.2fs", elapsed)
        } catch {
            statusText = error.localizedDescription
            responseText = responseText.isEmpty ? "Generation failed: \(error.localizedDescription)" : responseText
        }

        isGenerating = false
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
}
#endif
