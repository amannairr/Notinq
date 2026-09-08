import Foundation

enum PromptJSONSupport {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

struct PromptExtractionInput: Sendable {
    var noteTitle: String
    var noteText: String
}

struct PromptStructuredKnowledgeInput: Sendable {
    var noteTitle: String
    var knowledge: StructuredKnowledge

    init(noteTitle: String, knowledge: StructuredKnowledge) {
        self.noteTitle = noteTitle
        self.knowledge = knowledge
    }

    init(noteTitle: String, knowledge: StudyKnowledgeSnapshot) {
        self.noteTitle = noteTitle
        self.knowledge = knowledge.structuredKnowledgeRepresentation()
    }
}

struct PromptGraphInput: Sendable {
    var noteTitle: String
    var graph: KnowledgeGraph
}

struct PromptTutorInput: Sendable {
    var noteTitle: String
    var knowledge: StructuredKnowledge
    var question: String

    init(noteTitle: String, knowledge: StructuredKnowledge, question: String) {
        self.noteTitle = noteTitle
        self.knowledge = knowledge
        self.question = question
    }

    init(noteTitle: String, knowledge: StudyKnowledgeSnapshot, question: String) {
        self.noteTitle = noteTitle
        self.knowledge = knowledge.structuredKnowledgeRepresentation()
        self.question = question
    }
}

struct PromptComparisonInput: Sendable {
    var leftTitle: String
    var rightTitle: String
    var leftJSON: String
    var rightJSON: String
}

struct PromptFlashcardEntry: Codable, Equatable, Sendable {
    var type: String
    var front: String
    var back: String
    var whyItMatters: String
    var confidence: Double
}

struct PromptFlashcardDeck: Codable, Equatable, Sendable {
    var cards: [PromptFlashcardEntry]
}

struct PromptQuizEntry: Codable, Equatable, Sendable {
    var prompt: String
    var options: [String]
    var correctAnswer: String
    var explanation: String
    var keywords: [String]
    var confidence: Double
}

struct PromptQuizSet: Codable, Equatable, Sendable {
    var title: String
    var questions: [PromptQuizEntry]
}

struct PromptConceptNode: Codable, Equatable, Sendable {
    var title: String
    var summary: String
    var children: [PromptConceptNode]
}

struct PromptSummaryOutput: Codable, Equatable, Sendable {
    var executiveSummary: String
    var detailedSummary: String
    var examRevisionSummary: String
    var confidence: Double
}

struct PromptLearningInsightsOutput: Codable, Equatable, Sendable {
    var keyConcepts: [String]
    var importantConcepts: [String]
    var frequentTerms: [StudyTerm]
    var potentialExamTopics: [String]
    var knowledgeGaps: [String]
    var confidence: Double
}

struct PromptTutorResponse: Codable, Equatable, Sendable {
    var answer: String
    var keyPoints: [String]
    var followUpQuestions: [String]
    var confidence: Double
    var citations: [PromptTutorCitation]? = nil
}

struct PromptTutorCitation: Codable, Equatable, Sendable {
    var sourceType: String
    var sourceID: String
    var noteTitle: String
    var conceptName: String?
    var snippet: String
}

struct PromptDefinitionEntry: Codable, Equatable, Sendable {
    var term: String
    var definition: String
    var aliases: [String]
    var example: String
    var confidence: Double
}

struct PromptDefinitionSet: Codable, Equatable, Sendable {
    var definitions: [PromptDefinitionEntry]
}

struct PromptTimelineEntry: Codable, Equatable, Sendable {
    var dateLabel: String
    var event: String
    var significance: String
    var confidence: Double
}

struct PromptTimeline: Codable, Equatable, Sendable {
    var title: String
    var events: [PromptTimelineEntry]
}

struct PromptFormulaEntry: Codable, Equatable, Sendable {
    var formula: String
    var meaning: String
    var variables: [String]
    var example: String
    var confidence: Double
}

struct PromptFormulaSet: Codable, Equatable, Sendable {
    var formulas: [PromptFormulaEntry]
}

struct PromptRevisionPlan: Codable, Equatable, Sendable {
    var priorities: [String]
    var dailyPlan: [String]
    var quickWins: [String]
    var confidence: Double
}

struct PromptCheatSheet: Codable, Equatable, Sendable {
    var title: String
    var bullets: [String]
    var mnemonics: [String]
    var confidence: Double
}

struct PromptPodcastSegment: Codable, Equatable, Sendable {
    var title: String
    var script: String
}

struct PromptPodcastScript: Codable, Equatable, Sendable {
    var title: String
    var segments: [PromptPodcastSegment]
    var closingSummary: String
    var confidence: Double
}

struct PromptComparisonResult: Codable, Equatable, Sendable {
    var overview: String
    var similarities: [String]
    var differences: [String]
    var recommendation: String
    var confidence: Double
}

struct PromptActionItem: Codable, Equatable, Sendable {
    var title: String
    var description: String
    var priority: String
    var confidence: Double
}

struct PromptActionItemList: Codable, Equatable, Sendable {
    var items: [PromptActionItem]
}

enum PromptValidationSupport {
    static func summaryValidation(_ output: PromptSummaryOutput) -> PromptValidationReport {
        let issues = [
            output.executiveSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? PromptValidationIssue(field: "executiveSummary", message: "Missing executive summary", severity: .error)
                : nil,
            output.detailedSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? PromptValidationIssue(field: "detailedSummary", message: "Missing detailed summary", severity: .error)
                : nil,
            output.confidence < 0.4
                ? PromptValidationIssue(field: "confidence", message: "Low confidence", severity: .warning)
                : nil
        ].compactMap { $0 }
        return PromptValidationReport(isValid: !issues.contains(where: { $0.severity == .error }), shouldRetry: !issues.isEmpty, confidence: output.confidence, issues: issues)
    }

    static func flashcardValidation(_ output: PromptFlashcardDeck) -> PromptValidationReport {
        let fronts = output.cards.map(\.front)
        let backs = output.cards.map(\.back)
        var issues = PromptValidatorEngine.validateDuplicates(fronts, field: "front")
        issues += PromptValidatorEngine.validateDuplicates(backs, field: "back")
        issues += output.cards.flatMap { card in
            [
                card.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? PromptValidationIssue(field: "front", message: "Missing flashcard front", severity: .error)
                    : nil,
                card.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? PromptValidationIssue(field: "back", message: "Missing flashcard back", severity: .error)
                    : nil
            ].compactMap { $0 }
        }
        let confidences = output.cards.map(\.confidence)
        issues += PromptValidatorEngine.validateConfidence(confidences, minimum: 0.5, field: "confidence")
        return PromptValidationReport(isValid: !issues.contains(where: { $0.severity == .error }), shouldRetry: !issues.isEmpty, confidence: confidences.min() ?? 0.5, issues: issues)
    }

    static func quizValidation(_ output: PromptQuizSet) -> PromptValidationReport {
        let prompts = output.questions.map(\.prompt)
        var issues = PromptValidatorEngine.validateDuplicates(prompts, field: "prompt")
        issues += output.questions.flatMap { question in
            var local: [PromptValidationIssue] = []
            if question.options.count < 2 {
                local.append(PromptValidationIssue(field: "options", message: "Quiz question needs at least two options", severity: .error))
            }
            if question.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                local.append(PromptValidationIssue(field: "explanation", message: "Missing explanation", severity: .warning))
            }
            if question.correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                local.append(PromptValidationIssue(field: "correctAnswer", message: "Missing correct answer", severity: .error))
            }
            return local
        }
        let confidences = output.questions.map(\.confidence)
        issues += PromptValidatorEngine.validateConfidence(confidences, minimum: 0.5, field: "confidence")
        return PromptValidationReport(isValid: !issues.contains(where: { $0.severity == .error }), shouldRetry: !issues.isEmpty, confidence: confidences.min() ?? 0.5, issues: issues)
    }

    static func conceptValidation(_ output: [PromptConceptNode]) -> PromptValidationReport {
        let titles = flattenTitles(output)
        let issues = PromptValidatorEngine.validateDuplicates(titles, field: "title")
        return PromptValidationReport(isValid: !issues.contains(where: { $0.severity == .error }), shouldRetry: !issues.isEmpty, confidence: 0.8, issues: issues)
    }

    static func genericValidation(confidence: Double = 0.8) -> PromptValidationReport {
        PromptValidationReport(isValid: true, shouldRetry: false, confidence: confidence, issues: [])
    }

    private static func flattenTitles(_ nodes: [PromptConceptNode]) -> [String] {
        nodes.flatMap { node in
            [node.title] + flattenTitles(node.children)
        }
    }
}

enum PromptCatalog {
    static let entries: [PromptCatalogEntry] = [
        PromptCatalogEntry(id: "knowledgeExtraction", version: "1.0.0", description: "Canonical structured extraction from raw notes.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptExtractionInput", outputType: "CanonicalExtractionPayload", expectedLatency: "high", estimatedTokens: 900),
        PromptCatalogEntry(id: "summary", version: "1.0.0", description: "Faithful summary from structured knowledge.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptSummaryOutput", expectedLatency: "medium", estimatedTokens: 420),
        PromptCatalogEntry(id: "flashcards", version: "1.0.0", description: "One-concept-per-card flashcards.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptFlashcardDeck", expectedLatency: "medium", estimatedTokens: 520),
        PromptCatalogEntry(id: "multipleChoiceQuiz", version: "1.0.0", description: "Grounded multiple choice quiz items.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptQuizSet", expectedLatency: "medium", estimatedTokens: 560),
        PromptCatalogEntry(id: "learningInsights", version: "1.0.0", description: "Study priorities and coverage gaps.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptLearningInsightsOutput", expectedLatency: "medium", estimatedTokens: 360),
        PromptCatalogEntry(id: "conceptMap", version: "1.0.0", description: "Hierarchical concept tree.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptConceptNode", expectedLatency: "medium", estimatedTokens: 520),
        PromptCatalogEntry(id: "knowledgeGraphExpansion", version: "1.0.0", description: "Conservative graph expansion.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptGraphInput", outputType: "KnowledgeGraphExtractionPayload", expectedLatency: "medium", estimatedTokens: 520),
        PromptCatalogEntry(id: "aiTutor", version: "1.0.0", description: "Grounded tutor response.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptTutorInput", outputType: "PromptTutorResponse", expectedLatency: "medium", estimatedTokens: 420),
        PromptCatalogEntry(id: "definitions", version: "1.0.0", description: "Concise term definitions.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptDefinitionSet", expectedLatency: "low", estimatedTokens: 360),
        PromptCatalogEntry(id: "timeline", version: "1.0.0", description: "Study timeline.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptTimeline", expectedLatency: "low", estimatedTokens: 360),
        PromptCatalogEntry(id: "formulaExtraction", version: "1.0.0", description: "Formula and notation extraction.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptFormulaSet", expectedLatency: "low", estimatedTokens: 360),
        PromptCatalogEntry(id: "revisionPlan", version: "1.0.0", description: "Actionable revision plan.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptRevisionPlan", expectedLatency: "low", estimatedTokens: 360),
        PromptCatalogEntry(id: "cheatSheet", version: "1.0.0", description: "Compact cheat sheet.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptCheatSheet", expectedLatency: "low", estimatedTokens: 360),
        PromptCatalogEntry(id: "podcast", version: "1.0.0", description: "Short educational podcast script.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptPodcastScript", expectedLatency: "medium", estimatedTokens: 520),
        PromptCatalogEntry(id: "comparison", version: "1.0.0", description: "Compare two structured outputs.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptComparisonInput", outputType: "PromptComparisonResult", expectedLatency: "low", estimatedTokens: 360),
        PromptCatalogEntry(id: "actionItems", version: "1.0.0", description: "Actionable study tasks.", supportedProviders: ["localLlama", "openAI", "anthropic", "gemini"], inputType: "PromptStructuredKnowledgeInput", outputType: "PromptActionItemList", expectedLatency: "low", estimatedTokens: 360)
    ]

    static let knowledgeExtractionSchema = PromptSchemaDescriptor(
        name: "CanonicalExtractionPayload",
        description: "Canonical structured extraction payload.",
        requiredFields: ["concepts", "facts", "relationships", "source_references"],
        jsonSchema: """
        {
          "concepts": [{"id":"string","name":"string","description":"string","importance_score":"number","confidence_score":"number","aliases":["string"],"source_chunk_ids":["string"]}],
          "facts": [{"id":"string","statement":"string","confidence_score":"number","concept_ids":["string"],"source_chunk_ids":["string"]}],
          "relationships": [{"source_id":"string","target_id":"string","relationship_type":"string","confidence_score":"number","source_chunk_ids":["string"]}],
          "source_references": [{"chunk_id":"string","document_id":"string","chunk_index":"number","start_offset":"number","end_offset":"number"}]
        }
        """
    )

    static let summarySchema = PromptSchemaDescriptor(name: "PromptSummaryOutput", description: "Structured summary output", requiredFields: ["executiveSummary", "detailedSummary", "examRevisionSummary", "confidence"], jsonSchema: "{ \"executiveSummary\": \"string\", \"detailedSummary\": \"string\", \"examRevisionSummary\": \"string\", \"confidence\": \"number\" }")
    static let flashcardSchema = PromptSchemaDescriptor(name: "PromptFlashcardDeck", description: "Flashcard deck", requiredFields: ["cards"], jsonSchema: "{ \"cards\": [{\"type\":\"string\",\"front\":\"string\",\"back\":\"string\",\"whyItMatters\":\"string\",\"confidence\":\"number\"}] }")
    static let quizSchema = PromptSchemaDescriptor(name: "PromptQuizSet", description: "Quiz set", requiredFields: ["title", "questions"], jsonSchema: "{ \"title\": \"string\", \"questions\": [{\"prompt\":\"string\",\"options\":[\"string\"],\"correctAnswer\":\"string\",\"explanation\":\"string\",\"keywords\":[\"string\"],\"confidence\":\"number\"}] }")
    static let insightsSchema = PromptSchemaDescriptor(name: "PromptLearningInsightsOutput", description: "Learning insights", requiredFields: ["keyConcepts", "importantConcepts", "confidence"], jsonSchema: "{ \"keyConcepts\": [\"string\"], \"importantConcepts\": [\"string\"], \"frequentTerms\": [{\"term\":\"string\",\"count\":\"number\"}], \"potentialExamTopics\": [\"string\"], \"knowledgeGaps\": [\"string\"], \"confidence\": \"number\" }")
    static let conceptMapSchema = PromptSchemaDescriptor(name: "PromptConceptNode", description: "Concept map tree", requiredFields: ["title"], jsonSchema: "{ \"title\": \"string\", \"summary\": \"string\", \"children\": [] }")
    static let graphExpansionSchema = PromptSchemaDescriptor(name: "KnowledgeGraphExtractionPayload", description: "Graph expansion payload", requiredFields: ["concepts", "relationships"], jsonSchema: "{ \"concepts\": [], \"relationships\": [] }")
    static let tutorSchema = PromptSchemaDescriptor(name: "PromptTutorResponse", description: "Tutor response", requiredFields: ["answer", "keyPoints", "followUpQuestions", "confidence"], jsonSchema: "{ \"answer\": \"string\", \"keyPoints\": [\"string\"], \"followUpQuestions\": [\"string\"], \"confidence\": \"number\", \"citations\": [{\"sourceType\":\"string\",\"sourceID\":\"string\",\"noteTitle\":\"string\",\"conceptName\":\"string\",\"snippet\":\"string\"}] }")
    static let definitionsSchema = PromptSchemaDescriptor(name: "PromptDefinitionSet", description: "Definitions", requiredFields: ["definitions"], jsonSchema: "{ \"definitions\": [{\"term\":\"string\",\"definition\":\"string\",\"aliases\":[\"string\"],\"example\":\"string\",\"confidence\":\"number\"}] }")
    static let timelineSchema = PromptSchemaDescriptor(name: "PromptTimeline", description: "Timeline", requiredFields: ["title", "events"], jsonSchema: "{ \"title\": \"string\", \"events\": [{\"dateLabel\":\"string\",\"event\":\"string\",\"significance\":\"string\",\"confidence\":\"number\"}] }")
    static let formulaSchema = PromptSchemaDescriptor(name: "PromptFormulaSet", description: "Formula extraction", requiredFields: ["formulas"], jsonSchema: "{ \"formulas\": [{\"formula\":\"string\",\"meaning\":\"string\",\"variables\":[\"string\"],\"example\":\"string\",\"confidence\":\"number\"}] }")
    static let revisionPlanSchema = PromptSchemaDescriptor(name: "PromptRevisionPlan", description: "Revision plan", requiredFields: ["priorities", "dailyPlan", "quickWins", "confidence"], jsonSchema: "{ \"priorities\": [\"string\"], \"dailyPlan\": [\"string\"], \"quickWins\": [\"string\"], \"confidence\": \"number\" }")
    static let cheatSheetSchema = PromptSchemaDescriptor(name: "PromptCheatSheet", description: "Cheat sheet", requiredFields: ["title", "bullets", "confidence"], jsonSchema: "{ \"title\": \"string\", \"bullets\": [\"string\"], \"mnemonics\": [\"string\"], \"confidence\": \"number\" }")
    static let podcastSchema = PromptSchemaDescriptor(name: "PromptPodcastScript", description: "Podcast script", requiredFields: ["title", "segments", "confidence"], jsonSchema: "{ \"title\": \"string\", \"segments\": [{\"title\":\"string\",\"script\":\"string\"}], \"closingSummary\": \"string\", \"confidence\": \"number\" }")
    static let comparisonSchema = PromptSchemaDescriptor(name: "PromptComparisonResult", description: "Comparison result", requiredFields: ["overview", "similarities", "differences", "recommendation", "confidence"], jsonSchema: "{ \"overview\": \"string\", \"similarities\": [\"string\"], \"differences\": [\"string\"], \"recommendation\": \"string\", \"confidence\": \"number\" }")
    static let actionItemsSchema = PromptSchemaDescriptor(name: "PromptActionItemList", description: "Action items", requiredFields: ["items"], jsonSchema: "{ \"items\": [{\"title\":\"string\",\"description\":\"string\",\"priority\":\"string\",\"confidence\":\"number\"}] }")

    static func entry(for identifier: AIPromptIdentifier) -> PromptCatalogEntry? {
        entries.first { $0.id == identifier.rawValue }
    }

    static func documentation(for identifier: AIPromptIdentifier) -> String {
        let definition = definition(for: identifier)
        let entry = entry(for: identifier)
        let inputType = entry?.inputType ?? "Unknown"
        let outputType = entry?.outputType ?? "Unknown"
        return [
            "Purpose: \(definition.systemPrompt)",
            "Inputs: \(inputType)",
            "Outputs: \(outputType)",
            "Why redesigned: deterministic structure, smaller instructions, and JSON-first outputs.",
            "Expected improvements: fewer hallucinations, lower variance, easier validation.",
            "Potential limitations: local models may still omit fields when the source is ambiguous."
        ].joined(separator: "\n")
    }

    static func definition(for identifier: AIPromptIdentifier) -> AIPromptDefinition {
        switch identifier {
        case .knowledgeExtraction:
            return KnowledgeExtractionPrompt.definition
        case .summary:
            return SummaryPrompt.definition
        case .revisionGuide:
            return RevisionPlanPrompt.definition
        case .keyConcepts:
            return DefinitionsPrompt.definition
        case .flashcards:
            return FlashcardsPrompt.definition
        case .practiceQuestions:
            return AIActionItemsPrompt.definition
        case .multipleChoiceQuiz:
            return QuizPrompt.definition
        case .conceptMap:
            return ConceptMapPrompt.definition
        case .learningInsights:
            return LearningInsightsPrompt.definition
        case .knowledgeGaps:
            return ActionItemsPrompt.definition
        case .activeRecall:
            return TutorPrompt.definition
        case .assistantChat:
            return AIHelperChatPrompt.definition
        case .directEditing:
            return DirectEditPrompt.definition
        case .knowledgeGraphExpansion:
            return KnowledgeGraphExpansionPrompt.definition
        case .aiTutor:
            return TutorPrompt.definition
        case .definitions:
            return DefinitionsPrompt.definition
        case .timeline:
            return TimelinePrompt.definition
        case .formulaExtraction:
            return FormulaExtractionPrompt.definition
        case .revisionPlan:
            return RevisionPlanPrompt.definition
        case .cheatSheet:
            return CheatSheetPrompt.definition
        case .podcast:
            return PodcastPrompt.definition
        case .comparison:
            return ComparisonPrompt.definition
        case .actionItems:
            return ActionItemsPrompt.definition
        }
    }
}

struct KnowledgeExtractionPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .knowledgeExtraction
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.knowledgeExtraction
    static let outputSchema = PromptCatalog.knowledgeExtractionSchema
    static let defaultTemperature: Float = 0.0
    static let defaultTopP: Float = 0.85
    static let defaultMaxTokens: Int32 = 900
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.75
    static let validationStrategy: PromptValidationStrategy = .strictJSON

    static func buildDocument(input: PromptExtractionInput, context: PromptBuildContext) -> PromptDocument {
        let body = """
        Note title: \(input.noteTitle)

        Note text:
        \(input.noteText)
        """
        return PromptBuilder.buildDocument(
            role: "You are a deterministic extraction engine for study notes.",
            task: "Return canonical extraction data grounded only in the note.",
            rules: [
                "Extract only explicit information present in the note.",
                "Do not summarize, infer, expand, or explain.",
                "Preserve source order exactly as it appears in the note.",
                "Use conservative confidence scores.",
                "Leave unsupported fields empty.",
                "Return only concepts, facts, relationships, and source references."
            ],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: [
                "Do not invent concepts, relationships, or examples.",
                "Do not use markdown fences or prose outside JSON.",
                "Do not reorder the extracted sections."
            ],
            validationRules: [
                "Every concept needs an identifier, name, confidence, importance, and source chunk ids.",
                "Every fact needs an identifier, statement, confidence, and source chunk ids.",
                "Every relationship needs a normalized allowed relationship type and valid source and target identifiers."
            ],
            body: body,
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: [
                "prompt": identifier.rawValue,
                "inputType": String(reflecting: PromptExtractionInput.self),
                "outputType": String(reflecting: CanonicalExtractionPayload.self)
            ]
        )
    }

    static func validate(output: CanonicalExtractionPayload, input: PromptExtractionInput, context: PromptBuildContext) -> PromptValidationReport {
        let report = ExtractionValidator.validate(payload: output)
        let required: [String: String] = [
            "concepts": output.concepts.isEmpty ? "" : "ok",
            "facts": output.facts.isEmpty ? "" : "ok",
            "relationships": output.relationships.isEmpty ? "" : "ok",
            "source_references": output.sourceReferences.isEmpty ? "" : "ok"
        ]
        var issues = PromptValidatorEngine.validateRequiredFields(required, required: outputSchema.requiredFields)
        issues += report.issues.map {
            PromptValidationIssue(field: $0.field, message: $0.message, severity: $0.severity == .error ? .error : .warning)
        }
        return PromptValidationReport(
            isValid: report.isValid && !issues.contains(where: { $0.severity == .error }),
            shouldRetry: !issues.isEmpty,
            confidence: output.concepts.map(\.confidenceScore).min() ?? 0.5,
            issues: issues
        )
    }
}

struct SummaryPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .summary
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.summary
    static let outputSchema = PromptCatalog.summarySchema
    static let defaultTemperature: Float = 0.2
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 420
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.75
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        let body = PromptJSONSupport.encode(input.knowledge)
        return PromptBuilder.buildDocument(
            role: "You are a study summarizer.",
            task: "Write a summary that stays faithful to the structured knowledge.",
            rules: ["Do not add facts not present in the knowledge snapshot.", "Prefer short, direct language."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not emit markdown.", "Do not repeat the same point more than once."],
            validationRules: ["All sections must be present.", "Summary should be grounded in extracted concepts."],
            body: "Note title: \(input.noteTitle)\n\nStructured knowledge JSON:\n\(body)",
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptSummaryOutput, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationSupport.summaryValidation(output)
    }
}

struct FlashcardsPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .flashcards
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.flashcards
    static let outputSchema = PromptSchemaDescriptor(name: "PromptFlashcardDeck", description: "Flashcards", requiredFields: ["cards"], jsonSchema: "{}")
    static let defaultTemperature: Float = 0.2
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 520
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a flashcard generator.",
            task: "Create focused, non-duplicative flashcards from structured knowledge.",
            rules: ["One concept per card.", "Avoid redundant cards.", "Keep backs short and precise."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not add explanations beyond the back field.", "Do not output markdown."],
            validationRules: ["Each card needs a front and back.", "Avoid duplicate fronts."],
            body: "Structured knowledge JSON:\n\(PromptJSONSupport.encode(input.knowledge))",
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptFlashcardDeck, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationSupport.flashcardValidation(output)
    }
}

struct QuizPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .multipleChoiceQuiz
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.quiz
    static let outputSchema = PromptCatalog.quizSchema
    static let defaultTemperature: Float = 0.15
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 560
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a quiz writer.",
            task: "Create multiple choice quiz items grounded in structured knowledge.",
            rules: ["Use plausible distractors.", "Keep explanations short.", "Prefer application over trivia."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not repeat the same question.", "Do not use ambiguous correct answers."],
            validationRules: ["Each question needs at least two options.", "Each question needs an explanation."],
            body: "Structured knowledge JSON:\n\(PromptJSONSupport.encode(input.knowledge))",
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptQuizSet, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationSupport.quizValidation(output)
    }
}

struct LearningInsightsPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .learningInsights
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.learningInsights
    static let outputSchema = PromptCatalog.insightsSchema
    static let defaultTemperature: Float = 0.15
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 360
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .graphAware

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a learning analyst.",
            task: "Return study priorities and coverage gaps from structured knowledge.",
            rules: ["Use only extracted knowledge.", "Prioritize actionable study guidance."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not speculate about missing content.", "Do not repeat the same gap wording."],
            validationRules: ["Insights should map to extracted concepts.", "Top priorities should be explicit."],
            body: PromptJSONSupport.encode(input.knowledge),
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptLearningInsightsOutput, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        let issues = [
            output.keyConcepts.isEmpty ? PromptValidationIssue(field: "keyConcepts", message: "No key concepts", severity: .warning) : nil,
            output.importantConcepts.isEmpty ? PromptValidationIssue(field: "importantConcepts", message: "No important concepts", severity: .warning) : nil
        ].compactMap { $0 }
        return PromptValidationReport(isValid: true, shouldRetry: !issues.isEmpty, confidence: output.confidence, issues: issues)
    }
}

struct ConceptMapPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .conceptMap
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.conceptMap
    static let outputSchema = PromptCatalog.conceptMapSchema
    static let defaultTemperature: Float = 0.1
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 520
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .graphAware

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a concept map renderer.",
            task: "Render the explicit relationships from structured knowledge as a stable concept tree.",
            rules: ["Use relationships already present in the knowledge snapshot.", "Do not invent new nodes.", "Keep the hierarchy shallow and stable."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not invent nodes.", "Do not duplicate nodes across branches."],
            validationRules: ["Hierarchy must reflect the relationship graph.", "Children should be related to the parent."],
            body: PromptJSONSupport.encode(input.knowledge.relationships),
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: [PromptConceptNode], input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationSupport.conceptValidation(output)
    }
}

struct KnowledgeGraphExpansionPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .knowledgeGraphExpansion
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = "Expand the knowledge graph from structured knowledge."
    static let outputSchema = PromptCatalog.graphExpansionSchema
    static let defaultTemperature: Float = 0.15
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 520
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .graphAware

    static func buildDocument(input: PromptGraphInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a knowledge graph expansion model.",
            task: "Infer missing graph nodes and relationships from the current graph.",
            rules: ["Use only nodes supported by the graph context.", "Prefer conservative edges."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not add unsupported nodes.", "Do not create cycles unless the source implies them."],
            validationRules: ["Every concept should be grounded in the source graph.", "Confidence should be conservative."],
            body: PromptJSONSupport.encode(input.graph),
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: KnowledgeGraphExtractionPayload, input: PromptGraphInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationSupport.genericValidation(confidence: 0.8)
    }
}

struct TutorPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .aiTutor
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.tutor
    static let outputSchema = PromptCatalog.tutorSchema
    static let defaultTemperature: Float = 0.2
    static let defaultTopP: Float = 0.92
    static let defaultMaxTokens: Int32 = 420
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .graphAware

    static func buildDocument(input: PromptTutorInput, context: PromptBuildContext) -> PromptDocument {
        let tutorGuidance = context.tutorContext?.guidanceSummary ?? "No mastery data available."
        let evidenceSummary = context.tutorContext?.evidenceSummary ?? "No retrieved evidence available."
        let citationsJSON = PromptJSONSupport.encode(context.tutorContext?.citations ?? [])
        return PromptBuilder.buildDocument(
            role: "You are a local study tutor.",
            task: "Answer the user's question using the structured knowledge snapshot.",
            rules: ["Do not invent facts.", "Use concise explanations.", "Prefer direct answers.", "Adapt the explanation depth to the student's mastery.", PromptFragments.citationRules(), "Reference the retrieved evidence and source notes when available."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not answer outside the knowledge snapshot.", "Do not add unsupported references.", "Do not cite sources that do not appear in the evidence summary."],
            validationRules: ["The answer should relate to the question.", "Include key points and follow-up questions.", "Ground the explanation in retrieved notes, chunks, or concepts."],
            body: "Note title: \(input.noteTitle)\n\nQuestion: \(input.question)\n\nTutor guidance:\n\(tutorGuidance)\n\nEvidence summary:\n\(evidenceSummary)\n\nCitations JSON:\n\(citationsJSON)\n\nKnowledge JSON:\n\(PromptJSONSupport.encode(input.knowledge))",
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptTutorResponse, input: PromptTutorInput, context: PromptBuildContext) -> PromptValidationReport {
        let trimmedAnswer = output.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        var issues: [PromptValidationIssue] = []

        if trimmedAnswer.isEmpty {
            issues.append(PromptValidationIssue(field: "answer", message: "Missing answer", severity: .error))
        }

        let lowerQuestion = input.question.lowercased()
        let supportedConcepts = input.knowledge.concepts.filter { concept in
            ([concept.name] + concept.aliases).contains(where: { lowerQuestion.contains($0.lowercased()) })
        }
        if supportedConcepts.isEmpty {
            issues.append(PromptValidationIssue(field: "coverage", message: "The question is not grounded in the supplied knowledge", severity: .warning))
        }

        return PromptValidationReport(
            isValid: !issues.contains(where: { $0.severity == .error }),
            shouldRetry: !issues.isEmpty,
            confidence: output.confidence,
            issues: issues
        )
    }
}

struct DefinitionsPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .definitions
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.definitions
    static let outputSchema = PromptCatalog.definitionsSchema
    static let defaultTemperature: Float = 0.15
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 360
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a definitions extractor.",
            task: "List the key terms and their concise definitions.",
            rules: ["Use terms from the knowledge snapshot.", "Keep definitions short."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not invent new terminology.", "Do not duplicate definitions."],
            validationRules: ["Every definition should correspond to a concept.", "Aliases should be compact."],
            body: PromptJSONSupport.encode(input.knowledge),
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptDefinitionSet, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        let issues = PromptValidatorEngine.validateDuplicates(output.definitions.map(\.term), field: "term")
        return PromptValidationReport(isValid: true, shouldRetry: !issues.isEmpty, confidence: output.definitions.map(\.confidence).min() ?? 0.7, issues: issues)
    }
}

struct TimelinePrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .timeline
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.timeline
    static let outputSchema = PromptCatalog.timelineSchema
    static let defaultTemperature: Float = 0.15
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 360
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a timeline builder.",
            task: "Infer a timeline of events or stages from the knowledge snapshot.",
            rules: ["Use only grounded sequence information.", "Keep the timeline concise."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not invent dates.", "Use stage labels when dates are not present."],
            validationRules: ["Events should be ordered logically.", "Each event should have a clear significance."],
            body: PromptJSONSupport.encode(input.knowledge),
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptTimeline, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationReport(isValid: !output.events.isEmpty, shouldRetry: output.events.isEmpty, confidence: 0.75, issues: output.events.isEmpty ? [PromptValidationIssue(field: "events", message: "Missing timeline events", severity: .warning)] : [])
    }
}

struct FormulaExtractionPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .formulaExtraction
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.formulaExtraction
    static let outputSchema = PromptCatalog.formulaSchema
    static let defaultTemperature: Float = 0.1
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 360
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a formula extraction model.",
            task: "Extract formulas, variables, and examples from the structured knowledge.",
            rules: ["Keep formulas literal.", "Use only formulas in the source."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not invent new formulas.", "Do not over-explain."],
            validationRules: ["Each formula should have meaning and example.", "Variables should be explicit."],
            body: PromptJSONSupport.encode(input.knowledge),
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptFormulaSet, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        let issues = PromptValidatorEngine.validateDuplicates(output.formulas.map(\.formula), field: "formula")
        return PromptValidationReport(isValid: !issues.contains(where: { $0.severity == .error }), shouldRetry: !issues.isEmpty, confidence: output.formulas.map(\.confidence).min() ?? 0.7, issues: issues)
    }
}

struct RevisionPlanPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .revisionPlan
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.revisionPlan
    static let outputSchema = PromptCatalog.revisionPlanSchema
    static let defaultTemperature: Float = 0.15
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 360
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a revision planner.",
            task: "Turn the structured knowledge into a compact study plan.",
            rules: ["Prioritize high-yield concepts.", "Make the plan actionable."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not be verbose.", "Do not add unrelated study advice."],
            validationRules: ["Priorities and daily plan should align with the snapshot.", "Keep quick wins short."],
            body: PromptJSONSupport.encode(input.knowledge),
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptRevisionPlan, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationReport(isValid: !output.priorities.isEmpty, shouldRetry: output.priorities.isEmpty, confidence: output.confidence, issues: [])
    }
}

struct CheatSheetPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .cheatSheet
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.cheatSheet
    static let outputSchema = PromptCatalog.cheatSheetSchema
    static let defaultTemperature: Float = 0.15
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 360
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a cheat sheet generator.",
            task: "Create a compact cheat sheet with bullets and mnemonics.",
            rules: ["Keep it short.", "Use high-yield phrasing."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not produce essays.", "Do not duplicate bullets."],
            validationRules: ["Bullets should be specific.", "Mnemonics should be memorable."],
            body: PromptJSONSupport.encode(input.knowledge),
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptCheatSheet, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationReport(isValid: !output.bullets.isEmpty, shouldRetry: output.bullets.isEmpty, confidence: output.confidence, issues: [])
    }
}

struct PodcastPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .podcast
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.summary
    static let outputSchema = PromptCatalog.podcastSchema
    static let defaultTemperature: Float = 0.2
    static let defaultTopP: Float = 0.92
    static let defaultMaxTokens: Int32 = 520
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a podcast script writer.",
            task: "Turn the structured knowledge into a short educational podcast outline.",
            rules: ["Keep it grounded in the snapshot.", "Keep segments concise."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not invent dialogue personas not requested.", "Do not add unsupported claims."],
            validationRules: ["Every segment should be tied to the knowledge snapshot.", "The closing summary must reinforce the main point."],
            body: PromptJSONSupport.encode(input.knowledge),
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptPodcastScript, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationReport(isValid: !output.segments.isEmpty, shouldRetry: output.segments.isEmpty, confidence: output.confidence, issues: [])
    }
}

struct ComparisonPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .comparison
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.comparison
    static let outputSchema = PromptCatalog.comparisonSchema
    static let defaultTemperature: Float = 0.1
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 360
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptComparisonInput, context: PromptBuildContext) -> PromptDocument {
        let body = """
        Left title: \(input.leftTitle)
        Left JSON:
        \(input.leftJSON)

        Right title: \(input.rightTitle)
        Right JSON:
        \(input.rightJSON)
        """
        return PromptBuilder.buildDocument(
            role: "You are a comparison analyst.",
            task: "Compare two prompt outputs and report concrete differences.",
            rules: ["Be specific.", "Focus on changed content and structural differences."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not repeat the same delta.", "Do not invent scores."],
            validationRules: ["Every difference should be concrete.", "Recommendation should be actionable."],
            body: body,
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptComparisonResult, input: PromptComparisonInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationReport(isValid: !output.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, shouldRetry: false, confidence: output.confidence, issues: [])
    }
}

struct ActionItemsPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .actionItems
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.actionItems
    static let outputSchema = PromptCatalog.actionItemsSchema
    static let defaultTemperature: Float = 0.15
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 360
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are an action item generator.",
            task: "Produce concrete study actions from the knowledge snapshot.",
            rules: ["Each action should be feasible.", "Prioritize missing or weak concepts."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not produce vague suggestions.", "Do not duplicate actions."],
            validationRules: ["Every action item should be concrete.", "Priorities should be explicit."],
            body: PromptJSONSupport.encode(input.knowledge),
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptActionItemList, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        let issues = PromptValidatorEngine.validateDuplicates(output.items.map(\.title), field: "title")
        return PromptValidationReport(isValid: !issues.contains(where: { $0.severity == .error }), shouldRetry: !issues.isEmpty, confidence: output.items.map(\.confidence).min() ?? 0.7, issues: issues)
    }
}

struct AIHelperChatPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .assistantChat
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.assistantChat
    static let outputSchema = PromptSchemaDescriptor(name: "assistantChat", description: "Plain text response", requiredFields: [], jsonSchema: "")
    static let defaultTemperature: Float = 0.4
    static let defaultTopP: Float = 0.92
    static let defaultMaxTokens: Int32 = 512
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .heuristic

    static func buildDocument(input: PromptExtractionInput, context: PromptBuildContext) -> PromptDocument {
        let body = """
        Note title: \(input.noteTitle)

        Note text:
        \(input.noteText)

        User request:
        \(context.userRequest ?? "")
        """
        return PromptBuilder.buildDocument(
            role: "You are a grounded note assistant.",
            task: "Respond directly to the user's request.",
            rules: ["Use the note as primary context.", "Be concise when the request is concise."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not invent unsupported facts.", "Do not mention internal policies."],
            validationRules: ["The answer should address the user's request.", "If uncertain, say so directly."],
            body: body,
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .text,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: String, input: PromptExtractionInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationReport(isValid: true, shouldRetry: false, confidence: 0.8, issues: [])
    }
}

struct DirectEditPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .directEditing
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.directEditing
    static let outputSchema = PromptSchemaDescriptor(name: "directEdit", description: "Plain text rewrite", requiredFields: [], jsonSchema: "")
    static let defaultTemperature: Float = 0.35
    static let defaultTopP: Float = 0.92
    static let defaultMaxTokens: Int32 = 512
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .heuristic

    static func buildDocument(input: PromptExtractionInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a precise editing model.",
            task: "Rewrite or transform the selected text exactly as requested.",
            rules: ["Preserve meaning.", "Use the note only as surrounding context."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not add unrelated content.", "Do not mention that you are an AI."],
            validationRules: ["The response should satisfy the user request.", "Do not alter meaning unless asked."],
            body: """
            Note title: \(input.noteTitle)

            Selected text:
            \(context.selectedText ?? "")

            User request:
            \(context.userRequest ?? "")
            """,
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .text,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: String, input: PromptExtractionInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationReport(isValid: !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, shouldRetry: false, confidence: 0.8, issues: [])
    }
}

struct AIActionItemsPrompt: PromptDefinition {
    static let identifier: AIPromptIdentifier = .practiceQuestions
    static let version: AIPromptVersion = .current
    static let baseSystemPrompt = PromptTextAssets.actionItems
    static let outputSchema = PromptSchemaDescriptor(name: "practiceQuestions", description: "Practice questions", requiredFields: [], jsonSchema: "{}")
    static let defaultTemperature: Float = 0.2
    static let defaultTopP: Float = 0.9
    static let defaultMaxTokens: Int32 = 420
    static let retryPolicy: PromptRetryPolicy = .standard
    static let confidenceRequirement: Double = 0.7
    static let validationStrategy: PromptValidationStrategy = .typed

    static func buildDocument(input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptDocument {
        PromptBuilder.buildDocument(
            role: "You are a practice question generator.",
            task: "Return short application-oriented prompts with answers.",
            rules: ["Keep prompts focused.", "Ground each question in the structured knowledge."],
            schema: outputSchema,
            confidenceRequirement: confidenceRequirement,
            failureRules: ["Do not create duplicate prompts.", "Do not create vague answers."],
            validationRules: ["Questions should be answerable from the snapshot.", "Answers should be short."],
            body: PromptJSONSupport.encode(input.knowledge),
            temperature: defaultTemperature,
            topP: defaultTopP,
            maxTokens: defaultMaxTokens,
            responseFormat: .json,
            metadata: ["prompt": identifier.rawValue]
        )
    }

    static func validate(output: PromptActionItemList, input: PromptStructuredKnowledgeInput, context: PromptBuildContext) -> PromptValidationReport {
        PromptValidationSupport.genericValidation(confidence: 0.8)
    }
}
