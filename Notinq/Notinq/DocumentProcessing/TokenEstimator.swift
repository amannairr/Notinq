import Foundation

protocol DocumentTokenEstimating {
    func estimate(document: ProcessedDocument, blocks: [DocumentBlock], sections: [DocumentSection], targetChunkSize: Int) -> DocumentTokenEstimate
    func estimatedTokenCount(for text: String) -> Int
}

final class TokenEstimator: DocumentTokenEstimating {
    static let shared = TokenEstimator()

    private init() {}

    func estimate(document: ProcessedDocument, blocks: [DocumentBlock], sections: [DocumentSection], targetChunkSize: Int = 320) -> DocumentTokenEstimate {
        let blockEstimates = blocks.enumerated().map { index, block in
            DocumentBlockTokenEstimate(
                blockID: block.id,
                blockIndex: index,
                kind: block.kind,
                estimatedTokens: estimatedTokenCount(for: block)
            )
        }

        let sectionEstimates = sections.enumerated().map { sectionIndex, section in
            let sectionBlockIndices = blocks.enumerated().compactMap { index, block -> Int? in
                block.sectionID == section.id ? index : nil
            }
            let startIndex = sectionBlockIndices.first ?? 0
            let endIndex = sectionBlockIndices.last ?? startIndex
            let sectionTokens = sectionBlockIndices.reduce(0) { total, index in
                total + blockEstimates[index].estimatedTokens
            }
            return DocumentSectionTokenEstimate(
                sectionID: section.id,
                sectionIndex: sectionIndex,
                estimatedTokens: sectionTokens,
                startBlockIndex: startIndex,
                endBlockIndex: endIndex
            )
        }

        let suggestedChunkBoundaries = buildChunkBoundaries(
            blockEstimates: blockEstimates,
            sections: sections,
            blocks: blocks,
            targetChunkSize: max(64, targetChunkSize)
        )

        return DocumentTokenEstimate(
            estimatedTotalTokens: blockEstimates.reduce(0) { $0 + $1.estimatedTokens },
            blockEstimates: blockEstimates,
            sectionEstimates: sectionEstimates,
            suggestedChunkBoundaries: suggestedChunkBoundaries,
            method: .approximateWordRatio,
            targetChunkSize: max(64, targetChunkSize)
        )
    }

    func estimatedTokenCount(for text: String) -> Int {
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let characterEstimate = Int((Double(text.count) / 4.0).rounded(.up))
        let wordEstimate = Int((Double(words) * 1.25).rounded(.up))
        return max(1, max(characterEstimate, wordEstimate))
    }

    private func estimatedTokenCount(for block: DocumentBlock) -> Int {
        let base = estimatedTokenCount(for: block.normalizedContent.isEmpty ? block.content : block.normalizedContent)
        switch block.kind {
        case .codeBlock:
            return max(1, Int((Double(block.content.count) / 3.2).rounded(.up)))
        case .table:
            let rowCount = max(1, block.tableRows.count)
            return max(1, Int((Double(base) * 1.2 + Double(rowCount) * 2.0).rounded(.up)))
        case .heading:
            return max(1, base + 2)
        case .bulletedList, .numberedList:
            return max(1, Int((Double(base) * 1.1).rounded(.up)))
        case .equation:
            return max(1, Int((Double(base) * 1.15).rounded(.up)))
        case .quote:
            return max(1, Int((Double(base) * 1.05).rounded(.up)))
        case .paragraph:
            return base
        }
    }

    private func buildChunkBoundaries(
        blockEstimates: [DocumentBlockTokenEstimate],
        sections: [DocumentSection],
        blocks: [DocumentBlock],
        targetChunkSize: Int
    ) -> [DocumentChunkBoundary] {
        guard !blockEstimates.isEmpty else { return [] }

        var boundaries: [DocumentChunkBoundary] = []
        var startIndex = 0
        var runningTokens = 0

        func flush(endIndex: Int, hard: Bool, sectionID: String?) {
            guard endIndex >= startIndex else { return }
            let estimatedTokens = blockEstimates[startIndex...endIndex].reduce(0) { $0 + $1.estimatedTokens }
            boundaries.append(
                DocumentChunkBoundary(
                    startBlockIndex: startIndex,
                    endBlockIndex: endIndex,
                    estimatedTokens: estimatedTokens,
                    sectionID: sectionID,
                    isHardBoundary: hard
                )
            )
        }

        for index in blockEstimates.indices {
            let nextTokens = blockEstimates[index].estimatedTokens
            let block = blocks[index]
            let boundarySectionID = block.sectionID ?? sections.first?.id

            let wouldOverflow = runningTokens + nextTokens > targetChunkSize && runningTokens > 0
            let headingBoundary = block.kind == .heading && runningTokens > 0
            if wouldOverflow || headingBoundary {
                flush(endIndex: index - 1, hard: headingBoundary, sectionID: blocks[index - 1].sectionID ?? boundarySectionID)
                startIndex = index
                runningTokens = 0
            }

            runningTokens += nextTokens
        }

        flush(endIndex: blockEstimates.count - 1, hard: true, sectionID: blocks.last?.sectionID)

        return boundaries.filter { $0.startBlockIndex <= $0.endBlockIndex }
    }
}
