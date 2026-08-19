import Foundation

final class DocumentProcessingPipeline {
    static let shared = DocumentProcessingPipeline()

    private let processor: DocumentProcessingNormalizing
    private let detector: StructureDetecting
    private let splitter: SectionSplitting
    private let complexityEstimator: DocumentComplexityEstimating
    private let tokenEstimator: DocumentTokenEstimating
    private let cache: DocumentStructureCaching

    init(
        processor: DocumentProcessingNormalizing = DocumentProcessor.shared,
        detector: StructureDetecting = StructureDetector.shared,
        splitter: SectionSplitting = SectionSplitter.shared,
        complexityEstimator: DocumentComplexityEstimating = ComplexityEstimator.shared,
        tokenEstimator: DocumentTokenEstimating = TokenEstimator.shared,
        cache: DocumentStructureCaching = DocumentStructureCache.shared
    ) {
        self.processor = processor
        self.detector = detector
        self.splitter = splitter
        self.complexityEstimator = complexityEstimator
        self.tokenEstimator = tokenEstimator
        self.cache = cache
    }

    func process(
        title: String,
        text: String,
        sourceKind: String = "note",
        sourceID: String? = nil,
        targetChunkSize: Int = 320
    ) throws -> DocumentStructure {
        let processed = processor.normalize(title: title, text: text)
        if let cached = cache.cachedStructure(for: processed.contentHash) {
            return cached
        }

        let detectedBlocks = detector.detect(in: processed)
        let split = splitter.split(title: processed.title, blocks: detectedBlocks)
        let blocks = split.blocks
        let sections = split.sections
        let statistics = buildStatistics(processed: processed, blocks: blocks, sections: sections)
        let complexity = complexityEstimator.estimate(document: processed, blocks: blocks, sections: sections, statistics: statistics)
        let tokenEstimate = tokenEstimator.estimate(document: processed, blocks: blocks, sections: sections, targetChunkSize: targetChunkSize)
        let structure = buildStructure(
            title: processed.title,
            originalText: processed.originalText,
            normalizedText: processed.normalizedText,
            contentHash: processed.contentHash,
            sourceKind: sourceKind,
            sourceID: sourceID,
            blocks: blocks,
            sections: sections,
            statistics: statistics,
            complexity: complexity,
            tokenEstimate: tokenEstimate
        )

        try DocumentStructureValidator.validate(structure)
        cache.store(structure, for: processed.contentHash)
        return structure
    }

    private func buildStructure(
        title: String,
        originalText: String,
        normalizedText: String,
        contentHash: String,
        sourceKind: String,
        sourceID: String?,
        blocks: [DocumentBlock],
        sections: [DocumentSection],
        statistics: DocumentStatistics,
        complexity: DocumentComplexityEstimate,
        tokenEstimate: DocumentTokenEstimate
    ) -> DocumentStructure {
        let headings = blocks.compactMap { block -> String? in
            guard block.kind == .heading else { return nil }
            return block.normalizedContent.isEmpty ? block.content : block.normalizedContent
        }

        let listItems = blocks.flatMap { block -> [DocumentListItem] in
            guard block.kind == .bulletedList || block.kind == .numberedList else { return [] }
            return block.listItems.enumerated().map { index, text in
                DocumentListItem(
                    text: text,
                    line: block.startLine + index,
                    isNumbered: block.kind == .numberedList
                )
            }
        }

        let codeBlocks = blocks.compactMap { block -> DocumentCodeBlock? in
            guard block.kind == .codeBlock else { return nil }
            return DocumentCodeBlock(
                content: block.content,
                language: block.codeLanguage,
                startLine: block.startLine,
                endLine: block.endLine
            )
        }

        let equations = blocks.compactMap { block -> String? in
            guard block.kind == .equation else { return nil }
            return block.equation ?? block.normalizedContent
        }

        let tables = blocks.compactMap { block -> DocumentTable? in
            guard block.kind == .table else { return nil }
            return DocumentTable(
                rows: block.tableRows,
                startLine: block.startLine,
                endLine: block.endLine
            )
        }

        return DocumentStructure(
            title: title,
            originalText: originalText,
            normalizedText: normalizedText,
            cleanedText: normalizedText,
            sourceSignature: contentHash,
            metadata: DocumentMetadata(
                documentID: sourceID ?? contentHash,
                title: title,
                sourceKind: sourceKind,
                contentHash: contentHash,
                normalizedCharacterCount: normalizedText.count,
                lineCount: statistics.lineCount,
                processedAt: Date(),
                processingVersion: "v2"
            ),
            blocks: blocks,
            sections: sections,
            headings: headings,
            lists: listItems,
            codeBlocks: codeBlocks,
            equations: equations,
            tables: tables,
            statistics: statistics,
            complexity: complexity,
            tokenEstimate: tokenEstimate
        )
    }

    private func buildStatistics(processed: ProcessedDocument, blocks: [DocumentBlock], sections: [DocumentSection]) -> DocumentStatistics {
        let words = processed.normalizedText.split { $0.isWhitespace || $0.isNewline }
        let sentenceCount = max(0, processed.normalizedText.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)
        let blankLineCount = processed.lines.filter { $0.isEmpty }.count

        return DocumentStatistics(
            characterCount: processed.originalText.count,
            normalizedCharacterCount: processed.normalizedText.count,
            wordCount: words.count,
            sentenceCount: sentenceCount,
            lineCount: processed.lines.count,
            blankLineCount: blankLineCount,
            blockCount: blocks.count,
            sectionCount: sections.count,
            headingCount: blocks.filter { $0.kind == .heading }.count,
            paragraphCount: blocks.filter { $0.kind == .paragraph }.count,
            bulletedListCount: blocks.filter { $0.kind == .bulletedList }.count,
            numberedListCount: blocks.filter { $0.kind == .numberedList }.count,
            tableCount: blocks.filter { $0.kind == .table }.count,
            codeBlockCount: blocks.filter { $0.kind == .codeBlock }.count,
            equationCount: blocks.filter { $0.kind == .equation }.count,
            quoteCount: blocks.filter { $0.kind == .quote }.count
        )
    }

}

extension DocumentProcessingPipeline {
    func process(title: String, rawContent: String) throws -> DocumentStructure {
        try process(title: title, text: rawContent, sourceKind: "note", sourceID: nil)
    }
}
