import Foundation

extension Notification.Name {
    static let knowledgeGraphDidChange = Notification.Name("NotinqKnowledgeGraphDidChange")
}

enum StudentKnowledgeLearningStatus: String, Codable, CaseIterable, Sendable {
    case firstLearning
    case review
    case relearning
    case forgotten
}

enum StudentKnowledgeReviewOutcome: String, Codable, CaseIterable, Sendable {
    case correct
    case incorrect
    case partial
    case easy
    case hard
}

enum StudentKnowledgeReviewSource: String, Codable, CaseIterable, Sendable {
    case flashcard
    case question
    case quiz
    case testMe
    case manual
}

struct StudentKnowledgeReviewEvent: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var reviewedAt: Date = Date()
    var outcome: StudentKnowledgeReviewOutcome
    var source: StudentKnowledgeReviewSource
    var noteID: UUID?
    var graphConceptID: UUID?
    var score: Double?
    var wasCorrect: Bool
}

struct StudentKnowledgeConceptRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var graphConceptIDs: [UUID] = []
    var name: String
    var description: String
    var aliases: [String] = []
    var sourceNoteIDs: [UUID] = []
    var relationshipCount: Int = 0
    var familiarity: Double = 0.2
    var confidence: Double = 0.5
    var masteryLevel: Double = 0
    var lastReviewedAt: Date?
    var reviewCount: Int = 0
    var correctAnswerCount: Int = 0
    var incorrectAnswerCount: Int = 0
    var streak: Int = 0
    var easeFactor: Double = 2.5
    var nextReviewDate: Date?
    var learningStatus: StudentKnowledgeLearningStatus = .firstLearning
    var reviewHistory: [StudentKnowledgeReviewEvent] = []
    var archivedAt: Date?
    var isArchived: Bool = false
    var lastSyncedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var normalizedName: String {
        Self.normalizedKey(for: name)
    }

    static func normalizedKey(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct StudentKnowledgeGraphConceptSnapshot: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var noteID: UUID
    var name: String
    var description: String
    var aliases: [String]
    var relationshipCount: Int
    var confidence: Double
    var importance: Double
    var difficulty: Double
}

struct StudentKnowledgeDistributionBucket: Identifiable, Codable, Equatable, Sendable {
    var id: String { title }
    var title: String
    var lowerBound: Double
    var upperBound: Double
    var count: Int
}

struct StudentKnowledgeCalendarDay: Identifiable, Codable, Equatable, Sendable {
    var date: Date
    var dueCount: Int

    var id: String {
        StudentKnowledgeCalendarDay.dayKey(for: date)
    }

    static func dayKey(for date: Date) -> String {
        let calendar = Calendar.current
        let normalized = calendar.startOfDay(for: date)
        return ISO8601DateFormatter().string(from: normalized)
    }
}

struct StudentKnowledgeDashboardSummary: Codable, Equatable, Sendable {
    var totalConcepts: Int = 0
    var masteredConcepts: Int = 0
    var learningConcepts: Int = 0
    var reviewConcepts: Int = 0
    var forgottenConcepts: Int = 0
    var archivedConcepts: Int = 0
    var overallProgress: Double = 0
    var weakestConcepts: [StudentKnowledgeConceptRecord] = []
    var strongestConcepts: [StudentKnowledgeConceptRecord] = []
    var masteryDistribution: [StudentKnowledgeDistributionBucket] = []
    var reviewCalendar: [StudentKnowledgeCalendarDay] = []
    var lastUpdatedAt: Date?

    static let empty = StudentKnowledgeDashboardSummary()
}

struct StudentKnowledgeStoreMetadata: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var createdAt: Date = Date()
    var lastUpdatedAt: Date = Date()
    var lastSyncedAt: Date?
}

struct StudentKnowledgeStoreSnapshot: Codable, Equatable, Sendable {
    var version: Int = 1
    var metadata: StudentKnowledgeStoreMetadata = StudentKnowledgeStoreMetadata()
    var concepts: [StudentKnowledgeConceptRecord] = []
}

struct LegacyStudentKnowledgeStoreSnapshot: Codable {
    var concepts: [StudentKnowledgeConceptRecord]
}
