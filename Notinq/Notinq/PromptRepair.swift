import Foundation

enum PromptRepairer {
    static func repairJSONString(_ text: String) -> String? {
        let cleaned = stripMarkdownFences(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if let exact = extractBalancedJSON(from: cleaned) {
            return normalizeJSONSyntax(exact)
        }

        if let objectRange = cleaned.range(of: #"\{[\s\S]*\}"#, options: .regularExpression) {
            return normalizeJSONSyntax(String(cleaned[objectRange]))
        }

        if let arrayRange = cleaned.range(of: #"\[[\s\S]*\]"#, options: .regularExpression) {
            return normalizeJSONSyntax(String(cleaned[arrayRange]))
        }

        return nil
    }

    static func repair<T: Decodable>(_ text: String, as type: T.Type) -> T? {
        let candidates = [
            text,
            repairJSONString(text) ?? ""
        ].filter { !$0.isEmpty }

        let decoder = JSONDecoder()
        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let value = try? decoder.decode(T.self, from: data) {
                return value
            }
        }
        return nil
    }

    private static func stripMarkdownFences(_ text: String) -> String {
        text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```JSON", with: "")
            .replacingOccurrences(of: "```", with: "")
    }

    private static func extractBalancedJSON(from text: String) -> String? {
        var depth = 0
        var startIndex: String.Index?
        var endIndex: String.Index?

        for index in text.indices {
            let character = text[index]
            if character == "{" || character == "[" {
                if startIndex == nil {
                    startIndex = index
                }
                depth += 1
            } else if character == "}" || character == "]" {
                depth -= 1
                if depth == 0 {
                    endIndex = text.index(after: index)
                    break
                }
            }
        }

        guard let startIndex, let endIndex else { return nil }
        return String(text[startIndex..<endIndex])
    }

    private static func normalizeJSONSyntax(_ text: String) -> String {
        text
            .replacingOccurrences(of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

