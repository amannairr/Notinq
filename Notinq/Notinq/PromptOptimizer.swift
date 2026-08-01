import Foundation

enum PromptModelFamily: String, Codable, CaseIterable, Sendable {
    case phi
    case qwen
    case gemma
    case gpt
    case claude
    case unknown
}

struct PromptOptimizationProfile: Codable, Equatable, Sendable {
    var family: PromptModelFamily
    var compactnessBias: Double
    var schemaStrictness: Double
    var temperatureScale: Double
    var maxTokensScale: Double
    var extraSystemInstructions: [String]
}

struct PromptOptimizationResult: Equatable, Sendable {
    var document: PromptDocument
    var profile: PromptOptimizationProfile
}

enum PromptOptimizer {
    static func optimize(_ document: PromptDocument, for providerKind: AIProviderKind, modelIdentifier: String? = nil) -> PromptOptimizationResult {
        let profile = PromptProviderAdapter.profile(for: providerKind, modelIdentifier: modelIdentifier)
        var optimized = document

        optimized.temperature = Float(Double(document.temperature) * profile.temperatureScale)
        optimized.maxTokens = Int32(max(64, Double(document.maxTokens) * profile.maxTokensScale))

        if !profile.extraSystemInstructions.isEmpty {
            let appendix = profile.extraSystemInstructions.joined(separator: "\n")
            optimized.systemPrompt = [document.systemPrompt, appendix].joined(separator: "\n\n")
        }

        if profile.compactnessBias > 0.5 {
            optimized.systemPrompt = optimized.systemPrompt.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return PromptOptimizationResult(document: optimized, profile: profile)
    }
}
