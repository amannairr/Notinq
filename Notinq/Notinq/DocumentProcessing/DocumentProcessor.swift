import Foundation

protocol DocumentProcessingNormalizing {
    func normalize(title: String, text: String) -> ProcessedDocument
}

final class DocumentProcessor: DocumentProcessingNormalizing {
    static let shared = DocumentProcessor()

    private init() {}

    func normalize(title: String, text: String) -> ProcessedDocument {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lineEndingNormalized = normalizeLineEndings(text)
        let compatibilityNormalized = lineEndingNormalized.precomposedStringWithCompatibilityMapping
        let rawLines = compatibilityNormalized.components(separatedBy: "\n")
        var normalizedLines: [String] = []
        var inCodeBlock = false
        var lastLineWasBlank = false

        for rawLine in rawLines {
            let trimmedMarker = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedMarker.hasPrefix("```") {
                let fenceLine = trimmedMarker.trimmingCharacters(in: .whitespaces)
                normalizedLines.append(fenceLine)
                inCodeBlock.toggle()
                lastLineWasBlank = false
                continue
            }

            let normalizedLine: String
            if inCodeBlock {
                normalizedLine = rawLine.replacingOccurrences(of: "\u{00A0}", with: " ")
                    .replacingOccurrences(of: "\t", with: "    ")
                    .trimmingCharacters(in: .whitespaces)
            } else {
                normalizedLine = normalizeContentLine(rawLine)
            }

            if normalizedLine.isEmpty {
                if lastLineWasBlank {
                    continue
                }
                normalizedLines.append("")
                lastLineWasBlank = true
            } else {
                normalizedLines.append(normalizedLine)
                lastLineWasBlank = false
            }
        }

        let trimmedLines = trimOuterBlankLines(normalizedLines)
        let normalizedText = trimmedLines.joined(separator: "\n")
        return ProcessedDocument(
            title: normalizedTitle,
            originalText: text,
            normalizedText: normalizedText,
            lines: trimmedLines,
            contentHash: ProcessedDocument.contentHash(for: normalizedTitle, text: normalizedText)
        )
    }

    private func normalizeLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func normalizeContentLine(_ rawLine: String) -> String {
        var line = rawLine
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "„", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "…", with: "...")
            .replacingOccurrences(of: "•", with: "-")
            .replacingOccurrences(of: "·", with: "-")

        line = line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return line
    }

    private func trimOuterBlankLines(_ lines: [String]) -> [String] {
        var result = lines
        while result.first?.isEmpty == true {
            result.removeFirst()
        }
        while result.last?.isEmpty == true {
            result.removeLast()
        }
        return result
    }
}
