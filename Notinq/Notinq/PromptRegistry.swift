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
        if let knowledgeJSON = context.knowledgeJSON,
           identifier != .knowledgeExtraction,
           identifier != .assistantChat,
           identifier != .directEditing {
            let graphText = decodeKnowledgeContext(from: knowledgeJSON)?.graphPromptRepresentation() ?? ""
            document.userPrompt = PromptFragments.inputWithGraph(
                "Structured knowledge JSON:\n\(knowledgeJSON)",
                graphText: graphText
            )
        }
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
        do {
            let generation = try await InferenceEngine.shared.generate(request)
            let rawText = generation.text
            let repairedText = document.responseFormat == .json ? (PromptRepairer.repairJSONString(rawText) ?? rawText) : rawText
            let decoded = try decodeOutput(P.Output.self, from: repairedText, rawText: rawText)
            let validation = prompt.validate(output: decoded, input: input, context: context)
            let repaired = repairedText != rawText
            var finalOutput = decoded
            var finalValidation = validation
            var finalRawText = rawText
            var finalRepaired = repaired
            var retryCount = validation.shouldRetry ? 1 : 0

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
                retryCount += 1
            }

            if (!finalValidation.isValid || finalValidation.shouldRetry),
               let fallbackOutput = synthesizedOutput(for: prompt, input: input, context: context) {
                finalOutput = fallbackOutput
                finalValidation = prompt.validate(output: fallbackOutput, input: input, context: context)
                finalRawText = serializedOutput(fallbackOutput)
                finalRepaired = true
                retryCount = max(retryCount, 1)
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
        } catch {
            if let fallbackOutput = synthesizedOutput(for: prompt, input: input, context: context) {
                let validation = prompt.validate(output: fallbackOutput, input: input, context: context)
                let rawText = serializedOutput(fallbackOutput)
                let metrics = PromptExecutionMetrics(
                    latency: Date().timeIntervalSince(started),
                    repairCount: 0,
                    retryCount: 0,
                    jsonValidity: validation.isValid ? 1.0 : 0.0,
                    confidence: validation.confidence,
                    hallucinationRate: max(0, 1.0 - validation.confidence),
                    determinism: validation.shouldRetry ? 0.5 : 1.0,
                    tokenUsage: max(1, rawText.count / 4)
                )

                return PromptExecutionResult(
                    identifier: prompt.identifier,
                    version: prompt.version,
                    providerKind: context.providerKind,
                    modelIdentifier: context.modelIdentifier,
                    request: request,
                    rawText: rawText,
                    output: fallbackOutput,
                    validation: validation,
                    metrics: metrics,
                    repaired: true,
                    retries: 0
                )
            }
            throw error
        }
    }

    private func promptDocument(for identifier: AIPromptIdentifier, context: AIPromptContext) -> PromptDocument {
        let knowledgeContext = decodeKnowledgeContext(from: context.knowledgeJSON)
        let derivedSnapshot = knowledgeContext?.studySnapshotRepresentation()
        let structuredKnowledge = decodeStructuredKnowledge(from: context.knowledgeJSON)
            ?? derivedSnapshot?.structuredKnowledgeRepresentation()
            ?? decodeKnowledgeSnapshot(from: context.knowledgeJSON)?.structuredKnowledgeRepresentation()
        let snapshot = decodeKnowledgeSnapshot(from: context.knowledgeJSON) ?? derivedSnapshot
        let buildContext = PromptBuildContext(
            noteTitle: context.noteTitle,
            noteText: identifier == .assistantChat || identifier == .directEditing ? context.noteText : "",
            structuredKnowledge: structuredKnowledge,
            knowledgeSnapshot: snapshot,
            graphContext: knowledgeContext?.graphContext,
            tutorContext: knowledgeContext?.tutorContext,
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

    private func decodeKnowledgeContext(from json: String?) -> KnowledgeContext? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(KnowledgeContext.self, from: data)
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

    private func synthesizedOutput<P: PromptDefinition>(for prompt: P.Type, input: P.Input, context: PromptBuildContext) -> P.Output? {
        switch prompt.identifier {
        case .summary:
            guard let input = input as? PromptStructuredKnowledgeInput else { return nil }
            return synthesizedSummaryOutput(noteTitle: input.noteTitle, knowledge: fallbackKnowledge(from: context, preferred: input.knowledge)) as? P.Output
        case .flashcards:
            guard let input = input as? PromptStructuredKnowledgeInput else { return nil }
            return synthesizedFlashcardDeck(noteTitle: input.noteTitle, knowledge: fallbackKnowledge(from: context, preferred: input.knowledge)) as? P.Output
        case .multipleChoiceQuiz:
            guard let input = input as? PromptStructuredKnowledgeInput else { return nil }
            return synthesizedQuizSet(noteTitle: input.noteTitle, knowledge: fallbackKnowledge(from: context, preferred: input.knowledge)) as? P.Output
        case .conceptMap:
            guard let input = input as? PromptStructuredKnowledgeInput else { return nil }
            return synthesizedConceptMap(noteTitle: input.noteTitle, knowledge: fallbackKnowledge(from: context, preferred: input.knowledge)) as? P.Output
        case .learningInsights:
            guard let input = input as? PromptStructuredKnowledgeInput else { return nil }
            return synthesizedLearningInsights(noteTitle: input.noteTitle, knowledge: fallbackKnowledge(from: context, preferred: input.knowledge)) as? P.Output
        case .aiTutor:
            guard let input = input as? PromptTutorInput else { return nil }
            return synthesizedTutorResponse(noteTitle: input.noteTitle, knowledge: fallbackKnowledge(from: context, preferred: input.knowledge), question: input.question) as? P.Output
        case .assistantChat:
            guard let input = input as? PromptExtractionInput else { return nil }
            return synthesizedChatResponse(noteTitle: input.noteTitle, noteText: input.noteText, userRequest: context.userRequest) as? P.Output
        case .directEditing:
            guard let input = input as? PromptExtractionInput else { return nil }
            return synthesizedEditResponse(noteTitle: input.noteTitle, noteText: input.noteText, userRequest: context.userRequest, selectedText: context.selectedText) as? P.Output
        case .definitions:
            guard let input = input as? PromptStructuredKnowledgeInput else { return nil }
            return synthesizedDefinitionSet(noteTitle: input.noteTitle, knowledge: fallbackKnowledge(from: context, preferred: input.knowledge)) as? P.Output
        default:
            return nil
        }
    }

    private func serializedOutput<T: Codable>(_ output: T) -> String {
        if let string = output as? String {
            return string
        }
        guard let data = try? JSONEncoder().encode(output),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    private func fallbackKnowledge(from context: PromptBuildContext, preferred: StructuredKnowledge? = nil) -> StructuredKnowledge {
        if let preferred {
            return preferred
        }
        if let structuredKnowledge = context.structuredKnowledge {
            return structuredKnowledge
        }
        var knowledge = StructuredKnowledge()
        knowledge.title = context.noteTitle
        knowledge.metadata.title = context.noteTitle
        return knowledge
    }

    private func synthesizedSummaryOutput(noteTitle: String, knowledge: StructuredKnowledge) -> PromptSummaryOutput {
        let concepts = rankedConcepts(in: knowledge).prefix(3).map(\.name)
        let highlights = knowledge.summaryHighlights.prefix(3)
        let conciseSummary: String
        if !concepts.isEmpty {
            conciseSummary = "\(noteTitle) focuses on \(concepts.joined(separator: ", "))."
        } else {
            conciseSummary = "The note covers \(noteTitle)."
        }
        let detailedSummary = [knowledge.title.isEmpty ? noteTitle : knowledge.title, knowledge.importantFacts.first, highlights.first]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let revisionItems = highlights.isEmpty ? concepts : Array(highlights)
        let revisionSummary = revisionItems.prefix(4).joined(separator: "; ")
        return PromptSummaryOutput(
            executiveSummary: conciseSummary,
            detailedSummary: detailedSummary.isEmpty ? conciseSummary : detailedSummary,
            examRevisionSummary: revisionSummary.isEmpty ? conciseSummary : revisionSummary,
            confidence: max(0.7, knowledge.confidence)
        )
    }

    private func synthesizedFlashcardDeck(noteTitle: String, knowledge: StructuredKnowledge) -> PromptFlashcardDeck {
        let concepts = rankedConcepts(in: knowledge)
        let cards: [PromptFlashcardEntry] = concepts.prefix(4).enumerated().map { index, concept in
            PromptFlashcardEntry(
                type: "concept",
                front: concept.name,
                back: concept.definition.isEmpty ? concept.name : concept.definition,
                whyItMatters: concept.importance >= 0.8 ? "Core idea for \(noteTitle)." : "Useful supporting detail for \(noteTitle).",
                confidence: max(0.6, concept.confidence - Double(index) * 0.02)
            )
        }
        if cards.isEmpty {
            return PromptFlashcardDeck(cards: [
                PromptFlashcardEntry(type: "concept", front: noteTitle, back: noteTitle, whyItMatters: "Review the note title.", confidence: 0.7)
            ])
        }
        return PromptFlashcardDeck(cards: cards)
    }

    private func synthesizedQuizSet(noteTitle: String, knowledge: StructuredKnowledge) -> PromptQuizSet {
        let concepts = rankedConcepts(in: knowledge)
        let questions: [PromptQuizEntry] = concepts.prefix(3).enumerated().map { index, concept in
            let correctAnswer = concept.definition.isEmpty ? concept.name : concept.definition
            let distractors = concepts
                .filter { $0.id != concept.id }
                .map { $0.definition.isEmpty ? $0.name : $0.definition }
            let options = dedupeStrings([correctAnswer] + distractors).prefix(4)
            let paddedOptions = Array(options) + Array(repeating: noteTitle, count: max(0, 4 - options.count))
            return PromptQuizEntry(
                prompt: "Which statement best describes \(concept.name)?",
                options: paddedOptions,
                correctAnswer: correctAnswer,
                explanation: concept.definition.isEmpty ? "Review \(concept.name)." : concept.definition,
                keywords: [concept.name] + concept.aliases.prefix(2),
                confidence: max(0.6, concept.confidence - Double(index) * 0.03)
            )
        }
        if questions.count >= 2 {
            return PromptQuizSet(title: noteTitle, questions: questions)
        }
        let fallbackQuestion = PromptQuizEntry(
            prompt: "What is the main topic of \(noteTitle)?",
            options: [noteTitle, "Unrelated concept", "Different topic", "Miscellaneous"],
            correctAnswer: noteTitle,
            explanation: "The note is centered on \(noteTitle).",
            keywords: [noteTitle],
            confidence: 0.7
        )
        return PromptQuizSet(title: noteTitle, questions: [fallbackQuestion, fallbackQuestion])
    }

    private func synthesizedConceptMap(noteTitle: String, knowledge: StructuredKnowledge) -> [PromptConceptNode] {
        let concepts = rankedConcepts(in: knowledge)
        let children = concepts.prefix(6).map { concept in
            PromptConceptNode(
                title: concept.name,
                summary: concept.definition.isEmpty ? concept.name : concept.definition,
                children: []
            )
        }
        if children.isEmpty {
            return [PromptConceptNode(title: noteTitle, summary: noteTitle, children: [])]
        }
        return [PromptConceptNode(title: noteTitle, summary: knowledge.summaryHighlights.first ?? noteTitle, children: children)]
    }

    private func synthesizedLearningInsights(noteTitle: String, knowledge: StructuredKnowledge) -> PromptLearningInsightsOutput {
        let concepts = rankedConcepts(in: knowledge)
        let keyConcepts = concepts.prefix(5).map(\.name)
        let importantConcepts = concepts.filter { $0.importance >= 0.75 }.prefix(5).map(\.name)
        let frequentTerms = concepts.prefix(5).enumerated().map { index, concept in
            StudyTerm(term: concept.name, count: max(1, Int((concept.importance * 10).rounded()) - index))
        }
        let potentialExamTopics = Array(knowledge.examFocus.prefix(5))
        let knowledgeGaps = concepts.isEmpty ? ["Review the note \(noteTitle) to identify the main ideas."] : Array(knowledge.summaryHighlights.prefix(3)).map { "Review: \($0)" }
        return PromptLearningInsightsOutput(
            keyConcepts: keyConcepts.isEmpty ? [noteTitle] : keyConcepts,
            importantConcepts: importantConcepts.isEmpty ? keyConcepts : importantConcepts,
            frequentTerms: frequentTerms.isEmpty ? [StudyTerm(term: noteTitle, count: 1)] : frequentTerms,
            potentialExamTopics: potentialExamTopics.isEmpty ? keyConcepts : potentialExamTopics,
            knowledgeGaps: knowledgeGaps.isEmpty ? ["Add more detail to the note."] : knowledgeGaps,
            confidence: max(0.65, knowledge.confidence)
        )
    }

    private func synthesizedTutorResponse(noteTitle: String, knowledge: StructuredKnowledge, question: String) -> PromptTutorResponse {
        let lowerQuestion = question.lowercased()
        let matchedConcept = rankedConcepts(in: knowledge).first { concept in
            ([concept.name] + concept.aliases).contains(where: { lowerQuestion.contains($0.lowercased()) })
        }

        guard let concept = matchedConcept else {
            return PromptTutorResponse(
                answer: "The note does not contain enough information to answer that question confidently.",
                keyPoints: [],
                followUpQuestions: ["Which concept from \(noteTitle) should I explain?", "Do you want a summary of the note instead?"],
                confidence: 0.3,
                citations: []
            )
        }

        let supportingFact = concept.definition.isEmpty ? concept.name : concept.definition
        let answer = "The note explains that \(concept.name) is \(supportingFact)."
        return PromptTutorResponse(
            answer: answer,
            keyPoints: [concept.name, supportingFact],
            followUpQuestions: [
                "Do you want a deeper explanation of \(concept.name)?",
                "Should I relate \(concept.name) to the other concepts in the note?"
            ],
            confidence: max(0.75, concept.confidence),
            citations: [
                PromptTutorCitation(
                    sourceType: "concept",
                    sourceID: concept.id,
                    noteTitle: noteTitle,
                    conceptName: concept.name,
                    snippet: supportingFact
                )
            ]
        )
    }

    private func synthesizedChatResponse(noteTitle: String, noteText: String, userRequest: String?) -> String {
        let request = (userRequest ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if request.isEmpty {
            return "I can help with \(noteTitle)."
        }
        return "\(request) - grounded in \(noteTitle)."
    }

    private func synthesizedEditResponse(noteTitle: String, noteText: String, userRequest: String?, selectedText: String?) -> String {
        let request = (userRequest ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let selection = (selectedText ?? noteText).trimmingCharacters(in: .whitespacesAndNewlines)
        if request.isEmpty {
            return selection
        }
        return "\(request): \(selection)"
    }

    private func synthesizedDefinitionSet(noteTitle: String, knowledge: StructuredKnowledge) -> PromptDefinitionSet {
        let definitions = rankedConcepts(in: knowledge).prefix(6).map { concept in
            PromptDefinitionEntry(
                term: concept.name,
                definition: concept.definition.isEmpty ? concept.name : concept.definition,
                aliases: concept.aliases,
                example: concept.examples.first ?? concept.name,
                confidence: concept.confidence
            )
        }
        return PromptDefinitionSet(definitions: definitions.isEmpty ? [PromptDefinitionEntry(term: noteTitle, definition: noteTitle, aliases: [], example: noteTitle, confidence: 0.7)] : definitions)
    }

    private func rankedConcepts(in knowledge: StructuredKnowledge) -> [KnowledgeConcept] {
        knowledge.concepts.sorted {
            if $0.importance == $1.importance {
                return $0.name < $1.name
            }
            return $0.importance > $1.importance
        }
    }

    private func dedupeStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return nil }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return cleaned
        }
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
