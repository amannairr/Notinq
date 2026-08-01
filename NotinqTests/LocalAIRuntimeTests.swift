#if canImport(XCTest)
import XCTest
@testable import Notinq

@MainActor
final class LocalAIRuntimeTests: XCTestCase {
    private let sampleModel = LocalModel(
        id: "test-model",
        name: "Test Model",
        path: "/tmp/notinq-test-model.gguf",
        size: 42_000_000,
        contextLength: 2_048,
        parameterCount: 1_500_000_000,
        quantization: "Q4_K_M"
    )

    func testModelLoadingAndUnloading() async throws {
        let backend = MockLocalLLMBackend()
        try await backend.loadModel(sampleModel, configuration: .init())

        XCTAssertTrue(backend.isLoaded)
        XCTAssertEqual(backend.currentModel(), sampleModel)

        backend.unloadModel()

        XCTAssertFalse(backend.isLoaded)
        XCTAssertNil(backend.currentModel())
    }

    func testGenerateReturnsResponseFromBackend() async throws {
        let backend = MockLocalLLMBackend()
        try await backend.loadModel(sampleModel, configuration: .init())
        backend.cannedText = "Cell respiration converts glucose into usable energy."

        let provider = LocalAIProvider(
            backend: backend,
            availableModels: { [self.sampleModel] },
            configuration: .init()
        )

        let response = try await provider.generate(
            InferenceRequest(
                systemPrompt: "You are a concise assistant.",
                userPrompt: "Summarize cellular respiration.",
                temperature: 0.2,
                topP: 0.8,
                topK: 20,
                repeatPenalty: 1.0,
                maxTokens: 64,
                stream: false
            )
        )

        XCTAssertEqual(response.text, backend.cannedText)
        XCTAssertEqual(response.finishReason, "stop")
        XCTAssertGreaterThanOrEqual(response.tokensGenerated, 1)
    }

    func testStreamingDeliversTokens() async throws {
        let backend = MockLocalLLMBackend()
        try await backend.loadModel(sampleModel, configuration: .init())
        backend.streamTokens = ["Cell ", "membrane ", "protects ", "the ", "cell."]
        backend.cannedText = backend.streamTokens.joined()

        let provider = LocalAIProvider(
            backend: backend,
            availableModels: { [self.sampleModel] },
            configuration: .init()
        )

        var streamed = ""
        let response = try await provider.generateStream(
            InferenceRequest(
                systemPrompt: "",
                userPrompt: "Explain the cell membrane.",
                temperature: 0.1,
                topP: 0.9,
                topK: 40,
                repeatPenalty: 1.1,
                maxTokens: 64,
                stream: true
            )
        ) { token in
            streamed += token
        }

        XCTAssertEqual(streamed, backend.cannedText)
        XCTAssertEqual(response.text, backend.cannedText)
    }

    func testCancellationStopsStreaming() async throws {
        let backend = MockLocalLLMBackend()
        try await backend.loadModel(sampleModel, configuration: .init())
        backend.streamTokens = ["One ", "two ", "three ", "four "]

        let provider = LocalAIProvider(
            backend: backend,
            availableModels: { [self.sampleModel] },
            configuration: .init()
        )

        let task = Task {
            try await provider.generateStream(
                InferenceRequest(
                    systemPrompt: "",
                    userPrompt: "Stream something slowly.",
                    temperature: 0.1,
                    topP: 0.9,
                    topK: 40,
                    repeatPenalty: 1.1,
                    maxTokens: 64,
                    stream: true
                )
            ) { _ in }
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        provider.cancelCurrentGeneration()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation to throw")
        } catch InferenceError.cancelled {
            XCTAssertTrue(backend.wasCancelled)
        }
    }

    func testConfigurationIsReflectedInProviderCapabilities() {
        let backend = MockLocalLLMBackend()
        let provider = LocalAIProvider(
            backend: backend,
            availableModels: { [self.sampleModel] },
            configuration: AIConfiguration(
                defaultTemperature: 0.2,
                defaultTopP: 0.75,
                defaultTopK: 24,
                defaultRepeatPenalty: 1.05,
                defaultMaxTokens: 128,
                defaultContextSize: 1_024,
                streamingEnabled: false
            )
        )

        XCTAssertFalse(provider.capabilities.canStream)
        XCTAssertEqual(provider.capabilities.contextLimits.inputTokenLimit, 1_024)
        XCTAssertEqual(provider.capabilities.contextLimits.outputTokenLimit, 128)
    }

    func testMissingModelThrowsModelNotFound() async {
        let provider = LocalAIProvider(
            backend: MockLocalLLMBackend(),
            availableModels: { [] },
            configuration: .init()
        )

        do {
            try await provider.loadModel()
            XCTFail("Expected modelNotFound")
        } catch InferenceError.modelNotFound {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInvalidPathThrowsLoadFailed() async {
        let backend = MockLocalLLMBackend(validateFilePaths: true)
        let provider = LocalAIProvider(
            backend: backend,
            availableModels: {
                [
                    LocalModel(
                        id: "missing-model",
                        name: "Missing Model",
                        path: "/definitely/missing/model.gguf",
                        size: 1,
                        contextLength: 1_024,
                        parameterCount: 1_500_000_000,
                        quantization: "Q4_K_M"
                    )
                ]
            },
            configuration: .init()
        )

        do {
            try await provider.loadModel()
            XCTFail("Expected loadFailed")
        } catch InferenceError.loadFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class MockLocalLLMBackend: LocalLLMBackend {
    var loadedModel: LocalModel?
    var lastConfiguration: AIConfiguration?
    var cannedText = "Mock local response."
    var streamTokens: [String] = ["Mock ", "stream ", "response."]
    var validateFilePaths: Bool
    private(set) var wasCancelled = false

    init(validateFilePaths: Bool = false) {
        self.validateFilePaths = validateFilePaths
    }

    func loadModel(_ model: LocalModel, configuration: AIConfiguration) async throws {
        if validateFilePaths && FileManager.default.fileExists(atPath: model.path) == false {
            throw InferenceError.loadFailed
        }

        loadedModel = model
        lastConfiguration = configuration
        wasCancelled = false
    }

    func unloadModel() {
        loadedModel = nil
    }

    var isLoaded: Bool {
        loadedModel != nil
    }

    func currentModel() -> LocalModel? {
        loadedModel
    }

    func generate(_ request: InferenceRequest) async throws -> InferenceResponse {
        guard loadedModel != nil else {
            throw InferenceError.modelNotLoaded
        }

        return InferenceResponse(
            text: cannedText,
            latency: 0.05,
            tokensGenerated: max(1, cannedText.split { $0.isWhitespace || $0.isNewline }.count),
            promptTokens: max(1, request.systemPrompt.split { $0.isWhitespace || $0.isNewline }.count + request.userPrompt.split { $0.isWhitespace || $0.isNewline }.count),
            completionTokens: max(1, cannedText.split { $0.isWhitespace || $0.isNewline }.count)
        )
    }

    func generateStream(_ request: InferenceRequest, onToken: @escaping (String) -> Void) async throws -> InferenceResponse {
        guard loadedModel != nil else {
            throw InferenceError.modelNotLoaded
        }

        var output = ""
        for token in streamTokens {
            if wasCancelled {
                throw InferenceError.cancelled
            }
            output += token
            onToken(token)
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        return InferenceResponse(
            text: output,
            latency: 0.08,
            tokensGenerated: max(1, streamTokens.count),
            promptTokens: max(1, request.systemPrompt.split { $0.isWhitespace || $0.isNewline }.count + request.userPrompt.split { $0.isWhitespace || $0.isNewline }.count),
            completionTokens: max(1, streamTokens.count)
        )
    }

    func cancel() {
        wasCancelled = true
    }
}
#endif
