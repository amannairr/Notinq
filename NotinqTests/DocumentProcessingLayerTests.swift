import XCTest
@testable import Notinq

final class DocumentProcessorTests: XCTestCase {
    func testNormalTextRemainsStable() {
        let processed = DocumentProcessor.shared.normalize(title: "Biology", text: "Cell membranes regulate transport.")

        XCTAssertEqual(processed.normalizedText, "Cell membranes regulate transport.")
        XCTAssertEqual(processed.lines, ["Cell membranes regulate transport."])
    }

    func testWhitespaceBlankLinesAndLineEndingsAreNormalized() {
        let processed = DocumentProcessor.shared.normalize(title: "Biology", text: "Cell   membranes\r\n\r\n\r\n  regulate    transport.  ")

        XCTAssertEqual(processed.normalizedText, "Cell membranes\n\nregulate transport.")
    }

    func testUnicodeAndCommonOcrArtifactsAreNormalized() {
        let processed = DocumentProcessor.shared.normalize(title: "OCR", text: "“Neural” ﬁbers — and non\u{00A0}breaking spaces…")

        XCTAssertEqual(processed.normalizedText, "\"Neural\" fibers - and non breaking spaces...")
    }

    func testTextThatShouldNotChangeIsPreserved() {
        let input = "Use x = 2 in the equation."
        let processed = DocumentProcessor.shared.normalize(title: "Math", text: input)

        XCTAssertEqual(processed.normalizedText, input)
    }
}

final class StructureDetectorTests: XCTestCase {
    func testHeadingAndNestedHeadingDetection() {
        let document = DocumentProcessor.shared.normalize(
            title: "Machine Learning",
            text: """
            # Introduction
            Overview text.

            ## Neural Networks
            Inner content.
            """
        )

        let blocks = StructureDetector.shared.detect(in: document)

        XCTAssertEqual(blocks.map(\.kind), [.heading, .paragraph, .heading, .paragraph])
        XCTAssertEqual(blocks[0].headingLevel, 1)
        XCTAssertEqual(blocks[2].headingLevel, 2)
    }

    func testBulletAndNumberedListDetection() {
        let document = DocumentProcessor.shared.normalize(
            title: "Lists",
            text: """
            - alpha
            - beta
            1. first
            2. second
            """
        )

        let blocks = StructureDetector.shared.detect(in: document)

        XCTAssertEqual(blocks.map(\.kind), [.bulletedList, .numberedList])
        XCTAssertEqual(blocks[0].listItems, ["alpha", "beta"])
        XCTAssertEqual(blocks[1].listItems, ["first", "second"])
    }

    func testTableCodeEquationAndQuoteDetection() {
        let document = DocumentProcessor.shared.normalize(
            title: "Mixed",
            text: """
            | Term | Definition | Example |
            | Cell | Basic unit | Animal cell |

            ```swift
            let x = 2 + 2
            ```

            E = mc^2

            > quoted idea
            > follow-up
            """
        )

        let blocks = StructureDetector.shared.detect(in: document)

        XCTAssertTrue(blocks.contains(where: { $0.kind == .table }))
        XCTAssertTrue(blocks.contains(where: { $0.kind == .codeBlock }))
        XCTAssertTrue(blocks.contains(where: { $0.kind == .equation }))
        XCTAssertTrue(blocks.contains(where: { $0.kind == .quote }))
    }

    func testAmbiguousParagraphIsNotForcedIntoEquationDetection() {
        let document = DocumentProcessor.shared.normalize(
            title: "Mixed",
            text: "This is a paragraph with x = y in the middle."
        )

        let blocks = StructureDetector.shared.detect(in: document)

        XCTAssertEqual(blocks.map(\.kind), [.paragraph])
    }
}

final class SectionSplitterTests: XCTestCase {
    func testFlatSectionsArePreservedInOrder() {
        let blocks = [
            headingBlock("Introduction", level: 1, line: 0),
            paragraphBlock("Intro text.", line: 1),
            headingBlock("Methods", level: 1, line: 2),
            paragraphBlock("Method text.", line: 3)
        ]

        let result = SectionSplitter.shared.split(title: "Biology", blocks: blocks)

        XCTAssertEqual(result.sections.map(\.title), ["Introduction", "Methods"])
        XCTAssertEqual(result.sections.map(\.level), [1, 1])
    }

    func testNestedSectionsPreserveHierarchy() {
        let blocks = [
            headingBlock("Intro", level: 1, line: 0),
            paragraphBlock("Intro text.", line: 1),
            headingBlock("Neural Networks", level: 2, line: 2),
            paragraphBlock("Deep content.", line: 3)
        ]

        let result = SectionSplitter.shared.split(title: "ML", blocks: blocks)

        XCTAssertEqual(result.sections.count, 2)
        XCTAssertEqual(result.sections[1].parentID, result.sections[0].id)
    }

    func testContentBeforeFirstHeadingIsKeptInPreambleSection() {
        let blocks = [
            paragraphBlock("Lead-in text.", line: 0),
            headingBlock("Topic", level: 1, line: 1),
            paragraphBlock("Topic text.", line: 2)
        ]

        let result = SectionSplitter.shared.split(title: "Lecture", blocks: blocks)

        XCTAssertEqual(result.sections.first?.title, "Lecture")
        XCTAssertEqual(result.sections.first?.kind, .root)
        XCTAssertEqual(result.sections[1].title, "Topic")
    }

    func testConsecutiveSectionsRemainDistinct() {
        let blocks = [
            headingBlock("A", level: 1, line: 0),
            headingBlock("B", level: 1, line: 1),
            headingBlock("C", level: 1, line: 2)
        ]

        let result = SectionSplitter.shared.split(title: "Outline", blocks: blocks)

        XCTAssertEqual(result.sections.map(\.title), ["A", "B", "C"])
    }
}

final class ComplexityEstimatorTests: XCTestCase {
    func testEmptyDocumentIsLowComplexity() {
        let processed = ProcessedDocument(title: "Empty", originalText: "", normalizedText: "", lines: [], contentHash: "empty")
        let estimate = ComplexityEstimator.shared.estimate(document: processed, blocks: [], sections: [], statistics: DocumentStatistics())

        XCTAssertEqual(estimate.readingDifficulty, .easy)
        XCTAssertEqual(estimate.estimatedStudyMinutes, 1)
    }

    func testLongComplexDocumentScoresHigher() {
        let document = DocumentProcessor.shared.normalize(
            title: "Biology",
            text: String(repeating: "Neural adaptation depends on synaptic plasticity. ", count: 40) + "\n\n# Appendix\n- Alpha\n- Beta\n"
        )
        let blocks = StructureDetector.shared.detect(in: document)
        let split = SectionSplitter.shared.split(title: document.title, blocks: blocks)
        let statistics = DocumentStatistics(
            characterCount: document.originalText.count,
            normalizedCharacterCount: document.normalizedText.count,
            wordCount: document.normalizedText.split { $0.isWhitespace || $0.isNewline }.count,
            sentenceCount: 40,
            lineCount: document.lines.count,
            blankLineCount: 1,
            blockCount: split.blocks.count,
            sectionCount: split.sections.count,
            headingCount: split.blocks.filter { $0.kind == .heading }.count,
            paragraphCount: split.blocks.filter { $0.kind == .paragraph }.count,
            bulletedListCount: split.blocks.filter { $0.kind == .bulletedList }.count,
            numberedListCount: split.blocks.filter { $0.kind == .numberedList }.count,
            tableCount: 0,
            codeBlockCount: 0,
            equationCount: 0,
            quoteCount: 0
        )

        let estimate = ComplexityEstimator.shared.estimate(document: document, blocks: split.blocks, sections: split.sections, statistics: statistics)

        XCTAssertEqual(estimate.readingDifficulty, .challenging)
        XCTAssertGreaterThan(estimate.conceptDensity, 0)
        XCTAssertEqual(estimate.sectionMetrics.count, split.sections.count)
    }
}

final class TokenEstimatorTests: XCTestCase {
    func testEmptyDocumentProducesZeroTokens() {
        let estimate = TokenEstimator.shared.estimate(
            document: ProcessedDocument(title: "Empty", originalText: "", normalizedText: "", lines: [], contentHash: "empty"),
            blocks: [],
            sections: [],
            targetChunkSize: 128
        )

        XCTAssertEqual(estimate.estimatedTotalTokens, 0)
        XCTAssertTrue(estimate.suggestedChunkBoundaries.isEmpty)
    }

    func testShortDocumentProducesSingleChunk() {
        let structure = makeTokenTestStructure(text: "Short note text.")
        let estimate = TokenEstimator.shared.estimate(document: structure.document, blocks: structure.blocks, sections: structure.sections, targetChunkSize: 128)

        XCTAssertEqual(estimate.suggestedChunkBoundaries.count, 1)
        XCTAssertEqual(estimate.suggestedChunkBoundaries.first?.startBlockIndex, 0)
    }

    func testLongDocumentCreatesMultipleChunkBoundaries() {
        let blocks = (0..<12).map { index in
            paragraphBlock(String(repeating: "Section \(index) ", count: 20), line: index)
        }
        let sections = [makeSection(id: "section-1", title: "Body", level: 0, blockIDs: blocks.map(\.id))]
        let document = ProcessedDocument(title: "Long", originalText: "", normalizedText: "", lines: [], contentHash: "long")

        let estimate = TokenEstimator.shared.estimate(document: document, blocks: blocks, sections: sections, targetChunkSize: 60)

        XCTAssertGreaterThan(estimate.suggestedChunkBoundaries.count, 1)
    }

    func testSectionThatExceedsTargetStillGetsBoundaries() {
        let block = paragraphBlock(String(repeating: "Important concept ", count: 80), line: 0)
        let section = makeSection(id: "section-1", title: "Massive", level: 0, blockIDs: [block.id])
        let document = ProcessedDocument(title: "Huge", originalText: "", normalizedText: "", lines: [], contentHash: "huge")

        let estimate = TokenEstimator.shared.estimate(document: document, blocks: [block], sections: [section], targetChunkSize: 20)

        XCTAssertEqual(estimate.suggestedChunkBoundaries.count, 1)
        XCTAssertGreaterThan(estimate.suggestedChunkBoundaries[0].estimatedTokens, 20)
    }
}

final class DocumentStructureValidationTests: XCTestCase {
    func testValidStructurePassesValidation() throws {
        let structure = try DocumentProcessingPipeline.shared.process(
            title: "Validation",
            text: """
            # Intro
            Valid text.
            """
        )

        XCTAssertNoThrow(try DocumentStructureValidator.validate(structure))
    }

    func testInvalidReferencesFailValidation() throws {
        var structure = try DocumentProcessingPipeline.shared.process(
            title: "Validation",
            text: """
            # Intro
            Valid text.
            """
        )
        structure.sections[0].blockIDs.append("missing")

        XCTAssertThrowsError(try DocumentStructureValidator.validate(structure))
    }

    func testInvalidBlockSectionReferenceFailsValidation() throws {
        var structure = try DocumentProcessingPipeline.shared.process(
            title: "Validation",
            text: """
            # Intro
            Valid text.
            """
        )
        structure.blocks[0].sectionID = "missing-section"

        XCTAssertThrowsError(try DocumentStructureValidator.validate(structure))
    }

    func testInvalidHierarchyFailsValidation() throws {
        var structure = try DocumentProcessingPipeline.shared.process(
            title: "Validation",
            text: """
            # Intro
            ## Detail
            Detail text.
            """
        )
        structure.sections[1].parentID = nil
        structure.sections[1].level = 0

        XCTAssertThrowsError(try DocumentStructureValidator.validate(structure))
    }

    func testInvalidChunkBoundariesFailValidation() throws {
        var structure = try DocumentProcessingPipeline.shared.process(
            title: "Validation",
            text: """
            # Intro
            Intro text.
            """
        )
        structure.tokenEstimate.suggestedChunkBoundaries = [
            DocumentChunkBoundary(startBlockIndex: 0, endBlockIndex: 9, estimatedTokens: 10, sectionID: structure.sections.first?.id, isHardBoundary: true)
        ]

        XCTAssertThrowsError(try DocumentStructureValidator.validate(structure))
    }
}

final class DocumentStructureCacheTests: XCTestCase {
    func testSameContentReturnsCachedStructure() {
        let cache = DocumentStructureCache(cacheURL: temporaryCacheURL())
        cache.clear()
        let structure = makeCachedStructure(hash: "abc")

        cache.store(structure, for: "abc")

        XCTAssertEqual(cache.cachedStructure(for: "abc"), structure)
    }

    func testCacheMissReturnsNil() {
        let cache = DocumentStructureCache(cacheURL: temporaryCacheURL())
        cache.clear()

        XCTAssertNil(cache.cachedStructure(for: "missing"))
    }

    func testCachePersistsAcrossInstances() {
        let url = temporaryCacheURL()
        let firstCache = DocumentStructureCache(cacheURL: url)
        firstCache.clear()
        let structure = makeCachedStructure(hash: "persisted")

        firstCache.store(structure, for: "persisted")

        let secondCache = DocumentStructureCache(cacheURL: url)
        XCTAssertEqual(secondCache.cachedStructure(for: "persisted"), structure)
    }
}

final class DocumentProcessingPipelineTests: XCTestCase {
    func testRawInputProducesExpectedDocumentStructure() throws {
        let structure = try DocumentProcessingPipeline.shared.process(
            title: "Biology",
            text: """
            # Cell Theory

            - Cells are basic units of life.
            - Cells divide.
            """
        )

        XCTAssertEqual(structure.title, "Biology")
        XCTAssertFalse(structure.blocks.isEmpty)
        XCTAssertFalse(structure.sections.isEmpty)
        XCTAssertTrue(structure.headings.contains("Cell Theory"))
    }

    func testEveryStageRunsInOrder() throws {
        let recorder = PipelineRecorder()
        let pipeline = DocumentProcessingPipeline(
            processor: recorder,
            detector: recorder,
            splitter: recorder,
            complexityEstimator: recorder,
            tokenEstimator: recorder,
            cache: recorder
        )

        _ = try pipeline.process(title: "Order", text: "# Heading\nBody text.")

        XCTAssertEqual(recorder.events, [
            "processor",
            "cache-read",
            "detector",
            "splitter",
            "complexity",
            "token",
            "cache-store"
        ])
    }

    func testFailuresAreSurfaced() {
        let pipeline = DocumentProcessingPipeline(
            processor: FailingProcessor(),
            detector: PipelineRecorder(),
            splitter: PipelineRecorder(),
            complexityEstimator: PipelineRecorder(),
            tokenEstimator: FailingTokenEstimator(),
            cache: PipelineRecorder()
        )

        XCTAssertThrowsError(try pipeline.process(title: "Bad", text: "# One\nTwo"))
    }
}

final class DocumentProcessingBoundaryIntegrationTests: XCTestCase {
    func testProcessedDocumentReachesAiBoundaryWithoutRawString() async throws {
        let structure = try DocumentProcessingPipeline.shared.process(
            title: "Biology",
            text: """
            # Cell Membrane
            The membrane controls transport.
            """
        )

        let knowledge = await AIService.shared.extractStructuredKnowledge(from: structure)
        let studyData = await AIService.shared.generateStudyData(from: structure, existingStudyData: NoteStudyData())

        XCTAssertEqual(knowledge.metadata.sourceSignature, structure.sourceSignature)
        XCTAssertEqual(studyData.knowledgeSignature, structure.sourceSignature)
    }
}

// MARK: - Helpers

private func headingBlock(_ title: String, level: Int, line: Int) -> DocumentBlock {
    DocumentBlock(
        id: UUID().uuidString,
        kind: .heading,
        content: title,
        normalizedContent: title,
        startLine: line,
        endLine: line,
        headingLevel: level,
        listStyle: nil,
        listItems: [],
        tableRows: [],
        codeLanguage: nil,
        equation: nil,
        quoteLevel: 0,
        sectionID: nil
    )
}

private func paragraphBlock(_ text: String, line: Int) -> DocumentBlock {
    DocumentBlock(
        id: UUID().uuidString,
        kind: .paragraph,
        content: text,
        normalizedContent: text,
        startLine: line,
        endLine: line,
        headingLevel: nil,
        listStyle: nil,
        listItems: [],
        tableRows: [],
        codeLanguage: nil,
        equation: nil,
        quoteLevel: 0,
        sectionID: nil
    )
}

private func makeSection(id: String, title: String, level: Int, blockIDs: [String]) -> DocumentSection {
    DocumentSection(
        id: id,
        kind: .paragraph,
        title: title,
        content: title,
        level: level,
        parentID: nil,
        childIDs: [],
        blockIDs: blockIDs,
        order: 0,
        startLine: 0,
        endLine: max(0, blockIDs.count - 1)
    )
}

private func makeCachedStructure(hash: String) -> DocumentStructure {
    let block = paragraphBlock("Cached content.", line: 0)
    let section = makeSection(id: "section-1", title: "Cached", level: 0, blockIDs: [block.id])
    return DocumentStructure(
        title: "Cached",
        originalText: "Cached content.",
        normalizedText: "Cached content.",
        cleanedText: "Cached content.",
        sourceSignature: hash,
        metadata: DocumentMetadata(documentID: hash, title: "Cached", sourceKind: "note", contentHash: hash, normalizedCharacterCount: 15, lineCount: 1, processedAt: Date(), processingVersion: "v2"),
        blocks: [block],
        sections: [section],
        headings: ["Cached"],
        lists: [],
        codeBlocks: [],
        equations: [],
        tables: [],
        statistics: DocumentStatistics(characterCount: 15, normalizedCharacterCount: 15, wordCount: 2, sentenceCount: 1, lineCount: 1, blankLineCount: 0, blockCount: 1, sectionCount: 1, headingCount: 0, paragraphCount: 1, bulletedListCount: 0, numberedListCount: 0, tableCount: 0, codeBlockCount: 0, equationCount: 0, quoteCount: 0),
        complexity: DocumentComplexityEstimate(),
        tokenEstimate: DocumentTokenEstimate(estimatedTotalTokens: 3, blockEstimates: [DocumentBlockTokenEstimate(blockID: block.id, blockIndex: 0, kind: .paragraph, estimatedTokens: 3)], sectionEstimates: [DocumentSectionTokenEstimate(sectionID: section.id, sectionIndex: 0, estimatedTokens: 3, startBlockIndex: 0, endBlockIndex: 0)], suggestedChunkBoundaries: [DocumentChunkBoundary(startBlockIndex: 0, endBlockIndex: 0, estimatedTokens: 3, sectionID: section.id, isHardBoundary: true)], method: .approximateWordRatio, targetChunkSize: 320)
    )
}

private func makeTokenTestStructure(text: String) -> (document: ProcessedDocument, blocks: [DocumentBlock], sections: [DocumentSection]) {
    let document = ProcessedDocument(title: "Token", originalText: text, normalizedText: text, lines: [text], contentHash: "token")
    let block = paragraphBlock(text, line: 0)
    let section = makeSection(id: "section-1", title: "Body", level: 0, blockIDs: [block.id])
    return (document, [block], [section])
}

private func temporaryCacheURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("document-structure-cache-\(UUID().uuidString).json")
}

private final class PipelineRecorder: DocumentProcessingNormalizing, StructureDetecting, SectionSplitting, DocumentComplexityEstimating, DocumentTokenEstimating, DocumentStructureCaching {
    var events: [String] = []

    func normalize(title: String, text: String) -> ProcessedDocument {
        events.append("processor")
        return ProcessedDocument(title: title, originalText: text, normalizedText: text, lines: text.isEmpty ? [] : text.components(separatedBy: "\n"), contentHash: ProcessedDocument.contentHash(for: title, text: text))
    }

    func detect(in document: ProcessedDocument) -> [DocumentBlock] {
        events.append("detector")
        return [paragraphBlock(document.normalizedText.isEmpty ? "Body" : document.normalizedText, line: 0)]
    }

    func split(title: String, blocks: [DocumentBlock]) -> DocumentSectionSplitResult {
        events.append("splitter")
        let section = makeSection(id: "section-1", title: title, level: 0, blockIDs: blocks.map(\.id))
        let mappedBlocks = blocks.map { block in
            var block = block
            block.sectionID = section.id
            return block
        }
        return DocumentSectionSplitResult(blocks: mappedBlocks, sections: [section])
    }

    func estimate(document: ProcessedDocument, blocks: [DocumentBlock], sections: [DocumentSection], statistics: DocumentStatistics) -> DocumentComplexityEstimate {
        events.append("complexity")
        return DocumentComplexityEstimate(
            readingDifficulty: .easy,
            conceptDensity: 0,
            estimatedStudyMinutes: 1,
            structuralDensity: 0,
            tokenEstimate: statistics.wordCount,
            headingCount: statistics.headingCount,
            listCount: statistics.bulletedListCount + statistics.numberedListCount,
            codeBlockCount: statistics.codeBlockCount,
            equationCount: statistics.equationCount,
            tableCount: statistics.tableCount,
            sentenceCount: statistics.sentenceCount,
            complexityScore: 0.25,
            sectionCount: sections.count,
            averageSentenceLength: 1,
            sectionMetrics: []
        )
    }

    func estimate(document: ProcessedDocument, blocks: [DocumentBlock], sections: [DocumentSection], targetChunkSize: Int) -> DocumentTokenEstimate {
        events.append("token")
        return DocumentTokenEstimate(
            estimatedTotalTokens: max(1, blocks.count),
            blockEstimates: blocks.enumerated().map { index, block in
                DocumentBlockTokenEstimate(blockID: block.id, blockIndex: index, kind: block.kind, estimatedTokens: 1)
            },
            sectionEstimates: sections.enumerated().map { index, section in
                DocumentSectionTokenEstimate(sectionID: section.id, sectionIndex: index, estimatedTokens: max(1, blocks.count), startBlockIndex: 0, endBlockIndex: max(0, blocks.count - 1))
            },
            suggestedChunkBoundaries: [DocumentChunkBoundary(startBlockIndex: 0, endBlockIndex: max(0, blocks.count - 1), estimatedTokens: max(1, blocks.count), sectionID: sections.first?.id, isHardBoundary: true)],
            method: .approximateWordRatio,
            targetChunkSize: targetChunkSize
        )
    }

    func estimatedTokenCount(for text: String) -> Int {
        max(1, text.split { $0.isWhitespace || $0.isNewline }.count)
    }

    func cachedStructure(for contentHash: String) -> DocumentStructure? {
        events.append("cache-read")
        return nil
    }

    func store(_ structure: DocumentStructure, for contentHash: String) {
        events.append("cache-store")
    }

    func removeStructure(for contentHash: String) {}
    func clear() {}
}

private final class FailingProcessor: DocumentProcessingNormalizing {
    func normalize(title: String, text: String) -> ProcessedDocument {
        ProcessedDocument(title: title, originalText: text, normalizedText: text, lines: text.isEmpty ? [] : text.components(separatedBy: "\n"), contentHash: "bad")
    }
}

private final class FailingTokenEstimator: DocumentTokenEstimating {
    func estimate(document: ProcessedDocument, blocks: [DocumentBlock], sections: [DocumentSection], targetChunkSize: Int) -> DocumentTokenEstimate {
        DocumentTokenEstimate(
            estimatedTotalTokens: 1,
            blockEstimates: [DocumentBlockTokenEstimate(blockID: blocks.first?.id ?? "block", blockIndex: 0, kind: .paragraph, estimatedTokens: 1)],
            sectionEstimates: [DocumentSectionTokenEstimate(sectionID: sections.first?.id ?? "section", sectionIndex: 0, estimatedTokens: 1, startBlockIndex: 0, endBlockIndex: 0)],
            suggestedChunkBoundaries: [DocumentChunkBoundary(startBlockIndex: 0, endBlockIndex: 99, estimatedTokens: 1, sectionID: sections.first?.id, isHardBoundary: true)],
            method: .approximateWordRatio,
            targetChunkSize: targetChunkSize
        )
    }

    func estimatedTokenCount(for text: String) -> Int {
        1
    }
}
