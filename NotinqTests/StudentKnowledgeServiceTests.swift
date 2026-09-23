import XCTest
@testable import Notinq

@MainActor
final class StudentKnowledgeServiceTests: XCTestCase {
    func testMasteryRetentionConfidenceAndReadinessCalculations() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.atpID,
            masteryScore: 0.8,
            confidenceScore: 0.9,
            reviewCount: 3,
            mistakeCount: 0,
            lastReviewed: Date()
        )
        try fixture.studyRepository.upsertStudentConcept(
            noteID: graph.noteID,
            conceptID: graph.respirationID,
            masteryScore: 0.4,
            confidenceScore: 0.5,
            reviewCount: 2,
            mistakeCount: 1,
            lastReviewed: Date()
        )
        let service = makeService(fixture: fixture)

        XCTAssertEqual(service.overallMastery(), 0.6, accuracy: 0.05)
        XCTAssertGreaterThan(service.retentionScore(), 0.45)
        XCTAssertEqual(service.confidenceScore(), 0.7, accuracy: 0.05)
        XCTAssertGreaterThan(service.examReadiness(), 0.45)
        XCTAssertLessThanOrEqual(service.examReadiness(), 1.0)
    }

    func testWeakAndStrongConceptGeneration() throws {
        let fixture = try AdaptiveGraphTestFixture()
        let graph = try fixture.seedATPGraph()
        try fixture.studyRepository.upsertStudentConcept(noteID: graph.noteID, conceptID: graph.atpID, masteryScore: 0.9, confidenceScore: 0.9, reviewCount: 2, mistakeCount: 0, lastReviewed: Date())
        try fixture.studyRepository.upsertStudentConcept(noteID: graph.noteID, conceptID: graph.respirationID, masteryScore: 0.2, confidenceScore: 0.3, reviewCount: 2, mistakeCount: 2, lastReviewed: Date())
        let service = makeService(fixture: fixture)

        XCTAssertTrue(service.strongConcepts().contains("ATP"))
        XCTAssertTrue(service.weakConcepts().contains("Cellular Respiration"))
    }

    func testGraphStatisticsLoadFromCanonicalGraph() throws {
        let fixture = try AdaptiveGraphTestFixture()
        _ = try fixture.seedATPGraph()
        let service = makeService(fixture: fixture)

        let stats = service.graphStatistics()

        XCTAssertEqual(stats.conceptCount, 5)
        XCTAssertEqual(stats.relationshipCount, 4)
        XCTAssertEqual(stats.connectedComponents, 1)
        XCTAssertGreaterThan(stats.averageDegree, 0)
    }

    private func makeService(fixture: AdaptiveGraphTestFixture) -> StudentKnowledgeService {
        StudentKnowledgeService(
            knowledgeRepository: fixture.knowledgeRepository,
            studentConceptService: StudentConceptService(repository: StudentConceptRepository(studyRepository: fixture.studyRepository)),
            studyRepository: fixture.studyRepository
        )
    }
}
