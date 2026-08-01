import Foundation

protocol PromptOutputValidator {
    associatedtype Output: Codable & Sendable
    static func validate(output: Output, rawText: String, context: PromptBuildContext) -> PromptValidationReport
}

enum PromptValidatorEngine {
    static func validateRequiredFields(_ fields: [String: String], required: [String]) -> [PromptValidationIssue] {
        required.compactMap { field in
            let value = fields[field]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard value.isEmpty else { return nil }
            return PromptValidationIssue(field: field, message: "Missing required field", severity: .error)
        }
    }

    static func validateDuplicates(_ values: [String], field: String) -> [PromptValidationIssue] {
        var seen = Set<String>()
        var issues: [PromptValidationIssue] = []
        for value in values {
            let key = normalize(value)
            guard !key.isEmpty else { continue }
            if !seen.insert(key).inserted {
                issues.append(PromptValidationIssue(field: field, message: "Duplicate content: \(value)", severity: .warning))
            }
        }
        return issues
    }

    static func validateConfidence(_ values: [Double], minimum: Double, field: String) -> [PromptValidationIssue] {
        guard !values.isEmpty else { return [] }
        let below = values.filter { $0 < minimum }
        guard !below.isEmpty else { return [] }
        return [PromptValidationIssue(field: field, message: "\(below.count) values are below confidence threshold", severity: .warning)]
    }

    static func validateConsistency(_ conditions: [Bool], field: String, message: String) -> [PromptValidationIssue] {
        conditions.allSatisfy { $0 } ? [] : [PromptValidationIssue(field: field, message: message, severity: .warning)]
    }

    static func genericJSONValidation(rawText: String, schema: PromptSchemaDescriptor) -> PromptValidationReport {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PromptValidationReport(isValid: false, shouldRetry: true, confidence: 0, issues: [
                PromptValidationIssue(field: schema.name, message: "Empty response", severity: .error)
            ])
        }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object) {
            return PromptValidationReport(isValid: true, shouldRetry: false, confidence: 1, issues: [])
        }

        return PromptValidationReport(isValid: false, shouldRetry: true, confidence: 0.2, issues: [
            PromptValidationIssue(field: schema.name, message: "Response is not valid JSON", severity: .error)
        ])
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

