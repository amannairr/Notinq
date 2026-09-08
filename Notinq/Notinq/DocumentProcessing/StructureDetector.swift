import Foundation

protocol StructureDetecting {
    func detect(in document: ProcessedDocument) -> [DocumentBlock]
}

final class StructureDetector: StructureDetecting {
    static let shared = StructureDetector()

    private init() {}

    func detect(in document: ProcessedDocument) -> [DocumentBlock] {
        var blocks: [DocumentBlock] = []
        let lines = document.lines
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let startLine = index
                let fenceLine = trimmed
                index += 1
                var contentLines: [String] = [line]
                while index < lines.count {
                    let candidate = lines[index]
                    contentLines.append(candidate)
                    if candidate.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
                        break
                    }
                    index += 1
                }

                let body = contentLines.dropFirst().dropLast().joined(separator: "\n")
                blocks.append(
                    DocumentBlock(
                        id: blockID(kind: .codeBlock, startLine: startLine, endLine: min(index, lines.count - 1)),
                        kind: .codeBlock,
                        content: contentLines.joined(separator: "\n"),
                        normalizedContent: body,
                        startLine: startLine,
                        endLine: min(index, lines.count - 1),
                        headingLevel: nil,
                        listStyle: nil,
                        listItems: [],
                        tableRows: [],
                        codeLanguage: language(fromFence: fenceLine),
                        equation: nil,
                        quoteLevel: 0,
                        sectionID: nil
                    )
                )
                index += 1
                continue
            }

            if let heading = headingMatch(for: trimmed) {
                blocks.append(
                    DocumentBlock(
                        id: blockID(kind: .heading, startLine: index, endLine: index),
                        kind: .heading,
                        content: line,
                        normalizedContent: heading.title,
                        startLine: index,
                        endLine: index,
                        headingLevel: heading.level,
                        listStyle: nil,
                        listItems: [],
                        tableRows: [],
                        codeLanguage: nil,
                        equation: nil,
                        quoteLevel: 0,
                        sectionID: nil
                    )
                )
                index += 1
                continue
            }

            if let quote = quoteMatch(for: trimmed) {
                let startLine = index
                var contentLines: [String] = [line]
                var values: [String] = [quote]
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard nextTrimmed.hasPrefix(">") else { break }
                    contentLines.append(next)
                    values.append(quoteMatch(for: nextTrimmed) ?? nextTrimmed)
                    index += 1
                }
                blocks.append(
                    DocumentBlock(
                        id: blockID(kind: .quote, startLine: startLine, endLine: max(startLine, index - 1)),
                        kind: .quote,
                        content: contentLines.joined(separator: "\n"),
                        normalizedContent: values.joined(separator: "\n"),
                        startLine: startLine,
                        endLine: max(startLine, index - 1),
                        headingLevel: nil,
                        listStyle: nil,
                        listItems: [],
                        tableRows: [],
                        codeLanguage: nil,
                        equation: nil,
                        quoteLevel: 1,
                        sectionID: nil
                    )
                )
                continue
            }

            if let firstListMatch = listMatch(for: trimmed) {
                let startLine = index
                var contentLines: [String] = [line]
                var items: [String] = [firstListMatch.text]
                let listStyle = firstListMatch.style
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let nextListMatch = listMatch(for: nextTrimmed), nextListMatch.style == listStyle else { break }
                    contentLines.append(next)
                    items.append(nextListMatch.text)
                    index += 1
                }

                blocks.append(
                    DocumentBlock(
                        id: blockID(kind: listStyle == .numbered ? .numberedList : .bulletedList, startLine: startLine, endLine: max(startLine, index - 1)),
                        kind: listStyle == .numbered ? .numberedList : .bulletedList,
                        content: contentLines.joined(separator: "\n"),
                        normalizedContent: items.joined(separator: "\n"),
                        startLine: startLine,
                        endLine: max(startLine, index - 1),
                        headingLevel: nil,
                        listStyle: listStyle,
                        listItems: items,
                        tableRows: [],
                        codeLanguage: nil,
                        equation: nil,
                        quoteLevel: 0,
                        sectionID: nil
                    )
                )
                continue
            }

            if isTableRow(trimmed) {
                let startLine = index
                var contentLines: [String] = [line]
                var rows: [[String]] = [splitTableRow(trimmed)]
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard isTableRow(nextTrimmed) else { break }
                    contentLines.append(next)
                    rows.append(splitTableRow(nextTrimmed))
                    index += 1
                }

                blocks.append(
                    DocumentBlock(
                        id: blockID(kind: .table, startLine: startLine, endLine: max(startLine, index - 1)),
                        kind: .table,
                        content: contentLines.joined(separator: "\n"),
                        normalizedContent: rows.map { $0.joined(separator: " | ") }.joined(separator: "\n"),
                        startLine: startLine,
                        endLine: max(startLine, index - 1),
                        headingLevel: nil,
                        listStyle: nil,
                        listItems: [],
                        tableRows: rows,
                        codeLanguage: nil,
                        equation: nil,
                        quoteLevel: 0,
                        sectionID: nil
                    )
                )
                continue
            }

            if isEquationLine(trimmed) {
                let startLine = index
                var contentLines: [String] = [line]
                var equations: [String] = [trimmed]
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard isEquationLine(nextTrimmed) else { break }
                    contentLines.append(next)
                    equations.append(nextTrimmed)
                    index += 1
                }

                blocks.append(
                    DocumentBlock(
                        id: blockID(kind: .equation, startLine: startLine, endLine: max(startLine, index - 1)),
                        kind: .equation,
                        content: contentLines.joined(separator: "\n"),
                        normalizedContent: equations.joined(separator: "\n"),
                        startLine: startLine,
                        endLine: max(startLine, index - 1),
                        headingLevel: nil,
                        listStyle: nil,
                        listItems: [],
                        tableRows: [],
                        codeLanguage: nil,
                        equation: equations.first,
                        quoteLevel: 0,
                        sectionID: nil
                    )
                )
                continue
            }

            let startLine = index
            var paragraphLines: [String] = [line]
            index += 1
            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
                if nextTrimmed.isEmpty ||
                    nextTrimmed.hasPrefix("```") ||
                    headingMatch(for: nextTrimmed) != nil ||
                    quoteMatch(for: nextTrimmed) != nil ||
                    listMatch(for: nextTrimmed) != nil ||
                    isTableRow(nextTrimmed) ||
                    isEquationLine(nextTrimmed) {
                    break
                }
                paragraphLines.append(next)
                index += 1
            }

            blocks.append(
                DocumentBlock(
                    id: blockID(kind: .paragraph, startLine: startLine, endLine: max(startLine, index - 1)),
                    kind: .paragraph,
                    content: paragraphLines.joined(separator: "\n"),
                    normalizedContent: paragraphLines.joined(separator: "\n"),
                    startLine: startLine,
                    endLine: max(startLine, index - 1),
                    headingLevel: nil,
                    listStyle: nil,
                    listItems: [],
                    tableRows: [],
                    codeLanguage: nil,
                    equation: nil,
                    quoteLevel: 0,
                    sectionID: nil
                )
            )
        }

        return blocks
    }

    private func headingMatch(for line: String) -> (level: Int, title: String)? {
        if line.hasPrefix("#") {
            let level = line.prefix { $0 == "#" }.count
            let title = line.drop(while: { $0 == "#" || $0 == " " }).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return (max(1, level), title)
        }

        if let numberRange = line.range(of: #"^\d+(?:\.\d+)*[.)]?\s+"#, options: .regularExpression) {
            let numericPrefix = String(line[..<numberRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let level = max(1, numericPrefix.split(separator: ".").count)
            let title = String(line[numberRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.first?.isUppercase == true else { return nil }
            return (level, title)
        }

        if line.hasSuffix(":") && line.count <= 80 && line.first?.isUppercase == true {
            return (1, String(line.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if line.count <= 72, line.first?.isUppercase == true, line.rangeOfCharacter(from: .punctuationCharacters) == nil {
            let wordCount = line.split { $0.isWhitespace }.count
            if wordCount <= 8 {
                return (1, line)
            }
        }

        return nil
    }

    private func listMatch(for line: String) -> (style: DocumentListStyle, text: String)? {
        if let range = line.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
            let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (.bullet, text)
        }

        if let range = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (.numbered, text)
        }

        return nil
    }

    private func quoteMatch(for line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isTableRow(_ line: String) -> Bool {
        let pipeCount = line.filter { $0 == "|" }.count
        return pipeCount >= 2 && line.split(separator: "|").count >= 3
    }

    private func splitTableRow(_ line: String) -> [String] {
        line.split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func isEquationLine(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        if line.hasPrefix("$") || line.hasPrefix("\\[") || line.hasPrefix("$$") {
            return true
        }

        let operators: Set<Character> = ["=", "→", "⇒", "+", "−", "×", "÷", "^"]
        let operatorCount = line.filter { operators.contains($0) }.count
        guard operatorCount > 0 else { return false }

        if line.hasSuffix(".") || line.hasSuffix("?") || line.hasSuffix("!") {
            return false
        }

        let wordCount = line.split { $0.isWhitespace }.count
        return wordCount <= 12 || operatorCount >= 2
    }

    private func language(fromFence fenceLine: String) -> String? {
        let language = fenceLine.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
        return language.isEmpty ? nil : String(language)
    }

    private func blockID(kind: DocumentBlockKind, startLine: Int, endLine: Int) -> String {
        "\(kind.rawValue)-\(startLine)-\(endLine)"
    }
}
