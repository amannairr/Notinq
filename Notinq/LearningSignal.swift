import Foundation

enum LearningSignalType: String, Codable, Sendable {
    case accepted
    case rejected
    case heavilyEdited
    case lightlyEdited
    case requestedAgain
    case markedHelpful
    case markedStillConfused
    case questionAttempted
    case questionCorrect
    case questionPartiallyCorrect
    case questionIncorrect
}

struct LearningSignal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let proposalID: UUID
    let conceptIDs: [String]
    let timestamp: Date
    let signalType: LearningSignalType
    let confidenceDelta: Double
    let sourceAction: AIEditorAction

    init(
        id: UUID = UUID(),
        proposalID: UUID,
        conceptIDs: [String],
        timestamp: Date = Date(),
        signalType: LearningSignalType,
        confidenceDelta: Double,
        sourceAction: AIEditorAction
    ) {
        self.id = id
        self.proposalID = proposalID
        self.conceptIDs = conceptIDs
        self.timestamp = timestamp
        self.signalType = signalType
        self.confidenceDelta = max(-1, min(1, confidenceDelta))
        self.sourceAction = sourceAction
    }
}

struct LearningSignalRecorder {
    var store: LearningSignalStore

    init(store: LearningSignalStore = .shared) {
        self.store = store
    }

    @discardableResult
    func recordAccepted(proposal: AIProposal, finalText: String) -> LearningSignal {
        let type = editSignalType(original: proposal.generatedText, final: finalText)
        let signal = makeSignal(
            proposal: proposal,
            type: type ?? .accepted,
            confidenceDelta: type == nil ? 0.05 : (type == .lightlyEdited ? 0.02 : -0.02)
        )
        store.append(signal)
        return signal
    }

    @discardableResult
    func recordRejected(proposal: AIProposal) -> LearningSignal {
        let signal = makeSignal(proposal: proposal, type: .rejected, confidenceDelta: -0.05)
        store.append(signal)
        return signal
    }

    @discardableResult
    func recordHelpful(proposal: AIProposal) -> LearningSignal {
        let signal = makeSignal(proposal: proposal, type: .markedHelpful, confidenceDelta: 0.1)
        store.append(signal)
        return signal
    }

    @discardableResult
    func recordStillConfused(proposal: AIProposal) -> LearningSignal {
        let signal = makeSignal(proposal: proposal, type: .markedStillConfused, confidenceDelta: -0.1)
        store.append(signal)
        return signal
    }

    @discardableResult
    func recordRequestedAgain(proposal: AIProposal) -> LearningSignal {
        let signal = makeSignal(proposal: proposal, type: .requestedAgain, confidenceDelta: -0.04)
        store.append(signal)
        return signal
    }

    @discardableResult
    func recordTeachMeAttempt(question: TeachMeQuestion) -> LearningSignal {
        let signal = makeSignal(
            proposalID: question.id,
            conceptIDs: [question.conceptID],
            type: .questionAttempted,
            confidenceDelta: 0
        )
        store.append(signal)
        return signal
    }

    @discardableResult
    func recordTeachMeEvaluation(question: TeachMeQuestion, evaluation: TeachMeEvaluation) -> LearningSignal {
        let signal = makeSignal(
            proposalID: question.id,
            conceptIDs: [question.conceptID],
            type: evaluation.signalType,
            confidenceDelta: evaluation.confidenceDelta
        )
        store.append(signal)
        return signal
    }

    func editSignalType(original: String, final: String) -> LearningSignalType? {
        let originalTrimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTrimmed = final.trimmingCharacters(in: .whitespacesAndNewlines)
        guard originalTrimmed != finalTrimmed else { return nil }

        let distance = Self.levenshteinDistance(originalTrimmed, finalTrimmed)
        let baseline = max(max(originalTrimmed.count, finalTrimmed.count), 1)
        let ratio = Double(distance) / Double(baseline)
        return ratio <= 0.25 ? .lightlyEdited : .heavilyEdited
    }

    private func makeSignal(
        proposal: AIProposal,
        type: LearningSignalType,
        confidenceDelta: Double
    ) -> LearningSignal {
        LearningSignal(
            proposalID: proposal.id,
            conceptIDs: proposal.adaptiveExplanationContext?.conceptIDs ?? [],
            signalType: type,
            confidenceDelta: confidenceDelta,
            sourceAction: proposal.action
        )
    }

    private func makeSignal(
        proposalID: UUID,
        conceptIDs: [String],
        type: LearningSignalType,
        confidenceDelta: Double
    ) -> LearningSignal {
        LearningSignal(
            proposalID: proposalID,
            conceptIDs: conceptIDs,
            signalType: type,
            confidenceDelta: confidenceDelta,
            sourceAction: .dontUnderstand
        )
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(min(previous[j] + 1, current[j - 1] + 1), substitution)
            }
            swap(&previous, &current)
        }

        return previous[b.count]
    }
}
