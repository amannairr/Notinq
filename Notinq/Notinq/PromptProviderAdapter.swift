import Foundation

enum PromptProviderAdapter {
    static func family(for providerKind: AIProviderKind, modelIdentifier: String? = nil) -> PromptModelFamily {
        let identifier = (modelIdentifier ?? ModelManager.shared.activeModelIDDescription()).lowercased()

        if identifier.contains("phi") {
            return .phi
        }
        if identifier.contains("gemma") {
            return .gemma
        }
        if identifier.contains("qwen") {
            return .qwen
        }

        switch providerKind {
        case .openAI:
            return .gpt
        case .anthropic:
            return .claude
        case .gemini:
            return .gemma
        case .localLlama, .unknown:
            return .unknown
        }
    }

    static func profile(for providerKind: AIProviderKind, modelIdentifier: String? = nil) -> PromptOptimizationProfile {
        switch family(for: providerKind, modelIdentifier: modelIdentifier) {
        case .phi:
            return PromptOptimizationProfile(
                family: .phi,
                compactnessBias: 0.9,
                schemaStrictness: 0.95,
                temperatureScale: 0.85,
                maxTokensScale: 0.82,
                extraSystemInstructions: [
                    "Prefer concise, direct outputs.",
                    "Avoid elaborate reasoning unless explicitly requested."
                ]
            )
        case .qwen:
            return PromptOptimizationProfile(
                family: .qwen,
                compactnessBias: 0.7,
                schemaStrictness: 0.9,
                temperatureScale: 0.9,
                maxTokensScale: 0.9,
                extraSystemInstructions: [
                    "Prefer compact JSON fields and stable naming.",
                    "Do not add commentary outside the requested schema."
                ]
            )
        case .gemma:
            return PromptOptimizationProfile(
                family: .gemma,
                compactnessBias: 0.8,
                schemaStrictness: 0.95,
                temperatureScale: 0.8,
                maxTokensScale: 0.85,
                extraSystemInstructions: [
                    "Prefer short, factual outputs.",
                    "Keep each field minimal and grounded in the source."
                ]
            )
        case .gpt:
            return PromptOptimizationProfile(
                family: .gpt,
                compactnessBias: 0.4,
                schemaStrictness: 0.88,
                temperatureScale: 0.95,
                maxTokensScale: 1.0,
                extraSystemInstructions: [
                    "Preserve the exact schema requested.",
                    "Return fully structured output."
                ]
            )
        case .claude:
            return PromptOptimizationProfile(
                family: .claude,
                compactnessBias: 0.5,
                schemaStrictness: 0.9,
                temperatureScale: 0.92,
                maxTokensScale: 1.0,
                extraSystemInstructions: [
                    "Prioritize consistency and precise structure.",
                    "Avoid speculative additions."
                ]
            )
        case .unknown:
            return PromptOptimizationProfile(
                family: .unknown,
                compactnessBias: 0.6,
                schemaStrictness: 0.9,
                temperatureScale: 0.9,
                maxTokensScale: 0.9,
                extraSystemInstructions: [
                    "Prefer deterministic outputs.",
                    "Stay within the requested schema."
                ]
            )
        }
    }
}

