import Foundation

protocol GenerationModelProvider: AnyObject {
    func run(prompt: String, completion: @escaping (String) -> Void)
    func run(prompt: String, maxTokens: Int32, completion: @escaping (String) -> Void)
    func runStreaming(
        prompt: String,
        maxTokens: Int32,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    )
}

protocol EmbeddingProvider: AnyObject {
    func embedding(for text: String) -> [Float]?
}

struct StudyGenerationBudget: Sendable {
    let flashcards: Int
    let quizQuestions: Int
    let tutorQuestions: Int
    let insightItemsPerSection: Int
    let maxResponseTokens: Int32
    let contextLimit: Int
}
