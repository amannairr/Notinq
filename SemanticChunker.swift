import Foundation

struct SemanticChunk: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var documentID: String
    var chunkIndex: Int
    var sectionName: String
    var paragraphIDs: [String]
    var content: String
    var startLine: Int
    var endLine: Int
}

final class SemanticChunker {
    static let shared = SemanticChunker()

    private init() {}

    func chunk(title: String, structure: DocumentStructure, contextLimit: Int) -> [SemanticChunk] {
        let documentID = structure.sourceSignature.isEmpty ? DocumentPreprocessor.shared.signature(for: title, text: structure.normalizedText) : structure.sourceSignature
        let targetTokenLimit = max(64, Int(Double(max(1, contextLimit)) * 0.85))
        var chunks: [SemanticChunk] = []

        for section in structure.sections {
            let paragraphs = paragraphBlocks(in: section.content)
            guard !paragraphs.isEmpty else {
                continue
            }

            let sectionName = section.title.isEmpty ? title : section.title
            let expanded = buildChunks(
                documentID: documentID,
                sectionName: sectionName,
                sectionStartLine: section.startLine + 1,
                paragraphs: paragraphs,
                targetTokenLimit: targetTokenLimit
            )
            chunks.append(contentsOf: expanded)
        }

        if chunks.isEmpty {
            let fallbackParagraphs = paragraphBlocks(in: structure.normalizedText)
            let fallback = fallbackParagraphs.isEmpty
                ? [SemanticParagraph(id: UUID().uuidString, text: structure.normalizedText, startLineOffset: 0, endLineOffset: max(structure.normalizedText.components(separatedBy: .newlines).count - 1, 0))]
                : fallbackParagraphs
            chunks = buildChunks(
                documentID: documentID,
                sectionName: title,
                sectionStartLine: 1,
                paragraphs: fallback,
                targetTokenLimit: targetTokenLimit
            )
        }

        return chunks.enumerated().map { index, chunk in
            SemanticChunk(
                id: chunk.id,
                documentID: documentID,
                chunkIndex: index,
                sectionName: chunk.sectionName,
                paragraphIDs: chunk.paragraphIDs,
                content: chunk.content,
                startLine: chunk.startLine,
                endLine: chunk.endLine
            )
        }
    }

    private func buildChunks(
        documentID: String,
        sectionName: String,
        sectionStartLine: Int,
        paragraphs: [SemanticParagraph],
        targetTokenLimit: Int
    ) -> [SemanticChunk] {
        guard !paragraphs.isEmpty else { return [] }
        if estimatedTokens(for: paragraphs.map(\.text).joined(separator: "\n\n")) <= targetTokenLimit {
            return [SemanticChunk(
                id: UUID().uuidString,
                documentID: documentID,
                chunkIndex: 0,
                sectionName: sectionName,
                paragraphIDs: paragraphs.map(\.id),
                content: paragraphs.map(\.text).joined(separator: "\n\n"),
                startLine: sectionStartLine + (paragraphs.first?.startLineOffset ?? 0),
                endLine: sectionStartLine + (paragraphs.last?.endLineOffset ?? 0)
            )]
        }

        var result: [SemanticChunk] = []
        var current: [SemanticParagraph] = []
        var currentTokens = 0
        let overlapCount = max(1, Int((Double(paragraphs.count) * 0.15).rounded(.up)))

        func flush() {
            guard !current.isEmpty else { return }
            result.append(
                SemanticChunk(
                    id: UUID().uuidString,
                    documentID: documentID,
                    chunkIndex: result.count,
                    sectionName: sectionName,
                    paragraphIDs: current.map(\.id),
                    content: current.map(\.text).joined(separator: "\n\n"),
                    startLine: sectionStartLine + (current.first?.startLineOffset ?? 0),
                    endLine: sectionStartLine + (current.last?.endLineOffset ?? 0)
                )
            )
        }

        for paragraph in paragraphs {
            let paragraphTokens = estimatedTokens(for: paragraph.text)
            let wouldOverflow = currentTokens + paragraphTokens > targetTokenLimit && !current.isEmpty
            if wouldOverflow {
                flush()
                let overlap = Array(current.suffix(overlapCount))
                current = overlap
                currentTokens = overlap.reduce(0) { $0 + estimatedTokens(for: $1.text) }
            }

            if paragraphTokens > targetTokenLimit {
                let split = recursivelySplit(paragraph: paragraph, documentID: documentID, sectionName: sectionName, sectionStartLine: sectionStartLine, targetTokenLimit: targetTokenLimit)
                if !split.isEmpty {
                    if !current.isEmpty {
                        flush()
                        current.removeAll()
                        currentTokens = 0
                    }
                    result.append(contentsOf: split)
                    continue
                }
            }

            current.append(paragraph)
            currentTokens += paragraphTokens
        }

        flush()
        return result
    }

    private func recursivelySplit(
        paragraph: SemanticParagraph,
        documentID: String,
        sectionName: String,
        sectionStartLine: Int,
        targetTokenLimit: Int
    ) -> [SemanticChunk] {
        let blocks = paragraph.text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard blocks.count > 1 else {
            return [SemanticChunk(
                id: UUID().uuidString,
                documentID: documentID,
                chunkIndex: 0,
                sectionName: sectionName,
                paragraphIDs: [paragraph.id],
                content: paragraph.text,
                startLine: sectionStartLine + paragraph.startLineOffset,
                endLine: sectionStartLine + paragraph.endLineOffset
            )]
        }

        var chunks: [SemanticChunk] = []
        var current: [String] = []
        var currentTokens = 0
        let overlapCount = max(1, Int((Double(blocks.count) * 0.1).rounded(.up)))

        func flush() {
            guard !current.isEmpty else { return }
            chunks.append(
                SemanticChunk(
                    id: UUID().uuidString,
                    documentID: documentID,
                    chunkIndex: chunks.count,
                    sectionName: sectionName,
                    paragraphIDs: [paragraph.id],
                    content: current.joined(separator: "\n"),
                    startLine: sectionStartLine + paragraph.startLineOffset,
                    endLine: sectionStartLine + paragraph.endLineOffset
                )
            )
        }

        for block in blocks {
            let tokens = estimatedTokens(for: block)
            if currentTokens + tokens > targetTokenLimit && !current.isEmpty {
                flush()
                current = Array(current.suffix(overlapCount))
                currentTokens = current.reduce(0) { $0 + estimatedTokens(for: $1) }
            }
            current.append(block)
            currentTokens += tokens
        }

        flush()
        return chunks
    }

    private func paragraphBlocks(in text: String) -> [SemanticParagraph] {
        let lines = text.components(separatedBy: .newlines)
        var paragraphs: [SemanticParagraph] = []
        var buffer: [String] = []
        var startLine = 0

        func flush(endLine: Int) {
            let content = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                paragraphs.append(SemanticParagraph(id: UUID().uuidString, text: content, startLineOffset: startLine, endLineOffset: endLine))
            }
            buffer.removeAll()
        }

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                flush(endLine: index - 1)
                startLine = index + 1
                continue
            }

            if looksLikeSpeakerTransition(trimmed), !buffer.isEmpty {
                flush(endLine: index - 1)
                startLine = index
            } else if looksLikeBullet(trimmed), buffer.isEmpty {
                startLine = index
            }

            buffer.append(trimmed)
        }

        flush(endLine: max(lines.count - 1, 0))
        return paragraphs
    }

    private func looksLikeSpeakerTransition(_ line: String) -> Bool {
        guard let first = line.first, first.isUppercase else { return false }
        return line.contains(":") && line.count < 80
    }

    private func looksLikeBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") || line.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil
    }

    private func estimatedTokens(for text: String) -> Int {
        max(1, text.split { $0.isWhitespace || $0.isNewline }.count * 3 / 4)
    }
}

private struct SemanticParagraph {
    var id: String
    var text: String
    var startLineOffset: Int
    var endLineOffset: Int
}
