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

enum StudyKnowledgeDifficulty: String, Codable, CaseIterable, Sendable {
    case intro
    case intermediate
    case advanced
}

struct StudyKnowledgeItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var summary: String
    var evidence: [String] = []
    var importance: Double = 0
    var difficulty: Double = 0.5
    var aliases: [String] = []
    var relatedTitles: [String] = []
    var category: String = ""
}

struct StudyKnowledgeRelationship: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var sourceTitle: String
    var targetTitle: String
    var relation: String
    var confidence: Double = 0.5
}

struct StudyKnowledgeNode: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var summary: String = ""
    var children: [StudyKnowledgeNode] = []
}

struct StudyKnowledgeSnapshot: Codable, Equatable, Sendable {
    var title: String = ""
    var sourceSignature: String = ""
    var cleanedText: String = ""
    var normalizedText: String = ""
    var topics: [String] = []
    var concepts: [StudyKnowledgeItem] = []
    var definitions: [StudyKnowledgeItem] = []
    var relationships: [StudyKnowledgeRelationship] = []
    var examples: [StudyKnowledgeItem] = []
    var procedures: [StudyKnowledgeItem] = []
    var formulas: [StudyKnowledgeItem] = []
    var importantFacts: [StudyKnowledgeItem] = []
    var keyTerms: [StudyKnowledgeItem] = []
    var misconceptions: [StudyKnowledgeItem] = []
    var prerequisites: [StudyKnowledgeItem] = []
    var hierarchy: [StudyKnowledgeNode] = []
    var difficulty: StudyKnowledgeDifficulty = .intermediate
    var supportingExamples: [StudyKnowledgeItem] = []
    var supportingEvidence: [String] = []
    var summaryHighlights: [String] = []
    var examFocus: [String] = []
    var tokenEstimate: Int = 0
    var extractionStrategy: String = ""

    var hasContent: Bool {
        !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !concepts.isEmpty
            || !definitions.isEmpty
            || !relationships.isEmpty
            || !examples.isEmpty
            || !procedures.isEmpty
            || !formulas.isEmpty
            || !importantFacts.isEmpty
            || !keyTerms.isEmpty
            || !misconceptions.isEmpty
            || !prerequisites.isEmpty
    }
}

struct StudyGenerationArtifacts: Codable, Equatable, Sendable {
    var flashcards: [StudyFlashcard] = []
    var quizQuestions: [StudyQuizQuestion] = []
    var tutorQuestions: [StudyTutorQuestion] = []
    var insights: StudyInsights = StudyInsights()
    var analysis: StudyContentAnalysis = StudyContentAnalysis()
    var source: StudyGenerationSource = .basic
    var artifacts: [StudyArtifact] = []
    var knowledgeSnapshot: StudyKnowledgeSnapshot = StudyKnowledgeSnapshot()
    var knowledgeSignature: String = ""

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
