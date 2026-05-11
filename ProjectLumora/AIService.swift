//
//  AIService.swift
//  ProjectLumora
//
//  Created by Aman Nair on 02/05/26.
//

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
    case flashcards
    case followUp

    var maxTokens: Int32 {
        switch self {
        case .summarize:
            return 180
        case .rewrite(let sourceLength):
            return Int32(min(360, max(200, sourceLength / 3)))
        case .explain:
            return 420
        case .add(let sourceLength):
            return Int32(min(420, max(180, sourceLength / 4)))
        case .ask:
            return 360
        case .flashcards:
            return 520
        case .followUp:
            return 300
        }
    }
}

class AIService {
    static let shared = AIService()
    private let router = AIRouter()

    func run(prompt: String, contextLength: Int, completion: @escaping (String) -> Void) {
        let provider = router.route(contextLength: contextLength)
        provider.run(prompt: prompt, completion: completion)
    }

    func run(prompt: String, contextLength: Int, kind: AIRequestKind, completion: @escaping (String) -> Void) {
        let provider = router.route(contextLength: contextLength)
        if let llamaProvider = provider as? LlamaProvider {
            llamaProvider.run(prompt: prompt, maxTokens: kind.maxTokens, completion: completion)
            return
        }
        provider.run(prompt: prompt, completion: completion)
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
        if let llamaProvider = provider as? LlamaProvider {
            llamaProvider.runStreaming(prompt: prompt, maxTokens: kind.maxTokens, onToken: onToken, completion: completion)
            return
        }

        provider.run(prompt: prompt) { response in
            onToken(response)
            completion()
        }
    }
}
