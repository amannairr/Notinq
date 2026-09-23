import Foundation

final class GeminiProvider: AIProvider {
    static let shared = GeminiProvider()

    let kind: AIProviderKind = .gemini
    let displayName: String = "Gemini"

    let capabilities = AIProviderCapabilities(
        canStream: true,
        canCancel: true,
        canGenerateJSON: true,
        canUseGrammar: false,
        canStructuredGenerate: true,
        supportsChatTemplates: true,
        contextLimits: AIContextLimits(inputTokenLimit: 32_000, outputTokenLimit: 4_096, preferredChunkTokenCount: 2_048)
    )

    func healthCheck() async -> AIProviderHealth {
        AIProviderHealth(isHealthy: false, message: "Cloud Gemini provider is not configured in this build.", contextLimits: capabilities.contextLimits)
    }

    func generate(_ request: AIGenerationRequest) async throws -> AIGenerationResult {
        let promptID = request.metadata["prompt"] ?? "unknown"
        let message = "Cloud generation is unavailable. Active request: \(promptID)."
        return AIGenerationResult(text: message, metrics: nil)
    }

    func stream(
        _ request: AIGenerationRequest,
        onToken: @escaping (String) -> Void
    ) async throws -> AIGenerationResult {
        let result = try await generate(request)
        onToken(result.text)
        return result
    }

    func cancel() {}

    func jsonGenerate(_ request: AIGenerationRequest) async throws -> Data {
        try await InferenceEngine.shared.generateJSON(request)
    }
}
