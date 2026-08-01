import Foundation
import CryptoKit

enum DocumentSectionKind: String, Codable, CaseIterable, Sendable {
    case heading
    case paragraph
    case list
    case numberedSection
    case codeBlock
    case equation
    case table
}

struct DocumentSection: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var kind: DocumentSectionKind
    var title: String = ""
    var content: String
    var level: Int = 0
    var startLine: Int
    var endLine: Int
}

struct DocumentListItem: Codable, Equatable, Sendable {
    var text: String
    var line: Int
    var isNumbered: Bool
}

struct DocumentCodeBlock: Codable, Equatable, Sendable {
    var content: String
    var language: String?
    var startLine: Int
    var endLine: Int
}

struct DocumentTable: Codable, Equatable, Sendable {
    var rows: [[String]]
    var startLine: Int
    var endLine: Int
}

struct DocumentComplexityEstimate: Codable, Equatable, Sendable {
    var tokenEstimate: Int
    var sentenceCount: Int
    var headingCount: Int
    var listCount: Int
    var codeBlockCount: Int
    var equationCount: Int
    var tableCount: Int
    var complexityScore: Double
}

struct DocumentStructure: Codable, Equatable, Sendable {
    var title: String
    var originalText: String
    var normalizedText: String
    var cleanedText: String
    var sourceSignature: String
    var sections: [DocumentSection]
    var headings: [String]
    var lists: [DocumentListItem]
    var codeBlocks: [DocumentCodeBlock]
    var equations: [String]
    var tables: [DocumentTable]
    var complexity: DocumentComplexityEstimate
}

final class DocumentPreprocessor {
    static let shared = DocumentPreprocessor()

    private init() {}

    func preprocess(title: String, text: String) -> DocumentStructure {
        let normalized = normalize(text)
        let lines = normalized.components(separatedBy: .newlines)
        let sections = buildSections(from: lines)
        let headings = sections.filter { $0.kind == .heading || $0.kind == .numberedSection }.map { $0.title.isEmpty ? $0.content : $0.title }
        let lists = extractLists(from: lines)
        let codeBlocks = extractCodeBlocks(from: lines)
        let equations = extractEquations(from: lines)
        let tables = extractTables(from: lines)
        let complexity = estimateComplexity(
            text: normalized,
            headings: headings,
            lists: lists,
            codeBlocks: codeBlocks,
            equations: equations,
            tables: tables
        )

        return DocumentStructure(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            originalText: text,
            normalizedText: normalized,
            cleanedText: normalized,
            sourceSignature: signature(for: title, text: normalized),
            sections: sections,
            headings: headings,
            lists: lists,
            codeBlocks: codeBlocks,
            equations: equations,
            tables: tables,
            complexity: complexity
        )
    }

    func normalize(_ text: String) -> String {
        let normalizedLineBreaks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let cleanedLines = normalizedLineBreaks
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .replacingOccurrences(of: "—", with: "-")
                    .replacingOccurrences(of: "–", with: "-")
                    .replacingOccurrences(of: "•", with: "-")
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .reduce(into: [String]()) { result, line in
                if line.isEmpty {
                    if result.last?.isEmpty == true {
                        return
                    }
                    result.append("")
                } else {
                    result.append(line)
                }
            }

        return cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildSections(from lines: [String]) -> [DocumentSection] {
        var sections: [DocumentSection] = []
        var currentLines: [String] = []
        var currentStart = 0
        var currentKind: DocumentSectionKind = .paragraph
        var currentTitle = ""
        var currentLevel = 0

        func flush(endLine: Int) {
            let content = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                currentLines.removeAll()
                return
            }
            sections.append(
                DocumentSection(
                    kind: currentKind,
                    title: currentTitle,
                    content: content,
                    level: currentLevel,
                    startLine: max(0, currentStart),
                    endLine: max(currentStart, endLine)
                )
            )
            currentLines.removeAll()
        }

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let detected = classify(line)

            if detected.kind == .heading || detected.kind == .numberedSection {
                flush(endLine: index)
                currentStart = index
                if let kind = detected.kind {
                    currentKind = kind
                }
                currentTitle = detected.title ?? line
                currentLevel = detected.level ?? 0
                currentLines = [line]
                continue
            }

            if currentLines.isEmpty {
                currentStart = index
            }
            currentLines.append(line)
            if let kind = detected.kind {
                currentKind = kind
            } else {
                currentKind = .paragraph
            }
        }

        flush(endLine: max(lines.count - 1, 0))
        return sections
    }

    private func extractLists(from lines: [String]) -> [DocumentListItem] {
        lines.enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if let match = trimmed.range(of: #"^(\-|\*|\+)\s+"#, options: .regularExpression) {
                let text = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return DocumentListItem(text: text, line: index + 1, isNumbered: false)
            }

            if let match = trimmed.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
                let text = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return DocumentListItem(text: text, line: index + 1, isNumbered: true)
            }

            return nil
        }
    }

    private func extractCodeBlocks(from lines: [String]) -> [DocumentCodeBlock] {
        var blocks: [DocumentCodeBlock] = []
        var inBlock = false
        var currentStart = 0
        var language: String?
        var buffer: [String] = []

        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("```") {
                if inBlock {
                    blocks.append(DocumentCodeBlock(content: buffer.joined(separator: "\n"), language: language, startLine: currentStart + 1, endLine: index + 1))
                    inBlock = false
                    buffer.removeAll()
                    language = nil
                } else {
                    inBlock = true
                    currentStart = index
                    let suffix = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                    language = suffix.isEmpty ? nil : String(suffix)
                }
                continue
            }

            if inBlock {
                buffer.append(rawLine)
            }
        }

        return blocks
    }

    private func extractEquations(from lines: [String]) -> [String] {
        lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let looksLikeEquation = trimmed.contains("=") || trimmed.contains("->") || trimmed.contains("→") || trimmed.contains("^")
            return looksLikeEquation ? trimmed : nil
        }
    }

    private func extractTables(from lines: [String]) -> [DocumentTable] {
        var tables: [DocumentTable] = []
        var currentRows: [[String]] = []
        var currentStart = 0

        func flush(endLine: Int) {
            guard currentRows.count >= 2 else {
                currentRows.removeAll()
                return
            }
            tables.append(DocumentTable(rows: currentRows, startLine: currentStart + 1, endLine: endLine + 1))
            currentRows.removeAll()
        }

        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if cells.count >= 3 {
                if currentRows.isEmpty {
                    currentStart = index
                }
                currentRows.append(cells)
            } else if !currentRows.isEmpty {
                flush(endLine: index - 1)
            }
        }

        if !currentRows.isEmpty {
            flush(endLine: max(lines.count - 1, 0))
        }

        return tables
    }

    private func estimateComplexity(
        text: String,
        headings: [String],
        lists: [DocumentListItem],
        codeBlocks: [DocumentCodeBlock],
        equations: [String],
        tables: [DocumentTable]
    ) -> DocumentComplexityEstimate {
        let words = text.split { $0.isWhitespace || $0.isNewline }
        let sentenceCount = max(1, text.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)
        let tokenEstimate = max(1, words.count / 4)
        let structureScore = Double(headings.count) * 0.08 + Double(lists.count) * 0.05 + Double(codeBlocks.count) * 0.12 + Double(equations.count) * 0.07 + Double(tables.count) * 0.1
        let lexicalScore = min(1.0, Double(tokenEstimate) / 900.0)
        let complexityScore = min(1.0, 0.18 + structureScore + lexicalScore)

        return DocumentComplexityEstimate(
            tokenEstimate: tokenEstimate,
            sentenceCount: sentenceCount,
            headingCount: headings.count,
            listCount: lists.count,
            codeBlockCount: codeBlocks.count,
            equationCount: equations.count,
            tableCount: tables.count,
            complexityScore: complexityScore
        )
    }

    private func classify(_ line: String) -> (kind: DocumentSectionKind?, title: String?, level: Int?) {
        guard !line.isEmpty else { return (nil, nil, nil) }

        if line.hasPrefix("#") {
            let hashes = line.prefix { $0 == "#" }.count
            let title = line.drop(while: { $0 == "#" || $0 == " " })
            return (.heading, String(title), hashes)
        }

        if let match = line.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
            let title = String(line[match.upperBound...])
            return (.numberedSection, title, 1)
        }

        if line.hasSuffix(":") && line.count < 80 {
            return (.heading, String(line.dropLast()), 1)
        }

        if line.count < 70, line.first?.isUppercase == true {
            return (.heading, line, 1)
        }

        if line.contains("|"), line.split(separator: "|").count >= 3 {
            return (.table, nil, nil)
        }

        if line.contains("=") || line.contains("->") || line.contains("→") || line.contains("^") {
            return (.equation, nil, nil)
        }

        if line.hasPrefix("-") || line.hasPrefix("*") || line.hasPrefix("+") {
            return (.list, nil, nil)
        }

        return (.paragraph, nil, nil)
    }

    func signature(for title: String, text: String) -> String {
        let payload = [title, text].joined(separator: "\u{241E}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
