import Foundation
import Combine
import SwiftUI

struct ExtractionTestView: View {
    @StateObject private var runner = ExtractionTestRunner()
    @State private var selectedResultID: ExtractionTestResult.ID?

    private var selectedResult: ExtractionTestResult? {
        if let selectedResultID {
            return runner.results.first(where: { $0.id == selectedResultID })
        }
        return runner.results.first
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summary

                List(runner.results, selection: $selectedResultID) { result in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(result.displayName)
                                .font(.headline)
                            Spacer()
                            Text(result.statusLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(result.statusTint)
                        }

                        HStack(spacing: 14) {
                            metric(label: "Concepts", value: "\(result.conceptCount)")
                            metric(label: "Relationships", value: "\(result.relationshipCount)")
                            metric(label: "Facts", value: "\(result.factCount)")
                            metric(label: "Time", value: result.processingTimeLabel)
                        }

                        if let message = result.loadError {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if !result.validationErrors.isEmpty {
                            Text(result.validationErrors.first ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .overlay {
                    if runner.results.isEmpty, !runner.isRunning {
                        ContentUnavailableView(
                            "No Results Yet",
                            systemImage: "testtube.2",
                            description: Text("Run the extraction benchmark to inspect outputs.")
                        )
                    }
                }
            }
            .padding(20)
            .frame(minWidth: 420, idealWidth: 500, maxWidth: 560)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await runner.runAllTests()
                        }
                    } label: {
                        if runner.isRunning {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Running...")
                            }
                        } else {
                            Text("Run Extraction Tests")
                        }
                    }
                    .disabled(runner.isRunning)
                }
            }
            .navigationTitle("Extraction Testing")
        } detail: {
            if let selectedResult {
                ExtractionDebugView(result: selectedResult)
            } else {
                ContentUnavailableView(
                    "Select a Transcript",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose a benchmark file to inspect its concepts, relationships, facts, validation, and raw JSON.")
                )
            }
        }
        .onAppear {
            if selectedResultID == nil {
                selectedResultID = runner.results.first?.id
            }
        }
        .onReceive(runner.$results) { newResults in
            if selectedResultID == nil {
                selectedResultID = newResults.first?.id
            } else if let currentSelection = selectedResultID,
                      !newResults.contains(where: { $0.id == currentSelection }) {
                selectedResultID = newResults.first?.id
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Knowledge Extraction Tests")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Runs the benchmark transcripts through the live extraction pipeline and exposes counts, validation, and raw JSON.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        let totals = runner.summary
        return Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                metric(label: "Files", value: "\(totals.fileCount)")
                metric(label: "Processed", value: "\(totals.processedCount)")
                metric(label: "Missing", value: "\(totals.missingCount)")
            }
            GridRow {
                metric(label: "Concepts", value: "\(totals.conceptCount)")
                metric(label: "Relationships", value: "\(totals.relationshipCount)")
                metric(label: "Facts", value: "\(totals.factCount)")
            }
        }
        .padding(.bottom, 4)
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
        }
    }
}

struct ExtractionTestResult: Identifiable {
    let id = UUID()
    let fileName: String
    let displayName: String
    let run: KnowledgeExtractionRun?
    let processingTime: Double
    let loadError: String?

    var conceptCount: Int { run?.canonicalExtraction.concepts.count ?? 0 }
    var relationshipCount: Int { run?.canonicalExtraction.relationships.count ?? 0 }
    var factCount: Int { run?.canonicalExtraction.facts.count ?? 0 }
    var validationErrors: [String] {
        var errors: [String] = []
        if let loadError {
            errors.append(loadError)
            return errors
        }

        guard let run else {
            errors.append("No extraction result produced.")
            return errors
        }

        if run.canonicalExtraction.concepts.isEmpty {
            errors.append("No concepts extracted.")
        }
        if run.canonicalExtraction.facts.isEmpty {
            errors.append("No facts extracted.")
        }
        if run.canonicalExtraction.relationships.isEmpty {
            errors.append("No relationships extracted.")
        }
        errors.append(contentsOf: run.debugReport.validationWarnings)
        return errors
    }

    var processingTimeLabel: String {
        String(format: "%.2fs", processingTime)
    }

    var statusLabel: String {
        if loadError != nil {
            return "Missing"
        }
        return validationErrors.isEmpty ? "Pass" : "Review"
    }

    var statusTint: Color {
        if loadError != nil {
            return .orange
        }
        return validationErrors.isEmpty ? .green : .secondary
    }
}

struct ExtractionResultSummary {
    var fileCount: Int = 0
    var processedCount: Int = 0
    var missingCount: Int = 0
    var conceptCount: Int = 0
    var relationshipCount: Int = 0
    var factCount: Int = 0
}

@MainActor
final class ExtractionTestRunner: ObservableObject {
    @Published var results: [ExtractionTestResult] = []
    @Published var isRunning = false

    private let expectedFiles = [
        "biology",
        "machine_learning",
        "statistics",
        "algorithms",
        "history",
        "chemistry",
        "economics",
        "operating_systems",
        "databases",
        "networking"
    ]

    var summary: ExtractionResultSummary {
        ExtractionResultSummary(
            fileCount: results.count,
            processedCount: results.filter { $0.loadError == nil }.count,
            missingCount: results.filter { $0.loadError != nil }.count,
            conceptCount: results.reduce(0) { $0 + $1.conceptCount },
            relationshipCount: results.reduce(0) { $0 + $1.relationshipCount },
            factCount: results.reduce(0) { $0 + $1.factCount }
        )
    }

    func runAllTests() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var newResults: [ExtractionTestResult] = []

        for fileName in expectedFiles {
            let title = fileName.replacingOccurrences(of: "_", with: " ").capitalized
            guard let url = benchmarkURL(for: fileName) else {
                newResults.append(
                    ExtractionTestResult(
                        fileName: fileName,
                        displayName: title,
                        run: nil,
                        processingTime: 0,
                        loadError: "Missing benchmark transcript: \(fileName).txt"
                    )
                )
                continue
            }

            do {
                let transcript = try String(contentsOf: url, encoding: .utf8)
                let started = Date()
                let run = await KnowledgeExtractionEngine.shared.extractRun(
                    noteTitle: title,
                    noteText: transcript
                )
                let elapsed = Date().timeIntervalSince(started)

                newResults.append(
                    ExtractionTestResult(
                        fileName: fileName,
                        displayName: title,
                        run: run,
                        processingTime: elapsed,
                        loadError: nil
                    )
                )
            } catch {
                newResults.append(
                    ExtractionTestResult(
                        fileName: fileName,
                        displayName: title,
                        run: nil,
                        processingTime: 0,
                        loadError: "Failed to load \(fileName).txt: \(error.localizedDescription)"
                    )
                )
            }
        }

        results = newResults
    }

    private func benchmarkURL(for fileName: String) -> URL? {
        let searchPaths = [
            "Notinq_Benchmark_Dataset",
            "Notinq/Notinq_Benchmark_Dataset",
            nil
        ]

        for searchPath in searchPaths {
            if let url = Bundle.main.url(forResource: fileName, withExtension: "txt", subdirectory: searchPath) {
                return url
            }
        }

        guard let resourceURL = Bundle.main.resourceURL else { return nil }

        let folderCandidates = [
            resourceURL.appendingPathComponent("Notinq_Benchmark_Dataset"),
            resourceURL.appendingPathComponent("Notinq").appendingPathComponent("Notinq_Benchmark_Dataset")
        ]

        for folder in folderCandidates {
            let candidate = folder.appendingPathComponent("\(fileName).txt")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}

struct ExtractionDebugView: View {
    let result: ExtractionTestResult

    var body: some View {
        TabView {
            ConceptsTab(concepts: result.run?.canonicalExtraction.concepts ?? [])
                .tabItem { Text("Concepts") }

            RelationshipsTab(relationships: result.run?.canonicalExtraction.relationships ?? [])
                .tabItem { Text("Relationships") }

            FactsTab(facts: result.run?.canonicalExtraction.facts ?? [])
                .tabItem { Text("Facts") }

            ValidationTab(errors: result.validationErrors)
                .tabItem { Text("Validation") }

            ScrollView {
                Text(result.prettyPrintedJSON)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .tabItem { Text("Raw JSON") }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private extension ExtractionTestResult {
    var prettyPrintedJSON: String {
        guard let run else { return "{}" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(run.canonicalExtraction),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

extension ExtractionConcept: Identifiable {}

extension ExtractionFact: Identifiable {}

extension ExtractionRelationship: Identifiable {
    var id: String {
        "\(sourceID)-\(targetID)-\(relationshipType.rawValue)"
    }
}

private struct ConceptsTab: View {
    let concepts: [ExtractionConcept]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(concepts, id: \.id) { concept in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(concept.name)
                                .font(.headline)
                            Spacer()
                            Text(String(format: "importance %.2f", concept.importanceScore))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if let descriptionText = concept.descriptionText, !descriptionText.isEmpty {
                            Text(descriptionText)
                                .font(.subheadline)
                        }

                        if !concept.aliases.isEmpty {
                            Text("Aliases: \(concept.aliases.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Confidence: \(String(format: "%.2f", concept.confidenceScore))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
        }
    }
}

private struct RelationshipsTab: View {
    let relationships: [ExtractionRelationship]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(relationships, id: \.id) { relationship in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(relationship.sourceID) → \(relationship.targetID)")
                            .font(.headline)
                        Text(relationship.relationshipType.rawValue)
                            .font(.subheadline.weight(.semibold))
                        Text("Confidence: \(String(format: "%.2f", relationship.confidenceScore))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
        }
    }
}

private struct FactsTab: View {
    let facts: [ExtractionFact]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(facts, id: \.id) { fact in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(fact.statement)
                            .font(.headline)

                        if !fact.conceptIDs.isEmpty {
                            Text("Concept IDs: \(fact.conceptIDs.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("Confidence: \(String(format: "%.2f", fact.confidenceScore))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
        }
    }
}

private struct ValidationTab: View {
    let errors: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if errors.isEmpty {
                    Label("No validation errors.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(errors, id: \.self) { error in
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}
