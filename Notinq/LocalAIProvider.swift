import Foundation

final class ManagedLocalLLMBackend: LocalLLMBackend {
    static let shared = ManagedLocalLLMBackend()

    private let manager = AIModelManager.shared

    private init() {}

    func loadModel(_ model: LocalModel, configuration: AIConfiguration) async throws {
        _ = configuration
        manager.selectPreferredModel(id: model.id)
        try await manager.loadModel()
    }

    func unloadModel() {
        manager.unloadModel()
    }

    var isLoaded: Bool {
        manager.isLoaded
    }

    func currentModel() -> LocalModel? {
        manager.currentModel()
    }

    func generate(_ request: InferenceRequest) async throws -> InferenceResponse {
        try await manager.generate(request)
    }

    func generateStream(_ request: InferenceRequest, onToken: @escaping (String) -> Void) async throws -> InferenceResponse {
        try await manager.generateStream(request, onToken: onToken)
    }

    func cancel() {
        manager.cancelCurrentGeneration()
    }
}

final class LocalAIProvider: AIProvider {
    static let shared = LocalAIProvider()

    private let backend: LocalLLMBackend
    private let availableModels: () -> [LocalModel]
    private var configuration: AIConfiguration

    init(
        backend: LocalLLMBackend = ManagedLocalLLMBackend.shared,
        availableModels: @escaping () -> [LocalModel] = { AIModelLibrary.shared.localModels() },
        configuration: AIConfiguration = .init()
    ) {
        self.backend = backend
        self.availableModels = availableModels
        self.configuration = configuration
    }

    let kind: AIProviderKind = .localLlama
    let displayName: String = "Local GGUF"
    var capabilities: AIProviderCapabilities {
        AIProviderCapabilities(
            canStream: configuration.streamingEnabled,
            canCancel: true,
            canGenerateJSON: false,
            canUseGrammar: false,
            canStructuredGenerate: false,
            supportsChatTemplates: false,
            contextLimits: AIContextLimits(
                inputTokenLimit: configuration.defaultContextSize,
                outputTokenLimit: configuration.defaultMaxTokens,
                preferredChunkTokenCount: max(128, configuration.defaultContextSize / 4)
            )
        )
    }

    func healthCheck() async -> AIProviderHealth {
        AIProviderHealth(
            isHealthy: backend.currentModel() != nil || !availableModels().isEmpty,
            message: backend.currentModel() != nil ? "Local model ready." : "Local model available.",
            contextLimits: capabilities.contextLimits
        )
    }

    func loadModel() async throws {
        if backend.currentModel() != nil {
            return
        }

        guard let model = availableModels().first else {
            throw InferenceError.modelNotFound
        }

        let qwen3Model = availableModels().first(where: { $0.id == "qwen-3-4b" })
        let preferredModel = qwen3Model ?? model
        try await backend.loadModel(preferredModel, configuration: configuration)
    }

    func unloadModel() {
        backend.unloadModel()
    }

    func currentModel() -> LocalModel? {
        backend.currentModel()
    }

    func modelInfo() -> LocalModel? {
        currentModel()
    }

    var isLoaded: Bool {
        backend.isLoaded
    }

    func generate(_ request: AIGenerationRequest) async throws -> AIGenerationResult {
        let typedRequest = InferenceRequest(legacy: request)
        let response = try await backend.generate(typedRequest)
        return AIGenerationResult(text: response.text, metrics: nil)
    }

    func stream(_ request: AIGenerationRequest, onToken: @escaping (String) -> Void) async throws -> AIGenerationResult {
        let typedRequest = InferenceRequest(legacy: request)
        let response = try await backend.generateStream(typedRequest, onToken: onToken)
        return AIGenerationResult(text: response.text, metrics: nil)
    }

    func cancel() {
        backend.cancel()
    }

    func jsonGenerate(_ request: AIGenerationRequest) async throws -> Data {
        let result = try await generate(request)
        return Data(result.text.utf8)
    }

    func updateConfiguration(_ configuration: AIConfiguration) {
        self.configuration = configuration
    }
}
