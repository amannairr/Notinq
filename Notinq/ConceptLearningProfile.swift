import Foundation

struct ConceptLearningProfile: Equatable, Sendable {
    var conceptID: String
    var helpfulCount: Int
    var confusedCount: Int
    var acceptCount: Int
    var rejectCount: Int
    var lightlyEditedCount: Int
    var heavilyEditedCount: Int
    var requestedAgainCount: Int
    var lastInteractionDate: Date?

    var helpfulRatio: Double {
        ratio(numerator: helpfulCount, denominator: helpfulCount + confusedCount)
    }

    var confusionRatio: Double {
        ratio(numerator: confusedCount, denominator: helpfulCount + confusedCount)
    }

    init(
        conceptID: String,
        helpfulCount: Int = 0,
        confusedCount: Int = 0,
        acceptCount: Int = 0,
        rejectCount: Int = 0,
        lightlyEditedCount: Int = 0,
        heavilyEditedCount: Int = 0,
        requestedAgainCount: Int = 0,
        lastInteractionDate: Date? = nil
    ) {
        self.conceptID = conceptID
        self.helpfulCount = helpfulCount
        self.confusedCount = confusedCount
        self.acceptCount = acceptCount
        self.rejectCount = rejectCount
        self.lightlyEditedCount = lightlyEditedCount
        self.heavilyEditedCount = heavilyEditedCount
        self.requestedAgainCount = requestedAgainCount
        self.lastInteractionDate = lastInteractionDate
    }

    private func ratio(numerator: Int, denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }
}

struct ConceptLearningProfileBuilder {
    func profile(for conceptID: String, signals: [LearningSignal]) -> ConceptLearningProfile {
        profiles(for: [conceptID], signals: signals)[conceptID] ?? ConceptLearningProfile(conceptID: conceptID)
    }

    func profiles(for conceptIDs: [String], signals: [LearningSignal]) -> [String: ConceptLearningProfile] {
        let requestedIDs = Set(conceptIDs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        var profiles = Dictionary(
            requestedIDs.map { ($0, ConceptLearningProfile(conceptID: $0)) },
            uniquingKeysWith: { first, _ in first }
        )

        for signal in signals {
            for conceptID in signal.conceptIDs where requestedIDs.isEmpty || requestedIDs.contains(conceptID) {
                var profile = profiles[conceptID] ?? ConceptLearningProfile(conceptID: conceptID)
                apply(signal, to: &profile)
                profiles[conceptID] = profile
            }
        }

        return profiles
    }

    func profiles(signals: [LearningSignal]) -> [String: ConceptLearningProfile] {
        profiles(for: [], signals: signals)
    }

    private func apply(_ signal: LearningSignal, to profile: inout ConceptLearningProfile) {
        switch signal.signalType {
        case .accepted:
            profile.acceptCount += 1
        case .rejected:
            profile.rejectCount += 1
        case .heavilyEdited:
            profile.heavilyEditedCount += 1
        case .lightlyEdited:
            profile.lightlyEditedCount += 1
        case .requestedAgain:
            profile.requestedAgainCount += 1
        case .markedHelpful:
            profile.helpfulCount += 1
        case .markedStillConfused:
            profile.confusedCount += 1
        case .questionAttempted:
            break
        case .questionCorrect:
            profile.helpfulCount += 1
        case .questionPartiallyCorrect:
            profile.confusedCount += 1
        case .questionIncorrect:
            profile.confusedCount += 1
        }

        if profile.lastInteractionDate.map({ signal.timestamp > $0 }) ?? true {
            profile.lastInteractionDate = signal.timestamp
        }
    }
}
