import Foundation

struct LearningEngineResult: Sendable {
    var knowledge: StudyKnowledgeSnapshot
    var summaryPack: StudySummaryPack
    var flashcards: [StudyFlashcard]
    var quizSet: StudyQuizSet
    var insights: StudyInsights
    var conceptMap: [StudyConceptNode]
    var activeRecallPrompts: [StudyActiveRecallPrompt]
    var knowledgeGaps: [StudyKnowledgeGap]
    var examPrep: StudyExamPrep
    var learningMemory: [StudyMemoryEntry]
    var learningInsights: LectureCompletenessAnalysis
}

@MainActor
final class LearningEngine {
    static let shared = LearningEngine()

    private let pipeline = KnowledgeExtractionPipeline.shared

    private init() {}

    func extractStructuredKnowledge(noteTitle: String, noteText: String, notebookText: String = "") async -> StructuredKnowledge {
        let structure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: noteText)
        return await extractStructuredKnowledge(from: structure, notebookText: notebookText)
    }

    func extractStructuredKnowledge(from structure: DocumentStructure, notebookText: String = "") async -> StructuredKnowledge {
        let result = await pipeline.extractKnowledge(from: structure, notebookText: notebookText)
        return result.structuredKnowledge
    }

    func extractKnowledge(noteTitle: String, noteText: String, notebookText: String = "") async -> StudyKnowledgeSnapshot {
        let structure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: noteText)
        let knowledge = await extractStructuredKnowledge(from: structure, notebookText: notebookText)
        return knowledge.legacySnapshotRepresentation()
    }

    func extractKnowledge(from structure: DocumentStructure, notebookText: String = "") async -> StudyKnowledgeSnapshot {
        let knowledge = await extractStructuredKnowledge(from: structure, notebookText: notebookText)
        return knowledge.legacySnapshotRepresentation()
    }

    func generateStudyData(
        noteTitle: String,
        noteText: String,
        notebookText: String = "",
        existingStudyData: NoteStudyData
    ) async -> NoteStudyData {
        let structure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: noteText)
        let knowledge = await extractStructuredKnowledge(from: structure, notebookText: notebookText)
        return generateStudyData(from: knowledge, existingStudyData: existingStudyData)
    }

    func generateStudyData(
        from structure: DocumentStructure,
        notebookText: String = "",
        existingStudyData: NoteStudyData
    ) async -> NoteStudyData {
        let knowledge = await extractStructuredKnowledge(from: structure, notebookText: notebookText)
        return generateStudyData(from: knowledge, existingStudyData: existingStudyData)
    }

    func generateStudyData(
        noteTitle: String,
        noteText: String,
        notebookText: String = ""
    ) async -> NoteStudyData {
        let structure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: noteText)
        return await generateStudyData(
            from: structure,
            notebookText: notebookText,
            existingStudyData: NoteStudyData()
        )
    }

    func generateStudyData(from knowledge: StructuredKnowledge, existingStudyData: NoteStudyData) -> NoteStudyData {
        var studyData = existingStudyData
        studyData.knowledgeSnapshot = knowledge.legacySnapshotRepresentation()
        studyData.knowledgeSignature = knowledge.metadata.sourceSignature
        studyData.summaryPack = generateSummaryPack(from: knowledge)
        studyData.flashcards = generateFlashcards(from: knowledge)
        studyData.quizSets = [generateQuizSet(from: knowledge)]
        studyData.insights = generateInsights(from: knowledge)
        studyData.conceptMap = generateConceptMap(from: knowledge)
        studyData.activeRecallPrompts = generateActiveRecallPrompts(from: knowledge)
        studyData.notebookKnowledgeGaps = generateKnowledgeGaps(from: knowledge)
        studyData.examPrep = generateExamPrep(from: knowledge)
        studyData.learningMemory = generateLearningMemory(from: knowledge, currentStudyData: studyData)
        studyData.learningInsights = generateLearningInsightsAnalysis(from: knowledge)
        studyData.lastGeneratedAt = Date()
        return studyData
    }

    func generateSummaryPack(from knowledge: StructuredKnowledge) -> StudySummaryPack {
        generateSummaryPack(from: knowledge.legacySnapshotRepresentation())
    }

    func generateFlashcards(from knowledge: StructuredKnowledge) -> [StudyFlashcard] {
        generateFlashcards(from: knowledge.legacySnapshotRepresentation())
    }

    func generateQuizSet(from knowledge: StructuredKnowledge) -> StudyQuizSet {
        generateQuizSet(from: knowledge.legacySnapshotRepresentation())
    }

    func generateInsights(from knowledge: StructuredKnowledge) -> StudyInsights {
        generateInsights(from: knowledge.legacySnapshotRepresentation())
    }

    func generateConceptMap(from knowledge: StructuredKnowledge) -> [StudyConceptNode] {
        guard !knowledge.relationships.isEmpty else {
            let snapshot = knowledge.legacySnapshotRepresentation()
            return generateConceptMap(from: snapshot)
        }

        let titleByID = knowledge.concepts.reduce(into: [String: String]()) { result, concept in
            result[concept.id] = concept.name
        }
        let outgoing = Dictionary(grouping: knowledge.relationships, by: \.sourceID)
        let incoming = Set(knowledge.relationships.map(\.targetID))
        let rootIDs = knowledge.concepts.map(\.id).filter { !incoming.contains($0) }

        func renderNode(id: String, visited: inout Set<String>) -> StudyConceptNode {
            let title = titleByID[id] ?? id
            guard visited.insert(id).inserted else {
                return StudyConceptNode(title: title, children: [])
            }
            let children = outgoing[id, default: []].map { relationship in
                var nextVisited = visited
                return renderNode(id: relationship.targetID, visited: &nextVisited)
            }
            return StudyConceptNode(title: title, children: children)
        }

        let rendered = rootIDs.prefix(5).map { rootID -> StudyConceptNode in
            var visited = Set<String>()
            return renderNode(id: rootID, visited: &visited)
        }

        if !rendered.isEmpty {
            return rendered
        }

        let fallbackRoots = knowledge.topics.prefix(3).map { StudyConceptNode(title: $0, children: []) }
        return fallbackRoots.isEmpty ? [StudyConceptNode(title: knowledge.title.isEmpty ? "Concept Map" : knowledge.title, children: [])] : fallbackRoots
    }

    func generateActiveRecallPrompts(from knowledge: StructuredKnowledge) -> [StudyActiveRecallPrompt] {
        generateActiveRecallPrompts(from: knowledge.legacySnapshotRepresentation())
    }

    func generateKnowledgeGaps(from knowledge: StructuredKnowledge) -> [StudyKnowledgeGap] {
        generateKnowledgeGaps(from: knowledge.legacySnapshotRepresentation())
    }

    func generateExamPrep(from knowledge: StructuredKnowledge) -> StudyExamPrep {
        generateExamPrep(from: knowledge.legacySnapshotRepresentation())
    }

    func generateLearningMemory(from knowledge: StructuredKnowledge, currentStudyData: NoteStudyData) -> [StudyMemoryEntry] {
        generateLearningMemory(from: knowledge.legacySnapshotRepresentation(), currentStudyData: currentStudyData)
    }

    func generateLearningInsightsAnalysis(from knowledge: StructuredKnowledge) -> LectureCompletenessAnalysis {
        generateLearningInsightsAnalysis(from: knowledge.legacySnapshotRepresentation())
    }

    func summaryText(from knowledge: StructuredKnowledge, mode: SummaryTab) -> String {
        summaryText(from: knowledge.legacySnapshotRepresentation(), mode: mode)
    }

    func generateSummaryPack(from knowledge: StudyKnowledgeSnapshot) -> StudySummaryPack {
        let bullets = summaryBullets(from: knowledge)
        let executive = bullets.prefix(3).joined(separator: "\n")
        let detailed = bullets.prefix(7).joined(separator: "\n")
        let exam = examRevisionParagraph(from: knowledge)
        return StudySummaryPack(
            executiveSummary: executive.isEmpty ? knowledge.cleanedText.prefix(240).description : executive,
            detailedSummary: detailed.isEmpty ? knowledge.cleanedText.prefix(600).description : detailed,
            examRevisionSummary: exam.isEmpty ? knowledge.cleanedText.prefix(360).description : exam
        )
    }

    func generateFlashcards(from knowledge: StudyKnowledgeSnapshot) -> [StudyFlashcard] {
        let items = (knowledge.concepts + knowledge.definitions + knowledge.formulas + knowledge.prerequisites + knowledge.misconceptions)
            .sorted { $0.importance > $1.importance }
            .prefix(12)
        return items.enumerated().map { index, item in
            let linkedConceptIDs = matchingConceptIDs(for: item, in: knowledge)
            return StudyFlashcard(
                type: cardType(for: item.category, index: index),
                front: item.title,
                back: item.summary,
                whyItMatters: item.evidence.first ?? item.summary,
                conceptIDs: linkedConceptIDs
            )
        }
    }

    func generateQuizSet(from knowledge: StudyKnowledgeSnapshot) -> StudyQuizSet {
        let questions = generateQuizQuestions(from: knowledge)
        return StudyQuizSet(
            title: knowledge.title.isEmpty ? "Study Quiz" : "\(knowledge.title) Quiz",
            questions: questions
        )
    }

    func generateInsights(from knowledge: StudyKnowledgeSnapshot) -> StudyInsights {
        StudyInsights(
            keyConcepts: knowledge.concepts.prefix(8).map(\.title),
            importantConcepts: (knowledge.definitions.prefix(5).map(\.title) + knowledge.formulas.prefix(3).map(\.title)),
            frequentTerms: frequencyTerms(from: knowledge),
            potentialExamTopics: knowledge.examFocus.prefix(6).map { $0 },
            knowledgeGaps: generateKnowledgeGaps(from: knowledge).prefix(6).map { $0.title }
        )
    }

    func generateConceptMap(from knowledge: StudyKnowledgeSnapshot) -> [StudyConceptNode] {
        let rootTitle = knowledge.title.isEmpty ? "Concept Map" : knowledge.title
        let primaryNodes = knowledge.topics.prefix(5).map { topic -> StudyConceptNode in
            let children = knowledge.concepts.prefix(3).map { StudyConceptNode(title: $0.title, children: []) }
            return StudyConceptNode(title: topic, children: children)
        }
        if primaryNodes.isEmpty {
            return [StudyConceptNode(title: rootTitle, children: knowledge.concepts.prefix(5).map { StudyConceptNode(title: $0.title, children: []) })]
        }
        return [StudyConceptNode(title: rootTitle, children: Array(primaryNodes))]
    }

    func generateActiveRecallPrompts(from knowledge: StudyKnowledgeSnapshot) -> [StudyActiveRecallPrompt] {
        let concepts = knowledge.concepts.prefix(8)
        return concepts.map { item in
            StudyActiveRecallPrompt(
                prompt: "Explain \(item.title) from memory.",
                answer: item.summary,
                hiddenText: item.evidence.first ?? ""
            )
        }
    }

    func generateKnowledgeGaps(from knowledge: StudyKnowledgeSnapshot) -> [StudyKnowledgeGap] {
        var gaps: [StudyKnowledgeGap] = []

        for prerequisite in knowledge.prerequisites.prefix(4) {
            gaps.append(
                StudyKnowledgeGap(
                    title: prerequisite.title,
                    description: prerequisite.summary,
                    evidence: prerequisite.evidence.first ?? prerequisite.summary,
                    priority: prerequisite.importance
                )
            )
        }

        for misconception in knowledge.misconceptions.prefix(4) {
            gaps.append(
                StudyKnowledgeGap(
                    title: misconception.title,
                    description: misconception.summary,
                    evidence: misconception.evidence.first ?? misconception.summary,
                    priority: min(1.0, misconception.importance + 0.1)
                )
            )
        }

        if gaps.isEmpty, let firstConcept = knowledge.concepts.first {
            gaps.append(
                StudyKnowledgeGap(
                    title: firstConcept.title,
                    description: "This concept should be reviewed carefully.",
                    evidence: firstConcept.evidence.first ?? firstConcept.summary,
                    priority: firstConcept.importance
                )
            )
        }

        return gaps.sorted { $0.priority > $1.priority }
    }

    func generateExamPrep(from knowledge: StudyKnowledgeSnapshot) -> StudyExamPrep {
        let difficult = (knowledge.formulas + knowledge.misconceptions + knowledge.prerequisites)
            .sorted { $0.difficulty > $1.difficulty }
            .prefix(6)
            .map { $0.title }

        return StudyExamPrep(
            likelyTopics: knowledge.examFocus.prefix(8).map { $0 },
            condensedRevisionGuide: examRevisionParagraph(from: knowledge),
            practiceQuestions: generateQuizQuestions(from: knowledge).prefix(5).map { $0 },
            difficultConcepts: difficult
        )
    }

    func generateLearningMemory(from knowledge: StudyKnowledgeSnapshot, currentStudyData: NoteStudyData) -> [StudyMemoryEntry] {
        let candidates = (knowledge.concepts + knowledge.definitions + knowledge.formulas)
            .prefix(16)
            .map { $0.title }
        let current = currentStudyData.learningMemory
        let existingByKey = current.reduce(into: [String: StudyMemoryEntry]()) { result, entry in
            let key = normalizedConceptKey(entry.concept)
            if result[key] == nil {
                result[key] = entry
            }
        }

        return candidates.map { candidate in
            if let existing = existingByKey[normalizedConceptKey(candidate)] {
                return existing
            }
            return StudyMemoryEntry(concept: candidate)
        }
    }

    func generateLearningInsightsAnalysis(from knowledge: StudyKnowledgeSnapshot) -> LectureCompletenessAnalysis {
        let conceptCount = knowledge.concepts.count
        let noteCount = max(1, knowledge.summaryHighlights.count)
        let coverage = min(1.0, Double(conceptCount) / Double(max(1, knowledge.topics.count + conceptCount)))
        let summary = knowledge.summaryHighlights.isEmpty
            ? "\(conceptCount) concepts identified for study."
            : knowledge.summaryHighlights.prefix(3).joined(separator: " ")

        let covered = knowledge.concepts.prefix(4).enumerated().map { index, item in
            coverageItem(index: index, item: item, state: .covered, noteSummary: knowledge.cleanedText)
        }

        let partial = knowledge.definitions.prefix(4).enumerated().map { index, item in
            coverageItem(index: index, item: item, state: .partial, noteSummary: knowledge.cleanedText)
        }

        let missing = knowledge.prerequisites.prefix(4).enumerated().map { index, item in
            coverageItem(index: index, item: item, state: .missing, noteSummary: knowledge.cleanedText)
        }

        return LectureCompletenessAnalysis(
            completenessScore: coverage,
            lectureConceptCount: conceptCount,
            noteConceptCount: noteCount,
            missingConcepts: missing,
            partiallyCapturedConcepts: partial,
            wellCoveredConcepts: covered,
            missingVisualContent: [],
            reviewPriority: [],
            summary: summary,
            generatedAt: Date()
        )
    }

    func summaryText(from knowledge: StudyKnowledgeSnapshot, mode: SummaryTab) -> String {
        let pack = generateSummaryPack(from: knowledge)
        switch mode {
        case .thirtySeconds:
            return pack.executiveSummary
        case .twoMinutes:
            return pack.detailedSummary
        case .exam:
            return pack.examRevisionSummary
        }
    }

    private func generateQuizQuestions(from knowledge: StudyKnowledgeSnapshot) -> [StudyQuizQuestion] {
        let candidates = (knowledge.concepts + knowledge.definitions + knowledge.prerequisites + knowledge.formulas)
            .sorted { $0.importance > $1.importance }
            .prefix(8)

        return candidates.enumerated().map { index, item in
            let linkedConceptIDs = matchingConceptIDs(for: item, in: knowledge)
            let distractors = Array(knowledge.concepts.map(\.title).filter { $0 != item.title }.prefix(3))
            let options = ([item.summary] + distractors).prefix(4).map { $0 }
            return StudyQuizQuestion(
                type: index % 2 == 0 ? .multipleChoice : .shortAnswer,
                prompt: "What should you know about \(item.title)?",
                options: options,
                correctAnswer: item.summary,
                explanation: item.evidence.first ?? item.summary,
                keywords: [item.title],
                conceptIDs: linkedConceptIDs
            )
        }
    }

    private func summaryBullets(from knowledge: StudyKnowledgeSnapshot) -> [String] {
        var bullets: [String] = []
        if !knowledge.topics.isEmpty {
            bullets.append("Topics: \(knowledge.topics.prefix(4).joined(separator: ", "))")
        }
        for item in knowledge.concepts.prefix(4) {
            bullets.append("• \(item.title): \(item.summary)")
        }
        for item in knowledge.formulas.prefix(2) {
            bullets.append("• Formula: \(item.title) - \(item.summary)")
        }
        return bullets
    }

    private func examRevisionParagraph(from knowledge: StudyKnowledgeSnapshot) -> String {
        let focus = knowledge.examFocus.prefix(6).joined(separator: ", ")
        let gaps = knowledge.prerequisites.prefix(3).map { $0.title }.joined(separator: ", ")
        let terms = knowledge.keyTerms.prefix(5).map { $0.title }.joined(separator: ", ")
        return [
            focus.isEmpty ? nil : "Likely exam focus: \(focus).",
            terms.isEmpty ? nil : "Key terms: \(terms).",
            gaps.isEmpty ? nil : "Review prerequisites: \(gaps)."
        ].compactMap { $0 }.joined(separator: " ")
    }

    private func cardType(for category: String, index: Int) -> StudyCardType {
        switch category {
        case "formula":
            return .questionAnswer
        case "misconception":
            return .questionAnswer
        case "definition":
            return .definition
        default:
            return index % 2 == 0 ? .concept : .cloze
        }
    }

    private func frequencyTerms(from knowledge: StudyKnowledgeSnapshot) -> [StudyTerm] {
        let counts = knowledge.cleanedText
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .reduce(into: [:]) { counts, word in counts[word, default: 0] += 1 }

        return counts
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { StudyTerm(term: $0.key, count: $0.value) }
    }

    private func normalizedConceptKey(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func matchingConceptIDs(for item: StudyKnowledgeItem, in knowledge: StudyKnowledgeSnapshot) -> [String] {
        let normalizedItemTitle = normalizedConceptKey(item.title)
        let matchedTitles = knowledge.concepts.compactMap { concept -> String? in
            let normalizedConceptTitle = normalizedConceptKey(concept.title)
            let aliases = concept.aliases.map(normalizedConceptKey)
            if normalizedItemTitle == normalizedConceptTitle || aliases.contains(normalizedItemTitle) {
                return concept.title
            }
            if !item.relatedTitles.isEmpty && item.relatedTitles.contains(where: { normalizedConceptKey($0) == normalizedConceptTitle }) {
                return concept.title
            }
            return nil
        }

        if matchedTitles.isEmpty {
            return [item.title]
        }

        return Array(Set(matchedTitles)).sorted()
    }

    private func coverageItem(index: Int, item: StudyKnowledgeItem, state: LectureCoverageState, noteSummary: String) -> LectureCoverageItem {
        LectureCoverageItem(
            title: item.title,
            state: state,
            whatWasMissed: item.summary,
            whyItMatters: item.evidence.first ?? item.summary,
            shortExplanation: item.summary,
            suggestedAddition: item.summary,
            importance: item.importance,
            evidence: item.evidence,
            matchScore: state == .covered ? item.importance : item.importance * 0.7,
            noteSummary: noteSummary
        )
    }
}
