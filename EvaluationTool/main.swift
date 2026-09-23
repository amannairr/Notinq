import Foundation

@main
struct AIEvaluationToolMain {
    static func main() async {
        let cli = AIEvaluationCLI(arguments: CommandLine.arguments)
        do {
            try await cli.run()
        } catch {
            FileHandle.standardError.write(Data("Evaluation failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

