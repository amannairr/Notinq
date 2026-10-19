# Notinq Phase 1 Audit Report

**Date:** 2026-10-19
**Revision:** `a2df39d` (main branch)
**Auditor:** Automated code audit via Claude

---

## Executive Summary

Notinq is a well-structured macOS note-taking and AI-assisted learning application. The project builds successfully and all 334 tests pass. The codebase demonstrates thoughtful architecture, particularly in knowledge extraction, adaptive tutoring, and the AI proposal review workflow.

**No critical (P0) defects were confirmed.** However, four HIGH-severity defects were identified that affect core reliability:

1. `DispatchSemaphore` blocks the UI thread during knowledge extraction (potential deadlock).
2. Critical persistence initialization errors are silently swallowed.
3. Every save operation blocks the main thread synchronously.
4. Study data persistence failures are silent.

These must be resolved before the application can be considered stabilization-ready.

**Release-readiness classification: Development baseline.**

---

## 1. Repository and Architecture Overview

### Project Structure

| Component | Files | Role |
|---|---|---|
| App entry + state | `NotinqApp.swift`, `AppState.swift` | App bootstrap, central state |
| Navigation | `MainContainerView.swift`, `ModeBarView.swift` | Mode-based layout orchestration |
| Editor | `EditorView.swift`, `TextViewBridge.swift`, `AITextView.swift` | Rich text editing with AppKit bridge |
| AI service | `AIService.swift`, `AIProposalCoordinator.swift`, `AIActionPromptBuilder.swift` | LLM orchestration and proposal generation |
| Study | `StudyView.swift`, `TeachMeModels.swift` | Flashcards, quizzes, Teach Me |
| Knowledge | `KnowledgeExtractionModels.swift`, `KnowledgeExtractionCache.swift` | Knowledge extraction and caching |
| Learning | `LearningInsightsAnalysis.swift`, `LearningSignal.swift` | Learning analysis and signals |
| Persistence | `SQLiteDatabase.swift`, `NoteRepository.swift`, `StudyRepository.swift` | SQLite-based persistence |
| Services | 23 files in `Services/` | Graph, adaptive tutoring, recommendations, analytics |
| Prompt system | `PromptBuilder.swift`, `PromptCatalog.swift`, 8 related files | Prompt construction and optimization |
| Local AI | `LlamaProvider.swift`, `InferenceEngine.swift` | llama.cpp integration |

### Architecture Summary

The application uses a mode-based architecture (`dashboard`, `graph`, `notes`, `ai`, `study`, `search`) with `AppState` as the central `ObservableObject`. State mutations trigger `NoteService.saveFolders()` which performs a synchronous full-tree save to SQLite.

The editor uses an AppKit `NSTextView` bridge (`TextViewBridge`) for rich text editing. AI proposals follow a create-review-accept/reject lifecycle with staleness detection and provenance tracking.

Knowledge extraction uses a local LLM (Qwen3-4B via llama.cpp) with heuristic fallback. Results are cached by content signature.

### Key Execution Paths

**Note editing:** `EditorView` -> `AITextView` -> `TextViewBridge` (NSTextView) -> debounced save -> `AppState.updateNoteContent()` -> `NoteService.saveFolders()` -> `NoteRepository` (SQLite)

**AI proposal:** User selects text -> `EditorView.performEditorAction()` -> `AIService.editorProposal()` -> `InferenceEngine.generate()` -> `TextViewBridge.makeAIProposal()` -> `AIProposalPreviewView` -> accept/reject -> `TextViewBridge.acceptAIProposal()`

**Study generation:** `AppState.requestStudyGeneration()` -> `StudyView` -> `KnowledgeExtractionEngine.extractRun()` -> `LearningEngine.generateStudyData()` -> flashcards/quizzes/insights persisted

---

## 2. Build and Test Baseline

### Build

The project builds successfully in Debug configuration in 3.04 seconds with zero errors and zero warnings.

### Tests

**334 tests discovered, 334 passed, 0 failed, 0 skipped.**

Test distribution by area:

| Area | Tests | Quality |
|---|---|---|
| Knowledge extraction | ~30 | Excellent - tests extraction, caching, validation, repair |
| Graph operations | ~35 | Excellent - traversal, alias resolution, cycle protection |
| Prompt system | ~20 | Excellent - 19 prompt types validated |
| Persistence (SQLite) | ~15 | Good - CRUD, FTS, migration, roundtrip |
| Study planning | ~15 | Good - prerequisite ordering, retention, review scheduling |
| Learning/recommendations | ~15 | Good - gap detection, mastery, recommendations |
| Document processing | ~25 | Good - normalization, structure detection, pipeline |
| Evaluation/regression | ~20 | Good - AI evaluation framework |
| TeachMe | ~15 | Good - state transitions, persistence, prioritization |
| Dashboard | ~5 | Good - integration and view model |
| Local AI runtime | ~5 | Good - mock-based generation and streaming |
| Onboarding | 3 | Good - state transitions and persistence |
| UI tests | 4 | Minimal - launch smoke only |

### Coverage Gaps

- **No tests** for: EditorView, TextViewBridge, AITextView, AIProposalPreviewView
- **No tests** for: AppState save/load roundtrip, MainContainerView navigation
- **No tests** for: Concurrent access patterns, race conditions
- **UI tests** are smoke-only (launch + screenshot capture)

---

## 3. Feature Verification Matrix

### A. Application Startup and Navigation

| Feature | Status | Evidence |
|---|---|---|
| App launches successfully | Implemented, unverified | Entry point exists (`NotinqApp.swift`); no runtime verification |
| Mode-based navigation | Implemented, unverified | `MainContainerView` switches on `AppMode` enum; no test coverage |
| Window creation and sizing | Implemented, unverified | `WindowAccessor` present; no test |
| Default folder/note creation | Implemented, unverified | `AppState.ensureSelection()` creates defaults; no test |
| Onboarding flow | Verified | 3 tests cover state transitions and persistence |
| Command palette | Implemented, unverified | `CommandBarView` exists; keyboard shortcut wired; no test |
| Settings overlay | Implemented, unverified | `SettingsOverlayView` exists; no test |

### B. Notes and Rich-Text Editing

| Feature | Status | Evidence |
|---|---|---|
| Create note | Implemented, unverified | `AppState.createNoteInSelectedFolder()` exists; no test |
| Edit note content | Implemented, unverified | `AITextView` + `TextViewBridge`; debounced save; no test |
| Rename note | Implemented, unverified | `AppState.renameNote()` exists; no test |
| Delete note | Implemented, unverified | `AppState.deleteNote()` exists; auto-creates placeholder; no test |
| Create/rename/delete folder | Implemented, unverified | Methods exist in AppState; no test |
| Rich text formatting | Implemented, unverified | Bold/italic/underline/heading via `TextViewBridge`; no test |
| Markdown rendering | Implemented, unverified | `MarkdownRichTextRenderer` exists; no test |
| Text selection | Implemented, unverified | NSTextView selection via bridge; no test |
| Undo/redo | Implemented, unverified | `registerUndoForAIBlockInsertion` exists; no test |
| Copy text | Implemented, unverified | `copySelectedText()` uses NSPasteboard; no test |
| Persistence across restarts | Partial | SQLite persistence exists; roundtrip tested for study data but not for note content specifically |
| Search (FTS) | Verified | `NoteRepository.searchNotes()` tested in `SQLiteKnowledgePersistenceTests` |

### C. AI-Assisted Editing

| Feature | Status | Evidence |
|---|---|---|
| AI editor actions (9 types) | Implemented, unverified | All 9 actions defined in `AIEditorAction` enum; prompt builder tested |
| Proposal creation | Implemented, unverified | `TextViewBridge.makeAIProposal()`; staleness + range clamping; no test |
| Proposal accept | Implemented, unverified | `acceptAIProposal()` inserts AI block with metadata; no test |
| Proposal reject | Implemented, unverified | `rejectAIProposal()` restores selection; no test |
| Proposal edit | Implemented, unverified | `editAIProposal()` updates generated text; no test |
| Staleness detection | Implemented, unverified | `DocumentSnapshot` with FNV-1a hash; checked before accept |
| Note-switch guard | Implemented, unverified | Completion handler checks `selectedNoteID == noteID`; correct logic |
| Cancellation | Partial | `activeProposalTask?.cancel()` called on note switch; AI service checks `Task.isCancelled` after completion but not during computation |
| AI block provenance | Implemented, unverified | `AIBlockSourceInfo` with metadata; inspector view exists |
| AI block follow-up actions | Implemented, unverified | Regenerate, shorter, more detailed, continue; no test |
| Loading state | Verified | Progress indicator shown during generation; visible in EditorView body |
| Adaptive explanation context | Verified | Context building tested in `AdaptiveTutorContextTests` |

### D. Study Tools

| Feature | Status | Evidence |
|---|---|---|
| Flashcard generation | Verified | Tested in `GraphAwareLearningTests`, `NotinqTests` |
| Flashcard review | Implemented, unverified | UI exists in StudyView; no test for review flow |
| Quiz generation | Verified | Tested in `GraphAwareLearningTests`, `NotinqTests` |
| Quiz answering | Implemented, unverified | UI exists in StudyView; no test |
| Teach Me sessions | Verified | 12 tests cover state transitions, prioritization, persistence |
| Knowledge extraction | Verified | 11 tests in `KnowledgeExtractionEngineTests` |
| Extraction caching | Verified | `testRepeatedExtractionUsesCache` passes |
| Study progress persistence | Verified | Tested in `SQLiteKnowledgePersistenceTests` |
| Concept map | Implemented, unverified | `buildConceptMap()` exists; uses semaphore pattern (AUD-001) |
| Exam prep | Implemented, unverified | `buildExamPrep()` exists; no test |

### E. Learning Insights

| Feature | Status | Evidence |
|---|---|---|
| Lecture completeness analysis | Implemented, unverified | `LectureCompletenessAnalysis` model exists; generation uses semaphore (AUD-001) |
| Concept coverage identification | Implemented, unverified | Coverage categories defined; UI in `LearningInsightsWorkspaceView` |
| Knowledge gap detection | Verified | 2 tests in `KnowledgeGapDetectorTests` |
| Source traceability | Implemented, unverified | `AdaptiveExplanationSource` tracks note references; no test |
| Gap-to-editor explanation flow | Implemented, unverified | `requestKnowledgeGapExplanation` -> EditorView proposal; no test |

### F. Knowledge Graph

| Feature | Status | Evidence |
|---|---|---|
| Graph construction | Verified | Tested across multiple test files |
| Graph visualization | Verified | 3 tests in `GraphVisualizationTests` |
| Graph explorer | Verified | 8 tests in `GraphExplorerTests` |
| Path finding | Verified | Tested in `GraphExplanationTests` |
| Bottleneck detection | Verified | Tested in `GraphExplanationTests` |
| Canonical concept resolution | Verified | Tested in `SQLiteKnowledgePersistenceTests` |
| Alias resolution | Verified | Tested in `GraphExplanationTests` |

### G. Persistence and Data Integrity

| Feature | Status | Evidence |
|---|---|---|
| SQLite database creation | Verified | Tested in multiple persistence tests |
| Note CRUD | Verified | `testNoteServiceCRUDPersistsAndUpdatesSQLite` passes |
| Cascading deletion | Verified | `testNoteDeletionRemovesDependentRecordsAndAvoidsDuplicates` passes |
| Restart recovery | Verified | `testRestartReloadsPersistedSQLiteState` passes |
| Schema migration | Implemented, unverified | `MigrationManager` exists; migration errors silently swallowed (AUD-002) |
| Full-text search | Verified | `testFTSSearchReturnsSavedNotes` passes |

### H. Privacy and Performance

| Feature | Status | Evidence |
|---|---|---|
| Local-first processing | Implemented, unverified | Qwen3-4B runs locally via llama.cpp |
| Cloud AI disclosure | Implemented, unverified | `allowCloudAIForComplexTasks` setting exists; `privateNotesMode` available |
| Research instrumentation opt-out | Implemented, unverified | `researchInstrumentationEnabled` preference; toggle in settings |
| Typing performance | **Defective** | Main-thread blocking on every save (AUD-003) |
| Extraction performance | **Defective** | DispatchSemaphore blocks UI thread (AUD-001) |

### I. Accessibility and Distribution

| Feature | Status | Evidence |
|---|---|---|
| Keyboard navigation | Not assessed | Requires runtime testing |
| Accessibility labels | Not assessed | Requires runtime inspection |
| Release build | Blocked | Signing configuration not evaluated |
| Notarization | Blocked | Requires Apple Developer account setup |

---

## 4. Critical User Journey Findings

### Journey A: Create and Edit a Note

**Path:** Create note -> edit content -> format text -> save -> navigate away -> reopen

**Assessment:** The path is implemented end-to-end. `AppState.createNoteInSelectedFolder()` creates a note, `AITextView` renders it via `TextViewBridge`, debounced changes trigger `AppState.updateNoteContent()` -> `NoteService.saveFolders()`.

**Confirmed issue:** Every content change triggers a full save that blocks the main thread (AUD-003). For small datasets this is imperceptible; for larger datasets it causes typing lag.

**Staleness protection:** The `DocumentSnapshot` mechanism correctly detects document changes between proposal creation and acceptance.

**Undo/redo:** AI block insertions register proper undo actions with full document state snapshots. Standard NSTextView undo is available for normal editing.

### Journey B: AI-Assisted Editing

**Path:** Select text -> request action -> receive proposal -> review -> accept/reject

**Assessment:** The path is well-designed with multiple safety checks:
- Selection text and range are captured before generation starts.
- `activeProposalRequestID` prevents duplicate concurrent proposals.
- Completion handler validates that the request ID matches and the note hasn't changed.
- `DocumentSnapshot` marks proposals as stale if the document changed.
- Accept validates `originatingNoteID == selectedNoteID` and `originatingRequestID == activeProposalRequestID`.
- Reject restores the original selection.

**No confirmed data-loss risk** in the proposal workflow. AI proposals INSERT content (they don't replace selected text), and the full document is preserved in the undo stack before insertion.

**Cancellation gap:** `Task.cancel()` is called on note switch, but the AI inference engine may complete its work before checking `Task.isCancelled`. This wastes resources but does not cause incorrect behavior (the stale completion is properly rejected by the guard).

### Journey C: Generate Study Materials

**Path:** Select note -> generate materials -> review flashcards/quizzes

**Assessment:** The path works through `AppState.requestStudyGeneration()` -> `StudyView`. Knowledge extraction uses the `KnowledgeExtractionEngine` with caching.

**Confirmed issue:** The extraction path uses `DispatchSemaphore.wait()` to block the thread while waiting for async extraction (AUD-001). On cache hits, the semaphore is not reached. On cache misses, the UI freezes.

**Study data persistence:** Flashcards and quizzes are persisted via `StudyRepository`. However, persist errors are silently swallowed (AUD-004).

### Journey D: Learning Insights

**Path:** Provide note content -> analyze -> inspect concepts -> navigate to source

**Assessment:** `LearningInsightsAnalysis.swift` provides the analysis model. `LearningInsightsWorkspaceView` presents the results. The analysis depends on the same semaphore-blocked extraction path (AUD-001).

**Knowledge gap to editor flow:** `AppState.requestKnowledgeGapExplanation()` sets a pending request that `EditorView` consumes, triggering an AI proposal. This cross-component communication works but is not tested.

### Journey E: Restart and Recovery

**Assessment:** `AppState.init()` calls `load()` which calls `NoteService.loadFolders()` -> `NoteRepository.loadFolders()`. The SQL schema uses `CREATE TABLE IF NOT EXISTS` for safe re-creation. `ensureSelection()` creates default data if the database is empty.

**Confirmed issue:** If schema creation fails during init, the error is silently swallowed (AUD-002). The app appears to start normally but cannot persist data.

**Study data recovery:** The `note(from:)` method tries `StudyRepository` first and falls back to inline JSON. This provides reasonable recovery.

---

## 5. Defect Register

See [DEFECT_BACKLOG.md](DEFECT_BACKLOG.md) for the full prioritized list with reproduction steps.

### Summary

| Priority | Count | Defects |
|---|---|---|
| P0 (Release blocker) | 0 | - |
| P1 (Core reliability) | 4 | AUD-001, AUD-002, AUD-003, AUD-004 |
| P2 (Feature correctness) | 4 | AUD-005, AUD-006, AUD-007, AUD-008 |
| P3 (Quality/polish) | 3 | AUD-009, AUD-010, AUD-011 |

---

## 6. Concurrency, Editor, and Persistence Risks

### Concurrency

- **DispatchSemaphore (AUD-001):** Two instances in `StudyView.swift` block the calling thread waiting for async work. Risk of deadlock if the async Task requires main actor access. Risk of UI freeze on cache misses.
- **queue.sync (AUD-003):** `NoteService` uses synchronous dispatch for all operations. Called from the main thread via `AppState.save()`.
- **Missing @MainActor (AUD-010):** `AppState` relies on convention for main-thread access. Currently safe but fragile.
- **No detected data races:** All SQLite access is serialized through `queue.sync`. AppState mutations appear to occur only from main-thread SwiftUI callbacks.

### Editor

- **Proposal lifecycle is well-guarded:** Request ID matching, note-switch guards, staleness detection, and undo registration all function correctly by code inspection.
- **No confirmed text corruption risk:** AI blocks are inserted (not replaced), with proper attributed string handling and undo grouping.
- **TextViewBridge observer cleanup:** Uses `deinit` for NotificationCenter cleanup with `weak self` in the observer. Adequate for current usage.

### Persistence

- **Full rewrite strategy (AUD-006):** Every save deletes and reinserts all data. O(n) write amplification.
- **FTS outside transaction (AUD-007):** Search index can become inconsistent if process crashes mid-save.
- **Silent failures (AUD-002, AUD-004):** Schema creation and study data persistence errors are swallowed.
- **WAL mode enabled:** SQLite is configured with WAL journal mode and NORMAL synchronous, which is appropriate for application use.

---

## 7. Crash and Diagnostic Evidence

No crash reports or forced terminations were observed during the audit. The build and test suite completed without crashes.

**Potential crash path identified:** `SQLiteDatabase.makeDefault()` uses `try!` as a last-resort fallback (AUD-005). This would crash at startup if all database URL candidates and in-memory fallback fail. This is extremely unlikely in practice.

No SIGKILL or watchdog evidence was found in the repository.

---

## 8. Release-Readiness Assessment

### Development Baseline (Current State)

| Criterion | Status |
|---|---|
| Builds in Debug | Pass |
| Launches successfully | Not verified (code inspection only) |
| Major views load | Not verified |
| All tests pass | Pass (334/334) |
| No critical data-loss defects | Pass (no confirmed P0) |
| No main-thread blocking | **FAIL** (AUD-001, AUD-003) |
| Persistence errors handled | **FAIL** (AUD-002, AUD-004) |
| AI proposals safe | Pass |
| Study generation safe | Pass (correctness OK; performance defective) |
| Release build verified | Not verified |
| Signing/notarization | Not verified |

### Required for Stabilization-Ready

1. Resolve AUD-001 (semaphore removal)
2. Resolve AUD-003 (async saves)
3. Resolve AUD-002 (initialization error handling)
4. Resolve AUD-004 (study persist error handling)
5. Add basic test coverage for editor and persistence workflows

### Required for Release-Ready (beyond stabilization)

1. Runtime verification of all user journeys
2. Release configuration build verification
3. Code signing and notarization setup
4. Accessibility audit
5. Performance profiling under load
6. Cloud AI provider integration testing (if applicable)

---

## 9. Unverified Assumptions and Limitations

1. **No runtime testing performed.** All findings are based on code inspection and test execution. UI behavior was not verified by launching the application.
2. **AI inference quality not assessed.** The Qwen3-4B model's output quality for extraction, proposals, and study materials was not evaluated.
3. **Cloud AI path not tested.** `GeminiProvider` exists but requires API credentials.
4. **Whisper transcription not tested.** Requires microphone access and audio input.
5. **Accessibility not assessed.** Requires runtime VoiceOver and keyboard-only testing.
6. **Memory profile not measured.** Large note handling and model memory usage not profiled.
7. **Release build not attempted.** Signing, entitlements, and notarization readiness unknown.

---

## 10. Files Created

| File | Purpose |
|---|---|
| `Audit/AUDIT_REPORT.md` | This report |
| `Audit/DEFECT_BACKLOG.md` | Prioritized defect list with reproduction steps |
| `Audit/STABILIZATION_PLAN.md` | Sequenced fix plan with acceptance criteria |
| `Audit/BASELINE.md` | Build/test snapshot and environment details |

No application code, project configuration, or user data was modified during this audit.
