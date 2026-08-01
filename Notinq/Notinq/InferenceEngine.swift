import Foundation

struct AIGenerationTiming: Codable, Equatable, Sendable {
    var timeToFirstToken: TimeInterval
    var generationTime: TimeInterval
    var tokensPerSecond: Double
    var contextUtilization: Double
}

final class InferenceEngine {
    static let shared = InferenceEngine()

    private let providerQueue = DispatchQueue(label: "notinq.ai.inference.provider", qos: .userInitiated)
    private let fallbackProvider = LlamaProvider.shared

    private init() {}

    var activeProvider: AIProviderProtocol {
        switch ModelManager.shared.activeProviderKind {
        case .localLlama:
            return LlamaProvider.shared
        case .gemini:
            return GeminiProvider.shared
        case .openAI, .anthropic, .unknown:
            return fallbackProvider
        }
    }

    func healthCheck() async -> AIProviderHealth {
        await activeProvider.healthCheck()
    }

    func generate(_ request: AIGenerationRequest) async throws -> AIGenerationResult {
        try await providerQueue.asyncThrowing {
            try await self.generateWithRetry(request: request)
        }
    }

    func stream(
        _ request: AIGenerationRequest,
        onToken: @escaping (String) -> Void
    ) async throws -> AIGenerationResult {
        try await providerQueue.asyncThrowing {
            let started = CFAbsoluteTimeGetCurrent()
            var firstTokenTime: CFAbsoluteTime?
            var tokenCount = 0
            let result = try await self.activeProvider.stream(request) { token in
                if firstTokenTime == nil {
                    firstTokenTime = CFAbsoluteTimeGetCurrent()
                }
                tokenCount += max(1, token.count / 4)
                onToken(token)
            }

            let total = CFAbsoluteTimeGetCurrent() - started
            let ttfb = firstTokenTime.map { $0 - started } ?? total
            let metrics = AIProviderMetrics(
                timeToFirstToken: ttfb,
                generationTime: total,
                tokensPerSecond: total > 0 ? Double(tokenCount) / total : 0,
                memoryUsageBytes: ProcessInfo.processInfo.physicalMemory,
                contextUtilization: {
                    let requestedContext = request.contextLimit ?? Int(request.maxTokens)
                    return min(1.0, Double(requestedContext) / Double(max(1, self.activeProvider.capabilities.contextLimits.inputTokenLimit)))
                }()
            )
            return AIGenerationResult(text: result.text, metrics: metrics)
        }
    }

    func cancel() {
        activeProvider.cancel()
    }

    func generateJSON(_ request: AIGenerationRequest) async throws -> Data {
        let result = try await generate(request)
        return validatedJSONData(from: result.text, fallbackPrompt: request.prompt, systemPrompt: request.systemPrompt)
    }

    func generateStructured<T: Decodable>(_ type: T.Type, request: AIGenerationRequest) async throws -> T {
        let data = try await generateJSON(request)
        if let value = try? JSONDecoder().decode(T.self, from: data) {
            return value
        }

        let retryRequest = AIGenerationRequest(
            prompt: request.prompt + "\n\nThe previous response was malformed. Return only valid JSON for the requested schema.",
            systemPrompt: request.systemPrompt,
            maxTokens: request.maxTokens,
            temperature: 0.0,
            topP: request.topP,
            responseFormat: .json,
            contextLimit: request.contextLimit,
            metadata: request.metadata
        )

        let retryData = try await generateJSON(retryRequest)
        guard let retryValue = try? JSONDecoder().decode(T.self, from: retryData) else {
            throw NSError(domain: "Notinq.InferenceEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode structured output."])
        }
        return retryValue
    }

    private func generateWithRetry(request: AIGenerationRequest) async throws -> AIGenerationResult {
        do {
            let result = try await activeProvider.generate(request)
            return result
        } catch {
            let retry = AIGenerationRequest(
                prompt: request.prompt + "\n\nIf you returned malformed content, correct it now.",
                systemPrompt: request.systemPrompt,
                maxTokens: request.maxTokens,
                temperature: request.temperature,
                topP: request.topP,
                responseFormat: request.responseFormat,
                contextLimit: request.contextLimit,
                metadata: request.metadata
            )
            return try await activeProvider.generate(retry)
        }
    }

    private func validatedJSONData(from text: String, fallbackPrompt: String, systemPrompt: String?) -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object) {
            return data
        }

        let extracted = extractJSONObject(from: trimmed)
        if let data = extracted.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return data
        }

        let fallbackObject: [String: String] = [
            "prompt": fallbackPrompt,
            "systemPrompt": systemPrompt ?? "",
            "response": trimmed
        ]
        return (try? JSONSerialization.data(withJSONObject: fallbackObject, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    private func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return text
        }
        return String(text[start...end])
    }
}

private extension DispatchQueue {
    func asyncThrowing<T>(_ work: @escaping () async throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            async {
                Task {
                    do {
                        continuation.resume(returning: try await work())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
