# Notinq Stabilization Plan

## Objective

Resolve confirmed HIGH-severity defects and establish a stabilization-ready baseline before feature development resumes.

## Prerequisites

- Audit approved (AUDIT_REPORT.md, DEFECT_BACKLOG.md reviewed)
- Working tree preserved; all fixes on a dedicated branch

---

## Phase S1: Remove Main-Thread Blocking (P1)

**Target:** AUD-001, AUD-003

### S1.1: Convert semaphore-blocked extraction to async

**Files:** `StudyView.swift`

1. Convert `extractedStudyKnowledgeSnapshot()` and `extractedStructuredKnowledge()` to `async` functions.
2. Replace the `DispatchSemaphore` + `Task` pattern with direct `await`.
3. Update callers (`buildLearningInsightsAnalysis`, `buildKeyConceptInsights`, `buildConceptMap`) to be `async`.
4. Add loading states to the UI while extraction runs.
5. Verify no deadlock path exists in the extraction pipeline.

**Acceptance criteria:**
- No `DispatchSemaphore` usage remains in StudyView.swift.
- Study generation completes without UI freezing.
- Existing study-related tests continue to pass.

### S1.2: Make NoteService save non-blocking

**Files:** `NoteService.swift`, `AppState.swift`

1. Convert `NoteService.saveFolders()` to use `queue.async` or make it `async`.
2. Debounce saves in AppState (coalesce rapid mutations).
3. Ensure `loadFolders()` remains synchronous at init (acceptable one-time cost).
4. Guard against concurrent in-flight saves (cancel or coalesce).

**Acceptance criteria:**
- Note editing does not block the main thread.
- Saves complete reliably within 100ms for typical note counts.
- No data loss from debounced saves.

---

## Phase S2: Fix Silent Persistence Failures (P1)

**Target:** AUD-002, AUD-004

### S2.1: Surface initialization errors

**Files:** `NoteRepository.swift`

1. Replace `try?` with `try` in `init` for `createSchemaIfNeeded()` and `migrateIfNeeded()`.
2. Either make `init` throwing or add an `isReady` flag with error reporting.
3. Add logging for initialization failures.
4. Add a test for initialization with a corrupt database.

### S2.2: Handle study data persist errors

**Files:** `NoteRepository.swift`

1. Replace `try?` on `studyRepository.persist()` with proper error handling.
2. Log errors. Consider including study persist in the main transaction.
3. Add a test verifying study data roundtrips correctly.

**Acceptance criteria:**
- Schema creation failures are logged and surfaced.
- Study data persist errors are logged (at minimum).
- Tests verify error paths.

---

## Phase S3: Improve Persistence Robustness (P2)

**Target:** AUD-005, AUD-006, AUD-007

### S3.1: Replace force-try fallback

**Files:** `SQLiteDatabase.swift`

1. Replace `try!` with a graceful fallback or fatalError with a descriptive message.

### S3.2: Move FTS rebuild into transaction

**Files:** `NoteRepository.swift`

1. Move `rebuildNotesFTS()` inside the transaction block in `saveFolders()`.
2. Alternatively, use SQLite FTS triggers for automatic sync.

### S3.3: Implement incremental save (optional, deferred)

**Files:** `NoteRepository.swift`, `NoteService.swift`

1. Track changed notes by content hash.
2. Only update changed rows instead of full delete+reinsert.
3. Update FTS incrementally for changed notes only.

**Note:** S3.3 is recommended but can be deferred if S1.2 (async saves) sufficiently reduces perceived latency.

**Acceptance criteria:**
- No `try!` in production persistence code.
- FTS is transactionally consistent with note data.

---

## Phase S4: Add Critical Test Coverage (P2)

**Target:** AUD-008

### S4.1: AI proposal lifecycle tests

1. Test proposal creation with valid selection.
2. Test staleness detection (document changed between proposal creation and acceptance).
3. Test note-switch guard (proposal for note A rejected when note B is selected).
4. Test accept, reject, and edit paths.

### S4.2: AppState persistence roundtrip tests

1. Test save/load cycle preserves folders, notes, and study data.
2. Test that `ensureSelection()` recovers from missing data.
3. Test concurrent save/load behavior.

### S4.3: NoteService concurrent access test

1. Test that concurrent saves do not corrupt data.
2. Test that save during load does not produce inconsistent state.

**Acceptance criteria:**
- At least 10 new tests covering editor and persistence workflows.
- All existing 334 tests continue to pass.

---

## Minimum Conditions for Next Phase

Before feature work resumes, all of the following must be true:

1. No `DispatchSemaphore` usage on paths reachable from the main thread.
2. `NoteService.saveFolders()` does not block the main thread.
3. Schema initialization errors are logged and handled.
4. Study data persist errors are logged.
5. No `try!` in persistence code.
6. FTS rebuild is transactionally consistent.
7. At least basic test coverage for AI proposal accept/reject.
8. All 334+ tests pass.

---

## Dependency Graph

```
S1.1 (semaphore removal) ──────────────────────────────┐
                                                        ├──> S4 (test coverage)
S1.2 (async saves) ─────> S3.3 (incremental saves)    │
                                                        │
S2.1 (init error handling) ────────────────────────────┤
S2.2 (study persist errors) ───────────────────────────┤
                                                        │
S3.1 (force-try removal) ─────────────────────────────┤
S3.2 (FTS in transaction) ────────────────────────────┘
```

S1 and S2 are independent and can be worked in parallel. S3 depends on S1.2 for optimal ordering. S4 should be done last to cover the fixed behavior.

---

## Estimated Scope

| Phase | Files changed | Risk | Effort |
|---|---|---|---|
| S1.1 | 1 (StudyView.swift) | Medium - async conversion in large file | Small-medium |
| S1.2 | 2 (NoteService, AppState) | Medium - concurrency change | Medium |
| S2.1 | 1 (NoteRepository) | Low - error handling change | Small |
| S2.2 | 1 (NoteRepository) | Low - error handling change | Small |
| S3.1 | 1 (SQLiteDatabase) | Low - one line | Trivial |
| S3.2 | 1 (NoteRepository) | Low - move code into block | Small |
| S3.3 | 2 (NoteRepository, NoteService) | Medium - persistence redesign | Medium-large |
| S4 | 3+ (new test files) | Low - additive | Medium |
