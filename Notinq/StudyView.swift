import SwiftUI
import Foundation
import NaturalLanguage
import AppKit

enum StudyWorkspaceSection: String, CaseIterable, Identifiable {
    case learningInsights = "Learning Insights"
    case summary = "Summary"
    case keyConcepts = "Key Concepts"
    case conceptMap = "Concept Map"
    case flashcards = "Flashcards"
    case quizzes = "Quizzes"
    case learningMemory = "Learning Memory"
    case knowledgeGaps = "Knowledge Gaps"
    case testMe = "Test Me"
    case insights = "Insights"
    case progress = "Progress"

    var id: String { rawValue }
}

enum StudyFlashcardFace: Equatable {
    case front
    case back
}

private extension StudyView {
    var headerActionTitle: String {
        selectedTool.actionLabel
    }

    var noteContentSource: String {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return selected.isEmpty ? noteText.trimmingCharacters(in: .whitespacesAndNewlines) : selected
    }

    var activeDocumentStructure: DocumentStructure {
        DocumentPreprocessor.shared.preprocess(title: noteLabel, text: noteContentSource)
    }

    var notebookNoteTexts: [String] {
        appState.folders.flatMap { folder in
            folder.notes.map { $0.content }
        }
    }

    var notebookCombinedText: String {
        notebookNoteTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    func generate(for tool: StudyTool) {
        guard noteID != nil else {
            transientStatusMessage = "Select a note before generating study material."
            return
        }

        selectedTool = tool

        switch tool {
        case .learningInsights:
            generateLearningInsights()
        case .flashcards:
            generateFlashcards()
        case .quizGenerator:
            generateQuizSet()
        case .summaryGenerator:
            generateSummary()
        case .keyConcepts:
            generateKeyConcepts()
        }
    }

    func generateAllStudyMaterials() {
        guard noteID != nil else {
            transientStatusMessage = "Select a note before generating study material."
            return
        }

        generateLearningInsights()
        generateFlashcards()
        generateQuizSet()
        generateSummary()
        generateKeyConcepts()
        transientStatusMessage = "Generated study materials for \(noteLabel)."
    }

    func generateLearningInsights() {
        guard let noteID else { return }
        let structure = activeDocumentStructure
        guard !structure.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            transientStatusMessage = "Add some note content first."
            return
        }

        let currentStudyData = studyData
        Task {
            let generated = await AIService.shared.generateStudyData(
                from: structure,
                notebookText: notebookCombinedText,
                existingStudyData: currentStudyData
            )
            await MainActor.run {
                appState.updateStudyData(generated, for: noteID)
                let analysis = generated.learningInsights
                appState.updateLearningInsights(analysis, for: noteID)
                let artifact = buildArtifact(
                    kind: .learningInsights,
                    title: "Learning Insights",
                    content: learningInsightsText(from: analysis),
                    sections: learningInsightsSections(from: analysis)
                )
                storeArtifact(artifact)
                persistStudySession(notesReviewed: 1)
                transientStatusMessage = "Learning Insights updated for \(noteLabel)."
            }
        }
    }

    func generateFlashcards() {
        guard let noteID else { return }
        let structure = activeDocumentStructure
        guard !structure.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            transientStatusMessage = "Add some note content first."
            return
        }

        let currentStudyData = studyData
        Task {
            let generated = await AIService.shared.generateStudyData(
                from: structure,
                notebookText: notebookCombinedText,
                existingStudyData: currentStudyData
            )
            await MainActor.run {
                appState.updateStudyData(generated, for: noteID)
                let cards = generated.flashcards
                let artifact = buildArtifact(
                    kind: .flashcards,
                    title: "Flashcards",
                    content: flashcardSetText(from: cards),
                    sections: flashcardSections(from: cards)
                )
                storeArtifact(artifact)
                resetFlashcardSession()
                persistStudySession(notesReviewed: 1)
                transientStatusMessage = cards.isEmpty ? "No flashcards could be generated." : "Generated \(cards.count) flashcards."
            }
        }
    }

    func generateSelectedStudyItem(_ action: StudyQuestionGenerationAction) {
        guard let noteID else { return }
        let source = selectedStudyQuestionSource(noteID: noteID)
        guard !source.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            transientStatusMessage = "Select or add note content first."
            return
        }

        Task {
            let output = await StudyQuestionGenerationEngine().generate(action: action, source: source)
            await MainActor.run {
                persistGeneratedStudyItem(output, action: action, noteID: noteID)
            }
        }
    }

    func selectedStudyQuestionSource(noteID: UUID) -> StudyQuestionGenerationSource {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = selected.isEmpty ? noteContentSource : selected
        let range = selected.isEmpty
            ? NSRange(location: 0, length: (sourceText as NSString).length)
            : NSRange(location: 0, length: (selected as NSString).length)
        return StudyQuestionGenerationSource(
            noteID: noteID,
            selectedText: sourceText,
            noteContext: noteText,
            sourceRange: range
        )
    }

    func persistGeneratedStudyItem(_ output: StudyQuestionGenerationOutput, action: StudyQuestionGenerationAction, noteID: UUID) {
        let recorder = LearningSignalRecorder()
        mutateStudyData { studyData in
            if let flashcard = output.flashcard {
                studyData.flashcards.insert(flashcard, at: 0)
                updateStreaks(&studyData, notesReviewed: 0, flashcardsCompleted: 0, quizzesCompleted: 0)
                recorder.recordStudyFlashcardGenerated(flashcard: flashcard, noteID: noteID)
                flashcardIndex = 0
                isFlashcardFlipped = false
            }

            if let question = output.question {
                let generatedSetTitle = "Generated Questions"
                if let index = studyData.quizSets.firstIndex(where: { $0.title == generatedSetTitle }) {
                    studyData.quizSets[index].questions.insert(question, at: 0)
                } else {
                    studyData.quizSets.insert(
                        StudyQuizSet(title: generatedSetTitle, questions: [question]),
                        at: 0
                    )
                }
                updateStreaks(&studyData, notesReviewed: 0, flashcardsCompleted: 0, quizzesCompleted: 0)
                recorder.recordStudyQuestionGenerated(question: question, noteID: noteID)
                generatedQuestionDraftAnswer = ""
                isGeneratedQuestionAnswerRevealed = false
            }
        }

        transientStatusMessage = "\(action.title) saved to study materials."
        focusStudyTool(action == .generateFlashcard ? .flashcards : .quizGenerator)
    }

    func generateQuizSet() {
        guard let noteID else { return }
        let structure = activeDocumentStructure
        guard !structure.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            transientStatusMessage = "Add some note content first."
            return
        }

        let currentStudyData = studyData
        Task {
            let generated = await AIService.shared.generateStudyData(
                from: structure,
                notebookText: notebookCombinedText,
                existingStudyData: currentStudyData
            )
            await MainActor.run {
                appState.updateStudyData(generated, for: noteID)
                let quizSet = generated.quizSets.first ?? buildQuizSet(from: structure.normalizedText)
                let artifact = buildArtifact(
                    kind: .quizGenerator,
                    title: quizSet.title,
                    content: quizSetText(from: quizSet),
                    sections: quizSections(from: quizSet)
                )
                storeArtifact(artifact)
                persistStudySession(notesReviewed: 1)
                transientStatusMessage = "Generated a quiz set with \(quizSet.questions.count) questions."
            }
        }
    }

    func generateSummary() {
        guard let noteID else { return }
        let structure = activeDocumentStructure
        guard !structure.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            transientStatusMessage = "Add some note content first."
            return
        }

        let currentStudyData = studyData
        Task {
            let generated = await AIService.shared.generateStudyData(
                from: structure,
                notebookText: notebookCombinedText,
                existingStudyData: currentStudyData
            )
            await MainActor.run {
                appState.updateStudyData(generated, for: noteID)
                let summaryPack = generated.summaryPack
                let artifact = buildArtifact(
                    kind: .summaryGenerator,
                    title: "Summary Generator",
                    content: summaryText(for: summaryPack, mode: selectedSummaryMode),
                    sections: summarySections(from: summaryPack)
                )
                storeArtifact(artifact)
                persistStudySession(notesReviewed: 1)
                transientStatusMessage = "Summary generated from the active note."
            }
        }
    }

    func generateKeyConcepts() {
        guard let noteID else { return }
        let structure = activeDocumentStructure
        guard !structure.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            transientStatusMessage = "Add some note content first."
            return
        }

        let currentStudyData = studyData
        Task {
            let generated = await AIService.shared.generateStudyData(
                from: structure,
                notebookText: notebookCombinedText,
                existingStudyData: currentStudyData
            )
            await MainActor.run {
                appState.updateStudyData(generated, for: noteID)
                let concepts = generated.insights
                let artifact = buildArtifact(
                    kind: .keyConcepts,
                    title: "Key Concepts",
                    content: keyConceptsText(from: concepts),
                    sections: keyConceptSections(from: concepts)
                )
                storeArtifact(artifact)
                persistStudySession(notesReviewed: 1)
                transientStatusMessage = "Extracted key concepts and relationships."
            }
        }
    }

    func openKnowledgeExtractionDebugger() {
        let structure = activeDocumentStructure
        guard !structure.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            transientStatusMessage = "Add some note content first."
            return
        }

        Task {
            let report = await AIService.shared.inspectKnowledgeExtraction(
                from: structure,
                notebookText: notebookCombinedText
            )
            await MainActor.run {
                knowledgeExtractionDebuggerReport = report
                isShowingKnowledgeExtractionDebugger = true
                transientStatusMessage = "Opened knowledge extraction debugger."
            }
        }
    }

    func generateExamPrep() {
        guard let noteID else { return }
        let structure = activeDocumentStructure
        guard !structure.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            transientStatusMessage = "Add some note content first."
            return
        }

        let currentStudyData = studyData
        Task {
            let generated = await AIService.shared.generateStudyData(
                from: structure,
                notebookText: notebookCombinedText,
                existingStudyData: currentStudyData
            )
            await MainActor.run {
                appState.updateStudyData(generated, for: noteID)
                let prep = generated.examPrep
                let artifact = buildArtifact(
                    kind: .examPrep,
                    title: "Exam Prep",
                    content: examPrepText(from: prep),
                    sections: examPrepSections(from: prep)
                )
                storeArtifact(artifact)
                persistStudySession(notesReviewed: 1)
                transientStatusMessage = "Exam prep generated from the active note."
            }
        }
    }

    func generateConceptMap() {
        guard let noteID else { return }
        let structure = activeDocumentStructure
        guard !structure.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let currentStudyData = studyData
        Task {
            let generated = await AIService.shared.generateStudyData(
                from: structure,
                notebookText: notebookCombinedText,
                existingStudyData: currentStudyData
            )
            await MainActor.run {
                appState.updateStudyData(generated, for: noteID)
                let map = generated.conceptMap
                let artifact = buildArtifact(
                    kind: .conceptMap,
                    title: "Concept Map",
                    content: conceptMapText(from: map),
                    sections: conceptMapSections(from: map)
                )
                storeArtifact(artifact)
            }
        }
    }

    func generateActiveRecallPrompts() {
        guard let noteID else { return }
        let structure = activeDocumentStructure
        guard !structure.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let currentStudyData = studyData
        Task {
            let generated = await AIService.shared.generateStudyData(
                from: structure,
                notebookText: notebookCombinedText,
                existingStudyData: currentStudyData
            )
            await MainActor.run {
                appState.updateStudyData(generated, for: noteID)
                let prompts = generated.activeRecallPrompts
                let artifact = buildArtifact(
                    kind: .activeRecall,
                    title: "Active Recall",
                    content: activeRecallText(from: prompts),
                    sections: activeRecallSections(from: prompts)
                )
                storeArtifact(artifact)
                activeRecallIndex = 0
                isActiveRecallAnswerRevealed = false
            }
        }
    }

    func generateNotebookKnowledgeGaps() {
        guard let noteID else { return }
        let structure = activeDocumentStructure
        guard !structure.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let currentStudyData = studyData
        Task {
            let generated = await AIService.shared.generateStudyData(
                from: structure,
                notebookText: notebookCombinedText,
                existingStudyData: currentStudyData
            )
            await MainActor.run {
                var mergedStudyData = generated
                let gaps = StudyKnowledgeGap.merge(existing: currentStudyData.notebookKnowledgeGaps, detected: generated.notebookKnowledgeGaps)
                mergedStudyData.notebookKnowledgeGaps = gaps
                appState.updateStudyData(mergedStudyData, for: noteID)
                for gap in gaps where gap.status == .active {
                    ResearchInstrumentationService.shared.recordKnowledgeGapDetected(
                        concept: gap.title,
                        heuristic: gap.detectionHeuristic,
                        noteID: noteID
                    )
                }
                let artifact = buildArtifact(
                    kind: .notebookKnowledgeGaps,
                    title: "Knowledge Gaps",
                    content: notebookGapsText(from: gaps),
                    sections: notebookGapSections(from: gaps)
                )
                storeArtifact(artifact)
            }
        }
    }

    func generateLearningMemory() {
        guard let noteID else { return }
        let structure = activeDocumentStructure
        guard !structure.normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let currentStudyData = studyData
        Task {
            let generated = await AIService.shared.generateStudyData(
                from: structure,
                notebookText: notebookCombinedText,
                existingStudyData: currentStudyData
            )
            await MainActor.run {
                appState.updateStudyData(generated, for: noteID)
                let rebuiltMemory = generated.learningMemory
                let artifact = buildArtifact(
                    kind: .learningMemory,
                    title: "Learning Memory",
                    content: learningMemoryText(from: rebuiltMemory),
                    sections: learningMemorySections(from: rebuiltMemory)
                )
                storeArtifact(artifact)
                persistStudySession(notesReviewed: 1)
            }
        }
    }

    func saveGeneratedContent(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        transientStatusMessage = "Saved in local study memory."
    }

    func exportFlashcardSet() {
        guard !studyData.flashcards.isEmpty else {
            transientStatusMessage = "Generate flashcards before exporting a set."
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(studyData.flashcards) else {
            transientStatusMessage = "Could not export flashcards."
            return
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Notinq-Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileName = "\(sanitizeFileName(noteLabel))-flashcards-\(Int(Date().timeIntervalSince1970)).json"
        let url = folder.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic])
            transientStatusMessage = "Exported flashcards to \(url.lastPathComponent)."
        } catch {
            transientStatusMessage = "Flashcard export failed."
        }
    }

    func markConceptOutcome(_ concept: String, mastered: Bool) {
        let cleaned = concept.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        mutateStudyData { studyData in
            let index = studyData.learningMemory.firstIndex(where: {
                normalizeConceptKey($0.concept) == normalizeConceptKey(cleaned)
            }) ?? {
                studyData.learningMemory.append(StudyMemoryEntry(concept: cleaned))
                return studyData.learningMemory.count - 1
            }()

            studyData.learningMemory[index].reviewHistory.append(Date())
            studyData.learningMemory[index].lastReviewedAt = Date()
            studyData.learningMemory[index].lastOutcome = mastered ? .correct : .incorrect
            if mastered {
                studyData.learningMemory[index].masteredCount += 1
            } else {
                studyData.learningMemory[index].missedCount += 1
            }
            updateStreaks(&studyData, notesReviewed: 0, flashcardsCompleted: 1, quizzesCompleted: 0)
        }
    }

    func recordQuizAttemptLocally(score: Int, totalQuestions: Int) {
        let questions = max(totalQuestions, 1)
        mutateStudyData { studyData in
            let percentage = (Double(score) / Double(questions)) * 100
            studyData.progress.quizAttempts.insert(
                StudyQuizAttempt(
                    quizSetID: studyData.quizSets.first?.id ?? UUID(),
                    quizTitle: studyData.quizSets.first?.title ?? "Quiz",
                    score: score,
                    totalQuestions: questions,
                    percentage: percentage
                ),
                at: 0
            )
            updateStreaks(&studyData, notesReviewed: 0, flashcardsCompleted: 0, quizzesCompleted: 1)
        }
    }

    func recordGeneratedQuestionAnswer(_ question: StudyQuizQuestion, isCorrect: Bool) {
        guard let noteID else { return }
        let answer = generatedQuestionDraftAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAnswer = answer.isEmpty ? (isCorrect ? "Marked correct" : "Marked incorrect") : answer
        let answeredQuestion = question.recordingAnswer(finalAnswer, isCorrect: isCorrect)
        mutateStudyData { studyData in
            for setIndex in studyData.quizSets.indices {
                guard let questionIndex = studyData.quizSets[setIndex].questions.firstIndex(where: { $0.id == question.id }) else {
                    continue
                }
                studyData.quizSets[setIndex].questions[questionIndex] = answeredQuestion
                updateStreaks(&studyData, notesReviewed: 0, flashcardsCompleted: 0, quizzesCompleted: 1)
                break
            }
        }
        LearningSignalRecorder().recordStudyQuestionAnswered(question: answeredQuestion, isCorrect: isCorrect, noteID: noteID)
        generatedQuestionDraftAnswer = ""
        isGeneratedQuestionAnswerRevealed = false
        transientStatusMessage = isCorrect ? "Marked question correct." : "Marked question for review."
    }

    func persistStudySession(notesReviewed: Int = 1, flashcardsCompleted: Int = 0, quizzesCompleted: Int = 0) {
        mutateStudyData { studyData in
            updateStreaks(&studyData, notesReviewed: notesReviewed, flashcardsCompleted: flashcardsCompleted, quizzesCompleted: quizzesCompleted)
        }
    }

    func updateStreaks(_ studyData: inout NoteStudyData, notesReviewed: Int, flashcardsCompleted: Int, quizzesCompleted: Int) {
        let now = Date()
        studyData.streaks.studySessions += 1
        studyData.streaks.notesReviewed += notesReviewed
        studyData.streaks.flashcardsCompleted += flashcardsCompleted
        studyData.streaks.quizzesCompleted += quizzesCompleted

        if let lastStudiedAt = studyData.streaks.lastStudiedAt {
            if Calendar.current.isDate(now, inSameDayAs: lastStudiedAt) {
                studyData.streaks.lastStudiedAt = now
            } else if Calendar.current.isDate(now, inSameDayAs: Calendar.current.date(byAdding: .day, value: -1, to: lastStudiedAt) ?? lastStudiedAt) {
                studyData.streaks.currentStreak += 1
                studyData.streaks.lastStudiedAt = now
            } else {
                studyData.streaks.currentStreak = 1
                studyData.streaks.lastStudiedAt = now
            }
        } else {
            studyData.streaks.currentStreak = 1
            studyData.streaks.lastStudiedAt = now
        }
    }

    private func startTeachMeSession() {
        let context = teachMeAdaptiveContext()
        let manualConcept = extractConceptCandidates(from: noteContentSource, limit: 1).first ?? noteLabel
        let session = TeachMeEngine().startSession(
            adaptiveContext: context,
            recommendedConcepts: teachMeRecommendedConcepts(),
            manualConcept: manualConcept
        )
        teachMeDraftAnswer = ""
        persistTeachMeSession(session)
        transientStatusMessage = session.activeConceptName.map { "Teach Me question ready for \($0)." } ?? "No concept available for Teach Me yet."
    }

    private func submitTeachMeAnswer() {
        guard let current = studyData.teachMeSession,
              let question = current.activeQuestion else { return }

        let submitted = TeachMeEngine().submitAnswer(teachMeDraftAnswer, for: current)
        if let response = submitted.answerHistory.last {
            let recorder = LearningSignalRecorder()
            recorder.recordTeachMeAttempt(question: question)
            recorder.recordTeachMeEvaluation(question: question, evaluation: response.evaluation)
        }
        teachMeDraftAnswer = ""
        persistTeachMeSession(submitted)
    }

    private func advanceTeachMeSession() {
        guard let current = studyData.teachMeSession else { return }
        let advanced = TeachMeEngine().advanceAfterFeedback(current)
        teachMeDraftAnswer = ""
        persistTeachMeSession(advanced)
    }

    private func persistTeachMeSession(_ session: TeachMeSession) {
        mutateStudyData { studyData in
            studyData.teachMeSession = session
            studyData.lastGeneratedAt = Date()
        }
    }

    private func teachMeAdaptiveContext() -> AdaptiveExplanationContext {
        let gaps = studyData.notebookKnowledgeGaps.isEmpty
            ? buildNotebookKnowledgeGaps(currentNoteText: noteContentSource)
            : studyData.notebookKnowledgeGaps
        let gapTitles = gaps
            .sorted { $0.priority > $1.priority }
            .map(\.title)
        let historicallyConfusing = studyData.learningMemory
            .filter { $0.missedCount > $0.masteredCount }
            .sorted { $0.missedCount > $1.missedCount }
            .map(\.concept)
        let weakConcepts = studyData.learningMemory
            .filter { $0.masteryScore < 0.6 }
            .sorted { $0.masteryScore < $1.masteryScore }
            .map(\.concept)
        let masteryStates = Dictionary(
            studyData.learningMemory.map { entry in
                (TeachMeEngine.conceptID(for: entry.concept), MasteryState.state(for: entry.masteryScore))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let sourceExcerpt = noteContentSource
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sources = sourceExcerpt.isEmpty ? [] : [
            AdaptiveExplanationSource(
                sourceID: noteID?.uuidString ?? UUID().uuidString,
                sourceType: "note",
                noteID: noteID,
                noteTitle: noteLabel,
                snippet: sourceExcerpt,
                relevantExcerpt: sourceExcerpt
            )
        ]

        return AdaptiveExplanationContext(
            selectedText: selectedText,
            conceptIDs: (gapTitles + weakConcepts + historicallyConfusing).map(teachMeConceptID),
            weakConcepts: weakConcepts,
            identifiedKnowledgeGaps: gapTitles,
            historicallyConfusingConcepts: historicallyConfusing,
            masteryStates: masteryStates,
            retrievedNoteSources: sources,
            inferredLearnerLevel: "Study Session",
            confidence: gapTitles.isEmpty ? 0.35 : 0.7
        )
    }

    private func teachMeConceptID(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func teachMeRecommendedConcepts() -> [String] {
        let planned = StudyPlannerService()
            .dailyPlan(maxMinutes: 45)
            .tasks
            .map(\.concept)
        let fallback = studyData.insights.knowledgeGaps
            + studyData.insights.importantConcepts
            + studyData.insights.keyConcepts
        return uniqueTeachMeConcepts(planned + fallback)
    }

    private func uniqueTeachMeConcepts(_ concepts: [String]) -> [String] {
        var seen: Set<String> = []
        return concepts.filter { concept in
            let key = concept
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    func mutateStudyData(_ mutation: (inout NoteStudyData) -> Void) {
        guard let noteID else { return }
        appState.mutateStudyData(for: noteID) { studyData in
            mutation(&studyData)
        }
    }

    func cachedStudyKnowledgeSnapshot(from noteText: String) -> StudyKnowledgeSnapshot {
        let notebookText = notebookCombinedText
        let signature = studyKnowledgeSignature(noteTitle: noteLabel, noteText: noteText, notebookText: notebookText)

        if let noteID {
            let currentStudyData = appState.studyData(for: noteID)
            if currentStudyData.knowledgeSignature == signature, currentStudyData.knowledgeSnapshot.hasContent {
                return currentStudyData.knowledgeSnapshot
            }

            let snapshot = extractedStudyKnowledgeSnapshot(
                noteTitle: noteLabel,
                noteText: noteText,
                notebookText: notebookText,
                signature: signature
            )
            mutateStudyData { studyData in
                studyData.knowledgeSignature = signature
                studyData.knowledgeSnapshot = snapshot
            }
            return snapshot
        }

        return extractedStudyKnowledgeSnapshot(
            noteTitle: noteLabel,
            noteText: noteText,
            notebookText: notebookText,
            signature: signature
        )
    }

    private func extractedStudyKnowledgeSnapshot(
        noteTitle: String,
        noteText: String,
        notebookText: String,
        signature: String
    ) -> StudyKnowledgeSnapshot {
        if let cached = KnowledgeExtractionCache.shared.cachedKnowledge(for: signature) {
            return cached.legacySnapshotRepresentation()
        }

        // Schedule non-blocking async extraction for future cache hits
        Task {
            let run = await KnowledgeExtractionEngine.shared.extractRun(
                noteTitle: noteTitle,
                noteText: noteText,
                notebookText: notebookText
            )
            KnowledgeExtractionCache.shared.store(run.knowledge, for: signature)
        }

        // Return heuristic-based snapshot immediately instead of blocking
        return buildStudyKnowledgeSnapshot(
            noteTitle: noteTitle,
            noteText: noteText,
            notebookText: notebookText,
            signature: signature
        )
    }

    private func studyKnowledgeSignature(noteTitle: String, noteText: String, notebookText: String) -> String {
        [
            noteTitle,
            noteText,
            notebookText
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .joined(separator: "\u{241E}")
    }

    private func buildStudyKnowledgeSnapshot(
        noteTitle: String,
        noteText: String,
        notebookText: String,
        signature: String
    ) -> StudyKnowledgeSnapshot {
        let cleanedText = normalizeStudyNoteText(noteText)
        let sentences = splitSentences(cleanedText)
        let concepts = dedupeStrings(extractConceptCandidates(from: cleanedText, limit: 24))
        let notebookConcepts = Set(extractConceptCandidates(from: notebookText, limit: 24).map(normalizeConceptKey))
        let conceptCounts = conceptFrequency(in: cleanedText)
        let headingCandidates = cleanedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isLikelyHeading($0) }

        func evidence(for concept: String) -> [String] {
            let matching = sentences.filter { $0.localizedCaseInsensitiveContains(concept) }
            if !matching.isEmpty {
                return Array(matching.prefix(2))
            }
            return Array(headingCandidates.filter { $0.localizedCaseInsensitiveContains(concept) }.prefix(1))
        }

        func summary(for concept: String) -> String {
            let sentence = bestSentence(for: concept, in: sentences)
                ?? {
                    let fallback = sentenceContaining(concept, in: cleanedText)
                    return fallback.isEmpty ? nil : fallback
                }()
                ?? headingCandidates.first(where: { $0.localizedCaseInsensitiveContains(concept) })
                ?? concept
            return sentenceFragment(stripCitationMarkers(sentence))
        }

        func importance(for concept: String) -> Double {
            let normalized = normalizeConceptKey(concept)
            let frequency = Double(conceptCounts[normalized, default: 0])
            let sentenceMatches = Double(sentences.filter { $0.localizedCaseInsensitiveContains(concept) }.count)
            let headingBoost = headingCandidates.contains(where: { normalizeConceptKey($0).contains(normalized) }) ? 0.18 : 0
            let notebookBoost = notebookConcepts.contains(normalized) ? 0.12 : 0
            return min(1.0, 0.22 + (frequency * 0.16) + (sentenceMatches * 0.09) + headingBoost + notebookBoost)
        }

        func difficulty(for concept: String) -> Double {
            let normalized = normalizeConceptKey(concept)
            let words = normalized.split(separator: " ").count
            let hasFormulaLikeShape = concept.contains("=") || concept.contains("->") || concept.contains("(") || concept.contains(")")
            let conceptFrequency = conceptCounts[normalized, default: 0]
            var score = 0.2 + min(0.4, Double(words) * 0.06)
            if hasFormulaLikeShape { score += 0.2 }
            if conceptFrequency == 1 { score += 0.1 }
            if evidence(for: concept).count <= 1 { score += 0.1 }
            return min(1.0, score)
        }

        func relatedTitles(for concept: String) -> [String] {
            let normalized = normalizeConceptKey(concept)
            let related = sentences
                .filter { $0.localizedCaseInsensitiveContains(concept) }
                .flatMap { extractConceptCandidates(from: $0, limit: 4) }
                .filter { normalizeConceptKey($0) != normalized }
            return dedupeStrings(related).prefix(3).map(displayConcept)
        }

        func item(category: String, concept: String) -> StudyKnowledgeItem {
            StudyKnowledgeItem(
                title: displayConcept(concept),
                summary: summary(for: concept),
                evidence: evidence(for: concept),
                importance: importance(for: concept),
                difficulty: difficulty(for: concept),
                aliases: aliases(for: concept),
                relatedTitles: relatedTitles(for: concept),
                category: category
            )
        }

        let definitionTriggers = [" is ", " are ", " means ", " refers to ", " defined as ", " describes "]
        let procedureTriggers = [" first ", " then ", " next ", " step ", " process ", " algorithm ", " workflow ", " procedure "]
        let exampleTriggers = [" for example", " for instance", " such as", " e.g.", " example:"]
        let misconceptionTriggers = [" common mistake", " misconception", " confused with", " do not ", " don't ", " not "]
        let formulaTriggers = ["=", "→", "->", "∑", "∫", "≈", "≤", "≥"]

        let keyConceptItems = concepts.prefix(12).map { item(category: "key_term", concept: $0) }
        let definitions = concepts.compactMap { concept -> StudyKnowledgeItem? in
            guard let sentence = sentences.first(where: { sentence in
                sentence.localizedCaseInsensitiveContains(concept.lowercased()) || sentence.localizedCaseInsensitiveContains(concept)
            }) else { return nil }
            let lower = sentence.lowercased()
            guard definitionTriggers.contains(where: { lower.contains($0) }) else { return nil }
            return item(category: "definition", concept: concept)
        }

        let procedures = sentences.compactMap { sentence -> StudyKnowledgeItem? in
            let lower = sentence.lowercased()
            guard procedureTriggers.contains(where: { lower.contains($0) }) else { return nil }
            guard let concept = concepts.first(where: { lower.contains($0.lowercased()) }) ?? concepts.first else { return nil }
            return StudyKnowledgeItem(
                title: displayConcept(concept),
                summary: sentenceFragment(stripCitationMarkers(sentence)),
                evidence: [sentence],
                importance: 0.72,
                difficulty: 0.58,
                relatedTitles: relatedTitles(for: concept),
                category: "procedure"
            )
        }

        let examples = sentences.compactMap { sentence -> StudyKnowledgeItem? in
            let lower = sentence.lowercased()
            guard exampleTriggers.contains(where: { lower.contains($0) }) else { return nil }
            guard let concept = concepts.first(where: { lower.contains($0.lowercased()) }) ?? concepts.first else { return nil }
            return StudyKnowledgeItem(
                title: displayConcept(concept),
                summary: sentenceFragment(stripCitationMarkers(sentence)),
                evidence: [sentence],
                importance: 0.64,
                difficulty: 0.42,
                relatedTitles: relatedTitles(for: concept),
                category: "example"
            )
        }

        let formulas = sentences.compactMap { sentence -> StudyKnowledgeItem? in
            let lower = sentence.lowercased()
            guard formulaTriggers.contains(where: { sentence.contains($0) }) || lower.contains("formula") else { return nil }
            guard let concept = concepts.first(where: { lower.contains($0.lowercased()) }) ?? concepts.first else { return nil }
            return StudyKnowledgeItem(
                title: displayConcept(concept),
                summary: sentenceFragment(stripCitationMarkers(sentence)),
                evidence: [sentence],
                importance: 0.78,
                difficulty: 0.82,
                relatedTitles: relatedTitles(for: concept),
                category: "formula"
            )
        }

        let misconceptions = sentences.compactMap { sentence -> StudyKnowledgeItem? in
            let lower = sentence.lowercased()
            guard misconceptionTriggers.contains(where: { lower.contains($0) }) else { return nil }
            guard let concept = concepts.first(where: { lower.contains($0.lowercased()) }) ?? concepts.first else { return nil }
            return StudyKnowledgeItem(
                title: displayConcept(concept),
                summary: sentenceFragment(stripCitationMarkers(sentence)),
                evidence: [sentence],
                importance: 0.6,
                difficulty: 0.62,
                relatedTitles: relatedTitles(for: concept),
                category: "misconception"
            )
        }

        let importantFacts = concepts.prefix(8).map { concept in
            StudyKnowledgeItem(
                title: displayConcept(concept),
                summary: summary(for: concept),
                evidence: evidence(for: concept),
                importance: importance(for: concept),
                difficulty: difficulty(for: concept),
                relatedTitles: relatedTitles(for: concept),
                category: "fact"
            )
        }

        let prerequisites = prerequisiteGaps(for: cleanedText, notebookText: notebookText).prefix(8).map { gap in
            StudyKnowledgeItem(
                title: gap.title,
                summary: gap.description,
                evidence: [gap.evidence],
                importance: min(1.0, gap.priority / 6.0),
                difficulty: 0.76,
                relatedTitles: [],
                category: "prerequisite"
            )
        }

        let hierarchyRoots = buildKnowledgeHierarchy(
            noteTitle: noteTitle,
            concepts: keyConceptItems,
            relationships: relationshipsBetween(concepts: keyConceptItems, in: sentences)
        )

        let knowledgeDifficulty: StudyKnowledgeDifficulty
        let averageDifficulty = concepts.isEmpty ? 0.5 : concepts.map { difficulty(for: $0) }.reduce(0, +) / Double(concepts.count)
        switch averageDifficulty {
        case ..<0.38:
            knowledgeDifficulty = .intro
        case ..<0.68:
            knowledgeDifficulty = .intermediate
        default:
            knowledgeDifficulty = .advanced
        }

        return StudyKnowledgeSnapshot(
            title: noteTitle,
            sourceSignature: signature,
            cleanedText: cleanedText,
            concepts: keyConceptItems,
            definitions: definitions,
            relationships: relationshipsBetween(concepts: keyConceptItems, in: sentences),
            examples: examples,
            procedures: procedures,
            formulas: formulas,
            importantFacts: importantFacts,
            keyTerms: keyConceptItems,
            misconceptions: misconceptions,
            prerequisites: prerequisites,
            hierarchy: hierarchyRoots,
            difficulty: knowledgeDifficulty,
            supportingExamples: Array((examples + procedures).prefix(4)),
            summaryHighlights: summaryHighlights(from: keyConceptItems, definitions: definitions, importantFacts: importantFacts),
            examFocus: examFocus(from: keyConceptItems, definitions: definitions, formulas: formulas, procedures: procedures)
        )
    }

    private func isLikelyHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasSuffix(":") { return true }
        if trimmed.count < 64, trimmed == trimmed.uppercased(), trimmed.contains(where: { $0.isLetter }) { return true }
        if trimmed.first?.isNumber == true { return true }
        return false
    }

    private func normalizeStudyNoteText(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)

        var cleaned: [String] = []
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                if cleaned.last != "" {
                    cleaned.append("")
                }
                continue
            }

            if let last = cleaned.last, last.hasSuffix("-"), line.first?.isLowercase == true {
                cleaned[cleaned.count - 1] = String(last.dropLast()) + line
                continue
            }

            if let last = cleaned.last, shouldMergeStudyLines(previous: last, current: line) {
                cleaned[cleaned.count - 1] = last + " " + line
            } else if cleaned.last != line {
                cleaned.append(line)
            }
        }

        return cleaned.joined(separator: "\n")
    }

    private func shouldMergeStudyLines(previous: String, current: String) -> Bool {
        guard !previous.isEmpty, !current.isEmpty else { return false }
        let previousEndsWithSentence = previous.last.map { ".!?;:".contains($0) } ?? false
        if previousEndsWithSentence { return false }
        if current.first?.isLowercase == true { return true }
        if current.first?.isNumber == true { return true }
        return current.hasPrefix(")") || current.hasPrefix("•")
    }

    private func buildKnowledgeHierarchy(
        noteTitle: String,
        concepts: [StudyKnowledgeItem],
        relationships: [StudyKnowledgeRelationship]
    ) -> [StudyKnowledgeNode] {
        let childNodes = concepts.prefix(6).map { concept -> StudyKnowledgeNode in
            let related = relationships
                .filter { $0.sourceTitle == concept.title || $0.targetTitle == concept.title }
                .map { $0.sourceTitle == concept.title ? $0.targetTitle : $0.sourceTitle }
            let grandchildren = dedupeStrings(related)
                .prefix(3)
                .map { StudyKnowledgeNode(title: $0) }
            return StudyKnowledgeNode(title: concept.title, summary: concept.summary, children: Array(grandchildren))
        }
        return [StudyKnowledgeNode(title: noteTitle, summary: "Primary study topic", children: Array(childNodes))]
    }

    private func relationshipsBetween(concepts: [StudyKnowledgeItem], in sentences: [String]) -> [StudyKnowledgeRelationship] {
        var relationships: [StudyKnowledgeRelationship] = []
        let titles = concepts.map(\.title)

        for sentence in sentences {
            let matches = titles.filter { sentence.localizedCaseInsensitiveContains($0) }
            guard matches.count >= 2 else { continue }
            let first = matches[0]
            for target in matches.dropFirst().prefix(3) {
                relationships.append(
                    StudyKnowledgeRelationship(
                        sourceTitle: first,
                        targetTitle: target,
                        relation: relationType(for: sentence),
                        confidence: sentence.count > 80 ? 0.82 : 0.68
                    )
                )
            }
        }

        return dedupeKnowledgeRelationships(relationships)
    }

    private func relationType(for sentence: String) -> String {
        let lower = sentence.lowercased()
        if lower.contains("depends on") || lower.contains("requires") || lower.contains("prerequisite") {
            return "dependsOn"
        }
        if lower.contains("causes") || lower.contains("leads to") {
            return "leadsTo"
        }
        if lower.contains("example") {
            return "illustrates"
        }
        if lower.contains("compares") || lower.contains("versus") || lower.contains("compared to") {
            return "contrastsWith"
        }
        return "relatedTo"
    }

    private func dedupeKnowledgeRelationships(_ relationships: [StudyKnowledgeRelationship]) -> [StudyKnowledgeRelationship] {
        var seen = Set<String>()
        var results: [StudyKnowledgeRelationship] = []
        for relationship in relationships {
            let key = [
                normalizeConceptKey(relationship.sourceTitle),
                normalizeConceptKey(relationship.targetTitle),
                relationship.relation
            ].joined(separator: "|")
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(relationship)
        }
        return results
    }

    private func summaryHighlights(from concepts: [StudyKnowledgeItem], definitions: [StudyKnowledgeItem], importantFacts: [StudyKnowledgeItem]) -> [String] {
        let items = [
            concepts.prefix(3).map(\.title),
            definitions.prefix(2).map(\.title),
            importantFacts.prefix(2).map(\.title)
        ].flatMap { $0 }
        return dedupeStrings(items).prefix(6).map { $0 }
    }

    private func examFocus(from concepts: [StudyKnowledgeItem], definitions: [StudyKnowledgeItem], formulas: [StudyKnowledgeItem], procedures: [StudyKnowledgeItem]) -> [String] {
        let items = [
            definitions.prefix(3).map { "Define \($0.title)" },
            formulas.prefix(2).map { "Use the formula for \($0.title)" },
            procedures.prefix(2).map { "Explain the steps for \($0.title)" },
            concepts.prefix(3).map { "Apply \($0.title) in context" }
        ].flatMap { $0 }
        return dedupeStrings(items).prefix(8).map { $0 }
    }

    private func aliases(for concept: String) -> [String] {
        let raw = concept
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return dedupeStrings(raw)
    }

    func buildLearningInsightsAnalysis(noteText: String, notebookText: String) -> LectureCompletenessAnalysis {
        let lectureKnowledge = cachedStudyKnowledgeSnapshot(from: noteText)
        let notebookKnowledge = extractedStudyKnowledgeSnapshot(
            noteTitle: "Student Notes",
            noteText: notebookText,
            notebookText: "",
            signature: studyKnowledgeSignature(noteTitle: "Student Notes", noteText: notebookText, notebookText: "")
        )

        let notebookLookup = Set(
            (notebookKnowledge.concepts + notebookKnowledge.definitions + notebookKnowledge.keyTerms)
                .flatMap { [$0.title] + $0.aliases + $0.relatedTitles }
                .map(normalizeConceptKey)
        )

        func makeCoverageItem(_ concept: StudyKnowledgeItem, state: LectureCoverageState, noteSummary: String) -> LectureCoverageItem {
            let related = concept.relatedTitles.prefix(2).joined(separator: ", ")
            return LectureCoverageItem(
                title: concept.title,
                state: state,
                whatWasMissed: state == .covered ? "" : "The note does not fully capture \(concept.title).",
                whyItMatters: state == .missing ? "This concept is required to understand the source more completely." : "This idea is relevant to the note's study flow.",
                shortExplanation: concept.summary.isEmpty ? noteSummary : concept.summary,
                suggestedAddition: state == .covered ? "" : "Add a short definition\(related.isEmpty ? "" : ", connect it to \(related)") and one example.",
                importance: concept.importance,
                evidence: concept.evidence.isEmpty ? [concept.summary] : concept.evidence,
                matchScore: state == .covered ? 0.88 : (state == .partial ? 0.56 : 0.12),
                noteSummary: noteSummary
            )
        }

        let lectureConcepts = lectureKnowledge.concepts
        let covered = lectureConcepts.filter { concept in
            let key = normalizeConceptKey(concept.title)
            return notebookLookup.contains(key) || concept.relatedTitles.contains(where: { notebookLookup.contains(normalizeConceptKey($0)) })
        }
        .prefix(6)
        .map { makeCoverageItem($0, state: .covered, noteSummary: $0.summary) }

        let partiallyCaptured = lectureConcepts.filter { concept in
            let key = normalizeConceptKey(concept.title)
            return !notebookLookup.contains(key) && concept.relatedTitles.contains(where: { notebookLookup.contains(normalizeConceptKey($0)) })
        }
        .prefix(5)
        .map { makeCoverageItem($0, state: .partial, noteSummary: $0.summary) }

        let missingConcepts = lectureKnowledge.prerequisites
            .filter { prerequisite in
                !notebookLookup.contains(normalizeConceptKey(prerequisite.title))
            }
            .prefix(5)
            .map { makeCoverageItem($0, state: .missing, noteSummary: $0.summary) }

        let weightedScore = (
            Double(covered.count) * 1.0 +
            Double(partiallyCaptured.count) * 0.55 +
            Double(max(0, lectureConcepts.count - covered.count - partiallyCaptured.count - missingConcepts.count)) * 0.18
        ) / Double(max(1, lectureConcepts.count))

        let reviewPriority = (missingConcepts + partiallyCaptured)
            .enumerated()
            .map { index, item in
                LectureReviewPriorityItem(
                    rank: index + 1,
                    title: item.title,
                    reason: item.state == .missing ? "Missing from the current note context." : "Only partially explained in the current note.",
                    state: item.state,
                    importance: item.importance
                )
            }

        let summary = [
            "See which concepts are fully captured, partially explained, or missing from your notes.",
            "Covered: \(covered.count). Partial: \(partiallyCaptured.count). Missing: \(missingConcepts.count)."
        ].joined(separator: " ")

        return LectureCompletenessAnalysis(
            completenessScore: min(1, max(0, weightedScore)),
            lectureConceptCount: lectureConcepts.count,
            noteConceptCount: notebookKnowledge.concepts.count,
            missingConcepts: missingConcepts,
            partiallyCapturedConcepts: partiallyCaptured,
            wellCoveredConcepts: covered,
            missingVisualContent: lectureKnowledge.supportingExamples.filter { $0.category == "example" }.map {
                LectureVisualGap(
                    title: $0.title,
                    whatWasMissed: "The note likely relied on a visual or worked example here.",
                    whyItMatters: "Visuals often preserve structure that is hard to reconstruct from text alone.",
                    shortExplanation: $0.summary,
                    suggestedAddition: "Add a sketch, a diagram caption, or a short visual note.",
                    importance: $0.importance,
                    evidence: $0.evidence
                )
            },
            reviewPriority: reviewPriority,
            summary: summary,
            generatedAt: Date()
        )
    }

    func buildFlashcards(from text: String) -> [StudyFlashcard] {
        let knowledge = cachedStudyKnowledgeSnapshot(from: text)
        var cards: [StudyFlashcard] = []
        var seenFronts = Set<String>()

        func appendCard(type: StudyCardType, front: String, back: String, why: String) {
            guard seenFronts.insert(front.lowercased()).inserted else { return }
            cards.append(StudyFlashcard(type: type, front: front, back: back, whyItMatters: why))
        }

        for concept in knowledge.definitions.prefix(3) {
            appendCard(
                type: .definition,
                front: "What is \(concept.title)?",
                back: [
                    concept.summary,
                    concept.evidence.first ?? "Use the note context to refine the definition.",
                    "Why it matters",
                    "This concept supports the rest of the topic."
                ].joined(separator: "\n"),
                why: "Definition recall turns a name into a usable concept."
            )
        }

        for item in knowledge.examples.prefix(2) {
            appendCard(
                type: .questionAnswer,
                front: "Give an example of \(item.title).",
                back: [
                    item.summary,
                    item.evidence.first ?? "",
                    "Why it matters",
                    "Examples show whether you can apply the idea, not just repeat it."
                ].joined(separator: "\n"),
                why: "Examples test application, not keyword matching."
            )
        }

        for item in knowledge.misconceptions.prefix(2) {
            appendCard(
                type: .concept,
                front: "What is a common mistake about \(item.title)?",
                back: [
                    item.summary,
                    "Corrective cue",
                    "This note warns against treating the idea as \(item.summary.lowercased())."
                ].joined(separator: "\n"),
                why: "Misconception cards help students avoid predictable exam errors."
            )
        }

        for item in knowledge.formulas.prefix(2) {
            appendCard(
                type: .cloze,
                front: item.summary,
                back: [
                    item.title,
                    "Formula cue",
                    item.summary
                ].joined(separator: "\n"),
                why: "Formula recall should focus on the structure and the meaning of each term."
            )
        }

        for item in knowledge.prerequisites.prefix(1) {
            appendCard(
                type: .questionAnswer,
                front: "Why do you need to know \(item.title)?",
                back: [
                    item.summary,
                    item.evidence.first ?? "",
                    "Why it matters",
                    "Prerequisites unlock the rest of the topic."
                ].joined(separator: "\n"),
                why: "Prerequisite cards make weak foundations visible early."
            )
        }

        if cards.isEmpty, let firstConcept = knowledge.concepts.first {
            appendCard(
                type: .definition,
                front: "What is \(firstConcept.title)?",
                back: firstConcept.summary,
                why: "Start with the note's primary concept."
            )
        }

        return Array(cards.prefix(8))
    }

    func buildQuizSet(from text: String) -> StudyQuizSet {
        let knowledge = cachedStudyKnowledgeSnapshot(from: text)
        var questions: [StudyQuizQuestion] = []
        let conceptItems = knowledge.concepts
        let definitionLookup = knowledge.definitions.reduce(into: [String: StudyKnowledgeItem]()) { result, item in
            let key = normalizeConceptKey(item.title)
            if result[key] == nil {
                result[key] = item
            }
        }
        let relationshipLookup = knowledge.relationships
        var usedConceptKeys = Set<String>()

        func distractors(excluding concept: StudyKnowledgeItem) -> [String] {
            conceptItems
                .filter { normalizeConceptKey($0.title) != normalizeConceptKey(concept.title) }
                .prefix(3)
                .map(\.title)
        }

        for concept in conceptItems.prefix(3) {
            let options = ([concept.title] + distractors(excluding: concept)).shuffled()
            let explanation = definitionLookup[normalizeConceptKey(concept.title)]?.summary ?? concept.summary
            questions.append(
                StudyQuizQuestion(
                    type: .multipleChoice,
                    prompt: "Which choice best describes \(concept.title) in this note?",
                    options: options,
                    correctAnswer: concept.title,
                    explanation: explanation,
                    keywords: [concept.title]
                )
            )
            usedConceptKeys.insert(normalizeConceptKey(concept.title))
        }

        if let concept = conceptItems.dropFirst().first {
            questions.append(
                StudyQuizQuestion(
                    type: .trueFalse,
                    prompt: "True or false: \(concept.title) is a topic worth revisiting for understanding this note.",
                    options: ["True", "False"],
                    correctAnswer: "True",
                    explanation: concept.summary,
                    keywords: [concept.title]
                )
            )
        }

        if let concept = conceptItems.first {
            let blank = (definitionLookup[normalizeConceptKey(concept.title)]?.summary ?? concept.summary)
                .replacingOccurrences(of: concept.title, with: "_____")
            questions.append(
                StudyQuizQuestion(
                    type: .fillInTheBlank,
                    prompt: blank,
                    options: [],
                    correctAnswer: concept.title,
                    explanation: "Use the surrounding meaning to recover the missing concept.",
                    keywords: [concept.title]
                )
            )
        }

        if conceptItems.count >= 2 {
            let first = conceptItems[0]
            let second = conceptItems[1]
            questions.append(
                StudyQuizQuestion(
                    type: .comparison,
                    prompt: "Compare \(first.title) and \(second.title). How are they related or different?",
                    options: [],
                    correctAnswer: relationshipAnswer(first: first, second: second, relationships: relationshipLookup),
                    explanation: "A strong comparison links both ideas instead of listing them separately.",
                    keywords: [first.title, second.title]
                )
            )
        }

        if let concept = conceptItems.dropFirst(2).first ?? conceptItems.first {
            questions.append(
                StudyQuizQuestion(
                    type: .application,
                    prompt: "How would you use \(concept.title) in a new example or problem?",
                    options: [],
                    correctAnswer: applicationAnswer(from: concept.summary, concept: concept.title),
                    explanation: "Application questions test transfer, not recognition.",
                    keywords: [concept.title]
                )
            )
        }

        if let concept = conceptItems.dropFirst(3).first ?? conceptItems.first {
            questions.append(
                StudyQuizQuestion(
                    type: .conceptualUnderstanding,
                    prompt: "Why does \(concept.title) matter in the bigger topic?",
                    options: [],
                    correctAnswer: concept.summary,
                    explanation: "This checks whether you can explain the concept in context.",
                    keywords: [concept.title]
                )
            )
        }

        if let concept = conceptItems.dropFirst(4).first ?? conceptItems.first {
            questions.append(
                StudyQuizQuestion(
                    type: .shortAnswer,
                    prompt: "In your own words, explain \(concept.title) and connect it to the note.",
                    options: [],
                    correctAnswer: concept.summary,
                    explanation: "Use a concise but complete explanation.",
                    keywords: [concept.title]
                )
            )
        }

        return StudyQuizSet(title: "Quiz Generator - \(noteLabel)", questions: Array(questions.prefix(8)))
    }

    func buildSummaryPack(from text: String) -> StudySummaryPack {
        let knowledge = cachedStudyKnowledgeSnapshot(from: text)
        let executiveLines = [
            "Title",
            knowledge.title,
            "Top ideas",
            summaryBulletList(knowledge.summaryHighlights, emptyText: "No strong ideas identified yet."),
            "Key terms",
            summaryBulletList(knowledge.keyTerms.prefix(5).map(\.title), emptyText: "No key terms identified yet.")
        ]
        let executive = structuredSummaryBlock(title: "Executive", lines: executiveLines)

        let detailedLines = [
            "Overview",
            summaryParagraph(from: splitSentences(knowledge.cleanedText)),
            "Core ideas",
            summaryBulletList(knowledge.concepts.prefix(5).map { "\($0.title) - \($0.summary)" }, emptyText: "No core ideas identified yet."),
            "Definitions",
            summaryBulletList(knowledge.definitions.prefix(5).map { "\($0.title) - \($0.summary)" }, emptyText: "No definitions identified yet."),
            "Important relationships",
            summaryBulletList(knowledge.relationships.prefix(5).map { "\($0.sourceTitle) \(relationshipLabel(for: $0.relation)) \( $0.targetTitle)" }, emptyText: "No relationships identified yet."),
            "Examples",
            summaryBulletList(knowledge.examples.prefix(3).map { "\($0.title) - \($0.summary)" }, emptyText: "No examples identified yet.")
        ]
        let detailed = structuredSummaryBlock(title: "Detailed", lines: detailedLines)

        let revisionLines = [
            "Exam focus",
            summaryBulletList(Array(knowledge.examFocus.prefix(6)), emptyText: "No exam focus identified yet."),
            "Definitions",
            summaryBulletList(knowledge.definitions.prefix(4).map { "\($0.title): \($0.summary)" }, emptyText: "No definitions identified yet."),
            "Formulas and procedures",
            summaryBulletList((knowledge.formulas.prefix(2).map { $0.summary }) + (knowledge.procedures.prefix(2).map { $0.summary }), emptyText: "No formulas or procedures identified yet."),
            "Common mistakes",
            summaryBulletList(knowledge.misconceptions.prefix(4).map { "\($0.title) - \($0.summary)" }, emptyText: "No common mistakes identified yet."),
            "Quick review",
            summaryBulletList(Array(knowledge.summaryHighlights.prefix(5)), emptyText: "No quick review points identified yet.")
        ]
        let exam = structuredSummaryBlock(title: "Revision", lines: revisionLines)
        return StudySummaryPack(executiveSummary: executive, detailedSummary: detailed, examRevisionSummary: exam)
    }

    func buildKeyConceptInsights(from text: String, notebookText: String) -> StudyInsights {
        let knowledge = cachedStudyKnowledgeSnapshot(from: text)
        let notebookKnowledge = extractedStudyKnowledgeSnapshot(
            noteTitle: "Student Notes",
            noteText: notebookText,
            notebookText: "",
            signature: studyKnowledgeSignature(noteTitle: "Student Notes", noteText: notebookText, notebookText: "")
        )
        let notebookLookup = Set(notebookKnowledge.concepts.map(\.title).map(normalizeConceptKey))
        let rankedConcepts = knowledge.concepts.sorted { $0.importance > $1.importance }
        let repeatedConcepts = rankedConcepts.filter { $0.importance >= 0.55 }
        return StudyInsights(
            keyConcepts: Array(rankedConcepts.prefix(8).map(\.title)),
            importantConcepts: Array(repeatedConcepts.prefix(5).map(\.title)),
            frequentTerms: Array(rankedConcepts.prefix(6).enumerated().map { index, item in
                StudyTerm(term: item.title, count: max(1, Int((item.importance * 10).rounded()) - index))
            }),
            potentialExamTopics: knowledge.examFocus.prefix(6).map { $0 },
            knowledgeGaps: notebookKnowledge.concepts
                .filter { !Set(knowledge.concepts.map(\.title).map(normalizeConceptKey)).contains(normalizeConceptKey($0.title)) && !notebookLookup.contains(normalizeConceptKey($0.title)) }
                .prefix(6)
                .map(\.title)
        )
    }

    private func extractedStructuredKnowledge(
        noteTitle: String,
        noteText: String,
        notebookText: String,
        signature: String
    ) -> StructuredKnowledge {
        if let cached = KnowledgeExtractionCache.shared.cachedKnowledge(for: signature) {
            return cached
        }

        // Schedule non-blocking async extraction for future cache hits
        Task {
            let run = await KnowledgeExtractionEngine.shared.extractRun(
                noteTitle: noteTitle,
                noteText: noteText,
                notebookText: notebookText
            )
            KnowledgeExtractionCache.shared.store(run.knowledge, for: signature)
        }

        return StructuredKnowledge(metadata: KnowledgeMetadata(title: noteTitle, sourceSignature: signature), title: noteTitle)
    }

    func buildExamPrep(from text: String) -> StudyExamPrep {
        let knowledge = cachedStudyKnowledgeSnapshot(from: text)
        return StudyExamPrep(
            likelyTopics: knowledge.examFocus.prefix(6).map { $0 },
            condensedRevisionGuide: summaryText(for: buildSummaryPack(from: text), mode: .revision),
            practiceQuestions: Array(buildQuizSet(from: text).questions.prefix(6)),
            difficultConcepts: knowledge.formulas.prefix(2).map(\.title) + knowledge.prerequisites.prefix(2).map(\.title)
        )
    }

    func buildConceptMap(from text: String) -> [StudyConceptNode] {
        let signature = studyKnowledgeSignature(noteTitle: noteLabel, noteText: text, notebookText: notebookCombinedText)
        let structuredKnowledge = extractedStructuredKnowledge(
            noteTitle: noteLabel,
            noteText: text,
            notebookText: notebookCombinedText,
            signature: signature
        )
        guard !structuredKnowledge.relationships.isEmpty else { return [] }

        let titleByID = structuredKnowledge.concepts.reduce(into: [String: String]()) { result, concept in
            result[concept.id] = concept.name
        }
        let outgoing = Dictionary(grouping: structuredKnowledge.relationships, by: { $0.sourceID })
        let incoming = Set(structuredKnowledge.relationships.map(\.targetID))
        let roots = structuredKnowledge.concepts.map(\.id).filter { !incoming.contains($0) }

        func renderNode(id: String, visited: inout Set<String>) -> StudyConceptNode {
            let title = titleByID[id] ?? id
            guard visited.insert(id).inserted else {
                return StudyConceptNode(title: title, children: [])
            }
            let children = outgoing[id, default: []].map { renderNode(id: $0.targetID, visited: &visited) }
            return StudyConceptNode(title: title, children: children)
        }

        return roots.prefix(5).map { root in
            var visited = Set<String>()
            return renderNode(id: root, visited: &visited)
        }
    }

    func buildActiveRecallPrompts(from text: String) -> [StudyActiveRecallPrompt] {
        let knowledge = cachedStudyKnowledgeSnapshot(from: text)
        guard !knowledge.concepts.isEmpty else { return [] }
        var prompts: [StudyActiveRecallPrompt] = []
        var seenQuestions = Set<String>()

        for concept in knowledge.concepts.prefix(4) {
            let promptText = activeRecallQuestion(for: concept.title, sentence: concept.summary)
            guard seenQuestions.insert(promptText.lowercased()).inserted else { continue }

            prompts.append(
                StudyActiveRecallPrompt(
                    prompt: promptText,
                    answer: concept.summary,
                    hiddenText: concept.evidence.first ?? concept.summary
                )
            )
        }

        return prompts
    }

    func buildNotebookKnowledgeGaps(currentNoteText: String) -> [StudyKnowledgeGap] {
        let currentKnowledge = cachedStudyKnowledgeSnapshot(from: currentNoteText)
        let notebookConceptCounts = notebookConceptFrequency
        let currentKeys = Set(currentKnowledge.concepts.map { normalizeConceptKey($0.title) })
        var gaps: [StudyKnowledgeGap] = []

        for (topic, count) in notebookConceptCounts.sorted(by: { $0.value > $1.value }).prefix(10) where count >= 2 {
            guard !currentKeys.contains(topic) else { continue }
            gaps.append(
                StudyKnowledgeGap(
                    title: "Review \(displayConcept(topic))",
                    description: "This idea appears repeatedly in the notebook but is not captured in the active note.",
                    evidence: "Referenced across \(count) notes.",
                    priority: Double(count)
                )
            )
        }

        for prerequisite in currentKnowledge.prerequisites.prefix(4) where !currentKeys.contains(normalizeConceptKey(prerequisite.title)) {
            gaps.append(
                StudyKnowledgeGap(
                    title: prerequisite.title,
                    description: prerequisite.summary,
                    evidence: prerequisite.evidence.first ?? "Missing from the active note.",
                    priority: max(1.0, prerequisite.importance * 5.0)
                )
            )
        }

        return dedupeGaps(gaps).prefix(6).map { $0 }
    }

    func activeKnowledgeGaps() -> [StudyKnowledgeGap] {
        let detected = buildNotebookKnowledgeGaps(currentNoteText: noteContentSource)
        let source = studyData.notebookKnowledgeGaps.isEmpty
            ? detected
            : StudyKnowledgeGap.merge(existing: studyData.notebookKnowledgeGaps, detected: detected)
        return source
            .filter { $0.status == .active }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    func updateKnowledgeGap(_ gap: StudyKnowledgeGap, status: StudyKnowledgeGapStatus, resolutionMethod: String? = nil) {
        guard let noteID else { return }
        appState.mutateStudyData(for: noteID) { studyData in
            let detected = buildNotebookKnowledgeGaps(currentNoteText: noteContentSource)
            var gaps = StudyKnowledgeGap.merge(existing: studyData.notebookKnowledgeGaps, detected: detected)
            guard let index = gaps.firstIndex(where: { $0.normalizedKey == gap.normalizedKey }) else { return }
            gaps[index].status = status
            gaps[index].updatedAt = Date()
            gaps[index].resolutionMethod = resolutionMethod
            studyData.notebookKnowledgeGaps = gaps
        }

        switch status {
        case .active:
            break
        case .ignored:
            ResearchInstrumentationService.shared.recordKnowledgeGapIgnored(
                concept: gap.title,
                heuristic: gap.detectionHeuristic,
                noteID: noteID
            )
            transientStatusMessage = "Ignored \(gap.title)."
        case .resolved:
            ResearchInstrumentationService.shared.recordKnowledgeGapResolved(
                concept: gap.title,
                resolutionMethod: resolutionMethod ?? "markedUnderstood",
                noteID: noteID
            )
            transientStatusMessage = "Marked \(gap.title) as understood."
        }
    }

    func explainKnowledgeGap(_ gap: StudyKnowledgeGap) {
        guard let noteID else { return }
        appState.requestKnowledgeGapExplanation(
            concept: gap.title,
            reason: gap.description,
            evidence: gap.evidence,
            noteID: noteID
        )
    }

    func supplementalSection(for section: SupplementalStudySection) -> AnyView {
        let isExpanded = isSupplementalSectionExpanded(section)

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    toggleSupplementalSection(section)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(toolTint(forSupplemental: section))
                            .frame(width: 30, height: 30)
                            .background(toolTint(forSupplemental: section).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(section.rawValue)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(supplementalSubtitle(for: section))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.studySurfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.studyBorderSoft, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(section.rawValue)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Toggle this study section.")

                if isExpanded {
                    supplementalSectionContent(for: section)
                        .padding(.leading, 6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        )
    }

    func supplementalSectionContent(for section: SupplementalStudySection) -> AnyView {
        switch section {
        case .teachMe:
            return AnyView(teachMeSection)
        case .learningMemory:
            return AnyView(learningMemorySection)
        case .knowledgeGaps:
            return AnyView(knowledgeGapsSection)
        case .examPrep:
            return AnyView(examPrepSection)
        case .conceptMap:
            return AnyView(conceptMapSection)
        case .knowledgeGraph:
            return AnyView(knowledgeGraphSection)
        case .activeRecall:
            return AnyView(activeRecallSection)
        case .streaks:
            return AnyView(streaksSection)
        }
    }

    private var teachMeSection: some View {
        let session = studyData.teachMeSession ?? TeachMeSession()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                statPill(title: "State", value: teachMeStateLabel(session.state))
                statPill(title: "Concept", value: session.activeConceptName ?? "None")
            }

            if let question = session.activeQuestion {
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.conceptName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(question.question)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let gap = question.originatingKnowledgeGap, !gap.isEmpty {
                        Text("Gap: \(gap)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let source = question.sourceReferences.first {
                        Text("Source: \(source.noteTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.studySurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                emptyCompactState(
                    title: "No active Teach Me question",
                    message: "Press Start to pick the best available gap, confusing concept, weak mastery item, or selected concept and turn it into one question."
                )
            }

            switch session.state {
            case .idle, .complete:
                HStack(spacing: 8) {
                    quickAction("Start", tint: Color(red: 0.24, green: 0.49, blue: 0.59), icon: "play.fill") {
                        startTeachMeSession()
                    }
                    if session.state == .complete {
                        quickAction("Reset", tint: Color.textSecondary, icon: "arrow.counterclockwise") {
                            persistTeachMeSession(TeachMeSession())
                        }
                    }
                }
            case .question:
                quickAction("Answer", tint: Color(red: 0.31, green: 0.56, blue: 0.38), icon: "square.and.pencil") {
                    persistTeachMeSession(TeachMeEngine().beginAnswering(session))
                }
            case .answering:
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $teachMeDraftAnswer)
                        .font(.body)
                        .frame(minHeight: 88)
                        .padding(8)
                        .background(Color.studySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    quickAction("Submit", tint: Color(red: 0.31, green: 0.56, blue: 0.38), icon: "checkmark") {
                        submitTeachMeAnswer()
                    }
                    .disabled(teachMeDraftAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .feedback:
                if let response = session.answerHistory.last {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(teachMeEvaluationTitle(response.evaluation))
                            .font(.subheadline.weight(.semibold))
                        Text(response.feedback)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.studySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                quickAction("Continue", tint: Color(red: 0.24, green: 0.49, blue: 0.59), icon: "arrow.right") {
                    advanceTeachMeSession()
                }
            }
        }
    }

    private var learningMemorySection: some View {
        let mastered = studyData.learningMemory.filter { $0.masteryScore >= 0.7 }
        let missed = studyData.learningMemory.filter { $0.missedCount > $0.masteredCount }
        let memoryText = learningMemoryText(from: studyData.learningMemory)
        let artifact = studyData.artifacts.first(where: { $0.kind == .learningMemory }) ?? buildArtifact(
            kind: .learningMemory,
            title: "Learning Memory",
            content: memoryText,
            sections: learningMemorySections(from: studyData.learningMemory)
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                statPill(title: "Mastered", value: "\(mastered.count)")
                statPill(title: "Needs Review", value: "\(missed.count)")
                statPill(title: "Total", value: "\(studyData.learningMemory.count)")
            }

            HStack(spacing: 8) {
                quickAction("Review", tint: Color(red: 0.24, green: 0.49, blue: 0.59), icon: "arrow.counterclockwise") {
                    focusStudyTool(.flashcards)
                }
                quickAction("Practice", tint: Color(red: 0.31, green: 0.56, blue: 0.38), icon: "brain.head.profile") {
                    focusStudyTool(.quizGenerator)
                }
                quickAction("Explore", tint: Color(red: 0.27, green: 0.43, blue: 0.55), icon: "magnifyingglass") {
                    focusStudyTool(.learningInsights)
                }
            }

            if studyData.learningMemory.isEmpty {
                emptyCompactState(title: "No learning memory yet", message: "Generate flashcards or active recall prompts to begin tracking mastered and missed concepts.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    memorySection(title: "Mastered concepts", items: mastered.prefix(4), tint: Color(red: 0.27, green: 0.58, blue: 0.39))
                    memorySection(title: "Repeated misses", items: missed.prefix(4), tint: Color(red: 0.73, green: 0.35, blue: 0.33))
                }
            }

            actionButtons(artifact: artifact, accent: Color(red: 0.24, green: 0.49, blue: 0.59), onRegenerate: { generateLearningMemory() })
        }
    }

    private var knowledgeGapsSection: some View {
        let gaps = activeKnowledgeGaps()
        let artifact = studyData.artifacts.first(where: { $0.kind == .notebookKnowledgeGaps }) ?? buildArtifact(
            kind: .notebookKnowledgeGaps,
            title: "Knowledge Gaps",
            content: notebookGapsText(from: gaps),
            sections: notebookGapSections(from: gaps)
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                quickAction("Scan Gaps", tint: Color(red: 0.73, green: 0.35, blue: 0.33), icon: "waveform.path.ecg") {
                    generateNotebookKnowledgeGaps()
                }
                quickAction("Generate Quiz", tint: Color(red: 0.60, green: 0.45, blue: 0.20), icon: "checklist") {
                    focusStudyTool(.quizGenerator)
                    generateQuizSet()
                }
                quickAction("Compare", tint: Color(red: 0.73, green: 0.35, blue: 0.33), icon: "scale.3d") {
                    onCompareConcepts()
                }
                quickAction("Open Graph", tint: Color(red: 0.24, green: 0.49, blue: 0.59), icon: "circle.grid.2x2") {
                    focusStudyTool(.keyConcepts)
                }
            }

            if gaps.isEmpty {
                emptyCompactState(
                    title: "No active knowledge gaps",
                    message: "Use Scan Gaps to compare this note with the notebook. When a gap appears, Explain creates a reviewable AI proposal instead of changing the note directly."
                )
            } else {
                ForEach(gaps.prefix(4)) { gap in
                    PossibleKnowledgeGapCard(
                        model: KnowledgeGapDisplayModel(gap: gap),
                        onExplain: { explainKnowledgeGap(gap) },
                        onIgnore: { updateKnowledgeGap(gap, status: .ignored) },
                        onMarkUnderstood: { updateKnowledgeGap(gap, status: .resolved, resolutionMethod: "markedUnderstood") }
                    )
                }
            }

            actionButtons(artifact: artifact, accent: Color(red: 0.73, green: 0.35, blue: 0.33), onRegenerate: { generateNotebookKnowledgeGaps() })
        }
    }

    private var examPrepSection: some View {
        let prep = studyData.examPrep
        let artifact = studyData.artifacts.first(where: { $0.kind == .examPrep }) ?? buildArtifact(
            kind: .examPrep,
            title: "Exam Prep",
            content: examPrepText(from: prep),
            sections: examPrepSections(from: prep)
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                quickAction("Review", tint: Color(red: 0.31, green: 0.56, blue: 0.38), icon: "rectangle.stack") {
                    focusStudyTool(.flashcards)
                }
                quickAction("Practice", tint: Color(red: 0.60, green: 0.45, blue: 0.20), icon: "brain.head.profile") {
                    focusStudyTool(.quizGenerator)
                }
                quickAction("Open Map", tint: Color(red: 0.27, green: 0.43, blue: 0.55), icon: "point.3.connected.trianglepath.dotted") {
                    focusStudyTool(.keyConcepts)
                }
            }

            if prep.likelyTopics.isEmpty {
                emptyCompactState(title: "No exam prep yet", message: "Generate exam prep to build likely topics, revision notes, and practice questions from the note.")
            } else {
                chipSection(title: "Likely Topics", items: prep.likelyTopics, tint: Color(red: 0.60, green: 0.45, blue: 0.20))

                generatedTextBlock(
                    title: "Condensed Revision Guide",
                    subtitle: "Exam-focused summary",
                    body: prep.condensedRevisionGuide,
                    artifact: artifact,
                    accent: Color(red: 0.60, green: 0.45, blue: 0.20),
                    onRegenerate: { generateExamPrep() }
                )

                if !prep.practiceQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Practice Questions")
                            .font(.headline)
                        ForEach(prep.practiceQuestions.prefix(3)) { question in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(question.prompt)
                                    .font(.subheadline.weight(.semibold))
                                Text("Answer: \(question.correctAnswer)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !question.explanation.isEmpty {
                                    Text(question.explanation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.studySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }

            actionButtons(artifact: artifact, accent: Color(red: 0.60, green: 0.45, blue: 0.20), onRegenerate: { generateExamPrep() })
        }
    }

    private var conceptMapSection: some View {
        let map = studyData.conceptMap.isEmpty ? buildConceptMap(from: noteContentSource) : studyData.conceptMap
        let artifact = studyData.artifacts.first(where: { $0.kind == .conceptMap }) ?? buildArtifact(
            kind: .conceptMap,
            title: "Concept Map",
            content: conceptMapText(from: map),
            sections: conceptMapSections(from: map)
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                quickAction("Explore", tint: Color(red: 0.27, green: 0.43, blue: 0.55), icon: "magnifyingglass") {
                    focusStudyTool(.keyConcepts)
                }
                quickAction("Compare", tint: Color(red: 0.73, green: 0.35, blue: 0.33), icon: "scale.3d") {
                    onCompareConcepts()
                }
                quickAction("Practice", tint: Color(red: 0.31, green: 0.56, blue: 0.38), icon: "brain.head.profile") {
                    focusStudyTool(.quizGenerator)
                }
            }

            if map.isEmpty {
                emptyCompactState(title: "No concept map yet", message: "Generate a concept map to see the note as a relationship tree.")
            } else {
                conceptMapNode(map[0], depth: 0)
            }

            actionButtons(artifact: artifact, accent: Color(red: 0.27, green: 0.43, blue: 0.55), onRegenerate: { generateConceptMap() })
        }
    }

    private var knowledgeGraphSection: some View {
        guard let noteID else {
            return AnyView(
                emptyCompactState(
                    title: "No note selected",
                    message: "Choose a note before building its knowledge graph."
                )
            )
        }

        let graph = knowledgeGraphManager.graphsByNoteID[noteID]
        let graphStatus = knowledgeGraphManager.generationStateByNoteID[noteID]

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    statPill(title: "Concepts", value: "\(graph?.concepts.count ?? 0)")
                    statPill(title: "Relationships", value: "\(graph?.relationships.count ?? 0)")
                    statPill(title: "Status", value: graphStatus?.isGenerating == true ? "Updating" : "Ready")

                    Spacer()

                    Button {
                        let snapshot = NoteFile(
                            id: noteID,
                            title: noteTitle,
                            content: noteText,
                            updatedAt: lastUpdatedAt ?? Date()
                        )
                        KnowledgeService.shared.ingest(note: KnowledgeIngestionRequest(
                            noteID: snapshot.id,
                            title: snapshot.title,
                            content: snapshot.content,
                            updatedAt: snapshot.updatedAt
                        ))
                    } label: {
                        Text("Update Graph")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.studySurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                quickAction("Open Graph", tint: Color(red: 0.27, green: 0.43, blue: 0.55), icon: "circle.grid.2x2") {
                        focusStudyTool(.keyConcepts)
                    }
                    quickAction("Review", tint: Color(red: 0.24, green: 0.49, blue: 0.59), icon: "arrow.counterclockwise") {
                        focusStudyTool(.flashcards)
                    }
                    quickAction("Generate Quiz", tint: Color(red: 0.60, green: 0.45, blue: 0.20), icon: "checklist") {
                        focusStudyTool(.quizGenerator)
                    }
                }

                KnowledgeGraphView(noteID: noteID, noteTitle: noteLabel)
            }
        )
    }

    private var activeRecallSection: some View {
        let prompts = studyData.activeRecallPrompts.isEmpty ? buildActiveRecallPrompts(from: noteContentSource) : studyData.activeRecallPrompts
        let prompt = prompts.isEmpty ? nil : prompts[min(activeRecallIndex, prompts.count - 1)]
        let artifact = studyData.artifacts.first(where: { $0.kind == .activeRecall }) ?? buildArtifact(
            kind: .activeRecall,
            title: "Active Recall",
            content: activeRecallText(from: prompts),
            sections: activeRecallSections(from: prompts)
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                quickAction("Practice", tint: Color(red: 0.31, green: 0.56, blue: 0.38), icon: "brain.head.profile") {
                    isActiveRecallAnswerRevealed = false
                }
                quickAction("Generate Quiz", tint: Color(red: 0.60, green: 0.45, blue: 0.20), icon: "checklist") {
                    focusStudyTool(.quizGenerator)
                }
                quickAction("Review", tint: Color(red: 0.24, green: 0.49, blue: 0.59), icon: "book.pages") {
                    focusStudyTool(.flashcards)
                }
            }

            if let prompt {
                VStack(alignment: .leading, spacing: 10) {
                    Text(prompt.prompt)
                        .font(.headline)
                    Text(isActiveRecallAnswerRevealed ? prompt.answer : "Think it through before revealing the answer.")
                        .font(.subheadline)
                        .foregroundStyle(isActiveRecallAnswerRevealed ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button { isActiveRecallAnswerRevealed.toggle() } label: {
                            Text(isActiveRecallAnswerRevealed ? "Hide Answer" : "Reveal Answer")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.studySurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            markConceptOutcome(prompt.prompt, mastered: true)
                        } label: {
                            Text("Got it")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(red: 0.27, green: 0.58, blue: 0.39))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color(red: 0.27, green: 0.58, blue: 0.39).opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            markConceptOutcome(prompt.prompt, mastered: false)
                        } label: {
                            Text("Review")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(red: 0.73, green: 0.35, blue: 0.33))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color(red: 0.73, green: 0.35, blue: 0.33).opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            activeRecallIndex = min(prompts.count - 1, activeRecallIndex + 1)
                            isActiveRecallAnswerRevealed = false
                        } label: {
                            Text("Next Prompt")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.studySurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(activeRecallIndex >= prompts.count - 1)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.studySurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                emptyCompactState(title: "No active recall prompts", message: "Generate active recall prompts from the note to practice mentally before revealing the answer.")
            }

            actionButtons(artifact: artifact, accent: Color(red: 0.32, green: 0.56, blue: 0.38), onRegenerate: { generateActiveRecallPrompts() })
        }
    }

    private var streaksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                statPill(title: "Sessions", value: "\(studyData.streaks.studySessions)")
                statPill(title: "Notes", value: "\(studyData.streaks.notesReviewed)")
                statPill(title: "Cards", value: "\(studyData.streaks.flashcardsCompleted)")
                statPill(title: "Quizzes", value: "\(studyData.streaks.quizzesCompleted)")
            }
            HStack(spacing: 8) {
                statPill(title: "Current Streak", value: "\(studyData.streaks.currentStreak) days")
                statPill(title: "Memory Items", value: "\(studyData.learningMemory.count)")
            }

            HStack(spacing: 8) {
                quickAction("Review Deck", tint: Color(red: 0.31, green: 0.56, blue: 0.38), icon: "rectangle.stack") {
                    focusStudyTool(.flashcards)
                }
                quickAction("Plan Session", tint: Color(red: 0.60, green: 0.45, blue: 0.20), icon: "calendar") {
                    focusStudyTool(.quizGenerator)
                }
                quickAction("Open Insights", tint: Color(red: 0.24, green: 0.49, blue: 0.59), icon: "chart.line.uptrend.xyaxis") {
                    focusStudyTool(.learningInsights)
                }
            }
        }
    }

    private func memorySection(title: String, items: ArraySlice<StudyMemoryEntry>, tint: Color) -> some View {
        memorySection(title: title, items: Array(items), tint: tint)
    }

    private func memorySection(title: String, items: [StudyMemoryEntry], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if items.isEmpty {
                Text("Nothing yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.concept)
                                .font(.caption.weight(.semibold))
                            Text("Mastered \(entry.masteredCount) · Missed \(entry.missedCount)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int((entry.masteryScore * 100).rounded()))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                    .padding(10)
                    .background(tint.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func conceptMapNode(_ node: StudyConceptNode, depth: Int, isLast: Bool = true) -> AnyView {
        let isExpanded = depth == 0 || expandedConceptNodeIDs.contains(node.id) || node.children.isEmpty
        let accent = depth == 0 ? Color(red: 0.27, green: 0.43, blue: 0.55) : Color(red: 0.24, green: 0.49, blue: 0.59)

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    if !node.children.isEmpty {
                        if expandedConceptNodeIDs.contains(node.id) {
                            expandedConceptNodeIDs.remove(node.id)
                        } else {
                            expandedConceptNodeIDs.insert(node.id)
                        }
                    }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text(conceptTreePrefix(depth: depth, isLast: isLast))
                            .font(.system(size: depth == 0 ? 15 : 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(depth == 0 ? accent : Color.textSecondary)
                            .frame(minWidth: depth == 0 ? 28 : 34, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(node.title)
                                    .font(depth == 0 ? .headline : .subheadline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                if !node.children.isEmpty {
                                    Text("\(node.children.count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(accent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(accent.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }

                            if depth == 0 {
                                Text("The root of the hierarchy and its major branches.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)

                        if !node.children.isEmpty {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.studySurfaceRaised,
                                accent.opacity(depth == 0 ? 0.07 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: depth == 0 ? 18 : 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: depth == 0 ? 18 : 16, style: .continuous)
                            .stroke(depth == 0 ? accent.opacity(0.24) : Color.studyBorderSoft, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(node.title)
                .accessibilityValue(node.children.isEmpty ? "Leaf node" : (isExpanded ? "Expanded" : "Collapsed"))
                .accessibilityHint(node.children.isEmpty ? "Leaf concept" : "Toggle branch visibility")

                if isExpanded && !node.children.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                            conceptMapNode(child, depth: depth + 1, isLast: index == node.children.count - 1)
                        }
                    }
                    .padding(.leading, depth == 0 ? 12 : 18)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        )
    }

    private func conceptTreePrefix(depth: Int, isLast: Bool) -> String {
        guard depth > 0 else { return "◉" }
        let indent = String(repeating: "  ", count: max(0, depth - 1))
        let connector = isLast ? "└─" : "├─"
        return "\(indent)\(connector)"
    }

    func learningMemoryText(from memory: [StudyMemoryEntry]) -> String {
        guard !memory.isEmpty else {
            return structuredSummaryBlock(
                title: "Learning Memory",
                lines: [
                    "No learning memory yet.",
                    "Generate flashcards, quizzes, or active recall prompts to begin tracking mastery."
                ]
            )
        }

        let sorted = memory.sorted(by: { lhs, rhs in
            if lhs.masteryScore == rhs.masteryScore {
                return lhs.missedCount > rhs.missedCount
            }
            return lhs.masteryScore > rhs.masteryScore
        })

        let strengths = sorted.filter { $0.masteryScore >= 0.7 }.prefix(4).map { entry in
            "\(entry.concept) - \(Int((entry.masteryScore * 100).rounded()))% mastery"
        }
        let needsReview = sorted.filter { $0.masteryScore < 0.7 }.prefix(4).map { entry in
            "\(entry.concept) - \(entry.missedCount) miss\(entry.missedCount == 1 ? "" : "es")"
        }
        let recentHistory = sorted.prefix(4).map { entry in
            let lastReview = entry.lastReviewedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
            return "\(entry.concept) | Last review: \(lastReview)"
        }

        return structuredSummaryBlock(
            title: "Learning Memory",
            lines: [
                "Mastered concepts",
                summaryBulletList(Array(strengths), emptyText: "No mastered concepts yet."),
                "Needs review",
                summaryBulletList(Array(needsReview), emptyText: "No concepts need review yet."),
                "Recent review history",
                summaryBulletList(Array(recentHistory), emptyText: "No review history yet.")
            ]
        )
    }

    func notebookGapsText(from gaps: [StudyKnowledgeGap]) -> String {
        guard !gaps.isEmpty else {
            return structuredSummaryBlock(
                title: "Knowledge Gaps",
                lines: ["No notebook gaps detected yet."]
            )
        }

        let orderedGaps = gaps.sorted { $0.priority > $1.priority }
        return structuredSummaryBlock(
            title: "Knowledge Gaps",
            lines: orderedGaps.prefix(6).enumerated().flatMap { index, gap in
                [
                    "\(index + 1). \(gap.title)",
                    gap.description,
                    "Evidence: \(gap.evidence)",
                    "Priority: \(String(format: "%.1f", gap.priority))"
                ]
            }
        )
    }

    func conceptMapText(from map: [StudyConceptNode]) -> String {
        guard let root = map.first else { return "No concept map yet." }
        return conceptMapText(root, depth: 0, isLast: true)
    }

    func conceptMapText(_ node: StudyConceptNode, depth: Int, isLast: Bool) -> String {
        let prefix = conceptTreePrefix(depth: depth, isLast: isLast)
        let label = depth == 0 ? node.title : "\(prefix) \(node.title)"
        let children = node.children.enumerated().map { index, child in
            conceptMapText(child, depth: depth + 1, isLast: index == node.children.count - 1)
        }
        return ([label] + children).joined(separator: "\n")
    }

    func activeRecallText(from prompts: [StudyActiveRecallPrompt]) -> String {
        guard !prompts.isEmpty else { return "No active recall prompts yet." }
        return prompts.enumerated().map { index, prompt in
            [
                "\(index + 1). \(prompt.prompt)",
                "Answer: \(prompt.answer)",
                prompt.hiddenText.isEmpty ? nil : "Hidden text: \(prompt.hiddenText)"
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    func learningInsightsText(from analysis: LectureCompletenessAnalysis) -> String {
        [
            "Learning Insights for \(noteLabel)",
            "Completeness Score: \(analysis.scorePercent)%",
            analysis.summary,
            "",
            "Missing Concepts",
            analysis.missingConcepts.isEmpty ? "None identified." : analysis.missingConcepts.map { "- \($0.title): \($0.shortExplanation)" }.joined(separator: "\n"),
            "",
            "Weakly Covered Concepts",
            analysis.partiallyCapturedConcepts.isEmpty ? "None identified." : analysis.partiallyCapturedConcepts.map { "- \($0.title): \($0.shortExplanation)" }.joined(separator: "\n"),
            "",
            "Suggested Review Topics",
            analysis.reviewPriority.isEmpty ? "No review priorities identified." : analysis.reviewPriority.map { "- \($0.title): \($0.reason)" }.joined(separator: "\n")
        ].joined(separator: "\n")
    }

    func learningInsightsSections(from analysis: LectureCompletenessAnalysis) -> [StudyArtifactSection] {
        [
            StudyArtifactSection(
                title: "Completeness Score",
                body: [
                    "\(analysis.scorePercent)%",
                    analysis.summary
                ].joined(separator: "\n")
            ),
            StudyArtifactSection(
                title: "Missing Concepts",
                body: analysis.missingConcepts.isEmpty ? "None identified." : analysis.missingConcepts.map { "\($0.title)\n\($0.shortExplanation)" }.joined(separator: "\n\n")
            ),
            StudyArtifactSection(
                title: "Weakly Covered Concepts",
                body: analysis.partiallyCapturedConcepts.isEmpty ? "None identified." : analysis.partiallyCapturedConcepts.map { "\($0.title)\n\($0.shortExplanation)" }.joined(separator: "\n\n")
            ),
            StudyArtifactSection(
                title: "Suggested Review Topics",
                body: analysis.reviewPriority.isEmpty ? "No review priorities identified." : analysis.reviewPriority.map { "\($0.rank). \($0.title)\n\($0.reason)" }.joined(separator: "\n\n")
            )
        ]
    }

    func flashcardSetText(from cards: [StudyFlashcard]) -> String {
        guard !cards.isEmpty else { return "No flashcards available yet." }

        return cards.enumerated().map { index, card in
            [
                "\(index + 1). \(card.type.title)",
                "Front",
                card.front,
                "Back",
                card.back,
                card.whyItMatters.isEmpty ? nil : "Context: \(card.whyItMatters)"
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    func flashcardCardText(_ card: StudyFlashcard) -> String {
        [
            card.type.title,
            "Front",
            card.front,
            "Back",
            card.back,
            card.whyItMatters.isEmpty ? nil : "Context: \(card.whyItMatters)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    func shuffleFlashcards() {
        guard !studyData.flashcards.isEmpty else { return }
        resetFlashcardSession()
        let shuffled = studyData.flashcards.shuffled()
        mutateStudyData { studyData in
            studyData.flashcards = shuffled
            studyData.lastGeneratedAt = Date()
        }
        let artifact = buildArtifact(
            kind: .flashcards,
            title: "Flashcards",
            content: flashcardSetText(from: shuffled),
            sections: flashcardSections(from: shuffled)
        )
        storeArtifact(artifact)
    }

    func flashcardSections(from cards: [StudyFlashcard]) -> [StudyArtifactSection] {
        cards.enumerated().map { index, card in
            StudyArtifactSection(
                title: "Card \(index + 1) · \(card.type.title)",
                body: [
                    "Front",
                    card.front,
                    "",
                    "Back",
                    card.back,
                    card.whyItMatters.isEmpty ? nil : "",
                    card.whyItMatters.isEmpty ? nil : "Context: \(card.whyItMatters)"
                ]
                .compactMap { $0 }
                .joined(separator: "\n")
            )
        }
    }

    func quizSetText(from quizSet: StudyQuizSet) -> String {
        guard !quizSet.questions.isEmpty else { return "No quiz questions available yet." }

        let grouped = Dictionary(grouping: quizSet.questions) { $0.type }
        let orderedTypes = StudyQuizQuestionType.allCases.filter { grouped[$0] != nil }
        var sections: [String] = [quizSet.title]
        for type in orderedTypes {
            guard let questions = grouped[type] else { continue }
            let renderedQuestions = questions.enumerated().map { index, question in
                [
                    "\(index + 1). \(question.prompt)",
                    question.options.isEmpty ? nil : "Options: \(question.options.joined(separator: " | "))",
                    "Answer: \(question.correctAnswer)",
                    question.explanation.isEmpty ? nil : "Explanation: \(question.explanation)",
                    question.keywords.isEmpty ? nil : "Keywords: \(question.keywords.joined(separator: ", "))"
                ]
                .compactMap { $0 }
                .joined(separator: "\n")
            }
            sections.append("")
            sections.append(type.title)
            sections.append(renderedQuestions.joined(separator: "\n\n"))
        }
        return sections.joined(separator: "\n")
    }

    func quizSections(from quizSet: StudyQuizSet) -> [StudyArtifactSection] {
        let grouped = Dictionary(grouping: quizSet.questions) { $0.type }
        return StudyQuizQuestionType.allCases.compactMap { type in
            guard let questions = grouped[type], !questions.isEmpty else { return nil }
            return StudyArtifactSection(
                title: type.title,
                body: questions.enumerated().map { index, question in
                    [
                        "\(index + 1). \(question.prompt)",
                        question.options.isEmpty ? nil : "Options: \(question.options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " | "))",
                        "Answer: \(question.correctAnswer)",
                        question.explanation.isEmpty ? nil : "Explanation: \(question.explanation)"
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                }.joined(separator: "\n\n")
            )
        }
    }

    func summaryText(for summaryPack: StudySummaryPack, mode: StudySummaryMode) -> String {
        switch mode {
        case .executive:
            return summaryPack.executiveSummary.isEmpty ? "No executive summary available yet." : summaryPack.executiveSummary
        case .detailed:
            return summaryPack.detailedSummary.isEmpty ? "No detailed summary available yet." : summaryPack.detailedSummary
        case .revision:
            return summaryPack.examRevisionSummary.isEmpty ? "No revision summary available yet." : summaryPack.examRevisionSummary
        }
    }

    func summarySections(from summaryPack: StudySummaryPack) -> [StudyArtifactSection] {
        [
            StudyArtifactSection(title: "Overview", body: summaryPack.executiveSummary.isEmpty ? "No executive summary available yet." : summaryPack.executiveSummary),
            StudyArtifactSection(title: "Study Notes", body: summaryPack.detailedSummary.isEmpty ? "No detailed summary available yet." : summaryPack.detailedSummary),
            StudyArtifactSection(title: "Exam Focus", body: summaryPack.examRevisionSummary.isEmpty ? "No revision summary available yet." : summaryPack.examRevisionSummary)
        ]
    }

    func keyConceptsText(from insights: StudyInsights) -> String {
        [
            "Core Concepts",
            summaryBulletList(insights.keyConcepts, emptyText: "None identified."),
            "",
            "Definitions",
            summaryBulletList(insights.importantConcepts, emptyText: "None identified."),
            "",
            "Relationships",
            summaryBulletList(insights.frequentTerms.map { "\($0.term) (\($0.count) references)" }, emptyText: "None identified."),
            "",
            "Exam Signals",
            summaryBulletList(insights.potentialExamTopics, emptyText: "None identified."),
            "",
            "Knowledge Gaps",
            summaryBulletList(insights.knowledgeGaps, emptyText: "None identified.")
        ].joined(separator: "\n")
    }

    func keyConceptSections(from insights: StudyInsights) -> [StudyArtifactSection] {
        [
            StudyArtifactSection(title: "Core Concepts", body: summaryBulletList(insights.keyConcepts, emptyText: "None identified.")),
            StudyArtifactSection(title: "Definitions", body: summaryBulletList(insights.importantConcepts, emptyText: "None identified.")),
            StudyArtifactSection(title: "Relationships", body: summaryBulletList(insights.frequentTerms.map { "\($0.term) (\($0.count) references)" }, emptyText: "None identified.")),
            StudyArtifactSection(title: "Exam Signals", body: summaryBulletList(insights.potentialExamTopics, emptyText: "None identified.")),
            StudyArtifactSection(title: "Knowledge Gaps", body: summaryBulletList(insights.knowledgeGaps, emptyText: "None identified."))
        ]
    }

    func examPrepText(from prep: StudyExamPrep) -> String {
        [
            "Likely Topics",
            summaryBulletList(prep.likelyTopics, emptyText: "None identified."),
            "",
            "Revision Guide",
            prep.condensedRevisionGuide.isEmpty ? "No revision guide generated yet." : prep.condensedRevisionGuide,
            "",
            "Practice Questions",
            prep.practiceQuestions.isEmpty ? "None generated yet." : prep.practiceQuestions.enumerated().map { index, question in
                [
                    "\(index + 1). \(question.prompt)",
                    question.options.isEmpty ? nil : "Options: \(question.options.joined(separator: " | "))",
                    "Answer: \(question.correctAnswer)",
                    question.explanation.isEmpty ? nil : "Explanation: \(question.explanation)"
                ]
                .compactMap { $0 }
                .joined(separator: "\n")
            }.joined(separator: "\n\n"),
            "",
            "Difficult Concepts",
            summaryBulletList(prep.difficultConcepts, emptyText: "None identified.")
        ].joined(separator: "\n")
    }

    func examPrepSections(from prep: StudyExamPrep) -> [StudyArtifactSection] {
        [
            StudyArtifactSection(title: "Likely Topics", body: summaryBulletList(prep.likelyTopics, emptyText: "None identified.")),
            StudyArtifactSection(title: "Condensed Revision Guide", body: prep.condensedRevisionGuide.isEmpty ? "No revision guide generated yet." : prep.condensedRevisionGuide),
            StudyArtifactSection(title: "Practice Questions", body: prep.practiceQuestions.isEmpty ? "None generated yet." : prep.practiceQuestions.enumerated().map { index, question in
                [
                    "\(index + 1). \(question.prompt)",
                    question.options.isEmpty ? nil : "Options: \(question.options.joined(separator: " | "))",
                    "Answer: \(question.correctAnswer)",
                    question.explanation.isEmpty ? nil : "Explanation: \(question.explanation)"
                ]
                .compactMap { $0 }
                .joined(separator: "\n")
            }.joined(separator: "\n\n")),
            StudyArtifactSection(title: "Difficult Concepts", body: summaryBulletList(prep.difficultConcepts, emptyText: "None identified."))
        ]
    }

    func conceptMapSections(from map: [StudyConceptNode]) -> [StudyArtifactSection] {
        guard let root = map.first else { return [StudyArtifactSection(title: "Concept Map", body: "No concept map yet.")] }
        return [
            StudyArtifactSection(title: "Hierarchy", body: conceptMapText(root, depth: 0, isLast: true)),
            StudyArtifactSection(title: "Study Lens", body: conceptMapStudyLens(from: root))
        ]
    }

    func activeRecallSections(from prompts: [StudyActiveRecallPrompt]) -> [StudyArtifactSection] {
        prompts.enumerated().map { index, prompt in
            StudyArtifactSection(
                title: "Prompt \(index + 1)",
                body: [
                    prompt.prompt,
                    "Answer: \(prompt.answer)",
                    prompt.hiddenText.isEmpty ? nil : "Hidden text: \(prompt.hiddenText)"
                ]
                .compactMap { $0 }
                .joined(separator: "\n")
            )
        }
    }

    func notebookGapSections(from gaps: [StudyKnowledgeGap]) -> [StudyArtifactSection] {
        gaps.enumerated().map { index, gap in
            StudyArtifactSection(
                title: "Gap \(index + 1)",
                body: [
                    gap.title,
                    gap.description,
                    "Evidence: \(gap.evidence)",
                    "Priority: \(gap.priority)"
                ].joined(separator: "\n")
            )
        }
    }

    func learningMemorySections(from memory: [StudyMemoryEntry]) -> [StudyArtifactSection] {
        let mastered = memory.filter { $0.masteryScore >= 0.7 }
        let missed = memory.filter { $0.missedCount > $0.masteredCount }
        return [
            StudyArtifactSection(title: "Mastered Concepts", body: mastered.isEmpty ? "None yet." : mastered.map { "\($0.concept)\nMastered: \($0.masteredCount)\nMissed: \($0.missedCount)\nLast Review: \($0.lastReviewedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")" }.joined(separator: "\n\n")),
            StudyArtifactSection(title: "Repeated Misses", body: missed.isEmpty ? "None yet." : missed.map { "\($0.concept)\nMastered: \($0.masteredCount)\nMissed: \($0.missedCount)\nLast Review: \($0.lastReviewedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")" }.joined(separator: "\n\n")),
            StudyArtifactSection(title: "Study History", body: learningMemoryText(from: memory))
        ]
    }

    func rebuildLearningMemory(from candidates: [String], currentStudyData: NoteStudyData) -> [StudyMemoryEntry] {
        let existing = currentStudyData.learningMemory.reduce(into: [String: StudyMemoryEntry]()) { result, entry in
            result[normalizeConceptKey(entry.concept)] = entry
        }
        let uniqueCandidates = dedupeStrings(candidates).prefix(12)

        return uniqueCandidates.map { concept in
            if let entry = existing[normalizeConceptKey(concept)] {
                return entry
            }

            let conceptKey = normalizeConceptKey(concept)
            let supportingReviews = currentStudyData.artifacts.filter { artifact in
                artifact.content.lowercased().contains(conceptKey)
                    || artifact.sections.contains(where: { $0.body.lowercased().contains(conceptKey) || $0.title.lowercased().contains(conceptKey) })
            }

            let reviewHistory = supportingReviews.map(\.generatedAt)
            let mastery = max(0, supportingReviews.count - supportingReviews.filter { $0.kind == .notebookKnowledgeGaps }.count)
            let misses = supportingReviews.filter { $0.kind == .notebookKnowledgeGaps }.count

            return StudyMemoryEntry(
                concept: concept,
                masteredCount: mastery,
                missedCount: misses,
                reviewHistory: reviewHistory,
                lastReviewedAt: reviewHistory.sorted().last,
                lastOutcome: misses > mastery ? .incorrect : .almost
            )
        }
    }

    func flashcardConceptCandidates(from card: StudyFlashcard) -> [String] {
        extractConceptCandidates(from: "\(card.front)\n\(card.back)", limit: 4)
    }

    func quizConceptCandidates(from quizSet: StudyQuizSet) -> [String] {
        quizSet.questions.flatMap { question in
            extractConceptCandidates(from: "\(question.prompt)\n\(question.correctAnswer)", limit: 3)
        }
    }

    private func structuredSummaryBlock(title: String, lines: [String]) -> String {
        ([title] + lines).joined(separator: "\n")
    }

    private func summaryBulletList(_ items: [String], emptyText: String) -> String {
        guard !items.isEmpty else { return emptyText }
        return items.map { "- \($0)" }.joined(separator: "\n")
    }

    private func summaryParagraph(from sentences: [String]) -> String {
        let meaningful = sentences
            .map { stripCitationMarkers($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)
        guard !meaningful.isEmpty else {
            return "No summary could be generated from the current note."
        }
        return meaningful.joined(separator: " ")
    }

    private func summaryOverviewLines(from sentences: [String], concepts: [String]) -> [String] {
        let intro = summaryParagraph(from: sentences)
        let focus = concepts.prefix(4).map(displayConcept)
        return [
            intro,
            focus.isEmpty ? "Focus: no dominant concept could be inferred." : "Focus: \(focus.joined(separator: ", "))"
        ]
    }

    private func summaryKeyIdeaLines(from sentences: [String], concepts: [String]) -> [String] {
        let candidates = sentences.prefix(4).enumerated().map { index, sentence in
            "\(index + 1). \(sentenceFragment(stripCitationMarkers(sentence)))"
        }
        if candidates.isEmpty {
            return concepts.prefix(4).map(displayConcept)
        }
        return candidates
    }

    private func summaryDefinitionLines(from concepts: [String], sentences: [String]) -> [String] {
        let joinedText = sentences.joined(separator: " ")
        return concepts.prefix(4).map { concept in
            let sentence = sentenceContaining(concept, in: joinedText)
            let fallback = sentences.first ?? concept
            let resolved = sentence.isEmpty ? fallback : sentence
            return "\(displayConcept(concept)): \(sentenceFragment(resolved))"
        }
    }

    private func summaryRememberLines(from sentences: [String], concepts: [String]) -> [String] {
        var lines: [String] = []
        if let firstConcept = concepts.first {
            lines.append("Anchor the note around \(displayConcept(firstConcept)).")
        }
        if let firstSentence = sentences.first {
            lines.append("Re-read: \(sentenceFragment(stripCitationMarkers(firstSentence)))")
        }
        return lines
    }

    private func summaryMistakeLines(from sentences: [String], concepts: [String]) -> [String] {
        guard let firstConcept = concepts.first else {
            return ["Do not memorize isolated terms without the surrounding explanation."]
        }
        return [
            "Avoid treating \(displayConcept(firstConcept)) as a standalone label.",
            "Connect it to the surrounding explanation: \(sentenceFragment(bestSentence(for: firstConcept, in: sentences) ?? sentences.first ?? firstConcept))"
        ]
    }

    private func summaryQuickReviewLines(from concepts: [String], sentences: [String]) -> [String] {
        let joinedText = sentences.joined(separator: " ")
        var lines: [String] = []
        for concept in concepts.prefix(3) {
            let sentence = sentenceContaining(concept, in: joinedText)
            let fallback = sentences.first ?? concept
            lines.append("\(displayConcept(concept)) - \(sentenceFragment(sentence.isEmpty ? fallback : sentence))")
        }
        return lines
    }

    private func conceptMapStudyLens(from root: StudyConceptNode) -> String {
        let branches = root.children.prefix(4).map { $0.title }
        guard !branches.isEmpty else {
            return "No deeper branches were identified yet."
        }
        return [
            "Root",
            root.title,
            "",
            "Primary branches",
            summaryBulletList(Array(branches), emptyText: "No primary branches.")
        ].joined(separator: "\n")
    }

    private func comparisonAnswer(first: String, second: String, sentences: [String], concepts: [String]) -> String {
        let joinedText = sentences.joined(separator: " ")
        let firstSentence = concepts.first.map { sentenceContaining($0, in: joinedText) }.flatMap { $0.isEmpty ? nil : $0 } ?? sentences.first ?? first
        let secondSentence = concepts.dropFirst().first.map { sentenceContaining($0, in: joinedText) }.flatMap { $0.isEmpty ? nil : $0 } ?? sentences.dropFirst().first ?? second
        return "\(first) and \(second) are related because \(sentenceFragment(firstSentence)) while \(sentenceFragment(secondSentence))."
    }

    private func applicationAnswer(from sentence: String, concept: String) -> String {
        let cleaned = sentenceFragment(stripCitationMarkers(sentence))
        return "Apply \(displayConcept(concept)) by using it in a new context, for example: \(cleaned)"
    }

    private func relationshipAnswer(first: StudyKnowledgeItem, second: StudyKnowledgeItem, relationships: [StudyKnowledgeRelationship]) -> String {
        if let link = relationships.first(where: {
            ($0.sourceTitle == first.title && $0.targetTitle == second.title)
            || ($0.sourceTitle == second.title && $0.targetTitle == first.title)
        }) {
            return "\(first.title) \(relationshipLabel(for: link.relation)) \(second.title) because \(first.summary.isEmpty ? first.title : first.summary)."
        }

        return "\(first.title) and \(second.title) belong to the same study cluster and should be connected in your explanation."
    }

    private func relationshipLabel(for relation: String) -> String {
        switch relation {
        case "dependsOn":
            return "depends on"
        case "leadsTo":
            return "leads to"
        case "illustrates":
            return "illustrates"
        case "contrastsWith":
            return "contrasts with"
        default:
            return "is related to"
        }
    }

    func buildArtifact(kind: StudyArtifactKind, title: String, content: String, sections: [StudyArtifactSection]) -> StudyArtifact {
        StudyArtifact(
            kind: kind,
            title: title,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            sections: sections,
            sourceNoteID: noteID,
            sourceNoteTitle: noteLabel
        )
    }

    func storeArtifact(_ artifact: StudyArtifact) {
        mutateStudyData { studyData in
            upsert(&studyData.artifacts, artifact: artifact)
            studyData.lastGeneratedAt = artifact.generatedAt
        }
    }

    func saveArtifact(_ artifact: StudyArtifact) {
        storeArtifact(artifact)
        transientStatusMessage = "\(artifact.title) saved locally."
    }

    private func upsert(_ artifacts: inout [StudyArtifact], artifact: StudyArtifact) {
        if let index = artifacts.firstIndex(where: { $0.kind == artifact.kind }) {
            artifacts[index] = artifact
        } else {
            artifacts.append(artifact)
        }
    }

    private func dedupeStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = normalizeConceptKey(trimmed)
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    func displayConcept(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }
        return trimmed
            .split(separator: " ")
            .map { word in
                let token = String(word)
                return token.uppercased() == token ? token : token.prefix(1).uppercased() + token.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    func sentenceFragment(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count <= 120 { return clean }
        return String(clean.prefix(117)) + "..."
    }

    func stripCitationMarkers(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "Generated:", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "Summary:", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "Question:", with: "", options: [.caseInsensitive, .diacriticInsensitive])
            .replacingOccurrences(of: "Answer:", with: "", options: [.caseInsensitive, .diacriticInsensitive])
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func bestSentence(for concept: String, in sentences: [String]) -> String? {
        let normalized = normalizeConceptKey(concept)
        return sentences.first(where: { normalizeConceptKey($0).contains(normalized) })
            ?? sentences.first(where: { $0.lowercased().contains(concept.lowercased()) })
    }

    func quizExplanation(from sentence: String, concept: String) -> String {
        let cleaned = stripCitationMarkers(sentence)
        let lower = cleaned.lowercased()
        if let range = lower.range(of: concept.lowercased()) {
            let tail = cleaned[range.upperBound...]
            let answer = stripRecallPrefixes(String(tail))
            if !answer.isEmpty {
                return answer
            }
        }
        return sentenceFragment(cleaned)
    }

    func quizShortAnswer(from sentence: String, concept: String) -> String {
        let cleaned = stripCitationMarkers(sentence)
        let answer = stripRecallPrefixes(cleaned)
        return answer.isEmpty ? displayConcept(concept) : answer
    }

    func condensedAnswer(from sentence: String, for concept: String) -> String {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if let range = lower.range(of: concept.lowercased()) {
            let after = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = stripRecallPrefixes(after)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return sentenceFragment(trimmed)
    }

    func activeRecallQuestion(for concept: String, sentence: String) -> String {
        let label = displayConcept(concept)
        let lower = sentence.lowercased()

        if lower.contains(" is ") || lower.contains(" are ") || lower.contains(" means ") || lower.contains(" refers to ") || lower.contains(" describes ") {
            return "What is \(label)?"
        }

        if lower.contains(" involves ") || lower.contains(" uses ") || lower.contains(" helps ") || lower.contains(" works ") {
            return "How does \(label) work?"
        }

        if lower.contains(" causes ") || lower.contains(" leads to ") || lower.contains(" results in ") {
            return "What does \(label) lead to?"
        }

        return "Explain \(label) in your own words."
    }

    func scoreRecallSentence(_ sentence: String, concepts: [String]) -> Int {
        let lower = sentence.lowercased()
        return concepts.reduce(into: 0) { result, concept in
            if lower.contains(concept.lowercased()) {
                result += 3
            }
        } + min(4, sentence.split { $0.isWhitespace }.count / 8)
    }

    func stripRecallPrefixes(_ text: String) -> String {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":-—"))

        let prefixes = [
            "is ",
            "are ",
            "was ",
            "were ",
            "means ",
            "means that ",
            "refers to ",
            "describes ",
            "involves ",
            "uses ",
            "helps ",
            "works ",
            "causes ",
            "leads to ",
            "results in ",
            "can be ",
            "is a ",
            "is an ",
            "is the ",
            "are the "
        ]

        for prefix in prefixes {
            if cleaned.lowercased().hasPrefix(prefix) {
                return sentenceFragment(String(cleaned.dropFirst(prefix.count)))
            }
        }

        return sentenceFragment(String(cleaned))
    }

    func buildDetailedSummary(from text: String, concepts: [String], sentences: [String]) -> String {
        var sections: [String] = []
        sections.append("Core ideas")
        sections.append(concepts.prefix(5).map { "• \($0)" }.joined(separator: "\n"))
        sections.append("\nKey relationships")
        sections.append(sentences.prefix(4).map { "• \(sentenceFragment($0))" }.joined(separator: "\n"))
        sections.append("\nStudy note")
        sections.append(summarySentence(for: text, missingCount: 0, coveredCount: concepts.count))
        return sections.joined(separator: "\n")
    }

    func buildExamRevisionSummary(from text: String, concepts: [String]) -> String {
        let likely = buildExamTopics(from: text)
        return [
            "Exam revision summary",
            "Topics to know: \(likely.joined(separator: ", "))",
            "Key terms: \(concepts.prefix(6).map(displayConcept).joined(separator: ", "))",
            "Focus on definitions, links between ideas, and one example for each concept."
        ].joined(separator: "\n")
    }

    func buildExamTopics(from text: String) -> [String] {
        let concepts = extractConceptCandidates(from: text, limit: 12)
        return Array(concepts.prefix(5).map(displayConcept))
    }

    func summarySentence(for text: String, missingCount: Int, coveredCount: Int) -> String {
        let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        return "This note spans \(wordCount) words, \(coveredCount) reinforced ideas, and \(missingCount) likely prerequisites to review."
    }

    func extractConceptCandidates(from text: String, limit: Int) -> [String] {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "because", "but", "by", "can", "could", "did", "do", "does", "for", "from", "had", "has", "have", "how", "i", "if", "in", "into", "is", "it", "its", "may", "might", "of", "on", "or", "our", "so", "than", "that", "the", "their", "there", "these", "this", "those", "to", "was", "were", "what", "when", "where", "which", "who", "why", "with", "you", "your"
        ]

        var counts: [String: Int] = [:]
        let words = normalizedText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for word in words where word.count > 2 {
            let lower = word.lowercased()
            guard !stopWords.contains(lower) else { continue }
            counts[lower, default: 0] += 1
        }

        for index in 0..<(max(0, words.count - 1)) {
            let first = words[index].lowercased()
            let second = words[index + 1].lowercased()
            guard first.count > 2, second.count > 2 else { continue }
            guard !stopWords.contains(first), !stopWords.contains(second) else { continue }
            let phrase = "\(first) \(second)"
            counts[phrase, default: 0] += 2
        }

        return counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .prefix(limit)
            .map { displayConcept($0.key) }
    }

    func extractNotebookConcepts(from text: String) -> [String] {
        Array(conceptFrequency(in: text).keys.prefix(10).map(displayConcept))
    }

    func conceptFrequency(in text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for concept in extractConceptCandidates(from: text, limit: 30) {
            counts[normalizeConceptKey(concept), default: 0] += 1
        }
        return counts
    }

    var notebookConceptFrequency: [String: Int] {
        var counts: [String: Int] = [:]
        for noteText in notebookNoteTexts {
            let concept = extractConceptCandidates(from: noteText, limit: 12)
            for item in concept {
                counts[normalizeConceptKey(item), default: 0] += 1
            }
        }
        return counts
    }

    func prerequisiteGaps(for noteText: String, notebookText: String) -> [StudyKnowledgeGap] {
        let lower = noteText.lowercased()
        var gaps: [StudyKnowledgeGap] = []

        for (topic, prerequisites) in prerequisiteMap {
            guard lower.contains(topic) || extractConceptCandidates(from: noteText, limit: 20).map(normalizeConceptKey).contains(normalizeConceptKey(topic)) else { continue }
            for prerequisite in prerequisites where !lower.contains(prerequisite) {
                let relatedCount = notebookConceptFrequency[normalizeConceptKey(prerequisite), default: 0]
                if relatedCount > 0 {
                    gaps.append(
                        StudyKnowledgeGap(
                            title: "\(displayConcept(topic)) needs \(displayConcept(prerequisite))",
                            description: "You mention \(displayConcept(topic)), but \(displayConcept(prerequisite)) is barely covered.",
                            evidence: "Notebook-wide use suggests this is a recurring prerequisite.",
                            priority: Double(relatedCount)
                        )
                    )
                }
            }
        }

        return gaps
    }

    var prerequisiteMap: [String: [String]] {
        [
            "neural networks": ["gradient descent", "backpropagation", "activation function", "loss function"],
            "machine learning": ["training data", "loss function", "overfitting", "gradient descent"],
            "regression": ["loss function", "feature", "prediction"],
            "statistics": ["probability", "mean", "variance"],
            "probability": ["distribution", "random variable", "expectation"],
            "calculus": ["derivative", "chain rule", "gradient"],
            "database": ["normalization", "index", "transaction"],
            "operating system": ["process", "thread", "memory"],
            "reinforcement learning": ["reward", "policy", "value function"],
            "linear algebra": ["matrix", "vector", "eigenvalue"]
        ]
    }

    func dedupeGaps(_ gaps: [StudyKnowledgeGap]) -> [StudyKnowledgeGap] {
        var seen = Set<String>()
        var results: [StudyKnowledgeGap] = []
        for gap in gaps.sorted(by: { $0.priority > $1.priority }) {
            let key = normalizeConceptKey(gap.title)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(gap)
        }
        return results
    }

    func sanitizeFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        return String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    func normalizeConceptKey(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func splitSentences(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func sentenceContaining(_ concept: String, in text: String) -> String {
        let lower = concept.lowercased()
        return splitSentences(text).first(where: { $0.lowercased().contains(lower) }) ?? ""
    }

    private func toolTint(forSupplemental section: SupplementalStudySection) -> Color {
        switch section {
        case .teachMe:
            return Color(red: 0.24, green: 0.49, blue: 0.59)
        case .learningMemory:
            return Color(red: 0.24, green: 0.49, blue: 0.59)
        case .knowledgeGaps:
            return Color(red: 0.73, green: 0.35, blue: 0.33)
        case .examPrep:
            return Color(red: 0.60, green: 0.45, blue: 0.20)
        case .conceptMap:
            return Color(red: 0.27, green: 0.43, blue: 0.55)
        case .knowledgeGraph:
            return Color(red: 0.23, green: 0.49, blue: 0.59)
        case .activeRecall:
            return Color(red: 0.31, green: 0.56, blue: 0.38)
        case .streaks:
            return Color(red: 0.54, green: 0.38, blue: 0.61)
        }
    }

    private func supplementalSubtitle(for section: SupplementalStudySection) -> String {
        switch section {
        case .teachMe:
            return "Turn a gap into one short question and feedback."
        case .learningMemory:
            return "Track what feels solid and what still needs review."
        case .knowledgeGaps:
            return "Compare the active note with the rest of the notebook."
        case .examPrep:
            return "Produce likely topics, revision notes, and practice prompts."
        case .conceptMap:
            return "See the note as a hierarchy of connected ideas."
        case .knowledgeGraph:
            return "Build a persistent graph of concepts and relationships."
        case .activeRecall:
            return "Hide the answer first, then reveal it only after you think."
        case .streaks:
            return "Keep lightweight study stats without clutter."
        }
    }

    private func teachMeStateLabel(_ state: TeachMeSessionState) -> String {
        switch state {
        case .idle:
            return "Idle"
        case .question:
            return "Question"
        case .answering:
            return "Answering"
        case .feedback:
            return "Feedback"
        case .complete:
            return "Complete"
        }
    }

    private func teachMeEvaluationTitle(_ evaluation: TeachMeEvaluation) -> String {
        switch evaluation {
        case .correct:
            return "Correct"
        case .partiallyCorrect:
            return "Partially Correct"
        case .incorrect:
            return "Needs Review"
        }
    }

}

enum StudyCardType: String, CaseIterable, Codable, Identifiable {
    case definition
    case questionAnswer = "question_answer"
    case concept
    case cloze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .definition:
            return "Definition"
        case .questionAnswer:
            return "Q&A"
        case .concept:
            return "Concept"
        case .cloze:
            return "Cloze"
        }
    }

    var tint: Color {
        switch self {
        case .definition:
            return Color(red: 0.33, green: 0.57, blue: 0.74)
        case .questionAnswer:
            return Color(red: 0.33, green: 0.63, blue: 0.50)
        case .concept:
            return Color(red: 0.74, green: 0.51, blue: 0.32)
        case .cloze:
            return Color(red: 0.62, green: 0.42, blue: 0.66)
        }
    }
}

enum StudyQuestionGenerationAction: String, Codable, CaseIterable, Identifiable {
    case generateFlashcard
    case recallQuestion
    case understandingQuestion
    case applicationQuestion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generateFlashcard:
            return "Generate Flashcard"
        case .recallQuestion:
            return "Recall Question"
        case .understandingQuestion:
            return "Understanding Question"
        case .applicationQuestion:
            return "Application Question"
        }
    }
}

enum StudyQuestionCognitiveLevel: String, Codable, CaseIterable, Identifiable {
    case recall
    case understanding
    case application

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recall:
            return "Recall"
        case .understanding:
            return "Understanding"
        case .application:
            return "Application"
        }
    }
}

struct StudyQuestionSourceReference: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var noteID: UUID?
    var rangeLocation: Int
    var rangeLength: Int
    var excerpt: String

    var range: NSRange {
        NSRange(location: rangeLocation, length: rangeLength)
    }

    init(noteID: UUID? = nil, range: NSRange, excerpt: String) {
        self.noteID = noteID
        self.rangeLocation = range.location
        self.rangeLength = range.length
        self.excerpt = excerpt
    }
}

struct StudyQuestionAnswerRecord: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var answer: String
    var isCorrect: Bool
    var answeredAt: Date = Date()
}

struct StudyFlashcard: Identifiable, Codable, Equatable {
    var id: UUID
    var type: StudyCardType
    var front: String
    var back: String
    var whyItMatters: String
    var conceptIDs: [String]
    var sourceConcept: String
    var cognitiveLevel: StudyQuestionCognitiveLevel
    var sourceReferences: [StudyQuestionSourceReference]
    var generationAction: StudyQuestionGenerationAction

    init(
        id: UUID = UUID(),
        type: StudyCardType,
        front: String,
        back: String,
        whyItMatters: String = "",
        conceptIDs: [String] = [],
        sourceConcept: String = "",
        cognitiveLevel: StudyQuestionCognitiveLevel = .recall,
        sourceReferences: [StudyQuestionSourceReference] = [],
        generationAction: StudyQuestionGenerationAction = .generateFlashcard
    ) {
        self.id = id
        self.type = type
        self.front = front
        self.back = back
        self.whyItMatters = whyItMatters
        self.conceptIDs = conceptIDs
        self.sourceConcept = sourceConcept
        self.cognitiveLevel = cognitiveLevel
        self.sourceReferences = sourceReferences
        self.generationAction = generationAction
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case front
        case back
        case whyItMatters
        case conceptIDs
        case sourceConcept
        case cognitiveLevel
        case sourceReferences
        case generationAction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decode(StudyCardType.self, forKey: .type)
        front = try container.decode(String.self, forKey: .front)
        back = try container.decode(String.self, forKey: .back)
        whyItMatters = try container.decodeIfPresent(String.self, forKey: .whyItMatters) ?? ""
        conceptIDs = try container.decodeIfPresent([String].self, forKey: .conceptIDs) ?? []
        sourceConcept = try container.decodeIfPresent(String.self, forKey: .sourceConcept) ?? conceptIDs.first ?? ""
        cognitiveLevel = try container.decodeIfPresent(StudyQuestionCognitiveLevel.self, forKey: .cognitiveLevel) ?? .recall
        sourceReferences = try container.decodeIfPresent([StudyQuestionSourceReference].self, forKey: .sourceReferences) ?? []
        generationAction = try container.decodeIfPresent(StudyQuestionGenerationAction.self, forKey: .generationAction) ?? .generateFlashcard
    }
}

enum StudyQuizQuestionType: String, CaseIterable, Codable, Identifiable {
    case multipleChoice = "multiple_choice"
    case trueFalse = "true_false"
    case shortAnswer = "short_answer"
    case fillInTheBlank = "fill_in_the_blank"
    case conceptualUnderstanding = "conceptual_understanding"
    case application = "application"
    case comparison = "comparison"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multipleChoice:
            return "Multiple Choice"
        case .trueFalse:
            return "True / False"
        case .shortAnswer:
            return "Short Answer"
        case .fillInTheBlank:
            return "Fill in the Blank"
        case .conceptualUnderstanding:
            return "Conceptual Understanding"
        case .application:
            return "Application"
        case .comparison:
            return "Comparison"
        }
    }
}

struct StudyQuizQuestion: Identifiable, Codable, Equatable {
    var id: UUID
    var type: StudyQuizQuestionType
    var prompt: String
    var options: [String]
    var correctAnswer: String
    var explanation: String
    var keywords: [String]
    var conceptIDs: [String]
    var sourceConcept: String
    var cognitiveLevel: StudyQuestionCognitiveLevel
    var sourceReferences: [StudyQuestionSourceReference]
    var generationAction: StudyQuestionGenerationAction
    var answerHistory: [StudyQuestionAnswerRecord]

    init(
        id: UUID = UUID(),
        type: StudyQuizQuestionType,
        prompt: String,
        options: [String] = [],
        correctAnswer: String,
        explanation: String = "",
        keywords: [String] = [],
        conceptIDs: [String] = [],
        sourceConcept: String = "",
        cognitiveLevel: StudyQuestionCognitiveLevel = .recall,
        sourceReferences: [StudyQuestionSourceReference] = [],
        generationAction: StudyQuestionGenerationAction = .recallQuestion,
        answerHistory: [StudyQuestionAnswerRecord] = []
    ) {
        self.id = id
        self.type = type
        self.prompt = prompt
        self.options = options
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.keywords = keywords
        self.conceptIDs = conceptIDs
        self.sourceConcept = sourceConcept
        self.cognitiveLevel = cognitiveLevel
        self.sourceReferences = sourceReferences
        self.generationAction = generationAction
        self.answerHistory = answerHistory
    }

    func recordingAnswer(_ answer: String, isCorrect: Bool, answeredAt: Date = Date()) -> StudyQuizQuestion {
        var copy = self
        copy.answerHistory.append(StudyQuestionAnswerRecord(answer: answer, isCorrect: isCorrect, answeredAt: answeredAt))
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case prompt
        case options
        case correctAnswer
        case explanation
        case keywords
        case conceptIDs
        case sourceConcept
        case cognitiveLevel
        case sourceReferences
        case generationAction
        case answerHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try container.decode(StudyQuizQuestionType.self, forKey: .type)
        prompt = try container.decode(String.self, forKey: .prompt)
        options = try container.decodeIfPresent([String].self, forKey: .options) ?? []
        correctAnswer = try container.decode(String.self, forKey: .correctAnswer)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        conceptIDs = try container.decodeIfPresent([String].self, forKey: .conceptIDs) ?? []
        sourceConcept = try container.decodeIfPresent(String.self, forKey: .sourceConcept) ?? conceptIDs.first ?? keywords.first ?? ""
        cognitiveLevel = try container.decodeIfPresent(StudyQuestionCognitiveLevel.self, forKey: .cognitiveLevel) ?? .recall
        sourceReferences = try container.decodeIfPresent([StudyQuestionSourceReference].self, forKey: .sourceReferences) ?? []
        generationAction = try container.decodeIfPresent(StudyQuestionGenerationAction.self, forKey: .generationAction) ?? .recallQuestion
        answerHistory = try container.decodeIfPresent([StudyQuestionAnswerRecord].self, forKey: .answerHistory) ?? []
    }
}

struct StudyQuizSet: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var generatedAt: Date = Date()
    var questions: [StudyQuizQuestion]
}

struct StudyQuestionGenerationSource: Equatable {
    var noteID: UUID?
    var selectedText: String
    var noteContext: String
    var sourceRange: NSRange

    var sourceExcerpt: String {
        selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct StudyQuestionGenerationOutput: Equatable {
    var flashcard: StudyFlashcard?
    var question: StudyQuizQuestion?
}

struct StudyGeneratedInsertion: Equatable {
    var content: String
    var feature: String
    var sourceConcept: String?
    var sourceItemID: String?
    var sourceItemTitle: String?
    var sourceExcerpt: String
}

protocol StudyQuestionProviding {
    func generateStudyQuestion(
        action: StudyQuestionGenerationAction,
        source: StudyQuestionGenerationSource
    ) async -> StudyQuestionGenerationOutput
}

struct LiveStudyQuestionProvider: StudyQuestionProviding {
    func generateStudyQuestion(
        action: StudyQuestionGenerationAction,
        source: StudyQuestionGenerationSource
    ) async -> StudyQuestionGenerationOutput {
        await AIService.shared.generateStudyQuestion(action: action, source: source)
    }
}

struct StudyQuestionGenerationEngine {
    var provider: any StudyQuestionProviding

    init(provider: any StudyQuestionProviding = LiveStudyQuestionProvider()) {
        self.provider = provider
    }

    func generate(
        action: StudyQuestionGenerationAction,
        source: StudyQuestionGenerationSource
    ) async -> StudyQuestionGenerationOutput {
        await provider.generateStudyQuestion(action: action, source: source)
    }
}

struct StudyTutorQuestion: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var prompt: String
    var expectedAnswer: String
    var keyPoints: [String] = []
    var explanation: String = ""
    var concept: String = ""
    var conceptIDs: [String] = []
}

struct StudyTerm: Codable, Equatable, Identifiable {
    var term: String
    var count: Int

    var id: String { term }
}

struct StudyInsights: Codable, Equatable {
    var keyConcepts: [String] = []
    var importantConcepts: [String] = []
    var frequentTerms: [StudyTerm] = []
    var potentialExamTopics: [String] = []
    var knowledgeGaps: [String] = []
}

struct StudyQuizAttempt: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var quizSetID: UUID
    var quizTitle: String
    var attemptedAt: Date = Date()
    var score: Int
    var totalQuestions: Int
    var percentage: Double
}

struct StudyTestMeSessionRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var completedAt: Date = Date()
    var score: Int
    var totalQuestions: Int
    var concepts: [String] = []
}

struct StudyProgress: Codable, Equatable {
    var flashcardsCreated: Int = 0
    var flashcardsReviewed: Int = 0
    var quizAttempts: [StudyQuizAttempt] = []
    var testMeSessions: [StudyTestMeSessionRecord] = []
}

struct StudyMemoryEntry: Codable, Equatable, Identifiable {
    var concept: String
    var masteredCount: Int = 0
    var missedCount: Int = 0
    var reviewHistory: [Date] = []
    var lastReviewedAt: Date?
    var lastOutcome: StudyTutorVerdict = .almost

    var id: String { concept }

    var masteryScore: Double {
        let total = masteredCount + missedCount
        guard total > 0 else { return 0.5 }
        return Double(masteredCount) / Double(total)
    }
}

struct StudyStreakSummary: Codable, Equatable {
    var studySessions: Int = 0
    var notesReviewed: Int = 0
    var flashcardsCompleted: Int = 0
    var quizzesCompleted: Int = 0
    var currentStreak: Int = 0
    var lastStudiedAt: Date?
}

struct StudyExamPrep: Codable, Equatable {
    var likelyTopics: [String] = []
    var condensedRevisionGuide: String = ""
    var practiceQuestions: [StudyQuizQuestion] = []
    var difficultConcepts: [String] = []
}

struct StudySummaryPack: Codable, Equatable {
    var executiveSummary: String = ""
    var detailedSummary: String = ""
    var examRevisionSummary: String = ""
}

struct StudyConceptNode: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var children: [StudyConceptNode] = []
}

struct StudyActiveRecallPrompt: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var prompt: String
    var answer: String
    var hiddenText: String = ""
}

enum StudyKnowledgeGapStatus: String, Codable, Equatable {
    case active
    case ignored
    case resolved

    var displayTitle: String {
        switch self {
        case .active:
            return "Active"
        case .ignored:
            return "Ignored"
        case .resolved:
            return "Resolved"
        }
    }
}

struct StudyKnowledgeGap: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var description: String
    var evidence: String
    var priority: Double
    var status: StudyKnowledgeGapStatus
    var detectedAt: Date
    var updatedAt: Date
    var detectionHeuristic: String
    var resolutionMethod: String?

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        evidence: String,
        priority: Double,
        status: StudyKnowledgeGapStatus = .active,
        detectedAt: Date = Date(),
        updatedAt: Date = Date(),
        detectionHeuristic: String = "studyKnowledgeGapAnalysis",
        resolutionMethod: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.evidence = evidence
        self.priority = priority
        self.status = status
        self.detectedAt = detectedAt
        self.updatedAt = updatedAt
        self.detectionHeuristic = detectionHeuristic
        self.resolutionMethod = resolutionMethod
    }

    var normalizedKey: String {
        StudyKnowledgeGap.normalizedKey(for: title)
    }

    var supportingEvidenceSummary: String {
        evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No supporting evidence captured."
            : evidence
    }

    func updatingStatus(_ status: StudyKnowledgeGapStatus, resolutionMethod: String? = nil, now: Date = Date()) -> StudyKnowledgeGap {
        var copy = self
        copy.status = status
        copy.updatedAt = now
        copy.resolutionMethod = resolutionMethod
        return copy
    }

    static func merge(existing: [StudyKnowledgeGap], detected: [StudyKnowledgeGap], now: Date = Date()) -> [StudyKnowledgeGap] {
        var gapsByKey = existing.reduce(into: [String: StudyKnowledgeGap]()) { result, gap in
            let key = gap.normalizedKey
            guard !key.isEmpty else { return }
            result[key] = gap
        }

        for detectedGap in detected {
            let key = detectedGap.normalizedKey
            guard !key.isEmpty else { continue }
            if var existingGap = gapsByKey[key] {
                existingGap.title = detectedGap.title
                existingGap.description = detectedGap.description
                existingGap.evidence = detectedGap.evidence
                existingGap.priority = detectedGap.priority
                existingGap.detectionHeuristic = detectedGap.detectionHeuristic
                existingGap.updatedAt = now
                gapsByKey[key] = existingGap
            } else {
                var activeGap = detectedGap
                activeGap.status = .active
                activeGap.detectedAt = now
                activeGap.updatedAt = now
                gapsByKey[key] = activeGap
            }
        }

        return gapsByKey.values.sorted { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status.rawValue < rhs.status.rawValue }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    static func normalizedKey(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case evidence
        case priority
        case status
        case detectedAt
        case updatedAt
        case detectionHeuristic
        case resolutionMethod
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        evidence = try container.decode(String.self, forKey: .evidence)
        priority = try container.decode(Double.self, forKey: .priority)
        status = try container.decodeIfPresent(StudyKnowledgeGapStatus.self, forKey: .status) ?? .active
        detectedAt = try container.decodeIfPresent(Date.self, forKey: .detectedAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? detectedAt
        detectionHeuristic = try container.decodeIfPresent(String.self, forKey: .detectionHeuristic) ?? "studyKnowledgeGapAnalysis"
        resolutionMethod = try container.decodeIfPresent(String.self, forKey: .resolutionMethod)
    }
}

struct KnowledgeGapDisplayModel: Identifiable, Equatable {
    let id: UUID
    let concept: String
    let reason: String
    let supportingEvidenceSummary: String
    let status: StudyKnowledgeGapStatus

    init(gap: StudyKnowledgeGap) {
        id = gap.id
        concept = gap.title
        reason = gap.description
        supportingEvidenceSummary = gap.supportingEvidenceSummary
        status = gap.status
    }
}

struct PossibleKnowledgeGapCard: View {
    let model: KnowledgeGapDisplayModel
    let onExplain: () -> Void
    let onIgnore: () -> Void
    let onMarkUnderstood: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("⚠ Possible Knowledge Gap")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.73, green: 0.35, blue: 0.33))

                Spacer(minLength: 8)

                Text(model.status.displayTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.studySurfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            Text("You may need to revisit “\(model.concept)”.")
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 5) {
                Text("Reason:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Evidence:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(model.supportingEvidenceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Explain", action: onExplain)
                    .buttonStyle(.borderedProminent)
                Button("Ignore", action: onIgnore)
                    .buttonStyle(.borderless)
                Button("Mark Understood", action: onMarkUnderstood)
                    .buttonStyle(.borderless)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.studyBorderSoft, lineWidth: 1)
        )
    }
}

struct NoteStudyData: Codable, Equatable {
    var flashcards: [StudyFlashcard] = []
    var quizSets: [StudyQuizSet] = []
    var tutorQuestions: [StudyTutorQuestion] = []
    var insights: StudyInsights = StudyInsights()
    var learningInsights: LectureCompletenessAnalysis = LectureCompletenessAnalysis()
    var artifacts: [StudyArtifact] = []
    var knowledgeSnapshot: StudyKnowledgeSnapshot = StudyKnowledgeSnapshot()
    var knowledgeSignature: String = ""
    var progress: StudyProgress = StudyProgress()
    var learningMemory: [StudyMemoryEntry] = []
    var streaks: StudyStreakSummary = StudyStreakSummary()
    var examPrep: StudyExamPrep = StudyExamPrep()
    var summaryPack: StudySummaryPack = StudySummaryPack()
    var conceptMap: [StudyConceptNode] = []
    var activeRecallPrompts: [StudyActiveRecallPrompt] = []
    var notebookKnowledgeGaps: [StudyKnowledgeGap] = []
    var teachMeSession: TeachMeSession?
    var lastGeneratedAt: Date?
}

extension StudyInsights {
    var isEmpty: Bool {
        keyConcepts.isEmpty
            && importantConcepts.isEmpty
            && frequentTerms.isEmpty
            && potentialExamTopics.isEmpty
            && knowledgeGaps.isEmpty
    }
}

extension NoteStudyData {
    var hasMaterials: Bool {
        !flashcards.isEmpty
            || !quizSets.isEmpty
            || !tutorQuestions.isEmpty
            || !insights.isEmpty
            || learningInsights.hasResults
            || !artifacts.isEmpty
    }
}

extension StudyProgress {
    var averageQuizScore: Int {
        guard !quizAttempts.isEmpty else { return 0 }
        let total = quizAttempts.reduce(0.0) { $0 + $1.percentage }
        return Int((total / Double(quizAttempts.count)).rounded())
    }

    var bestQuizScore: Int {
        Int(quizAttempts.map(\.percentage).max() ?? 0)
    }
}

struct PracticeQuizSession {
    let quizSetID: UUID
    var answers: [UUID: String] = [:]
    var isSubmitted = false
    var score: Int = 0
    var didPersistAttempt = false
}

enum StudyTutorVerdict: String, Codable {
    case correct
    case almost
    case incorrect

    var title: String {
        switch self {
        case .correct:
            return "Correct"
        case .almost:
            return "Almost There"
        case .incorrect:
            return "Review Needed"
        }
    }

    var tint: Color {
        switch self {
        case .correct:
            return Color(red: 0.27, green: 0.58, blue: 0.39)
        case .almost:
            return Color(red: 0.78, green: 0.58, blue: 0.25)
        case .incorrect:
            return Color(red: 0.73, green: 0.35, blue: 0.33)
        }
    }
}

struct StudyTutorEvaluation {
    var verdict: StudyTutorVerdict
    var feedback: String
    var explanation: String
    var modelAnswer: String
    var awardedPoint: Int
}

struct StudyTutorTurn {
    var questionID: UUID
    var concept: String
    var answer: String
    var evaluation: StudyTutorEvaluation
}

struct StudyTutorSessionState {
    var isActive = false
    var currentIndex = 0
    var answerText = ""
    var isEvaluating = false
    var currentEvaluation: StudyTutorEvaluation?
    var turns: [StudyTutorTurn] = []
    var score = 0
    var isComplete = false
    var didPersistCompletion = false
}

enum StudyStatusTone {
    case neutral
    case success
    case error

    var tint: Color {
        switch self {
        case .neutral:
            return Color(red: 0.24, green: 0.49, blue: 0.59)
        case .success:
            return Color(red: 0.27, green: 0.58, blue: 0.39)
        case .error:
            return Color(red: 0.73, green: 0.35, blue: 0.33)
        }
    }

    var icon: String {
        switch self {
        case .neutral:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

private enum StudyTool: String, CaseIterable, Identifiable {
    case learningInsights = "Learning Insights"
    case summaryGenerator = "Summary Generator"
    case keyConcepts = "Key Concepts"
    case flashcards = "Flashcards"
    case quizGenerator = "Quiz Generator"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .learningInsights:
            return "brain.head.profile"
        case .flashcards:
            return "rectangle.stack"
        case .quizGenerator:
            return "checklist"
        case .summaryGenerator:
            return "text.alignleft"
        case .keyConcepts:
            return "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .learningInsights:
            return "Compare coverage against the source note."
        case .flashcards:
            return "Review the strongest memory cues."
        case .quizGenerator:
            return "Check recall without leaving the note."
        case .summaryGenerator:
            return "Collapse the note into a quick overview."
        case .keyConcepts:
            return "Pull out the terms worth keeping in view."
        }
    }

    var actionLabel: String {
        switch self {
        case .learningInsights:
            return "Analyze"
        case .flashcards:
            return "Create"
        case .quizGenerator:
            return "Build"
        case .summaryGenerator:
            return "Generate"
        case .keyConcepts:
            return "Extract"
        }
    }
}

private enum StudySummaryMode: String, CaseIterable, Identifiable {
    case executive = "Executive"
    case detailed = "Detailed"
    case revision = "Revision"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .executive:
            return "Quick overview"
        case .detailed:
            return "Expanded explanation"
        case .revision:
            return "Exam-ready revision"
        }
    }
}

enum SupplementalStudySection: String, CaseIterable, Identifiable {
    case teachMe = "Teach Me"
    case conceptMap = "Concept Map"
    case learningMemory = "Learning Memory"
    case knowledgeGaps = "Knowledge Gaps"
    case examPrep = "Exam Prep"
    case knowledgeGraph = "Knowledge Graph"
    case activeRecall = "Active Recall"
    case streaks = "Study Streaks"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .teachMe:
            return "graduationcap"
        case .learningMemory:
            return "memorychip"
        case .knowledgeGaps:
            return "exclamationmark.triangle"
        case .examPrep:
            return "checklist"
        case .conceptMap:
            return "point.3.connected.trianglepath.dotted"
        case .knowledgeGraph:
            return "circle.grid.2x2"
        case .activeRecall:
            return "brain.head.profile"
        case .streaks:
            return "chart.line.uptrend.xyaxis"
        }
    }
}

struct StudyView: View {
    let noteID: UUID?
    let noteTitle: String
    let noteText: String
    let selectedText: String
    let lastUpdatedAt: Date?
    let noteHasContent: Bool
    let studyData: NoteStudyData
    let autoGenerateStudyMaterialsRequestID: UUID?
    let isGenerating: Bool
    let generationStatus: String
    let generationSummary: String?
    let statusMessage: String?
    let statusTone: StudyStatusTone
    let onGenerateMaterials: () -> Void
    let onAutoGenerateStudyMaterialsConsumed: () -> Void
    let onClose: () -> Void
    let onExplainSimply: () -> Void
    let onGiveExample: () -> Void
    let onCompareConcepts: () -> Void
    let onCreateAnalogy: () -> Void
    let onMarkFlashcardReviewed: (StudyFlashcard) -> Void
    let onRecordQuizAttempt: (StudyQuizSet, Int, Int) -> Void
    let onEvaluateTestMe: (StudyTutorQuestion, String, @escaping (StudyTutorEvaluation) -> Void) -> Void
    let onRecordTestMeSession: (Int, Int, [String]) -> Void
    let onInsertContent: (StudyGeneratedInsertion) -> Void
    @Binding var panelWidth: CGFloat

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var knowledgeGraphManager = KnowledgeGraphManager.shared
    @State private var selectedTool: StudyTool = .learningInsights
    @State private var panelLastDragX: CGFloat?
    @State private var flashcardIndex: Int = 0
    @State private var isFlashcardFlipped: Bool = false
    @State private var isFlashcardInteractionLocked: Bool = false
    @State private var activeRecallIndex: Int = 0
    @State private var isActiveRecallAnswerRevealed: Bool = false
    @State private var knowledgeExtractionDebuggerReport: KnowledgeExtractionDebugReport?
    @State private var isShowingKnowledgeExtractionDebugger: Bool = false
    @State private var selectedSummaryMode: StudySummaryMode = .executive
    @State private var expandedSupplementalSections: Set<SupplementalStudySection> = []
    @State private var expandedConceptNodeIDs: Set<UUID> = []
    @State private var teachMeDraftAnswer: String = ""
    @State private var generatedQuestionDraftAnswer: String = ""
    @State private var isGeneratedQuestionAnswerRevealed: Bool = false
    @State private var transientStatusMessage: String?
    @State private var studyScrollContentHeight: CGFloat = 0
    @State private var studyScrollViewportHeight: CGFloat = 0
    static let outerChromePadding: CGFloat = 0
    static let outerChromeCornerRadius: CGFloat = 0
    static func studyScrollBottomPadding(hasOverflow: Bool) -> CGFloat {
        hasOverflow ? 180 : 72
    }

    private func isSupplementalSectionExpanded(_ section: SupplementalStudySection) -> Bool {
        expandedSupplementalSections.contains(section)
    }

    private func toggleSupplementalSection(_ section: SupplementalStudySection) {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.92)) {
            if expandedSupplementalSections.contains(section) {
                expandedSupplementalSections.remove(section)
            } else {
                expandedSupplementalSections.insert(section)
            }
        }
    }

    private var noteLabel: String {
        noteTitle.isEmpty ? "Untitled Note" : noteTitle
    }

    private var studySourceText: String {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty {
            return selected
        }
        return noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var wordCount: Int {
        noteText.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var readingTimeLabel: String {
        guard wordCount > 0 else { return "0 min" }
        let minutes = max(1, Int((Double(wordCount) / 220.0).rounded(.up)))
        return "\(minutes) min"
    }

    private var lastUpdatedLabel: String {
        guard let lastUpdatedAt else { return "Unknown" }
        return lastUpdatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var summaryPreview: String {
        if !studyData.summaryPack.executiveSummary.isEmpty {
            return studyData.summaryPack.executiveSummary
        }

        if let generationSummary, !generationSummary.isEmpty {
            return generationSummary
        }

        let source = studySourceText
        guard !source.isEmpty else {
            return "Generate materials from the current note to populate this panel."
        }

        return String(source.prefix(180)) + (source.count > 180 ? "..." : "")
    }

    private var summaryWordCount: Int {
        let summaryText = summaryText(for: studyData.summaryPack, mode: selectedSummaryMode)
        return summaryText.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var effectiveKeyConcepts: [String] {
        if !studyData.insights.keyConcepts.isEmpty {
            return studyData.insights.keyConcepts
        }
        if !studyData.insights.importantConcepts.isEmpty {
            return studyData.insights.importantConcepts
        }
        return studySourceText
            .split { $0.isWhitespace || $0.isNewline }
            .prefix(10)
            .map(String.init)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.studySurfaceRaised,
                Color.studySurface,
                Color.studySurfaceMuted
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func verticalOverflowAffordanceVisible(contentHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        contentHeight > viewportHeight + 1
    }

    var body: some View {
        GeometryReader { _ in
            let hasOverflow = Self.verticalOverflowAffordanceVisible(
                contentHeight: studyScrollContentHeight,
                viewportHeight: studyScrollViewportHeight
            )

            ZStack(alignment: .leading) {
                backgroundGradient

                VStack(spacing: 0) {
                    headerCard

                    Divider()
                        .opacity(0.08)

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            studyWorkflowMap

                            ForEach(StudyTool.allCases) { tool in
                                toolSection(for: tool)
                            }

                            ForEach(SupplementalStudySection.allCases) { section in
                                supplementalSection(for: section)
                            }

                            Color.clear
                                .frame(height: Self.studyScrollBottomPadding(hasOverflow: hasOverflow))
                        }
                        .padding(18)
                        .padding(.bottom, Self.studyScrollBottomPadding(hasOverflow: hasOverflow))
                        .background(
                            GeometryReader { contentProxy in
                                Color.clear
                                    .onAppear {
                                        studyScrollContentHeight = contentProxy.size.height
                                    }
                                    .onChange(of: contentProxy.size.height) { _, newValue in
                                        studyScrollContentHeight = newValue
                                    }
                            }
                        )
                    }
                    .background(
                        GeometryReader { viewportProxy in
                            Color.clear
                                .onAppear {
                                    studyScrollViewportHeight = viewportProxy.size.height
                                }
                                .onChange(of: viewportProxy.size.height) { _, newValue in
                                    studyScrollViewportHeight = newValue
                                }
                        }
                    )
                    .scrollIndicators(.hidden)
                    .overlay(alignment: .bottom) {
                        if hasOverflow {
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.bgEditor.opacity(0.04),
                                    Color.bgEditor.opacity(0.24)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 42)
                            .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: noteID) { _, _ in
                        resetFlashcardSession()
                        isFlashcardInteractionLocked = false
                        expandedSupplementalSections.removeAll()
                        expandedConceptNodeIDs.removeAll()
                    }
                    .onChange(of: studyData.flashcards.map(\.id)) { _, _ in
                        syncFlashcardSession()
                    }
                }

                resizeGrip
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.bgEditor)
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.92), value: selectedTool)
        .animation(.spring(response: 0.26, dampingFraction: 0.92), value: panelWidth)
        .task(id: autoGenerateStudyMaterialsRequestID) {
            guard autoGenerateStudyMaterialsRequestID != nil else { return }
            guard noteHasContent, noteID != nil else { return }
            generateAllStudyMaterials()
            onAutoGenerateStudyMaterialsConsumed()
        }
        .sheet(isPresented: $isShowingKnowledgeExtractionDebugger) {
            if let report = knowledgeExtractionDebuggerReport {
                KnowledgeExtractionDebuggerView(report: report)
            } else {
                VStack(spacing: 12) {
                    Text("No extraction debug data available.")
                        .font(.headline)
                    Text("Run the debugger from a note with content to inspect the raw chunk, prompt, and merged knowledge.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(minWidth: 520, minHeight: 320)
            }
        }
    }

    private var resizeGrip: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if panelLastDragX == nil {
                            panelLastDragX = value.location.x
                        }
                        if let lastX = panelLastDragX {
                            let delta = value.location.x - lastX
                            withTransaction(Transaction(animation: nil)) {
                                panelWidth = clamp(panelWidth - delta, min: 380, max: 450)
                            }
                            panelLastDragX = value.location.x
                        }
                    }
                    .onEnded { _ in
                        panelLastDragX = nil
                    }
            )
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.studyBorderSoft)
                    .frame(width: 4, height: 52)
                    .padding(.leading, 4)
            }
            .padding(.leading, -7)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(noteLabel)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)

                    Text("Study panel attached to the editor")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text("Everything stays in the note-taking flow.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 10) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Color.studySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Close study panel")

                    HStack(spacing: 8) {
                        Button(action: { generate(for: selectedTool) }) {
                            HStack(spacing: 8) {
                                if isGenerating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: selectedTool.icon)
                                }
                                Text(isGenerating ? generationStatus : headerActionTitle)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.22, green: 0.44, blue: 0.58))
                        .disabled(isGenerating || !noteHasContent)

                        Button {
                            generateExamPrep()
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "checklist")
                                Text("Exam Prep")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(red: 0.31, green: 0.56, blue: 0.38))
                        .disabled(isGenerating || !noteHasContent)
                    }
                }
            }

            HStack(spacing: 8) {
                statPill(title: "Word Count", value: "\(wordCount)")
                statPill(title: "Reading Time", value: readingTimeLabel)
                statPill(title: "Last Updated", value: lastUpdatedLabel)
            }

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: statusTone.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTone.tint)
                Text(transientStatusMessage ?? (statusMessage?.isEmpty == false ? (statusMessage ?? "") : summaryPreview))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.top, 2)

            demoReadinessHintStrip
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.studySurfaceRaised, Color.studySurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.studyBorderSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 8)
        .padding(18)
    }

    private var demoReadinessHintStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start here")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    quickAction("Find Gaps", tint: Color(red: 0.73, green: 0.35, blue: 0.33), icon: "exclamationmark.triangle") {
                        revealSupplementalSection(.knowledgeGaps)
                        generateNotebookKnowledgeGaps()
                    }

                    quickAction("Teach Me", tint: Color(red: 0.24, green: 0.49, blue: 0.59), icon: "graduationcap") {
                        revealSupplementalSection(.teachMe)
                    }
                }

                HStack(spacing: 8) {
                    quickAction("Questions", tint: Color(red: 0.60, green: 0.45, blue: 0.20), icon: "checklist") {
                        focusStudyTool(.quizGenerator)
                    }

                    quickAction("Flashcards", tint: Color(red: 0.31, green: 0.56, blue: 0.38), icon: "rectangle.stack") {
                        focusStudyTool(.flashcards)
                    }
                }
            }
            .disabled(!noteHasContent)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var studyWorkflowMap: some View {
        let gapCount = activeKnowledgeGaps().count
        let analysis = studyData.learningInsights
        let missingCount = analysis.missingConcepts.count
        let partialCount = analysis.partiallyCapturedConcepts.count
        let teachMeState = studyData.teachMeSession?.state ?? .idle

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Study Map")
                        .font(.headline)
                    Text("Find what is missing, practice it, and add only reviewed AI proposals to the note.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text("AI proposes. Student decides.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.24, green: 0.49, blue: 0.59))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.24, green: 0.49, blue: 0.59).opacity(0.10))
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                studyMapTile(
                    title: "Coverage",
                    value: Self.coverageSummary(
                        missing: missingCount,
                        partial: partialCount,
                        hasAnalysis: analysis.hasResults,
                        isLoading: isGenerating
                    ),
                    icon: "chart.line.uptrend.xyaxis",
                    tint: Color(red: 0.24, green: 0.49, blue: 0.59)
                ) {
                    focusStudyTool(.learningInsights)
                }

                studyMapTile(
                    title: "Knowledge Gaps",
                    value: Self.knowledgeGapSummary(activeCount: gapCount),
                    icon: "exclamationmark.triangle",
                    tint: Color(red: 0.73, green: 0.35, blue: 0.33)
                ) {
                    revealSupplementalSection(.knowledgeGaps)
                }

                studyMapTile(
                    title: "Teach Me",
                    value: Self.teachMeSummary(for: teachMeState),
                    icon: "graduationcap",
                    tint: Color(red: 0.31, green: 0.56, blue: 0.38)
                ) {
                    revealSupplementalSection(.teachMe)
                }

                studyMapTile(
                    title: "Practice",
                    value: Self.practiceSummary(flashcards: studyData.flashcards.count, quizSets: studyData.quizSets.count),
                    icon: "rectangle.stack",
                    tint: Color(red: 0.60, green: 0.45, blue: 0.20)
                ) {
                    focusStudyTool(studyData.flashcards.isEmpty ? .quizGenerator : .flashcards)
                }
            }
        }
        .padding(16)
        .background(Color.studySurfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.studyBorderSoft, lineWidth: 1)
        )
        .accessibilityIdentifier("study-map")
    }

    private func studyMapTile(title: String, value: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(Color.studySurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.14), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .help("Open \(title)")
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier("study-map-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    static func coverageSummary(missing: Int, partial: Int, hasAnalysis: Bool = true, isLoading: Bool = false) -> String {
        if isLoading {
            return "Analyzing coverage"
        }
        guard hasAnalysis else {
            return "Analysis not run yet"
        }
        if missing == 0 && partial == 0 {
            return "No gaps in the current analysis"
        }
        return "\(missing) missing, \(partial) partial"
    }

    static func knowledgeGapSummary(activeCount: Int) -> String {
        activeCount == 0 ? "Scan or keep studying" : "\(activeCount) active"
    }

    static func teachMeSummary(for state: TeachMeSessionState) -> String {
        switch state {
        case .idle:
            return "Ready to start"
        case .question:
            return "Question waiting"
        case .answering:
            return "Answer in progress"
        case .feedback:
            return "Feedback ready"
        case .complete:
            return "Session complete"
        }
    }

    static func practiceSummary(flashcards: Int, quizSets: Int) -> String {
        if flashcards == 0 && quizSets == 0 {
            return "Create cards or quiz"
        }
        return "\(flashcards) cards, \(quizSets) quizzes"
    }

    private func toolSection(for tool: StudyTool) -> some View {
        let isSelected = selectedTool == tool

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: tool.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(toolTint(tool))
                    .frame(width: 30, height: 30)
                    .background(toolTint(tool).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(tool.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Button {
                    handleToolAction(tool)
                } label: {
                    Text(tool.actionLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(toolTint(tool))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(14)
            .background(
                LinearGradient(
                    colors: [
                        Color.studySurfaceRaised,
                        toolTint(tool).opacity(0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? toolTint(tool).opacity(0.34) : Color.studyBorderSoft, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
                    selectedTool = tool
                }
            }

            if isSelected {
                toolDetail(for: tool)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func toolDetail(for tool: StudyTool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.rawValue)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(detailSubtitle(for: tool))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            switch tool {
            case .learningInsights:
                learningInsightsDetail
            case .flashcards:
                flashcardsDetail
            case .quizGenerator:
                quizDetail
            case .summaryGenerator:
                summaryDetail
            case .keyConcepts:
                keyConceptsDetail
            }
        }
        .padding(16)
        .background(Color.studySurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.studyBorderSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var learningInsightsDetail: some View {
        let analysis = studyData.learningInsights
        let artifact = studyData.artifacts.first(where: { $0.kind == .learningInsights }) ?? buildArtifact(
            kind: .learningInsights,
            title: "Learning Insights",
            content: learningInsightsText(from: analysis),
            sections: learningInsightsSections(from: analysis)
        )

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                scoreRing(score: analysis.completenessScore)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Lecture Completeness \(analysis.scorePercent)%")
                        .font(.headline)
                    Text("Spot what is missing or underdeveloped before you leave the note.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            statRow(title: "Missing Concepts", value: "\(analysis.missingConcepts.count)")
            statRow(title: "Partially Captured", value: "\(analysis.partiallyCapturedConcepts.count)")
            statRow(title: "Well Covered", value: "\(analysis.wellCoveredConcepts.count)")

            if !analysis.missingConcepts.isEmpty {
                chipSection(title: "Top Missing", items: analysis.missingConcepts.prefix(3).map(\.title), tint: Color(red: 0.72, green: 0.31, blue: 0.28))
            }
            if !analysis.partiallyCapturedConcepts.isEmpty {
                chipSection(title: "Weak Coverage", items: analysis.partiallyCapturedConcepts.prefix(3).map(\.title), tint: Color(red: 0.77, green: 0.56, blue: 0.21))
            }
            if !analysis.reviewPriority.isEmpty {
                chipSection(title: "Review First", items: analysis.reviewPriority.prefix(3).map(\.title), tint: Color(red: 0.27, green: 0.43, blue: 0.55))
            }

            actionButtons(
                artifact: artifact,
                accent: Color(red: 0.24, green: 0.49, blue: 0.59),
                onRegenerate: { generateLearningInsights() }
            )

            HStack(spacing: 8) {
                quickAction("Explain Simply", onExplainSimply)
                quickAction("Example", onGiveExample)
                quickAction("Compare", onCompareConcepts)
                quickAction("Analogy", onCreateAnalogy)
            }
        }
    }

    private var flashcardsDetail: some View {
        let cards = studyData.flashcards
        let card = cards.isEmpty ? nil : cards[min(flashcardIndex, cards.count - 1)]
        let artifact = studyData.artifacts.first(where: { $0.kind == .flashcards }) ?? buildArtifact(
            kind: .flashcards,
            title: "Flashcards",
            content: flashcardSetText(from: cards),
            sections: flashcardSections(from: cards)
        )

        return VStack(alignment: .leading, spacing: 12) {
            statRow(title: "Flashcards Available", value: "\(cards.count)")
            statRow(title: "Reviewed", value: "\(studyData.progress.flashcardsReviewed)")

            HStack(spacing: 8) {
                quickAction("Generate Flashcard", tint: Color(red: 0.31, green: 0.56, blue: 0.38), icon: "rectangle.stack.badge.plus") {
                    generateSelectedStudyItem(.generateFlashcard)
                }
            }

            if !cards.isEmpty {
                ProgressView(value: Self.flashcardProgressValue(currentIndex: flashcardIndex, cardCount: cards.count))
                    .tint(card?.type.tint ?? Color(red: 0.31, green: 0.56, blue: 0.38))
                    .accessibilityLabel("Flashcard progress")
                    .accessibilityValue(Self.flashcardProgressLabel(currentIndex: flashcardIndex, cardCount: cards.count))
            }

            if cards.isEmpty {
                emptyCompactState(
                    title: "No flashcards yet",
                    message: "Use Generate Flashcard above for the current selection, or press Create in the Flashcards row to build a deck from the note."
                )
            } else if let card {
                VStack(alignment: .leading, spacing: 10) {
                    flashcardFlipCard(card: card, indexText: "\(flashcardIndex + 1)/\(cards.count)")
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(cardAccessibilityLabel(for: card))
                    .accessibilityHint("Tap to flip the card.")
                    .onTapGesture {
                        performFlashcardAction {
                            if reduceMotion {
                                isFlashcardFlipped.toggle()
                            } else {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                                    isFlashcardFlipped.toggle()
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            performFlashcardAction {
                                flashcardIndex = Self.previousFlashcardIndex(currentIndex: flashcardIndex, cardCount: cards.count)
                                isFlashcardFlipped = false
                            }
                        } label: {
                            Text("Previous")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.studySurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .disabled(isFlashcardInteractionLocked || flashcardIndex == 0)

                        Button {
                            performFlashcardAction {
                                if reduceMotion {
                                    isFlashcardFlipped.toggle()
                                } else {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                                        isFlashcardFlipped.toggle()
                                    }
                                }
                            }
                        } label: {
                            Text(isFlashcardFlipped ? "Show Front" : "Flip")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(card.type.tint.opacity(0.12))
                                .foregroundStyle(card.type.tint)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.space, modifiers: [])
                        .keyboardShortcut(.return, modifiers: [])
                        .disabled(isFlashcardInteractionLocked)

                        Button {
                            performFlashcardAction {
                                flashcardIndex = Self.nextFlashcardIndex(currentIndex: flashcardIndex, cardCount: cards.count)
                                isFlashcardFlipped = false
                            }
                        } label: {
                            Text("Next")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.studySurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .disabled(isFlashcardInteractionLocked || flashcardIndex >= cards.count - 1)

                        Button {
                            performFlashcardAction {
                                shuffleFlashcards()
                            }
                        } label: {
                            Text("Shuffle")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.studySurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isFlashcardInteractionLocked)
                        .keyboardShortcut("s", modifiers: [.command, .shift])

                        Spacer()

                        Button {
                            performFlashcardAction {
                                copyToPasteboard(flashcardCardText(card))
                            }
                        } label: {
                            Text("Copy Card")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(card.type.tint)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(card.type.tint.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isFlashcardInteractionLocked)
                        .keyboardShortcut("c", modifiers: [.command, .shift])

                        Button {
                            performFlashcardAction {
                                insertGeneratedContent(flashcardCardText(card), card: card)
                            }
                        } label: {
                            Text("Insert Card")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(card.type.tint)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isFlashcardInteractionLocked)
                        .keyboardShortcut("i", modifiers: [.command, .shift])

                        Button {
                            performFlashcardAction {
                                onMarkFlashcardReviewed(card)
                                transientStatusMessage = "Marked flashcard as reviewed."
                            }
                        } label: {
                            Text("Mark Reviewed")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color(red: 0.31, green: 0.56, blue: 0.38))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isFlashcardInteractionLocked)
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                    }

                    actionButtons(
                        artifact: artifact,
                        accent: card.type.tint,
                        onRegenerate: { performFlashcardAction { generateFlashcards() } },
                        includeExport: true
                    )
                    .disabled(isFlashcardInteractionLocked)
                }
            }
        }
    }

    private func performFlashcardAction(_ action: () -> Void) {
        guard !isFlashcardInteractionLocked else { return }
        isFlashcardInteractionLocked = true
        action()

        Task { @MainActor in
            let delay = reduceMotion ? UInt64(90_000_000) : UInt64(260_000_000)
            try? await Task.sleep(nanoseconds: delay)
            isFlashcardInteractionLocked = false
        }
    }

    private func resetFlashcardSession() {
        flashcardIndex = 0
        isFlashcardFlipped = false
    }

    private func syncFlashcardSession() {
        let cardCount = studyData.flashcards.count
        guard cardCount > 0 else {
            resetFlashcardSession()
            isFlashcardInteractionLocked = false
            return
        }

        flashcardIndex = min(flashcardIndex, cardCount - 1)
        isFlashcardFlipped = false
        isFlashcardInteractionLocked = false
    }

    private func cardAccessibilityLabel(for card: StudyFlashcard) -> String {
        let side = Self.flashcardFace(for: isFlashcardFlipped)
        return "\(card.type.title) flashcard, \(side == .front ? "front" : "back") side. \(side == .front ? card.front : card.back)"
    }

    private func flashcardFace(card: StudyFlashcard, side: StudyFlashcardFace, indexText: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(card.type.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(card.type.tint)
                Spacer()
                Text(indexText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(side == .front ? card.front : card.back)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if side == .front, !card.whyItMatters.isEmpty {
                Text(card.whyItMatters)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func flashcardFlipCard(card: StudyFlashcard, indexText: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.studySurfaceRaised,
                            card.type.tint.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 168)
                .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 6)

            Group {
                if isFlashcardFlipped {
                    flashcardFace(card: card, side: .back, indexText: indexText)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    flashcardFace(card: card, side: .front, indexText: indexText)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.88), value: isFlashcardFlipped)
    }

    static func previousFlashcardIndex(currentIndex: Int, cardCount: Int) -> Int {
        guard cardCount > 0 else { return 0 }
        return max(0, min(currentIndex, cardCount - 1) - 1)
    }

    static func nextFlashcardIndex(currentIndex: Int, cardCount: Int) -> Int {
        guard cardCount > 0 else { return 0 }
        return min(cardCount - 1, max(0, currentIndex) + 1)
    }

    static func flashcardProgressValue(currentIndex: Int, cardCount: Int) -> Double {
        guard cardCount > 0 else { return 0 }
        return Double(min(currentIndex + 1, cardCount)) / Double(cardCount)
    }

    static func flashcardProgressLabel(currentIndex: Int, cardCount: Int) -> String {
        guard cardCount > 0 else { return "0 of 0 cards" }
        let current = min(currentIndex + 1, cardCount)
        return "\(current) of \(cardCount) cards"
    }

    static func flashcardFace(for isFlipped: Bool) -> StudyFlashcardFace {
        isFlipped ? .back : .front
    }

    static func flashcardControlsDisabled(cardCount: Int, isLocked: Bool) -> Bool {
        isLocked || cardCount == 0
    }

    static func flashcardSessionCompleted(currentIndex: Int, cardCount: Int) -> Bool {
        cardCount > 0 && currentIndex >= cardCount - 1
    }

    static func flashcardDeckChanged(previousIDs: [UUID], currentIDs: [UUID]) -> Bool {
        previousIDs != currentIDs
    }

    private var quizDetail: some View {
        let multipleChoice = studyData.quizSets.flatMap(\.questions).filter { $0.type == .multipleChoice }.count
        let shortAnswer = studyData.quizSets.flatMap(\.questions).filter { $0.type == .shortAnswer }.count
        let generatedQuestion = studyData.quizSets.first?.questions.first

        return VStack(alignment: .leading, spacing: 12) {
            statRow(title: "Quiz Sets", value: "\(studyData.quizSets.count)")
            statRow(title: "Multiple Choice", value: "\(multipleChoice)")
            statRow(title: "Short Answer", value: "\(shortAnswer)")

            HStack(spacing: 8) {
                quickAction("Recall Question", tint: Color(red: 0.60, green: 0.45, blue: 0.20), icon: "arrow.counterclockwise") {
                    generateSelectedStudyItem(.recallQuestion)
                }
                quickAction("Understanding", tint: Color(red: 0.24, green: 0.49, blue: 0.59), icon: "lightbulb") {
                    generateSelectedStudyItem(.understandingQuestion)
                }
                quickAction("Application", tint: Color(red: 0.53, green: 0.34, blue: 0.71), icon: "arrow.triangle.branch") {
                    generateSelectedStudyItem(.applicationQuestion)
                }
            }

            if let generatedQuestion {
                generatedQuestionPracticeCard(generatedQuestion)
            }

            if let quizSet = studyData.quizSets.first {
                let artifact = studyData.artifacts.first(where: { $0.kind == .quizGenerator }) ?? buildArtifact(
                    kind: .quizGenerator,
                    title: quizSet.title,
                    content: quizSetText(from: quizSet),
                    sections: quizSections(from: quizSet)
                )
                generatedTextBlock(
                    title: quizSet.title,
                    subtitle: "\(quizSet.questions.count) questions",
                    body: quizPreview(for: quizSet),
                    artifact: artifact,
                    accent: Color(red: 0.60, green: 0.45, blue: 0.20),
                    onRegenerate: { generateQuizSet() }
                )
            } else {
                emptyCompactState(
                    title: "No quizzes yet",
                    message: "Use Recall Question, Understanding, or Application above for one selected-content question, or press Build in the Quiz Generator row for a full set."
                )
            }
        }
    }

    private func generatedQuestionPracticeCard(_ question: StudyQuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(question.cognitiveLevel.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.60, green: 0.45, blue: 0.20))
                Spacer()
                if !question.sourceConcept.isEmpty {
                    Text(question.sourceConcept)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(question.prompt)
                .font(.headline)
                .foregroundStyle(.primary)

            TextField("Type your answer", text: $generatedQuestionDraftAnswer, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            if isGeneratedQuestionAnswerRevealed {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Answer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(question.correctAnswer)
                        .font(.subheadline)
                    if !question.explanation.isEmpty {
                        Text(question.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.studySurfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 8) {
                Button(isGeneratedQuestionAnswerRevealed ? "Hide Answer" : "Reveal Answer") {
                    isGeneratedQuestionAnswerRevealed.toggle()
                }
                .buttonStyle(.borderless)

                Button("Correct") {
                    recordGeneratedQuestionAnswer(question, isCorrect: true)
                }
                .buttonStyle(.borderless)

                Button("Incorrect") {
                    recordGeneratedQuestionAnswer(question, isCorrect: false)
                }
                .buttonStyle(.borderless)

                Spacer()
            }
            .font(.caption.weight(.semibold))

            if let reference = question.sourceReferences.first {
                Text("Source: characters \(reference.rangeLocation)-\(reference.rangeLocation + reference.rangeLength)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.studyBorderSoft, lineWidth: 1)
        )
    }

    private var summaryDetail: some View {
        let summaryPack = studyData.summaryPack
        let artifact = buildArtifact(
            kind: .summaryGenerator,
            title: "Summary Generator",
            content: summaryText(for: summaryPack, mode: selectedSummaryMode),
            sections: summarySections(from: summaryPack)
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(StudySummaryMode.allCases) { mode in
                    Button {
                        selectedSummaryMode = mode
                    } label: {
                        Text(mode.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedSummaryMode == mode ? .white : Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(selectedSummaryMode == mode ? Color(red: 0.54, green: 0.38, blue: 0.61) : Color.studySurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            statRow(title: "Summary Length", value: "\(summaryWordCount) words")

            generatedTextBlock(
                title: "\(selectedSummaryMode.rawValue) Summary",
                subtitle: selectedSummaryMode.subtitle,
                body: summaryText(for: summaryPack, mode: selectedSummaryMode),
                artifact: artifact,
                accent: Color(red: 0.54, green: 0.38, blue: 0.61),
                onRegenerate: { generateSummary() }
            )
        }
    }

    private var keyConceptsDetail: some View {
        let concepts = effectiveKeyConcepts
        let insights = studyData.insights
        let artifact = studyData.artifacts.first(where: { $0.kind == .keyConcepts }) ?? buildArtifact(
            kind: .keyConcepts,
            title: "Key Concepts",
            content: keyConceptsText(from: insights),
            sections: keyConceptSections(from: insights)
        )

        return VStack(alignment: .leading, spacing: 12) {
            statRow(title: "Key Concepts", value: "\(concepts.count)")

            if concepts.isEmpty {
                emptyCompactState(
                    title: "No key concepts yet",
                    message: "Generate materials or use Learning Insights to extract the important terms."
                )
            } else {
                chipSection(title: "Important Terms", items: concepts.prefix(8), tint: Color(red: 0.23, green: 0.47, blue: 0.59))
                actionButtons(
                    artifact: artifact,
                    accent: Color(red: 0.23, green: 0.47, blue: 0.59),
                    onRegenerate: { generateKeyConcepts() }
                )
            }
        }
    }

    private func actionButtons(artifact: StudyArtifact, accent: Color, onRegenerate: (() -> Void)? = nil, includeExport: Bool = false) -> some View {
        let content = artifact.content
        return HStack(spacing: 8) {
            Button {
                copyToPasteboard(content)
            } label: {
                Text("Copy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.studySurfaceRaised)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if includeExport {
                Button {
                    exportFlashcardSet()
                } label: {
                    Text("Export Set")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.54, green: 0.38, blue: 0.61))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.studySurfaceRaised)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(red: 0.54, green: 0.38, blue: 0.61).opacity(0.20), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }

            if let onRegenerate {
                Button {
                    onRegenerate()
                } label: {
                    Text("Regenerate")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.studySurfaceRaised)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.18), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
            }

            Button {
                saveArtifact(artifact)
            } label: {
                Text("Save")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.studySurface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.borderSubtle, lineWidth: 0.8))
            }
            .buttonStyle(.plain)

            Button {
                insertGeneratedContent(content, artifact: artifact)
            } label: {
                Text("Add to Note")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.studySurfaceRaised)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.18), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func generatedTextBlock(
        title: String,
        subtitle: String,
        body: String,
        artifact: StudyArtifact,
        accent: Color,
        onRegenerate: (() -> Void)? = nil
    ) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(body.isEmpty ? "Nothing generated yet." : body)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            actionButtons(artifact: artifact, accent: accent, onRegenerate: onRegenerate)
        }
        .padding(14)
        .background(Color.studySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.15), lineWidth: 1)
        )
        .onDrag {
            dragProvider(artifact.content)
        }
    }

    private func quickAction(_ title: String, tint: Color = Color.textSecondary, icon: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.14), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func focusStudyTool(_ tool: StudyTool) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
            selectedTool = tool
        }
    }

    private func revealSupplementalSection(_ section: SupplementalStudySection) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
            _ = expandedSupplementalSections.insert(section)
        }
    }

    private func scoreRing(score: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.studyBorderSoft, lineWidth: 10)
            Circle()
                .trim(from: 0, to: score.clamped(to: 0...1))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.22, green: 0.50, blue: 0.62),
                            Color(red: 0.35, green: 0.68, blue: 0.47)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(Int((score.clamped(to: 0...1) * 100).rounded()))")
                .font(.system(size: 24, weight: .bold, design: .rounded))
        }
        .frame(width: 92, height: 92)
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(Color.studySurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studySurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func chipSection(title: String, items: ArraySlice<String>, tint: Color) -> some View {
        chipSection(title: title, items: Array(items), tint: tint)
    }

    private func chipSection(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(tint)
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)

                        Text(item)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(tint.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(tint.opacity(0.18), lineWidth: 0.9)
                    )
                }
            }
        }
    }

    private func emptyCompactState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.studySurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func toolTint(_ tool: StudyTool) -> Color {
        switch tool {
        case .learningInsights:
            return Color(red: 0.24, green: 0.49, blue: 0.59)
        case .flashcards:
            return Color(red: 0.31, green: 0.56, blue: 0.38)
        case .quizGenerator:
            return Color(red: 0.60, green: 0.45, blue: 0.20)
        case .summaryGenerator:
            return Color(red: 0.54, green: 0.38, blue: 0.61)
        case .keyConcepts:
            return Color(red: 0.27, green: 0.43, blue: 0.55)
        }
    }

    private func detailSubtitle(for tool: StudyTool) -> String {
        switch tool {
        case .learningInsights:
            return "Compare coverage against the source note."
        case .flashcards:
            return "Review the strongest memory cues."
        case .quizGenerator:
            return "Check recall without leaving the note."
        case .summaryGenerator:
            return "Collapse the note into a quick overview."
        case .keyConcepts:
            return "Pull out the terms worth keeping in view."
        }
    }

    private var learningInsightsText: String {
        let analysis = studyData.learningInsights
        var lines: [String] = []
        lines.append("Learning Insights for \(noteLabel)")
        lines.append("Completeness: \(analysis.scorePercent)%")

        if !analysis.missingConcepts.isEmpty {
            lines.append("Missing concepts: \(analysis.missingConcepts.map(\.title).joined(separator: ", "))")
        }
        if !analysis.partiallyCapturedConcepts.isEmpty {
            lines.append("Partially covered: \(analysis.partiallyCapturedConcepts.map(\.title).joined(separator: ", "))")
        }
        if !analysis.reviewPriority.isEmpty {
            lines.append("Review first: \(analysis.reviewPriority.map(\.title).joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    private var flashcardsText: String {
        guard !studyData.flashcards.isEmpty else {
            return "Flashcards\nNo flashcards available yet."
        }

        return studyData.flashcards.enumerated().map { index, card in
            """
            \(index + 1). \(card.type.title)
            Q: \(card.front)
            A: \(card.back)
            """
        }.joined(separator: "\n\n")
    }

    private var quizText: String {
        guard !studyData.quizSets.isEmpty else {
            return "Quiz Generator\nNo quiz sets available yet."
        }

        return studyData.quizSets.map { quizSet in
            """
            \(quizSet.title)
            \(quizSet.questions.count) questions
            \(quizPreview(for: quizSet))
            """
        }.joined(separator: "\n\n")
    }

    private var keyConceptsText: String {
        guard !effectiveKeyConcepts.isEmpty else {
            return "No key concepts captured yet."
        }

        return effectiveKeyConcepts.joined(separator: "\n")
    }

    private func quizPreview(for quizSet: StudyQuizSet) -> String {
        let questions = quizSet.questions.prefix(3).map { "• \($0.prompt)" }
        return questions.isEmpty ? "No preview available." : questions.joined(separator: "\n")
    }

    private func handleToolAction(_ tool: StudyTool) {
        generate(for: tool)
    }

    private func insertGeneratedContent(_ content: String, artifact: StudyArtifact) {
        insertGeneratedContent(
            content,
            feature: artifact.kind.title,
            sourceConcept: effectiveKeyConcepts.first,
            sourceItemID: artifact.id.uuidString,
            sourceItemTitle: artifact.title,
            sourceExcerpt: String(noteContentSource.prefix(600))
        )
    }

    private func insertGeneratedContent(_ content: String, card: StudyFlashcard) {
        insertGeneratedContent(
            content,
            feature: StudyArtifactKind.flashcards.title,
            sourceConcept: card.sourceConcept.isEmpty ? card.conceptIDs.first : card.sourceConcept,
            sourceItemID: card.id.uuidString,
            sourceItemTitle: card.front,
            sourceExcerpt: card.sourceReferences.first?.excerpt ?? card.front
        )
    }

    private func insertGeneratedContent(
        _ content: String,
        feature: String,
        sourceConcept: String?,
        sourceItemID: String?,
        sourceItemTitle: String?,
        sourceExcerpt: String
    ) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onInsertContent(
            StudyGeneratedInsertion(
                content: trimmed,
                feature: feature,
                sourceConcept: sourceConcept,
                sourceItemID: sourceItemID,
                sourceItemTitle: sourceItemTitle,
                sourceExcerpt: sourceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }

    private func copyToPasteboard(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
    }

    private func dragProvider(_ content: String) -> NSItemProvider {
        NSItemProvider(object: content.trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}
