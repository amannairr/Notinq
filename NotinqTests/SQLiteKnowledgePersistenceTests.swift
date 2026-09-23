import Foundation
import XCTest
@testable import Notinq

final class SQLiteKnowledgePersistenceTests: XCTestCase {
    private let migrationKey = "notinq.sqlite.legacyNotesMigrated"
    private var databaseURL: URL!
    private var database: SQLiteDatabase!
    private var migrationManager: MigrationManager!
    private var studyRepository: StudyRepository!
    private var noteRepository: NoteRepository!
    private var knowledgeRepository: KnowledgeRepository!
    private var searchService: SearchService!
    private var noteService: NoteService!
    private var syncService: TestKnowledgeSyncService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.removeObject(forKey: migrationKey)

        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notinq-tests-")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")

        database = try SQLiteDatabase(url: databaseURL)
        migrationManager = MigrationManager(legacyNotesURL: legacyNotesURL)
        studyRepository = StudyRepository(database: database)
        noteRepository = NoteRepository(
            database: database,
            migrationManager: migrationManager,
            studyRepository: studyRepository,
            performMigration: false
        )
        knowledgeRepository = KnowledgeRepository(database: database)
        syncService = TestKnowledgeSyncService(database: database)
        noteService = NoteService(repository: noteRepository, knowledgeService: syncService)

        let lexical = LexicalRetriever(noteRepository: noteRepository, knowledgeRepository: knowledgeRepository)
        let graph = GraphRetriever(knowledgeRepository: knowledgeRepository)
        let hybrid = HybridRetriever(
            lexicalRetriever: lexical,
            graphRetriever: graph,
            vectorRetriever: VectorRetriever.shared
        )
        searchService = SearchService(retriever: hybrid)
    }

    override func tearDownWithError() throws {
        searchService = nil
        knowledgeRepository = nil
        noteRepository = nil
        studyRepository = nil
        migrationManager = nil
        database = nil
        noteService = nil
        syncService = nil

        if let databaseURL {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        try? FileManager.default.removeItem(at: legacyNotesURL)
        UserDefaults.standard.removeObject(forKey: migrationKey)
        try super.tearDownWithError()
    }

    func testLegacyNotesMigrationMovesStudyDataIntoSQLite() throws {
        let note = makeNote(
            title: "Cell Theory",
            content: "Cells are the basic unit of life.",
            studyData: makeStudyData()
        )
        let folder = NoteFolder(title: "Biology", notes: [note])
        try writeLegacyPayload(folders: [folder])

        try migrationManager.migrateIfNeeded(database: database)

        let loadedFolders = try noteRepository.loadFolders()
        XCTAssertEqual(loadedFolders.count, 1)
        XCTAssertEqual(loadedFolders.first?.title, "Biology")
        XCTAssertEqual(loadedFolders.first?.notes.first?.title, "Cell Theory")
        XCTAssertEqual(loadedFolders.first?.notes.first?.studyData.flashcards.count, 1)
        XCTAssertEqual(loadedFolders.first?.notes.first?.studyData.artifacts.count, 1)
        XCTAssertEqual(loadedFolders.first?.notes.first?.studyData.learningMemory.count, 1)

        let persistedStudyData = try studyRepository.studyData(for: note.id, noteTitle: note.title)
        XCTAssertEqual(persistedStudyData.flashcards.count, 1)
        XCTAssertEqual(persistedStudyData.artifacts.count, 1)
        XCTAssertEqual(persistedStudyData.learningMemory.count, 1)
    }

    func testFTSSearchReturnsSavedNotes() throws {
        let note = makeNote(
            title: "Photosynthesis",
            content: "Photosynthesis converts light energy into chemical energy."
        )
        try noteRepository.saveFolders([NoteFolder(title: "Biology", notes: [note])])

        let results = try noteRepository.searchNotes(query: "chemical energy", limit: 10)
        XCTAssertEqual(results.first?.noteID, note.id)
        XCTAssertEqual(results.first?.noteTitle, "Photosynthesis")
        XCTAssertTrue(results.first?.snippet.localizedCaseInsensitiveContains("chemical energy") ?? false)
    }

    func testChunkIndexingPersistsChunksAndSupportsSearch() throws {
        let note = makeNote(
            title: "Geology",
            content: "Granite is an igneous rock.\n\nMagma cools slowly underground to form large crystals."
        )
        try noteRepository.saveFolders([NoteFolder(title: "Earth Science", notes: [note])])

        let structure = DocumentPreprocessor.shared.preprocess(title: note.title, text: note.content)
        let chunks = SemanticChunker.shared.chunk(
            title: note.title,
            structure: structure,
            contextLimit: Int(AIRuntimeConfig.current.llama.contextSize)
        )
        try knowledgeRepository.persist(
            noteID: note.id,
            noteTitle: note.title,
            noteContent: note.content,
            chunks: chunks,
            extraction: nil
        )
        try knowledgeRepository.persist(
            noteID: note.id,
            noteTitle: note.title,
            noteContent: note.content,
            chunks: chunks,
            extraction: nil
        )

        let storedChunks = try knowledgeRepository.chunks(for: note.id)
        XCTAssertEqual(storedChunks.count, chunks.count)

        let hits = try knowledgeRepository.searchChunks(query: "igneous rock", limit: 10)
        XCTAssertEqual(hits.first?.noteID, note.id)
        XCTAssertEqual(hits.first?.noteTitle, note.title)
        XCTAssertTrue(hits.first?.snippet.localizedCaseInsensitiveContains("igneous rock") ?? false)
    }

    func testConceptPersistenceStoresAliasesAndRelationships() throws {
        let note = makeNote(
            title: "Neuron Basics",
            content: "Neurons transmit electrical signals across synapses."
        )
        try noteRepository.saveFolders([NoteFolder(title: "Biology", notes: [note])])

        let structure = DocumentPreprocessor.shared.preprocess(title: note.title, text: note.content)
        let chunks = SemanticChunker.shared.chunk(
            title: note.title,
            structure: structure,
            contextLimit: Int(AIRuntimeConfig.current.llama.contextSize)
        )

        var extraction = StructuredKnowledge()
        var neuron = KnowledgeConcept()
        neuron.id = "concept-neuron"
        neuron.name = "Neuron"
        neuron.definition = "A cell that transmits signals."
        neuron.aliases = ["nerve cell"]
        neuron.section = "Biology"
        neuron.source = note.title
        neuron.confidence = 0.97

        var synapse = KnowledgeConcept()
        synapse.id = "concept-synapse"
        synapse.name = "Synapse"
        synapse.definition = "A junction between neurons."
        synapse.aliases = ["neural junction"]
        synapse.section = "Biology"
        synapse.source = note.title
        synapse.confidence = 0.91

        var relationship = KnowledgeRelationship()
        relationship.id = "relationship-neuron-synapse"
        relationship.sourceID = neuron.id
        relationship.targetID = synapse.id
        relationship.relationKind = .relatedTo
        relationship.relation = KnowledgeRelationshipKind.relatedTo.rawValue
        relationship.confidence = 0.84

        extraction.concepts = [neuron, synapse]
        extraction.relationships = [relationship]

        try knowledgeRepository.persist(
            noteID: note.id,
            noteTitle: note.title,
            noteContent: note.content,
            chunks: chunks,
            extraction: extraction
        )
        try knowledgeRepository.persist(
            noteID: note.id,
            noteTitle: note.title,
            noteContent: note.content,
            chunks: chunks,
            extraction: extraction
        )

        let concepts = try knowledgeRepository.concepts(for: note.id)
        XCTAssertEqual(concepts.count, 2)
        XCTAssertTrue(concepts.contains { $0.canonicalName == "Neuron" && $0.aliases.contains("nerve cell") })
        XCTAssertTrue(concepts.contains { $0.canonicalName == "Synapse" && $0.aliases.contains("neural junction") })

        let relationships = try knowledgeRepository.relationships(for: note.id)
        XCTAssertEqual(relationships.count, 1)
        XCTAssertEqual(relationships.first?.sourceConceptID, neuron.id)
        XCTAssertEqual(relationships.first?.targetConceptID, synapse.id)
        XCTAssertEqual(relationships.first?.relationType, KnowledgeRelationshipKind.relatedTo.rawValue)
    }

    func testHybridRetrieverRanksExactNoteMatchesFirst() throws {
        let note = makeNote(
            title: "Cell Membrane",
            content: "The cell membrane regulates transport across the cell boundary."
        )
        let folder = NoteFolder(title: "Biology", notes: [note])
        try noteRepository.saveFolders([folder])

        let structure = DocumentPreprocessor.shared.preprocess(title: note.title, text: note.content)
        let chunks = SemanticChunker.shared.chunk(
            title: note.title,
            structure: structure,
            contextLimit: Int(AIRuntimeConfig.current.llama.contextSize)
        )

        var extraction = StructuredKnowledge()
        var concept = KnowledgeConcept()
        concept.id = "concept-cell-membrane"
        concept.name = "Cell membrane"
        concept.definition = "The boundary around a cell."
        concept.aliases = ["cell membrane"]
        concept.section = "Biology"
        concept.source = note.title
        concept.confidence = 0.95
        extraction.concepts = [concept]

        try knowledgeRepository.persist(
            noteID: note.id,
            noteTitle: note.title,
            noteContent: note.content,
            chunks: chunks,
            extraction: extraction
        )

        let results = searchService.search(
            SearchRequest(
                query: "cell membrane",
                currentNoteID: nil,
                folders: [folder]
            )
        )

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.noteID, note.id)
        XCTAssertEqual(results.first?.sourceKind, .note)
        XCTAssertTrue(results.contains { $0.sourceKind == .chunk })
        XCTAssertTrue(results.contains { $0.sourceKind == .concept })
    }

    func testNoteServiceCRUDPersistsAndUpdatesSQLite() throws {
        var folders: [NoteFolder] = []

        let folder = noteService.createFolder(named: "Science", folders: &folders)
        XCTAssertEqual(folders.count, 1)

        guard let createdNote = noteService.createNote(in: folder.id, folders: &folders) else {
            return XCTFail("Expected note creation to succeed")
        }

        noteService.updateFolderTitle(folder.id, title: "Biology", folders: &folders)
        noteService.renameNote(createdNote.id, title: "Cell Structure", folders: &folders)
        noteService.updateNoteContent(createdNote.id, content: "Cells contain membranes and organelles.", folders: &folders)

        let reloadedFolders = try noteRepository.loadFolders()
        XCTAssertEqual(reloadedFolders.first?.title, "Biology")
        XCTAssertEqual(reloadedFolders.first?.notes.last?.title, "Cell Structure")
        XCTAssertTrue(reloadedFolders.first?.notes.last?.content.contains("membranes") ?? false)

        let searchResults = try noteRepository.searchNotes(query: "membranes", limit: 10)
        XCTAssertEqual(searchResults.first?.noteID, createdNote.id)
        XCTAssertEqual(searchResults.first?.noteTitle, "Cell Structure")

        XCTAssertGreaterThan(syncService.ingestCount, 0)
        assertRequiredTablesExist()
    }

    func testNoteDeletionRemovesDependentRecordsAndAvoidsDuplicates() throws {
        var folders: [NoteFolder] = [
            NoteFolder(
                title: "Biology",
                notes: [
                    makeNote(title: "Cell Membrane", content: "The membrane controls transport."),
                    makeNote(title: "Mitochondria", content: "Mitochondria generate ATP.")
                ]
            )
        ]

        try noteRepository.saveFolders(folders)

        let noteToDelete = folders[0].notes[0]
        noteService.deleteNote(noteToDelete.id, folders: &folders)

        let remainingFolders = try noteRepository.loadFolders()
        XCTAssertEqual(remainingFolders.first?.notes.count, 1)
        XCTAssertEqual(try knowledgeRepository.chunks(for: noteToDelete.id).count, 0)
        XCTAssertEqual(try knowledgeRepository.concepts(for: noteToDelete.id).count, 0)
        XCTAssertEqual(try knowledgeRepository.relationships(for: noteToDelete.id).count, 0)

        let currentNote = remainingFolders.first?.notes.first
        XCTAssertEqual(currentNote?.title, "Mitochondria")

        let beforeRepeatSaveChunks = try knowledgeRepository.searchChunks(query: "ATP", limit: 10).count
        noteService.saveFolders(remainingFolders)
        let afterRepeatSaveChunks = try knowledgeRepository.searchChunks(query: "ATP", limit: 10).count
        XCTAssertEqual(beforeRepeatSaveChunks, afterRepeatSaveChunks)
    }

    func testRestartReloadsPersistedSQLiteState() throws {
        noteService.saveFolders([
            NoteFolder(
                title: "Physics",
                notes: [makeNote(title: "Momentum", content: "Momentum equals mass times velocity.")]
            )
        ])

        let restartDatabase = try SQLiteDatabase(url: databaseURL)
        let restartStudyRepository = StudyRepository(database: restartDatabase)
        let restartNoteRepository = NoteRepository(database: restartDatabase, studyRepository: restartStudyRepository, performMigration: false)
        let loadedFolders = try restartNoteRepository.loadFolders()

        XCTAssertEqual(loadedFolders.count, 1)
        XCTAssertEqual(loadedFolders.first?.title, "Physics")
        XCTAssertEqual(loadedFolders.first?.notes.first?.title, "Momentum")
        XCTAssertTrue(loadedFolders.first?.notes.first?.content.contains("velocity") ?? false)
    }

    func testStudentConceptMasteryAndReviewEventsPersistThroughMasteryTracker() throws {
        let note = makeNote(title: "Neuron Basics", content: "Neurons transmit signals across synapses.")
        try noteRepository.saveFolders([NoteFolder(title: "Biology", notes: [note])])

        let conceptID = "concept-neuron"
        let studentConceptService = StudentConceptService(repository: StudentConceptRepository(studyRepository: studyRepository))

        let updated = try studentConceptService.updateMastery(
            conceptID: conceptID,
            noteID: note.id,
            outcome: .partial,
            source: .question,
            questionID: UUID(),
            flashcardID: nil,
            reviewedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(updated.reviewCount, 1)
        XCTAssertEqual(updated.mistakeCount, 0)
        XCTAssertGreaterThan(updated.masteryScore, 0)
        XCTAssertGreaterThan(updated.confidenceScore, 0.5)

        let persisted = try studentConceptService.studentConcept(noteID: note.id, conceptID: conceptID)
        XCTAssertEqual(persisted?.reviewCount, 1)
        XCTAssertEqual(persisted?.mistakeCount, 0)
        XCTAssertEqual(persisted?.masteryScore, updated.masteryScore)

        let events = try ReviewEventStore(repository: studyRepository).history(for: conceptID)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.result, StudentKnowledgeReviewOutcome.partial.rawValue)
        XCTAssertNotNil(events.first?.questionID)
    }

    func testFlashcardAndQuestionConceptIDsPersistAndReload() throws {
        let note = makeNote(title: "Cell Theory", content: "Cells are the basic unit of life.")
        try noteRepository.saveFolders([NoteFolder(title: "Biology", notes: [note])])

        var studyData = NoteStudyData()
        studyData.flashcards = [
            StudyFlashcard(
                type: .concept,
                front: "What is a neuron?",
                back: "A nerve cell.",
                whyItMatters: "It transmits signals.",
                conceptIDs: ["concept-neuron"]
            )
        ]
        studyData.quizSets = [
            StudyQuizSet(
                title: "Biology Quiz",
                questions: [
                    StudyQuizQuestion(
                        type: .shortAnswer,
                        prompt: "Explain the neuron.",
                        correctAnswer: "A nerve cell",
                        conceptIDs: ["concept-neuron", "concept-synapse"]
                    )
                ]
            )
        ]
        studyData.lastGeneratedAt = Date(timeIntervalSince1970: 1_700_000_100)

        try studyRepository.persist(noteID: note.id, noteTitle: note.title, studyData: studyData)

        let flashcards = try studyRepository.flashcards(for: note.id)
        let questions = try studyRepository.questions(for: note.id)

        XCTAssertEqual(flashcards.count, 1)
        XCTAssertEqual(flashcards.first?.conceptIDs, ["concept-neuron"])
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions.first?.conceptIDs, ["concept-neuron", "concept-synapse"])
    }

    func testStudyAnalyticsServiceRanksWeakAndStrongConcepts() throws {
        let note = makeNote(title: "ATP Basics", content: "ATP stores energy for cellular work.")
        try noteRepository.saveFolders([NoteFolder(title: "Biology", notes: [note])])

        let studentConceptService = StudentConceptService(repository: StudentConceptRepository(studyRepository: studyRepository))
        _ = try studentConceptService.updateMastery(
            conceptID: "concept-atp",
            noteID: note.id,
            outcome: .correct,
            source: .flashcard,
            flashcardID: UUID()
        )
        _ = try studentConceptService.updateMastery(
            conceptID: "concept-glucose",
            noteID: note.id,
            outcome: .incorrect,
            source: .question,
            questionID: UUID()
        )

        let analytics = StudyAnalyticsService(
            studentConceptService: studentConceptService,
            reviewEventStore: ReviewEventStore(repository: studyRepository)
        )

        let weakest = analytics.weakestConcepts(limit: 2)
        let strongest = analytics.strongestConcepts(limit: 2)
        let recent = analytics.recentlyReviewedConcepts(limit: 2)
        let needingReview = analytics.conceptsNeedingReview(limit: 2)

        XCTAssertEqual(weakest.first?.conceptID, "concept-glucose")
        XCTAssertEqual(strongest.first?.conceptID, "concept-atp")
        XCTAssertFalse(recent.isEmpty)
        XCTAssertFalse(needingReview.isEmpty)
    }

    func testContextBuilderIncludesTutorMasteryAndRecentReviewHistory() throws {
        let note = makeNote(title: "Synapse Notes", content: "Synapses transmit signals between neurons.")
        try noteRepository.saveFolders([NoteFolder(title: "Biology", notes: [note])])

        var extraction = StructuredKnowledge()
        var concept = KnowledgeConcept()
        concept.id = "concept-synapse"
        concept.name = "Synapse"
        concept.definition = "A junction between neurons."
        concept.aliases = ["neural junction"]
        concept.section = "Biology"
        concept.source = note.title
        concept.confidence = 0.95
        extraction.concepts = [concept]

        let structure = DocumentPreprocessor.shared.preprocess(title: note.title, text: note.content)
        let chunks = SemanticChunker.shared.chunk(
            title: note.title,
            structure: structure,
            contextLimit: Int(AIRuntimeConfig.current.llama.contextSize)
        )
        try knowledgeRepository.persist(
            noteID: note.id,
            noteTitle: note.title,
            noteContent: note.content,
            chunks: chunks,
            extraction: extraction
        )

        let studentConceptService = StudentConceptService(repository: StudentConceptRepository(studyRepository: studyRepository))
        for _ in 0..<15 {
            _ = try studentConceptService.updateMastery(
                conceptID: "concept-synapse",
                noteID: note.id,
                outcome: .correct,
                source: .flashcard,
                flashcardID: UUID()
            )
        }

        let context = ContextBuilder(
            knowledgeRepository: knowledgeRepository,
            studyRepository: studyRepository,
            studentConceptService: studentConceptService
        ).build(noteID: note.id, title: note.title, text: note.content)

        XCTAssertEqual(context.noteID, note.id)
        XCTAssertFalse(context.studentConcepts.isEmpty)
        XCTAssertFalse(context.recentReviewHistory.isEmpty)
        XCTAssertFalse(context.tutorContext.focusConcepts.isEmpty)
        XCTAssertEqual(context.tutorContext.focusConcepts.first?.conceptID, "concept-synapse")
        XCTAssertEqual(context.tutorContext.explanationStyle, "advanced")
    }

    func testCanonicalConceptResolutionMergesAliasesAcrossNotes() throws {
        let noteA = makeNote(title: "ATP", content: "ATP stores energy.")
        let noteB = makeNote(title: "Adenosine Triphosphate", content: "Adenosine Triphosphate is abbreviated ATP.")
        try noteRepository.saveFolders([NoteFolder(title: "Biology", notes: [noteA, noteB])])

        try persistKnowledge(
            note: noteA,
            concepts: [
                makeConcept(id: "concept-atp", name: "ATP", definition: "Cellular energy currency.", aliases: ["Adenosine Triphosphate"])
            ],
            relationships: []
        )
        try persistKnowledge(
            note: noteB,
            concepts: [
                makeConcept(id: "concept-adenosine-triphosphate", name: "adenosine-triphosphate", definition: "The expanded name for ATP.", aliases: ["ATP"])
            ],
            relationships: []
        )

        let first = try knowledgeRepository.concepts(for: noteA.id)
        let second = try knowledgeRepository.concepts(for: noteB.id)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(first.first?.id, second.first?.id)

        let canonical = try knowledgeRepository.canonicalConcept(named: "Adenosine Triphosphate", aliases: ["adenosine-triphosphate"])
        XCTAssertEqual(canonical?.id, first.first?.id)
        XCTAssertTrue(canonical?.aliases.contains("ATP") ?? false)
    }

    func testCrossNoteGraphTraversalAndRetrievalStitchCanonicalConcepts() throws {
        let energyNote = makeNote(title: "ATP Energy", content: "ATP depends on mitochondria for cellular energy.")
        let organelleNote = makeNote(title: "Mitochondria Organelles", content: "Mitochondria are organelles.")
        try noteRepository.saveFolders([NoteFolder(title: "Biology", notes: [energyNote, organelleNote])])

        let atp = makeConcept(id: "concept-atp", name: "ATP", definition: "Energy currency.", aliases: ["Adenosine Triphosphate"])
        let mitochondria = makeConcept(id: "concept-mitochondria", name: "Mitochondria", definition: "Energy-producing cell structures.")
        try persistKnowledge(
            note: energyNote,
            concepts: [atp, mitochondria],
            relationships: [
                makeRelationship(id: "relationship-atp-mitochondria", sourceID: atp.id, targetID: mitochondria.id, kind: .requires)
            ]
        )

        let mitochondriaAgain = makeConcept(id: "concept-mitochondria-other", name: "mitochondria", definition: "Organelles involved in ATP production.", aliases: ["Mitochondria"])
        let organelle = makeConcept(id: "concept-organelle", name: "Organelle", definition: "Specialized cell structure.")
        try persistKnowledge(
            note: organelleNote,
            concepts: [mitochondriaAgain, organelle],
            relationships: [
                makeRelationship(id: "relationship-mitochondria-organelle", sourceID: mitochondriaAgain.id, targetID: organelle.id, kind: .partOf)
            ]
        )

        let atpID = try XCTUnwrap(try knowledgeRepository.canonicalConcept(named: "ATP")?.id)
        let mitochondriaID = try XCTUnwrap(try knowledgeRepository.canonicalConcept(named: "Mitochondria")?.id)
        let organelleID = try XCTUnwrap(try knowledgeRepository.canonicalConcept(named: "Organelle")?.id)

        XCTAssertEqual(try knowledgeRepository.concepts(for: energyNote.id).first { $0.canonicalName == "Mitochondria" }?.id, mitochondriaID)
        XCTAssertEqual(try knowledgeRepository.concepts(for: organelleNote.id).first { $0.id == mitochondriaID }?.id, mitochondriaID)

        let descendants = try knowledgeRepository.descendants(of: atpID, depth: 2, limit: 10)
        XCTAssertTrue(descendants.contains { $0.id == mitochondriaID })
        XCTAssertTrue(descendants.contains { $0.id == organelleID })

        let path = try knowledgeRepository.shortestPath(from: atpID, to: organelleID, maxDepth: 3)
        XCTAssertEqual(path.map(\.id), [atpID, mitochondriaID, organelleID])

        let graphRetriever = GraphRetriever(knowledgeRepository: knowledgeRepository, maxTraversalDepth: 2)
        let hits = graphRetriever.retrieve(query: "ATP", limit: 12)
        XCTAssertTrue(hits.contains { $0.title.localizedCaseInsensitiveContains("Mitochondria") })
        XCTAssertTrue(hits.contains { $0.title.localizedCaseInsensitiveContains("Organelle") })
    }

    @MainActor
    func testLearningEnginePrioritizesWeakPrerequisitesBeforeDependents() {
        var atp = makeConcept(id: "concept-atp", name: "ATP", definition: "ATP stores energy.", importance: 0.95)
        atp.relationships = ["Mitochondria"]
        let mitochondria = makeConcept(id: "concept-mitochondria", name: "Mitochondria", definition: "Mitochondria produce ATP.", importance: 0.8)

        var relationship = KnowledgeRelationship()
        relationship.id = "relationship-atp-mitochondria"
        relationship.sourceID = atp.id
        relationship.targetID = mitochondria.id
        relationship.relationKind = .requires
        relationship.relation = KnowledgeRelationshipKind.requires.rawValue
        relationship.confidence = 0.95

        var knowledge = StructuredKnowledge(title: "Cell Energy")
        knowledge.concepts = [atp, mitochondria]
        knowledge.relationships = [relationship]

        var existing = NoteStudyData()
        existing.learningMemory = [
            StudyMemoryEntry(concept: "Mitochondria", masteredCount: 0, missedCount: 3),
            StudyMemoryEntry(concept: "ATP", masteredCount: 3, missedCount: 0)
        ]

        let generated = LearningEngine.shared.generateStudyData(from: knowledge, existingStudyData: existing)
        XCTAssertEqual(generated.flashcards.first?.front, "Mitochondria")
        XCTAssertEqual(generated.learningInsights.reviewPriority.first?.title, "Mitochondria")
        XCTAssertTrue(generated.notebookKnowledgeGaps.contains { $0.title == "Mitochondria" })
        XCTAssertTrue(generated.examPrep.difficultConcepts.contains("Mitochondria"))
    }

    private func makeNote(title: String, content: String, studyData: NoteStudyData = NoteStudyData()) -> NoteFile {
        NoteFile(title: title, content: content, studyData: studyData)
    }

    private func makeConcept(
        id: String,
        name: String,
        definition: String,
        aliases: [String] = [],
        importance: Double = 0.8,
        confidence: Double = 0.9
    ) -> KnowledgeConcept {
        var concept = KnowledgeConcept()
        concept.id = id
        concept.name = name
        concept.definition = definition
        concept.aliases = aliases
        concept.importance = importance
        concept.confidence = confidence
        concept.category = "concept"
        return concept
    }

    private func makeRelationship(id: String, sourceID: String, targetID: String, kind: KnowledgeRelationshipKind) -> KnowledgeRelationship {
        var relationship = KnowledgeRelationship()
        relationship.id = id
        relationship.sourceID = sourceID
        relationship.targetID = targetID
        relationship.relationKind = kind
        relationship.relation = kind.rawValue
        relationship.confidence = 0.9
        return relationship
    }

    private func persistKnowledge(note: NoteFile, concepts: [KnowledgeConcept], relationships: [KnowledgeRelationship]) throws {
        let structure = DocumentPreprocessor.shared.preprocess(title: note.title, text: note.content)
        let chunks = SemanticChunker.shared.chunk(
            title: note.title,
            structure: structure,
            contextLimit: Int(AIRuntimeConfig.current.llama.contextSize)
        )
        var extraction = StructuredKnowledge(title: note.title)
        extraction.concepts = concepts
        extraction.relationships = relationships
        try knowledgeRepository.persist(
            noteID: note.id,
            noteTitle: note.title,
            noteContent: note.content,
            chunks: chunks,
            extraction: extraction
        )
    }

    private func makeStudyData() -> NoteStudyData {
        var studyData = NoteStudyData()
        studyData.flashcards = [
            StudyFlashcard(type: .concept, front: "What is ATP?", back: "The cell's energy currency", whyItMatters: "It powers many reactions.")
        ]
        studyData.artifacts = [
            StudyArtifact(
                kind: .summaryGenerator,
                title: "Summary",
                content: "Cells are the basic unit of life.",
                sourceNoteTitle: "Cell Theory",
                generatedAt: Date()
            )
        ]
        studyData.learningMemory = [
            StudyMemoryEntry(concept: "cell", masteredCount: 1, missedCount: 0, reviewHistory: [], lastReviewedAt: Date(), lastOutcome: .correct)
        ]
        studyData.lastGeneratedAt = Date()
        return studyData
    }

    private func writeLegacyPayload(folders: [NoteFolder]) throws {
        let payload = LegacyNotesStoragePayload(
            folders: folders,
            selectedFolderID: folders.first?.id,
            selectedNoteID: folders.first?.notes.first?.id
        )
        try FileManager.default.createDirectory(
            at: legacyNotesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(payload)
        try data.write(to: legacyNotesURL, options: .atomic)
    }

    private var legacyNotesURL: URL {
        let baseURL = databaseURL.deletingPathExtension()
            .appendingPathExtension("legacy")
        return baseURL
            .appendingPathComponent("lumora-notes.json", isDirectory: false)
    }

    private func assertRequiredTablesExist() {
        let rows = try? database.fetch("SELECT name FROM sqlite_master WHERE type = 'table'")
        let names = Set(rows?.compactMap { $0.string("name") } ?? [])
        XCTAssertTrue(names.contains("folders"))
        XCTAssertTrue(names.contains("notes"))
        XCTAssertTrue(names.contains("chunks"))
        XCTAssertTrue(names.contains("concepts"))
        XCTAssertTrue(names.contains("relationships"))
    }
}

private struct LegacyNotesStoragePayload: Codable {
    var folders: [NoteFolder]
    var selectedFolderID: UUID?
    var selectedNoteID: UUID?
}

private final class TestKnowledgeSyncService: KnowledgeSyncing {
    private let knowledgeRepository: KnowledgeRepository
    private let studyRepository: StudyRepository

    private(set) var ingestCount = 0
    private(set) var removeCount = 0

    init(database: SQLiteDatabase) {
        self.knowledgeRepository = KnowledgeRepository(database: database)
        self.studyRepository = StudyRepository(database: database)
    }

    func ingest(note: KnowledgeIngestionRequest) {
        ingestCount += 1
        let structure = DocumentPreprocessor.shared.preprocess(title: note.title, text: note.content)
        let chunks = SemanticChunker.shared.chunk(
            title: note.title,
            structure: structure,
            contextLimit: Int(AIRuntimeConfig.current.llama.contextSize)
        )
        try? knowledgeRepository.persist(
            noteID: note.noteID,
            noteTitle: note.title,
            noteContent: note.content,
            chunks: chunks,
            extraction: nil
        )
    }

    func removeKnowledge(for noteID: UUID) {
        removeCount += 1
        try? studyRepository.remove(noteID: noteID)
        try? knowledgeRepository.remove(noteID: noteID)
    }
}
