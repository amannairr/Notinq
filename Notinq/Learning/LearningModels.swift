import Foundation

struct StudentConceptRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String { conceptID }
    var conceptID: String
    var masteryScore: Double
    var confidenceScore: Double
    var lastReviewed: Date?
    var mistakeCount: Int
    var reviewCount: Int
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var effectiveMasteryScore: Double {
        guard let lastReviewed else {
            return clamp(masteryScore)
        }

        let daysSinceReview = max(0, Date().timeIntervalSince(lastReviewed) / 86_400)
        let decayFactor = exp(-daysSinceReview / 30.0)
        return clamp(masteryScore * decayFactor)
    }

    private func clamp(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }
}

struct ReviewEvent: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var conceptID: String
    var noteID: UUID?
    var questionID: UUID?
    var flashcardID: UUID?
    var result: String = "unknown"
    var score: Double
    var eventType: String
    var timestamp: Date = Date()
    var metadata: [String: String] = [:]

    var occurredAt: Date {
        timestamp
    }
}

protocol StudentConceptRepositoryProtocol {
    func studentConcepts(for noteID: UUID) throws -> [StudentConceptRecord]
    func studentConcept(for noteID: UUID, conceptID: String) throws -> StudentConceptRecord?
    func weakStudentConcepts(limit: Int) throws -> [StudentConceptRecord]
    func strongStudentConcepts(limit: Int) throws -> [StudentConceptRecord]
    func recentStudentConcepts(limit: Int) throws -> [StudentConceptRecord]
    func conceptsNeedingReview(limit: Int) throws -> [StudentConceptRecord]
    func upsert(
        noteID: UUID,
        conceptID: String,
        masteryScore: Double,
        confidenceScore: Double,
        reviewCount: Int,
        mistakeCount: Int,
        lastReviewed: Date?
    ) throws
    func recordReviewEvent(_ event: ReviewEvent) throws
}

final class StudentConceptRepository: StudentConceptRepositoryProtocol {
    static let shared = StudentConceptRepository()

    private let studyRepository: StudyRepository

    init(studyRepository: StudyRepository = .shared) {
        self.studyRepository = studyRepository
    }

    func studentConcepts(for noteID: UUID) throws -> [StudentConceptRecord] {
        try studyRepository.studentConcepts(for: noteID)
    }

    func weakStudentConcepts(limit: Int) throws -> [StudentConceptRecord] {
        try studyRepository.weakestStudentConcepts(limit: limit)
    }

    func strongStudentConcepts(limit: Int) throws -> [StudentConceptRecord] {
        try studyRepository.strongestStudentConcepts(limit: limit)
    }

    func recentStudentConcepts(limit: Int) throws -> [StudentConceptRecord] {
        try studyRepository.recentlyReviewedStudentConcepts(limit: limit)
    }

    func conceptsNeedingReview(limit: Int) throws -> [StudentConceptRecord] {
        try studyRepository.studentConceptsNeedingReview(limit: limit)
    }

    func studentConcept(for noteID: UUID, conceptID: String) throws -> StudentConceptRecord? {
        try studyRepository.studentConcept(for: noteID, conceptID: conceptID)
    }

    func upsert(
        noteID: UUID,
        conceptID: String,
        masteryScore: Double,
        confidenceScore: Double,
        reviewCount: Int,
        mistakeCount: Int,
        lastReviewed: Date?
    ) throws {
        try studyRepository.upsertStudentConcept(
            noteID: noteID,
            conceptID: conceptID,
            masteryScore: masteryScore,
            confidenceScore: confidenceScore,
            reviewCount: reviewCount,
            mistakeCount: mistakeCount,
            lastReviewed: lastReviewed
        )
    }

    func recordReviewEvent(_ event: ReviewEvent) throws {
        try studyRepository.recordReviewEvent(event)
    }
}

final class StudentConceptService {
    static let shared = StudentConceptService()

    private let repository: StudentConceptRepositoryProtocol

    init(repository: StudentConceptRepositoryProtocol = StudentConceptRepository.shared) {
        self.repository = repository
    }

    func studentConcepts(for noteID: UUID) throws -> [StudentConceptRecord] {
        try repository.studentConcepts(for: noteID)
    }

    func weakestConcepts(limit: Int = 10) throws -> [StudentConceptRecord] {
        try repository.weakStudentConcepts(limit: limit)
    }

    func strongestConcepts(limit: Int = 10) throws -> [StudentConceptRecord] {
        try repository.strongStudentConcepts(limit: limit)
    }

    func recentlyReviewedConcepts(limit: Int = 10) throws -> [StudentConceptRecord] {
        try repository.recentStudentConcepts(limit: limit)
    }

    func conceptsNeedingReview(limit: Int = 10) throws -> [StudentConceptRecord] {
        try repository.conceptsNeedingReview(limit: limit)
    }

    func studentConcept(noteID: UUID, conceptID: String) throws -> StudentConceptRecord? {
        try repository.studentConcept(for: noteID, conceptID: conceptID)
    }

    @discardableResult
    func updateMastery(
        conceptID: String,
        noteID: UUID,
        outcome: StudentKnowledgeReviewOutcome,
        source: StudentKnowledgeReviewSource,
        questionID: UUID? = nil,
        flashcardID: UUID? = nil,
        reviewedAt: Date = Date()
    ) throws -> StudentConceptRecord {
        let current = try repository.studentConcept(for: noteID, conceptID: conceptID)
        let baseline = current ?? StudentConceptRecord(
            conceptID: conceptID,
            masteryScore: 0.0,
            confidenceScore: 0.5,
            lastReviewed: nil,
            mistakeCount: 0,
            reviewCount: 0
        )
        let scheduled = Self.applyReview(current: baseline, outcome: outcome, reviewedAt: reviewedAt)
        let reviewDelta = scheduled.reviewCount - baseline.reviewCount
        let mistakeDelta = scheduled.mistakeCount - baseline.mistakeCount

        try repository.upsert(
            noteID: noteID,
            conceptID: conceptID,
            masteryScore: scheduled.masteryScore,
            confidenceScore: scheduled.confidenceScore,
            reviewCount: reviewDelta,
            mistakeCount: mistakeDelta,
            lastReviewed: reviewedAt
        )

        try repository.recordReviewEvent(
            ReviewEvent(
                conceptID: conceptID,
                noteID: noteID,
                questionID: questionID,
                flashcardID: flashcardID,
                result: outcome.rawValue,
                score: outcome == .incorrect ? 0 : 1,
                eventType: source.rawValue,
                timestamp: reviewedAt,
                metadata: [:]
            )
        )

        return scheduled
    }

    private static func applyReview(
        current: StudentConceptRecord,
        outcome: StudentKnowledgeReviewOutcome,
        reviewedAt: Date
    ) -> StudentConceptRecord {
        var updated = current
        updated.reviewCount += 1
        updated.lastReviewed = reviewedAt
        updated.updatedAt = reviewedAt

        switch outcome {
        case .correct:
            updated.masteryScore = clamp(updated.masteryScore + 0.05)
            updated.confidenceScore = clamp(updated.confidenceScore + 0.04)
        case .incorrect:
            updated.masteryScore = clamp(updated.masteryScore - 0.05)
            updated.confidenceScore = clamp(updated.confidenceScore - 0.04)
            updated.mistakeCount += 1
        case .partial:
            updated.masteryScore = clamp(updated.masteryScore + 0.01)
            updated.confidenceScore = clamp(updated.confidenceScore + 0.01)
        case .easy:
            updated.masteryScore = clamp(updated.masteryScore + 0.05)
            updated.confidenceScore = clamp(updated.confidenceScore + 0.05)
        case .hard:
            updated.masteryScore = clamp(updated.masteryScore + 0.01)
            updated.confidenceScore = clamp(updated.confidenceScore - 0.02)
        }

        return updated
    }

    private static func clamp(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }
}

final class ReviewEventStore {
    static let shared = ReviewEventStore()

    private let repository: StudyRepository

    init(repository: StudyRepository = .shared) {
        self.repository = repository
    }

    func record(_ event: ReviewEvent) {
        try? repository.recordReviewEvent(event)
    }

    func history(for conceptID: String) throws -> [ReviewEvent] {
        try repository.reviewEvents(forConceptID: conceptID)
    }
}

protocol ReviewEventRepositoryProtocol {
    func reviewEvents(forConceptID conceptID: String) throws -> [ReviewEvent]
    func reviewEvents(for noteID: UUID) throws -> [ReviewEvent]
    func recordReviewEvent(_ event: ReviewEvent) throws
}

final class MasteryTracker {
    static let shared = MasteryTracker()

    private let service: StudentConceptService

    init(service: StudentConceptService = .shared) {
        self.service = service
    }

    @discardableResult
    func recordCorrectAnswer(
        conceptID: String,
        noteID: UUID,
        questionID: UUID? = nil,
        flashcardID: UUID? = nil,
        source: StudentKnowledgeReviewSource = .question
    ) throws -> StudentConceptRecord {
        try service.updateMastery(
            conceptID: conceptID,
            noteID: noteID,
            outcome: .correct,
            source: source,
            questionID: questionID,
            flashcardID: flashcardID
        )
    }

    @discardableResult
    func recordIncorrectAnswer(
        conceptID: String,
        noteID: UUID,
        questionID: UUID? = nil,
        flashcardID: UUID? = nil,
        source: StudentKnowledgeReviewSource = .question
    ) throws -> StudentConceptRecord {
        try service.updateMastery(
            conceptID: conceptID,
            noteID: noteID,
            outcome: .incorrect,
            source: source,
            questionID: questionID,
            flashcardID: flashcardID
        )
    }

    @discardableResult
    func recordFlashcardReview(
        conceptID: String,
        noteID: UUID,
        flashcardID: UUID? = nil,
        outcome: StudentKnowledgeReviewOutcome,
        reviewedAt: Date = Date()
    ) throws -> StudentConceptRecord {
        try service.updateMastery(
            conceptID: conceptID,
            noteID: noteID,
            outcome: outcome,
            source: .flashcard,
            questionID: nil,
            flashcardID: flashcardID,
            reviewedAt: reviewedAt
        )
    }

    @discardableResult
    func recordQuestionReview(
        conceptID: String,
        noteID: UUID,
        questionID: UUID? = nil,
        outcome: StudentKnowledgeReviewOutcome,
        reviewedAt: Date = Date()
    ) throws -> StudentConceptRecord {
        try service.updateMastery(
            conceptID: conceptID,
            noteID: noteID,
            outcome: outcome,
            source: .question,
            questionID: questionID,
            flashcardID: nil,
            reviewedAt: reviewedAt
        )
    }

    @discardableResult
    func recordReview(
        conceptID: String,
        noteID: UUID,
        outcome: StudentKnowledgeReviewOutcome,
        source: StudentKnowledgeReviewSource,
        questionID: UUID? = nil,
        flashcardID: UUID? = nil,
        reviewedAt: Date = Date()
        ) throws -> StudentConceptRecord {
        try service.updateMastery(
            conceptID: conceptID,
            noteID: noteID,
            outcome: outcome,
            source: source,
            questionID: questionID,
            flashcardID: flashcardID,
            reviewedAt: reviewedAt
        )
    }

    @discardableResult
    func recordPartialAnswer(
        conceptID: String,
        noteID: UUID,
        questionID: UUID? = nil,
        flashcardID: UUID? = nil,
        source: StudentKnowledgeReviewSource = .question
    ) throws -> StudentConceptRecord {
        try service.updateMastery(
            conceptID: conceptID,
            noteID: noteID,
            outcome: .partial,
            source: source,
            questionID: questionID,
            flashcardID: flashcardID
        )
    }
}

final class StudyPlanner {
    static let shared = StudyPlanner()

    private init() {}

    func plan(concepts: [CanonicalConceptRecord], mastery: [StudentConceptRecord]) -> [String] {
        let mastered = Set(mastery.map(\.conceptID))
        return concepts.map(\.canonicalName).filter { !mastered.contains($0) }
    }
}
