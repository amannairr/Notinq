import Foundation

struct AdaptiveExplanationSource: Codable, Equatable, Sendable {
    var sourceID: String
    var sourceType: String
    var noteID: UUID?
    var noteTitle: String
    var sectionTitle: String?
    var snippet: String
    var relevantExcerpt: String

    init(
        sourceID: String = UUID().uuidString,
        sourceType: String = "note",
        noteID: UUID? = nil,
        noteTitle: String,
        sectionTitle: String? = nil,
        snippet: String = "",
        relevantExcerpt: String = ""
    ) {
        self.sourceID = sourceID
        self.sourceType = sourceType
        self.noteID = noteID
        self.noteTitle = noteTitle
        self.sectionTitle = sectionTitle
        self.snippet = snippet
        self.relevantExcerpt = relevantExcerpt
    }

    var groundingText: String {
        let excerpt = relevantExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !excerpt.isEmpty { return excerpt }
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AdaptiveExplanationContext: Equatable, Sendable {
    var selectedText: String
    var conceptIDs: [String]
    var weakConcepts: [String]
    var strongConcepts: [String]
    var missingPrerequisites: [String]
    var identifiedKnowledgeGaps: [String]
    var historicallyHelpfulConcepts: [String]
    var historicallyConfusingConcepts: [String]
    var priorHelpfulExplanationsCount: Int
    var priorConfusingExplanationsCount: Int
    var masteryStates: [String: MasteryState]
    var retrievedNoteSources: [AdaptiveExplanationSource]
    var inferredLearnerLevel: String
    var confidence: Double

    var hasEvidence: Bool {
        !weakConcepts.isEmpty || !strongConcepts.isEmpty || !missingPrerequisites.isEmpty || !retrievedNoteSources.isEmpty
    }

    var hasSourceGrounding: Bool {
        retrievedNoteSources.contains { !$0.groundingText.isEmpty }
    }

    init(
        selectedText: String = "",
        conceptIDs: [String] = [],
        weakConcepts: [String] = [],
        strongConcepts: [String] = [],
        missingPrerequisites: [String] = [],
        identifiedKnowledgeGaps: [String] = [],
        historicallyHelpfulConcepts: [String] = [],
        historicallyConfusingConcepts: [String] = [],
        priorHelpfulExplanationsCount: Int = 0,
        priorConfusingExplanationsCount: Int = 0,
        masteryStates: [String: MasteryState] = [:],
        retrievedNoteSources: [AdaptiveExplanationSource] = [],
        inferredLearnerLevel: String = "Unknown",
        confidence: Double = 0
    ) {
        self.selectedText = selectedText
        self.conceptIDs = conceptIDs
        self.weakConcepts = weakConcepts
        self.strongConcepts = strongConcepts
        self.missingPrerequisites = missingPrerequisites
        self.historicallyHelpfulConcepts = historicallyHelpfulConcepts
        self.historicallyConfusingConcepts = historicallyConfusingConcepts
        self.identifiedKnowledgeGaps = identifiedKnowledgeGaps.isEmpty
            ? Self.knowledgeGaps(
                missingPrerequisites: missingPrerequisites,
                weakConcepts: weakConcepts,
                historicallyConfusingConcepts: historicallyConfusingConcepts
            )
            : Self.uniqueStrings(Array(identifiedKnowledgeGaps.prefix(3)))
        self.priorHelpfulExplanationsCount = max(0, priorHelpfulExplanationsCount)
        self.priorConfusingExplanationsCount = max(0, priorConfusingExplanationsCount)
        self.masteryStates = masteryStates
        self.retrievedNoteSources = retrievedNoteSources
        self.inferredLearnerLevel = inferredLearnerLevel
        self.confidence = max(0, min(1, confidence))
    }

    static func unavailable() -> AdaptiveExplanationContext {
        AdaptiveExplanationContext(
            inferredLearnerLevel: "Unknown",
            confidence: 0
        )
    }

    static func fromTutorContext(_ context: AdaptiveTutorContext) -> AdaptiveExplanationContext {
        let weakConcepts = uniqueNames(context.weakConcepts + context.knowledgeGaps)
        let strongConcepts = uniqueNames(context.strongConcepts)
        let missingPrerequisites = uniqueNames(context.missingPrerequisites)
        let conceptIDs = uniqueIDs(context.weakConcepts + context.strongConcepts + context.missingPrerequisites + context.knowledgeGaps)
        let sources = context.retrievedNotes.prefix(3).map {
            let excerpt = preferredExcerpt(snippet: $0.snippet, content: $0.content)
            return AdaptiveExplanationSource(
                sourceID: $0.id,
                sourceType: $0.sourceType.rawValue,
                noteID: $0.noteID,
                noteTitle: $0.noteTitle,
                sectionTitle: $0.title.isEmpty ? nil : $0.title,
                snippet: $0.snippet,
                relevantExcerpt: excerpt
            )
        }
        let evidenceCount = weakConcepts.count + strongConcepts.count + missingPrerequisites.count + sources.count
        guard evidenceCount > 0 else { return .unavailable() }
        let confidence = min(0.85, 0.35 + Double(evidenceCount) * 0.1)

        return AdaptiveExplanationContext(
            conceptIDs: conceptIDs,
            weakConcepts: weakConcepts,
            strongConcepts: strongConcepts,
            missingPrerequisites: missingPrerequisites,
            identifiedKnowledgeGaps: Self.knowledgeGaps(
                missingPrerequisites: missingPrerequisites,
                weakConcepts: weakConcepts,
                historicallyConfusingConcepts: []
            ),
            historicallyHelpfulConcepts: [],
            historicallyConfusingConcepts: [],
            retrievedNoteSources: sources,
            inferredLearnerLevel: inferredLearnerLevel(
                weakConcepts: weakConcepts,
                strongConcepts: strongConcepts,
                missingPrerequisites: missingPrerequisites,
                sources: sources
            ),
            confidence: confidence
        )
    }

    private static func inferredLearnerLevel(
        weakConcepts: [String],
        strongConcepts: [String],
        missingPrerequisites: [String],
        sources: [AdaptiveExplanationSource]
    ) -> String {
        if !missingPrerequisites.isEmpty { return "Needs prerequisite support" }
        if !weakConcepts.isEmpty { return "Developing understanding" }
        if !strongConcepts.isEmpty { return "Ready for deeper explanation" }
        if !sources.isEmpty { return "Context available" }
        return "Unknown"
    }

    private static func uniqueNames(_ concepts: [Concept]) -> [String] {
        var seen: Set<String> = []
        return concepts.compactMap { concept in
            let name = concept.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return nil }
            return name
        }
    }

    private static func uniqueIDs(_ concepts: [Concept]) -> [String] {
        var seen: Set<String> = []
        return concepts.compactMap { concept in
            let id = concept.id.uuidString
            guard seen.insert(id).inserted else { return nil }
            return id
        }
    }

    private static func preferredExcerpt(snippet: String, content: String) -> String {
        let snippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !snippet.isEmpty { return String(snippet.prefix(480)) }
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(content.prefix(480))
    }

    mutating func applyLearningProfiles(
        _ profiles: [ConceptLearningProfile],
        conceptNameByID: [String: String] = [:]
    ) {
        let relevantIDs = Set(conceptIDs)
        let relevantProfiles = profiles.filter { relevantIDs.isEmpty || relevantIDs.contains($0.conceptID) }
        historicallyHelpfulConcepts = Self.uniqueStrings(
            relevantProfiles
                .filter { $0.helpfulCount > $0.confusedCount }
                .map { conceptNameByID[$0.conceptID] ?? $0.conceptID }
        )
        historicallyConfusingConcepts = Self.uniqueStrings(
            relevantProfiles
                .filter { ($0.confusedCount > 0 && $0.confusedCount >= $0.helpfulCount) || $0.requestedAgainCount >= 2 }
                .map { conceptNameByID[$0.conceptID] ?? $0.conceptID }
        )
        priorHelpfulExplanationsCount = relevantProfiles.reduce(0) { $0 + $1.helpfulCount }
        priorConfusingExplanationsCount = relevantProfiles.reduce(0) { $0 + $1.confusedCount + $1.requestedAgainCount }
        identifiedKnowledgeGaps = Self.knowledgeGaps(
            missingPrerequisites: missingPrerequisites,
            weakConcepts: weakConcepts,
            historicallyConfusingConcepts: historicallyConfusingConcepts
        )
        let visibleConcepts = Set(
            Self.uniqueStrings(weakConcepts + strongConcepts + identifiedKnowledgeGaps)
                .map { $0.lowercased() }
        )
        let masteryBuilder = ConceptMasteryBuilder()
        let masteryPairs: [(String, MasteryState)] = relevantProfiles.compactMap { profile in
            let conceptName = conceptNameByID[profile.conceptID] ?? profile.conceptID
            let normalizedName = conceptName.lowercased()
            guard visibleConcepts.isEmpty || visibleConcepts.contains(normalizedName) else { return nil }
            return (conceptName, masteryBuilder.mastery(for: profile).masteryState)
        }
        masteryStates = Dictionary(masteryPairs, uniquingKeysWith: { first, _ in first })
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }
    }

    private static func knowledgeGaps(
        missingPrerequisites: [String],
        weakConcepts: [String],
        historicallyConfusingConcepts: [String]
    ) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for value in missingPrerequisites + weakConcepts + historicallyConfusingConcepts {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
            if result.count == 3 { break }
        }
        return result
    }
}
