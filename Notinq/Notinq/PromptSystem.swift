import Foundation

protocol PromptDefinition {
    associatedtype Input: Sendable
    associatedtype Output: Codable

    static var identifier: AIPromptIdentifier { get }
    static var version: AIPromptVersion { get }
    static var baseSystemPrompt: String { get }
    static var outputSchema: PromptSchemaDescriptor { get }
    static var defaultTemperature: Float { get }
    static var defaultTopP: Float { get }
    static var defaultMaxTokens: Int32 { get }
    static var retryPolicy: PromptRetryPolicy { get }
    static var confidenceRequirement: Double { get }
    static var validationStrategy: PromptValidationStrategy { get }

    static func buildDocument(input: Input, context: PromptBuildContext) -> PromptDocument
    static func validate(output: Output, input: Input, context: PromptBuildContext) -> PromptValidationReport
}

extension PromptDefinition {
    static var definition: AIPromptDefinition {
        AIPromptDefinition(
            identifier: identifier,
            version: version,
            systemPrompt: baseSystemPrompt,
            outputDescription: outputSchema.description
        )
    }
}

protocol AnyPromptDefinition {
    var identifier: AIPromptIdentifier { get }
    var version: AIPromptVersion { get }
    var schema: PromptSchemaDescriptor { get }
    var defaultTemperature: Float { get }
    var defaultTopP: Float { get }
    var defaultMaxTokens: Int32 { get }
    var retryPolicy: PromptRetryPolicy { get }
    var confidenceRequirement: Double { get }
    var validationStrategy: PromptValidationStrategy { get }
    var inputTypeName: String { get }
    var outputTypeName: String { get }
    var systemPrompt: String { get }
    var outputDescription: String { get }
    func buildRequest(from anyInput: Any, context: PromptBuildContext) throws -> AIGenerationRequest
}

struct AnyPromptBox<Base: PromptDefinition>: AnyPromptDefinition {
    let baseType: Base.Type

    var identifier: AIPromptIdentifier { Base.identifier }
    var version: AIPromptVersion { Base.version }
    var schema: PromptSchemaDescriptor { Base.outputSchema }
    var defaultTemperature: Float { Base.defaultTemperature }
    var defaultTopP: Float { Base.defaultTopP }
    var defaultMaxTokens: Int32 { Base.defaultMaxTokens }
    var retryPolicy: PromptRetryPolicy { Base.retryPolicy }
    var confidenceRequirement: Double { Base.confidenceRequirement }
    var validationStrategy: PromptValidationStrategy { Base.validationStrategy }
    var inputTypeName: String { String(reflecting: Base.Input.self) }
    var outputTypeName: String { String(reflecting: Base.Output.self) }
    var systemPrompt: String { Base.baseSystemPrompt }
    var outputDescription: String { Base.outputSchema.description }

    func buildRequest(from anyInput: Any, context: PromptBuildContext) throws -> AIGenerationRequest {
        guard let input = anyInput as? Base.Input else {
            throw NSError(domain: "Notinq.PromptSystem", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid prompt input type for \(Base.identifier.rawValue)."])
        }
        let document = Base.buildDocument(input: input, context: context)
        return AIGenerationRequest(
            prompt: document.userPrompt,
            systemPrompt: document.systemPrompt,
            maxTokens: document.maxTokens,
            temperature: document.temperature,
            topP: document.topP,
            responseFormat: document.responseFormat,
            contextLimit: context.contextLimit,
            metadata: document.metadata.merging([
                "prompt": Base.identifier.rawValue,
                "promptVersion": "\(Base.version.major).\(Base.version.minor).\(Base.version.patch)"
            ], uniquingKeysWith: { _, new in new })
        )
    }
}

struct PromptExecutionSummary: Codable, Equatable, Sendable {
    var promptID: String
    var version: String
    var providerKind: AIProviderKind
    var modelIdentifier: String?
    var metrics: PromptExecutionMetrics
    var validation: PromptValidationReport
}
