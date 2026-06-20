import Foundation

enum AIAction {
    case summarize
    case rewrite
    case explain
    case add

    var title: String {
        switch self {
        case .summarize: return "Summary"
        case .rewrite: return "Rewrite"
        case .explain: return "Explanation"
        case .add: return "Addition"
        }
    }

    var blockTitle: String {
        switch self {
        case .summarize: return "Summary"
        case .rewrite: return "Rewrite"
        case .explain: return "Explain"
        case .add: return "Continue"
        }
    }
}

enum AIRequestKind {
    case summarize
    case rewrite(sourceLength: Int)
    case explain
    case add(sourceLength: Int)
    case ask
    case studyUnified
    case flashcards
    case studyQuiz
    case studyTutorQuestions
    case studyInsights
    case studySelection
    case studyEvaluation
    case noteCompletenessAnalysis
    case followUp

    var maxTokens: Int32 {
        let cap = AIRuntimeConfig.current.llama.maxTokens
        switch self {
        case .summarize:
            return min(cap, 180)
        case .rewrite(let sourceLength):
            return min(cap, Int32(min(360, max(200, sourceLength / 3))))
        case .explain:
            return min(cap, 420)
        case .add(let sourceLength):
            return min(cap, Int32(min(420, max(180, sourceLength / 4))))
        case .ask:
            return min(cap, 360)
        case .studyUnified:
            return min(max(cap, 1024), 1200)
        case .flashcards:
            return min(cap, 520)
        case .studyQuiz:
            return min(cap, 520)
        case .studyTutorQuestions:
            return min(cap, 420)
        case .studyInsights:
            return min(cap, 320)
        case .studySelection:
            return min(cap, 320)
        case .studyEvaluation:
            return min(cap, 280)
        case .noteCompletenessAnalysis:
            return min(cap, 720)
        case .followUp:
            return min(cap, 300)
        }
    }
}

final class AIService {
    static let shared = AIService()
    private let router = AIRouter()

    func run(prompt: String, contextLength: Int, completion: @escaping (String) -> Void) {
        let provider = router.route(contextLength: contextLength)
        provider.run(prompt: prompt, completion: completion)
    }

    func run(prompt: String, contextLength: Int, kind: AIRequestKind, completion: @escaping (String) -> Void) {
        let provider = router.route(contextLength: contextLength)
        provider.run(prompt: prompt, maxTokens: kind.maxTokens, completion: completion)
    }

    func runStreaming(
        prompt: String,
        contextLength: Int,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        runStreaming(
            prompt: prompt,
            contextLength: contextLength,
            kind: .followUp,
            onToken: onToken,
            completion: completion
        )
    }

    func runStreaming(
        prompt: String,
        contextLength: Int,
        kind: AIRequestKind,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        let provider = router.route(contextLength: contextLength)
        provider.runStreaming(prompt: prompt, maxTokens: kind.maxTokens, onToken: onToken, completion: completion)
    }
}
