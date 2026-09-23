import Foundation

enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case localLlama = "local_llama"
    case openAI = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case unknown
}

struct AIContextLimits: Codable, Equatable, Sendable {
    var inputTokenLimit: Int
    var outputTokenLimit: Int
    var preferredChunkTokenCount: Int
}

struct AIProviderCapabilities: Codable, Equatable, Sendable {
    var canStream: Bool
    var canCancel: Bool
    var canGenerateJSON: Bool
    var canUseGrammar: Bool
    var canStructuredGenerate: Bool
    var supportsChatTemplates: Bool
    var contextLimits: AIContextLimits
}

struct AIProviderHealth: Codable, Equatable, Sendable {
    var isHealthy: Bool
    var message: String
    var contextLimits: AIContextLimits
}

struct AIProviderMetrics: Codable, Equatable, Sendable {
    var timeToFirstToken: TimeInterval
    var generationTime: TimeInterval
    var tokensPerSecond: Double
    var memoryUsageBytes: UInt64
    var contextUtilization: Double
}

struct AIGenerationResult: Codable, Equatable, Sendable {
    var text: String
    var metrics: AIProviderMetrics?
}

enum AIResponseFormat: Equatable, Sendable {
    case text
    case json
    case structured(name: String, schemaDescription: String)
}

extension AIResponseFormat {
    var description: String {
        switch self {
        case .text:
            return "text"
        case .json:
            return "json"
        case .structured(let name, let schemaDescription):
            return "structured(\(name)): \(schemaDescription)"
        }
    }
}

struct AIGenerationRequest: Sendable {
    var prompt: String
    var systemPrompt: String?
    var maxTokens: Int32
    var temperature: Float
    var topP: Float
    var responseFormat: AIResponseFormat
    var contextLimit: Int?
    var metadata: [String: String]

    init(
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int32 = 512,
        temperature: Float = 0.6,
        topP: Float = 0.9,
        responseFormat: AIResponseFormat = .text,
        contextLimit: Int? = nil,
        metadata: [String: String] = [:]
    ) {
        self.prompt = prompt
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.responseFormat = responseFormat
        self.contextLimit = contextLimit
        self.metadata = metadata
    }
}

protocol AIProviderProtocol: AnyObject {
    var kind: AIProviderKind { get }
    var displayName: String { get }
    var capabilities: AIProviderCapabilities { get }

    func healthCheck() async -> AIProviderHealth
    func generate(_ request: AIGenerationRequest) async throws -> AIGenerationResult
    func stream(
        _ request: AIGenerationRequest,
        onToken: @escaping (String) -> Void
    ) async throws -> AIGenerationResult
    func cancel()
    func jsonGenerate(_ request: AIGenerationRequest) async throws -> Data
}

protocol AIProvider: AIProviderProtocol {
    func loadModel() async throws
    func unloadModel()
    func currentModel() -> LocalModel?
    func modelInfo() -> LocalModel?
    var isLoaded: Bool { get }
    func generate(_ request: InferenceRequest) async throws -> InferenceResponse
    func generateStream(_ request: InferenceRequest, onToken: @escaping (String) -> Void) async throws -> InferenceResponse
    func cancelCurrentGeneration()
}

protocol GenerationModelProvider: AIProviderProtocol {}

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

extension AIProviderProtocol {
    func healthCheck() async -> AIProviderHealth {
        AIProviderHealth(isHealthy: true, message: displayName, contextLimits: capabilities.contextLimits)
    }

    func stream(
        _ request: AIGenerationRequest,
        onToken: @escaping (String) -> Void
    ) async throws -> AIGenerationResult {
        try await generate(request)
    }

    func cancel() {}

    func jsonGenerate(_ request: AIGenerationRequest) async throws -> Data {
        let result = try await generate(request)
        return Data(result.text.utf8)
    }
}

extension AIProvider {
    func loadModel() async throws {}

    func unloadModel() {}

    func currentModel() -> LocalModel? {
        nil
    }

    func modelInfo() -> LocalModel? {
        currentModel()
    }

    var isLoaded: Bool {
        currentModel() != nil
    }

    func cancelCurrentGeneration() {
        cancel()
    }

    func generate(_ request: InferenceRequest) async throws -> InferenceResponse {
        let legacy = request.asGenerationRequest()
        let result = try await generate(legacy)
        return InferenceResponse(
            text: result.text,
            latency: result.metrics?.generationTime ?? 0,
            tokensGenerated: estimatedGeneratedTokens(for: result.text),
            promptTokens: 0,
            completionTokens: 0,
            finishReason: "stop"
        )
    }

    func generateStream(_ request: InferenceRequest, onToken: @escaping (String) -> Void) async throws -> InferenceResponse {
        let legacy = request.asGenerationRequest()
        let result = try await stream(legacy, onToken: onToken)
        return InferenceResponse(
            text: result.text,
            latency: result.metrics?.generationTime ?? 0,
            tokensGenerated: estimatedGeneratedTokens(for: result.text),
            promptTokens: 0,
            completionTokens: 0,
            finishReason: "stop"
        )
    }

    private func estimatedGeneratedTokens(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return max(1, trimmed.split { $0.isWhitespace || $0.isNewline }.count)
    }
}

extension GenerationModelProvider {
    func run(prompt: String, completion: @escaping (String) -> Void) {
        Task {
            let request = AIGenerationRequest(prompt: prompt)
            let result = (try? await generate(request))?.text ?? "Unable to generate response."
            await MainActor.run {
                completion(result)
            }
        }
    }

    func run(prompt: String, maxTokens: Int32, completion: @escaping (String) -> Void) {
        Task {
            let request = AIGenerationRequest(prompt: prompt, maxTokens: maxTokens)
            let result = (try? await generate(request))?.text ?? "Unable to generate response."
            await MainActor.run {
                completion(result)
            }
        }
    }

    func runStreaming(
        prompt: String,
        maxTokens: Int32,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        Task {
            let request = AIGenerationRequest(prompt: prompt, maxTokens: maxTokens)
            _ = try? await stream(request, onToken: onToken)
            await MainActor.run {
                completion()
            }
        }
    }
}

extension Notification.Name {
    static let notinqProviderSelectionDidChange = Notification.Name("notinq.ai.providerSelectionDidChange")
    static let notinqHardwareDidChange = Notification.Name("notinq.ai.hardwareDidChange")
}
