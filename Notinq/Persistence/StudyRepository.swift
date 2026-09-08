import Foundation

protocol StudyRepositoryProtocol {
    func persist(noteID: UUID, noteTitle: String, studyData: NoteStudyData) throws
    func studyData(for noteID: UUID, noteTitle: String?) throws -> NoteStudyData
    func flashcards(for noteID: UUID) throws -> [StudyFlashcard]
    func questions(for noteID: UUID) throws -> [StudyQuizQuestion]
    func summaries(for noteID: UUID) throws -> [StudyArtifact]
    func studentConcepts(for noteID: UUID) throws -> [StudentConceptRecord]
    func studentConcept(for noteID: UUID, conceptID: String) throws -> StudentConceptRecord?
    func reviewEvents(for noteID: UUID) throws -> [ReviewEvent]
    func reviewEvents(forConceptID conceptID: String) throws -> [ReviewEvent]
    func recordReviewEvent(_ event: ReviewEvent) throws
    func upsertStudentConcept(
        noteID: UUID,
        conceptID: String,
        masteryScore: Double,
        confidenceScore: Double,
        reviewCount: Int,
        mistakeCount: Int,
        lastReviewed: Date?
    ) throws
    func weakestStudentConcepts(limit: Int) throws -> [StudentConceptRecord]
    func strongestStudentConcepts(limit: Int) throws -> [StudentConceptRecord]
    func recentlyReviewedStudentConcepts(limit: Int) throws -> [StudentConceptRecord]
    func studentConceptsNeedingReview(limit: Int) throws -> [StudentConceptRecord]
}

final class StudyRepository: StudyRepositoryProtocol {
    static let shared = StudyRepository()

    private let database: SQLiteDatabase
    private let queue = DispatchQueue(label: "notinq.study.repository", qos: .utility)

    init(database: SQLiteDatabase = SQLiteDatabase.makeDefault()) {
        self.database = database
        try? createSchemaIfNeeded()
    }

    func persist(noteID: UUID, noteTitle: String, studyData: NoteStudyData) throws {
        try createSchemaIfNeeded()
        try database.transaction {
            try deleteExistingRows(noteID: noteID)
            try insertFlashcards(noteID: noteID, noteTitle: noteTitle, studyData: studyData)
            try insertQuestions(noteID: noteID, studyData: studyData)
            try insertSummaries(noteID: noteID, studyData: studyData)
            try insertStudentConcepts(noteID: noteID, studyData: studyData)
            try insertReviewEvents(noteID: noteID, studyData: studyData)
        }
    }

    func studyData(for noteID: UUID, noteTitle: String? = nil) throws -> NoteStudyData {
        let flashcards = try flashcards(for: noteID)
        let questions = try questions(for: noteID)
        let summaries = try summaries(for: noteID)
        let studentConcepts = try studentConcepts(for: noteID)
        let reviewEvents = try reviewEvents(for: noteID)

        var studyData = NoteStudyData()
        studyData.flashcards = flashcards
        studyData.quizSets = questions.isEmpty ? [] : [StudyQuizSet(title: noteTitle ?? "Quiz", questions: questions)]
        studyData.artifacts = summaries
        studyData.learningMemory = studentConcepts.map {
            StudyMemoryEntry(
                concept: $0.conceptID,
                masteredCount: max(0, $0.reviewCount - $0.mistakeCount),
                missedCount: $0.mistakeCount,
                reviewHistory: [],
                lastReviewedAt: $0.lastReviewed,
                lastOutcome: $0.masteryScore >= 0.5 ? .correct : .almost
            )
        }
        studyData.progress.quizAttempts = reviewEvents.compactMap { event in
            guard event.eventType == "quiz_attempt" else { return nil }
            return StudyQuizAttempt(
                quizSetID: UUID(uuidString: event.metadata["quizSetID"] ?? "") ?? UUID(),
                quizTitle: event.metadata["quizTitle"] ?? (noteTitle ?? "Quiz"),
                attemptedAt: event.occurredAt,
                score: Int(event.score.rounded()),
                totalQuestions: Int(event.metadata["totalQuestions"] ?? "1") ?? 1,
                percentage: event.score
            )
        }
        studyData.progress.flashcardsCreated = flashcards.count
        studyData.progress.flashcardsReviewed = studentConcepts.reduce(0) { $0 + $1.reviewCount }
        studyData.lastGeneratedAt = summaries.first?.generatedAt ?? Date()
        return studyData
    }

    func flashcards(for noteID: UUID) throws -> [StudyFlashcard] {
        let rows = try database.fetch(
            "SELECT id, front, back, why_it_matters, card_type, concept_ids_json FROM flashcards WHERE note_id = ? ORDER BY created_at ASC",
            bindings: [.text(noteID.uuidString)]
        )
        return rows.compactMap { row in
            guard let front = row.string("front"), let back = row.string("back") else { return nil }
            let type = StudyCardType(rawValue: row.string("card_type") ?? "concept") ?? .concept
            return StudyFlashcard(
                id: UUID(uuidString: row.string("id") ?? "") ?? UUID(),
                type: type,
                front: front,
                back: back,
                whyItMatters: row.string("why_it_matters") ?? "",
                conceptIDs: Self.decodeStringArray(row.string("concept_ids_json"))
            )
        }
    }

    func questions(for noteID: UUID) throws -> [StudyQuizQuestion] {
        let rows = try database.fetch(
            "SELECT id, prompt, options_json, answer, explanation, question_type, keywords_json, concept_ids_json FROM questions WHERE note_id = ? ORDER BY created_at ASC",
            bindings: [.text(noteID.uuidString)]
        )
        return rows.compactMap { row in
            guard let prompt = row.string("prompt"), let answer = row.string("answer") else { return nil }
            let questionType = StudyQuizQuestionType(rawValue: row.string("question_type") ?? "short_answer") ?? .shortAnswer
            return StudyQuizQuestion(
                id: UUID(uuidString: row.string("id") ?? "") ?? UUID(),
                type: questionType,
                prompt: prompt,
                options: Self.decodeStringArray(row.string("options_json")),
                correctAnswer: answer,
                explanation: row.string("explanation") ?? "",
                keywords: Self.decodeStringArray(row.string("keywords_json")),
                conceptIDs: Self.decodeStringArray(row.string("concept_ids_json"))
            )
        }
    }

    func summaries(for noteID: UUID) throws -> [StudyArtifact] {
        let rows = try database.fetch(
            "SELECT id, summary_type, body, created_at FROM summaries WHERE note_id = ? ORDER BY created_at ASC",
            bindings: [.text(noteID.uuidString)]
        )
        return rows.compactMap { row in
            guard let summaryType = row.string("summary_type"), let body = row.string("body") else { return nil }
            return StudyArtifact(
                id: UUID(uuidString: row.string("id") ?? "") ?? UUID(),
                kind: artifactKind(from: summaryType),
                title: summaryType,
                content: body,
                sections: [],
                sourceNoteID: noteID,
                sourceNoteTitle: "",
                generatedAt: Self.date(from: row.string("created_at")) ?? Date()
            )
        }
    }

    func studentConcepts(for noteID: UUID) throws -> [StudentConceptRecord] {
        let rows = try database.fetch(
            "SELECT concept_id, mastery_score, confidence_score, last_reviewed, mistake_count, review_count, created_at, updated_at FROM student_concepts WHERE note_id = ? ORDER BY concept_id ASC",
            bindings: [.text(noteID.uuidString)]
        )
        return rows.compactMap { row in
            guard let conceptID = row.string("concept_id") else { return nil }
            return StudentConceptRecord(
                conceptID: conceptID,
                masteryScore: row.double("mastery_score") ?? 0,
                confidenceScore: row.double("confidence_score") ?? 0.5,
                lastReviewed: Self.date(from: row.string("last_reviewed")),
                mistakeCount: row.int("mistake_count") ?? 0,
                reviewCount: row.int("review_count") ?? 0,
                createdAt: Self.date(from: row.string("created_at")) ?? Date(),
                updatedAt: Self.date(from: row.string("updated_at")) ?? Date()
            )
        }
    }

    func studentConcept(for noteID: UUID, conceptID: String) throws -> StudentConceptRecord? {
        let rows: [SQLiteRow] = try database.fetch(
            "SELECT concept_id, mastery_score, confidence_score, last_reviewed, mistake_count, review_count, created_at, updated_at FROM student_concepts WHERE note_id = ? AND concept_id = ? LIMIT 1",
            bindings: [.text(noteID.uuidString), .text(conceptID)]
        )
        guard let row = rows.first, let storedConceptID = row.string("concept_id") else { return nil }
        return StudentConceptRecord(
            conceptID: storedConceptID,
            masteryScore: row.double("mastery_score") ?? 0,
            confidenceScore: row.double("confidence_score") ?? 0.5,
            lastReviewed: Self.date(from: row.string("last_reviewed")),
            mistakeCount: row.int("mistake_count") ?? 0,
            reviewCount: row.int("review_count") ?? 0,
            createdAt: Self.date(from: row.string("created_at")) ?? Date(),
            updatedAt: Self.date(from: row.string("updated_at")) ?? Date()
        )
    }

    func reviewEvents(for noteID: UUID) throws -> [ReviewEvent] {
        let rows = try database.fetch(
            "SELECT id, concept_id, note_id, question_id, flashcard_id, result, score, event_type, timestamp, occurred_at, metadata_json FROM review_events WHERE note_id = ? ORDER BY COALESCE(timestamp, occurred_at) DESC",
            bindings: [.text(noteID.uuidString)]
        )
        return rows.compactMap { row in
            guard let conceptID = row.string("concept_id"), let eventType = row.string("event_type") else { return nil }
            let timestamp = Self.date(from: row.string("timestamp")) ?? Self.date(from: row.string("occurred_at")) ?? Date()
            return ReviewEvent(
                id: row.string("id") ?? UUID().uuidString,
                conceptID: conceptID,
                noteID: UUID(uuidString: row.string("note_id") ?? ""),
                questionID: UUID(uuidString: row.string("question_id") ?? ""),
                flashcardID: UUID(uuidString: row.string("flashcard_id") ?? ""),
                result: row.string("result") ?? eventType,
                score: row.double("score") ?? 0,
                eventType: eventType,
                timestamp: timestamp,
                metadata: Self.decodeDictionary(row.string("metadata_json"))
            )
        }
    }

    func reviewEvents(forConceptID conceptID: String) throws -> [ReviewEvent] {
        let rows = try database.fetch(
            "SELECT id, concept_id, note_id, question_id, flashcard_id, result, score, event_type, timestamp, occurred_at, metadata_json FROM review_events WHERE concept_id = ? ORDER BY COALESCE(timestamp, occurred_at) DESC",
            bindings: [.text(conceptID)]
        )
        return rows.compactMap { row in
            guard let conceptID = row.string("concept_id"), let eventType = row.string("event_type") else { return nil }
            let timestamp = Self.date(from: row.string("timestamp")) ?? Self.date(from: row.string("occurred_at")) ?? Date()
            return ReviewEvent(
                id: row.string("id") ?? UUID().uuidString,
                conceptID: conceptID,
                noteID: UUID(uuidString: row.string("note_id") ?? ""),
                questionID: UUID(uuidString: row.string("question_id") ?? ""),
                flashcardID: UUID(uuidString: row.string("flashcard_id") ?? ""),
                result: row.string("result") ?? eventType,
                score: row.double("score") ?? 0,
                eventType: eventType,
                timestamp: timestamp,
                metadata: Self.decodeDictionary(row.string("metadata_json"))
            )
        }
    }

    func recordReviewEvent(_ event: ReviewEvent) throws {
        try createSchemaIfNeeded()
        try database.execute(
            "INSERT OR REPLACE INTO review_events (id, concept_id, note_id, question_id, flashcard_id, result, score, event_type, timestamp, occurred_at, metadata_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            bindings: [
                .text(event.id),
                .text(event.conceptID),
                event.noteID.map { .text($0.uuidString) } ?? .null,
                event.questionID.map { .text($0.uuidString) } ?? .null,
                event.flashcardID.map { .text($0.uuidString) } ?? .null,
                .text(event.result),
                .real(event.score),
                .text(event.eventType),
                .text(Self.string(from: event.timestamp)),
                .text(Self.string(from: event.timestamp)),
                .text(Self.encodeDictionary(event.metadata))
            ]
        )
    }

    func remove(noteID: UUID) throws {
        try createSchemaIfNeeded()
        try database.transaction {
            try database.execute("DELETE FROM flashcards WHERE note_id = ?", bindings: [.text(noteID.uuidString)])
            try database.execute("DELETE FROM questions WHERE note_id = ?", bindings: [.text(noteID.uuidString)])
            try database.execute("DELETE FROM summaries WHERE note_id = ?", bindings: [.text(noteID.uuidString)])
            try database.execute("DELETE FROM student_concepts WHERE note_id = ?", bindings: [.text(noteID.uuidString)])
            try database.execute("DELETE FROM review_events WHERE note_id = ?", bindings: [.text(noteID.uuidString)])
        }
    }

    private func createSchemaIfNeeded() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS flashcards (
            id TEXT PRIMARY KEY NOT NULL,
            note_id TEXT NOT NULL,
            concept_id TEXT,
            front TEXT NOT NULL,
            back TEXT NOT NULL,
            why_it_matters TEXT NOT NULL DEFAULT '',
            card_type TEXT NOT NULL DEFAULT 'concept',
            concept_ids_json TEXT NOT NULL DEFAULT '[]',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS questions (
            id TEXT PRIMARY KEY NOT NULL,
            note_id TEXT NOT NULL,
            concept_id TEXT,
            prompt TEXT NOT NULL,
            answer TEXT NOT NULL,
            explanation TEXT NOT NULL DEFAULT '',
            question_type TEXT NOT NULL DEFAULT 'short_answer',
            options_json TEXT NOT NULL DEFAULT '[]',
            keywords_json TEXT NOT NULL DEFAULT '[]',
            concept_ids_json TEXT NOT NULL DEFAULT '[]',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS summaries (
            id TEXT PRIMARY KEY NOT NULL,
            note_id TEXT NOT NULL,
            concept_id TEXT,
            summary_type TEXT NOT NULL,
            body TEXT NOT NULL,
            concept_ids_json TEXT NOT NULL DEFAULT '[]',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS student_concepts (
            concept_id TEXT NOT NULL,
            note_id TEXT NOT NULL,
            mastery_score REAL NOT NULL DEFAULT 0.0,
            confidence_score REAL NOT NULL DEFAULT 0.5,
            last_reviewed TEXT,
            mistake_count INTEGER NOT NULL DEFAULT 0,
            review_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (concept_id, note_id),
            FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS review_events (
            id TEXT PRIMARY KEY NOT NULL,
            concept_id TEXT NOT NULL,
            note_id TEXT,
            question_id TEXT,
            flashcard_id TEXT,
            result TEXT NOT NULL DEFAULT 'unknown',
            event_type TEXT NOT NULL,
            score REAL NOT NULL DEFAULT 0.0,
            timestamp TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            occurred_at TEXT NOT NULL,
            metadata_json TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY(note_id) REFERENCES notes(id) ON DELETE CASCADE
        )
        """)

        try ensureColumn(table: "student_concepts", column: "confidence_score", definition: "REAL NOT NULL DEFAULT 0.5")
        try ensureColumn(table: "student_concepts", column: "created_at", definition: "TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP")
        try ensureColumn(table: "review_events", column: "question_id", definition: "TEXT")
        try ensureColumn(table: "review_events", column: "flashcard_id", definition: "TEXT")
        try ensureColumn(table: "review_events", column: "result", definition: "TEXT NOT NULL DEFAULT 'unknown'")
        try ensureColumn(table: "review_events", column: "timestamp", definition: "TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP")
    }

    private func deleteExistingRows(noteID: UUID) throws {
        try database.execute("DELETE FROM flashcards WHERE note_id = ?", bindings: [.text(noteID.uuidString)])
        try database.execute("DELETE FROM questions WHERE note_id = ?", bindings: [.text(noteID.uuidString)])
        try database.execute("DELETE FROM summaries WHERE note_id = ?", bindings: [.text(noteID.uuidString)])
        try database.execute("DELETE FROM student_concepts WHERE note_id = ?", bindings: [.text(noteID.uuidString)])
    }

    private func insertFlashcards(noteID: UUID, noteTitle: String, studyData: NoteStudyData) throws {
        let conceptIDs = conceptIDs(for: studyData)
        for card in studyData.flashcards {
            let cardConceptIDs = card.conceptIDs.isEmpty
                ? matchedConceptIDs(for: card.front + " " + card.back, fallback: conceptIDs, studyData: studyData)
                : card.conceptIDs
            try database.execute(
                "INSERT INTO flashcards (id, note_id, concept_id, front, back, why_it_matters, card_type, concept_ids_json, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(card.id.uuidString),
                    .text(noteID.uuidString),
                    cardConceptIDs.first.map { .text($0) } ?? .null,
                    .text(card.front),
                    .text(card.back),
                    .text(card.whyItMatters),
                    .text(card.type.rawValue),
                    .text(Self.encodeStringArray(cardConceptIDs)),
                    .text(Self.string(from: studyData.lastGeneratedAt ?? Date())),
                    .text(Self.string(from: studyData.lastGeneratedAt ?? Date()))
                ]
            )
        }

        // Keep a small generated summary artifact when legacy data has no explicit summaries.
        if studyData.summaryPack.executiveSummary.isEmpty == false {
            try database.execute(
                "INSERT INTO summaries (id, note_id, concept_id, summary_type, body, concept_ids_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(UUID().uuidString),
                    .text(noteID.uuidString),
                    conceptIDs.first.map { .text($0) } ?? .null,
                    .text("executive_summary"),
                    .text(studyData.summaryPack.executiveSummary),
                    .text(Self.encodeStringArray(conceptIDs.prefix(8).map { $0 })),
                    .text(Self.string(from: studyData.lastGeneratedAt ?? Date()))
                ]
            )
        }
    }

    private func insertQuestions(noteID: UUID, studyData: NoteStudyData) throws {
        let conceptIDs = conceptIDs(for: studyData)
        let allQuestions = studyData.quizSets.flatMap(\.questions) + studyData.examPrep.practiceQuestions + studyData.tutorQuestions.map {
            StudyQuizQuestion(
                type: .shortAnswer,
                prompt: $0.prompt,
                options: [],
                correctAnswer: $0.expectedAnswer,
                explanation: $0.explanation,
                keywords: [$0.concept],
                conceptIDs: $0.conceptIDs
            )
        }

        for question in allQuestions {
            let matched = question.conceptIDs.isEmpty
                ? matchedConceptIDs(for: question.prompt + " " + question.correctAnswer + " " + question.keywords.joined(separator: " "), fallback: conceptIDs, studyData: studyData)
                : question.conceptIDs
            try database.execute(
                "INSERT INTO questions (id, note_id, concept_id, prompt, answer, explanation, question_type, options_json, keywords_json, concept_ids_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(question.id.uuidString),
                    .text(noteID.uuidString),
                    matched.first.map { .text($0) } ?? .null,
                    .text(question.prompt),
                    .text(question.correctAnswer),
                    .text(question.explanation),
                    .text(question.type.rawValue),
                    .text(Self.encodeStringArray(question.options)),
                    .text(Self.encodeStringArray(question.keywords)),
                    .text(Self.encodeStringArray(matched)),
                    .text(Self.string(from: studyData.lastGeneratedAt ?? Date()))
                ]
            )
        }
    }

    private func insertSummaries(noteID: UUID, studyData: NoteStudyData) throws {
        let conceptIDs = conceptIDs(for: studyData)
        let candidateSummaries = [
            (type: "executive_summary", body: studyData.summaryPack.executiveSummary),
            (type: "detailed_summary", body: studyData.summaryPack.detailedSummary),
            (type: "exam_revision_summary", body: studyData.summaryPack.examRevisionSummary)
        ]
        .filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let artifactSummaries = studyData.artifacts.compactMap { artifact -> (type: String, body: String)? in
            let type = artifact.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = artifact.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard type.isEmpty == false || body.isEmpty == false else { return nil }
            return (type: type.isEmpty ? artifact.kind.rawValue : type, body: body)
        }

        for summary in candidateSummaries + artifactSummaries {
            try database.execute(
                "INSERT INTO summaries (id, note_id, concept_id, summary_type, body, concept_ids_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(UUID().uuidString),
                    .text(noteID.uuidString),
                    conceptIDs.first.map { .text($0) } ?? .null,
                    .text(summary.type),
                    .text(summary.body),
                    .text(Self.encodeStringArray(conceptIDs.prefix(8).map { $0 })),
                    .text(Self.string(from: studyData.lastGeneratedAt ?? Date()))
                ]
            )
        }
    }

    private func insertStudentConcepts(noteID: UUID, studyData: NoteStudyData) throws {
        let conceptIDs = conceptIDs(for: studyData)
        var masteryByConcept: [String: StudyMemoryEntry] = [:]
        for entry in studyData.learningMemory {
            masteryByConcept[normalizeConceptKey(entry.concept)] = entry
        }

        for conceptID in conceptIDs {
            let entry = masteryByConcept[normalizeConceptKey(conceptID)]
            let mastery = entry?.masteryScore ?? 0.5
            try upsertStudentConcept(
                noteID: noteID,
                conceptID: conceptID,
                masteryScore: mastery,
                confidenceScore: mastery,
                reviewCount: (entry?.masteredCount ?? 0) + (entry?.missedCount ?? 0),
                mistakeCount: entry?.missedCount ?? 0,
                lastReviewed: entry?.lastReviewedAt
            )
        }
    }

    private func insertReviewEvents(noteID: UUID, studyData: NoteStudyData) throws {
        for attempt in studyData.progress.quizAttempts {
            try database.execute(
                "INSERT OR REPLACE INTO review_events (id, concept_id, note_id, question_id, flashcard_id, result, score, event_type, timestamp, occurred_at, metadata_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                bindings: [
                    .text(attempt.id.uuidString),
                    .text(attempt.quizSetID.uuidString),
                    .text(noteID.uuidString),
                    .null,
                    .null,
                    .text(attempt.percentage >= 70 ? "correct" : "incorrect"),
                    .real(attempt.percentage),
                    .text("quiz_attempt"),
                    .text(Self.string(from: attempt.attemptedAt)),
                    .text(Self.string(from: attempt.attemptedAt)),
                    .text(Self.encodeDictionary([
                        "quizSetID": attempt.quizSetID.uuidString,
                        "quizTitle": attempt.quizTitle,
                        "totalQuestions": String(attempt.totalQuestions)
                    ]))
                ]
            )
        }
    }

    func upsertStudentConcept(
        noteID: UUID,
        conceptID: String,
        masteryScore: Double,
        confidenceScore: Double,
        reviewCount: Int,
        mistakeCount: Int,
        lastReviewed: Date?
    ) throws {
        try createSchemaIfNeeded()
        let timestamp = Self.string(from: Date())
        try database.execute(
            """
            INSERT INTO student_concepts (concept_id, note_id, mastery_score, confidence_score, last_reviewed, mistake_count, review_count, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(concept_id, note_id) DO UPDATE SET
                mastery_score = excluded.mastery_score,
                confidence_score = excluded.confidence_score,
                last_reviewed = excluded.last_reviewed,
                mistake_count = student_concepts.mistake_count + excluded.mistake_count,
                review_count = student_concepts.review_count + excluded.review_count,
                updated_at = excluded.updated_at
            """,
            bindings: [
                .text(conceptID),
                .text(noteID.uuidString),
                .real(masteryScore),
                .real(confidenceScore),
                lastReviewed.map { .text(Self.string(from: $0)) } ?? .null,
                .integer(Int64(mistakeCount)),
                .integer(Int64(reviewCount)),
                .text(timestamp),
                .text(timestamp)
            ]
        )
    }

    func weakestStudentConcepts(limit: Int) throws -> [StudentConceptRecord] {
        try studentConcepts(ordering: "mastery_score ASC, review_count DESC", limit: limit)
    }

    func strongestStudentConcepts(limit: Int) throws -> [StudentConceptRecord] {
        try studentConcepts(ordering: "mastery_score DESC, confidence_score DESC", limit: limit)
    }

    func recentlyReviewedStudentConcepts(limit: Int) throws -> [StudentConceptRecord] {
        try studentConcepts(ordering: "COALESCE(last_reviewed, updated_at) DESC", limit: limit)
    }

    func studentConceptsNeedingReview(limit: Int) throws -> [StudentConceptRecord] {
        try studentConcepts(
            ordering: "CASE WHEN last_reviewed IS NULL THEN 0 ELSE 1 END ASC, mastery_score ASC, review_count ASC",
            limit: limit
        )
    }

    private func artifactKind(from summaryType: String) -> StudyArtifactKind {
        switch summaryType {
        case "executive_summary": return .summaryGenerator
        case "detailed_summary": return .summaryGenerator
        case "exam_revision_summary": return .examPrep
        default: return .summaryGenerator
        }
    }

    private func conceptIDs(for studyData: NoteStudyData) -> [String] {
        let fromSnapshot = studyData.knowledgeSnapshot.concepts.map { normalizeConceptKey($0.id.uuidString.isEmpty ? $0.title : $0.id.uuidString) }
        let fromMemory = studyData.learningMemory.map { normalizeConceptKey($0.concept) }
        return Array(Set(fromSnapshot + fromMemory)).sorted()
    }

    private func matchedConceptIDs(for text: String, fallback: [String], studyData: NoteStudyData) -> [String] {
        let lower = text.lowercased()
        let conceptPairs = studyData.knowledgeSnapshot.concepts.map { concept in
            (id: normalizeConceptKey(concept.id.uuidString), title: concept.title.lowercased(), aliases: concept.aliases.map { $0.lowercased() })
        }
        let matches = conceptPairs.compactMap { concept -> String? in
            if lower.contains(concept.title) { return concept.id }
            if concept.aliases.contains(where: { lower.contains($0) }) { return concept.id }
            return nil
        }
        return matches.isEmpty ? fallback : Array(Set(matches + fallback.prefix(1)))
    }

    private func normalizeConceptKey(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func studentConcepts(ordering: String, limit: Int) throws -> [StudentConceptRecord] {
        try queue.sync {
            let rows = try database.fetch(
                """
                SELECT concept_id, mastery_score, confidence_score, last_reviewed, mistake_count, review_count, created_at, updated_at
                FROM student_concepts
                ORDER BY \(ordering)
                LIMIT ?
                """,
                bindings: [.integer(Int64(limit))]
            )
            return rows.compactMap { row in
                guard let conceptID = row.string("concept_id") else { return nil }
                return StudentConceptRecord(
                    conceptID: conceptID,
                    masteryScore: row.double("mastery_score") ?? 0,
                    confidenceScore: row.double("confidence_score") ?? 0.5,
                    lastReviewed: Self.date(from: row.string("last_reviewed")),
                    mistakeCount: row.int("mistake_count") ?? 0,
                    reviewCount: row.int("review_count") ?? 0,
                    createdAt: Self.date(from: row.string("created_at")) ?? Date(),
                    updatedAt: Self.date(from: row.string("updated_at")) ?? Date()
                )
            }
        }
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        let data = (try? JSONEncoder().encode(values)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeStringArray(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func decodeDictionary(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func encodeDictionary(_ dictionary: [String: String]) -> String {
        let data = (try? JSONEncoder().encode(dictionary)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func string(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    private func ensureColumn(table: String, column: String, definition: String) throws {
        let rows = try database.fetch("PRAGMA table_info(\(table))")
        let columns = Set(rows.compactMap { $0.string("name") })
        guard columns.contains(column) == false else { return }
        try database.execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }
}
