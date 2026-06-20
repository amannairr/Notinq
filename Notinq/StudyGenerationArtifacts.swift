import Foundation

enum StudyGenerationSource: String, Codable, Sendable {
    case basic
    case standard
    case advanced
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

    var hasAnyContent: Bool {
        !flashcards.isEmpty
            || !quizQuestions.isEmpty
            || !tutorQuestions.isEmpty
            || !insights.keyConcepts.isEmpty
            || !insights.importantConcepts.isEmpty
            || !insights.potentialExamTopics.isEmpty
            || !insights.knowledgeGaps.isEmpty
    }
}
