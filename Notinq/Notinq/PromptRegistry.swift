import Foundation

private enum PromptRegistryTextAssets {
    static let knowledgeExtraction = "Deterministic knowledge extraction from semantic chunks. Return valid JSON only."
    static let summary = "Structured study summarizer."
    static let revisionPlan = "Revision planner."
    static let definitions = "Definitions extractor."
    static let flashcards = "Flashcard generator."
    static let actionItems = "Action item generator."
    static let quiz = "Quiz writer."
    static let conceptMap = "Concept map builder."
    static let learningInsights = "Learning analyst."
    static let assistantChat = "Grounded study assistant."
    static let directEditing = "Precise editor."
}

struct AIPromptVersion: Codable, Equatable, Sendable {
    var major: Int
    var minor: Int
    var patch: Int

    static let current = AIPromptVersion(major: 1, minor: 0, patch: 0)
}

enum AIPromptIdentifier: String, Codable, CaseIterable, Sendable {
    case knowledgeExtraction
    case summary
    case revisionGuide
    case keyConcepts
    case flashcards
    case practiceQuestions
    case multipleChoiceQuiz
    case conceptMap
    case learningInsights
    case knowledgeGaps
    case activeRecall
    case assistantChat
    case directEditing
    case knowledgeGraphExpansion
    case aiTutor
    case definitions
    case timeline
    case formulaExtraction
    case revisionPlan
    case cheatSheet
    case podcast
    case comparison
    case actionItems
}

enum AIWorkspacePreset: String, CaseIterable, Sendable {
    case summarize
    case rewrite
    case explain
    case flashcards
    case quiz
    case keyPoints
}

struct AIPromptDefinition: Codable, Equatable, Sendable {
    var identifier: AIPromptIdentifier
    var version: AIPromptVersion
    var systemPrompt: String
    var outputDescription: String
}

struct AIPromptContext: Sendable {
    var noteTitle: String
    var noteText: String
    var knowledgeJSON: String?
    var selectedText: String?
    var userRequest: String?
}

final class PromptRegistry {
    static let shared = PromptRegistry()

    private let definitions: [AIPromptIdentifier: AIPromptDefinition]

    private init() {
        definitions = [
            .knowledgeExtraction: AIPromptDefinition(
                identifier: .knowledgeExtraction,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.knowledgeExtraction,
                outputDescription: "Structured knowledge JSON."
            ),
            .summary: AIPromptDefinition(
                identifier: .summary,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.summary,
                outputDescription: "Structured summary JSON."
            ),
            .revisionGuide: AIPromptDefinition(
                identifier: .revisionGuide,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.revisionPlan,
                outputDescription: "Revision plan JSON."
            ),
            .keyConcepts: AIPromptDefinition(
                identifier: .keyConcepts,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.definitions,
                outputDescription: "Definitions JSON."
            ),
            .flashcards: AIPromptDefinition(
                identifier: .flashcards,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.flashcards,
                outputDescription: "Flashcard deck JSON."
            ),
            .practiceQuestions: AIPromptDefinition(
                identifier: .practiceQuestions,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.actionItems,
                outputDescription: "Practice questions JSON."
            ),
            .multipleChoiceQuiz: AIPromptDefinition(
                identifier: .multipleChoiceQuiz,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.quiz,
                outputDescription: "Quiz JSON."
            ),
            .conceptMap: AIPromptDefinition(
                identifier: .conceptMap,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.conceptMap,
                outputDescription: "Concept map JSON."
            ),
            .learningInsights: AIPromptDefinition(
                identifier: .learningInsights,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.learningInsights,
                outputDescription: "Learning insights JSON."
            ),
            .knowledgeGaps: AIPromptDefinition(
                identifier: .knowledgeGaps,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.actionItems,
                outputDescription: "Knowledge gaps JSON."
            ),
            .activeRecall: AIPromptDefinition(
                identifier: .activeRecall,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.flashcards,
                outputDescription: "Active recall JSON."
            ),
            .assistantChat: AIPromptDefinition(
                identifier: .assistantChat,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.assistantChat,
                outputDescription: "Grounded text answer."
            ),
            .directEditing: AIPromptDefinition(
                identifier: .directEditing,
                version: .current,
                systemPrompt: PromptRegistryTextAssets.directEditing,
                outputDescription: "Direct edit text."
            )
        ]
    }

    func definition(for identifier: AIPromptIdentifier) -> AIPromptDefinition {
        definitions[identifier] ?? AIPromptDefinition(
            identifier: identifier,
            version: .current,
            systemPrompt: "Return the requested content.",
            outputDescription: "Structured output"
        )
    }

    func renderPrompt(for identifier: AIPromptIdentifier, context: AIPromptContext) -> AIGenerationRequest {
        let document = promptDocument(for: identifier, context: context)
        return buildRequest(from: document, identifier: identifier)
    }

    func jsonRequest(for identifier: AIPromptIdentifier, context: AIPromptContext, maxTokens: Int32 = 768) -> AIGenerationRequest {
        var document = promptDocument(for: identifier, context: context)
        document.maxTokens = maxTokens
        document.responseFormat = .json
        document.temperature = min(document.temperature, 0.2)
        document.topP = min(document.topP, 0.9)
        return buildRequest(from: document, identifier: identifier)
    }

    func buildRequest<P: PromptDefinition>(for prompt: P.Type, input: P.Input, context: PromptBuildContext = PromptBuildContext()) -> AIGenerationRequest {
        let document = prompt.buildDocument(input: input, context: context)
        return buildRequest(from: document, identifier: prompt.identifier, version: prompt.version)
    }

    func execute<P: PromptDefinition>(
        _ prompt: P.Type,
        input: P.Input
    ) async throws -> PromptExecutionResult<P.Output> {
        try await execute(prompt, input: input, context: PromptBuildContext(noteTitle: "", noteText: ""))
    }

    func execute<P: PromptDefinition>(
        _ prompt: P.Type,
        input: P.Input,
        context: PromptBuildContext
    ) async throws -> PromptExecutionResult<P.Output> {
        let document = prompt.buildDocument(input: input, context: context)
        let optimization = PromptOptimizer.optimize(document, for: context.providerKind, modelIdentifier: context.modelIdentifier)
        let request = buildRequest(from: optimization.document, identifier: prompt.identifier, version: prompt.version)
        let started = Date()
        let generation = try await InferenceEngine.shared.generate(request)
        let rawText = generation.text
        let repairedText = document.responseFormat == .json ? (PromptRepairer.repairJSONString(rawText) ?? rawText) : rawText
        let decoded = try decodeOutput(P.Output.self, from: repairedText, rawText: rawText)
        let validation = prompt.validate(output: decoded, input: input, context: context)
        let repaired = repairedText != rawText
        let retryCount: Int

        var finalOutput = decoded
        var finalValidation = validation
        var finalRawText = rawText
        var finalRepaired = repaired
        retryCount = validation.shouldRetry ? 1 : 0

        if validation.shouldRetry && document.retryPolicy.maxAttempts > 1 {
            let retryDocument = PromptDocument(
                systemPrompt: document.systemPrompt,
                userPrompt: [document.userPrompt, PromptValidationSummary.forRetry(validation)].joined(separator: "\n\n"),
                temperature: document.retryPolicy.fallbackTemperature,
                topP: document.topP,
                maxTokens: document.maxTokens,
                responseFormat: document.responseFormat,
                confidenceRequirement: document.confidenceRequirement,
                retryPolicy: document.retryPolicy,
                validationStrategy: document.validationStrategy,
                schema: document.schema,
                metadata: document.metadata
            )
            let retryRequest = buildRequest(from: retryDocument, identifier: prompt.identifier, version: prompt.version)
            let retryGeneration = try await InferenceEngine.shared.generate(retryRequest)
            finalRawText = retryGeneration.text
            let retryRepaired = document.responseFormat == .json ? (PromptRepairer.repairJSONString(finalRawText) ?? finalRawText) : finalRawText
            finalOutput = try decodeOutput(P.Output.self, from: retryRepaired, rawText: finalRawText)
            finalValidation = prompt.validate(output: finalOutput, input: input, context: context)
            finalRepaired = finalRepaired || retryRepaired != finalRawText
        }

        let metrics = PromptExecutionMetrics(
            latency: Date().timeIntervalSince(started),
            repairCount: finalRepaired ? 1 : 0,
            retryCount: retryCount,
            jsonValidity: finalValidation.isValid ? 1.0 : 0.0,
            confidence: finalValidation.confidence,
            hallucinationRate: max(0, 1.0 - finalValidation.confidence),
            determinism: finalValidation.shouldRetry ? 0.5 : 1.0,
            tokenUsage: estimatedTokenUsage(for: generation)
        )

        return PromptExecutionResult(
            identifier: prompt.identifier,
            version: prompt.version,
            providerKind: context.providerKind,
            modelIdentifier: context.modelIdentifier,
            request: request,
            rawText: finalRawText,
            output: finalOutput,
            validation: finalValidation,
            metrics: metrics,
            repaired: finalRepaired,
            retries: retryCount
        )
    }

    private func promptDocument(for identifier: AIPromptIdentifier, context: AIPromptContext) -> PromptDocument {
        let structuredKnowledge = decodeStructuredKnowledge(from: context.knowledgeJSON)
            ?? decodeKnowledgeSnapshot(from: context.knowledgeJSON)?.structuredKnowledgeRepresentation()
        let buildContext = PromptBuildContext(
            noteTitle: context.noteTitle,
            noteText: identifier == .assistantChat || identifier == .directEditing ? context.noteText : "",
            structuredKnowledge: structuredKnowledge,
            knowledgeSnapshot: decodeKnowledgeSnapshot(from: context.knowledgeJSON),
            selectedText: context.selectedText,
            userRequest: context.userRequest,
            providerKind: ModelManager.shared.currentModelDiagnostics().providerKind,
            modelIdentifier: ModelManager.shared.activeModelIDDescription(),
            noteSignature: nil,
            contextLimit: Int(AIRuntimeConfig.current.llama.contextSize)
        )

        switch identifier {
        case .knowledgeExtraction:
            return KnowledgeExtractionPrompt.buildDocument(
                input: PromptExtractionInput(noteTitle: context.noteTitle, noteText: context.noteText),
                context: buildContext
            )
        case .summary:
            return SummaryPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .revisionGuide, .revisionPlan:
            return RevisionPlanPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .keyConcepts, .definitions:
            return DefinitionsPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .flashcards:
            return FlashcardsPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .practiceQuestions, .actionItems:
            return AIActionItemsPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .multipleChoiceQuiz:
            return QuizPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .conceptMap:
            return ConceptMapPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .learningInsights:
            return LearningInsightsPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .knowledgeGaps:
            return ActionItemsPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .activeRecall, .aiTutor:
            return TutorPrompt.buildDocument(
                input: PromptTutorInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation(), question: context.userRequest ?? ""),
                context: buildContext
            )
        case .assistantChat:
            return AIHelperChatPrompt.buildDocument(
                input: PromptExtractionInput(noteTitle: context.noteTitle, noteText: context.noteText),
                context: buildContext
            )
        case .directEditing:
            return DirectEditPrompt.buildDocument(
                input: PromptExtractionInput(noteTitle: context.noteTitle, noteText: context.noteText),
                context: buildContext
            )
        case .knowledgeGraphExpansion:
            return KnowledgeGraphExpansionPrompt.buildDocument(
                input: PromptGraphInput(noteTitle: context.noteTitle, graph: buildContext.knowledgeGraph ?? KnowledgeGraph(noteID: UUID(), concepts: [], relationships: [], lastUpdated: Date())),
                context: buildContext
            )
        case .timeline:
            return TimelinePrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .formulaExtraction:
            return FormulaExtractionPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .cheatSheet:
            return CheatSheetPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .podcast:
            return PodcastPrompt.buildDocument(
                input: PromptStructuredKnowledgeInput(noteTitle: context.noteTitle, knowledge: structuredKnowledge ?? StudyKnowledgeSnapshot(title: context.noteTitle).structuredKnowledgeRepresentation()),
                context: buildContext
            )
        case .comparison:
            return ComparisonPrompt.buildDocument(
                input: PromptComparisonInput(leftTitle: context.noteTitle, rightTitle: context.userRequest ?? "", leftJSON: context.noteText, rightJSON: context.knowledgeJSON ?? "{}"),
                context: buildContext
            )
        }
    }

    private func buildRequest(from document: PromptDocument, identifier: AIPromptIdentifier, version: AIPromptVersion? = nil) -> AIGenerationRequest {
        let metadata = document.metadata.merging([
            "prompt": identifier.rawValue,
            "promptVersion": "\(version?.major ?? 1).\(version?.minor ?? 0).\(version?.patch ?? 0)"
        ], uniquingKeysWith: { _, new in new })
        let optimized = PromptOptimizer.optimize(document, for: ModelManager.shared.currentModelDiagnostics().providerKind, modelIdentifier: ModelManager.shared.activeModelIDDescription()).document
        return AIGenerationRequest(
            prompt: optimized.userPrompt,
            systemPrompt: optimized.systemPrompt,
            maxTokens: optimized.maxTokens,
            temperature: optimized.temperature,
            topP: optimized.topP,
            responseFormat: optimized.responseFormat,
            contextLimit: ModelManager.shared.currentModelDiagnostics().contextLength,
            metadata: metadata
        )
    }

    private func decodeKnowledgeSnapshot(from json: String?) -> StudyKnowledgeSnapshot? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StudyKnowledgeSnapshot.self, from: data)
    }

    private func decodeStructuredKnowledge(from json: String?) -> StructuredKnowledge? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StructuredKnowledge.self, from: data)
    }

    private func decodeOutput<T: Decodable>(_ type: T.Type, from text: String, rawText: String) throws -> T {
        let decoder = JSONDecoder()
        if let data = text.data(using: .utf8), let value = try? decoder.decode(T.self, from: data) {
            return value
        }
        if let repaired: T = PromptRepairer.repair(text, as: T.self) {
            return repaired
        }
        throw NSError(domain: "Notinq.PromptRegistry", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode prompt output for \(T.self). Raw: \(rawText)"])
    }

    private func estimatedTokenUsage(for result: AIGenerationResult) -> Int {
        guard let metrics = result.metrics else { return max(1, result.text.count / 4) }
        return max(1, Int(metrics.tokensPerSecond * metrics.generationTime))
    }

    func workspacePresetRequest(for preset: AIWorkspacePreset) -> String {
        switch preset {
        case .summarize:
            return "Summarize the note into a concise, study-ready overview."
        case .rewrite:
            return "Rewrite the note to be clearer and more readable without changing its meaning."
        case .explain:
            return "Explain the most important concept in the note simply and accurately."
        case .flashcards:
            return "Create 5 focused flashcards from the note."
        case .quiz:
            return "Generate a short, balanced quiz from the note."
        case .keyPoints:
            return "Extract the key points from the note."
        }
    }
}
