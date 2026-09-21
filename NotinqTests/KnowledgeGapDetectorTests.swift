import XCTest
@testable import Notinq

final class KnowledgeGapDetectorTests: XCTestCase {
    func testLowMasteryConceptCreatesGap() {
        let limits = concept(id: UUID().uuidString, name: "Limits")
        let detector = KnowledgeGapDetector()

        let gaps = detector.detectGaps(
            concepts: [limits],
            relationships: [],
            mastery: [
                StudentConceptRecord(
                    conceptID: limits.id.uuidString,
                    masteryScore: 0.2,
                    confidenceScore: 0.4,
                    lastReviewed: Date(),
                    mistakeCount: 0,
                    reviewCount: 1
                )
            ]
        )

        XCTAssertEqual(gaps.first?.concept.name, "Limits")
        XCTAssertEqual(gaps.first?.reason, "Low mastery")
    }

    func testStrongDependentWeakPrerequisiteReturnsPrerequisiteGap() {
        let limits = concept(id: UUID().uuidString, name: "Limits")
        let derivatives = concept(id: UUID().uuidString, name: "Derivatives")
        let detector = KnowledgeGapDetector()
        let relationship = ConceptRelationship(
            id: UUID(),
            sourceConceptID: derivatives.id,
            destinationConceptID: limits.id,
            type: .prerequisite,
            confidence: 0.9
        )

        let gaps = detector.detectGaps(
            concepts: [limits, derivatives],
            relationships: [relationship],
            mastery: [
                StudentConceptRecord(conceptID: limits.id.uuidString, masteryScore: 0.2, confidenceScore: 0.4, lastReviewed: Date(), mistakeCount: 0, reviewCount: 2),
                StudentConceptRecord(conceptID: derivatives.id.uuidString, masteryScore: 0.9, confidenceScore: 0.8, lastReviewed: Date(), mistakeCount: 0, reviewCount: 2)
            ]
        )

        XCTAssertTrue(gaps.contains { $0.concept.name == "Limits" })
        XCTAssertTrue(gaps.contains { $0.reason == "Weak prerequisite for mastered dependent concept" })
    }

    private func concept(id: String, name: String) -> Concept {
        Concept(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            description: "\(name) description",
            aliases: [],
            noteID: UUID(),
            confidence: 0.9,
            importanceScore: 0.9,
            difficultyScore: 0.2
        )
    }
}
