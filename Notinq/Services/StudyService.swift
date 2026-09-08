import Foundation

struct StudyGenerationRequest: Sendable {
    let noteID: UUID
    let title: String
    let content: String
    let notebookText: String
    let existingStudyData: NoteStudyData
}

final class StudyService {
    static let shared = StudyService()

    private init() {}

    func generateStudyData(for request: StudyGenerationRequest) async -> NoteStudyData {
        await AIService.shared.generateStudyData(
            noteTitle: request.title,
            noteText: request.content,
            notebookText: request.notebookText,
            existingStudyData: request.existingStudyData
        )
    }

    func recordReviewEvent(conceptID: String, noteID: UUID?, score: Double, kind: String) {
        let result: StudentKnowledgeReviewOutcome
        switch score {
        case 0.75...:
            result = .correct
        case 0.4..<0.75:
            result = .partial
        default:
            result = .incorrect
        }
        let source: StudentKnowledgeReviewSource
        switch kind.lowercased() {
        case "flashcard":
            source = .flashcard
        case "question", "quiz", "test":
            source = .question
        default:
            source = .manual
        }

        if let noteID {
            _ = try? MasteryTracker.shared.recordReview(
                conceptID: conceptID,
                noteID: noteID,
                outcome: result,
                source: source
            )
        } else {
            ReviewEventStore.shared.record(
                ReviewEvent(
                    conceptID: conceptID,
                    noteID: nil,
                    questionID: nil,
                    flashcardID: nil,
                    result: result.rawValue,
                    score: score,
                    eventType: kind,
                    metadata: [:]
                )
            )
        }
    }

    func studyPlanner() -> StudyPlanner {
        StudyPlanner.shared
    }
}
