import Foundation

enum TeachMeSessionState: String, Codable, Equatable, Sendable {
    case idle
    case question
    case answering
    case feedback
    case complete
}

enum TeachMeEvaluation: String, Codable, Equatable, Sendable {
    case correct
    case partiallyCorrect
    case incorrect

    var signalType: LearningSignalType {
        switch self {
        case .correct:
            return .questionCorrect
        case .partiallyCorrect:
            return .questionPartiallyCorrect
        case .incorrect:
            return .questionIncorrect
        }
    }

    var confidenceDelta: Double {
        switch self {
        case .correct:
            return 0.08
        case .partiallyCorrect:
            return 0.01
        case .incorrect:
            return -0.08
        }
    }
}

struct TeachMeQuestion: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var conceptID: String
    var conceptName: String
    var question: String
    var sourceReferences: [AdaptiveExplanationSource]
    var originatingKnowledgeGap: String?
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        conceptID: String,
        conceptName: String,
        question: String,
        sourceReferences: [AdaptiveExplanationSource] = [],
        originatingKnowledgeGap: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.conceptID = conceptID
        self.conceptName = conceptName
        self.question = question
        self.sourceReferences = sourceReferences
        self.originatingKnowledgeGap = originatingKnowledgeGap
        self.generatedAt = generatedAt
    }
}

struct TeachMeResponse: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var questionID: UUID
    var answer: String
    var submittedAt: Date
    var evaluation: TeachMeEvaluation
    var confidence: Double
    var feedback: String

    init(
        id: UUID = UUID(),
        questionID: UUID,
        answer: String,
        submittedAt: Date = Date(),
        evaluation: TeachMeEvaluation,
        confidence: Double,
        feedback: String
    ) {
        self.id = id
        self.questionID = questionID
        self.answer = answer
        self.submittedAt = submittedAt
        self.evaluation = evaluation
        self.confidence = max(0, min(1, confidence))
        self.feedback = feedback
    }
}

struct TeachMeSession: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var state: TeachMeSessionState
    var activeConceptID: String?
    var activeConceptName: String?
    var activeQuestion: TeachMeQuestion?
    var answerHistory: [TeachMeResponse]
    var followUpCount: Int
    var startedAt: Date?
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        state: TeachMeSessionState = .idle,
        activeConceptID: String? = nil,
        activeConceptName: String? = nil,
        activeQuestion: TeachMeQuestion? = nil,
        answerHistory: [TeachMeResponse] = [],
        followUpCount: Int = 0,
        startedAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.state = state
        self.activeConceptID = activeConceptID
        self.activeConceptName = activeConceptName
        self.activeQuestion = activeQuestion
        self.answerHistory = answerHistory
        self.followUpCount = followUpCount
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

struct TeachMeConceptCandidate: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case knowledgeGap
        case historicallyConfusing
        case weakMastery
        case manual
    }

    var conceptID: String
    var conceptName: String
    var source: Source
    var originatingKnowledgeGap: String?
    var sourceReferences: [AdaptiveExplanationSource]
}

struct TeachMeEngine {
    func startSession(
        adaptiveContext: AdaptiveExplanationContext,
        manualConcept: String? = nil,
        now: Date = Date()
    ) -> TeachMeSession {
        guard let candidate = selectConcept(adaptiveContext: adaptiveContext, manualConcept: manualConcept) else {
            return TeachMeSession(state: .idle)
        }

        let question = makeQuestion(for: candidate, followUp: false, now: now)
        return TeachMeSession(
            state: .question,
            activeConceptID: candidate.conceptID,
            activeConceptName: candidate.conceptName,
            activeQuestion: question,
            startedAt: now,
            updatedAt: now
        )
    }

    func beginAnswering(_ session: TeachMeSession, now: Date = Date()) -> TeachMeSession {
        guard session.state == .question else { return session }
        var updated = session
        updated.state = .answering
        updated.updatedAt = now
        return updated
    }

    func submitAnswer(_ answer: String, for session: TeachMeSession, now: Date = Date()) -> TeachMeSession {
        guard let question = session.activeQuestion else { return session }
        let evaluation = evaluate(answer: answer, for: question)
        let feedback = feedback(for: evaluation, answer: answer, question: question)
        var updated = session
        updated.state = .feedback
        updated.answerHistory.append(
            TeachMeResponse(
                questionID: question.id,
                answer: answer,
                submittedAt: now,
                evaluation: evaluation,
                confidence: confidence(for: evaluation, answer: answer),
                feedback: feedback
            )
        )
        updated.updatedAt = now
        return updated
    }

    func advanceAfterFeedback(_ session: TeachMeSession, now: Date = Date()) -> TeachMeSession {
        guard session.state == .feedback, let last = session.answerHistory.last else { return session }

        if last.evaluation == .correct || session.followUpCount >= 1 {
            var completed = session
            completed.state = .complete
            completed.updatedAt = now
            return completed
        }

        guard let conceptID = session.activeConceptID,
              let conceptName = session.activeConceptName else {
            var completed = session
            completed.state = .complete
            completed.updatedAt = now
            return completed
        }

        let candidate = TeachMeConceptCandidate(
            conceptID: conceptID,
            conceptName: conceptName,
            source: .knowledgeGap,
            originatingKnowledgeGap: session.activeQuestion?.originatingKnowledgeGap,
            sourceReferences: session.activeQuestion?.sourceReferences ?? []
        )
        var followUp = session
        followUp.followUpCount += 1
        followUp.activeQuestion = makeQuestion(for: candidate, followUp: true, now: now)
        followUp.state = .question
        followUp.updatedAt = now
        return followUp
    }

    func selectConcept(
        adaptiveContext: AdaptiveExplanationContext,
        manualConcept: String? = nil
    ) -> TeachMeConceptCandidate? {
        if let gap = adaptiveContext.identifiedKnowledgeGaps.firstNonEmpty {
            return candidate(
                name: gap,
                source: .knowledgeGap,
                originatingKnowledgeGap: gap,
                references: adaptiveContext.retrievedNoteSources
            )
        }

        if let concept = adaptiveContext.historicallyConfusingConcepts.firstNonEmpty {
            return candidate(
                name: concept,
                source: .historicallyConfusing,
                originatingKnowledgeGap: nil,
                references: adaptiveContext.retrievedNoteSources
            )
        }

        let weakMastery = adaptiveContext.masteryStates
            .filter { $0.value == .struggling || $0.value == .needsPractice }
            .map(\.key)
            .sorted()
            .firstNonEmpty
        if let weakMastery {
            return candidate(
                name: weakMastery,
                source: .weakMastery,
                originatingKnowledgeGap: nil,
                references: adaptiveContext.retrievedNoteSources
            )
        }

        if let manualConcept = manualConcept?.trimmingCharacters(in: .whitespacesAndNewlines), !manualConcept.isEmpty {
            return candidate(
                name: manualConcept,
                source: .manual,
                originatingKnowledgeGap: nil,
                references: adaptiveContext.retrievedNoteSources
            )
        }

        return nil
    }

    private func makeQuestion(
        for candidate: TeachMeConceptCandidate,
        followUp: Bool,
        now: Date
    ) -> TeachMeQuestion {
        let prompt = followUp
            ? "Follow-up: what is one missing step that connects \(candidate.conceptName) to the idea in your notes?"
            : "What is the key idea behind \(candidate.conceptName), and why does it matter in these notes?"

        return TeachMeQuestion(
            conceptID: candidate.conceptID,
            conceptName: candidate.conceptName,
            question: prompt,
            sourceReferences: candidate.sourceReferences,
            originatingKnowledgeGap: candidate.originatingKnowledgeGap,
            generatedAt: now
        )
    }

    private func evaluate(answer: String, for question: TeachMeQuestion) -> TeachMeEvaluation {
        let answerTokens = meaningfulTokens(answer)
        guard !answerTokens.isEmpty else { return .incorrect }

        let conceptTokens = Set(meaningfulTokens(question.conceptName))
        let overlap = answerTokens.filter { conceptTokens.contains($0) }.count
        let explanationSignals = answerTokens.filter { explanatoryTokens.contains($0) }.count

        if answerTokens.count >= 10 && (overlap > 0 || explanationSignals >= 2 || conceptTokens.isEmpty) {
            return .correct
        }
        if answerTokens.count >= 4 || overlap > 0 || explanationSignals > 0 {
            return .partiallyCorrect
        }
        return .incorrect
    }

    private func feedback(
        for evaluation: TeachMeEvaluation,
        answer: String,
        question: TeachMeQuestion
    ) -> String {
        let sourceHint = question.sourceReferences.first?.noteTitle
        let sourceText = sourceHint.map { " Check \($0) for the source idea." } ?? ""
        switch evaluation {
        case .correct:
            return "Good. You named the core idea and connected it to the note.\(sourceText)"
        case .partiallyCorrect:
            return "Partly there. Add the missing relationship: what \(question.conceptName) changes, explains, or enables.\(sourceText)"
        case .incorrect:
            return "Review the prerequisite first, then restate \(question.conceptName) in your own words.\(sourceText)"
        }
    }

    private func confidence(for evaluation: TeachMeEvaluation, answer: String) -> Double {
        let base: Double
        switch evaluation {
        case .correct:
            base = 0.82
        case .partiallyCorrect:
            base = 0.55
        case .incorrect:
            base = 0.25
        }
        let lengthBoost = min(Double(meaningfulTokens(answer).count) / 80.0, 0.08)
        return max(0, min(1, base + lengthBoost))
    }

    private func candidate(
        name: String,
        source: TeachMeConceptCandidate.Source,
        originatingKnowledgeGap: String?,
        references: [AdaptiveExplanationSource]
    ) -> TeachMeConceptCandidate {
        TeachMeConceptCandidate(
            conceptID: Self.conceptID(for: name),
            conceptName: name,
            source: source,
            originatingKnowledgeGap: originatingKnowledgeGap,
            sourceReferences: references
        )
    }

    static func conceptID(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func meaningfulTokens(_ value: String) -> [String] {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    private var explanatoryTokens: Set<String> {
        [
            "adjusts", "allows", "because", "changes", "connects", "explains",
            "helps", "matters", "moves", "produces", "reduces", "relates",
            "supports", "uses"
        ]
    }
}

private extension Array where Element == String {
    var firstNonEmpty: String? {
        first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
