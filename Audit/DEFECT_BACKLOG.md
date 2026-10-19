# Notinq Defect Backlog

Prioritized list of confirmed defects found during the Phase 1 audit. Each defect references the AUDIT_REPORT.md for full context.

---

## P1 - Core Reliability

### AUD-001: DispatchSemaphore blocks thread during knowledge extraction

| Field | Detail |
|---|---|
| **Severity** | High |
| **Confidence** | Confirmed |
| **Affected workflow** | Study materials generation, Learning Insights, Concept Map |
| **Files** | `StudyView.swift:768-781`, `StudyView.swift:1555-1568` |

**Evidence:**
```swift
let semaphore = DispatchSemaphore(value: 0)
var extracted: StructuredKnowledge?
Task {
    let run = await KnowledgeExtractionEngine.shared.extractRun(...)
    extracted = run.knowledge
    semaphore.signal()
}
semaphore.wait()  // Blocks calling thread
```

Two identical patterns exist: `extractedStudyKnowledgeSnapshot()` (line 768) and `extractedStructuredKnowledge()` (line 1555). Both are called from synchronous methods within the SwiftUI view (`buildLearningInsightsAnalysis`, `buildKeyConceptInsights`, `buildConceptMap`).

**Reproduction:** Trigger any study generation or Learning Insights analysis on a note without cached extraction results.

**Expected behavior:** UI remains responsive during extraction.

**Actual behavior:** UI freezes for the duration of knowledge extraction (potentially seconds for LLM-based extraction). Risk of deadlock if the async work attempts main actor access.

**Impact:** Complete UI freeze during study material generation on cache misses. Potential watchdog kills on extended freezes.

**Recommended fix:** Convert `extractedStudyKnowledgeSnapshot` and `extractedStructuredKnowledge` to `async` functions. Replace the semaphore pattern with `await`. Update callers to use `Task { }` with loading state.

**Regression test:** Add a test that calls these methods and verifies completion without blocking the main thread. Use `XCTExpectation` with a timeout.

---

### AUD-002: Silent `try?` swallows critical initialization errors

| Field | Detail |
|---|---|
| **Severity** | High |
| **Confidence** | Confirmed |
| **Affected workflow** | Application startup, all persistence operations |
| **Files** | `NoteRepository.swift:25,27` |

**Evidence:**
```swift
init(...) {
    self.database = database
    self.migrationManager = migrationManager
    self.studyRepository = studyRepository ?? StudyRepository(database: database)
    try? createSchemaIfNeeded()        // Silent failure
    if performMigration {
        try? migrationManager.migrateIfNeeded(database: database)  // Silent failure
    }
}
```

**Reproduction:** Trigger a scenario where schema creation fails (e.g., database file permissions, disk full).

**Expected behavior:** Initialization failure is reported; app shows an error state or recovers.

**Actual behavior:** Init succeeds silently. Subsequent operations fail with cryptic "table not found" errors.

**Impact:** If schema creation fails at launch, the app appears to work but cannot save or load notes. Data entered during the session is lost.

**Recommended fix:** Change `try?` to `try` and propagate errors. Add a `throws` init or an `isReady` flag. Log errors at minimum.

**Regression test:** Test that `NoteRepository(database: corruptDB)` surfaces an error rather than silently proceeding.

---

### AUD-003: `queue.sync` blocks main thread on every save

| Field | Detail |
|---|---|
| **Severity** | High |
| **Confidence** | Confirmed |
| **Affected workflow** | All note editing (every content change triggers save) |
| **Files** | `NoteService.swift:19,25` |

**Evidence:**
```swift
func saveFolders(_ folders: [NoteFolder]) {
    queue.sync {
        let previousFolders = (try? repository.loadFolders()) ?? []
        guard (try? repository.saveFolders(folders)) != nil else { return }
        syncKnowledge(previousFolders: previousFolders, currentFolders: folders)
    }
}
```

Called from `AppState.save()` which is called from every state mutation (`updateNoteContent`, `createFolder`, `deleteNote`, `renameNote`, etc.). The `saveFolders` path includes: loading all folders from DB, deleting all rows, reinserting all rows, rebuilding FTS, persisting study data for each note, and syncing knowledge for all notes.

**Reproduction:** Edit a note with multiple folders and notes. Every debounced keystroke triggers `save()`.

**Expected behavior:** Saves happen asynchronously; typing remains fluid.

**Actual behavior:** Main thread blocks for the duration of the full save cycle. Noticeable as typing lag proportional to dataset size.

**Impact:** Typing lag, UI jank on every save. Worsens linearly with number of notes.

**Recommended fix:** Convert `saveFolders` to `async`. Use `queue.async` with completion or Swift concurrency. Debounce saves at the AppState level (separate from the existing text debounce). Consider incremental saves instead of full rewrite.

**Regression test:** Measure save duration under load. Assert main thread is not blocked during save.

**Dependencies:** Benefits from fixing AUD-006 (incremental saves).

---

### AUD-004: Study data persistence fails silently

| Field | Detail |
|---|---|
| **Severity** | High |
| **Confidence** | Confirmed |
| **Affected workflow** | Study material persistence (flashcards, quizzes, progress) |
| **Files** | `NoteRepository.swift:87-91` |

**Evidence:**
```swift
for folder in folders {
    for note in folder.notes {
        try? studyRepository.persist(noteID: note.id, noteTitle: note.title, studyData: note.studyData)
    }
}
```

Study data persistence uses `try?`, meaning any error (DB constraint violation, disk full, schema mismatch) is silently ignored. This is called after the main note transaction commits, so notes are saved but study data may not be.

**Reproduction:** Corrupt the study tables or trigger a constraint violation during study data persist.

**Expected behavior:** Errors are logged; user is informed if study data cannot be saved.

**Actual behavior:** Study data disappears silently. Flashcards, quiz progress, and learning insights are lost without warning.

**Impact:** Silent loss of study materials and learning progress.

**Recommended fix:** Replace `try?` with proper error handling. At minimum, log the error. Consider including study persist in the same transaction as notes.

**Regression test:** Verify study data roundtrips through save/load. Test error path when study persist fails.

---

## P2 - Feature Correctness

### AUD-005: Force `try!` crash in SQLiteDatabase fallback

| Field | Detail |
|---|---|
| **Severity** | Medium |
| **Confidence** | Confirmed |
| **Affected workflow** | Application startup |
| **Files** | `SQLiteDatabase.swift:66` |

**Evidence:**
```swift
static func makeDefault() -> SQLiteDatabase {
    let preferredURLs = candidateDefaultURLs()
    for url in preferredURLs {
        if let database = try? SQLiteDatabase(url: url) { return database }
    }
    return try! SQLiteDatabase(url: memoryURL)  // Crash if this fails
}
```

**Impact:** If all file-based DB URLs and the in-memory fallback fail, the app crashes on startup. Very unlikely in practice (in-memory SQLite rarely fails), but unrecoverable.

**Recommended fix:** Return an optional or use a sentinel error state instead of `try!`.

---

### AUD-006: Full delete+reinsert save strategy causes write amplification

| Field | Detail |
|---|---|
| **Severity** | Medium |
| **Confidence** | Confirmed |
| **Affected workflow** | All persistence operations |
| **Files** | `NoteRepository.swift:52-83` |

**Evidence:**
```swift
try database.transaction {
    try database.execute("DELETE FROM notes")
    try database.execute("DELETE FROM folders")
    // ... reinsert all folders and notes
}
try rebuildNotesFTS()
```

Every `saveFolders` call deletes all rows and reinserts everything. For N notes, this is O(N) DELETE + O(N) INSERT + O(N) FTS rebuild on every single-character content change.

**Impact:** Unnecessary disk I/O and CPU. Performance degrades linearly with note count. Contributes to the main-thread blocking in AUD-003.

**Recommended fix:** Implement incremental updates: upsert changed notes, delete removed notes, update FTS incrementally. Use content hashing to skip unchanged notes.

---

### AUD-007: FTS index rebuild outside transaction boundary

| Field | Detail |
|---|---|
| **Severity** | Medium |
| **Confidence** | Confirmed |
| **Affected workflow** | Search after save |
| **Files** | `NoteRepository.swift:85` |

**Evidence:** `rebuildNotesFTS()` is called after the main transaction commits. A crash between commit and FTS rebuild leaves search out of sync with note data.

**Impact:** Search returns stale or missing results until the next successful save. Self-healing on next save.

**Recommended fix:** Move FTS rebuild inside the transaction, or use FTS triggers for automatic sync.

---

### AUD-008: Missing test coverage for editor, AI proposals, and UI layer

| Field | Detail |
|---|---|
| **Severity** | Medium |
| **Confidence** | Confirmed |
| **Affected workflow** | Editor, AI proposal workflow, UI navigation |
| **Files** | NotinqTests/, NotinqUITests/ |

**Evidence:** The 334 passing tests cover knowledge extraction, graph operations, study planning, prompt systems, and persistence well. However:

- **No tests** for EditorView, TextViewBridge, AITextView, or the proposal accept/reject lifecycle
- **No tests** for MainContainerView navigation or mode switching
- **No tests** for AppState save/load roundtrips
- **UI tests** are smoke-only (launch + screenshot)
- **No tests** for concurrent access patterns or race conditions

**Impact:** Critical user-facing workflows (editing, AI proposals, navigation) have no automated regression coverage.

**Recommended fix:** Add focused tests for: (1) AI proposal creation, staleness detection, accept/reject; (2) AppState save/load roundtrip; (3) NoteService concurrent access.

---

## P3 - Quality and Polish

### AUD-009: `created_at` timestamp overwritten on every save

| Field | Detail |
|---|---|
| **Severity** | Low |
| **Confidence** | Confirmed |
| **Files** | `NoteRepository.swift:75-76` |

Both `created_at` and `updated_at` columns are set to `note.updatedAt`. The `NoteFile` model lacks a `createdAt` property, so original creation dates are lost.

**Recommended fix:** Add a `createdAt` property to `NoteFile`. Preserve it during saves.

---

### AUD-010: Missing `@MainActor` annotation on AppState

| Field | Detail |
|---|---|
| **Severity** | Low |
| **Confidence** | Confirmed |
| **Files** | `AppState.swift:91` |

AppState has 22 `@Published` properties but no `@MainActor` annotation. Currently safe by convention (only accessed from SwiftUI main-thread callbacks), but fragile against future changes.

**Recommended fix:** Add `@MainActor` to `AppState` class. Audit all mutation sites.

---

### AUD-011: SQL string interpolation in private helper methods

| Field | Detail |
|---|---|
| **Severity** | Low |
| **Confidence** | Confirmed |
| **Files** | `StudyRepository.swift:608-618,664-668` |

`studentConcepts(ordering:)` and `ensureColumn(table:column:definition:)` use string interpolation for SQL fragments. Both are `private` and only called with hardcoded string literals, so there is no external input path. Still represents a code hygiene concern.

**Recommended fix:** Use an enum or validated type for ordering clauses. Add a comment documenting that parameters must be trusted.
