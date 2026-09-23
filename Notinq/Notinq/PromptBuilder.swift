import Foundation

struct PromptBuilder {
    static func buildDocument(
        role: String,
        task: String,
        input: String = "",
        rules: [String],
        schema: PromptSchemaDescriptor,
        confidenceRequirement: Double = 0.75,
        failureRules: [String],
        validationRules: [String] = [],
        body: String = "",
        temperature: Float,
        topP: Float,
        maxTokens: Int32,
        responseFormat: AIResponseFormat,
        metadata: [String: String] = [:]
    ) -> PromptDocument {
        let inputText = input.isEmpty ? body : input
        let sections = [
            PromptFragments.role(role),
            PromptFragments.objective(task),
            PromptFragments.input(inputText),
            PromptFragments.constraints(PromptFragments.sharedRules() + rules + validationRules.map { "Validation: \($0)" }),
            PromptFragments.outputSchema(schema),
            PromptFragments.failureRules(failureRules)
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return PromptDocument(
            systemPrompt: sections.joined(separator: "\n\n"),
            userPrompt: "",
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            responseFormat: responseFormat,
            confidenceRequirement: confidenceRequirement,
            retryPolicy: .standard,
            validationStrategy: responseFormat == .json ? .strictJSON : .typed,
            schema: schema,
            metadata: metadata
        )
    }
}
