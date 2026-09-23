# Performance Notes

## Bottlenecks Reviewed

- Dashboard loading now gathers mastery, graph statistics, daily plan, scheduled reviews, recommendations, and learning gaps in one view-model refresh path.
- Graph Explorer renders bounded subgraphs through `GraphVisualizationService` and keeps visible nodes/edges capped by the view model.
- Retention and review scheduling use existing student concept records and avoid new persistence or graph traversals.

## Optimizations Applied

- Dashboard work is collected off the main actor before publishing a single snapshot back to the UI.
- Graph Explorer visualization remains bounded by node, edge, and radius limits to avoid runaway rendering.
- Study planning now reuses scheduled review results and preserves overdue review priority without additional storage.
- Loading states use stable dashboard structure with redacted placeholders to reduce layout jumps.

## Remaining Risks

- Several graph and learning services still read from shared singleton repositories, which contributes to Swift concurrency warnings under stricter checking.
- Some dashboard and graph calculations still call multiple services that may each query SQLite independently during one refresh.
- Full graph rendering remains a simple deterministic layout; very dense graphs may need clustering or progressive disclosure before large-library use.
- The full XCTest suite includes long-running local model evaluation tests and may not be appropriate for ordinary build validation.
