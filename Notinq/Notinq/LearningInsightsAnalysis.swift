import Foundation
import NaturalLanguage
import Combine

enum LectureContentSourceKind: String, Codable, CaseIterable, Identifiable {
    case transcript
    case slides
    case notes
    case audio
    case whiteboard
    case pdf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .transcript:
            return "Transcript"
        case .slides:
            return "Slides"
        case .notes:
            return "Notes"
        case .audio:
            return "Audio"
        case .whiteboard:
            return "Whiteboard"
        case .pdf:
            return "PDF"
        }
    }

    var defaultWeight: Double {
        switch self {
        case .transcript:
            return 1.0
        case .slides:
            return 1.2
        case .notes:
            return 1.0
        case .audio:
            return 1.1
        case .whiteboard:
            return 1.1
        case .pdf:
            return 1.0
        }
    }
}

struct LectureContentSource: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: LectureContentSourceKind
    var title: String
    var text: String
    var weight: Double = 1.0

    var effectiveWeight: Double {
        max(0.1, weight * kind.defaultWeight)
    }

    var isVisualCandidateSource: Bool {
        kind == .slides || kind == .whiteboard || kind == .pdf
    }
}

struct LectureAnalysisInput: Codable, Equatable {
    var lectureTitle: String = ""
    var noteTitle: String = ""
    var studentNotes: String = ""
    var sources: [LectureContentSource] = []

    var hasLectureSources: Bool {
        sources.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    var hasStudentNotes: Bool {
        !studentNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAnyContent: Bool {
        hasLectureSources || hasStudentNotes
    }
}

enum LearningInsightsAnalysisPhase: Equatable {
    case idle
    case loading
    case ready
    case empty
    case failure(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var canRetry: Bool {
        if case .failure = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Add a transcript or slide notes, then run the analysis."
        case .loading:
            return "Analyzing lecture sources..."
        case .ready:
            return "Analysis updated."
        case .empty:
            return "No lecture concepts were identified."
        case .failure(let message):
            return message
        }
    }
}

enum LearningInsightsPreviewMode: String, CaseIterable, Identifiable {
    case explanation
    case flashcards
    case quiz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explanation:
            return "Explanation"
        case .flashcards:
            return "Flashcards"
        case .quiz:
            return "Quiz"
        }
    }
}

enum LearningInsightsAction: String, CaseIterable, Identifiable {
    case analyze
    case explanation
    case flashcards
    case quiz
    case insert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .analyze:
            return "Analyze Lecture"
        case .explanation:
            return "Generate Explanation"
        case .flashcards:
            return "Create Flashcards"
        case .quiz:
            return "Create Quiz Questions"
        case .insert:
            return "Insert Into Note"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .analyze:
            return "Analyze lecture sources"
        case .explanation:
            return "Generate explanation"
        case .flashcards:
            return "Create flashcards"
        case .quiz:
            return "Create quiz questions"
        case .insert:
            return "Insert generated content into note"
        }
    }
}

enum LearningInsightsButtonAvailability {
    static func canAnalyze(isAnalyzing: Bool, hasSourceText: Bool) -> Bool {
        hasSourceText && !isAnalyzing
    }

    static func canGenerate(isAnalyzing: Bool, hasConceptSelection: Bool) -> Bool {
        hasConceptSelection && !isAnalyzing
    }

    static func canInsert(isAnalyzing: Bool, hasGeneratedPreview: Bool) -> Bool {
        hasGeneratedPreview && !isAnalyzing
    }
}

enum LectureCoverageState: String, Codable, CaseIterable, Identifiable {
    case missing
    case partial
    case covered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .missing:
            return "Missing"
        case .partial:
            return "Partially Captured"
        case .covered:
            return "Well Covered"
        }
    }
}

struct LectureCoverageItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var state: LectureCoverageState
    var whatWasMissed: String
    var whyItMatters: String
    var shortExplanation: String
    var suggestedAddition: String
    var importance: Double
    var evidence: [String] = []
    var matchScore: Double = 0
    var noteSummary: String = ""
}

struct LectureVisualGap: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var whatWasMissed: String
    var whyItMatters: String
    var shortExplanation: String
    var suggestedAddition: String
    var importance: Double
    var evidence: [String] = []
}

struct LectureReviewPriorityItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var rank: Int
    var title: String
    var reason: String
    var state: LectureCoverageState
    var importance: Double
}

struct LectureCompletenessAnalysis: Codable, Equatable {
    var completenessScore: Double = 0
    var lectureConceptCount: Int = 0
    var noteConceptCount: Int = 0
    var missingConcepts: [LectureCoverageItem] = []
    var partiallyCapturedConcepts: [LectureCoverageItem] = []
    var wellCoveredConcepts: [LectureCoverageItem] = []
    var missingVisualContent: [LectureVisualGap] = []
    var reviewPriority: [LectureReviewPriorityItem] = []
    var summary: String = ""
    var generatedAt: Date = Date()

    var scorePercent: Int {
        Int((completenessScore.clamped(to: 0...1) * 100).rounded())
    }

    var hasResults: Bool {
        lectureConceptCount > 0 || noteConceptCount > 0 || !missingConcepts.isEmpty || !partiallyCapturedConcepts.isEmpty || !wellCoveredConcepts.isEmpty || !missingVisualContent.isEmpty
    }
}

struct LectureIngestionSnapshot {
    var lectureTitle: String
    var noteTitle: String
    var studentNotes: String
    var sources: [LectureContentSource]
    var lectureText: String
    var sourceCount: Int
    var noteWordCount: Int
    var lectureWordCount: Int
}

struct LectureConceptCandidate: Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var normalizedTitle: String
    var sourceKinds: Set<LectureContentSourceKind>
    var evidence: [String]
    var importance: Double
    var tokenCount: Int
    var detailScore: Double

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LectureContentIngestionLayer {
    func ingest(input: LectureAnalysisInput) -> LectureIngestionSnapshot {
        let lectureSources = input.sources.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let lectureText = lectureSources
            .map(\.text)
            .joined(separator: "\n\n")

        return LectureIngestionSnapshot(
            lectureTitle: input.lectureTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            noteTitle: input.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            studentNotes: input.studentNotes,
            sources: lectureSources,
            lectureText: lectureText,
            sourceCount: lectureSources.count,
            noteWordCount: lectureWordCount(in: input.studentNotes),
            lectureWordCount: lectureWordCount(in: lectureText)
        )
    }

    private func lectureWordCount(in text: String) -> Int {
        text
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }
}

struct LectureConceptExtractionLayer {
    private let extractor = PhraseExtractor()

    func extract(from snapshot: LectureIngestionSnapshot) -> LectureConceptExtractionResult {
        let lectureConcepts = merge(
            snapshot.sources.flatMap { source in
                extractConcepts(
                    text: source.text,
                    sourceKinds: [source.kind],
                    sourceWeights: [source.kind: source.effectiveWeight],
                    preferVisualContent: source.isVisualCandidateSource
                )
            }
        )
        let noteConcepts = extractConcepts(
            text: snapshot.studentNotes,
            sourceKinds: [.notes],
            sourceWeights: [.notes: 1.0],
            preferVisualContent: false
        )

        return LectureConceptExtractionResult(
            lectureConcepts: lectureConcepts,
            noteConcepts: noteConcepts,
            visualSignals: extractVisualSignals(from: snapshot)
        )
    }

    private func merge(_ concepts: [LectureConceptCandidate]) -> [LectureConceptCandidate] {
        var merged: [String: LectureConceptCandidate] = [:]
        for concept in concepts {
            let key = concept.normalizedTitle
            if var existing = merged[key] {
                existing.sourceKinds.formUnion(concept.sourceKinds)
                existing.evidence.append(contentsOf: concept.evidence)
                existing.importance = max(existing.importance, concept.importance)
                existing.tokenCount = max(existing.tokenCount, concept.tokenCount)
                existing.detailScore = max(existing.detailScore, concept.detailScore)
                if existing.title.count < concept.title.count {
                    existing.title = concept.title
                }
                merged[key] = existing
            } else {
                merged[key] = concept
            }
        }

        return merged.values.sorted {
            if $0.importance == $1.importance {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.importance > $1.importance
        }
    }

    private func extractConcepts(
        text: String,
        sourceKinds: Set<LectureContentSourceKind>,
        sourceWeights: [LectureContentSourceKind: Double],
        preferVisualContent: Bool
    ) -> [LectureConceptCandidate] {
        let phrases = extractor.extractPhrases(from: text, preferVisualContent: preferVisualContent)
        let filtered = phrases.filter { $0.title.count >= 2 }

        var merged: [String: LectureConceptCandidate] = [:]
        for phrase in filtered {
            let normalized = normalizeLectureText(phrase.title)
            guard !normalized.isEmpty else { continue }

            var candidate = merged[normalized] ?? LectureConceptCandidate(
                title: phrase.title,
                normalizedTitle: normalized,
                sourceKinds: sourceKinds,
                evidence: [],
                importance: 0,
                tokenCount: phrase.tokenCount,
                detailScore: phrase.detailScore
            )
            candidate.sourceKinds.formUnion(sourceKinds)
            candidate.evidence.append(contentsOf: phrase.evidence)
            candidate.importance = max(candidate.importance, phrase.importance * averageWeight(for: sourceWeights, kinds: sourceKinds))
            candidate.tokenCount = max(candidate.tokenCount, phrase.tokenCount)
            candidate.detailScore = max(candidate.detailScore, phrase.detailScore)
            if candidate.title.count < phrase.title.count {
                candidate.title = phrase.title
            }
            merged[normalized] = candidate
        }

        return merged.values
            .sorted {
                if $0.importance == $1.importance {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.importance > $1.importance
            }
            .prefix(18)
            .map { $0 }
    }

    private func extractVisualSignals(from snapshot: LectureIngestionSnapshot) -> [LectureVisualGap] {
        let visualKeywords = [
            "diagram", "figure", "chart", "workflow", "architecture", "pipeline",
            "graph", "table", "flowchart", "visual", "screenshot", "illustration", "sketch", "whiteboard"
        ]

        var results: [LectureVisualGap] = []
        for source in snapshot.sources where source.isVisualCandidateSource {
            for rawLine in source.text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                let normalized = normalizeLectureText(line)
                guard visualKeywords.contains(where: { normalized.contains($0) }) else { continue }

                let title = conciseVisualTitle(from: line)
                results.append(
                    LectureVisualGap(
                        title: title,
                        whatWasMissed: "The lecture appears to have used a visual explanation here, but the notes do not capture it.",
                        whyItMatters: "Visuals often communicate structure, process flow, or relationships that are hard to reconstruct from text alone.",
                        shortExplanation: "The slide or board content strongly suggests a diagram-heavy explanation.",
                        suggestedAddition: "Add a sketch, a flow note, or a short caption describing the visual relationship.",
                        importance: source.kind == .slides ? 1.4 : 1.1,
                        evidence: [line]
                    )
                )
            }
        }

        return dedupeVisualGaps(results)
    }

    private func averageWeight(for sourceWeights: [LectureContentSourceKind: Double], kinds: Set<LectureContentSourceKind>) -> Double {
        let weights = kinds.map { sourceWeights[$0] ?? 1.0 }
        guard !weights.isEmpty else { return 1.0 }
        return weights.reduce(0, +) / Double(weights.count)
    }

    private func conciseVisualTitle(from line: String) -> String {
        let trimmed = line
            .replacingOccurrences(of: "•", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 72 {
            return trimmed
        }
        let words = trimmed.split(separator: " ")
        return words.prefix(8).joined(separator: " ") + "..."
    }
}

struct LectureConceptExtractionResult {
    var lectureConcepts: [LectureConceptCandidate]
    var noteConcepts: [LectureConceptCandidate]
    var visualSignals: [LectureVisualGap]
}

struct LectureConceptComparisonLayer {
    func compare(extraction: LectureConceptExtractionResult) -> LectureComparisonResult {
        let noteLookup = extraction.noteConcepts
        var missing: [LectureCoverageItem] = []
        var partial: [LectureCoverageItem] = []
        var covered: [LectureCoverageItem] = []

        for concept in extraction.lectureConcepts {
            let match = bestMatch(for: concept, against: noteLookup)
            let state = classify(match: match)
            let item = makeItem(for: concept, match: match, state: state)

            switch state {
            case .missing:
                missing.append(item)
            case .partial:
                partial.append(item)
            case .covered:
                covered.append(item)
            }
        }

        let visualGaps = extraction.visualSignals
            .sorted { $0.importance > $1.importance }

        let completeness = LectureCompletenessScoringLayer().score(
            lectureConcepts: extraction.lectureConcepts,
            missing: missing,
            partial: partial,
            covered: covered,
            visualGaps: visualGaps
        )

        let reviewPriority = makeReviewPriority(
            missing: missing,
            partial: partial,
            visualGaps: visualGaps
        )

        return LectureComparisonResult(
            completenessScore: completeness,
            lectureConceptCount: extraction.lectureConcepts.count,
            noteConceptCount: extraction.noteConcepts.count,
            missingConcepts: missing.sorted { $0.importance > $1.importance },
            partiallyCapturedConcepts: partial.sorted { $0.importance > $1.importance },
            wellCoveredConcepts: covered.sorted { $0.importance > $1.importance },
            missingVisualContent: visualGaps,
            reviewPriority: reviewPriority,
            summary: makeSummary(
                lectureCount: extraction.lectureConcepts.count,
                noteCount: extraction.noteConcepts.count,
                missingCount: missing.count,
                partialCount: partial.count,
                coveredCount: covered.count,
                visualGapCount: visualGaps.count,
                completeness: completeness
            )
        )
    }

    private func bestMatch(for lecture: LectureConceptCandidate, against notes: [LectureConceptCandidate]) -> ConceptMatch {
        var best = ConceptMatch(title: "", score: 0, noteEvidence: [], noteDetailScore: 0)
        for note in notes {
            let score = matchingScore(lecture: lecture, note: note)
            if score.score > best.score {
                best = score
            }
        }
        return best
    }

    private func matchingScore(lecture: LectureConceptCandidate, note: LectureConceptCandidate) -> ConceptMatch {
        let exact = lecture.normalizedTitle == note.normalizedTitle ? 1.0 : 0.0
        let tokenOverlap = tokenOverlapScore(lhs: lecture.normalizedTitle, rhs: note.normalizedTitle)
        let semantic = Double(EmbeddingService.shared.similarity(between: lecture.title, and: note.title))
        let score = max(exact, max(tokenOverlap, semantic))
        let evidence = note.evidence
        let detailScore = min(1.0, Double(note.tokenCount) / Double(max(lecture.tokenCount, 1)) + note.detailScore * 0.35)
        return ConceptMatch(
            title: note.title,
            score: score,
            noteEvidence: evidence,
            noteDetailScore: detailScore
        )
    }

    private func classify(match: ConceptMatch) -> LectureCoverageState {
        guard match.score > 0 else { return .missing }
        if match.score >= 0.75 && match.noteDetailScore >= 0.65 {
            return .covered
        }
        if match.score >= 0.40 || match.noteDetailScore >= 0.35 {
            return .partial
        }
        return .missing
    }

    private func makeItem(
        for lecture: LectureConceptCandidate,
        match: ConceptMatch,
        state: LectureCoverageState
    ) -> LectureCoverageItem {
        let explanation = explanationForLectureConcept(
            lecture: lecture,
            match: match,
            state: state
        )

        return LectureCoverageItem(
            title: lecture.displayTitle,
            state: state,
            whatWasMissed: explanation.whatWasMissed,
            whyItMatters: explanation.whyItMatters,
            shortExplanation: explanation.shortExplanation,
            suggestedAddition: explanation.suggestedAddition,
            importance: lecture.importance,
            evidence: lecture.evidence,
            matchScore: match.score,
            noteSummary: match.title
        )
    }

    private func explanationForLectureConcept(
        lecture: LectureConceptCandidate,
        match: ConceptMatch,
        state: LectureCoverageState
    ) -> (whatWasMissed: String, whyItMatters: String, shortExplanation: String, suggestedAddition: String) {
        let evidenceSnippet = snippet(from: lecture.evidence.first ?? lecture.title)
        let missingDetail = missingDetailSnippet(from: lecture.evidence.first ?? lecture.title, against: match.noteEvidence.first ?? "")

        switch state {
        case .missing:
            return (
                whatWasMissed: missingDetail.isEmpty ? "The lecture concept was not represented in the notes." : "The notes did not capture \(missingDetail).",
                whyItMatters: importanceReason(for: lecture),
                shortExplanation: evidenceSnippet.isEmpty ? "This was a lecture concept with no clear note match." : evidenceSnippet,
                suggestedAddition: suggestionForConcept(lecture.title, lecture.evidence.first)
            )
        case .partial:
            return (
                whatWasMissed: missingDetail.isEmpty ? "The notes mention the concept, but not the supporting detail." : "The notes mention \(lecture.title), but missed \(missingDetail).",
                whyItMatters: importanceReason(for: lecture),
                shortExplanation: evidenceSnippet.isEmpty ? "The lecture included more detail than the notes captured." : evidenceSnippet,
                suggestedAddition: suggestionForConcept(lecture.title, lecture.evidence.first)
            )
        case .covered:
            return (
                whatWasMissed: "The concept is represented well enough to reconstruct the lecture point.",
                whyItMatters: importanceReason(for: lecture),
                shortExplanation: evidenceSnippet.isEmpty ? "The notes capture the core concept and supporting detail." : evidenceSnippet,
                suggestedAddition: "No major addition is required. Add an example only if you want a stronger recall cue."
            )
        }
    }

    private func importanceReason(for lecture: LectureConceptCandidate) -> String {
        let sourceNames = lecture.sourceKinds
            .map(\.displayName)
            .sorted()
            .joined(separator: ", ")
        if sourceNames.isEmpty {
            return "This is a recurring lecture concept and is likely central to the topic."
        }
        return "This concept came from \(sourceNames) and is likely part of the lecture's main explanation."
    }

    private func suggestionForConcept(_ concept: String, _ evidence: String?) -> String {
        let base = "Add a short definition and one concrete example for \(concept)."
        guard let evidence else { return base }
        let detail = missingDetailSnippet(from: evidence, against: concept)
        guard !detail.isEmpty else { return base }
        return "Add a note that explains \(detail) in the context of \(concept)."
    }

    private func makeReviewPriority(
        missing: [LectureCoverageItem],
        partial: [LectureCoverageItem],
        visualGaps: [LectureVisualGap]
    ) -> [LectureReviewPriorityItem] {
        let conceptItems = missing.map { (item: $0, state: LectureCoverageState.missing) }
            + partial.map { (item: $0, state: LectureCoverageState.partial) }

        let visualItems = visualGaps.map {
            LectureReviewPriorityItem(
                rank: 0,
                title: $0.title,
                reason: $0.whatWasMissed,
                state: .missing,
                importance: $0.importance + 0.1
            )
        }

        let sortedConcepts = conceptItems
            .sorted {
                let lhsScore = $0.item.importance * gapMultiplier(for: $0.state)
                let rhsScore = $1.item.importance * gapMultiplier(for: $1.state)
                if lhsScore == rhsScore {
                    return $0.item.title.localizedCaseInsensitiveCompare($1.item.title) == .orderedAscending
                }
                return lhsScore > rhsScore
            }
            .map {
                LectureReviewPriorityItem(
                    rank: 0,
                    title: $0.item.title,
                    reason: $0.item.whatWasMissed,
                    state: $0.state,
                    importance: $0.item.importance
                )
            }

        let combined = (sortedConcepts + visualItems)
            .sorted {
                let lhsScore = $0.importance * gapMultiplier(for: $0.state)
                let rhsScore = $1.importance * gapMultiplier(for: $1.state)
                if lhsScore == rhsScore {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return lhsScore > rhsScore
            }

        return combined.enumerated().map { index, item in
            var updated = item
            updated.rank = index + 1
            return updated
        }
    }

    private func gapMultiplier(for state: LectureCoverageState) -> Double {
        switch state {
        case .missing:
            return 1.35
        case .partial:
            return 1.05
        case .covered:
            return 0.75
        }
    }

    private func makeSummary(
        lectureCount: Int,
        noteCount: Int,
        missingCount: Int,
        partialCount: Int,
        coveredCount: Int,
        visualGapCount: Int,
        completeness: Double
    ) -> String {
        let percent = Int((completeness * 100).rounded())
        return "\(percent)% completeness across \(lectureCount) lecture concepts and \(noteCount) note concepts, with \(missingCount) missing, \(partialCount) partial, \(coveredCount) covered, and \(visualGapCount) missing visual cues."
    }
}

struct LectureComparisonResult {
    var completenessScore: Double
    var lectureConceptCount: Int
    var noteConceptCount: Int
    var missingConcepts: [LectureCoverageItem]
    var partiallyCapturedConcepts: [LectureCoverageItem]
    var wellCoveredConcepts: [LectureCoverageItem]
    var missingVisualContent: [LectureVisualGap]
    var reviewPriority: [LectureReviewPriorityItem]
    var summary: String
}

struct LectureCompletenessScoringLayer {
    func score(
        lectureConcepts: [LectureConceptCandidate],
        missing: [LectureCoverageItem],
        partial: [LectureCoverageItem],
        covered: [LectureCoverageItem],
        visualGaps: [LectureVisualGap]
    ) -> Double {
        let totalConceptImportance = lectureConcepts.reduce(0) { $0 + max($1.importance, 0.1) }
        guard totalConceptImportance > 0 else { return 0 }

        let coveredScore = covered.reduce(0) { $0 + max($1.importance, 0.1) }
        let partialScore = partial.reduce(0) { $0 + max($1.importance, 0.1) } * 0.55
        let visualPenalty = visualGaps.reduce(0) { $0 + max($1.importance, 0.1) } * 0.12
        let raw = (coveredScore + partialScore - visualPenalty) / totalConceptImportance
        return raw.clamped(to: 0...1)
    }
}

struct LectureCompletenessAnalyzer {
    static let shared = LectureCompletenessAnalyzer()

    private let ingestionLayer = LectureContentIngestionLayer()
    private let extractionLayer = LectureConceptExtractionLayer()
    private let comparisonLayer = LectureConceptComparisonLayer()

    init() {}

    func analyze(input: LectureAnalysisInput) -> LectureCompletenessAnalysis {
        guard input.hasAnyContent else {
            return LectureCompletenessAnalysis(
                completenessScore: 0,
                summary: "Add lecture transcript or slide text to begin the analysis."
            )
        }

        let ingestion = ingestionLayer.ingest(input: input)
        let extraction = extractionLayer.extract(from: ingestion)
        let comparison = comparisonLayer.compare(extraction: extraction)

        return LectureCompletenessAnalysis(
            completenessScore: comparison.completenessScore,
            lectureConceptCount: comparison.lectureConceptCount,
            noteConceptCount: comparison.noteConceptCount,
            missingConcepts: comparison.missingConcepts,
            partiallyCapturedConcepts: comparison.partiallyCapturedConcepts,
            wellCoveredConcepts: comparison.wellCoveredConcepts,
            missingVisualContent: comparison.missingVisualContent,
            reviewPriority: comparison.reviewPriority,
            summary: comparison.summary,
            generatedAt: Date()
        )
    }
}

@MainActor
final class LearningInsightsWorkspaceModel: ObservableObject {
    @Published var analysis: LectureCompletenessAnalysis?
    @Published var phase: LearningInsightsAnalysisPhase
    @Published var selectedConcept: LectureCoverageItem?
    @Published var previewMode: LearningInsightsPreviewMode
    @Published var generatedPreview: String
    @Published var statusMessage: String

    private let onSaveAnalysis: (LectureCompletenessAnalysis) -> Void
    private let onInsertIntoNote: (String) -> Void
    private let analyzer: (LectureAnalysisInput) throws -> LectureCompletenessAnalysis
    private var currentRequestID: UUID?
    private var noteTitle: String
    private var studentNotes: String

    init(
        noteTitle: String,
        studentNotes: String,
        initialAnalysis: LectureCompletenessAnalysis?,
        onSaveAnalysis: @escaping (LectureCompletenessAnalysis) -> Void,
        onInsertIntoNote: @escaping (String) -> Void,
        analyzer: ((LectureAnalysisInput) throws -> LectureCompletenessAnalysis)? = nil
    ) {
        self.noteTitle = noteTitle
        self.studentNotes = studentNotes
        self.onSaveAnalysis = onSaveAnalysis
        self.onInsertIntoNote = onInsertIntoNote
        self.analyzer = analyzer ?? { input in
            LectureCompletenessAnalyzer().analyze(input: input)
        }
        analysis = initialAnalysis
        previewMode = .explanation
        generatedPreview = ""
        statusMessage = initialAnalysis?.summary ?? LearningInsightsAnalysisPhase.idle.statusText
        phase = Self.phase(for: initialAnalysis)
        syncSelectionIfNeeded(using: initialAnalysis)
    }

    var hasSelectedConcept: Bool {
        selectedConcept != nil
    }

    var hasGeneratedPreview: Bool {
        !generatedPreview.isEmpty
    }

    var isAnalyzing: Bool {
        phase.isLoading
    }

    var resolvedAnalysis: LectureCompletenessAnalysis? {
        analysis
    }

    func updateInitialAnalysis(_ initialAnalysis: LectureCompletenessAnalysis?) {
        guard analysis == nil else { return }
        analysis = initialAnalysis
        phase = Self.phase(for: initialAnalysis)
        statusMessage = initialAnalysis?.summary ?? phase.statusText
        syncSelectionIfNeeded(using: initialAnalysis)
    }

    func analyzeLecture(transcript: String, slides: String) {
        guard !phase.isLoading else { return }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSlides = slides.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty || !trimmedSlides.isEmpty else {
            phase = .empty
            statusMessage = "Add a transcript or slide notes, then run the analysis."
            selectedConcept = nil
            generatedPreview = ""
            return
        }

        let requestID = UUID()
        currentRequestID = requestID
        phase = .loading
        statusMessage = phase.statusText

        let input = LectureAnalysisInput(
            lectureTitle: noteTitle,
            noteTitle: noteTitle,
            studentNotes: studentNotes,
            sources: [
                LectureContentSource(kind: .transcript, title: "Transcript", text: trimmedTranscript),
                LectureContentSource(kind: .slides, title: "Slides", text: trimmedSlides)
            ]
        )

        DispatchQueue.global(qos: .userInitiated).async { [analyzer] in
            do {
                let result = try analyzer(input)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.currentRequestID == requestID else { return }
                    self.apply(result: result)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.currentRequestID == requestID else { return }
                    self.fail(message: error.localizedDescription.isEmpty ? "The analysis could not be completed." : error.localizedDescription)
                }
            }
        }
    }

    func retryAnalysis(transcript: String, slides: String) {
        analyzeLecture(transcript: transcript, slides: slides)
    }

    func selectConcept(_ concept: LectureCoverageItem, analysis: LectureCompletenessAnalysis?) {
        selectedConcept = concept
        generatedPreview = previewText(for: concept, mode: previewMode)
        if let analysis, selectedConcept?.id == concept.id {
            statusMessage = analysis.summary
        }
    }

    func generatePreview(for concept: LectureCoverageItem, mode: LearningInsightsPreviewMode) {
        guard !isAnalyzing else { return }
        previewMode = mode
        generatedPreview = previewText(for: concept, mode: mode)
        statusMessage = "Prepared \(mode.title.lowercased()) for \(concept.title)."
    }

    func insertGeneratedPreview() {
        guard !generatedPreview.isEmpty, !isAnalyzing else { return }
        onInsertIntoNote(generatedPreview)
        statusMessage = "Inserted the generated content into the note."
    }

    func currentPreviewIsAvailable() -> Bool {
        !generatedPreview.isEmpty
    }

    private func apply(result: LectureCompletenessAnalysis) {
        analysis = result
        phase = result.hasResults ? .ready : .empty
        statusMessage = result.hasResults ? result.summary : phase.statusText
        currentRequestID = nil
        onSaveAnalysis(result)
        syncSelectionIfNeeded(using: result)
    }

    private func fail(message: String) {
        analysis = nil
        phase = .failure(message)
        statusMessage = message
        currentRequestID = nil
        selectedConcept = nil
        generatedPreview = ""
    }

    private func syncSelectionIfNeeded(using analysis: LectureCompletenessAnalysis?) {
        guard let analysis else {
            selectedConcept = nil
            generatedPreview = ""
            return
        }

        let allItems = analysis.missingConcepts + analysis.partiallyCapturedConcepts + analysis.wellCoveredConcepts
        guard !allItems.isEmpty else {
            selectedConcept = nil
            generatedPreview = ""
            return
        }

        if let selectedConcept,
           allItems.contains(where: { $0.id == selectedConcept.id }) {
            return
        }

        selectedConcept = allItems.first
        if let selectedConcept {
            generatedPreview = previewText(for: selectedConcept, mode: previewMode)
        }
    }

    private func previewText(for concept: LectureCoverageItem, mode: LearningInsightsPreviewMode) -> String {
        switch mode {
        case .explanation:
            return [
                "Definition",
                concept.shortExplanation,
                "",
                "Why it matters",
                concept.whyItMatters,
                "",
                "What to add",
                concept.suggestedAddition,
                "",
                "Where it appears in notes",
                noteEvidence(for: concept)
            ]
            .joined(separator: "\n")
        case .flashcards:
            return [
                "Flashcard 1",
                "Front: What is \(concept.title)?",
                "Back: \(concept.shortExplanation)",
                "",
                "Flashcard 2",
                "Front: Why does \(concept.title) matter?",
                "Back: \(concept.whyItMatters)",
                "",
                "Flashcard 3",
                "Front: What should be added to the note?",
                "Back: \(concept.suggestedAddition)"
            ]
            .joined(separator: "\n")
        case .quiz:
            return [
                "Question 1",
                "Explain \(concept.title) in one or two sentences.",
                "",
                "Question 2",
                "Why is \(concept.title) important in the lecture?",
                "",
                "Question 3",
                "What detail is still missing from the notes?"
            ]
            .joined(separator: "\n")
        }
    }

    private func noteEvidence(for concept: LectureCoverageItem) -> String {
        let trimmed = studentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No note evidence yet."
        }

        let lines = trimmed.components(separatedBy: .newlines)
        if let match = lines.first(where: { $0.localizedCaseInsensitiveContains(concept.title) }) {
            return match.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let sentences = trimmed.split(whereSeparator: { ".!?".contains($0) })
        if let match = sentences.first(where: { $0.localizedCaseInsensitiveContains(concept.title) }) {
            return match.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return concept.noteSummary.isEmpty ? "The note does not directly mention this concept." : concept.noteSummary
    }

    private static func phase(for analysis: LectureCompletenessAnalysis?) -> LearningInsightsAnalysisPhase {
        guard let analysis else { return .idle }
        return analysis.hasResults ? .ready : .empty
    }
}

private struct ConceptMatch {
    var title: String
    var score: Double
    var noteEvidence: [String]
    var noteDetailScore: Double
}

private struct PhraseCandidate {
    var title: String
    var evidence: [String]
    var importance: Double
    var tokenCount: Int
    var detailScore: Double
}

private final class PhraseExtractor {
    private let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "because", "but", "by", "can",
        "could", "did", "do", "does", "for", "from", "has", "have", "if", "in",
        "into", "is", "it", "its", "of", "on", "or", "our", "the", "their", "then",
        "there", "these", "this", "those", "to", "was", "we", "were", "with", "you",
        "your", "when", "where", "which", "while", "about", "over", "under", "between"
    ]

    func extractPhrases(from text: String, preferVisualContent: Bool) -> [PhraseCandidate] {
        let lines = text.components(separatedBy: .newlines)
        var merged: [String: PhraseCandidate] = [:]

        for (lineIndex, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let prefixBoost = line.hasPrefix("•") || line.hasPrefix("-") || line.hasPrefix("*") ? 0.25 : 0
            let headingBoost = line.count <= 60 && line.split(separator: " ").count <= 8 ? 0.2 : 0
            let sourceBoost = preferVisualContent && looksVisual(line) ? 0.25 : 0
            let sentenceFragments = splitFragments(line)

            for fragment in sentenceFragments {
                let tokens = tokenize(fragment)
                let phrases = buildPhrases(from: tokens)
                for phrase in phrases {
                    let normalized = normalizeLectureText(phrase.title)
                    guard !normalized.isEmpty else { continue }

                    var candidate = merged[normalized] ?? phrase
                    candidate.importance += prefixBoost + headingBoost + sourceBoost + Double(max(0, 6 - lineIndex)) * 0.01
                    candidate.evidence.append(line)
                    candidate.importance += Double(min(3, candidate.evidence.count - 1)) * 0.08
                    merged[normalized] = candidate
                }
            }
        }

        return merged.values.sorted { $0.importance > $1.importance }
    }

    private func splitFragments(_ line: String) -> [String] {
        let rawFragments = line.components(separatedBy: CharacterSet(charactersIn: ".!?;"))
        return rawFragments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func tokenize(_ text: String) -> [String] {
        text.split { $0.isWhitespace || $0.isNewline || $0.isPunctuation }
            .map(String.init)
    }

    private func buildPhrases(from tokens: [String]) -> [PhraseCandidate] {
        var phrases: [PhraseCandidate] = []
        var current: [String] = []

        func flush() {
            guard !current.isEmpty else { return }
            let compact = compactPhrase(current)
            guard !compact.isEmpty else {
                current.removeAll(keepingCapacity: true)
                return
            }

            let importance = phraseImportance(for: current, phrase: compact)
            let detailScore = phraseDetailScore(for: current, phrase: compact)
            phrases.append(
                PhraseCandidate(
                    title: compact,
                    evidence: [],
                    importance: importance,
                    tokenCount: current.count,
                    detailScore: detailScore
                )
            )
            current.removeAll(keepingCapacity: true)
        }

        for token in tokens {
            if isConceptToken(token) {
                current.append(token)
                if current.count == 5 {
                    flush()
                }
            } else {
                flush()
            }
        }
        flush()

        if phrases.isEmpty {
            for token in tokens where isStrongSingleToken(token) {
                phrases.append(
                    PhraseCandidate(
                        title: token,
                        evidence: [],
                        importance: 0.5,
                        tokenCount: 1,
                        detailScore: 0.2
                    )
                )
            }
        }

        return phrases
    }

    private func compactPhrase(_ tokens: [String]) -> String {
        let filtered = tokens.filter { !stopWords.contains($0.lowercased()) }
        guard !filtered.isEmpty else { return "" }
        return filtered.joined(separator: " ")
    }

    private func phraseImportance(for tokens: [String], phrase: String) -> Double {
        var importance = 0.6
        if tokens.count > 1 { importance += 0.35 }
        if tokens.count > 2 { importance += 0.15 }
        if phrase.contains("-") || phrase.contains("/") { importance += 0.15 }
        if phrase.contains(where: { $0.isNumber }) { importance += 0.2 }
        if tokens.contains(where: { token in token.allSatisfy { $0.isUppercase } && token.count > 1 }) { importance += 0.2 }
        if phrase.count <= 24 { importance += 0.05 }
        return importance
    }

    private func phraseDetailScore(for tokens: [String], phrase: String) -> Double {
        var score = 0.15
        if tokens.count > 1 { score += 0.15 }
        if phrase.range(of: #"[0-9]"#, options: .regularExpression) != nil { score += 0.1 }
        if phrase.range(of: #"[A-Z][a-z]+ [A-Z][a-z]+"#, options: .regularExpression) != nil { score += 0.15 }
        if phrase.contains("-") || phrase.contains("/") { score += 0.1 }
        return min(1.0, score)
    }

    private func isConceptToken(_ token: String) -> Bool {
        let normalized = token.lowercased()
        if stopWords.contains(normalized) { return false }
        if token.count <= 2 { return token.allSatisfy { $0.isNumber } }
        if token.contains(where: { $0.isNumber }) { return true }
        if token.contains("-") || token.contains("/") || token.contains("+") { return true }
        if token.first?.isUppercase == true { return true }
        if token.allSatisfy({ $0.isUppercase }) { return true }
        return token.count >= 4
    }

    private func isStrongSingleToken(_ token: String) -> Bool {
        token.count >= 4 && !stopWords.contains(token.lowercased())
    }

    private func looksVisual(_ text: String) -> Bool {
        let normalized = normalizeLectureText(text)
        let keywords = [
            "diagram", "figure", "chart", "workflow", "architecture", "pipeline",
            "graph", "table", "flowchart", "visual", "illustration", "screenshot", "whiteboard"
        ]
        return keywords.contains(where: { normalized.contains($0) })
    }
}

private func dedupeVisualGaps(_ gaps: [LectureVisualGap]) -> [LectureVisualGap] {
    var seen = Set<String>()
    var results: [LectureVisualGap] = []

    for gap in gaps {
        let key = normalizeLectureText(gap.title)
        guard !key.isEmpty, !seen.contains(key) else { continue }
        seen.insert(key)
        results.append(gap)
    }

    return results
}

private func normalizeLectureText(_ text: String) -> String {
    text
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func tokenOverlapScore(lhs: String, rhs: String) -> Double {
    let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
    let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
    guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }

    let overlap = lhsTokens.intersection(rhsTokens)
    let union = lhsTokens.union(rhsTokens)
    return Double(overlap.count) / Double(union.count)
}

private func snippet(from text: String, maxWords: Int = 14) -> String {
    let words = text.split { $0.isWhitespace || $0.isNewline }
    guard !words.isEmpty else { return "" }
    if words.count <= maxWords {
        return words.joined(separator: " ")
    }
    return words.prefix(maxWords).joined(separator: " ") + "..."
}

private func missingDetailSnippet(from lectureText: String, against noteText: String) -> String {
    let lectureTokens = lectureText
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
    let noteTokens = Set(
        noteText
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    )

    let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "because", "but", "by", "can",
        "could", "did", "do", "does", "for", "from", "has", "have", "if", "in",
        "into", "is", "it", "its", "of", "on", "or", "our", "the", "their", "then",
        "there", "these", "this", "those", "to", "was", "we", "were", "with", "you",
        "your", "when", "where", "which", "while", "about", "over", "under", "between"
    ]

    let missing = lectureTokens.filter { !noteTokens.contains($0) && !stopWords.contains($0) }
    let unique = Array(Set(missing)).sorted { $0.count > $1.count }
    guard !unique.isEmpty else { return "" }
    return unique.prefix(4).joined(separator: " ")
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
