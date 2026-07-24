import AppKit
import Foundation

enum MarkdownRichTextRenderer {
    private static let semanticSectionTitleMap: [String: String] = [
        "question": "Question",
        "questions": "Question",
        "answer": "Answer",
        "answers": "Answer",
        "explanation": "Explanation",
        "explanations": "Explanation",
        "summary": "Summary",
        "summaries": "Summary",
        "key point": "Key Points",
        "key points": "Key Points",
        "keypoints": "Key Points",
        "flashcard": "Flashcards",
        "flashcards": "Flashcards",
        "takeaway": "Summary",
        "takeaways": "Summary",
        "definition": "Definition",
        "definitions": "Definition",
        "example": "Examples",
        "examples": "Examples",
        "review": "Review",
        "reviews": "Review",
        "notes": "Notes",
        "note": "Notes",
        "quiz": "Quiz",
        "check": "Check"
    ]

    static func render(
        _ markdown: String,
        baseFontSize: CGFloat = 15.5,
        baseAttributes: [NSAttributedString.Key: Any] = [:]
    ) -> NSAttributedString {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let semanticNormalized = canonicalizeSemanticSectionMarkers(in: normalized)

        let lines = semanticNormalized.components(separatedBy: "\n")
        let result = NSMutableAttributedString()
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if result.length > 0, !result.string.hasSuffix("\n\n") {
                    result.append(NSAttributedString(string: "\n"))
                }
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let codeBlock = collectCodeBlock(lines: lines, startIndex: index)
                result.append(renderCodeBlock(codeBlock.lines, baseFontSize: baseFontSize, baseAttributes: baseAttributes))
                index = codeBlock.nextIndex
                continue
            }

            if let headingLevel = headingLevel(for: trimmed) {
                result.append(renderHeading(trimmed, level: headingLevel, baseFontSize: baseFontSize, baseAttributes: baseAttributes))
                index += 1
                continue
            }

            if let semanticSectionTitle = semanticSectionTitle(for: trimmed) {
                result.append(renderSemanticSectionHeading(semanticSectionTitle, baseFontSize: baseFontSize, baseAttributes: baseAttributes))
                index += 1
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                let quoteBlock = collectContiguousLines(lines: lines, startIndex: index) { line in
                    let lineTrimmed = line.trimmingCharacters(in: .whitespaces)
                    return lineTrimmed.hasPrefix("> ") || lineTrimmed == ">"
                }
                result.append(renderQuoteBlock(quoteBlock.lines, baseFontSize: baseFontSize, baseAttributes: baseAttributes))
                index = quoteBlock.nextIndex
                continue
            }

            if isListLine(trimmed) {
                let listBlock = collectContiguousLines(lines: lines, startIndex: index) { line in
                    isListLine(line.trimmingCharacters(in: .whitespaces))
                }
                result.append(renderListBlock(listBlock.lines, baseFontSize: baseFontSize, baseAttributes: baseAttributes))
                index = listBlock.nextIndex
                continue
            }

            let paragraphBlock = collectContiguousLines(lines: lines, startIndex: index) { line in
                let lineTrimmed = line.trimmingCharacters(in: .whitespaces)
                return !lineTrimmed.isEmpty && !lineTrimmed.hasPrefix("```") && headingLevel(for: lineTrimmed) == nil && !lineTrimmed.hasPrefix("> ") && lineTrimmed != ">" && !isListLine(lineTrimmed)
            }
            result.append(renderParagraph(paragraphBlock.lines, baseFontSize: baseFontSize, baseAttributes: baseAttributes))
            index = paragraphBlock.nextIndex
        }

        if result.length > 0, result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        return result
    }

    private static func renderHeading(
        _ line: String,
        level: Int,
        baseFontSize: CGFloat,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let text = stripHeadingPrefix(line, level: level)
        if let semanticSectionTitle = semanticSectionTitle(for: text) {
            return renderSemanticSectionHeading(
                semanticSectionTitle,
                baseFontSize: baseFontSize,
                baseAttributes: baseAttributes
            )
        }

        let fontSize: CGFloat
        let weight: NSFont.Weight
        let spacingBefore: CGFloat
        let spacingAfter: CGFloat

        switch level {
        case 1:
            fontSize = baseFontSize + 9
            weight = .bold
            spacingBefore = 10
            spacingAfter = 8
        case 2:
            fontSize = baseFontSize + 5
            weight = .semibold
            spacingBefore = 8
            spacingAfter = 6
        default:
            fontSize = baseFontSize + 2
            weight = .medium
            spacingBefore = 6
            spacingAfter = 5
        }

        let paragraph = makeParagraphStyle(lineSpacing: 5, paragraphSpacingBefore: spacingBefore, paragraphSpacingAfter: spacingAfter)
        let attributes = mergedAttributes(
            baseAttributes: baseAttributes,
            font: .systemFont(ofSize: fontSize, weight: weight),
            paragraphStyle: paragraph
        )
        return styledAttributedString(text, attributes: attributes)
    }

    private static func renderSemanticSectionHeading(
        _ title: String,
        baseFontSize: CGFloat,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let paragraph = makeParagraphStyle(lineSpacing: 3, paragraphSpacingBefore: 12, paragraphSpacingAfter: 8)
        paragraph.firstLineHeadIndent = 0
        paragraph.headIndent = 0
        paragraph.tailIndent = 0

        let attributes = mergedAttributes(
            baseAttributes: baseAttributes,
            font: .systemFont(ofSize: baseFontSize + 1.75, weight: .semibold),
            foregroundColor: semanticAccentColor(),
            paragraphStyle: paragraph,
            backgroundColor: semanticBadgeBackgroundColor()
        )

        return styledAttributedString(title, attributes: attributes)
    }

    private static func renderParagraph(
        _ lines: [String],
        baseFontSize: CGFloat,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let text = lines.joined(separator: " ")
        let paragraph = makeParagraphStyle(lineSpacing: 6, paragraphSpacingBefore: 0, paragraphSpacingAfter: 10)
        let attributes = mergedAttributes(
            baseAttributes: baseAttributes,
            font: .systemFont(ofSize: baseFontSize, weight: .regular),
            paragraphStyle: paragraph
        )
        return styledAttributedString(text, attributes: attributes)
    }

    private static func renderQuoteBlock(
        _ lines: [String],
        baseFontSize: CGFloat,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let text = lines
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix(">") ? String(trimmed.drop(while: { $0 == ">" || $0 == " " })) : trimmed
            }
            .joined(separator: " ")

        let paragraph = makeParagraphStyle(lineSpacing: 5, paragraphSpacingBefore: 2, paragraphSpacingAfter: 8)
        paragraph.firstLineHeadIndent = 18
        paragraph.headIndent = 18
        paragraph.tailIndent = -10

        let attributes = mergedAttributes(
            baseAttributes: baseAttributes,
            font: NSFontManager.shared.convert(.systemFont(ofSize: baseFontSize), toHaveTrait: .italicFontMask),
            foregroundColor: NSColor.secondaryLabelColor,
            paragraphStyle: paragraph,
            backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.25)
        )

        return styledAttributedString(text, attributes: attributes)
    }

    private static func renderListBlock(
        _ lines: [String],
        baseFontSize: CGFloat,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let (prefix, text) = listPrefixAndText(trimmed)
            let paragraph = makeParagraphStyle(lineSpacing: 5, paragraphSpacingBefore: 0, paragraphSpacingAfter: index == lines.count - 1 ? 8 : 2)
            paragraph.firstLineHeadIndent = 18
            paragraph.headIndent = 18
            paragraph.tailIndent = -10

            let lineAttributes = mergedAttributes(
                baseAttributes: baseAttributes,
                font: .systemFont(ofSize: baseFontSize, weight: .regular),
                paragraphStyle: paragraph
            )

            let item = NSMutableAttributedString(string: prefix, attributes: lineAttributes)
            let content = styledAttributedString(text, attributes: lineAttributes)
            item.append(content)
            result.append(item)
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
    }

    private static func renderCodeBlock(
        _ lines: [String],
        baseFontSize: CGFloat,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let text = lines.joined(separator: "\n")
        let paragraph = makeParagraphStyle(lineSpacing: 3, paragraphSpacingBefore: 6, paragraphSpacingAfter: 10)
        paragraph.firstLineHeadIndent = 14
        paragraph.headIndent = 14
        paragraph.tailIndent = -14

        let attributes = mergedAttributes(
            baseAttributes: baseAttributes,
            font: .monospacedSystemFont(ofSize: baseFontSize - 1, weight: .regular),
            foregroundColor: NSColor.secondaryLabelColor,
            paragraphStyle: paragraph,
            backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.34)
        )

        let block = styledAttributedString(text, attributes: attributes)
        let padded = NSMutableAttributedString(string: "\n")
        padded.append(block)
        padded.append(NSAttributedString(string: "\n"))
        return padded
    }

    private static func styledAttributedString(
        _ text: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: attributes)
        applyInlineFormatting(to: result, baseAttributes: attributes)
        return result
    }

    private static func applyInlineFormatting(
        to attributedString: NSMutableAttributedString,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        replaceInlineCode(in: attributedString, baseAttributes: baseAttributes)
        replaceDelimitedText(
            in: attributedString,
            pattern: #"(?<!\*)\*\*(.+?)\*\*(?!\*)"#,
            baseAttributes: baseAttributes
        ) { inner, attrs in
            let font = font(from: attrs, fallback: .systemFont(ofSize: 15.5, weight: .regular))
            let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            return mergedAttributes(baseAttributes: attrs, font: boldFont)
        }
        replaceDelimitedText(
            in: attributedString,
            pattern: #"(?<!\*)\*(.+?)\*(?!\*)"#,
            baseAttributes: baseAttributes
        ) { inner, attrs in
            let font = font(from: attrs, fallback: .systemFont(ofSize: 15.5, weight: .regular))
            let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            return mergedAttributes(baseAttributes: attrs, font: italicFont)
        }
    }

    private static func replaceInlineCode(
        in attributedString: NSMutableAttributedString,
        baseAttributes: [NSAttributedString.Key: Any]
    ) {
        replaceDelimitedText(
            in: attributedString,
            pattern: #"(?<!`)`([^`]+)`(?!`)"#,
            baseAttributes: baseAttributes
        ) { inner, attrs in
            let codeFont = NSFont.monospacedSystemFont(ofSize: font(from: attrs, fallback: .systemFont(ofSize: 15.5)).pointSize - 0.5, weight: .regular)
            return mergedAttributes(
                baseAttributes: attrs,
                font: codeFont,
                foregroundColor: NSColor.labelColor,
                backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.45)
            )
        }
    }

    private static func replaceDelimitedText(
        in attributedString: NSMutableAttributedString,
        pattern: String,
        baseAttributes: [NSAttributedString.Key: Any],
        transform: (_ inner: String, _ currentAttributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let currentString = attributedString.string as NSString
        let matches = regex.matches(in: attributedString.string, range: NSRange(location: 0, length: currentString.length))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let innerRange = match.range(at: 1)
            let inner = currentString.substring(with: innerRange)
            let attrs = transform(inner, currentAttributes(at: attributedString, range: match.range, fallback: baseAttributes))
            let replacement = NSAttributedString(string: inner, attributes: attrs)
            attributedString.replaceCharacters(in: match.range, with: replacement)
        }
    }

    private static func currentAttributes(
        at attributedString: NSMutableAttributedString,
        range: NSRange,
        fallback: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        guard attributedString.length > 0 else { return fallback }
        let location = min(max(range.location, 0), max(0, attributedString.length - 1))
        return attributedString.attributes(at: location, effectiveRange: nil)
    }

    private static func headingLevel(for line: String) -> Int? {
        switch line {
        case let value where value.hasPrefix("# "):
            return 1
        case let value where value.hasPrefix("## "):
            return 2
        case let value where value.hasPrefix("### "):
            return 3
        default:
            return nil
        }
    }

    private static func stripHeadingPrefix(_ line: String, level: Int) -> String {
        let prefix = String(repeating: "#", count: level) + " "
        return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
    }

    private static func isListLine(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            return true
        }
        return line.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil
    }

    private static func semanticSectionTitle(for line: String) -> String? {
        let normalized = normalizeSemanticSectionCandidate(line)
        return semanticSectionTitleMap[normalized]
    }

    private static func canonicalizeSemanticSectionMarkers(in text: String) -> String {
        let pattern = #"(?i)(?:\*\*)?(Question|Answer|Explanation|Summary|Key Points|Flashcards|Takeaways|Examples|Definition|Quiz|Review|Notes?|Simplify)(?:\*\*)?:\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "\n\n## $1\n"
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeSemanticSectionCandidate(_ line: String) -> String {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func semanticAccentColor() -> NSColor {
        NSColor(calibratedRed: 0.38, green: 0.45, blue: 0.48, alpha: 1.0)
    }

    private static func semanticBadgeBackgroundColor() -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.26, green: 0.28, blue: 0.30, alpha: 0.88)
                : NSColor(calibratedRed: 0.92, green: 0.95, blue: 0.96, alpha: 0.96)
        }
    }

    private static func listPrefixAndText(_ line: String) -> (String, String) {
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return ("• ", String(line.dropFirst(2)))
        }
        if line.hasPrefix("• ") {
            return ("• ", String(line.dropFirst(2)))
        }

        if let match = line.range(of: #"^(\d+)\.\s+"#, options: .regularExpression) {
            let prefix = String(line[..<match.upperBound])
            return (prefix, String(line[match.upperBound...]))
        }

        return ("• ", line)
    }

    private static func collectContiguousLines(
        lines: [String],
        startIndex: Int,
        predicate: (String) -> Bool
    ) -> (lines: [String], nextIndex: Int) {
        var collected: [String] = []
        var index = startIndex
        while index < lines.count {
            let line = lines[index]
            if !predicate(line) { break }
            collected.append(line)
            index += 1
        }
        return (collected, index)
    }

    private static func collectCodeBlock(lines: [String], startIndex: Int) -> (lines: [String], nextIndex: Int) {
        var collected: [String] = []
        var index = startIndex + 1
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                return (collected, index + 1)
            }
            collected.append(line)
            index += 1
        }
        return (collected, index)
    }

    private static func makeParagraphStyle(
        lineSpacing: CGFloat,
        paragraphSpacingBefore: CGFloat,
        paragraphSpacingAfter: CGFloat
    ) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacingBefore = paragraphSpacingBefore
        paragraph.paragraphSpacing = paragraphSpacingAfter
        return paragraph
    }

    private static func mergedAttributes(
        baseAttributes: [NSAttributedString.Key: Any],
        font: NSFont? = nil,
        foregroundColor: NSColor? = nil,
        paragraphStyle: NSParagraphStyle? = nil,
        backgroundColor: NSColor? = nil
    ) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes
        if let font { attributes[.font] = font }
        if let foregroundColor { attributes[.foregroundColor] = foregroundColor }
        if let paragraphStyle { attributes[.paragraphStyle] = paragraphStyle }
        if let backgroundColor { attributes[.backgroundColor] = backgroundColor }
        return attributes
    }

    private static func font(from attributes: [NSAttributedString.Key: Any], fallback: NSFont) -> NSFont {
        attributes[.font] as? NSFont ?? fallback
    }
}

extension String {
    func markdownAttributedString() -> AttributedString? {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        return try? AttributedString(markdown: self, options: options)
    }
}
