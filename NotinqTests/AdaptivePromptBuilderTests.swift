import XCTest
@testable import Notinq

final class AdaptivePromptBuilderTests: XCTestCase {
    func testPromptContainsAdaptiveKnowledgeSections() {
        let atpID = UUID()
        let mitochondriaID = UUID()
        let noteID = UUID()
        let atp = Concept(id: atpID, name: "ATP", description: "Energy currency", aliases: [], noteID: noteID, confidence: 0.9, importanceScore: 0.9, difficultyScore: 0.2)
        let mitochondria = Concept(id: mitochondriaID, name: "Mitochondria", description: "Organelle", aliases: [], noteID: noteID, confidence: 0.9, importanceScore: 0.9, difficultyScore: 0.2)
        let relationship = ConceptRelationship(
            id: UUID(),
            sourceConceptID: atpID,
            destinationConceptID: mitochondriaID,
            type: .partOf,
            confidence: 0.9
        )
        let graphContext = GraphContext(
            concepts: [
                CanonicalConceptRecord(id: atpID.uuidString, canonicalName: "ATP", aliases: ["Adenosine Triphosphate"], sourceReferences: [], confidence: 0.9, description: "Energy currency"),
                CanonicalConceptRecord(id: mitochondriaID.uuidString, canonicalName: "Mitochondria", aliases: [], sourceReferences: [], confidence: 0.9, description: "Organelle")
            ],
            relationships: [
                KnowledgeRelationshipRecord(
                    id: "atp-mito",
                    sourceConceptID: atpID.uuidString,
                    targetConceptID: mitochondriaID.uuidString,
                    relationType: KnowledgeRelationshipKind.partOf.rawValue,
                    confidence: 0.9,
                    provenance: []
                )
            ],
            prerequisiteChains: [["Cellular Respiration", "ATP"]],
            paths: [],
            explanations: []
        )
        let context = AdaptiveTutorContext(
            question: "Explain ATP.",
            retrievedNotes: [
                RetrievedChunk(id: "chunk-1", noteID: UUID(), noteTitle: "ATP Notes", title: "ATP", content: "ATP is produced in mitochondria.", snippet: "ATP is produced in mitochondria.", sourceType: .chunk, relevance: 1)
            ],
            relevantConcepts: [atp, mitochondria],
            relationships: [relationship],
            weakConcepts: [mitochondria],
            strongConcepts: [atp],
            prerequisites: [mitochondria],
            missingPrerequisites: [mitochondria],
            studyPlanRecommendations: ["Review Mitochondria."],
            masteryMap: [:],
            knowledgeGaps: [mitochondria],
            relatedConcepts: [atp, mitochondria],
            reviewHistory: [],
            graphContext: graphContext
        )

        let prompt = AdaptivePromptBuilder().buildPrompt(from: context)

        XCTAssertTrue(prompt.contains("KNOWN WELL"))
        XCTAssertTrue(prompt.contains("WEAK"))
        XCTAssertTrue(prompt.contains("MISSING PREREQUISITES"))
        XCTAssertTrue(prompt.contains("GRAPH CONTEXT"))
        XCTAssertTrue(prompt.contains("Knowledge Graph"))
        XCTAssertTrue(prompt.contains("PART_OF -> Mitochondria"))
        XCTAssertTrue(prompt.contains("Cellular Respiration -> ATP"))
        XCTAssertTrue(prompt.contains("- Mitochondria"))
        XCTAssertTrue(prompt.contains("Retrieved Note Context"))
        XCTAssertTrue(prompt.contains("Explain ATP."))
        XCTAssertTrue(prompt.contains("Avoid re-teaching concepts already mastered."))
        XCTAssertLessThan(prompt.split(separator: " ").count, 700)
    }

    func testAdaptiveRequestCarriesContextSizeMetadataAndTokenBudget() {
        let noteID = UUID()
        let concept = Concept(id: UUID(), name: "Limits", description: "Foundation for calculus", aliases: [], noteID: noteID, confidence: 0.8, importanceScore: 0.8, difficultyScore: 0.3)
        let context = AdaptiveTutorContext(
            question: "Explain derivatives.",
            retrievedNotes: [],
            relevantConcepts: [concept],
            relationships: [],
            weakConcepts: [concept],
            strongConcepts: [],
            prerequisites: [concept],
            missingPrerequisites: [concept],
            studyPlanRecommendations: ["Review Limits."],
            masteryMap: [concept.id: 0.2],
            knowledgeGaps: [concept],
            relatedConcepts: [concept],
            reviewHistory: [],
            graphContext: .empty
        )

        let request = AdaptiveTutorService().request(
            for: context,
            requestKind: "testAdaptive",
            maxTokens: 256
        )

        XCTAssertEqual(request.maxTokens, 256)
        XCTAssertEqual(request.metadata["graphAware"], "true")
        XCTAssertEqual(request.metadata["adaptiveContextConcepts"], "1")
        XCTAssertEqual(request.metadata["adaptiveContextGaps"], "1")
        XCTAssertTrue(request.prompt.contains("WEAK"))
        XCTAssertTrue(request.prompt.contains("MISSING PREREQUISITES"))
    }
}
