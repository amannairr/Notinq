import Foundation
import AppKit

struct AIEvaluationCLI {
    let arguments: [String]

    init(arguments: [String] = CommandLine.arguments) {
        self.arguments = arguments
    }

    func run() async throws {
        let options = parseArguments(arguments)
        if options.migrationSuite {
            let bundle = try await ModelMigrationEvaluationRunner.shared.run(
                modelIDs: options.modelIDs ?? ["qwen-2-5-3b", "qwen-3-4b"],
                datasetRoot: options.datasetRootURL,
                outputRoot: options.outputRootURL
            )
            if options.openFolder {
                NSWorkspace.shared.open(URL(fileURLWithPath: bundle.outputRoot))
            }

            let output = [
                "Model migration evaluation complete",
                "Models: \(bundle.modelIDs.joined(separator: ", "))",
                "Dataset root: \(bundle.datasetRoot)",
                "Output root: \(bundle.outputRoot)",
                "Comparison report: \(bundle.comparisonMarkdownPath)"
            ].joined(separator: "\n")
            print(output)
            return
        }

        let runner = AIEvaluationRunner()
        let noteSet = AIEvaluationNoteSet(rawValue: options.noteSet ?? "all") ?? .all

        let bundle = try await runner.run(noteSet: noteSet, selectedModelID: options.modelID)

        if options.openFolder {
            runner.openEvaluationFolder()
        }

        let output = [
            "Evaluation complete",
            "Model: \(bundle.manifest.modelName)",
            "Note set: \(bundle.manifest.noteSet)",
            "Average score: \(String(format: \"%.3f\", bundle.manifest.averageOverallScore))",
            "Output root: \(bundle.outputRootURL.path)",
            "Report: \(bundle.reportURL.path)",
            "Prompt snapshot: \(bundle.promptVersionURL.path)"
        ].joined(separator: "\n")
        print(output)
    }

    private func parseArguments(_ arguments: [String]) -> Options {
        var modelID: String?
        var modelIDs: [String]?
        var noteSet: String?
        var migrationSuite = false
        var datasetRootURL: URL?
        var outputRootURL: URL?
        var openFolder = false
        var iterator = arguments.dropFirst().makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--model":
                modelID = iterator.next()
            case "--models":
                if let value = iterator.next() {
                    modelIDs = value.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.filter { !$0.isEmpty }
                }
            case "--note-set":
                noteSet = iterator.next()
            case "--migration-suite":
                migrationSuite = true
            case "--dataset-root":
                if let value = iterator.next() {
                    datasetRootURL = URL(fileURLWithPath: value)
                }
            case "--output-root":
                if let value = iterator.next() {
                    outputRootURL = URL(fileURLWithPath: value)
                }
            case "--open-folder":
                openFolder = true
            default:
                continue
            }
        }

        return Options(
            modelID: modelID,
            modelIDs: modelIDs,
            noteSet: noteSet,
            migrationSuite: migrationSuite,
            datasetRootURL: datasetRootURL,
            outputRootURL: outputRootURL,
            openFolder: openFolder
        )
    }

    private struct Options {
        var modelID: String?
        var modelIDs: [String]?
        var noteSet: String?
        var migrationSuite: Bool
        var datasetRootURL: URL?
        var outputRootURL: URL?
        var openFolder: Bool
    }
}
