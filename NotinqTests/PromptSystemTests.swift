import XCTest
@testable import Notinq

@MainActor
final class PromptSystemTests: XCTestCase {
    func testDownstreamPromptsDoNotReadTranscriptText() {
        let sentinel = "TRANSCRIPT_SENTINEL_DO_NOT_USE"
        let knowledge = PromptTestFixtures.sampleStructuredKnowledge(from: PromptTestFixtures.commonCases[0])
        let context = AIPromptContext(
            noteTitle: "Biology 101",
            noteText: sentinel,
            knowledgeJSON: PromptJSONSupport.encode(knowledge),
            selectedText: nil,
            userRequest: "How does the membrane work?"
        )

        let requests = [
            PromptRegistry.shared.jsonRequest(for: .summary, context: context),
            PromptRegistry.shared.jsonRequest(for: .flashcards, context: context),
            PromptRegistry.shared.jsonRequest(for: .multipleChoiceQuiz, context: context),
            PromptRegistry.shared.jsonRequest(for: .learningInsights, context: context),
            PromptRegistry.shared.jsonRequest(for: .conceptMap, context: context),
            PromptRegistry.shared.jsonRequest(for: .aiTutor, context: context)
        ]

        for request in requests {
            XCTAssertFalse(request.prompt.contains(sentinel))
            XCTAssertFalse(request.systemPrompt?.contains(sentinel) ?? false)
        }
    }

    func testPromptRegistryBuildsStructuredSummaryRequest() {
        let knowledge = PromptTestFixtures.sampleStructuredKnowledge(from: PromptTestFixtures.commonCases[0])
        let context = AIPromptContext(
            noteTitle: "Biology 101",
            noteText: "",
            knowledgeJSON: PromptJSONSupport.encode(knowledge),
            selectedText: nil,
            userRequest: nil
        )

        let request = PromptRegistry.shared.jsonRequest(for: .summary, context: context)

        XCTAssertEqual(request.responseFormat, .json)
        XCTAssertTrue(request.systemPrompt?.contains("study summary") ?? false)
        XCTAssertTrue(request.prompt.contains("Structured knowledge JSON"))
    }

    func testPromptCatalogExposesMetadataForAllPrompts() {
        XCTAssertGreaterThanOrEqual(PromptCatalog.entries.count, 15)

        for entry in PromptCatalog.entries {
            XCTAssertFalse(entry.id.isEmpty)
            XCTAssertFalse(entry.version.isEmpty)
            XCTAssertFalse(entry.description.isEmpty)
            XCTAssertFalse(entry.supportedProviders.isEmpty)
            XCTAssertFalse(entry.inputType.isEmpty)
            XCTAssertFalse(entry.outputType.isEmpty)
            XCTAssertFalse(entry.expectedLatency.isEmpty)
            XCTAssertGreaterThan(entry.estimatedTokens, 0)
        }
    }

    func testPromptDocumentationIsAvailableForEachPrompt() {
        for identifier in AIPromptIdentifier.allCases {
            let documentation = PromptCatalog.documentation(for: identifier)
            XCTAssertTrue(documentation.contains("Purpose:"))
            XCTAssertTrue(documentation.contains("Inputs:"))
            XCTAssertTrue(documentation.contains("Outputs:"))
        }
    }

    func testRepresentativePromptFixturesCoverCommonInputShapes() {
        let fixtures = PromptTestFixtures.commonCases
        XCTAssertTrue(fixtures.contains(where: { $0.kind == .shortLecture }))
        XCTAssertTrue(fixtures.contains(where: { $0.kind == .longLecture }))
        XCTAssertTrue(fixtures.contains(where: { $0.kind == .poorOCR }))
        XCTAssertTrue(fixtures.contains(where: { $0.kind == .technical }))
        XCTAssertTrue(fixtures.contains(where: { $0.kind == .humanities }))
        XCTAssertTrue(fixtures.contains(where: { $0.kind == .mixedFormatting }))
    }

    func testEveryPromptRendersTheStandardSixSectionShape() {
        let fixtures = PromptTestFixtures.commonCases
        let knowledge = PromptTestFixtures.sampleStructuredKnowledge(from: fixtures[0])
        let graph = PromptTestFixtures.sampleGraph()

        let requests: [(String, AIGenerationRequest)] = [
            ("knowledgeExtraction", PromptRegistry.shared.buildRequest(for: KnowledgeExtractionPrompt.self, input: PromptExtractionInput(noteTitle: fixtures[2].noteTitle, noteText: fixtures[2].noteText))),
            ("summary", PromptRegistry.shared.buildRequest(for: SummaryPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[0].noteTitle, knowledge: knowledge))),
            ("flashcards", PromptRegistry.shared.buildRequest(for: FlashcardsPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[1].noteTitle, knowledge: knowledge))),
            ("quiz", PromptRegistry.shared.buildRequest(for: QuizPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[4].noteTitle, knowledge: knowledge))),
            ("learningInsights", PromptRegistry.shared.buildRequest(for: LearningInsightsPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[3].noteTitle, knowledge: knowledge))),
            ("conceptMap", PromptRegistry.shared.buildRequest(for: ConceptMapPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[5].noteTitle, knowledge: knowledge))),
            ("knowledgeGraphExpansion", PromptRegistry.shared.buildRequest(for: KnowledgeGraphExpansionPrompt.self, input: PromptGraphInput(noteTitle: fixtures[0].noteTitle, graph: graph))),
            ("tutor", PromptRegistry.shared.buildRequest(for: TutorPrompt.self, input: PromptTutorInput(noteTitle: fixtures[0].noteTitle, knowledge: knowledge, question: "What is the cell membrane?"))),
            ("definitions", PromptRegistry.shared.buildRequest(for: DefinitionsPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[0].noteTitle, knowledge: knowledge))),
            ("timeline", PromptRegistry.shared.buildRequest(for: TimelinePrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[1].noteTitle, knowledge: knowledge))),
            ("formulaExtraction", PromptRegistry.shared.buildRequest(for: FormulaExtractionPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[3].noteTitle, knowledge: knowledge))),
            ("revisionPlan", PromptRegistry.shared.buildRequest(for: RevisionPlanPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[4].noteTitle, knowledge: knowledge))),
            ("cheatSheet", PromptRegistry.shared.buildRequest(for: CheatSheetPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[5].noteTitle, knowledge: knowledge))),
            ("podcast", PromptRegistry.shared.buildRequest(for: PodcastPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[1].noteTitle, knowledge: knowledge))),
            ("comparison", PromptRegistry.shared.buildRequest(for: ComparisonPrompt.self, input: PromptComparisonInput(leftTitle: fixtures[0].noteTitle, rightTitle: fixtures[1].noteTitle, leftJSON: fixtures[0].noteText, rightJSON: fixtures[1].noteText))),
            ("actionItems", PromptRegistry.shared.buildRequest(for: ActionItemsPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[4].noteTitle, knowledge: knowledge))),
            ("assistantChat", PromptRegistry.shared.buildRequest(for: AIHelperChatPrompt.self, input: PromptExtractionInput(noteTitle: fixtures[0].noteTitle, noteText: fixtures[0].noteText))),
            ("directEditing", PromptRegistry.shared.buildRequest(for: DirectEditPrompt.self, input: PromptExtractionInput(noteTitle: fixtures[5].noteTitle, noteText: fixtures[5].noteText))),
            ("practiceQuestions", PromptRegistry.shared.buildRequest(for: AIActionItemsPrompt.self, input: PromptStructuredKnowledgeInput(noteTitle: fixtures[3].noteTitle, knowledge: knowledge)))
        ]

        for (name, request) in requests {
            let systemPrompt = request.systemPrompt ?? ""
            XCTAssertTrue(systemPrompt.contains("Role:"), "\(name) missing Role")
            XCTAssertTrue(systemPrompt.contains("Objective:"), "\(name) missing Objective")
            XCTAssertTrue(systemPrompt.contains("Input:"), "\(name) missing Input")
            XCTAssertTrue(systemPrompt.contains("Rules:"), "\(name) missing Rules")
            XCTAssertTrue(systemPrompt.contains("Output Schema:"), "\(name) missing Output Schema")
            XCTAssertTrue(systemPrompt.contains("Failure Rules:"), "\(name) missing Failure Rules")
            XCTAssertTrue(request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(name) should keep user prompt empty")
            XCTAssertFalse(systemPrompt.localizedCaseInsensitiveContains("markdown"), "\(name) should not mention markdown")
        }
    }

    func testPromptOptimizerPrefersCompactLocalPhiStylePrompts() {
        let document = PromptDocument.json(
            systemPrompt: "System",
            userPrompt: "User",
            maxTokens: 600,
            schema: PromptCatalog.summarySchema
        )

        let optimized = PromptOptimizer.optimize(document, for: .localLlama, modelIdentifier: "phi-4-mini-instruct")

        XCTAssertEqual(optimized.profile.family, .phi)
        XCTAssertLessThanOrEqual(optimized.document.maxTokens, document.maxTokens)
        XCTAssertTrue(optimized.document.systemPrompt.contains("Prefer concise, direct outputs."))
    }

    func testPromptRepairerExtractsJSONObjectFromWrappedText() throws {
        struct Payload: Codable, Equatable {
            var name: String
        }

        let repaired = PromptRepairer.repair("""
        ```json
        { "name": "Notinq" }
        ```
        """, as: Payload.self)

        XCTAssertEqual(repaired, Payload(name: "Notinq"))
    }

    func testConceptMapUsesRelationshipsOnly() {
        let knowledge = PromptTestFixtures.sampleStructuredKnowledge(from: PromptTestFixtures.commonCases[0])
        let rendered = LearningEngine.shared.generateConceptMap(from: knowledge)

        let titles = flattenConceptTitles(rendered)

        XCTAssertTrue(titles.contains("Cell membrane"))
        XCTAssertTrue(titles.contains("Transport"))
    }
}

private enum PromptFixtureKind: String, CaseIterable {
    case shortLecture
    case longLecture
    case poorOCR
    case technical
    case humanities
    case mixedFormatting
}

private struct PromptTestFixture {
    let kind: PromptFixtureKind
    let noteTitle: String
    let noteText: String
}

private enum PromptTestFixtures {
    static let commonCases: [PromptTestFixture] = [
        PromptTestFixture(kind: .shortLecture, noteTitle: "Biology Short Lecture", noteText: "The cell membrane controls what enters and exits the cell."),
        PromptTestFixture(kind: .longLecture, noteTitle: "History Long Lecture", noteText: String(repeating: "The Industrial Revolution changed work and production. ", count: 12)),
        PromptTestFixture(kind: .poorOCR, noteTitle: "OCR Notes", noteText: "Th3 c3ll m3mbran3 pr0t3cts th3 c3ll."),
        PromptTestFixture(kind: .technical, noteTitle: "Computer Science", noteText: "A binary search tree maintains ordering: left subtree < node < right subtree."),
        PromptTestFixture(kind: .humanities, noteTitle: "Literature", noteText: "Themes, symbolism, and narrative voice shape the interpretation."),
        PromptTestFixture(kind: .mixedFormatting, noteTitle: "Mixed Notes", noteText: "# Heading\n- Bullet 1\n1. Numbered item\nCode: let x = 1")
    ]

    static func sampleKnowledgeSnapshot(from fixture: PromptTestFixture) -> StudyKnowledgeSnapshot {
        StudyKnowledgeSnapshot(
            title: fixture.noteTitle,
            sourceSignature: fixture.noteText,
            cleanedText: fixture.noteText,
            normalizedText: fixture.noteText.lowercased(),
            topics: [fixture.noteTitle],
            concepts: [
                StudyKnowledgeItem(title: "Cell membrane", summary: "Protects the cell and controls transport", evidence: [fixture.noteText], importance: 0.9, difficulty: 0.4, aliases: ["membrane"], relatedTitles: ["Transport"], category: "biology"),
                StudyKnowledgeItem(title: "Transport", summary: "Movement into and out of the cell", evidence: [fixture.noteText], importance: 0.8, difficulty: 0.5, aliases: [], relatedTitles: ["Cell membrane"], category: "biology")
            ],
            definitions: [
                StudyKnowledgeItem(title: "Cell membrane", summary: "The boundary that regulates passage", evidence: [fixture.noteText], importance: 0.8, difficulty: 0.4, aliases: [], relatedTitles: [], category: "definition")
            ],
            relationships: [
                StudyKnowledgeRelationship(sourceTitle: "Cell membrane", targetTitle: "Transport", relation: "controls", confidence: 0.9)
            ],
            examples: [
                StudyKnowledgeItem(title: "Selective permeability", summary: "Example of membrane behavior", evidence: [fixture.noteText], importance: 0.7, difficulty: 0.5, aliases: [], relatedTitles: [], category: "example")
            ],
            procedures: [],
            formulas: [],
            importantFacts: [],
            keyTerms: [],
            misconceptions: [],
            prerequisites: [],
            hierarchy: [
                StudyKnowledgeNode(title: "Biology", summary: "Top-level topic", children: [
                    StudyKnowledgeNode(title: "Cell membrane", summary: "Controls transport", children: [])
                ])
            ],
            supportingExamples: [],
            supportingEvidence: [fixture.noteText],
            summaryHighlights: [fixture.noteTitle],
            examFocus: ["Explain the role of the cell membrane"],
            tokenEstimate: max(1, fixture.noteText.split { $0.isWhitespace || $0.isNewline }.count),
            extractionStrategy: "deterministic"
        )
    }

    static func sampleStructuredKnowledge(from fixture: PromptTestFixture) -> StructuredKnowledge {
        sampleKnowledgeSnapshot(from: fixture).structuredKnowledgeRepresentation()
    }

    static func sampleGraph() -> KnowledgeGraph {
        let noteID = UUID()
        let sourceID = UUID()
        let targetID = UUID()
        return KnowledgeGraph(
            noteID: noteID,
            concepts: [
                Concept(id: sourceID, name: "Cell membrane", description: "Boundary controlling transport", aliases: ["membrane"], noteID: noteID, confidence: 0.9, importanceScore: 0.9, difficultyScore: 0.4),
                Concept(id: targetID, name: "Transport", description: "Movement across the membrane", aliases: [], noteID: noteID, confidence: 0.9, importanceScore: 0.8, difficultyScore: 0.5)
            ],
            relationships: [
                ConceptRelationship(sourceConceptID: sourceID, destinationConceptID: targetID, type: .applicationOf, confidence: 0.9)
            ],
            lastUpdated: Date()
        )
    }
}

private func flattenConceptTitles(_ nodes: [StudyConceptNode]) -> [String] {
    nodes.flatMap { node in
        [node.title] + flattenConceptTitles(node.children)
    }
}
