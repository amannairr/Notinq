import Foundation
import XCTest
@testable import Notinq

@MainActor
final class GraphAwareLearningTests: XCTestCase {
    func testGraphRelationshipsCreateFlashcards() {
        let snapshot = makeSnapshot()

        let flashcards = LearningEngine.shared.generateFlashcards(from: snapshot)
        let graphCard = flashcards.first { $0.front == "What concept produces ATP?" }

        XCTAssertEqual(graphCard?.back, "Mitochondria")
        XCTAssertEqual(graphCard?.conceptIDs, ["ATP", "Mitochondria"])
    }

    func testGraphRelationshipsCreateQuizQuestions() {
        let snapshot = makeSnapshot()

        let quiz = LearningEngine.shared.generateQuizSet(from: snapshot)

        XCTAssertEqual(quiz.questions.first?.prompt, "What concept produces ATP?")
        XCTAssertEqual(quiz.questions.first?.correctAnswer, "Mitochondria")
        XCTAssertTrue(quiz.questions.first?.explanation.contains("ATP PRODUCES Mitochondria") ?? false)
    }

    func testPrerequisiteOrderAppearsInRevisionGuide() {
        let snapshot = makeSnapshot()

        let examPrep = LearningEngine.shared.generateExamPrep(from: snapshot)

        XCTAssertTrue(examPrep.condensedRevisionGuide.contains("Recommended learning order: Organelle -> Mitochondria -> ATP"))
    }

    private func makeSnapshot() -> StudyKnowledgeSnapshot {
        StudyKnowledgeSnapshot(
            title: "Cell Energy",
            sourceSignature: "cell-energy",
            cleanedText: "ATP is produced by mitochondria. Mitochondria require organelles.",
            normalizedText: "atp is produced by mitochondria",
            topics: ["Cell Energy"],
            concepts: [
                StudyKnowledgeItem(
                    title: "ATP",
                    summary: "Energy currency of the cell.",
                    importance: 0.8,
                    aliases: ["Adenosine Triphosphate"],
                    relatedTitles: ["Mitochondria"],
                    category: "concept"
                ),
                StudyKnowledgeItem(
                    title: "Mitochondria",
                    summary: "Organelle involved in energy production.",
                    importance: 0.9,
                    relatedTitles: ["ATP", "Organelle"],
                    category: "concept"
                ),
                StudyKnowledgeItem(
                    title: "Organelle",
                    summary: "Specialized structure in a cell.",
                    importance: 0.7,
                    relatedTitles: ["Mitochondria"],
                    category: "concept"
                )
            ],
            definitions: [],
            relationships: [
                StudyKnowledgeRelationship(
                    sourceTitle: "ATP",
                    targetTitle: "Mitochondria",
                    relation: KnowledgeRelationshipKind.produces.rawValue,
                    confidence: 0.95
                ),
                StudyKnowledgeRelationship(
                    sourceTitle: "ATP",
                    targetTitle: "Mitochondria",
                    relation: KnowledgeRelationshipKind.requires.rawValue,
                    confidence: 0.9
                )
            ],
            examples: [],
            procedures: [],
            formulas: [],
            importantFacts: [],
            keyTerms: [],
            misconceptions: [],
            prerequisites: [
                StudyKnowledgeItem(title: "Organelle", summary: "Review organelles first.", importance: 0.9, category: "prerequisite"),
                StudyKnowledgeItem(title: "Mitochondria", summary: "Review mitochondria before ATP.", importance: 0.85, category: "prerequisite")
            ],
            hierarchy: [],
            difficulty: .intermediate,
            supportingExamples: [],
            supportingEvidence: [],
            summaryHighlights: [],
            examFocus: ["ATP"],
            tokenEstimate: 32,
            extractionStrategy: "test"
        )
    }
}
