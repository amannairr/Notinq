import Foundation

enum StudyGenerationSource: String, Codable, Sendable {
    case basic
    case standard
    case advanced
}

enum StudyArtifactKind: String, Codable, CaseIterable, Sendable {
    case learningInsights
    case flashcards
    case quizGenerator
    case summaryGenerator
    case keyConcepts
    case learningMemory
    case notebookKnowledgeGaps
    case examPrep
    case conceptMap
    case activeRecall

    var title: String {
        switch self {
        case .learningInsights:
            return "Learning Insights"
        case .flashcards:
            return "Flashcards"
        case .quizGenerator:
            return "Quiz Generator"
        case .summaryGenerator:
            return "Summary Generator"
        case .keyConcepts:
            return "Key Concepts"
        case .learningMemory:
            return "Learning Memory"
        case .notebookKnowledgeGaps:
            return "Knowledge Gaps"
        case .examPrep:
            return "Exam Prep"
        case .conceptMap:
            return "Concept Map"
        case .activeRecall:
            return "Active Recall"
        }
    }
}

struct StudyArtifactSection: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var body: String
}

struct StudyArtifact: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var kind: StudyArtifactKind
    var title: String
    var content: String
    var sections: [StudyArtifactSection] = []
    var sourceNoteID: UUID?
    var sourceNoteTitle: String = ""
    var generatedAt: Date = Date()
}

struct StudyGenerationContext: Sendable {
    let noteTitle: String
    let noteText: String

    var contentLength: Int { noteText.count }
}

struct StudyContentAnalysis: Codable, Equatable, Sendable {
    var mainTopic: String = ""
    var subjectArea: String = ""
    var difficulty: String = ""
    var contentDensity: String = ""
    var language: String = ""
    var keyTerms: [String] = []
    var frequentConcepts: [String] = []
    var sentenceCount: Int = 0
    var wordCount: Int = 0
}

struct StudyGenerationArtifacts: Codable, Equatable, Sendable {
    var flashcards: [StudyFlashcard] = []
    var quizQuestions: [StudyQuizQuestion] = []
    var tutorQuestions: [StudyTutorQuestion] = []
    var insights: StudyInsights = StudyInsights()
    var analysis: StudyContentAnalysis = StudyContentAnalysis()
    var source: StudyGenerationSource = .basic
    var artifacts: [StudyArtifact] = []

    var hasAnyContent: Bool {
        !flashcards.isEmpty
            || !quizQuestions.isEmpty
            || !tutorQuestions.isEmpty
            || !insights.keyConcepts.isEmpty
            || !insights.importantConcepts.isEmpty
            || !insights.potentialExamTopics.isEmpty
            || !insights.knowledgeGaps.isEmpty
            || !artifacts.isEmpty
    }
}
