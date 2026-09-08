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
        }
    }
}

final class AIService {
    static let shared = AIService()

    private let inferenceEngine = InferenceEngine.shared

    struct CitedTutorResponse {
        let response: PromptTutorResponse
        let context: KnowledgeContext

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
        completion: @escaping (String) -> Void
    ) {
        let promptContext = AIPromptContext(
            noteTitle: "",
            noteText: noteContext,
            knowledgeJSON: nil,
            selectedText: selectedText,
            userRequest: action.promptInstruction()
        )
        let request = PromptRegistry.shared.renderPrompt(for: .directEditing, context: promptContext)

        Task {
            let response = (try? await inferenceEngine.generate(request))?.text ?? "Unable to generate response."
            await MainActor.run {
                completion(response)
            }
        }
    }

    func streamFollowUp(
        noteContext: String,
        followUpTitle: String,
        blockContent: String,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        let promptContext = AIPromptContext(
            noteTitle: "",
            noteText: noteContext,
            knowledgeJSON: nil,
            selectedText: blockContent,
            userRequest: "\(followUpTitle) the following generated passage while preserving the note's context."
        )
        let request = PromptRegistry.shared.renderPrompt(for: .directEditing, context: promptContext)

        Task {
            _ = try? await inferenceEngine.stream(request, onToken: onToken)
            await MainActor.run {
                completion()
            }
        }
    }

    func chat(noteTitle: String, noteText: String, userRequest: String, completion: @escaping (String) -> Void) {
        let knowledgeContext = KnowledgeService.shared.buildContext(noteID: nil, title: noteTitle, text: noteText)
        let promptContext = AIPromptContext(
            noteTitle: noteTitle,
            noteText: noteText,
            knowledgeJSON: knowledgeContext.knowledgeJSON,
            selectedText: nil,
            userRequest: userRequest
        )
        let request = PromptRegistry.shared.renderPrompt(for: .assistantChat, context: promptContext)

        Task {
            let response = (try? await inferenceEngine.generate(request))?.text ?? "Unable to generate response."
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
                let execution = try await PromptRegistry.shared.execute(TutorPrompt.self, input: input, context: promptContext)
                await MainActor.run {
                    completion(CitedTutorResponse(response: execution.output, context: knowledgeContext))
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
                    completion(CitedTutorResponse(response: fallback, context: knowledgeContext))
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
        let knowledge = await extractStructuredKnowledge(from: structure, notebookText: notebookText)
        return LearningEngine.shared.generateStudyData(from: knowledge, existingStudyData: existingStudyData)
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
            return "Explain the selected text in plain language."
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
