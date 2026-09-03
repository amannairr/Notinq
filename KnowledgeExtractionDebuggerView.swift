import SwiftUI

struct KnowledgeExtractionDebuggerView: View {
    let report: KnowledgeExtractionDebugReport
    @State private var selectedChunkIndex: Int = 0

    private var selectedChunk: KnowledgeExtractionChunkDebug? {
        guard report.chunkRuns.indices.contains(selectedChunkIndex) else { return nil }
        return report.chunkRuns[selectedChunkIndex]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summary
                warnings
                chunks
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Knowledge Extraction Debugger")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(report.title.isEmpty ? report.sourceSignature : report.title)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                metric(label: "Chunks", value: "\(report.chunkRuns.count)")
                metric(label: "Latency", value: formatSeconds(report.latency))
                metric(label: "Retries", value: "\(report.retryCount)")
            }
            GridRow {
                metric(label: "Tokens", value: "\(report.tokenCount)")
                metric(label: "From Cache", value: report.fromCache ? "Yes" : "No")
                metric(label: "Warnings", value: "\(report.validationWarnings.count)")
            }
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Validation Warnings")
                .font(.headline)
            if report.validationWarnings.isEmpty {
                Text("No warnings.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.validationWarnings, id: \.self) { warning in
                        Text(warning)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var chunks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chunk Trace")
                .font(.headline)

            if report.chunkRuns.isEmpty {
                Text("No chunk data available.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Chunk", selection: $selectedChunkIndex) {
                    ForEach(report.chunkRuns.indices, id: \.self) { index in
                        Text("Chunk \(index + 1)").tag(index)
                    }
                }
                .pickerStyle(.segmented)

                if let chunk = selectedChunk {
                    VStack(alignment: .leading, spacing: 16) {
                        section(title: "Raw Chunk", text: chunk.rawChunk)
                        section(title: "Prompt", text: chunk.prompt)
                        section(title: "Raw Model Response", text: chunk.rawModelResponse)
                        section(title: "Parsed JSON", text: chunk.parsedJSON)
                        section(title: "Merged Knowledge", text: prettyPrint(chunk.mergedKnowledge))

                        HStack(spacing: 18) {
                            metric(label: "Latency", value: formatSeconds(chunk.latency))
                            metric(label: "Retries", value: "\(chunk.retryCount)")
                            metric(label: "Tokens", value: "\(chunk.tokenCount)")
                        }

                        if !chunk.validationWarnings.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Chunk Warnings")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(chunk.validationWarnings, id: \.self) { warning in
                                    Text(warning)
                                        .font(.system(size: 12, design: .monospaced))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
        }
    }

    private func section(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text.isEmpty ? "<empty>" : text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func prettyPrint(_ knowledge: StructuredKnowledge) -> String {
        guard let data = try? JSONEncoder.prettyPrintedEncoder.encode(knowledge),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.2fs", seconds)
    }
}

private extension JSONEncoder {
    static var prettyPrintedEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

#if DEBUG
struct KnowledgeExtractionDebuggerView_Previews: PreviewProvider {
    static var previews: some View {
        KnowledgeExtractionDebuggerView(report: KnowledgeExtractionDebugReport())
    }
}
#endif
