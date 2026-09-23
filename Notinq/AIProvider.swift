import Foundation

struct LocalModel: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var path: String
    var size: Int64
    var contextLength: Int
    var parameterCount: Int64
    var quantization: String

    var fileURL: URL {
        URL(fileURLWithPath: path)
    }
}

struct AIConfiguration: Codable, Equatable, Sendable {
    var defaultTemperature: Double = 0.6
    var defaultTopP: Double = 0.9
    var defaultTopK: Int = 40
    var defaultRepeatPenalty: Double = 1.1
    var defaultMaxTokens: Int = 512
    var defaultContextSize: Int = 2_048
    var streamingEnabled: Bool = true
}

struct InferenceRequest: Codable, Equatable, Sendable {
    var systemPrompt: String
    var userPrompt: String
    var temperature: Double
    var topP: Double
    var topK: Int
    var repeatPenalty: Double
    var maxTokens: Int
    var seed: Int64?
    var stream: Bool
    var stopSequences: [String]

    init(
        systemPrompt: String = "",
        userPrompt: String,
        temperature: Double = AIConfiguration().defaultTemperature,
        topP: Double = AIConfiguration().defaultTopP,
        topK: Int = AIConfiguration().defaultTopK,
        repeatPenalty: Double = AIConfiguration().defaultRepeatPenalty,
        maxTokens: Int = AIConfiguration().defaultMaxTokens,
        seed: Int64? = nil,
        stream: Bool = false,
        stopSequences: [String] = []
    ) {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
        self.maxTokens = maxTokens
        self.seed = seed
        self.stream = stream
        self.stopSequences = stopSequences
    }
}

struct InferenceResponse: Codable, Equatable, Sendable {
    var text: String
    var finishReason: String
    var latency: TimeInterval
    var tokensGenerated: Int
    var tokensPerSecond: Double
    var promptTokens: Int
    var completionTokens: Int
}

enum InferenceError: LocalizedError, Equatable {
    case modelNotFound
    case modelNotLoaded
    case loadFailed
    case generationFailed
    case cancelled
    case contextTooLarge
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "The requested model could not be found."
        case .modelNotLoaded:
            return "No model is currently loaded."
        case .loadFailed:
            return "The model failed to load."
        case .generationFailed:
            return "Generation failed."
        case .cancelled:
            return "The generation was cancelled."
        case .contextTooLarge:
            return "The prompt exceeds the current context size."
        case .invalidResponse:
            return "The model produced an invalid response."
        }
    }
}

extension InferenceRequest {
    func asGenerationRequest(contextLimit: Int? = nil) -> AIGenerationRequest {
        AIGenerationRequest(
            prompt: userPrompt,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
            maxTokens: Int32(maxTokens),
            temperature: Float(temperature),
            topP: Float(topP),
            responseFormat: .text,
            contextLimit: contextLimit,
            metadata: [
                "topK": "\(topK)",
                "repeatPenalty": "\(repeatPenalty)",
                "seed": seed.map(String.init) ?? ""
            ]
        )
    }

    init(legacy request: AIGenerationRequest) {
        self.init(
            systemPrompt: request.systemPrompt ?? "",
            userPrompt: request.prompt,
            temperature: Double(request.temperature),
            topP: Double(request.topP),
            topK: AIConfiguration().defaultTopK,
            repeatPenalty: AIConfiguration().defaultRepeatPenalty,
            maxTokens: Int(request.maxTokens),
            seed: nil,
            stream: request.responseFormat != .text,
            stopSequences: []
        )
    }
}

extension InferenceResponse {
    init(text: String, latency: TimeInterval = 0, tokensGenerated: Int = 0, promptTokens: Int = 0, completionTokens: Int = 0, finishReason: String = "stop") {
        self.text = text
        self.finishReason = finishReason
        self.latency = latency
        self.tokensGenerated = tokensGenerated
        self.tokensPerSecond = latency > 0 ? Double(tokensGenerated) / latency : 0
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

protocol LocalLLMBackend: AnyObject {
    func loadModel(_ model: LocalModel, configuration: AIConfiguration) async throws
    func unloadModel()
    var isLoaded: Bool { get }
    func currentModel() -> LocalModel?
    func generate(_ request: InferenceRequest) async throws -> InferenceResponse
    func generateStream(_ request: InferenceRequest, onToken: @escaping (String) -> Void) async throws -> InferenceResponse
    func cancel()
}
