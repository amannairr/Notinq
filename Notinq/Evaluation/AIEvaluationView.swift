import SwiftUI

#if DEBUG
struct AIEvaluationView: View {
    @StateObject private var suite = AIEvaluationSuite.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header

                HStack(alignment: .top, spacing: 16) {
                    sidebar
                        .frame(width: 300)
                    detailPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("AI Evaluation")
            .toolbar {
                Button(suite.isRunning ? "Running..." : "Run Evaluation") {
                    Task { await suite.runEvaluation() }
                }
                .disabled(suite.isRunning)

                Button("Open Folder") {
                    suite.openOutputFolder()
                }

                Button("Compare Runs") {
                    suite.comparePreviousRuns()
                }
                .disabled(suite.recentRuns.count < 2)
            }
        }
        .frame(minWidth: 1180, minHeight: 820)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Developer Evaluation")
                .font(.largeTitle.weight(.bold))
            Text(suite.statusMessage)
                .foregroundStyle(.secondary)
            if let run = suite.latestRun {
                Text("Model: \(run.manifest.modelName) | Prompt: \(run.manifest.promptVersion) | Score: \(String(format: "%.3f", run.manifest.averageOverallScore))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionCard(title: "Run Settings") {
                Picker("Note Set", selection: $suite.selectedNoteSet) {
                    ForEach(AIEvaluationNoteSet.allCases, id: \.self) { noteSet in
                        Text(noteSet.title).tag(noteSet)
                    }
                }
                .pickerStyle(.menu)

                Picker("Model", selection: $suite.selectedModelID) {
                    Text("Current Model").tag("")
                    ForEach(suite.availableModels, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.menu)

                Button("Run Evaluation") {
                    Task { await suite.runEvaluation() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(suite.isRunning)
            }

            sectionCard(title: "Notes") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(suite.availableNotes) { note in
                            Button {
                                suite.selectedNoteID = note.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(note.title)
                                        .font(.headline)
                                    Text(note.subject)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(suite.selectedNoteID == note.id ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minHeight: 220)
            }

            sectionCard(title: "Recent Runs") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(suite.recentRuns, id: \.evaluationDate) { run in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(run.modelName)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(run.noteSet) | \(run.resultCount) notes | \(String(format: "%.3f", run.averageOverallScore))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .frame(minHeight: 180)
            }
        }
    }

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let noteResult = suite.selectedNoteResult() {
                    sectionCard(title: "Prompt Snapshot") {
                        ForEach(noteResult.promptsUsed, id: \.feature) { prompt in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(prompt.feature)
                                    .font(.headline)
                                Text(prompt.systemPrompt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(prompt.userPrompt)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding(.bottom, 8)
                        }
                    }

                    sectionCard(title: "Scores") {
                        scoreGrid(result: noteResult)
                    }

                    sectionCard(title: "Performance") {
                        performanceGrid(result: noteResult)
                    }

                    sectionCard(title: "Outputs") {
                        outputGrid(result: noteResult)
                    }

                    sectionCard(title: "Review Prompt") {
                        Text(suite.reviewPrompt())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    sectionCard(title: "External Review Package") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(noteResult.rawNote)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Folder: \(suite.exportReviewPackage()?.path ?? "Unavailable")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Run the evaluation to inspect generated outputs, prompt snapshots, and local scores.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
                }

                if let comparison = suite.comparisonReport {
                    sectionCard(title: "Comparison Report") {
                        Text(comparison.title)
                            .font(.headline)
                        ForEach(comparison.comparisons, id: \.title) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("Delta: \(String(format: "%.3f", item.scoreDelta))")
                                    .font(.caption)
                                if !item.improvements.isEmpty {
                                    Text("Improvements: \(item.improvements.joined(separator: ", "))")
                                        .font(.caption)
                                }
                                if !item.regressions.isEmpty {
                                    Text("Regressions: \(item.regressions.joined(separator: ", "))")
                                        .font(.caption)
                                }
                                if !item.changedOutputs.isEmpty {
                                    Text("Changed: \(item.changedOutputs.joined(separator: ", "))")
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if let regression = suite.regressionReport {
                    sectionCard(title: "Regression Report") {
                        Text(regression.title)
                            .font(.headline)
                        metricRow("Latency Delta", regression.latencyDelta)
                        metricRow("Memory Delta MB", regression.memoryDeltaMB)
                        Text("JSON failures: \(regression.jsonFailures)")
                            .font(.caption)
                        Text("Hallucination delta: \(regression.hallucinationCountDelta)")
                            .font(.caption)
                        ForEach(regression.alerts, id: \.self) { alert in
                            Text(alert)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let benchmark = suite.benchmarkReport {
                    sectionCard(title: "Benchmark Dashboard") {
                        Text("\(benchmark.datasetName) | \(benchmark.noteCount) notes")
                            .font(.headline)
                        ForEach(benchmark.rankings, id: \.modelName) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("#\(item.rank) \(item.modelName) (\(item.promptVersion))")
                                    .font(.subheadline.weight(.semibold))
                                Text("Overall \(String(format: "%.3f", item.overallQuality)) | Summary \(String(format: "%.3f", item.summaryQuality)) | Quiz \(String(format: "%.3f", item.quizQuality))")
                                    .font(.caption)
                                Text("Flashcards \(String(format: "%.3f", item.flashcardQuality)) | Concept \(String(format: "%.3f", item.conceptMapQuality)) | Insights \(String(format: "%.3f", item.learningInsightsQuality))")
                                    .font(.caption)
                                Text("Speed \(String(format: "%.3f", item.speed)) | Memory \(String(format: "%.3f", item.memory)) | JSON \(String(format: "%.3f", item.jsonValidity))")
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if let promptReport = suite.promptImprovementReport {
                    sectionCard(title: "Prompt Improvement Report") {
                        ForEach(promptReport.recommendations, id: \.affectedPrompt) { recommendation in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recommendation.affectedPrompt)
                                    .font(.subheadline.weight(.semibold))
                                Text(recommendation.problem)
                                    .font(.caption)
                                Text(recommendation.evidence)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Recommendation: \(recommendation.recommendedImprovement)")
                                    .font(.caption)
                                Text("Expected benefit: \(recommendation.expectedBenefit)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if let promptComparison = suite.promptVersionComparisonReport {
                    sectionCard(title: "Prompt Version Comparison") {
                        Text("\(promptComparison.baselinePromptVersion) -> \(promptComparison.comparisonPromptVersion)")
                            .font(.headline)
                        ForEach(promptComparison.changes, id: \.identifier) { change in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(change.identifier)
                                    .font(.subheadline.weight(.semibold))
                                Text("Changed prompts: \(change.changedPrompts.joined(separator: ", "))")
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scoreGrid(result: AIEvaluationNoteResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metricRow("Summary", result.localScores.summary.overall)
            metricRow("Flashcards", result.localScores.flashcards.overall)
            metricRow("Quiz", result.localScores.quiz.overall)
            metricRow("Concept Map", result.localScores.conceptMap.overall)
            metricRow("Learning Insights", result.localScores.learningInsights.overall)
            metricRow("Knowledge JSON", result.localScores.knowledgeSnapshot.overall)
            metricRow("Overall", result.localScores.overall)
        }
    }

    private func performanceGrid(result: AIEvaluationNoteResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metricRow("Generation Time", result.performanceMetrics.generationTime)
            metricRow("Tokens / Sec", result.performanceMetrics.tokensPerSecond)
            metricRow("Memory MB", result.performanceMetrics.memoryUsageMB)
            metricRow("Context Size", Double(result.performanceMetrics.contextSize))
            metricRow("Model Load Time", result.performanceMetrics.modelLoadTime)
            Text("Hallucinations: \(result.performanceMetrics.hallucinationCount)")
                .font(.caption)
            if !result.performanceMetrics.latencyByFeature.isEmpty {
                ForEach(result.performanceMetrics.latencyByFeature.sorted(by: { $0.key < $1.key }), id: \.key) { feature, latency in
                    metricRow(feature, latency)
                }
            }
        }
    }

    private func outputGrid(result: AIEvaluationNoteResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Summary")
                .font(.headline)
            Text(result.outputs.summary)
                .textSelection(.enabled)

            Text("Flashcards")
                .font(.headline)
            Text(String(result.outputs.flashcards.count))

            Text("Quiz")
                .font(.headline)
            Text(String(result.outputs.quiz.count))

            Text("Concept Map")
                .font(.headline)
            Text(String(result.outputs.conceptMap.count))
        }
    }

    private func metricRow(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(String(format: "%.3f", value))
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
#endif
