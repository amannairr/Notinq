# Notinq Audit Baseline

## Audit Metadata

| Field | Value |
|---|---|
| Audit date | 2026-10-19 |
| Repository revision | `a2df39d` (Merge study planner review prioritization fix) |
| Working-tree status | Modified (26 tracked files, 1 untracked). No reset performed. |
| Xcode version | Xcode 26 (macOS 26.4 deployment target) |
| Swift version | 5.0 |
| Platform | darwin (Apple Silicon) |
| Scheme | Notinq (default) |
| Destination | macOS (host machine) |

## Build Results

| Metric | Result |
|---|---|
| Build outcome | **SUCCESS** |
| Build time | 3.04 seconds |
| Compiler errors | 0 |
| Compiler warnings | 0 (at default severity) |
| Configuration | Debug |

## Test Results

| Metric | Result |
|---|---|
| Test plan | Notinq |
| Total tests discovered | 334 |
| Passed | 334 |
| Failed | 0 |
| Skipped | 0 |
| Disabled | 0 |
| Expected failures | 0 |

All 334 tests pass deterministically in a single run.

## Project Configuration

- **Targets:** Notinq (app), NotinqTests (unit), NotinqUITests (UI)
- **Dependencies:** Metal, MetalKit, Accelerate (system frameworks); libllama.a, libwhisper.a, libggml*.a (pre-compiled C++ libraries)
- **No SPM packages**
- **Entitlements:** Microphone access (NSMicrophoneUsageDescription)
- **Bundle ID:** amannair.Notinq
- **Version:** 1.0 (build 1)

## Known Limitations

1. Release configuration build was not separately verified (would require full signing setup).
2. UI tests are smoke-only (launch + screenshot); no interactive UI test coverage.
3. Runtime behavior was assessed via code inspection, not live application testing (no simulator/device launch performed during this audit).
4. AI inference behavior depends on the local Qwen3-4B model file; extraction and generation quality were not evaluated.
5. Whisper (speech-to-text) functionality was not testable without microphone access.
6. Cloud AI provider (Gemini) requires API credentials not available during audit.

## Release-Readiness Classification

**Development baseline** - The application builds and all tests pass, but confirmed HIGH-severity defects (main-thread blocking, silent persistence failures) prevent classification as stabilization-ready. See DEFECT_BACKLOG.md for details.
