import Foundation

struct AIEvaluationNote: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var subject: String
    var difficulty: AIEvaluationDifficulty = .intermediate
    var sourceType: AIEvaluationSourceType = .lecture
    var approximateTokenCount: Int = 0
    var rawNote: String
    var expectedKeywords: [String]
    var sourceFileName: String
    var tags: [String] = []
    var metadata: [String: String] = [:]

    var displayName: String {
        title
    }
}

enum AIEvaluationNoteSet: String, Codable, CaseIterable, Sendable {
    case all
    case lecture
    case shortForm
    case noisy
    case longForm

    var title: String {
        switch self {
        case .all: return "All Notes"
        case .lecture: return "Lecture Notes"
        case .shortForm: return "Short Notes"
        case .noisy: return "Noisy Notes"
        case .longForm: return "Long Form"
        }
    }
}

enum AIEvaluationDifficulty: String, Codable, CaseIterable, Sendable {
    case intro
    case intermediate
    case advanced
}

enum AIEvaluationSourceType: String, Codable, CaseIterable, Sendable {
    case lecture
    case meeting
    case transcript
    case notes
    case noisyText = "noisy_text"
    case benchmark
    case goldStandard = "gold_standard"
}

struct AIEvaluationGenerationSettings: Codable, Equatable, Sendable {
    var temperature: Float
    var topP: Float
    var topK: Int
    var repeatPenalty: Float
    var maxTokens: Int
    var contextSize: Int

    static let `default` = AIEvaluationGenerationSettings(
        temperature: 0.2,
        topP: 0.9,
        topK: 40,
        repeatPenalty: 1.08,
        maxTokens: 768,
        contextSize: 4096
    )
}

struct AIEvaluationPerformanceMetrics: Codable, Equatable, Sendable {
    var generationTime: TimeInterval = 0
    var tokensPerSecond: Double = 0
    var memoryUsageMB: Double = 0
    var contextSize: Int = 0
    var modelLoadTime: TimeInterval = 0
    var latencyByFeature: [String: TimeInterval] = [:]
    var hallucinationCount: Int = 0

    private enum CodingKeys: String, CodingKey {
        case generationTime = "generation_time"
        case tokensPerSecond = "tokens_per_second"
        case memoryUsageMB = "memory_usage_mb"
        case contextSize = "context_size"
        case modelLoadTime = "model_load_time"
        case latencyByFeature = "latency_by_feature"
        case hallucinationCount = "hallucination_count"
    }
}

struct AIEvaluationPromptSnapshot: Codable, Equatable, Sendable {
    var feature: String
    var promptVersion: String
    var systemPrompt: String
    var userPrompt: String
    var outputDescription: String
    var responseFormat: String
}

struct AIEvaluationRawOutputs: Codable, Equatable, Sendable {
    var summary: String = ""
    var flashcards: String = ""
    var quiz: String = ""
    var conceptMap: String = ""
    var learningInsights: String = ""
    var knowledgeExtraction: String = ""

    static let empty = AIEvaluationRawOutputs()
}

struct AIEvaluationOutputs: Codable, Equatable, Sendable {
    var summary: String = ""
    var flashcards: [StudyFlashcard] = []
    var quiz: [StudyQuizQuestion] = []
    var conceptMap: [StudyConceptNode] = []
    var learningInsights: StudyInsights = StudyInsights()
    var knowledgeSnapshot: StudyKnowledgeSnapshot = StudyKnowledgeSnapshot()
    var rawOutputs: AIEvaluationRawOutputs = .empty

    private enum CodingKeys: String, CodingKey {
        case summary
        case flashcards
        case quiz
        case conceptMap = "concept_map"
        case learningInsights = "learning_insights"
        case knowledgeSnapshot = "knowledge_snapshot"
        case rawOutputs = "raw_outputs"
    }
}

struct AIEvaluationFeatureScores: Codable, Equatable, Sendable {
    var coverage: Double = 0
    var repetition: Double = 0
    var readability: Double = 0
    var length: Double = 0
    var structure: Double = 0
    var overall: Double = 0
}

struct AIEvaluationFlashcardScores: Codable, Equatable, Sendable {
    var duplicates: Double = 0
    var answerLength: Double = 0
    var conceptCoverage: Double = 0
    var specificity: Double = 0
    var overall: Double = 0
}

struct AIEvaluationQuizScores: Codable, Equatable, Sendable {
    var duplicateQuestions: Double = 0
    var explanationPresence: Double = 0
    var optionCount: Double = 0
    var answerPresence: Double = 0
    var overall: Double = 0
}

struct AIEvaluationConceptMapScores: Codable, Equatable, Sendable {
    var disconnectedNodes: Double = 0
    var missingRelationships: Double = 0
    var duplication: Double = 0
    var hierarchy: Double = 0
    var overall: Double = 0
}

struct AIEvaluationInsightScores: Codable, Equatable, Sendable {
    var missingConcepts: Double = 0
    var repetition: Double = 0
    var actionability: Double = 0
    var overall: Double = 0
}

struct AIEvaluationJSONScores: Codable, Equatable, Sendable {
    var parsingSuccess: Double = 0
    var schemaValidation: Double = 0
    var completeness: Double = 0
    var overall: Double = 0
}

struct AIEvaluationLocalScores: Codable, Equatable, Sendable {
    var summary: AIEvaluationFeatureScores = AIEvaluationFeatureScores()
    var flashcards: AIEvaluationFlashcardScores = AIEvaluationFlashcardScores()
    var quiz: AIEvaluationQuizScores = AIEvaluationQuizScores()
    var conceptMap: AIEvaluationConceptMapScores = AIEvaluationConceptMapScores()
    var learningInsights: AIEvaluationInsightScores = AIEvaluationInsightScores()
    var knowledgeSnapshot: AIEvaluationJSONScores = AIEvaluationJSONScores()
    var overall: Double = 0
}

struct AIEvaluationSemanticScores: Codable, Equatable, Sendable {
    var accuracy: Double = 0
    var completeness: Double = 0
    var educationalUsefulness: Double = 0
    var clarity: Double = 0
    var hallucinations: Double = 0
    var organization: Double = 0
    var quizQuality: Double = 0
    var flashcardQuality: Double = 0
    var overall: Double = 0
}

struct AIEvaluationSemanticEvaluationResult: Codable, Equatable, Sendable {
    var evaluatorID: String
    var referenceID: String?
    var heuristicScores: AIEvaluationLocalScores
    var semanticScores: AIEvaluationSemanticScores
    var heuristicScore: Double
    var semanticScore: Double
    var overallScore: Double
    var explanations: [String]
    var hallucinationCount: Int = 0
    var latencySeconds: TimeInterval = 0

    private enum CodingKeys: String, CodingKey {
        case evaluatorID = "evaluator_id"
        case referenceID = "reference_id"
        case heuristicScores = "heuristic_scores"
        case semanticScores = "semantic_scores"
        case heuristicScore = "heuristic_score"
        case semanticScore = "semantic_score"
        case overallScore = "overall_score"
        case explanations
        case hallucinationCount = "hallucination_count"
        case latencySeconds = "latency_seconds"
    }
}

struct AIEvaluationNoteResult: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var noteID: String
    var noteName: String
    var evaluationDate: Date
    var appVersion: String
    var gitCommit: String
    var modelName: String
    var modelIdentifier: String
    var promptVersion: String
    var noteSet: String
    var rawNote: String
    var promptsUsed: [AIEvaluationPromptSnapshot]
    var outputs: AIEvaluationOutputs
    var generationSettings: AIEvaluationGenerationSettings
    var localScores: AIEvaluationLocalScores
    var performanceMetrics: AIEvaluationPerformanceMetrics = AIEvaluationPerformanceMetrics()
    var semanticEvaluation: AIEvaluationSemanticEvaluationResult?
    var combinedReport: AIEvaluationCombinedReport?
    var regressionReport: AIEvaluationRegressionReport?
    var promptImprovementReport: AIEvaluationPromptImprovementReport?

    private enum CodingKeys: String, CodingKey {
        case id
        case noteID = "note_id"
        case noteName = "note_name"
        case evaluationDate = "evaluation_date"
        case appVersion = "app_version"
        case gitCommit = "git_commit"
        case modelName = "model_name"
        case modelIdentifier = "model_identifier"
        case promptVersion = "prompt_version"
        case noteSet = "note_set"
        case rawNote = "raw_note"
        case promptsUsed = "prompts_used"
        case outputs
        case generationSettings = "generation_settings"
        case localScores = "local_scores"
        case performanceMetrics = "performance_metrics"
        case semanticEvaluation = "semantic_evaluation"
        case combinedReport = "combined_report"
        case regressionReport = "regression_report"
        case promptImprovementReport = "prompt_improvement_report"
    }
}

struct AIEvaluationRunManifest: Codable, Equatable, Sendable {
    var evaluationDate: Date
    var noteSet: String
    var appVersion: String
    var gitCommit: String
    var modelName: String
    var modelIdentifier: String
    var promptVersion: String
    var resultCount: Int
    var averageOverallScore: Double
    var averageHeuristicScore: Double = 0
    var averageSemanticScore: Double = 0
    var averageGenerationTime: TimeInterval = 0
    var averageMemoryUsageMB: Double = 0
    var averageTokensPerSecond: Double = 0
    var noteResults: [AIEvaluationNoteResult]

    private enum CodingKeys: String, CodingKey {
        case evaluationDate = "evaluation_date"
        case noteSet = "note_set"
        case appVersion = "app_version"
        case gitCommit = "git_commit"
        case modelName = "model_name"
        case modelIdentifier = "model_identifier"
        case promptVersion = "prompt_version"
        case resultCount = "result_count"
        case averageOverallScore = "average_overall_score"
        case averageHeuristicScore = "average_heuristic_score"
        case averageSemanticScore = "average_semantic_score"
        case averageGenerationTime = "average_generation_time"
        case averageMemoryUsageMB = "average_memory_usage_mb"
        case averageTokensPerSecond = "average_tokens_per_second"
        case noteResults = "note_results"
    }
}

struct AIEvaluationCombinedReport: Codable, Equatable, Sendable {
    var evaluatorID: String
    var heuristicScore: Double
    var semanticScore: Double
    var overallScore: Double
    var heuristicExplanation: String
    var semanticExplanation: String
    var overallExplanation: String
    var signals: [String]

    private enum CodingKeys: String, CodingKey {
        case evaluatorID = "evaluator_id"
        case heuristicScore = "heuristic_score"
        case semanticScore = "semantic_score"
        case overallScore = "overall_score"
        case heuristicExplanation = "heuristic_explanation"
        case semanticExplanation = "semantic_explanation"
        case overallExplanation = "overall_explanation"
        case signals
    }
}

struct AIEvaluationRegressionDelta: Codable, Equatable, Sendable {
    var metric: String
    var baseline: Double
    var comparison: Double
    var delta: Double
}

struct AIEvaluationRegressionReport: Codable, Equatable, Sendable {
    var generatedAt: Date
    var title: String
    var baselineModel: String
    var comparisonModel: String
    var baselinePromptVersion: String
    var comparisonPromptVersion: String
    var scoreDeltas: [AIEvaluationRegressionDelta]
    var latencyDelta: Double
    var memoryDeltaMB: Double
    var jsonFailures: Int
    var hallucinationCountDelta: Int
    var alerts: [String]
}

struct AIEvaluationBenchmarkRanking: Codable, Equatable, Sendable {
    var rank: Int
    var modelName: String
    var promptVersion: String
    var overallQuality: Double
    var summaryQuality: Double
    var flashcardQuality: Double
    var quizQuality: Double
    var conceptMapQuality: Double
    var learningInsightsQuality: Double
    var speed: Double
    var memory: Double
    var jsonValidity: Double
}

struct AIEvaluationBenchmarkReport: Codable, Equatable, Sendable {
    var generatedAt: Date
    var datasetName: String
    var noteCount: Int
    var rankings: [AIEvaluationBenchmarkRanking]
    var notes: [String]
}

struct AIEvaluationPromptImprovementRecommendation: Codable, Equatable, Sendable {
    var affectedPrompt: String
    var problem: String
    var evidence: String
    var recommendedImprovement: String
    var expectedBenefit: String
}

struct AIEvaluationPromptImprovementReport: Codable, Equatable, Sendable {
    var generatedAt: Date
    var datasetName: String
    var recommendations: [AIEvaluationPromptImprovementRecommendation]
}

struct AIPromptVersionComparison: Codable, Equatable, Sendable {
    var identifier: String
    var baselineHash: String
    var comparisonHash: String
    var changedPrompts: [String]
}

struct AIPromptVersionComparisonReport: Codable, Equatable, Sendable {
    var generatedAt: Date
    var baselinePromptVersion: String
    var comparisonPromptVersion: String
    var changes: [AIPromptVersionComparison]
}

struct AIEvaluationGoldStandardReference: Codable, Equatable, Sendable {
    var noteID: String
    var subject: String
    var summary: String?
    var flashcards: [StudyFlashcard]?
    var quiz: [StudyQuizQuestion]?
    var conceptMap: [StudyConceptNode]?
    var learningInsights: StudyInsights?
    var knowledgeSnapshot: StudyKnowledgeSnapshot?
}

struct AIEvaluationGoldStandardNote: Codable, Equatable, Sendable {
    var noteID: String
    var subjectFolder: String
    var summaryURL: String?
    var flashcardsURL: String?
    var quizURL: String?
    var conceptMapURL: String?
    var learningInsightsURL: String?
    var knowledgeSnapshotURL: String?
}

struct AIEvaluationExternalReviewPackage: Codable, Equatable, Sendable {
    var evaluationDate: Date
    var noteID: String
    var noteName: String
    var appVersion: String
    var gitCommit: String
    var modelName: String
    var modelIdentifier: String
    var promptVersion: String
    var rawNote: String
    var promptsUsed: [AIEvaluationPromptSnapshot]
    var outputs: AIEvaluationOutputs
    var generationSettings: AIEvaluationGenerationSettings
    var reviewPrompt: String

    private enum CodingKeys: String, CodingKey {
        case evaluationDate = "evaluation_date"
        case noteID = "note_id"
        case noteName = "note_name"
        case appVersion = "app_version"
        case gitCommit = "git_commit"
        case modelName = "model_name"
        case modelIdentifier = "model_identifier"
        case promptVersion = "prompt_version"
        case rawNote = "raw_note"
        case promptsUsed = "prompts_used"
        case outputs
        case generationSettings = "generation_settings"
        case reviewPrompt = "review_prompt"
    }
}

struct AIEvaluationComparisonSummary: Codable, Equatable, Sendable {
    var title: String
    var baselineRunID: String
    var comparisonRunID: String
    var improvements: [String]
    var regressions: [String]
    var changedOutputs: [String]
    var scoreDelta: Double
}

struct AIEvaluationComparisonReport: Codable, Equatable, Sendable {
    var generatedAt: Date
    var title: String
    var baselineModel: String
    var comparisonModel: String
    var baselinePromptVersion: String
    var comparisonPromptVersion: String
    var noteSet: String
    var comparisons: [AIEvaluationComparisonSummary]

    private enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case title
        case baselineModel = "baseline_model"
        case comparisonModel = "comparison_model"
        case baselinePromptVersion = "baseline_prompt_version"
        case comparisonPromptVersion = "comparison_prompt_version"
        case noteSet = "note_set"
        case comparisons
    }
}

enum AIEvaluationSamples {
    static let notes: [AIEvaluationNote] = [
        AIEvaluationNote(
            id: "computer-science-lecture-01",
            title: "Computer Science Lecture",
            subject: "computer science lecture",
            rawNote: """
            # Computer Science Lecture

            Binary search tree operations rely on ordered traversal, recursion, and balancing tradeoffs. In class, the professor compared AVL trees with red-black trees and emphasized that search is logarithmic when the tree remains balanced. The lecture also covered amortized analysis for dynamic arrays and how recursion depth affects stack usage.
            """,
            expectedKeywords: ["binary search tree", "AVL", "red-black", "recursion", "amortized"],
            sourceFileName: "computer-science-lecture.md",
            tags: ["lecture", "computer-science"]
        ),
        AIEvaluationNote(
            id: "biology-lecture-01",
            title: "Biology Lecture",
            subject: "biology lecture",
            rawNote: """
            # Biology Lecture

            Cellular respiration converts glucose into ATP through glycolysis, the citric acid cycle, and oxidative phosphorylation. Mitochondria host the electron transport chain, and oxygen acts as the final electron acceptor. Enzyme activity depends on pH, temperature, and substrate concentration.
            """,
            expectedKeywords: ["cellular respiration", "ATP", "mitochondria", "electron transport chain", "enzyme"],
            sourceFileName: "biology-lecture.md",
            tags: ["lecture", "biology"]
        ),
        AIEvaluationNote(
            id: "mathematics-lecture-01",
            title: "Mathematics Lecture",
            subject: "mathematics lecture",
            rawNote: """
            # Mathematics Lecture

            The derivative measures instantaneous rate of change, while the integral measures accumulated area under a curve. The fundamental theorem of calculus links both ideas. We solved optimization problems by setting derivatives equal to zero and checking critical points with second derivative tests.
            """,
            expectedKeywords: ["derivative", "integral", "fundamental theorem", "optimization", "critical points"],
            sourceFileName: "mathematics-lecture.md",
            tags: ["lecture", "mathematics"]
        ),
        AIEvaluationNote(
            id: "history-lecture-01",
            title: "History Lecture",
            subject: "history lecture",
            rawNote: """
            # History Lecture

            The industrial revolution changed production, labor, and urban life. Mechanization increased output, but it also created harsh factory conditions and child labor concerns. The lecture connected these changes to migration patterns, social reform, and the rise of organized labor movements.
            """,
            expectedKeywords: ["industrial revolution", "mechanization", "child labor", "urban life", "labor movements"],
            sourceFileName: "history-lecture.md",
            tags: ["lecture", "history"]
        ),
        AIEvaluationNote(
            id: "literature-notes-01",
            title: "Literature Notes",
            subject: "literature notes",
            rawNote: """
            # Literature Notes

            In The Great Gatsby, Fitzgerald uses symbolism, unreliable narration, and recurring imagery to expose the gap between aspiration and reality. The green light represents desire and distance, while the valley of ashes reflects moral decay. Nick's perspective frames the critique of class and the American Dream.
            """,
            expectedKeywords: ["symbolism", "unreliable narration", "green light", "valley of ashes", "American Dream"],
            sourceFileName: "literature-notes.md",
            tags: ["literature", "analysis"]
        ),
        AIEvaluationNote(
            id: "meeting-notes-01",
            title: "Meeting Notes",
            subject: "meeting notes",
            rawNote: """
            # Meeting Notes

            Agenda item one: ship the onboarding redesign by Friday. Marketing needs the final screenshots, engineering needs accessibility review, and support wants a short FAQ. We agreed to delay the cloud onboarding experiment until the privacy copy is approved.
            """,
            expectedKeywords: ["onboarding", "Friday", "accessibility", "FAQ", "privacy copy"],
            sourceFileName: "meeting-notes.md",
            tags: ["meeting", "product"]
        ),
        AIEvaluationNote(
            id: "ocr-errors-01",
            title: "OCR Text With Errors",
            subject: "ocr text with recognition errors",
            rawNote: """
            # OCR Text With Errors

            Thc quict briwn fox jumpcd over thc lazy dog. The resuIts from the scan show rec0gnition err0rs, broken hyphens, and random capitalization. Neverthelcss, the note still mentions photosynthesis, chlorophyll, and light-dependent reactions.
            """,
            expectedKeywords: ["photosynthesis", "chlorophyll", "light-dependent reactions", "recognition errors", "scan"],
            sourceFileName: "ocr-errors.md",
            tags: ["ocr", "noisy"]
        ),
        AIEvaluationNote(
            id: "bullet-points-01",
            title: "Bullet Point Notes",
            subject: "bullet-point notes",
            rawNote: """
            # Bullet Point Notes

            - define hypothesis testing
            - null hypothesis is the default assumption
            - p-values help judge evidence
            - confidence intervals estimate ranges
            - beware of multiple comparisons
            """,
            expectedKeywords: ["hypothesis testing", "null hypothesis", "p-values", "confidence intervals", "multiple comparisons"],
            sourceFileName: "bullet-point-notes.md",
            tags: ["notes", "statistics"]
        ),
        AIEvaluationNote(
            id: "mixed-formatting-01",
            title: "Mixed Formatting Notes",
            subject: "mixed formatting",
            rawNote: """
            # Mixed Formatting Notes

            Heading: Supply and demand

            Supply curves rise with price. Demand curves fall with price. Equilibrium occurs where the two curves intersect. Example: a price ceiling below equilibrium can create shortages, while a price floor above equilibrium can create surpluses.
            """,
            expectedKeywords: ["supply", "demand", "equilibrium", "price ceiling", "price floor"],
            sourceFileName: "mixed-formatting.md",
            tags: ["economics", "mixed-formatting"]
        ),
        AIEvaluationNote(
            id: "long-transcript-01",
            title: "Long Transcript",
            subject: "long transcript",
            rawNote: """
            # Long Transcript

            Today we walked through a long project transcript about software architecture, memory pressure, incremental refactors, and quality assurance. The team compared monolith and modular designs, decided to centralize prompts, introduced caching, and planned a hidden diagnostics view. Later we discussed regression testing, model fallback behavior, and the importance of preserving public APIs while changing internals. The transcript continued with remarks about chunking, hierarchical summarization, and adaptive concurrency to protect low-memory systems.
            """,
            expectedKeywords: ["architecture", "caching", "diagnostics", "regression testing", "adaptive concurrency"],
            sourceFileName: "long-transcript.md",
            tags: ["transcript", "stress", "long"]
        )
    ]
}

extension AIEvaluationSamples {
    static var notesBySet: [AIEvaluationNoteSet: [AIEvaluationNote]] {
        var map: [AIEvaluationNoteSet: [AIEvaluationNote]] = [:]
        for note in notes {
            if note.tags.contains("lecture") {
                map[.lecture, default: []].append(note)
            }
            if note.subject.contains("ocr") || note.tags.contains("noisy") {
                map[.noisy, default: []].append(note)
            }
            if note.subject.contains("long") || note.tags.contains("long") {
                map[.longForm, default: []].append(note)
            }
            if note.rawNote.count < 360 {
                map[.shortForm, default: []].append(note)
            }
        }
        map[.all] = notes
        return map
    }
}
