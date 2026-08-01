import Foundation

struct PromptSchemaDescriptor: Codable, Equatable, Sendable {
    var name: String
    var description: String
    var requiredFields: [String]
    var jsonSchema: String
}

struct PromptCatalogEntry: Codable, Equatable, Sendable {
    var id: String
    var version: String
    var description: String
    var supportedProviders: [String]
    var inputType: String
    var outputType: String
    var expectedLatency: String
    var estimatedTokens: Int
}

struct PromptValidationIssue: Codable, Equatable, Sendable {
    var field: String
    var message: String
    var severity: PromptValidationSeverity
}

enum PromptValidationSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case error
}

enum PromptValidationStrategy: String, Codable, CaseIterable, Sendable {
    case strictJSON
    case typed
    case graphAware
    case heuristic
}

struct PromptValidationReport: Codable, Equatable, Sendable {
    var isValid: Bool
    var shouldRetry: Bool
    var confidence: Double
    var issues: [PromptValidationIssue]

    static let valid = PromptValidationReport(isValid: true, shouldRetry: false, confidence: 1.0, issues: [])
}

enum PromptValidationSummary {
    static func forRetry(_ report: PromptValidationReport) -> String {
        let issues = report.issues.map { "\($0.field): \($0.message)" }.joined(separator: "; ")
        return "The previous response failed validation. Fix the following issues and return only valid output: \(issues)"
    }
}

struct PromptRetryPolicy: Codable, Equatable, Sendable {
    var maxAttempts: Int
    var repairBeforeRetry: Bool
    var fallbackTemperature: Float

    static let standard = PromptRetryPolicy(maxAttempts: 2, repairBeforeRetry: true, fallbackTemperature: 0.0)
}

struct PromptDocument: Equatable, Sendable {
    var systemPrompt: String
    var userPrompt: String
    var temperature: Float
    var topP: Float
    var maxTokens: Int32
    var responseFormat: AIResponseFormat
    var confidenceRequirement: Double
    var retryPolicy: PromptRetryPolicy
    var validationStrategy: PromptValidationStrategy
    var schema: PromptSchemaDescriptor
    var metadata: [String: String]

    static func text(
        systemPrompt: String,
        userPrompt: String,
        temperature: Float = 0.3,
        topP: Float = 0.92,
        maxTokens: Int32 = 768,
        confidenceRequirement: Double = 0.7,
        retryPolicy: PromptRetryPolicy = .standard,
        validationStrategy: PromptValidationStrategy = .typed,
        schema: PromptSchemaDescriptor = PromptSchemaDescriptor(name: "text", description: "Plain text", requiredFields: [], jsonSchema: ""),
        metadata: [String: String] = [:]
    ) -> PromptDocument {
        PromptDocument(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            responseFormat: .text,
            confidenceRequirement: confidenceRequirement,
            retryPolicy: retryPolicy,
            validationStrategy: validationStrategy,
            schema: schema,
            metadata: metadata
        )
    }

    static func json(
        systemPrompt: String,
        userPrompt: String,
        temperature: Float = 0.2,
        topP: Float = 0.9,
        maxTokens: Int32 = 768,
        confidenceRequirement: Double = 0.75,
        retryPolicy: PromptRetryPolicy = .standard,
        validationStrategy: PromptValidationStrategy = .strictJSON,
        schema: PromptSchemaDescriptor,
        metadata: [String: String] = [:]
    ) -> PromptDocument {
        PromptDocument(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            responseFormat: .json,
            confidenceRequirement: confidenceRequirement,
            retryPolicy: retryPolicy,
            validationStrategy: validationStrategy,
            schema: schema,
            metadata: metadata
        )
    }
}

struct PromptExecutionMetrics: Codable, Equatable, Sendable {
    var latency: TimeInterval
    var repairCount: Int
    var retryCount: Int
    var jsonValidity: Double
    var confidence: Double
    var hallucinationRate: Double
    var determinism: Double
    var tokenUsage: Int
}

struct PromptExecutionResult<Output> {
    var identifier: AIPromptIdentifier
    var version: AIPromptVersion
    var providerKind: AIProviderKind
    var modelIdentifier: String?
    var request: AIGenerationRequest
    var rawText: String
    var output: Output
    var validation: PromptValidationReport
    var metrics: PromptExecutionMetrics
    var repaired: Bool
    var retries: Int
}

struct PromptBuildContext: Sendable {
    var noteTitle: String = ""
    var noteText: String = ""
    var structuredKnowledge: StructuredKnowledge?
    var knowledgeSnapshot: StudyKnowledgeSnapshot?
    var knowledgeGraph: KnowledgeGraph?
    var selectedText: String?
    var userRequest: String?
    var providerKind: AIProviderKind = .localLlama
    var modelIdentifier: String?
    var noteSignature: String?
    var contextLimit: Int?

    init(
        noteTitle: String = "",
        noteText: String = "",
        structuredKnowledge: StructuredKnowledge? = nil,
        knowledgeSnapshot: StudyKnowledgeSnapshot? = nil,
        knowledgeGraph: KnowledgeGraph? = nil,
        selectedText: String? = nil,
        userRequest: String? = nil,
        providerKind: AIProviderKind = .localLlama,
        modelIdentifier: String? = nil,
        noteSignature: String? = nil,
        contextLimit: Int? = nil
    ) {
        self.noteTitle = noteTitle
        self.noteText = noteText
        self.structuredKnowledge = structuredKnowledge
        self.knowledgeSnapshot = knowledgeSnapshot
        self.knowledgeGraph = knowledgeGraph
        self.selectedText = selectedText
        self.userRequest = userRequest
        self.providerKind = providerKind
        self.modelIdentifier = modelIdentifier
        self.noteSignature = noteSignature
        self.contextLimit = contextLimit
    }
}
