import Foundation

final class GeminiProvider: AIProvider {
    func run(prompt: String, completion: @escaping (String) -> Void) {
        completion("Not implemented")
    }

    func run(prompt: String, maxTokens: Int32, completion: @escaping (String) -> Void) {
        _ = maxTokens
        completion("Not implemented")
    }

    func runStreaming(
        prompt: String,
        maxTokens: Int32,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        _ = prompt
        _ = maxTokens
        onToken("Not implemented")
        completion()
    }
}
