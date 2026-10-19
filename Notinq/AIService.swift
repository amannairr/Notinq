import Foundation

enum AIRequestKind {
    case summarize
    case simplify
    case rewrite(sourceLength: Int)
    case explain
    case add(sourceLength: Int)
    case ask
    case studyUnified
    case flashcards
    case studyQuiz
    case studyTutorQuestions
    case studyInsights
    case studySelection
    case studyEvaluation
    case noteCompletenessAnalysis
    case knowledgeGraphExtraction
    case followUp
    case editorProposal

    var maxTokens: Int32 {
        let cap = AIRuntimeConfig.current.llama.maxTokens
        switch self {
        case .summarize:
            return min(cap, 180)
        case .simplify:
            return min(cap, 260)
        case .rewrite(let sourceLength):
            return min(cap, Int32(min(360, max(200, sourceLength / 3))))
        case .explain:
            return min(cap, 420)
        case .add(let sourceLength):
            return min(cap, Int32(min(420, max(180, sourceLength / 4))))
        case .ask:
            return min(cap, 360)
        case .studyUnified:
            return min(max(cap, 1024), 1200)
        case .flashcards:
            return min(cap, 520)
        case .studyQuiz:
            return min(cap, 520)
        case .studyTutorQuestions:
            return min(cap, 420)
        case .studyInsights:
            return min(cap, 320)
        case .studySelection:
            return min(cap, 320)
        case .studyEvaluation:
            return min(cap, 280)
        case .noteCompletenessAnalysis:
            return min(cap, 720)
        case .knowledgeGraphExtraction:
            return min(max(cap, 768), 960)
        case .followUp:
            return min(cap, 300)
        case .editorProposal:
            return min(cap, 420)
        }
    }
}

final class AIService {
    static let shared = AIService()

    private let inferenceEngine = InferenceEngine.shared
    private let adaptiveTutorService = AdaptiveTutorService.shared

    struct CitedTutorResponse {
        let response: PromptTutorResponse
        let context: KnowledgeContext
        let adaptiveContext: AdaptiveTutorContext?

        var citations: [PromptTutorCitation] {
            if let responseCitations = response.citations, responseCitations.isEmpty == false {
                return responseCitations
            }
            return context.tutorContext.citations.map { $0.asTutorCitation }
        }
    }

    func run(prompt: String, contextLength: Int, completion: @escaping (String) -> Void) {
        run(prompt: prompt, contextLength: contextLength, kind: .ask, completion: completion)
    }

    func run(prompt: String, contextLength: Int, kind: AIRequestKind, completion: @escaping (String) -> Void) {
        let request = AIGenerationRequest(
            prompt: prompt,
            systemPrompt: PromptRegistry.shared.definition(for: .assistantChat).systemPrompt,
            maxTokens: kind.maxTokens,
            temperature: 0.5,
            topP: 0.92,
            responseFormat: .text,
            contextLimit: contextLength,
            metadata: ["requestKind": "\(kind)"]
        )

        Task {
            let response = (try? await inferenceEngine.generate(request))?.text ?? "Unable to generate response."
            await MainActor.run {
                completion(response)
            }
        }
    }

    func runStreaming(
        prompt: String,
        contextLength: Int,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        runStreaming(prompt: prompt, contextLength: contextLength, kind: .followUp, onToken: onToken, completion: completion)
    }

    func runStreaming(
        prompt: String,
        contextLength: Int,
        kind: AIRequestKind,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        let request = AIGenerationRequest(
            prompt: prompt,
            systemPrompt: PromptRegistry.shared.definition(for: .assistantChat).systemPrompt,
            maxTokens: kind.maxTokens,
            temperature: 0.45,
            topP: 0.92,
            responseFormat: .text,
            contextLimit: contextLength,
            metadata: ["requestKind": "\(kind)"]
        )

        Task {
            _ = try? await inferenceEngine.stream(request, onToken: onToken)
            await MainActor.run {
                completion()
            }
        }
    }

    func cancelGeneration() {
        inferenceEngine.cancel()
    }

    @discardableResult
    func editorProposal(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String,
        noteID: UUID? = nil,
        completion: @escaping (AIProposalGenerationResult) -> Void
    ) -> Task<Void, Never> {
        Task {
            if action == .dontUnderstand {
                let response = await sourceBackedAdaptiveProposalResponse(
                    selectedText: selectedText,
                    noteContext: noteContext,
                    noteID: noteID,
                    requestKind: "editorProposal.\(action.rawValue)",
                    maxTokens: AIRequestKind.editorProposal.maxTokens
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    completion(response)
                }
                return
            }

            let prompt = Self.editorProposalPrompt(
                action: action,
                selectedText: selectedText,
                noteContext: noteContext
            )
            let response = await adaptiveTextResponseWithContext(
                question: prompt,
                noteID: noteID,
                requestKind: "editorProposal.\(action.rawValue)",
                maxTokens: AIRequestKind.editorProposal.maxTokens
            )
            let adaptiveContext = response.context.map(AdaptiveExplanationContext.fromTutorContext)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                completion(
                    AIProposalGenerationResult(
                        generatedText: response.text,
                        adaptiveExplanationContext: action == .dontUnderstand ? adaptiveContext : nil
                    )
                )
            }
        }
    }

    static func editorProposalPrompt(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String
    ) -> String {
        AIActionPromptBuilder().prompt(
            action: action,
            selectedText: selectedText,
            noteContext: noteContext
        )
    }

    static func editorProposalPrompt(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String,
        adaptiveContext: AdaptiveExplanationContext?
    ) -> String {
        AIActionPromptBuilder().prompt(
            action: action,
            selectedText: selectedText,
            noteContext: noteContext,
            adaptiveContext: adaptiveContext
        )
    }

    func chat(noteTitle: String, noteText: String, userRequest: String, completion: @escaping (String) -> Void) {
        Task {
            let query = [userRequest, noteTitle, String(noteText.prefix(1_200))].joined(separator: "\n\n")
            let response = await adaptiveTextResponse(
                question: query,
                noteID: nil,
                requestKind: "adaptiveChat",
                maxTokens: AIRequestKind.ask.maxTokens
            )
            await MainActor.run {
                completion(response)
            }
        }
    }

    func citedTutorResponse(
        noteID: UUID?,
        noteTitle: String,
        noteText: String,
        userRequest: String,
        completion: @escaping (CitedTutorResponse) -> Void
    ) {
        let knowledgeContext = KnowledgeService.shared.buildContext(noteID: noteID, title: noteTitle, text: noteText)
        let snapshot = knowledgeContext.studySnapshotRepresentation()
        let promptContext = PromptBuildContext(
            noteTitle: noteTitle,
            noteText: truncate(noteText, limit: 4_000),
            structuredKnowledge: snapshot.structuredKnowledgeRepresentation(),
            knowledgeSnapshot: snapshot,
            tutorContext: knowledgeContext.tutorContext,
            selectedText: nil,
            userRequest: userRequest,
            providerKind: ModelManager.shared.currentModelDiagnostics().providerKind,
            modelIdentifier: ModelManager.shared.activeModelIDDescription(),
            noteSignature: noteID?.uuidString,
            contextLimit: Int(AIRuntimeConfig.current.llama.contextSize)
        )
        let input = PromptTutorInput(noteTitle: noteTitle, knowledge: snapshot, question: userRequest)

        Task {
            do {
                let adaptiveContext = try await adaptiveTutorService.buildContext(
                    question: [userRequest, noteTitle, String(noteText.prefix(1_200))].joined(separator: "\n\n"),
                    noteID: noteID
                )
                let request = adaptiveTutorService.request(
                    for: adaptiveContext,
                    requestKind: "adaptiveCitedTutor",
                    maxTokens: AIRequestKind.ask.maxTokens
                )
                let answer = try await inferenceEngine.generate(request).text
                let response = PromptTutorResponse(
                    answer: answer,
                    keyPoints: adaptiveContext.relevantConcepts.prefix(5).map(\.name),
                    followUpQuestions: adaptiveContext.missingPrerequisites.prefix(3).map { "Review \($0.name) next?" },
                    confidence: adaptiveContext.relevantConcepts.isEmpty ? 0.55 : 0.75,
                    citations: nil
                )
                await MainActor.run {
                    completion(CitedTutorResponse(response: response, context: knowledgeContext, adaptiveContext: adaptiveContext))
                }
            } catch {
                do {
                    let execution = try await PromptRegistry.shared.execute(TutorPrompt.self, input: input, context: promptContext)
                    await MainActor.run {
                        completion(CitedTutorResponse(response: execution.output, context: knowledgeContext, adaptiveContext: nil))
                    }
                } catch {
                    chat(noteTitle: noteTitle, noteText: noteText, userRequest: userRequest) { responseText in
                        let fallback = PromptTutorResponse(
                            answer: responseText,
                            keyPoints: [],
                            followUpQuestions: [],
                            confidence: 0.5,
                            citations: nil
                        )
                        completion(CitedTutorResponse(response: fallback, context: knowledgeContext, adaptiveContext: nil))
                    }
                }
            }
        }
    }

    func extractStructuredKnowledge(noteTitle: String, noteText: String, notebookText: String = "") async -> StructuredKnowledge {
        let structure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: noteText)
        return await extractStructuredKnowledge(from: structure, notebookText: notebookText)
    }

    func extractStructuredKnowledge(from structure: DocumentStructure, notebookText: String = "") async -> StructuredKnowledge {
        await LearningEngine.shared.extractStructuredKnowledge(from: structure, notebookText: notebookText)
    }

    func extractKnowledge(noteTitle: String, noteText: String, notebookText: String = "") async -> StudyKnowledgeSnapshot {
        let structure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: noteText)
        return await extractKnowledge(from: structure, notebookText: notebookText)
    }

    func extractKnowledge(from structure: DocumentStructure, notebookText: String = "") async -> StudyKnowledgeSnapshot {
        await LearningEngine.shared.extractKnowledge(from: structure, notebookText: notebookText)
    }

    func inspectKnowledgeExtraction(noteTitle: String, noteText: String, notebookText: String = "") async -> KnowledgeExtractionDebugReport {
        let structure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: noteText)
        return await inspectKnowledgeExtraction(from: structure, notebookText: notebookText)
    }

    func inspectKnowledgeExtraction(from structure: DocumentStructure, notebookText: String = "") async -> KnowledgeExtractionDebugReport {
        await KnowledgeExtractionEngine.shared.inspectExtraction(from: structure, notebookText: notebookText)
    }

    func generateStudyData(
        noteTitle: String,
        noteText: String,
        notebookText: String = "",
        existingStudyData: NoteStudyData
    ) async -> NoteStudyData {
        let structure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: noteText)
        return await generateStudyData(from: structure, notebookText: notebookText, existingStudyData: existingStudyData)
    }

    func generateStudyData(
        from structure: DocumentStructure,
        notebookText: String = "",
        existingStudyData: NoteStudyData
    ) async -> NoteStudyData {
        let adaptiveStudyData = await adaptiveStudySeed(
            title: structure.title,
            text: structure.normalizedText,
            existingStudyData: existingStudyData
        )
        let knowledge = await extractStructuredKnowledge(from: structure, notebookText: notebookText)
        return LearningEngine.shared.generateStudyData(from: knowledge, existingStudyData: adaptiveStudyData)
    }

    func generateStudyData(
        noteTitle: String,
        noteText: String,
        notebookText: String = ""
    ) async -> NoteStudyData {
        let structure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: noteText)
        return await generateStudyData(from: structure, notebookText: notebookText, existingStudyData: NoteStudyData())
    }

    func generateStudyQuestion(
        action: StudyQuestionGenerationAction,
        source: StudyQuestionGenerationSource
    ) async -> StudyQuestionGenerationOutput {
        let prompt = Self.studyQuestionPrompt(action: action, source: source)
        let response = await adaptiveTextResponse(
            question: prompt,
            noteID: source.noteID,
            requestKind: "studyQuestion.\(action.rawValue)",
            maxTokens: action == .generateFlashcard ? AIRequestKind.flashcards.maxTokens : AIRequestKind.studyQuiz.maxTokens
        )
        return Self.parseStudyQuestionResponse(response, action: action, source: source)
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n[Context truncated]"
    }

    private func adaptiveTextResponse(
        question: String,
        noteID: UUID?,
        requestKind: String,
        maxTokens: Int32
    ) async -> String {
        let request = await adaptiveRequest(
            question: question,
            noteID: noteID,
            requestKind: requestKind,
            maxTokens: maxTokens
        )
        return (try? await inferenceEngine.generate(request))?.text ?? "Unable to generate response."
    }

    private func adaptiveTextResponseWithContext(
        question: String,
        noteID: UUID?,
        requestKind: String,
        maxTokens: Int32
    ) async -> (text: String, context: AdaptiveTutorContext?) {
        do {
            let context = try await adaptiveTutorService.buildContext(question: question, noteID: noteID)
            let request = adaptiveTutorService.request(for: context, requestKind: requestKind, maxTokens: maxTokens)
            let text = (try? await inferenceEngine.generate(request))?.text ?? "Unable to generate response."
            return (text, context)
        } catch {
            let request = AIGenerationRequest(
                prompt: question,
                systemPrompt: PromptRegistry.shared.definition(for: .assistantChat).systemPrompt,
                maxTokens: maxTokens,
                temperature: 0.45,
                topP: 0.92,
                responseFormat: .text,
                contextLimit: Int(AIRuntimeConfig.current.llama.contextSize),
                metadata: ["requestKind": requestKind, "graphAware": "false"]
            )
            let text = (try? await inferenceEngine.generate(request))?.text ?? "Unable to generate response."
            return (text, nil)
        }
    }

    private func sourceBackedAdaptiveProposalResponse(
        selectedText: String,
        noteContext: String,
        noteID: UUID?,
        requestKind: String,
        maxTokens: Int32
    ) async -> AIProposalGenerationResult {
        do {
            let seedPrompt = Self.editorProposalPrompt(
                action: .dontUnderstand,
                selectedText: selectedText,
                noteContext: noteContext
            )
            let context = try await adaptiveTutorService.buildContext(question: seedPrompt, noteID: noteID)
            var adaptiveContext = AdaptiveExplanationContext.fromTutorContext(context)
            adaptiveContext.selectedText = selectedText
            let profiles = ConceptLearningProfileBuilder().profiles(
                for: adaptiveContext.conceptIDs,
                signals: LearningSignalStore.shared.allSignals()
            )
            adaptiveContext.applyLearningProfiles(
                Array(profiles.values),
                conceptNameByID: Self.conceptNameByID(from: context)
            )
            let groundedPrompt = Self.editorProposalPrompt(
                action: .dontUnderstand,
                selectedText: selectedText,
                noteContext: noteContext,
                adaptiveContext: adaptiveContext
            )
            let request = AIGenerationRequest(
                prompt: groundedPrompt,
                systemPrompt: PromptRegistry.shared.definition(for: .assistantChat).systemPrompt,
                maxTokens: maxTokens,
                temperature: 0.45,
                topP: 0.9,
                responseFormat: .text,
                contextLimit: Int(AIRuntimeConfig.current.llama.contextSize),
                metadata: [
                    "requestKind": requestKind,
                    "graphAware": "true",
                    "sourceBacked": adaptiveContext.hasSourceGrounding ? "true" : "false",
                    "adaptiveContextSources": "\(adaptiveContext.retrievedNoteSources.count)"
                ]
            )
            let text = (try? await inferenceEngine.generate(request))?.text ?? "Unable to generate response."
            return AIProposalGenerationResult(
                generatedText: text,
                adaptiveExplanationContext: adaptiveContext
            )
        } catch {
            let fallbackContext = AdaptiveExplanationContext.unavailable()
            let prompt = Self.editorProposalPrompt(
                action: .dontUnderstand,
                selectedText: selectedText,
                noteContext: noteContext,
                adaptiveContext: fallbackContext
            )
            let request = AIGenerationRequest(
                prompt: prompt,
                systemPrompt: PromptRegistry.shared.definition(for: .assistantChat).systemPrompt,
                maxTokens: maxTokens,
                temperature: 0.45,
                topP: 0.9,
                responseFormat: .text,
                contextLimit: Int(AIRuntimeConfig.current.llama.contextSize),
                metadata: [
                    "requestKind": requestKind,
                    "graphAware": "false",
                    "sourceBacked": "false"
                ]
            )
            let text = (try? await inferenceEngine.generate(request))?.text ?? "Unable to generate response."
            return AIProposalGenerationResult(
                generatedText: text,
                adaptiveExplanationContext: fallbackContext
            )
        }
    }

    static func studyQuestionPrompt(action: StudyQuestionGenerationAction, source: StudyQuestionGenerationSource) -> String {
        let task: String
        switch action {
        case .generateFlashcard:
            task = "Create one flashcard with a front prompt and a concise back answer."
        case .recallQuestion:
            task = "Create one recall question that checks whether the student remembers the selected content."
        case .understandingQuestion:
            task = "Create one conceptual understanding question that asks why or how the selected content works."
        case .applicationQuestion:
            task = "Create one application question that asks the student to use the selected content in a new situation."
        }

        return [
            "Generate one study item from the student's selected note content.",
            "",
            "SELECTED CONTENT",
            source.selectedText,
            "",
            "SURROUNDING NOTE CONTEXT",
            String(source.noteContext.prefix(2_400)),
            "",
            "TASK",
            task,
            "",
            "Return compact JSON only:",
            "{\"question\":\"...\",\"answer\":\"...\",\"concept\":\"...\",\"explanation\":\"...\"}",
            "",
            "Rules:",
            "- Do not invent facts outside the supplied note context.",
            "- Keep the item short enough for quick studying.",
            "- The concept should be the main source concept tested by the item."
        ].joined(separator: "\n")
    }

    static func parseStudyQuestionResponse(
        _ response: String,
        action: StudyQuestionGenerationAction,
        source: StudyQuestionGenerationSource
    ) -> StudyQuestionGenerationOutput {
        let payload = jsonObject(from: response)
        let questionText = payload?["question"] as? String
        let answerText = payload?["answer"] as? String
        let concept = (payload?["concept"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let explanation = (payload?["explanation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackConcept = concept?.isEmpty == false ? concept! : inferredConcept(from: source.selectedText)
        let reference = StudyQuestionSourceReference(
            noteID: source.noteID,
            range: source.sourceRange,
            excerpt: source.sourceExcerpt
        )
        let answer = answerText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? answerText!.trimmingCharacters(in: .whitespacesAndNewlines)
            : String(source.selectedText.prefix(220))
        let question = questionText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? questionText!.trimmingCharacters(in: .whitespacesAndNewlines)
            : fallbackQuestion(for: action, concept: fallbackConcept)

        switch action {
        case .generateFlashcard:
            return StudyQuestionGenerationOutput(
                flashcard: StudyFlashcard(
                    type: .questionAnswer,
                    front: question,
                    back: answer,
                    whyItMatters: explanation,
                    conceptIDs: [fallbackConcept],
                    sourceConcept: fallbackConcept,
                    cognitiveLevel: .recall,
                    sourceReferences: [reference],
                    generationAction: action
                ),
                question: nil
            )
        case .recallQuestion, .understandingQuestion, .applicationQuestion:
            let type: StudyQuizQuestionType
            let level: StudyQuestionCognitiveLevel
            switch action {
            case .generateFlashcard:
                type = .shortAnswer
                level = .recall
            case .recallQuestion:
                type = .shortAnswer
                level = .recall
            case .understandingQuestion:
                type = .conceptualUnderstanding
                level = .understanding
            case .applicationQuestion:
                type = .application
                level = .application
            }
            return StudyQuestionGenerationOutput(
                flashcard: nil,
                question: StudyQuizQuestion(
                    type: type,
                    prompt: question,
                    correctAnswer: answer,
                    explanation: explanation,
                    keywords: [fallbackConcept],
                    conceptIDs: [fallbackConcept],
                    sourceConcept: fallbackConcept,
                    cognitiveLevel: level,
                    sourceReferences: [reference],
                    generationAction: action
                )
            )
        }
    }

    private static func jsonObject(from response: String) -> [String: Any]? {
        guard
            let start = response.firstIndex(of: "{"),
            let end = response.lastIndex(of: "}")
        else { return nil }
        let json = String(response[start...end])
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func inferredConcept(from text: String) -> String {
        let words = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        return words.prefix(3).joined(separator: " ").isEmpty ? "Selected Concept" : words.prefix(3).joined(separator: " ")
    }

    private static func fallbackQuestion(for action: StudyQuestionGenerationAction, concept: String) -> String {
        switch action {
        case .generateFlashcard, .recallQuestion:
            return "What should you remember about \(concept)?"
        case .understandingQuestion:
            return "Why does \(concept) matter in this note?"
        case .applicationQuestion:
            return "How would you apply \(concept) in a new example?"
        }
    }

    private static func conceptNameByID(from context: AdaptiveTutorContext) -> [String: String] {
        var names: [String: String] = [:]
        let concepts = context.weakConcepts
            + context.strongConcepts
            + context.missingPrerequisites
            + context.knowledgeGaps
            + context.relevantConcepts
            + context.relatedConcepts
        for concept in concepts {
            names[concept.id.uuidString] = concept.name
        }
        return names
    }

    private func adaptiveRequest(
        question: String,
        noteID: UUID?,
        requestKind: String,
        maxTokens: Int32
    ) async -> AIGenerationRequest {
        do {
            let context = try await adaptiveTutorService.buildContext(question: question, noteID: noteID)
            return adaptiveTutorService.request(for: context, requestKind: requestKind, maxTokens: maxTokens)
        } catch {
            return AIGenerationRequest(
                prompt: question,
                systemPrompt: PromptRegistry.shared.definition(for: .assistantChat).systemPrompt,
                maxTokens: maxTokens,
                temperature: 0.45,
                topP: 0.92,
                responseFormat: .text,
                contextLimit: Int(AIRuntimeConfig.current.llama.contextSize),
                metadata: ["requestKind": requestKind, "graphAware": "false"]
            )
        }
    }

    private func adaptiveStudySeed(
        title: String,
        text: String,
        existingStudyData: NoteStudyData
    ) async -> NoteStudyData {
        do {
            let query = ["Generate study materials.", title, String(text.prefix(1_500))].joined(separator: "\n\n")
            let context = try await adaptiveTutorService.buildContext(question: query, noteID: nil)
            var seeded = existingStudyData
            let weakNames = Set((context.weakConcepts + context.knowledgeGaps + context.missingPrerequisites).map(\.name))
            let strongNames = Set(context.strongConcepts.map(\.name))
            let adaptiveEntries = context.relevantConcepts.prefix(20).map { concept -> StudyMemoryEntry in
                let name = concept.name
                if weakNames.contains(name) {
                    return StudyMemoryEntry(concept: name, masteredCount: 0, missedCount: 1, reviewHistory: [], lastReviewedAt: nil, lastOutcome: .incorrect)
                }
                if strongNames.contains(name) {
                    return StudyMemoryEntry(concept: name, masteredCount: 1, missedCount: 0, reviewHistory: [], lastReviewedAt: nil, lastOutcome: .correct)
                }
                return StudyMemoryEntry(concept: name, masteredCount: 0, missedCount: 0, reviewHistory: [], lastReviewedAt: nil, lastOutcome: .almost)
            }
            seeded.learningMemory = mergeStudyMemory(existing: seeded.learningMemory, adaptive: adaptiveEntries)
            return seeded
        } catch {
            return existingStudyData
        }
    }

    private func mergeStudyMemory(existing: [StudyMemoryEntry], adaptive: [StudyMemoryEntry]) -> [StudyMemoryEntry] {
        var byConcept = Dictionary(existing.map { ($0.concept, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in adaptive where byConcept[entry.concept] == nil {
            byConcept[entry.concept] = entry
        }
        return byConcept.values.sorted { $0.concept.localizedCaseInsensitiveCompare($1.concept) == .orderedAscending }
    }
}

private extension CitationReference {
    var asTutorCitation: PromptTutorCitation {
        PromptTutorCitation(
            sourceType: sourceType.rawValue,
            sourceID: sourceID,
            noteTitle: noteTitle,
            conceptName: conceptName,
            snippet: snippet
        )
    }
}
