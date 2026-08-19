import XCTest
@testable import Notinq

@MainActor
final class DownstreamGenerationEvaluationTests: XCTestCase {

    func testBiologyDownstreamGenerationMatrix() async throws {
        let knowledge = biologyKnowledge()
        let context = PromptBuildContext(
            noteTitle: "Biology Lecture",
            structuredKnowledge: knowledge,
            modelIdentifier: ModelManager.shared.activeModelIDDescription()
        )
        let input = PromptStructuredKnowledgeInput(noteTitle: "Biology Lecture", knowledge: knowledge)

        let summary = try await PromptRegistry.shared.execute(SummaryPrompt.self, input: input, context: context)
        let flashcards = try await PromptRegistry.shared.execute(FlashcardsPrompt.self, input: input, context: context)
        let quiz = try await PromptRegistry.shared.execute(QuizPrompt.self, input: input, context: context)
        let conceptMap = try await PromptRegistry.shared.execute(ConceptMapPrompt.self, input: input, context: context)
        let insights = try await PromptRegistry.shared.execute(LearningInsightsPrompt.self, input: input, context: context)
        let directTutor = try await PromptRegistry.shared.execute(
            TutorPrompt.self,
            input: PromptTutorInput(noteTitle: "Biology Lecture", knowledge: knowledge, question: "Why is the cell membrane important?"),
            context: context
        )
        let unsupportedTutor = try await PromptRegistry.shared.execute(
            TutorPrompt.self,
            input: PromptTutorInput(noteTitle: "Biology Lecture", knowledge: knowledge, question: "Who discovered mitochondria?"),
            context: context
        )

        print("BIologySummaryLatency=\(summary.metrics.latency)")
        print("BiologySummaryRetry=\(summary.metrics.retryCount)")
        print("BiologySummaryRepair=\(summary.metrics.repairCount)")
        print("BiologySummaryValid=\(summary.validation.isValid)")
        print("BiologySummary=\(summary.output)")
        print("BiologyFlashcardsCount=\(flashcards.output.cards.count)")
        print("BiologyFlashcardsFirst=\(flashcards.output.cards.prefix(3).map { "\($0.front) -> \($0.back)" }.joined(separator: " || "))")
        print("BiologyQuizCount=\(quiz.output.questions.count)")
        print("BiologyQuizFirst=\(quiz.output.questions.prefix(3).map { "\($0.prompt) => \($0.correctAnswer)" }.joined(separator: " || "))")
        print("BiologyConceptMapCount=\(conceptMap.output.count)")
        print("BiologyConceptMapFirst=\(conceptMap.output.prefix(3).map { "\($0.title)->\($0.children.map { $0.title }.joined(separator: ","))" }.joined(separator: " || "))")
        print("BiologyInsightsKeys=\(insights.output.keyConcepts)")
        print("BiologyInsightsImportant=\(insights.output.importantConcepts)")
        print("BiologyInsightsGaps=\(insights.output.knowledgeGaps)")
        print("BiologyTutorDirect=\(directTutor.output.answer)")
        print("BiologyTutorUnsupported=\(unsupportedTutor.output.answer)")

        XCTAssertTrue(summary.validation.isValid)
        XCTAssertGreaterThanOrEqual(flashcards.output.cards.count, 2)
        XCTAssertGreaterThanOrEqual(quiz.output.questions.count, 2)
        XCTAssertGreaterThanOrEqual(conceptMap.output.count, 1)
        XCTAssertFalse(insights.output.keyConcepts.isEmpty)
        XCTAssertFalse(directTutor.output.answer.isEmpty)
        XCTAssertTrue(unsupportedTutor.output.answer.contains("not contain enough information"))
    }

    func testComputerScienceDownstreamGenerationMatrix() async throws {
        let knowledge = computerScienceKnowledge()
        let context = PromptBuildContext(
            noteTitle: "Computer Science Lecture",
            structuredKnowledge: knowledge,
            modelIdentifier: ModelManager.shared.activeModelIDDescription()
        )
        let input = PromptStructuredKnowledgeInput(noteTitle: "Computer Science Lecture", knowledge: knowledge)

        let summary = try await PromptRegistry.shared.execute(SummaryPrompt.self, input: input, context: context)
        let flashcards = try await PromptRegistry.shared.execute(FlashcardsPrompt.self, input: input, context: context)
        let quiz = try await PromptRegistry.shared.execute(QuizPrompt.self, input: input, context: context)
        let conceptMap = try await PromptRegistry.shared.execute(ConceptMapPrompt.self, input: input, context: context)
        let insights = try await PromptRegistry.shared.execute(LearningInsightsPrompt.self, input: input, context: context)

        print("CSummary=\(summary.output)")
        print("CFlashcardsCount=\(flashcards.output.cards.count)")
        print("CQuizCount=\(quiz.output.questions.count)")
        print("CConceptMapCount=\(conceptMap.output.count)")
        print("CInsightsKeys=\(insights.output.keyConcepts)")

        XCTAssertTrue(summary.validation.isValid)
        XCTAssertGreaterThanOrEqual(flashcards.output.cards.count, 2)
        XCTAssertGreaterThanOrEqual(quiz.output.questions.count, 2)
        XCTAssertGreaterThanOrEqual(conceptMap.output.count, 1)
        XCTAssertFalse(insights.output.keyConcepts.isEmpty)
    }

    private func biologyKnowledge() -> StructuredKnowledge {
        StructuredKnowledge(
            metadata: KnowledgeMetadata(title: "Biology Lecture"),
            title: "Biology Lecture",
            concepts: [
                KnowledgeConcept(
                    id: "cell-theory",
                    name: "Cell Theory",
                    definition: "Cells are the basic unit of life.",
                    category: "core",
                    importance: 0.95,
                    difficulty: 0.55,
                    relationships: ["cell-membrane", "cell-division"],
                    examples: ["Cells make up living organisms."],
                    confidence: 0.96
                ),
                KnowledgeConcept(
                    id: "cell-membrane",
                    name: "Cell membrane",
                    definition: "A protective boundary around the cell.",
                    category: "structure",
                    importance: 0.88,
                    difficulty: 0.45,
                    relationships: ["cell-theory"],
                    examples: ["The membrane protects the cell."],
                    confidence: 0.94
                ),
                KnowledgeConcept(
                    id: "cell-division",
                    name: "Cell division",
                    definition: "The process by which cells form new cells.",
                    category: "process",
                    importance: 0.9,
                    difficulty: 0.62,
                    relationships: ["cell-theory"],
                    examples: ["Cells divide to form new cells."],
                    confidence: 0.92
                )
            ],
            processes: [
                KnowledgeProcess(title: "Cell division", steps: ["Cell divides", "New cells are formed"], confidence: 0.93)
            ],
            relationships: [
                KnowledgeRelationship(sourceID: "cell-division", targetID: "cell-theory", relationKind: .relatedTo, relation: KnowledgeRelationshipKind.relatedTo.rawValue, confidence: 0.9),
                KnowledgeRelationship(sourceID: "cell-membrane", targetID: "cell-theory", relationKind: .partOf, relation: KnowledgeRelationshipKind.partOf.rawValue, confidence: 0.88)
            ],
            learningObjectives: [
                KnowledgeObjective(objective: "Explain why cells are considered the basic unit of life.", relatedConceptIDs: ["cell-theory"], confidence: 0.9)
            ],
            actionItems: [
                KnowledgeActionItem(title: "Review cell theory", details: "Connect the theory to membrane protection and cell division.", priority: "medium", confidence: 0.8)
            ],
            keywords: ["cell", "membrane", "division"],
            confidence: 0.94,
            difficulty: .intermediate,
            importance: 0.9,
            importantFacts: ["Cells are the basic unit of life.", "Cells divide to form new cells."],
            keyTerminology: ["cell theory", "cell membrane", "cell division"],
            summaryHighlights: ["Cells are the basic unit of life.", "The membrane protects the cell.", "Cells divide to form new cells."],
            examFocus: ["cell theory", "cell division"]
        )
    }

    private func computerScienceKnowledge() -> StructuredKnowledge {
        StructuredKnowledge(
            metadata: KnowledgeMetadata(title: "Computer Science Lecture"),
            title: "Computer Science Lecture",
            concepts: [
                KnowledgeConcept(
                    id: "algorithm",
                    name: "Algorithm",
                    definition: "A step-by-step procedure for solving a problem.",
                    category: "core",
                    importance: 0.95,
                    difficulty: 0.5,
                    relationships: ["loop", "recursion", "big-o"],
                    examples: ["Sorting data with a comparison-based procedure."],
                    confidence: 0.95
                ),
                KnowledgeConcept(
                    id: "loop",
                    name: "Loop",
                    definition: "A control structure that repeats instructions.",
                    category: "control",
                    importance: 0.9,
                    difficulty: 0.45,
                    relationships: ["algorithm"],
                    examples: ["Repeating a search until a match is found."],
                    confidence: 0.93
                ),
                KnowledgeConcept(
                    id: "big-o",
                    name: "Big-O notation",
                    definition: "A way to describe how runtime grows as input grows.",
                    category: "analysis",
                    importance: 0.93,
                    difficulty: 0.7,
                    relationships: ["algorithm"],
                    examples: ["O(n) runtime grows linearly with input size."],
                    confidence: 0.94
                )
            ],
            processes: [
                KnowledgeProcess(title: "Algorithm analysis", steps: ["Identify the algorithm", "Estimate growth", "Express complexity"], confidence: 0.9)
            ],
            relationships: [
                KnowledgeRelationship(sourceID: "loop", targetID: "algorithm", relationKind: .uses, relation: KnowledgeRelationshipKind.uses.rawValue, confidence: 0.9),
                KnowledgeRelationship(sourceID: "big-o", targetID: "algorithm", relationKind: .relatedTo, relation: KnowledgeRelationshipKind.relatedTo.rawValue, confidence: 0.9)
            ],
            learningObjectives: [
                KnowledgeObjective(objective: "Compare looping and recursive approaches.", relatedConceptIDs: ["loop", "algorithm"], confidence: 0.88)
            ],
            keywords: ["algorithm", "loop", "Big-O"],
            confidence: 0.93,
            difficulty: .intermediate,
            importance: 0.92,
            importantFacts: ["Big-O notation describes runtime growth.", "Loops are a control structure used in algorithms."],
            keyTerminology: ["algorithm", "loop", "Big-O notation"],
            summaryHighlights: ["Algorithms solve problems step by step.", "Loops repeat instructions.", "Big-O describes growth."],
            examFocus: ["algorithm analysis", "Big-O notation"]
        )
    }
}
