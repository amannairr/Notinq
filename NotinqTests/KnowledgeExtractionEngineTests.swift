import XCTest
@testable import Notinq

@MainActor
final class KnowledgeExtractionEngineTests: XCTestCase {
    func testRepeatedExtractionUsesCache() async throws {
        KnowledgeExtractionEngine.shared.clearCache()

        let note = """
        # Cell Theory

        Cell is the basic unit of life.
        Cells divide to form new cells.
        Cell membrane protects the cell.
        """

        let first = await KnowledgeExtractionEngine.shared.extractRun(
            noteTitle: "Cell Theory",
            noteText: note
        )
        let second = await KnowledgeExtractionEngine.shared.extractRun(
            noteTitle: "Cell Theory",
            noteText: note
        )

        XCTAssertFalse(first.fromCache)
        XCTAssertTrue(second.fromCache)
        XCTAssertEqual(first.knowledge.metadata.sourceSignature, second.knowledge.metadata.sourceSignature)
    }

    func testHeuristicExtractionBuildsConceptsAndRelationships() async throws {
        let note = """
        # Cell Theory

        Cell is the basic unit of life.
        Cells divide to form new cells.
        Cell membrane protects the cell.
        """

        let run = await KnowledgeExtractionEngine.shared.extractRun(
            noteTitle: "Cell Theory",
            noteText: note
        )

        XCTAssertFalse(run.knowledge.concepts.isEmpty)
        XCTAssertFalse(run.knowledge.relationships.isEmpty)
        XCTAssertEqual(run.knowledge.metadata.title, "Cell Theory")
        XCTAssertTrue(run.knowledge.concepts.allSatisfy { $0.confidence >= 0 && $0.confidence <= 1 })
    }

    func testExtractionDropsConversationalNoiseAndKeepsTechnicalTerms() async throws {
        KnowledgeExtractionEngine.shared.clearCache()

        let note = """
        Good morning everyone. Today we are discussing long-term potentiation.

        Long-term potentiation is a persistent strengthening of synapses after repeated activation.
        NMDA activation triggers calcium influx.
        Calcium influx leads to CaMKII activation and AMPA insertion.
        Specifically, this is the core mechanism.
        """

        let run = await KnowledgeExtractionEngine.shared.extractRun(
            noteTitle: "Neuroscience Lecture",
            noteText: note
        )

        let topicBlob = (run.knowledge.topics + run.knowledge.keywords + run.knowledge.concepts.map(\.name))
            .joined(separator: " ")
            .lowercased()

        XCTAssertTrue(topicBlob.contains("potentiation"))
        XCTAssertTrue(topicBlob.contains("nmda"))
        XCTAssertTrue(topicBlob.contains("ampa"))
        XCTAssertFalse(topicBlob.contains("good"))
        XCTAssertFalse(topicBlob.contains("morning"))
        XCTAssertFalse(topicBlob.contains("today"))
        XCTAssertFalse(topicBlob.contains("specifically"))
    }

    func testExtractionCapturesAliasesDefinitionsAndCanonicalRelationships() async throws {
        KnowledgeExtractionEngine.shared.clearCache()

        let note = """
        # Synaptic Plasticity

        Long-term potentiation (LTP) is a persistent strengthening of synapses after repeated activation.
        NMDA activation causes calcium influx.
        Calcium influx produces AMPA insertion.
        """

        let run = await KnowledgeExtractionEngine.shared.extractRun(
            noteTitle: "Synaptic Plasticity",
            noteText: note
        )

        let potentiation = run.knowledge.concepts.first { $0.name.lowercased().contains("long term potentiation") }
        XCTAssertNotNil(potentiation)
        XCTAssertTrue(potentiation?.aliases.contains(where: { $0.uppercased() == "LTP" }) ?? false)
        XCTAssertFalse(potentiation?.definition.isEmpty ?? true)
        XCTAssertTrue(potentiation?.definition.lowercased().contains("persistent strengthening") ?? false)
        XCTAssertFalse(potentiation?.definitionEvidence.isEmpty ?? true)

        XCTAssertTrue(
            run.knowledge.relationships.contains(where: { $0.relationKind == .causes }),
            "Relationship kinds: \(run.knowledge.relationships.map { $0.relationKind.rawValue })"
        )
        XCTAssertTrue(run.knowledge.relationships.contains(where: { $0.relationKind == .produces }))
        XCTAssertTrue(run.knowledge.relationships.allSatisfy { !$0.relation.isEmpty })
    }

    func testExtractionDebugReportIncludesQualityMetrics() async throws {
        let note = """
        # Enzymes

        Enzymes are biological catalysts.
        Enzymes lower activation energy.
        """

        let report = await KnowledgeExtractionEngine.shared.inspectExtraction(
            noteTitle: "Enzymes",
            noteText: note
        )

        XCTAssertEqual(report.title, "Enzymes")
        XCTAssertGreaterThan(report.metrics.conceptCount, 0)
        XCTAssertGreaterThanOrEqual(report.metrics.definitionCount, 0)
        XCTAssertGreaterThan(report.metrics.averageConceptConfidence, 0)
        XCTAssertFalse(report.topConcepts.isEmpty)
        XCTAssertNotNil(report.validation)
        XCTAssertGreaterThanOrEqual(report.metrics.conceptCount, report.topConcepts.count)
    }

    func testExtractionDebugReportIncludesChunkDetails() async throws {
        let note = """
        # Systems Thinking

        Feedback loops stabilize systems.
        Positive feedback amplifies change.
        Negative feedback reduces deviation.
        """

        let report = await KnowledgeExtractionEngine.shared.inspectExtraction(
            noteTitle: "Systems Thinking",
            noteText: note
        )

        XCTAssertFalse(report.chunkRuns.isEmpty)
        XCTAssertFalse(report.mergedKnowledge.title.isEmpty)
        XCTAssertGreaterThanOrEqual(report.tokenCount, 0)
        XCTAssertGreaterThanOrEqual(report.latency, 0)
        XCTAssertGreaterThanOrEqual(report.chunkRuns.first?.tokenCount ?? 0, 0)
        XCTAssertFalse(report.chunkRuns.first?.rawChunk.isEmpty ?? true)
    }

    func testSemanticChunkerRetainsChunkMetadata() {
        let note = """
        # Scheduling

        Tasks are grouped by priority.

        - High priority tasks are completed first.
        - Medium priority tasks come next.
        """

        let structure = DocumentPreprocessor.shared.preprocess(title: "Scheduling", text: note)
        let chunks = SemanticChunker.shared.chunk(title: "Scheduling", structure: structure, contextLimit: 256)

        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { !$0.documentID.isEmpty })
        XCTAssertTrue(chunks.allSatisfy { !$0.sectionName.isEmpty })
        XCTAssertTrue(chunks.allSatisfy { !$0.paragraphIDs.isEmpty })
    }

    func testQwen3IsThePreferredLocalModel() {
        let library = AIModelLibrary.shared
        let snapshot = library.refreshSnapshot()
        XCTAssertEqual(library.preferredModelID, "qwen-3-4b")
        XCTAssertEqual(library.preferredCatalogModel(for: .advanced)?.id, "qwen-3-4b")
        XCTAssertEqual(snapshot.catalog.first?.fileName, "Qwen3-4B-Q4_K_M.gguf")
    }

    func testValidatorFlagsDuplicateConceptsAndInvalidRelationships() {
        let knowledge = StructuredKnowledge(
            metadata: KnowledgeMetadata(title: "Biology 101", sourceType: "note"),
            title: "Biology 101",
            concepts: [
                KnowledgeConcept(id: "cell-1", name: "Cell", definition: "Basic unit of life", confidence: 0.9),
                KnowledgeConcept(id: "cell-2", name: "Cell", definition: "Basic unit of life", confidence: 0.8)
            ],
            definitions: [
                KnowledgeDefinition(id: "def-1", term: "Cell", definition: "Basic unit of life", confidence: 0.8)
            ],
            relationships: [
                KnowledgeRelationship(id: "rel-1", sourceID: "cell-1", targetID: "missing", relation: "includes", confidence: 0.8)
            ]
        )

        let report = KnowledgeValidator.validate(payload: knowledge, structure: nil)

        XCTAssertGreaterThan(report.duplicateConceptCount, 0)
        XCTAssertGreaterThan(report.invalidReferenceCount, 0)
        XCTAssertFalse(report.isValid)
        XCTAssertTrue(report.shouldRetry)
        XCTAssertGreaterThanOrEqual(report.confidenceFloor, 0)
        XCTAssertLessThanOrEqual(report.confidenceFloor, 1)
    }

    func testPartialExtractionRemainsValidWhenCoreFieldsArePresent() {
        let knowledge = StructuredKnowledge(
            metadata: KnowledgeMetadata(title: "History Notes", sourceType: "note"),
            title: "History Notes",
            sections: [
                KnowledgeSection(title: "Intro", kind: .heading, order: 0, content: "Intro", children: [])
            ],
            concepts: [
                KnowledgeConcept(id: "world-war-ii", name: "World War II", definition: "A global conflict", confidence: 0.85)
            ],
            confidence: 0.85
        )

        let structure = DocumentPreprocessor.shared.preprocess(title: "History Notes", text: "# Intro\nWorld War II")
        let report = KnowledgeValidator.validate(payload: knowledge, structure: structure)

        XCTAssertTrue(report.isValid)
        XCTAssertFalse(report.shouldRetry)
    }

    func testMalformedModelOutputCanBeRepairedIntoStructuredKnowledge() throws {
        let malformed = """
        ```json
        {
          "metadata": { "title": "Chemistry" },
          "title": "Chemistry",
          "sections": [],
          "concepts": [],
          "relationships": [],
          "confidence": 0.82,
        }
        ```
        """

        guard let repaired = PromptRepairer.repairJSONString(malformed) else {
            XCTFail("Expected JSON repair to succeed")
            return
        }

        let data = Data(repaired.utf8)
        let decoded = try JSONDecoder().decode(StructuredKnowledge.self, from: data)

        XCTAssertEqual(decoded.title, "Chemistry")
        XCTAssertEqual(decoded.metadata.title, "Chemistry")
        XCTAssertGreaterThanOrEqual(decoded.confidence, 0.8)
    }
}
