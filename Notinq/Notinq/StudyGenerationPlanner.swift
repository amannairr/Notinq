import Foundation

enum StudyGenerationPlanner {
    static func budget(for tier: AICapabilityTier) -> StudyGenerationBudget {
        switch tier {
        case .basic:
            return StudyGenerationBudget(
                flashcards: 4,
                quizQuestions: 4,
                tutorQuestions: 3,
                insightItemsPerSection: 3,
                maxResponseTokens: 420,
                contextLimit: 1024
            )
        case .standard:
            return StudyGenerationBudget(
                flashcards: 6,
                quizQuestions: 6,
                tutorQuestions: 4,
                insightItemsPerSection: 4,
                maxResponseTokens: 560,
                contextLimit: 1536
            )
        case .advanced:
            return StudyGenerationBudget(
                flashcards: 8,
                quizQuestions: 8,
                tutorQuestions: 5,
                insightItemsPerSection: 5,
                maxResponseTokens: 720,
                contextLimit: 2048
            )
        }
    }
}
