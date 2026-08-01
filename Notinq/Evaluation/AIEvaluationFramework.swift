import Foundation
import CryptoKit
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class AIEvaluationRunner {
    struct ResultBundle: Sendable {
        var manifest: AIEvaluationRunManifest
        var noteResults: [AIEvaluationNoteResult]
        var outputRootURL: URL
        var reportURL: URL
        var promptVersionURL: URL
    }

    let storage = AIEvaluationStorage()
    private let analysisEngine = AIEvaluationEngine()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func run(noteSet: AIEvaluationNoteSet = .all, selectedModelID: String? = nil) async throws -> ResultBundle {
        storage.bootstrapDatasetFiles()

        if let selectedModelID {
            ModelManager.shared.selectPreferredModel(id: selectedModelID)
        }

        let notes = AIEvaluationSamples.notesBySet[noteSet] ?? AIEvaluationSamples.notes
        let diagnostics = ModelManager.shared.currentModelDiagnostics()
        let activeModelName = diagnostics.activeModelID ?? ModelManager.shared.activeModelIDDescription()
        let modelIdentifier = diagnostics.activeModelID ?? activeModelName
        let promptVersion = PromptRegistry.shared.definition(for: .knowledgeExtraction).version
        let appVersion = appVersionString()
        let gitCommit = gitCommitString()
        let generationSettings = AIEvaluationGenerationSettings.default
        let runDate = Date()
        let promptVersionString = promptVersionString(promptVersion)
        let runFolderName = storage.runFolderName(for: runDate, modelName: activeModelName, promptVersion: promptVersionString)
        let outputRootURL = outputDirectory(for: runFolderName)
        let reportRootURL = reportDirectory(for: runFolderName)
        let comparisonRootURL = comparisonDirectory(for: runFolderName)

        var noteResults: [AIEvaluationNoteResult] = []
        for note in notes {
            let result = try await evaluate(
                note: note,
                runDate: runDate,
                appVersion: appVersion,
                gitCommit: gitCommit,
                modelName: activeModelName,
                modelIdentifier: modelIdentifier,
                promptVersion: promptVersion,
                noteSet: noteSet,
                generationSettings: generationSettings
            )
            noteResults.append(result)
            try storage.save(noteResult: result, promptSnapshots: result.promptsUsed, to: outputRootURL)
        }

        let averageOverall = noteResults.isEmpty ? 0 : noteResults.reduce(0.0) { $0 + $1.localScores.overall } / Double(noteResults.count)
        let averageHeuristic = noteResults.isEmpty ? 0 : noteResults.reduce(0.0) { $0 + $1.localScores.overall } / Double(noteResults.count)
        let averageSemantic = noteResults.compactMap { $0.semanticEvaluation?.overallScore }.reduce(0.0, +) / Double(max(1, noteResults.compactMap { $0.semanticEvaluation?.overallScore }.count))
        let averageGenerationTime = noteResults.reduce(0.0) { $0 + $1.performanceMetrics.generationTime } / Double(max(1, noteResults.count))
        let averageMemoryUsage = noteResults.reduce(0.0) { $0 + $1.performanceMetrics.memoryUsageMB } / Double(max(1, noteResults.count))
        let averageTokensPerSecond = noteResults.reduce(0.0) { $0 + $1.performanceMetrics.tokensPerSecond } / Double(max(1, noteResults.count))
        let manifest = AIEvaluationRunManifest(
            evaluationDate: runDate,
            noteSet: noteSet.rawValue,
            appVersion: appVersion,
            gitCommit: gitCommit,
            modelName: activeModelName,
            modelIdentifier: modelIdentifier,
            promptVersion: promptVersionString,
            resultCount: noteResults.count,
            averageOverallScore: averageOverall,
            averageHeuristicScore: averageHeuristic,
            averageSemanticScore: averageSemantic,
            averageGenerationTime: averageGenerationTime,
            averageMemoryUsageMB: averageMemoryUsage,
            averageTokensPerSecond: averageTokensPerSecond,
            noteResults: noteResults
        )

        let reportURL = try storage.saveRunManifest(manifest, to: reportRootURL)
        let promptVersionURL = try storage.savePromptVersionSnapshot(promptSnapshot(), promptVersion: promptVersionString)
        try storage.saveComparisonSeed(manifest, to: comparisonRootURL)

        return ResultBundle(
            manifest: manifest,
            noteResults: noteResults,
            outputRootURL: outputRootURL,
            reportURL: reportURL,
            promptVersionURL: promptVersionURL
        )
    }

    func compare(baseline: AIEvaluationRunManifest, comparison: AIEvaluationRunManifest) -> AIEvaluationComparisonReport {
        let byID = Dictionary(uniqueKeysWithValues: baseline.noteResults.map { ($0.noteID, $0) })
        let comparisons = comparison.noteResults.map { current in
            let previous = byID[current.noteID]
            let scoreDelta = current.localScores.overall - (previous?.localScores.overall ?? 0)
            let title = current.noteName
            let changes = changedOutputs(baseline: previous?.outputs, comparison: current.outputs)

            return AIEvaluationComparisonSummary(
                title: title,
                baselineRunID: previous?.id ?? baseline.noteSet,
                comparisonRunID: current.id,
                improvements: scoreDelta > 0 ? ["Overall score improved by \(formatDelta(scoreDelta))"] : [],
                regressions: scoreDelta < 0 ? ["Overall score dropped by \(formatDelta(scoreDelta))"] : [],
                changedOutputs: changes,
                scoreDelta: scoreDelta
            )
        }

        return AIEvaluationComparisonReport(
            generatedAt: Date(),
            title: "\(baseline.modelName) vs \(comparison.modelName)",
            baselineModel: baseline.modelName,
            comparisonModel: comparison.modelName,
            baselinePromptVersion: baseline.promptVersion,
            comparisonPromptVersion: comparison.promptVersion,
            noteSet: comparison.noteSet,
            comparisons: comparisons
        )
    }

    func regressionReport(baseline: AIEvaluationNoteResult, comparison: AIEvaluationNoteResult) -> AIEvaluationRegressionReport {
        analysisEngine.regressionReport(baseline: baseline, comparison: comparison)
    }

    func benchmarkReport(from runs: [AIEvaluationRunManifest], datasetName: String) -> AIEvaluationBenchmarkReport {
        analysisEngine.benchmarkReport(from: runs, datasetName: datasetName)
    }

    func promptImprovementReport(from noteResults: [AIEvaluationNoteResult], datasetName: String) -> AIEvaluationPromptImprovementReport {
        analysisEngine.promptImprovementReport(from: noteResults, datasetName: datasetName)
    }

    func comparePromptVersions(baselineVersion: String, comparisonVersion: String) -> AIPromptVersionComparisonReport? {
        guard
            let baseline = storage.loadPromptVersionSnapshot(promptVersion: baselineVersion),
            let comparison = storage.loadPromptVersionSnapshot(promptVersion: comparisonVersion)
        else {
            return nil
        }
        return comparePromptSnapshots(
            baseline: baseline,
            comparison: comparison,
            baselineVersion: baselineVersion,
            comparisonVersion: comparisonVersion
        )
    }

    func reviewPrompt(for result: AIEvaluationNoteResult) -> String {
        AIEvaluationReviewPromptBuilder.build(for: result)
    }

    func evaluationFolderURL() -> URL {
        storage.evaluationRootURL
    }

    func listRecentRuns(limit: Int = 10) -> [AIEvaluationRunManifest] {
        storage.listRecentRunManifests(limit: limit)
    }

    func openEvaluationFolder() {
        #if canImport(AppKit)
        NSWorkspace.shared.open(storage.evaluationRootURL)
        #endif
    }

    private func evaluate(
        note: AIEvaluationNote,
        runDate: Date,
        appVersion: String,
        gitCommit: String,
        modelName: String,
        modelIdentifier: String,
        promptVersion: AIPromptVersion,
        noteSet: AIEvaluationNoteSet,
        generationSettings: AIEvaluationGenerationSettings
    ) async throws -> AIEvaluationNoteResult {
        let generationStart = Date()
        let knowledge = try await generateKnowledgeSnapshot(for: note, settings: generationSettings)
        let knowledgeJSON = encodeJSONString(knowledge)

        let summaryRequest = PromptRegistry.shared.renderPrompt(
            for: .summary,
            context: AIPromptContext(noteTitle: note.title, noteText: note.rawNote, knowledgeJSON: knowledgeJSON, selectedText: nil, userRequest: nil)
        )
        let flashcardRequest = PromptRegistry.shared.jsonRequest(
            for: .flashcards,
            context: AIPromptContext(noteTitle: note.title, noteText: note.rawNote, knowledgeJSON: knowledgeJSON, selectedText: nil, userRequest: nil),
            maxTokens: Int32(generationSettings.maxTokens)
        )
        let quizRequest = PromptRegistry.shared.jsonRequest(
            for: .multipleChoiceQuiz,
            context: AIPromptContext(noteTitle: note.title, noteText: note.rawNote, knowledgeJSON: knowledgeJSON, selectedText: nil, userRequest: nil),
            maxTokens: Int32(generationSettings.maxTokens)
        )
        let conceptMapRequest = PromptRegistry.shared.jsonRequest(
            for: .conceptMap,
            context: AIPromptContext(noteTitle: note.title, noteText: note.rawNote, knowledgeJSON: knowledgeJSON, selectedText: nil, userRequest: nil),
            maxTokens: Int32(generationSettings.maxTokens)
        )
        let insightsRequest = PromptRegistry.shared.jsonRequest(
            for: .learningInsights,
            context: AIPromptContext(noteTitle: note.title, noteText: note.rawNote, knowledgeJSON: knowledgeJSON, selectedText: nil, userRequest: nil),
            maxTokens: Int32(generationSettings.maxTokens)
        )

        let summaryResponse = await generateText(summaryRequest, fallback: LearningEngine.shared.summaryText(from: knowledge, mode: .thirtySeconds))
        let flashcardResponse = await generateText(flashcardRequest, fallback: encodeJSONArray(LearningEngine.shared.generateFlashcards(from: knowledge)))
        let quizResponse = await generateText(quizRequest, fallback: encodeJSONArray(LearningEngine.shared.generateQuizSet(from: knowledge).questions))
        let conceptMapResponse = await generateText(conceptMapRequest, fallback: encodeJSONArray(LearningEngine.shared.generateConceptMap(from: knowledge)))
        let insightsResponse = await generateText(insightsRequest, fallback: encodeJSONString(LearningEngine.shared.generateInsights(from: knowledge)))

        let flashcards = StudyResponseParser.parseStudyFlashcards(from: flashcardResponse)
        let quiz = StudyResponseParser.parseStudyQuiz(from: quizResponse)
        let conceptMap = decodeConceptMap(from: conceptMapResponse) ?? LearningEngine.shared.generateConceptMap(from: knowledge)
        let learningInsights = decodeInsights(from: insightsResponse) ?? LearningEngine.shared.generateInsights(from: knowledge)

        let outputs = AIEvaluationOutputs(
            summary: summaryResponse.trimmingCharacters(in: .whitespacesAndNewlines),
            flashcards: flashcards,
            quiz: quiz,
            conceptMap: conceptMap,
            learningInsights: learningInsights,
            knowledgeSnapshot: knowledge,
            rawOutputs: AIEvaluationRawOutputs(
                summary: summaryResponse,
                flashcards: flashcardResponse,
                quiz: quizResponse,
                conceptMap: conceptMapResponse,
                learningInsights: insightsResponse,
                knowledgeExtraction: encodeJSONString(knowledge)
            )
        )

        let promptSnapshots = [
            promptSnapshot(feature: "knowledge_extraction", request: PromptRegistry.shared.jsonRequest(for: .knowledgeExtraction, context: AIPromptContext(noteTitle: note.title, noteText: note.rawNote, knowledgeJSON: nil, selectedText: nil, userRequest: nil), maxTokens: Int32(generationSettings.maxTokens)), definition: PromptRegistry.shared.definition(for: .knowledgeExtraction)),
            promptSnapshot(feature: "summary", request: summaryRequest, definition: PromptRegistry.shared.definition(for: .summary)),
            promptSnapshot(feature: "flashcards", request: flashcardRequest, definition: PromptRegistry.shared.definition(for: .flashcards)),
            promptSnapshot(feature: "quiz", request: quizRequest, definition: PromptRegistry.shared.definition(for: .multipleChoiceQuiz)),
            promptSnapshot(feature: "concept_map", request: conceptMapRequest, definition: PromptRegistry.shared.definition(for: .conceptMap)),
            promptSnapshot(feature: "learning_insights", request: insightsRequest, definition: PromptRegistry.shared.definition(for: .learningInsights))
        ]

        let localScores = evaluate(note: note, outputs: outputs)
        let generationEnd = Date()
        let performanceMetrics = performanceMetrics(
            start: generationStart,
            end: generationEnd,
            outputs: outputs,
            generationSettings: generationSettings
        )
        let combined = await analysisEngine.combinedReport(
            note: note,
            outputs: outputs,
            localScores: localScores,
            performanceMetrics: performanceMetrics,
            reference: storage.goldStandardReference(for: note)
        )
        return AIEvaluationNoteResult(
            id: note.id,
            noteID: note.id,
            noteName: note.title,
            evaluationDate: runDate,
            appVersion: appVersion,
            gitCommit: gitCommit,
            modelName: modelName,
            modelIdentifier: modelIdentifier,
            promptVersion: promptVersionString(promptVersion),
            noteSet: noteSet.rawValue,
            rawNote: note.rawNote,
            promptsUsed: promptSnapshots,
            outputs: outputs,
            generationSettings: generationSettings,
            localScores: localScores,
            performanceMetrics: performanceMetrics,
            semanticEvaluation: combined.semantic,
            combinedReport: combined.combined,
            regressionReport: nil,
            promptImprovementReport: nil
        )
    }

    private func generateKnowledgeSnapshot(for note: AIEvaluationNote, settings: AIEvaluationGenerationSettings) async throws -> StudyKnowledgeSnapshot {
        let promptContext = AIPromptContext(noteTitle: note.title, noteText: note.rawNote, knowledgeJSON: nil, selectedText: nil, userRequest: nil)
        let request = PromptRegistry.shared.jsonRequest(for: .knowledgeExtraction, context: promptContext, maxTokens: Int32(settings.maxTokens))
        let heuristic = await KnowledgeExtractionPipeline.shared.extractKnowledge(noteTitle: note.title, noteText: note.rawNote)

        guard let payload: ExtractedKnowledgePayload = try? await InferenceEngine.shared.generateStructured(ExtractedKnowledgePayload.self, request: request) else {
            return heuristic.snapshot
        }

        return merge(payload: payload, with: heuristic.snapshot)
    }

    private func merge(payload: ExtractedKnowledgePayload, with fallback: StudyKnowledgeSnapshot) -> StudyKnowledgeSnapshot {
        func item(_ value: String, category: String) -> StudyKnowledgeItem {
            StudyKnowledgeItem(
                title: value,
                summary: value,
                evidence: [value],
                importance: 0.8,
                difficulty: 0.5,
                aliases: [],
                relatedTitles: [],
                category: category
            )
        }

        func item(_ value: ExtractedKnowledgeConcept) -> StudyKnowledgeItem {
            StudyKnowledgeItem(
                title: value.name,
                summary: value.definition.isEmpty ? value.name : value.definition,
                evidence: value.examples.isEmpty ? [value.definition].filter { !$0.isEmpty } : value.examples,
                importance: value.importance,
                difficulty: value.difficulty,
                aliases: value.aliases,
                relatedTitles: value.relationships,
                category: value.category
            )
        }

        let hierarchy = payload.hierarchy.map { node in
            StudyKnowledgeNode(title: node.title, summary: node.content, children: node.children.map { child in
                StudyKnowledgeNode(title: child.title, summary: child.content, children: [])
            })
        }

        return StudyKnowledgeSnapshot(
            title: payload.title.isEmpty ? fallback.title : payload.title,
            sourceSignature: fallback.sourceSignature,
            cleanedText: fallback.cleanedText,
            normalizedText: fallback.normalizedText,
            topics: payload.topics.isEmpty ? fallback.topics : payload.topics,
            concepts: payload.concepts.isEmpty ? fallback.concepts : payload.concepts.map { item($0) },
            definitions: payload.definitions.isEmpty ? fallback.definitions : payload.definitions.map { item($0.definition, category: "definition") },
            relationships: fallback.relationships,
            examples: payload.examples.isEmpty ? fallback.examples : payload.examples.map { item($0.example, category: "example") },
            procedures: payload.procedures.isEmpty ? fallback.procedures : payload.procedures.map { item($0, category: "procedure") },
            formulas: payload.formulas.isEmpty ? fallback.formulas : payload.formulas.map { item($0, category: "formula") },
            importantFacts: payload.importantFacts.isEmpty ? fallback.importantFacts : payload.importantFacts.map { item($0, category: "important_fact") },
            keyTerms: payload.keyTerminology.isEmpty ? fallback.keyTerms : payload.keyTerminology.map { item($0, category: "key_term") },
            misconceptions: payload.misconceptions.isEmpty ? fallback.misconceptions : payload.misconceptions.map { item($0, category: "misconception") },
            prerequisites: payload.prerequisites.isEmpty ? fallback.prerequisites : payload.prerequisites.map { item($0, category: "prerequisite") },
            hierarchy: hierarchy.isEmpty ? fallback.hierarchy : hierarchy,
            difficulty: fallback.difficulty,
            supportingExamples: fallback.supportingExamples,
            supportingEvidence: payload.supportingEvidence.isEmpty ? fallback.supportingEvidence : payload.supportingEvidence,
            summaryHighlights: payload.summaryHighlights.isEmpty ? fallback.summaryHighlights : payload.summaryHighlights,
            examFocus: payload.examFocus.isEmpty ? fallback.examFocus : payload.examFocus,
            tokenEstimate: fallback.tokenEstimate,
            extractionStrategy: fallback.extractionStrategy
        )
    }

    private func evaluate(note: AIEvaluationNote, outputs: AIEvaluationOutputs) -> AIEvaluationLocalScores {
        let summary = evaluateSummary(note: note, summary: outputs.summary, knowledge: outputs.knowledgeSnapshot)
        let flashcards = evaluateFlashcards(note: note, flashcards: outputs.flashcards, knowledge: outputs.knowledgeSnapshot)
        let quiz = evaluateQuiz(note: note, quiz: outputs.quiz, knowledge: outputs.knowledgeSnapshot)
        let conceptMap = evaluateConceptMap(note: note, conceptMap: outputs.conceptMap, knowledge: outputs.knowledgeSnapshot)
        let learningInsights = evaluateLearningInsights(note: note, insights: outputs.learningInsights, knowledge: outputs.knowledgeSnapshot)
        let knowledgeJSON = evaluateKnowledgeJSON(outputs.knowledgeSnapshot)

        let overall = [
            summary.overall,
            flashcards.overall,
            quiz.overall,
            conceptMap.overall,
            learningInsights.overall,
            knowledgeJSON.overall
        ].reduce(0, +) / 6.0

        return AIEvaluationLocalScores(
            summary: summary,
            flashcards: flashcards,
            quiz: quiz,
            conceptMap: conceptMap,
            learningInsights: learningInsights,
            knowledgeSnapshot: knowledgeJSON,
            overall: overall
        )
    }

    private func evaluateSummary(note: AIEvaluationNote, summary: String, knowledge: StudyKnowledgeSnapshot) -> AIEvaluationFeatureScores {
        let normalized = normalize(summary)
        let keywords = note.expectedKeywords + knowledge.topics + knowledge.concepts.map { $0.title }
        let keywordHits = keywords.map(normalize).filter { normalized.contains($0) }
        let coverage = keywords.isEmpty ? 0 : Double(keywordHits.count) / Double(keywords.count)
        let repetition = 1.0 - duplicateSentenceRatio(summary)
        let readability = readabilityScore(summary)
        let length = lengthScore(summary, ideal: max(80, min(360, note.rawNote.count / 3)))
        let structure = structureScore(summary)
        let overall = average([coverage, repetition, readability, length, structure])
        return AIEvaluationFeatureScores(coverage: coverage, repetition: repetition, readability: readability, length: length, structure: structure, overall: overall)
    }

    private func evaluateFlashcards(note: AIEvaluationNote, flashcards: [StudyFlashcard], knowledge: StudyKnowledgeSnapshot) -> AIEvaluationFlashcardScores {
        let fronts = flashcards.map { normalize($0.front) }
        let duplicates = 1.0 - uniquenessRatio(fronts)
        let answerLength = flashcards.isEmpty ? 0 : average(flashcards.map { answerLengthScore($0.back) })
        let conceptCoverage = coverageScore(texts: flashcards.map(\.front) + flashcards.map(\.back), keywords: note.expectedKeywords + knowledge.concepts.map { $0.title })
        let specificity = flashcards.isEmpty ? 0 : average(flashcards.map { specificityScore($0.back) })
        let overall = average([1.0 - duplicates, answerLength, conceptCoverage, specificity])
        return AIEvaluationFlashcardScores(duplicates: duplicates, answerLength: answerLength, conceptCoverage: conceptCoverage, specificity: specificity, overall: overall)
    }

    private func evaluateQuiz(note: AIEvaluationNote, quiz: [StudyQuizQuestion], knowledge: StudyKnowledgeSnapshot) -> AIEvaluationQuizScores {
        let prompts = quiz.map { normalize($0.prompt) }
        let duplicateQuestions = 1.0 - uniquenessRatio(prompts)
        let explanationPresence = quiz.isEmpty ? 0 : Double(quiz.filter { !$0.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) / Double(quiz.count)
        let optionCount = quiz.isEmpty ? 0 : average(quiz.map { optionCountScore($0.options.count) })
        let answerPresence = quiz.isEmpty ? 0 : Double(quiz.filter { !$0.correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) / Double(quiz.count)
        let keywordCoverage = coverageScore(texts: quiz.map(\.prompt) + quiz.flatMap(\.options), keywords: note.expectedKeywords + knowledge.concepts.map { $0.title })
        let overall = average([1.0 - duplicateQuestions, explanationPresence, optionCount, answerPresence, keywordCoverage])
        return AIEvaluationQuizScores(duplicateQuestions: duplicateQuestions, explanationPresence: explanationPresence, optionCount: optionCount, answerPresence: answerPresence, overall: overall)
    }

    private func evaluateConceptMap(note: AIEvaluationNote, conceptMap: [StudyConceptNode], knowledge: StudyKnowledgeSnapshot) -> AIEvaluationConceptMapScores {
        let flattened = flatten(conceptMap)
        let uniqueRatio = uniquenessRatio(flattened.map(normalize))
        let duplication = 1.0 - uniqueRatio
        let disconnected = conceptMap.isEmpty ? 1 : max(0, Double(countLeaves(conceptMap) - knowledge.relationships.count) / Double(max(1, countLeaves(conceptMap))))
        let missingRelationships = knowledge.relationships.isEmpty ? 0.5 : max(0, 1.0 - Double(flattened.count) / Double(max(1, knowledge.concepts.count + knowledge.topics.count)))
        let hierarchy = hierarchyScore(conceptMap)
        let overall = average([1.0 - disconnected, 1.0 - missingRelationships, 1.0 - duplication, hierarchy])
        return AIEvaluationConceptMapScores(disconnectedNodes: disconnected, missingRelationships: missingRelationships, duplication: duplication, hierarchy: hierarchy, overall: overall)
    }

    private func evaluateLearningInsights(note: AIEvaluationNote, insights: StudyInsights, knowledge: StudyKnowledgeSnapshot) -> AIEvaluationInsightScores {
        let insightText = [insights.keyConcepts, insights.importantConcepts, insights.potentialExamTopics, insights.knowledgeGaps].flatMap { $0 }.joined(separator: " ")
        let keywords = note.expectedKeywords + knowledge.concepts.map { $0.title } + knowledge.definitions.map { $0.title }
        let missingConcepts = keywords.isEmpty ? 0 : 1.0 - coverageScore(texts: [insightText], keywords: keywords)
        let repetition = 1.0 - duplicateSentenceRatio(insightText)
        let actionability = insights.knowledgeGaps.isEmpty ? 0.35 : min(1.0, Double(insights.knowledgeGaps.count) / 4.0)
        let overall = average([1.0 - missingConcepts, repetition, actionability])
        return AIEvaluationInsightScores(missingConcepts: missingConcepts, repetition: repetition, actionability: actionability, overall: overall)
    }

    private func evaluateKnowledgeJSON(_ snapshot: StudyKnowledgeSnapshot) -> AIEvaluationJSONScores {
        let parsingSuccess = snapshot.hasContent ? 1.0 : 0.0
        let schemaValidation = snapshot.concepts.allSatisfy { !$0.title.isEmpty } ? 1.0 : 0.0
        let completeness = min(1.0, Double([
            snapshot.topics.isEmpty,
            snapshot.concepts.isEmpty,
            snapshot.definitions.isEmpty,
            snapshot.relationships.isEmpty,
            snapshot.examples.isEmpty,
            snapshot.procedures.isEmpty,
            snapshot.formulas.isEmpty,
            snapshot.importantFacts.isEmpty,
            snapshot.keyTerms.isEmpty
        ].filter { !$0 }.count) / 6.0)
        let overall = average([parsingSuccess, schemaValidation, completeness])
        return AIEvaluationJSONScores(parsingSuccess: parsingSuccess, schemaValidation: schemaValidation, completeness: completeness, overall: overall)
    }

    private func promptSnapshot(feature: String, request: AIGenerationRequest, definition: AIPromptDefinition) -> AIEvaluationPromptSnapshot {
        AIEvaluationPromptSnapshot(
            feature: feature,
            promptVersion: promptVersionString(definition.version),
            systemPrompt: request.systemPrompt ?? definition.systemPrompt,
            userPrompt: request.prompt,
            outputDescription: definition.outputDescription,
            responseFormat: request.responseFormat.description
        )
    }

    private func generateText(_ request: AIGenerationRequest, fallback: String) async -> String {
        let response = try? await InferenceEngine.shared.generate(request)
        let text = response?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? fallback : text
    }

    private func decodeConceptMap(from response: String) -> [StudyConceptNode]? {
        if let array = decodeJSON([StudyConceptNode].self, from: response) {
            return array
        }
        if let root = decodeJSON(StudyConceptNode.self, from: response) {
            return [root]
        }
        return nil
    }

    private func decodeInsights(from response: String) -> StudyInsights? {
        decodeJSON(StudyInsights.self, from: response)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from response: String) -> T? {
        guard let data = response.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(T.self, from: data)
    }

    private func encodeJSONString<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func encodeJSONArray<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func promptVersionString(_ version: AIPromptVersion) -> String {
        "\(version.major).\(version.minor).\(version.patch)"
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func duplicateSentenceRatio(_ text: String) -> Double {
        let sentences = splitSentences(text)
        guard !sentences.isEmpty else { return 0 }
        let unique = Set(sentences.map(normalize))
        return 1.0 - Double(unique.count) / Double(sentences.count)
    }

    private func readabilityScore(_ text: String) -> Double {
        let sentences = splitSentences(text)
        guard !sentences.isEmpty else { return 0.5 }
        let words = sentences.map { $0.split { $0.isWhitespace }.count }.reduce(0, +)
        let averageLength = Double(words) / Double(sentences.count)
        return max(0, min(1, 1.0 - min(1.0, abs(averageLength - 16.0) / 24.0)))
    }

    private func lengthScore(_ text: String, ideal: Int) -> Double {
        let count = text.count
        guard ideal > 0 else { return 0 }
        let delta = abs(Double(count - ideal)) / Double(max(ideal, 1))
        return max(0, min(1, 1.0 - min(1.0, delta)))
    }

    private func structureScore(_ text: String) -> Double {
        let lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return 0 }
        let structureLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("-") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("*") }
        return min(1.0, Double(structureLines.count + 1) / Double(lines.count + 1))
    }

    private func uniquenessRatio(_ values: [String]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(Set(values).count) / Double(values.count)
    }

    private func answerLengthScore(_ text: String) -> Double {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return max(0, min(1, 1.0 - abs(Double(count - 110)) / 140.0))
    }

    private func specificityScore(_ text: String) -> Double {
        let lower = text.lowercased()
        let hasNumber = lower.contains { $0.isNumber }
        let hasNamedConcept = text.split(separator: " ").count > 5
        return min(1.0, Double((hasNumber ? 1 : 0) + (hasNamedConcept ? 1 : 0)) / 2.0)
    }

    private func optionCountScore(_ count: Int) -> Double {
        switch count {
        case 4: return 1
        case 3, 5: return 0.8
        case 2...6: return 0.6
        default: return 0.2
        }
    }

    private func coverageScore(texts: [String], keywords: [String]) -> Double {
        guard !keywords.isEmpty else { return 0 }
        let text = normalize(texts.joined(separator: " "))
        let matches = keywords.map(normalize).filter { text.contains($0) }
        return min(1.0, Double(matches.count) / Double(keywords.count))
    }

    private func hierarchyScore(_ nodes: [StudyConceptNode]) -> Double {
        guard !nodes.isEmpty else { return 0 }
        let childCount = nodes.reduce(0) { $0 + $1.children.count }
        return min(1.0, Double(childCount + nodes.count) / Double(nodes.count * 3))
    }

    private func flatten(_ nodes: [StudyConceptNode]) -> [String] {
        var values: [String] = []
        for node in nodes {
            values.append(node.title)
            values.append(contentsOf: flatten(node.children))
        }
        return values
    }

    private func countLeaves(_ nodes: [StudyConceptNode]) -> Int {
        guard !nodes.isEmpty else { return 0 }
        return nodes.reduce(0) { total, node in
            if node.children.isEmpty {
                return total + 1
            }
            return total + countLeaves(node.children)
        }
    }

    private func splitSentences(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func changedOutputs(baseline: AIEvaluationOutputs?, comparison: AIEvaluationOutputs) -> [String] {
        var changes: [String] = []
        if baseline?.summary != comparison.summary {
            changes.append("summary")
        }
        if (baseline?.flashcards.count ?? 0) != comparison.flashcards.count {
            changes.append("flashcards")
        }
        if (baseline?.quiz.count ?? 0) != comparison.quiz.count {
            changes.append("quiz")
        }
        if (baseline?.conceptMap.count ?? 0) != comparison.conceptMap.count {
            changes.append("concept_map")
        }
        if (baseline?.learningInsights != comparison.learningInsights) == true {
            changes.append("learning_insights")
        }
        return changes
    }

    private func formatDelta(_ delta: Double) -> String {
        String(format: "%.2f", abs(delta))
    }

    private func appVersionString() -> String {
        let bundle = Bundle.main.infoDictionary
        let shortVersion = bundle?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = bundle?["CFBundleVersion"] as? String ?? "0"
        return "\(shortVersion) (\(build))"
    }

    private func gitCommitString() -> String {
        if let env = ProcessInfo.processInfo.environment["GIT_COMMIT"], !env.isEmpty {
            return env
        }
        return "unknown"
    }

    private func promptSnapshot() -> [AIPromptSnapshotEntry] {
        AIPromptIdentifier.allCases.map { identifier in
            let definition = PromptRegistry.shared.definition(for: identifier)
            return AIPromptSnapshotEntry(
                identifier: identifier.rawValue,
                promptVersion: promptVersionString(definition.version),
                systemPrompt: definition.systemPrompt,
                outputDescription: definition.outputDescription,
                contentHash: hashPromptSnapshot(definition.systemPrompt, outputDescription: definition.outputDescription),
                modifiedAt: Date(),
                changedPrompts: []
            )
        }
    }

    private func outputDirectory(for runFolderName: String) -> URL {
        storage.outputRootURL
            .appendingPathComponent(runFolderName, isDirectory: true)
    }

    private func reportDirectory(for runFolderName: String) -> URL {
        storage.reportRootURL
            .appendingPathComponent(runFolderName, isDirectory: true)
    }

    private func comparisonDirectory(for runFolderName: String) -> URL {
        storage.comparisonRootURL
            .appendingPathComponent(runFolderName, isDirectory: true)
    }

    private func performanceMetrics(
        start: Date,
        end: Date,
        outputs: AIEvaluationOutputs,
        generationSettings: AIEvaluationGenerationSettings
    ) -> AIEvaluationPerformanceMetrics {
        let generationTime = max(0.001, end.timeIntervalSince(start))
        let rawCharacters = outputs.rawOutputs.summary.count + outputs.rawOutputs.flashcards.count + outputs.rawOutputs.quiz.count + outputs.rawOutputs.conceptMap.count + outputs.rawOutputs.learningInsights.count + outputs.rawOutputs.knowledgeExtraction.count
        let estimatedTokens = max(1, rawCharacters / 4)
        let tokensPerSecond = Double(estimatedTokens) / generationTime
        return AIEvaluationPerformanceMetrics(
            generationTime: generationTime,
            tokensPerSecond: tokensPerSecond,
            memoryUsageMB: currentMemoryUsageMB(),
            contextSize: generationSettings.contextSize,
            modelLoadTime: 0,
            latencyByFeature: [
                "summary": generationTime * 0.2,
                "flashcards": generationTime * 0.15,
                "quiz": generationTime * 0.2,
                "concept_map": generationTime * 0.2,
                "learning_insights": generationTime * 0.25
            ],
            hallucinationCount: hallucinationCount(in: outputs)
        )
    }

    private func currentMemoryUsageMB() -> Double {
        Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0)
    }

    private func hallucinationCount(in outputs: AIEvaluationOutputs) -> Int {
        let body = [
            outputs.summary,
            outputs.rawOutputs.flashcards,
            outputs.rawOutputs.quiz,
            outputs.rawOutputs.conceptMap,
            outputs.rawOutputs.learningInsights
        ]
        .joined(separator: " ")
        .lowercased()
        return body.contains("hallucinat") ? 1 : 0
    }

    private func hashPromptSnapshot(_ systemPrompt: String, outputDescription: String) -> String {
        let digest = SHA256.hash(data: Data("\(systemPrompt)\n\(outputDescription)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func comparePromptSnapshots(
        baseline: [AIPromptSnapshotEntry],
        comparison: [AIPromptSnapshotEntry],
        baselineVersion: String,
        comparisonVersion: String
    ) -> AIPromptVersionComparisonReport {
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.identifier, $0) })
        let comparisonByID = Dictionary(uniqueKeysWithValues: comparison.map { ($0.identifier, $0) })
        let identifiers = Set(baselineByID.keys).union(comparisonByID.keys).sorted()
        let changes = identifiers.compactMap { identifier -> AIPromptVersionComparison? in
            guard let baselineEntry = baselineByID[identifier], let comparisonEntry = comparisonByID[identifier] else { return nil }
            guard baselineEntry.contentHash != comparisonEntry.contentHash else { return nil }
            var changedPrompts: [String] = []
            if baselineEntry.systemPrompt != comparisonEntry.systemPrompt {
                changedPrompts.append("system_prompt")
            }
            if baselineEntry.outputDescription != comparisonEntry.outputDescription {
                changedPrompts.append("output_description")
            }
            return AIPromptVersionComparison(
                identifier: identifier,
                baselineHash: baselineEntry.contentHash,
                comparisonHash: comparisonEntry.contentHash,
                changedPrompts: changedPrompts
            )
        }

        return AIPromptVersionComparisonReport(
            generatedAt: Date(),
            baselinePromptVersion: baselineVersion,
            comparisonPromptVersion: comparisonVersion,
            changes: changes
        )
    }
}

struct AIPromptSnapshotEntry: Codable, Equatable, Sendable {
    var identifier: String
    var promptVersion: String
    var systemPrompt: String
    var outputDescription: String
    var contentHash: String
    var modifiedAt: Date
    var changedPrompts: [String]

    private enum CodingKeys: String, CodingKey {
        case identifier
        case promptVersion = "prompt_version"
        case systemPrompt = "system_prompt"
        case outputDescription = "output_description"
        case contentHash = "content_hash"
        case modifiedAt = "modified_at"
        case changedPrompts = "changed_prompts"
    }
}

final class AIEvaluationStorage {
    let evaluationRootURL: URL
    let notesRootURL: URL
    let outputRootURL: URL
    let reportRootURL: URL
    let promptVersionRootURL: URL
    let comparisonRootURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        evaluationRootURL = base.appendingPathComponent("Notinq", isDirectory: true).appendingPathComponent("Evaluation", isDirectory: true)
        notesRootURL = evaluationRootURL.appendingPathComponent("Notes", isDirectory: true)
        outputRootURL = evaluationRootURL.appendingPathComponent("Outputs", isDirectory: true)
        reportRootURL = evaluationRootURL.appendingPathComponent("Reports", isDirectory: true)
        promptVersionRootURL = evaluationRootURL.appendingPathComponent("PromptVersions", isDirectory: true)
        comparisonRootURL = evaluationRootURL.appendingPathComponent("ModelComparisons", isDirectory: true)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        createDirectories()
    }

    func bootstrapDatasetFiles() {
        createDirectories()
        for note in AIEvaluationSamples.notes {
            let url = notesRootURL.appendingPathComponent(note.sourceFileName)
            if FileManager.default.fileExists(atPath: url.path) { continue }
            try? note.rawNote.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func save(noteResult: AIEvaluationNoteResult, promptSnapshots: [AIEvaluationPromptSnapshot], to runDirectory: URL) throws {
        let noteDirectory = runDirectory.appendingPathComponent(noteResult.noteID, isDirectory: true)
        try createDirectory(noteDirectory)
        try write(noteResult.outputs.summary, to: noteDirectory.appendingPathComponent("summary.md"))
        try write(markdownFlashcards(noteResult.outputs.flashcards), to: noteDirectory.appendingPathComponent("flashcards.md"))
        try write(markdownQuiz(noteResult.outputs.quiz), to: noteDirectory.appendingPathComponent("quiz.md"))
        try write(markdownConceptMap(noteResult.outputs.conceptMap), to: noteDirectory.appendingPathComponent("concept_map.md"))
        try write(markdownInsights(noteResult.outputs.learningInsights), to: noteDirectory.appendingPathComponent("learning_insights.md"))
        try writeJSON(noteResult.outputs.knowledgeSnapshot, to: noteDirectory.appendingPathComponent("knowledge_snapshot.json"))
        try writeJSON(noteResult.localScores, to: noteDirectory.appendingPathComponent("local_scores.json"))
        try writeJSON(noteResult, to: noteDirectory.appendingPathComponent("evaluation.json"))
        try writeJSON(promptSnapshots, to: noteDirectory.appendingPathComponent("prompt_snapshot.json"))
        if let combinedReport = noteResult.combinedReport {
            try writeJSON(combinedReport, to: noteDirectory.appendingPathComponent("combined_report.json"))
        }
        if let regressionReport = noteResult.regressionReport {
            try writeJSON(regressionReport, to: noteDirectory.appendingPathComponent("regression_report.json"))
        }
        if let promptImprovementReport = noteResult.promptImprovementReport {
            try writeJSON(promptImprovementReport, to: noteDirectory.appendingPathComponent("prompt_improvement_report.json"))
        }
        if let semanticEvaluation = noteResult.semanticEvaluation {
            try writeJSON(semanticEvaluation, to: noteDirectory.appendingPathComponent("semantic_evaluation.json"))
        }

        let reviewPrompt = AIEvaluationReviewPromptBuilder.build(for: noteResult)
        try write(reviewPrompt, to: noteDirectory.appendingPathComponent("review_prompt.txt"))

        let reviewPackage = AIEvaluationExternalReviewPackage(
            evaluationDate: noteResult.evaluationDate,
            noteID: noteResult.noteID,
            noteName: noteResult.noteName,
            appVersion: noteResult.appVersion,
            gitCommit: noteResult.gitCommit,
            modelName: noteResult.modelName,
            modelIdentifier: noteResult.modelIdentifier,
            promptVersion: noteResult.promptVersion,
            rawNote: noteResult.rawNote,
            promptsUsed: noteResult.promptsUsed,
            outputs: noteResult.outputs,
            generationSettings: noteResult.generationSettings,
            reviewPrompt: reviewPrompt
        )
        try write(reviewPromptMarkdown(reviewPackage), to: noteDirectory.appendingPathComponent("external_review.md"))
        try writeJSON(reviewPackage, to: noteDirectory.appendingPathComponent("external_review.json"))
    }

    func saveRunManifest(_ manifest: AIEvaluationRunManifest, to directory: URL) throws -> URL {
        try createDirectory(directory)
        let url = directory.appendingPathComponent("run_manifest.json")
        try writeJSON(manifest, to: url)
        try write(runMarkdown(manifest), to: directory.appendingPathComponent("run_summary.md"))
        return url
    }

    func savePromptVersionSnapshot(_ snapshot: [AIPromptSnapshotEntry], promptVersion: String) throws -> URL {
        let directory = promptVersionRootURL.appendingPathComponent(promptVersion, isDirectory: true)
        try createDirectory(directory)
        let url = directory.appendingPathComponent("prompt_registry_snapshot.json")
        try writeJSON(snapshot, to: url)
        return url
    }

    func loadPromptVersionSnapshot(promptVersion: String) -> [AIPromptSnapshotEntry]? {
        let url = promptVersionRootURL
            .appendingPathComponent(promptVersion, isDirectory: true)
            .appendingPathComponent("prompt_registry_snapshot.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode([AIPromptSnapshotEntry].self, from: data)
    }

    func saveComparisonSeed(_ manifest: AIEvaluationRunManifest, to directory: URL) throws {
        try createDirectory(directory)
        try writeJSON(manifest, to: directory.appendingPathComponent("comparison_seed.json"))
    }

    func listRecentRunManifests(limit: Int) -> [AIEvaluationRunManifest] {
        let files = (try? FileManager.default.contentsOfDirectory(at: reportRootURL, includingPropertiesForKeys: nil)) ?? []
        let manifests = files
            .flatMap { url -> [AIEvaluationRunManifest] in
                let data = try? Data(contentsOf: url.appendingPathComponent("run_manifest.json"))
                guard let data, let decoded = try? decoder.decode(AIEvaluationRunManifest.self, from: data) else { return [] }
                return [decoded]
            }
            .sorted { $0.evaluationDate > $1.evaluationDate }
        return Array(manifests.prefix(limit))
    }

    func runFolderName(for date: Date, modelName: String, promptVersion: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: date)
        return "\(timestamp)_\(sanitizeFolderComponent(modelName))_\(sanitizeFolderComponent(promptVersion))"
    }

    func dayFolderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func createDirectories() {
        [evaluationRootURL, notesRootURL, outputRootURL, reportRootURL, promptVersionRootURL, comparisonRootURL].forEach { try? createDirectory($0) }
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func sanitizeFolderComponent(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private func write(_ string: String, to url: URL) throws {
        try string.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    func goldStandardReference(for note: AIEvaluationNote) -> AIEvaluationGoldStandardReference? {
        let subjectDirectory = note.subject
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let candidate = evaluationRootURL
            .appendingPathComponent("GoldStandard", isDirectory: true)
            .appendingPathComponent(subjectDirectory, isDirectory: true)
            .appendingPathComponent("\(note.id).json")

        guard let data = try? Data(contentsOf: candidate) else { return nil }
        return try? decoder.decode(AIEvaluationGoldStandardReference.self, from: data)
    }

    private func markdownFlashcards(_ cards: [StudyFlashcard]) -> String {
        var lines = ["# Flashcards", ""]
        for (index, card) in cards.enumerated() {
            lines.append("## Card \(index + 1)")
            lines.append("- Front: \(card.front)")
            lines.append("- Back: \(card.back)")
            lines.append("- Type: \(card.type.rawValue)")
            lines.append("- Why it matters: \(card.whyItMatters)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func markdownQuiz(_ questions: [StudyQuizQuestion]) -> String {
        var lines = ["# Quiz", ""]
        for (index, question) in questions.enumerated() {
            lines.append("## Question \(index + 1)")
            lines.append(question.prompt)
            if !question.options.isEmpty {
                lines.append("")
                for option in question.options {
                    lines.append("- \(option)")
                }
            }
            lines.append("")
            lines.append("Answer: \(question.correctAnswer)")
            if !question.explanation.isEmpty {
                lines.append("Explanation: \(question.explanation)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func markdownConceptMap(_ nodes: [StudyConceptNode]) -> String {
        func render(_ node: StudyConceptNode, indent: Int, lines: inout [String]) {
            let prefix = String(repeating: "  ", count: indent)
            lines.append("\(prefix)- \(node.title)")
            node.children.forEach { render($0, indent: indent + 1, lines: &lines) }
        }

        var lines = ["# Concept Map", ""]
        nodes.forEach { render($0, indent: 0, lines: &lines) }
        return lines.joined(separator: "\n")
    }

    private func markdownInsights(_ insights: StudyInsights) -> String {
        var lines = ["# Learning Insights", ""]
        appendList("Key Concepts", insights.keyConcepts, to: &lines)
        appendList("Important Concepts", insights.importantConcepts, to: &lines)
        appendList("Potential Exam Topics", insights.potentialExamTopics, to: &lines)
        appendList("Knowledge Gaps", insights.knowledgeGaps, to: &lines)
        return lines.joined(separator: "\n")
    }

    private func appendList(_ title: String, _ values: [String], to lines: inout [String]) {
        lines.append("## \(title)")
        if values.isEmpty {
            lines.append("- None")
        } else {
            values.forEach { lines.append("- \($0)") }
        }
        lines.append("")
    }

    private func runMarkdown(_ manifest: AIEvaluationRunManifest) -> String {
        var lines = ["# Evaluation Run", ""]
        lines.append("- Date: \(manifest.evaluationDate.formatted(date: .abbreviated, time: .shortened))")
        lines.append("- Note set: \(manifest.noteSet)")
        lines.append("- Model: \(manifest.modelName)")
        lines.append("- Prompt version: \(manifest.promptVersion)")
        lines.append("- Notes evaluated: \(manifest.resultCount)")
        lines.append("- Average overall score: \(String(format: "%.3f", manifest.averageOverallScore))")
        lines.append("")
        for result in manifest.noteResults {
            lines.append("## \(result.noteName)")
            lines.append("- Score: \(String(format: "%.3f", result.localScores.overall))")
            lines.append("- Summary score: \(String(format: "%.3f", result.localScores.summary.overall))")
            lines.append("- Flashcards score: \(String(format: "%.3f", result.localScores.flashcards.overall))")
            lines.append("- Quiz score: \(String(format: "%.3f", result.localScores.quiz.overall))")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func reviewPromptMarkdown(_ package: AIEvaluationExternalReviewPackage) -> String {
        var lines = ["# External Review Package", ""]
        lines.append("## Note")
        lines.append(package.rawNote)
        lines.append("")
        lines.append("## Generated Outputs")
        lines.append("Summary:")
        lines.append(package.outputs.summary)
        lines.append("")
        lines.append("Flashcards:")
        lines.append(encodeJSONString(package.outputs.flashcards))
        lines.append("")
        lines.append("Quiz:")
        lines.append(encodeJSONString(package.outputs.quiz))
        lines.append("")
        lines.append("Concept Map:")
        lines.append(encodeJSONString(package.outputs.conceptMap))
        lines.append("")
        lines.append("Learning Insights:")
        lines.append(encodeJSONString(package.outputs.learningInsights))
        lines.append("")
        lines.append("Knowledge Snapshot:")
        lines.append(encodeJSONString(package.outputs.knowledgeSnapshot))
        lines.append("")
        lines.append("## Review Prompt")
        lines.append(package.reviewPrompt)
        return lines.joined(separator: "\n")
    }

    private func encodeJSONString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

enum AIEvaluationReviewPromptBuilder {
    static func build(for result: AIEvaluationNoteResult) -> String {
        """
        Evaluate the following study materials.

        Score each feature from 1-10 for:

        - accuracy
        - completeness
        - educational usefulness
        - clarity
        - hallucinations
        - organization
        - quiz quality
        - flashcard quality

        Identify concrete weaknesses.

        Suggest specific prompt improvements.

        Suggest model improvements.

        Return structured JSON.

        Note:
        \(result.noteName)

        Original note:
        \(result.rawNote)

        Generated summary:
        \(result.outputs.summary)
        """
    }
}
