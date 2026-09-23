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
        let graphAwareKnowledge = graphAwareSnapshot(from: knowledge, currentStudyData: studyData)
        studyData.knowledgeSnapshot = graphAwareKnowledge
        studyData.knowledgeSignature = knowledge.metadata.sourceSignature
        studyData.summaryPack = generateSummaryPack(from: graphAwareKnowledge)
        studyData.flashcards = generateFlashcards(from: graphAwareKnowledge)
        studyData.quizSets = [generateQuizSet(from: graphAwareKnowledge)]
        studyData.insights = generateInsights(from: graphAwareKnowledge)
        studyData.conceptMap = generateConceptMap(from: knowledge)
        studyData.activeRecallPrompts = generateActiveRecallPrompts(from: graphAwareKnowledge)
        studyData.notebookKnowledgeGaps = generateKnowledgeGaps(from: graphAwareKnowledge)
        studyData.examPrep = generateExamPrep(from: graphAwareKnowledge)
        studyData.learningMemory = generateLearningMemory(from: graphAwareKnowledge, currentStudyData: studyData)
        studyData.learningInsights = generateLearningInsightsAnalysis(from: graphAwareKnowledge)
        studyData.lastGeneratedAt = Date()
        return studyData
    }

    func generateSummaryPack(from knowledge: StructuredKnowledge) -> StudySummaryPack {
        generateSummaryPack(from: graphAwareSnapshot(from: knowledge, currentStudyData: NoteStudyData()))
    }

    func generateFlashcards(from knowledge: StructuredKnowledge) -> [StudyFlashcard] {
        generateFlashcards(from: graphAwareSnapshot(from: knowledge, currentStudyData: NoteStudyData()))
    }

    func generateQuizSet(from knowledge: StructuredKnowledge) -> StudyQuizSet {
        generateQuizSet(from: graphAwareSnapshot(from: knowledge, currentStudyData: NoteStudyData()))
    }

    func generateInsights(from knowledge: StructuredKnowledge) -> StudyInsights {
        generateInsights(from: graphAwareSnapshot(from: knowledge, currentStudyData: NoteStudyData()))
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
        generateActiveRecallPrompts(from: graphAwareSnapshot(from: knowledge, currentStudyData: NoteStudyData()))
    }

    func generateKnowledgeGaps(from knowledge: StructuredKnowledge) -> [StudyKnowledgeGap] {
        generateKnowledgeGaps(from: graphAwareSnapshot(from: knowledge, currentStudyData: NoteStudyData()))
    }

    func generateExamPrep(from knowledge: StructuredKnowledge) -> StudyExamPrep {
        generateExamPrep(from: graphAwareSnapshot(from: knowledge, currentStudyData: NoteStudyData()))
    }

    func generateLearningMemory(from knowledge: StructuredKnowledge, currentStudyData: NoteStudyData) -> [StudyMemoryEntry] {
        generateLearningMemory(from: graphAwareSnapshot(from: knowledge, currentStudyData: currentStudyData), currentStudyData: currentStudyData)
    }

    func generateLearningInsightsAnalysis(from knowledge: StructuredKnowledge) -> LectureCompletenessAnalysis {
        generateLearningInsightsAnalysis(from: graphAwareSnapshot(from: knowledge, currentStudyData: NoteStudyData()))
    }

    func summaryText(from knowledge: StructuredKnowledge, mode: SummaryTab) -> String {
        summaryText(from: graphAwareSnapshot(from: knowledge, currentStudyData: NoteStudyData()), mode: mode)
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
        let relationshipCards = graphRelationshipFlashcards(from: knowledge)
        let items = (knowledge.concepts + knowledge.definitions + knowledge.formulas + knowledge.prerequisites + knowledge.misconceptions)
            .sorted { $0.importance > $1.importance }
            .prefix(12)
        let conceptCards = items.enumerated().map { index, item in
            let linkedConceptIDs = matchingConceptIDs(for: item, in: knowledge)
            return StudyFlashcard(
                type: cardType(for: item.category, index: index),
                front: item.title,
                back: item.summary,
                whyItMatters: item.evidence.first ?? item.summary,
                conceptIDs: linkedConceptIDs
            )
        }
        return Array((conceptCards + relationshipCards).prefix(12))
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
            importantConcepts: (knowledge.prerequisites.prefix(3).map(\.title) + knowledge.definitions.prefix(5).map(\.title) + knowledge.formulas.prefix(3).map(\.title)),
            frequentTerms: frequencyTerms(from: knowledge),
            potentialExamTopics: (knowledge.examFocus + knowledge.concepts.prefix(6).map(\.title)).prefix(6).map { $0 },
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
            likelyTopics: (knowledge.examFocus + knowledge.concepts.prefix(8).map(\.title)).prefix(8).map { $0 },
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
        let reviewPriority = (knowledge.prerequisites + knowledge.concepts)
            .prefix(8)
            .enumerated()
            .map { index, item in
                LectureReviewPriorityItem(
                    rank: index + 1,
                    title: item.title,
                    reason: item.category == "prerequisite"
                        ? "Review this prerequisite before dependent concepts."
                        : "Review this graph-connected concept to strengthen dependent topics.",
                    state: item.category == "prerequisite" ? .missing : .partial,
                    importance: item.importance
                )
            }

        return LectureCompletenessAnalysis(
            completenessScore: coverage,
            lectureConceptCount: conceptCount,
            noteConceptCount: noteCount,
            missingConcepts: missing,
            partiallyCapturedConcepts: partial,
            wellCoveredConcepts: covered,
            missingVisualContent: [],
            reviewPriority: reviewPriority,
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
        let relationshipQuestions = graphRelationshipQuizQuestions(from: knowledge)
        let candidates = (knowledge.concepts + knowledge.definitions + knowledge.prerequisites + knowledge.formulas)
            .sorted { $0.importance > $1.importance }
            .prefix(max(0, 8 - relationshipQuestions.count))

        let conceptQuestions = candidates.enumerated().map { index, item in
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
        return Array((relationshipQuestions + conceptQuestions).prefix(8))
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
        let learningOrder = prerequisiteLearningOrder(from: knowledge).prefix(6).joined(separator: " -> ")
        return [
            focus.isEmpty ? nil : "Likely exam focus: \(focus).",
            terms.isEmpty ? nil : "Key terms: \(terms).",
            gaps.isEmpty ? nil : "Review prerequisites: \(gaps).",
            learningOrder.isEmpty ? nil : "Recommended learning order: \(learningOrder)."
        ].compactMap { $0 }.joined(separator: " ")
    }

    private func graphRelationshipFlashcards(from knowledge: StudyKnowledgeSnapshot) -> [StudyFlashcard] {
        knowledge.relationships
            .filter { $0.sourceTitle.isEmpty == false && $0.targetTitle.isEmpty == false }
            .prefix(4)
            .map { relationship in
                StudyFlashcard(
                    type: .questionAnswer,
                    front: relationshipQuestionPrompt(for: relationship),
                    back: relationship.targetTitle,
                    whyItMatters: "\(relationship.sourceTitle) \(relationship.relation) \(relationship.targetTitle).",
                    conceptIDs: [relationship.sourceTitle, relationship.targetTitle]
                )
            }
    }

    private func graphRelationshipQuizQuestions(from knowledge: StudyKnowledgeSnapshot) -> [StudyQuizQuestion] {
        knowledge.relationships
            .filter { $0.sourceTitle.isEmpty == false && $0.targetTitle.isEmpty == false }
            .prefix(3)
            .map { relationship in
                let distractors = knowledge.concepts
                    .map(\.title)
                    .filter { $0 != relationship.targetTitle && $0 != relationship.sourceTitle }
                    .prefix(3)
                return StudyQuizQuestion(
                    type: .shortAnswer,
                    prompt: relationshipQuestionPrompt(for: relationship),
                    options: Array(([relationship.targetTitle] + distractors).prefix(4)),
                    correctAnswer: relationship.targetTitle,
                    explanation: "\(relationship.sourceTitle) \(relationship.relation) \(relationship.targetTitle).",
                    keywords: [relationship.sourceTitle, relationship.targetTitle],
                    conceptIDs: [relationship.sourceTitle, relationship.targetTitle]
                )
            }
    }

    private func relationshipQuestionPrompt(for relationship: StudyKnowledgeRelationship) -> String {
        let relation = relationship.relation.lowercased()
        if relation.contains("produce") {
            return "What concept produces \(relationship.sourceTitle)?"
        }
        if relation.contains("require") || relation.contains("depend") || relation.contains("prereq") {
            return "What prerequisite supports \(relationship.sourceTitle)?"
        }
        if relation.contains("part") || relation.contains("is_a") || relation.contains("isa") {
            return "What is \(relationship.sourceTitle) connected to in the concept graph?"
        }
        return "How is \(relationship.sourceTitle) related in the concept graph?"
    }

    private func prerequisiteLearningOrder(from knowledge: StudyKnowledgeSnapshot) -> [String] {
        let prerequisiteTitles = knowledge.prerequisites.map(\.title)
        let dependentTitles = knowledge.relationships
            .filter { relationship in
                let relation = relationship.relation.lowercased()
                return relation.contains("require") || relation.contains("depend") || relation.contains("prereq")
            }
            .map(\.sourceTitle)
        return (prerequisiteTitles + dependentTitles).filter { $0.isEmpty == false }.dedupeLearningOrder()
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

    private func graphAwareSnapshot(from knowledge: StructuredKnowledge, currentStudyData: NoteStudyData) -> StudyKnowledgeSnapshot {
        var snapshot = knowledge.legacySnapshotRepresentation()
        guard !knowledge.concepts.isEmpty else { return snapshot }

        let conceptByID = Dictionary(knowledge.concepts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let titleByID = Dictionary(knowledge.concepts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let idByNormalizedTitle = Dictionary(knowledge.concepts.map { (normalizedConceptKey($0.name), $0.id) }, uniquingKeysWith: { first, _ in first })
        let memoryByKey = currentStudyData.learningMemory.reduce(into: [String: StudyMemoryEntry]()) { result, entry in
            result[normalizedConceptKey(entry.concept)] = entry
        }

        let prerequisiteEdges = knowledge.relationships.filter { relationship in
            isPrerequisiteRelationship(relationship)
                && conceptByID[relationship.sourceID] != nil
                && conceptByID[relationship.targetID] != nil
        }
        let dependenciesByConceptID = Dictionary(grouping: prerequisiteEdges, by: \.sourceID)
        let dependentsByConceptID = Dictionary(grouping: prerequisiteEdges, by: \.targetID)
        let edgeCountByID = knowledge.relationships.reduce(into: [String: Int]()) { result, relationship in
            result[relationship.sourceID, default: 0] += 1
            result[relationship.targetID, default: 0] += 1
        }

        var orderedIDs: [String] = []
        var visiting: Set<String> = []
        var visited: Set<String> = []

        func visit(_ conceptID: String) {
            guard !visited.contains(conceptID), !visiting.contains(conceptID) else { return }
            visiting.insert(conceptID)
            for dependency in dependenciesByConceptID[conceptID, default: []] {
                visit(dependency.targetID)
            }
            visiting.remove(conceptID)
            visited.insert(conceptID)
            orderedIDs.append(conceptID)
        }

        knowledge.concepts
            .sorted { $0.importance > $1.importance }
            .forEach { visit($0.id) }

        let rankByID = Dictionary(orderedIDs.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        snapshot.concepts = snapshot.concepts.map { item in
            guard let conceptID = idByNormalizedTitle[normalizedConceptKey(item.title)] else { return item }
            var adjusted = item
            let centralityBoost = min(0.18, Double(edgeCountByID[conceptID, default: 0]) * 0.03)
            let dependentPenalty = dependenciesByConceptID[conceptID, default: []].contains { edge in
                masteryScore(for: titleByID[edge.targetID] ?? edge.targetID, memoryByKey: memoryByKey) < 0.5
            } ? 0.18 : 0
            let prerequisiteBoost = !dependentsByConceptID[conceptID, default: []].isEmpty
                && masteryScore(for: titleByID[conceptID] ?? conceptID, memoryByKey: memoryByKey) < 0.65
                ? 0.14
                : 0
            adjusted.importance = min(1.0, max(0.0, adjusted.importance + centralityBoost + prerequisiteBoost - dependentPenalty))
            adjusted.relatedTitles = Array(Set(
                knowledge.relationships.compactMap { relationship -> String? in
                    if relationship.sourceID == conceptID { return titleByID[relationship.targetID] }
                    if relationship.targetID == conceptID { return titleByID[relationship.sourceID] }
                    return nil
                }
            )).sorted()
            return adjusted
        }.sorted {
            let leftRank = idByNormalizedTitle[normalizedConceptKey($0.title)].flatMap { rankByID[$0] } ?? Int.max
            let rightRank = idByNormalizedTitle[normalizedConceptKey($1.title)].flatMap { rankByID[$0] } ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return $0.importance > $1.importance
        }

        let existingPrerequisiteKeys = Set(snapshot.prerequisites.map { normalizedConceptKey($0.title) })
        let propagatedPrerequisites = prerequisiteEdges.compactMap { edge -> StudyKnowledgeItem? in
            guard let prerequisite = conceptByID[edge.targetID],
                  !existingPrerequisiteKeys.contains(normalizedConceptKey(prerequisite.name))
            else { return nil }

            let mastery = masteryScore(for: prerequisite.name, memoryByKey: memoryByKey)
            guard mastery < 0.65 else { return nil }
            return StudyKnowledgeItem(
                title: prerequisite.name,
                summary: "\(prerequisite.name) supports dependent concepts such as \(titleByID[edge.sourceID] ?? edge.sourceID).",
                evidence: prerequisite.examples.isEmpty ? prerequisite.sourceLocations.map(\.snippet).filter { !$0.isEmpty } : prerequisite.examples,
                importance: min(1.0, prerequisite.importance + (1.0 - mastery) * 0.25),
                difficulty: max(prerequisite.difficulty, 1.0 - mastery),
                aliases: prerequisite.aliases,
                relatedTitles: [titleByID[edge.sourceID] ?? edge.sourceID],
                category: "prerequisite"
            )
        }

        snapshot.prerequisites = (propagatedPrerequisites + snapshot.prerequisites)
            .sorted { $0.importance > $1.importance }
        snapshot.examFocus = Array(Set(snapshot.examFocus + snapshot.concepts.prefix(6).map(\.title))).sorted { left, right in
            let leftRank = snapshot.concepts.firstIndex(where: { $0.title == left }) ?? Int.max
            let rightRank = snapshot.concepts.firstIndex(where: { $0.title == right }) ?? Int.max
            return leftRank < rightRank
        }
        return snapshot
    }

    private func isPrerequisiteRelationship(_ relationship: KnowledgeRelationship) -> Bool {
        let relation = relationship.relation.lowercased()
        return relationship.relationKind == .requires
            || relation.contains("require")
            || relation.contains("depend")
            || relation.contains("prereq")
    }

    private func masteryScore(for conceptTitle: String, memoryByKey: [String: StudyMemoryEntry]) -> Double {
        memoryByKey[normalizedConceptKey(conceptTitle)]?.masteryScore ?? 0.5
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

private extension Array where Element == String {
    func dedupeLearningOrder() -> [String] {
        var seen: Set<String> = []
        return filter { value in
            let key = value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.isEmpty == false }
                .joined(separator: " ")
            return seen.insert(key).inserted
        }
    }
}
