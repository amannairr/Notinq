import Foundation

enum MasteryState: String, Codable, Sendable {
    case mastered
    case familiar
    case needsPractice
    case struggling

    var displayTitle: String {
        switch self {
        case .mastered:
            return "Mastered"
        case .familiar:
            return "Familiar"
        case .needsPractice:
            return "Needs Practice"
        case .struggling:
            return "Struggling"
        }
    }

    static func state(for score: Double) -> MasteryState {
        switch max(0, min(1, score)) {
        case 0.8...1:
            return .mastered
        case 0.6..<0.8:
            return .familiar
        case 0.4..<0.6:
            return .needsPractice
        default:
            return .struggling
        }
    }
}

struct ConceptMastery: Equatable, Sendable {
    let conceptID: String
    let masteryScore: Double
    let masteryState: MasteryState
    let lastUpdated: Date

    init(
        conceptID: String,
        masteryScore: Double,
        lastUpdated: Date = Date()
    ) {
        let clampedScore = max(0, min(1, masteryScore))
        self.conceptID = conceptID
        self.masteryScore = clampedScore
        self.masteryState = MasteryState.state(for: clampedScore)
        self.lastUpdated = lastUpdated
    }
}

struct ConceptMasteryBuilder {
    func mastery(for profile: ConceptLearningProfile) -> ConceptMastery {
        let score =
            0.5
            + Double(profile.helpfulCount) * 0.12
            + Double(profile.acceptCount) * 0.08
            + Double(profile.lightlyEditedCount) * 0.05
            - Double(profile.confusedCount) * 0.14
            - Double(profile.rejectCount) * 0.08
            - Double(profile.heavilyEditedCount) * 0.10
            - Double(profile.requestedAgainCount) * 0.07

        return ConceptMastery(
            conceptID: profile.conceptID,
            masteryScore: score,
            lastUpdated: profile.lastInteractionDate ?? Date(timeIntervalSince1970: 0)
        )
    }

    func masteries(for profiles: [ConceptLearningProfile]) -> [String: ConceptMastery] {
        Dictionary(
            profiles.map { ($0.conceptID, mastery(for: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
