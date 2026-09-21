import Foundation

enum AIAction {
    case summarize
    case simplify
    case rewrite
    case explain
    case add
    case ask

    var title: String {
        switch self {
        case .summarize: return "Summary"
        case .simplify: return "Simplify"
        case .rewrite: return "Rewrite"
        case .explain: return "Explanation"
        case .add: return "Addition"
        case .ask: return "Ask AI"
        }
    }

    var blockTitle: String {
        switch self {
        case .summarize: return "Summary"
        case .simplify: return "Simplify"
        case .rewrite: return "Rewrite"
        case .explain: return "Explain"
        case .add: return "Continue"
        case .ask: return "Ask AI"
        }
    }
}

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
    case editorExpand

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
        case .editorExpand:
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

    func directEdit(
        action: AIAction,
        selectedText: String,
        noteContext: String,
        noteID: UUID? = nil,
        completion: @escaping (String) -> Void
    ) {
        Task {
            let query = [
                action.promptInstruction(),
                selectedText,
                String(noteContext.prefix(1_200))
            ].joined(separator: "\n\n")
            let response = await adaptiveTextResponse(
                question: query,
                noteID: noteID,
                requestKind: "adaptiveDirectEdit",
                maxTokens: AIRequestKind.explain.maxTokens
            )
            await MainActor.run {
                completion(response)
            }
        }
    }

    func editorProposal(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String,
        noteID: UUID? = nil,
        completion: @escaping (String) -> Void
    ) {
        Task {
            let prompt = Self.editorProposalPrompt(
                action: action,
                selectedText: selectedText,
                noteContext: noteContext
            )
            let response = await adaptiveTextResponse(
                question: prompt,
                noteID: noteID,
                requestKind: "editorProposal.\(action.rawValue)",
                maxTokens: AIRequestKind.editorExpand.maxTokens
            )
            await MainActor.run {
                completion(response)
            }
        }
    }

    static func editorProposalPrompt(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String
    ) -> String {
        switch action {
        case .expand:
            return [
                "Expand the selected idea into clearer educational prose.",
                "Preserve the original meaning and important terminology.",
                "Do not invent facts not supported by the selected text or surrounding note context.",
                "Use surrounding note context only to improve terminology, coherence, and level; do not let unrelated context override the selected idea.",
                "Match the level and style of the surrounding notes.",
                "Add useful explanation without unnecessary verbosity.",
                "Return clean Markdown suitable for rich text rendering.",
                "Selected text:",
                selectedText,
                "Surrounding note context:",
                String(noteContext.prefix(1_500))
            ].joined(separator: "\n\n")
        case .explain:
            return [
                "Explain the selected idea clearly using the surrounding note context when relevant.",
                "Return clean Markdown suitable for rich text rendering.",
                "Selected text:",
                selectedText,
                "Surrounding note context:",
                String(noteContext.prefix(1_500))
            ].joined(separator: "\n\n")
        }
    }

    func streamFollowUp(
        noteContext: String,
        followUpTitle: String,
        blockContent: String,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        Task {
            let query = [
                "\(followUpTitle) the following generated passage while preserving the note's context.",
                blockContent,
                String(noteContext.prefix(1_200))
            ].joined(separator: "\n\n")
            let request = await adaptiveRequest(
                question: query,
                noteID: nil,
                requestKind: "adaptiveFollowUp",
                maxTokens: AIRequestKind.followUp.maxTokens
            )
            _ = try? await inferenceEngine.stream(request, onToken: onToken)
            await MainActor.run {
                completion()
            }
        }
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
        var byConcept = Dictionary(uniqueKeysWithValues: existing.map { ($0.concept, $0) })
        for entry in adaptive where byConcept[entry.concept] == nil {
            byConcept[entry.concept] = entry
        }
        return byConcept.values.sorted { $0.concept.localizedCaseInsensitiveCompare($1.concept) == .orderedAscending }
    }
}

private extension AIAction {
    func promptInstruction() -> String {
        switch self {
        case .summarize:
            return "Summarize the selected text into a study-ready overview."
        case .simplify:
            return "Rewrite the selected text in simpler language without losing meaning."
        case .rewrite:
            return "Rewrite the selected text for clarity and flow while preserving every fact."
        case .explain:
            return "Explain the selected text in plain language. Include prerequisite concepts and weak areas when the adaptive context identifies them."
        case .add:
            return "Continue the selected text naturally with a few helpful sentences."
        case .ask:
            return "Answer the user's question using the note context."
        }
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
