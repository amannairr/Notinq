import Combine
import Foundation
import SwiftUI

@MainActor
final class AIEvaluationSuite: ObservableObject {
    static let shared = AIEvaluationSuite()

    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Idle"
    @Published private(set) var latestRun: AIEvaluationRunner.ResultBundle?
    @Published private(set) var recentRuns: [AIEvaluationRunManifest] = []
    @Published private(set) var comparisonReport: AIEvaluationComparisonReport?
    @Published private(set) var regressionReport: AIEvaluationRegressionReport?
    @Published private(set) var benchmarkReport: AIEvaluationBenchmarkReport?
    @Published private(set) var promptImprovementReport: AIEvaluationPromptImprovementReport?
    @Published private(set) var promptVersionComparisonReport: AIPromptVersionComparisonReport?
    @Published var selectedNoteID: String?
    @Published var selectedNoteSet: AIEvaluationNoteSet = .all
    @Published var selectedModelID: String = ""
    @Published var lastExportURL: URL?

    private let runner = AIEvaluationRunner()

    private init() {
        refreshRecentRuns()
        if selectedModelID.isEmpty {
            selectedModelID = ModelManager.shared.activeModelIDDescription()
        }
    }

    var availableNotes: [AIEvaluationNote] {
        AIEvaluationSamples.notesBySet[selectedNoteSet] ?? AIEvaluationSamples.notes
    }

    var availableModels: [AIModelDefinition] {
        ModelManager.shared.availableModels()
    }

    func runEvaluation() async {
        guard !isRunning else { return }
        isRunning = true
        statusMessage = "Running evaluation for \(selectedNoteSet.title)..."

        do {
            let modelSelection = selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            let bundle = try await runner.run(noteSet: selectedNoteSet, selectedModelID: modelSelection.isEmpty ? nil : modelSelection)
            latestRun = bundle
            lastExportURL = bundle.outputRootURL
            selectedNoteID = bundle.noteResults.first?.noteID
            statusMessage = "Evaluation finished for \(bundle.manifest.resultCount) notes."
            refreshRecentRuns()
            updateComparisonIfPossible()
            updateBenchmarkAndRecommendations()
            updatePromptVersionComparison()
        } catch {
            statusMessage = "Evaluation failed: \(error.localizedDescription)"
        }

        isRunning = false
    }

    func selectedNoteResult() -> AIEvaluationNoteResult? {
        guard let latestRun else { return nil }
        guard let selectedNoteID else { return latestRun.noteResults.first }
        return latestRun.noteResults.first(where: { $0.noteID == selectedNoteID }) ?? latestRun.noteResults.first
    }

    func reviewPrompt() -> String {
        guard let result = selectedNoteResult() else { return "" }
        return runner.reviewPrompt(for: result)
    }

    func exportReviewPackage() -> URL? {
        guard let latestRun, let result = selectedNoteResult() else { return nil }
        return latestRun.outputRootURL.appendingPathComponent(result.noteID, isDirectory: true)
    }

    func openOutputFolder() {
        runner.openEvaluationFolder()
    }

    func comparePreviousRuns() {
        guard recentRuns.count >= 2 else {
            comparisonReport = nil
            regressionReport = nil
            return
        }
        let baseline = recentRuns[1]
        let comparison = recentRuns[0]
        comparisonReport = runner.compare(baseline: baseline, comparison: comparison)
        if let baselineResult = baseline.noteResults.first, let comparisonResult = comparison.noteResults.first {
            regressionReport = runner.regressionReport(baseline: baselineResult, comparison: comparisonResult)
        }
        if let comparisonReport {
            let directory = runner.evaluationFolderURL().appendingPathComponent("ModelComparisons", isDirectory: true)
            let dateFolder = runner.storage.runFolderName(for: comparisonReport.generatedAt, modelName: comparisonReport.comparisonModel, promptVersion: comparisonReport.comparisonPromptVersion)
            let outputURL = directory.appendingPathComponent(dateFolder, isDirectory: true)
            try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(comparisonReport) {
                try? data.write(to: outputURL.appendingPathComponent("comparison.json"), options: .atomic)
            }
            if let regressionReport, let data = try? JSONEncoder().encode(regressionReport) {
                try? data.write(to: outputURL.appendingPathComponent("regression.json"), options: .atomic)
            }
        }
        updatePromptVersionComparison()
    }

    func refreshRecentRuns() {
        recentRuns = runner.listRecentRuns(limit: 10)
        updateBenchmarkAndRecommendations()
    }

    func loadComparisonFromRecentRuns() {
        updateComparisonIfPossible()
    }

    private func updateComparisonIfPossible() {
        guard recentRuns.count >= 2 else { return }
        comparisonReport = runner.compare(baseline: recentRuns[1], comparison: recentRuns[0])
    }

    private func updateBenchmarkAndRecommendations() {
        benchmarkReport = runner.benchmarkReport(from: recentRuns, datasetName: selectedNoteSet.title)
        if let latestRun {
            promptImprovementReport = runner.promptImprovementReport(from: latestRun.noteResults, datasetName: selectedNoteSet.title)
        }
    }

    private func updatePromptVersionComparison() {
        guard recentRuns.count >= 2 else {
            promptVersionComparisonReport = nil
            return
        }
        promptVersionComparisonReport = runner.comparePromptVersions(
            baselineVersion: recentRuns[1].promptVersion,
            comparisonVersion: recentRuns[0].promptVersion
        )
    }
}
