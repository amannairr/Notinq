import Foundation

protocol DocumentComplexityEstimating {
    func estimate(document: ProcessedDocument, blocks: [DocumentBlock], sections: [DocumentSection], statistics: DocumentStatistics) -> DocumentComplexityEstimate
}

final class ComplexityEstimator: DocumentComplexityEstimating {
    static let shared = ComplexityEstimator()

    private init() {}

    func estimate(document: ProcessedDocument, blocks: [DocumentBlock], sections: [DocumentSection], statistics: DocumentStatistics) -> DocumentComplexityEstimate {
        let wordCount = max(0, statistics.wordCount)
        let sentenceCount = max(0, statistics.sentenceCount)
        let structuralSignals = statistics.headingCount + statistics.bulletedListCount + statistics.numberedListCount + statistics.tableCount + statistics.codeBlockCount + statistics.equationCount + statistics.quoteCount
        let averageSentenceLength = sentenceCount == 0 ? 0 : Double(wordCount) / Double(sentenceCount)
        let conceptDensity = Double(structuralSignals) / Double(max(1, sentenceCount))
        let structuralDensity = Double(structuralSignals) / Double(max(1, statistics.blockCount))
        let readingScore = min(1.0, 0.20 + (averageSentenceLength / 30.0) * 0.45 + structuralDensity * 0.25 + conceptDensity * 0.10)
        let estimatedStudyMinutes = max(1, Int((Double(wordCount) / 180.0 + Double(structuralSignals) * 0.45).rounded(.up)))
        let complexityScore = min(1.0, 0.35 * readingScore + 0.35 * min(1.0, conceptDensity / 2.0) + 0.30 * min(1.0, structuralDensity * 2.5))

        let sectionMetrics = sections.map { section in
            let sectionBlocks = blocks.filter { $0.sectionID == section.id }
            let sectionText = sectionBlocks.map(\.normalizedContent).joined(separator: "\n")
            let sectionWordCount = sectionText.split { $0.isWhitespace || $0.isNewline }.count
            let sectionSentenceCount = max(1, sectionText.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)
            let sectionTokenEstimate = max(1, Int((Double(sectionWordCount) * 1.25).rounded(.up)))
            let sectionDensity = Double(sectionBlocks.count) / Double(max(1, sectionSentenceCount))
            let sectionDifficulty = difficulty(for: Double(sectionWordCount) / Double(sectionSentenceCount), density: sectionDensity)

            return DocumentSectionComplexity(
                sectionID: section.id,
                readingDifficulty: sectionDifficulty,
                conceptDensity: min(1.0, sectionDensity),
                estimatedStudyMinutes: max(1, Int((Double(sectionWordCount) / 160.0 + Double(sectionBlocks.count) * 0.35).rounded(.up))),
                tokenEstimate: sectionTokenEstimate,
                blockCount: sectionBlocks.count
            )
        }

        return DocumentComplexityEstimate(
            readingDifficulty: difficulty(for: averageSentenceLength, density: structuralDensity),
            conceptDensity: min(1.0, conceptDensity),
            estimatedStudyMinutes: estimatedStudyMinutes,
            structuralDensity: min(1.0, structuralDensity),
            tokenEstimate: max(0, statistics.wordCount),
            headingCount: statistics.headingCount,
            listCount: statistics.bulletedListCount + statistics.numberedListCount,
            codeBlockCount: statistics.codeBlockCount,
            equationCount: statistics.equationCount,
            tableCount: statistics.tableCount,
            sentenceCount: statistics.sentenceCount,
            averageSentenceLength: averageSentenceLength,
            complexityScore: complexityScore,
            sectionCount: sections.count,
            sectionMetrics: sectionMetrics
        )
    }

    private func difficulty(for averageSentenceLength: Double, density: Double) -> DocumentReadingDifficulty {
        let score = averageSentenceLength / 18.0 + density * 1.75
        switch score {
        case ..<1.0:
            return .easy
        case ..<1.8:
            return .moderate
        case ..<2.6:
            return .challenging
        default:
            return .advanced
        }
    }
}
