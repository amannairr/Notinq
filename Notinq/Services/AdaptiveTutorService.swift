import Foundation

final class AdaptiveTutorService {
    static let shared = AdaptiveTutorService()

    private let contextBuilder: ContextBuilderV2
    private let promptBuilder: AdaptivePromptBuilder
    private let inferenceEngine: InferenceEngine

    init(
        contextBuilder: ContextBuilderV2 = ContextBuilderV2(),
        promptBuilder: AdaptivePromptBuilder = AdaptivePromptBuilder(),
        inferenceEngine: InferenceEngine = .shared
    ) {
        self.contextBuilder = contextBuilder
        self.promptBuilder = promptBuilder
        self.inferenceEngine = inferenceEngine
    }

    func generateResponse(
        question: String,
        noteID: UUID?
    ) async throws -> String {
        let context = try await buildContext(question: question, noteID: noteID)
        let request = request(for: context, requestKind: "adaptiveTutor")
        return try await inferenceEngine.generate(request).text
    }

    func buildContext(
        question: String,
        noteID: UUID?
    ) async throws -> AdaptiveTutorContext {
        let context = try await contextBuilder.buildAdaptiveContext(question: question, noteID: noteID)
        logContextMetrics(context)
        return context
    }

    func buildPrompt(from context: AdaptiveTutorContext) -> String {
        promptBuilder.buildPrompt(from: context)
    }

    func request(
        for context: AdaptiveTutorContext,
        requestKind: String,
        maxTokens: Int32 = AIRequestKind.ask.maxTokens
    ) -> AIGenerationRequest {
        let prompt = promptBuilder.buildPrompt(from: context)
        return AIGenerationRequest(
            prompt: prompt,
            systemPrompt: PromptRegistry.shared.definition(for: .assistantChat).systemPrompt,
            maxTokens: maxTokens,
            temperature: 0.45,
            topP: 0.9,
            responseFormat: .text,
            contextLimit: Int(AIRuntimeConfig.current.llama.contextSize),
            metadata: [
                "requestKind": requestKind,
                "graphAware": "true",
                "adaptiveContextConcepts": "\(context.relevantConcepts.count)",
                "adaptiveContextRelationships": "\(context.relationships.count)",
                "adaptiveContextGaps": "\(context.knowledgeGaps.count)"
            ]
        )
    }

    private func logContextMetrics(_ context: AdaptiveTutorContext) {
        #if DEBUG
        print(
            "AdaptiveTutorContext size concepts=\(context.relevantConcepts.count) relationships=\(context.relationships.count) prerequisites=\(context.prerequisites.count) gaps=\(context.knowledgeGaps.count) retrievedNotes=\(context.retrievedNotes.count)"
        )
        #endif
    }
}
