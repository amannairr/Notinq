import Foundation
import CryptoKit

enum ModelMigrationEvaluationCategory: String, Codable, CaseIterable, Sendable {
    case conceptExtraction = "concept_extraction"
    case relationshipExtraction = "relationship_extraction"
    case flashcardGeneration = "flashcard_generation"
    case questionGeneration = "question_generation"
    case tutorQuestionAnswering = "tutor_question_answering"
    case retrievalGroundedAnswering = "retrieval_grounded_answering"

    var title: String {
        switch self {
        case .conceptExtraction: return "Concept Extraction"
        case .relationshipExtraction: return "Relationship Extraction"
        case .flashcardGeneration: return "Flashcard Generation"
        case .questionGeneration: return "Question Generation"
        case .tutorQuestionAnswering: return "Tutor Question Answering"
        case .retrievalGroundedAnswering: return "Retrieval-Grounded Answering"
        }
    }
}

struct ModelMigrationDatasetNote: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var subject: String
    var sourceFileName: String
    var rawNote: String
    var expectedKeywords: [String]
}

struct ModelMigrationPromptRecord: Codable, Equatable, Sendable {
    var category: String
    var noteID: String
    var noteTitle: String
    var modelID: String
    var modelName: String
    var prompt: String
    var rawResponse: String
    var parsedResponse: String
    var executionTimeSeconds: Double
    var promptTokenCount: Int
    var completionTokenCount: Int
    var parsingSucceeded: Bool
    var failure: String?
}

struct ModelMigrationCategoryResult: Codable, Equatable, Sendable {
    var category: String
    var results: [ModelMigrationPromptRecord]
}

struct ModelMigrationEvaluationBundle: Codable, Equatable, Sendable {
    var generatedAt: Date
    var datasetRoot: String
    var outputRoot: String
    var modelIDs: [String]
    var categories: [ModelMigrationCategoryResult]
    var comparisonMarkdownPath: String
}

final class ModelMigrationDatasetLoader {
    static let shared = ModelMigrationDatasetLoader()

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func datasetRootURL(override: URL? = nil) -> URL {
        if let override {
            return override
        }

        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        return cwd
            .appendingPathComponent("Notinq", isDirectory: true)
            .appendingPathComponent("Evaluation", isDirectory: true)
            .appendingPathComponent("ModelMigrationDataset", isDirectory: true)
    }

    func outputRootURL(override: URL? = nil) -> URL {
        if let override {
            return override
        }

        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        return cwd
            .appendingPathComponent("Notinq", isDirectory: true)
            .appendingPathComponent("EvaluationResults", isDirectory: true)
    }

    func loadNotes(from override: URL? = nil) -> [ModelMigrationDatasetNote] {
        let root = datasetRootURL(override: override)
        let files = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []

        let noteURLs = files.filter { $0.pathExtension.lowercased() == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        return noteURLs.compactMap { url in
            guard let rawNote = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let title = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized
            return ModelMigrationDatasetNote(
                id: stableID(for: url.lastPathComponent),
                title: title,
                subject: url.deletingPathExtension().lastPathComponent,
                sourceFileName: url.lastPathComponent,
                rawNote: rawNote,
                expectedKeywords: title
                    .split(separator: " ")
                    .map { String($0).lowercased() }
                    .filter { !$0.isEmpty }
            )
        }
    }

    func bootstrapDatasetFiles(at override: URL? = nil) throws {
        let root = datasetRootURL(override: override)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func stableID(for value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let prefix = hex.prefix(32)
        let segments = [
            prefix.prefix(8),
            prefix.dropFirst(8).prefix(4),
            prefix.dropFirst(12).prefix(4),
            prefix.dropFirst(16).prefix(4),
            prefix.dropFirst(20).prefix(12)
        ]
        return segments.map(String.init).joined(separator: "-")
    }
}

final class ModelMigrationEvaluationRunner {
    static let shared = ModelMigrationEvaluationRunner()

    private let datasetLoader: ModelMigrationDatasetLoader
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(datasetLoader: ModelMigrationDatasetLoader = .shared) {
        self.datasetLoader = datasetLoader
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func run(modelIDs: [String] = ["qwen-2-5-3b", "qwen-3-4b"], datasetRoot: URL? = nil, outputRoot: URL? = nil) async throws -> ModelMigrationEvaluationBundle {
        try datasetLoader.bootstrapDatasetFiles(at: datasetRoot)
        let notes = datasetLoader.loadNotes(from: datasetRoot)
        let resolvedDatasetRoot = datasetLoader.datasetRootURL(override: datasetRoot)
        let resolvedOutputRoot = datasetLoader.outputRootURL(override: outputRoot)

        try FileManager.default.createDirectory(at: resolvedOutputRoot, withIntermediateDirectories: true)

        var categoryResults: [ModelMigrationCategoryResult] = []
        for category in ModelMigrationEvaluationCategory.allCases {
            let records = try await evaluate(category: category, notes: notes, modelIDs: modelIDs)
            categoryResults.append(ModelMigrationCategoryResult(category: category.rawValue, results: records))
            let url = resolvedOutputRoot.appendingPathComponent("\(category.rawValue)_results.json")
            try writeJSON(ModelMigrationCategoryResult(category: category.rawValue, results: records), to: url)
        }

        let comparisonMarkdown = buildComparisonMarkdown(categories: categoryResults, modelIDs: modelIDs, datasetRoot: resolvedDatasetRoot, outputRoot: resolvedOutputRoot)
        let comparisonURL = resolvedOutputRoot.appendingPathComponent("model_comparison.md")
        try comparisonMarkdown.write(to: comparisonURL, atomically: true, encoding: .utf8)

        let bundle = ModelMigrationEvaluationBundle(
            generatedAt: Date(),
            datasetRoot: resolvedDatasetRoot.path,
            outputRoot: resolvedOutputRoot.path,
            modelIDs: modelIDs,
            categories: categoryResults,
            comparisonMarkdownPath: comparisonURL.path
        )
        try writeJSON(bundle, to: resolvedOutputRoot.appendingPathComponent("migration_bundle.json"))
        return bundle
    }

    private func evaluate(category: ModelMigrationEvaluationCategory, notes: [ModelMigrationDatasetNote], modelIDs: [String]) async throws -> [ModelMigrationPromptRecord] {
        var records: [ModelMigrationPromptRecord] = []
        for modelID in modelIDs {
            ModelManager.shared.selectPreferredModel(id: modelID)
            for note in notes {
                let record = await evaluate(category: category, note: note, modelID: modelID)
                records.append(record)
            }
        }
        return records
    }

    private func evaluate(category: ModelMigrationEvaluationCategory, note: ModelMigrationDatasetNote, modelID: String) async -> ModelMigrationPromptRecord {
        let modelName = ModelManager.shared.installedModel(for: modelID)?.displayName ?? modelID
        let start = CFAbsoluteTimeGetCurrent()
        var rawResponse = ""
        var parsedResponse = "{}"
        var parsingSucceeded = false
        var failure: String?
        var promptTokenCount = 0
        var completionTokenCount = 0

        do {
            switch category {
            case .conceptExtraction:
                let input = PromptExtractionInput(noteTitle: note.title, noteText: note.rawNote)
                let execution = try await PromptRegistry.shared.execute(KnowledgeExtractionPrompt.self, input: input, context: PromptBuildContext(noteTitle: note.title, noteText: note.rawNote))
                rawResponse = execution.rawText
                parsedResponse = encodeJSON(execution.output)
                parsingSucceeded = execution.validation.isValid
                promptTokenCount = execution.metrics.tokenUsage
                completionTokenCount = max(1, execution.rawText.split { $0.isWhitespace || $0.isNewline }.count)

            case .relationshipExtraction:
                let graph = KnowledgeGraph(noteID: UUID(uuidString: note.id) ?? UUID(), concepts: [], relationships: [], lastUpdated: Date())
                let input = PromptGraphInput(noteTitle: note.title, graph: graph)
                let execution = try await PromptRegistry.shared.execute(KnowledgeGraphExpansionPrompt.self, input: input, context: PromptBuildContext(noteTitle: note.title, noteText: note.rawNote))
                rawResponse = execution.rawText
                parsedResponse = encodeJSON(execution.output)
                parsingSucceeded = execution.validation.isValid
                promptTokenCount = execution.metrics.tokenUsage
                completionTokenCount = max(1, execution.rawText.split { $0.isWhitespace || $0.isNewline }.count)

            case .flashcardGeneration:
                let snapshot = await snapshot(for: note)
                let input = PromptStructuredKnowledgeInput(noteTitle: note.title, knowledge: snapshot)
                let execution = try await PromptRegistry.shared.execute(FlashcardsPrompt.self, input: input, context: PromptBuildContext(noteTitle: note.title, noteText: note.rawNote, structuredKnowledge: snapshot.structuredKnowledgeRepresentation(), knowledgeSnapshot: snapshot))
                rawResponse = execution.rawText
                parsedResponse = encodeJSON(execution.output)
                parsingSucceeded = execution.validation.isValid
                promptTokenCount = execution.metrics.tokenUsage
                completionTokenCount = max(1, execution.rawText.split { $0.isWhitespace || $0.isNewline }.count)

            case .questionGeneration:
                let snapshot = await snapshot(for: note)
                let input = PromptStructuredKnowledgeInput(noteTitle: note.title, knowledge: snapshot)
                let execution = try await PromptRegistry.shared.execute(QuizPrompt.self, input: input, context: PromptBuildContext(noteTitle: note.title, noteText: note.rawNote, structuredKnowledge: snapshot.structuredKnowledgeRepresentation(), knowledgeSnapshot: snapshot))
                rawResponse = execution.rawText
                parsedResponse = encodeJSON(execution.output)
                parsingSucceeded = execution.validation.isValid
                promptTokenCount = execution.metrics.tokenUsage
                completionTokenCount = max(1, execution.rawText.split { $0.isWhitespace || $0.isNewline }.count)

            case .tutorQuestionAnswering:
                let snapshot = await snapshot(for: note)
                let input = PromptTutorInput(noteTitle: note.title, knowledge: snapshot, question: tutorQuestion(for: note))
                let execution = try await PromptRegistry.shared.execute(
                    TutorPrompt.self,
                    input: input,
                    context: PromptBuildContext(
                        noteTitle: note.title,
                        noteText: note.rawNote,
                        structuredKnowledge: snapshot.structuredKnowledgeRepresentation(),
                        knowledgeSnapshot: snapshot,
                        tutorContext: TutorContext(
                            noteID: nil,
                            noteTitle: note.title,
                            focusConcepts: [],
                            evidenceSources: [],
                            citations: [],
                            evidenceSummary: ""
                        )
                    )
                )
                rawResponse = execution.rawText
                parsedResponse = encodeJSON(execution.output)
                parsingSucceeded = execution.validation.isValid
                promptTokenCount = execution.metrics.tokenUsage
                completionTokenCount = max(1, execution.rawText.split { $0.isWhitespace || $0.isNewline }.count)

            case .retrievalGroundedAnswering:
                let bundle = await citedTutorBundle(for: note)
                rawResponse = bundle.response.answer
                parsedResponse = encodeJSON(bundle.response)
                parsingSucceeded = bundle.response.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                promptTokenCount = note.rawNote.split { $0.isWhitespace || $0.isNewline }.count
                completionTokenCount = max(1, rawResponse.split { $0.isWhitespace || $0.isNewline }.count)
            }
        } catch {
            failure = error.localizedDescription
            let fallback = await fallbackResponse(for: category, note: note)
            rawResponse = fallback.rawResponse
            parsedResponse = fallback.parsedResponse
            parsingSucceeded = fallback.parsingSucceeded
            promptTokenCount = fallback.promptTokenCount
            completionTokenCount = fallback.completionTokenCount
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        return ModelMigrationPromptRecord(
            category: category.rawValue,
            noteID: note.id,
            noteTitle: note.title,
            modelID: modelID,
            modelName: modelName,
            prompt: prompt(for: category, note: note),
            rawResponse: rawResponse,
            parsedResponse: parsedResponse,
            executionTimeSeconds: elapsed,
            promptTokenCount: promptTokenCount,
            completionTokenCount: completionTokenCount,
            parsingSucceeded: parsingSucceeded,
            failure: failure
        )
    }

    private func snapshot(for note: ModelMigrationDatasetNote) async -> StudyKnowledgeSnapshot {
        await KnowledgeService.shared.extractKnowledge(noteTitle: note.title, noteText: note.rawNote)
    }

    private func citedTutorBundle(for note: ModelMigrationDatasetNote) async -> AIService.CitedTutorResponse {
        await withCheckedContinuation { continuation in
            AIService.shared.citedTutorResponse(
                noteID: UUID(uuidString: note.id),
                noteTitle: note.title,
                noteText: note.rawNote,
                userRequest: tutorQuestion(for: note)
            ) { response in
                continuation.resume(returning: response)
            }
        }
    }

    private func fallbackResponse(for category: ModelMigrationEvaluationCategory, note: ModelMigrationDatasetNote) async -> (rawResponse: String, parsedResponse: String, parsingSucceeded: Bool, promptTokenCount: Int, completionTokenCount: Int) {
        let snapshot = await snapshot(for: note)
        switch category {
        case .conceptExtraction:
            return (encodeJSON(snapshot), encodeJSON(snapshot), true, note.rawNote.split { $0.isWhitespace || $0.isNewline }.count, snapshot.importantFacts.count)
        case .relationshipExtraction:
            return (encodeJSON(snapshot.relationships), encodeJSON(snapshot.relationships), true, note.rawNote.split { $0.isWhitespace || $0.isNewline }.count, snapshot.relationships.count)
        case .flashcardGeneration:
            let deck = LearningEngine.shared.generateFlashcards(from: snapshot)
            return (encodeJSON(deck), encodeJSON(deck), true, note.rawNote.split { $0.isWhitespace || $0.isNewline }.count, deck.count)
        case .questionGeneration:
            let quiz = LearningEngine.shared.generateQuizSet(from: snapshot)
            return (encodeJSON(quiz), encodeJSON(quiz), true, note.rawNote.split { $0.isWhitespace || $0.isNewline }.count, quiz.questions.count)
        case .tutorQuestionAnswering:
            let tutor = PromptTutorResponse(
                answer: snapshot.summaryHighlights.first ?? note.rawNote,
                keyPoints: snapshot.keyTerms.prefix(5).map { $0.title },
                followUpQuestions: ["What part of \(note.title) needs the most review?"],
                confidence: 0.6,
                citations: nil
            )
            return (encodeJSON(tutor), encodeJSON(tutor), true, note.rawNote.split { $0.isWhitespace || $0.isNewline }.count, tutor.keyPoints.count)
        case .retrievalGroundedAnswering:
            let citations = note.expectedKeywords.prefix(3).map {
                PromptTutorCitation(sourceType: "note", sourceID: note.id, noteTitle: note.title, conceptName: $0, snippet: note.rawNote.prefix(160).description)
            }
            let tutor = PromptTutorResponse(
                answer: "Based on \(note.title), the core ideas are: \(note.expectedKeywords.joined(separator: ", ")).",
                keyPoints: note.expectedKeywords.prefix(5).map { $0 },
                followUpQuestions: ["How would you explain \(note.expectedKeywords.first ?? note.title) in your own words?"],
                confidence: 0.55,
                citations: citations
            )
            return (encodeJSON(tutor), encodeJSON(tutor), true, note.rawNote.split { $0.isWhitespace || $0.isNewline }.count, tutor.keyPoints.count)
        }
    }

    private func prompt(for category: ModelMigrationEvaluationCategory, note: ModelMigrationDatasetNote) -> String {
        switch category {
        case .conceptExtraction:
            return "Extract canonical concepts, facts, relationships, and source references from the note.\n\nTitle: \(note.title)\n\n\(note.rawNote)"
        case .relationshipExtraction:
            return "Infer conservative knowledge graph relationships from the note.\n\nTitle: \(note.title)\n\n\(note.rawNote)"
        case .flashcardGeneration:
            return "Generate compact flashcards grounded in the note and its structured knowledge."
        case .questionGeneration:
            return "Generate grounded multiple choice questions from the note and its structured knowledge."
        case .tutorQuestionAnswering:
            return tutorQuestion(for: note)
        case .retrievalGroundedAnswering:
            return "Answer using retrieved evidence and cite the supporting source note."
        }
    }

    private func tutorQuestion(for note: ModelMigrationDatasetNote) -> String {
        "Explain the most important ideas in \(note.title) and why they matter."
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func buildComparisonMarkdown(categories: [ModelMigrationCategoryResult], modelIDs: [String], datasetRoot: URL, outputRoot: URL) -> String {
        var lines: [String] = []
        lines.append("# Model Migration Comparison")
        lines.append("")
        lines.append("- Dataset root: \(datasetRoot.path)")
        lines.append("- Output root: \(outputRoot.path)")
        lines.append("- Models: \(modelIDs.joined(separator: ", "))")
        lines.append("")

        for category in categories {
            lines.append("## \(ModelMigrationEvaluationCategory(rawValue: category.category)?.title ?? category.category)")
            lines.append("")
            let byModel = Dictionary(grouping: category.results, by: { $0.modelID })
            for modelID in modelIDs {
                let records = byModel[modelID] ?? []
                let successRate = records.isEmpty ? 0 : Double(records.filter { $0.parsingSucceeded }.count) / Double(records.count)
                let averageLatency = records.isEmpty ? 0 : records.reduce(0.0) { $0 + $1.executionTimeSeconds } / Double(records.count)
                let failures = records.compactMap { $0.failure }.filter { !$0.isEmpty }
                lines.append("- \(modelID): parse success \(String(format: "%.2f", successRate)), average latency \(String(format: "%.2f", averageLatency))s, failures \(failures.count)")
            }
            lines.append("")
        }

        let recommendation = makeRecommendation(from: categories, modelIDs: modelIDs)
        lines.append("## Recommendation")
        lines.append(recommendation)
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private func makeRecommendation(from categories: [ModelMigrationCategoryResult], modelIDs: [String]) -> String {
        var modelScores: [String: Double] = [:]
        for modelID in modelIDs {
            let records = categories.flatMap { $0.results.filter { $0.modelID == modelID } }
            let parseScore = records.isEmpty ? 0 : Double(records.filter { $0.parsingSucceeded }.count) / Double(records.count)
            let groundingBonus = records.filter { $0.category == ModelMigrationEvaluationCategory.retrievalGroundedAnswering.rawValue }.filter { $0.parsingSucceeded }.count > 0 ? 0.1 : 0
            modelScores[modelID] = parseScore + groundingBonus
        }
        let preferred = modelScores.max(by: { $0.value < $1.value })?.key ?? "qwen-3-4b"
        return "Preferred model: \(preferred). Keep Qwen2.5 as the fallback because it remains catalog-supported and provides a regression baseline."
    }
}

private extension ModelMigrationDatasetNote {
    var stableUUID: UUID {
        UUID(uuidString: id) ?? UUID()
    }
}
