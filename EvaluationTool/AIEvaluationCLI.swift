import Foundation

struct AIEvaluationCLI {
    let arguments: [String]

    init(arguments: [String] = CommandLine.arguments) {
        self.arguments = arguments
    }

    func run() async throws {
        let options = parseArguments(arguments)
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
        var noteSet: String?
        var openFolder = false
        var iterator = arguments.dropFirst().makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--model":
                modelID = iterator.next()
            case "--note-set":
                noteSet = iterator.next()
            case "--open-folder":
                openFolder = true
            default:
                continue
            }
        }

        return Options(modelID: modelID, noteSet: noteSet, openFolder: openFolder)
    }

    private struct Options {
        var modelID: String?
        var noteSet: String?
        var openFolder: Bool
    }
}

