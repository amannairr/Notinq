import Foundation

protocol AIEvaluationSemanticEvaluator {
    var identifier: String { get }
    func evaluate(
        note: AIEvaluationNote,
        outputs: AIEvaluationOutputs,
        reference: AIEvaluationGoldStandardReference?
    ) async -> AIEvaluationSemanticEvaluationResult?
}

protocol AIEvaluationGoldStandardEvaluator: AIEvaluationSemanticEvaluator {}
protocol AIEvaluationCloudEvaluator: AIEvaluationSemanticEvaluator {}
protocol AIEvaluationEmbeddingEvaluator: AIEvaluationSemanticEvaluator {}

struct AIEvaluationSemanticResultBundle: Codable, Equatable, Sendable {
    var combined: AIEvaluationCombinedReport
    var semantic: AIEvaluationSemanticEvaluationResult?
}

final class AIEvaluationEngine {
    let goldStandardEvaluator: any AIEvaluationGoldStandardEvaluator
    let cloudEvaluator: (any AIEvaluationCloudEvaluator)?
    let embeddingEvaluator: (any AIEvaluationEmbeddingEvaluator)?

    init(
        goldStandardEvaluator: some AIEvaluationGoldStandardEvaluator = AIGoldStandardEvaluator(),
        cloudEvaluator: (any AIEvaluationCloudEvaluator)? = nil,
        embeddingEvaluator: (any AIEvaluationEmbeddingEvaluator)? = nil
    ) {
        self.goldStandardEvaluator = goldStandardEvaluator
        self.cloudEvaluator = cloudEvaluator
        self.embeddingEvaluator = embeddingEvaluator
    }

    func combinedReport(
        note: AIEvaluationNote,
        outputs: AIEvaluationOutputs,
        localScores: AIEvaluationLocalScores,
        performanceMetrics: AIEvaluationPerformanceMetrics,
        reference: AIEvaluationGoldStandardReference?
    ) async -> AIEvaluationSemanticResultBundle {
        let semantic = await goldStandardEvaluator.evaluate(note: note, outputs: outputs, reference: reference)
        let heuristicScore = localScores.overall
        let semanticScore = semantic?.overallScore ?? heuristicScore
        let overallScore = (heuristicScore * 0.7) + (semanticScore * 0.3)
        let signals = [
            heuristicScore >= 0.8 ? "strong_heuristic_performance" : "heuristic_coverage_needs_work",
            semanticScore >= 0.8 ? "strong_gold_standard_alignment" : "gold_standard_alignment_gap"
        ]

        let combined = AIEvaluationCombinedReport(
            evaluatorID: goldStandardEvaluator.identifier,
            heuristicScore: heuristicScore,
            semanticScore: semanticScore,
            overallScore: overallScore,
            heuristicExplanation: explanation(for: localScores),
            semanticExplanation: semantic?.explanations.joined(separator: " ") ?? "No semantic evaluator result was produced.",
            overallExplanation: "Weighted 70% heuristic, 30% semantic when semantic reference data exists.",
            signals: signals + performanceSignals(from: performanceMetrics)
        )

        return AIEvaluationSemanticResultBundle(combined: combined, semantic: semantic)
    }

    func regressionReport(
        baseline: AIEvaluationNoteResult,
        comparison: AIEvaluationNoteResult
    ) -> AIEvaluationRegressionReport {
        let scoreDeltas: [AIEvaluationRegressionDelta] = [
            AIEvaluationRegressionDelta(metric: "overall", baseline: baseline.localScores.overall, comparison: comparison.localScores.overall, delta: comparison.localScores.overall - baseline.localScores.overall),
            AIEvaluationRegressionDelta(metric: "summary", baseline: baseline.localScores.summary.overall, comparison: comparison.localScores.summary.overall, delta: comparison.localScores.summary.overall - baseline.localScores.summary.overall),
            AIEvaluationRegressionDelta(metric: "flashcards", baseline: baseline.localScores.flashcards.overall, comparison: comparison.localScores.flashcards.overall, delta: comparison.localScores.flashcards.overall - baseline.localScores.flashcards.overall),
            AIEvaluationRegressionDelta(metric: "quiz", baseline: baseline.localScores.quiz.overall, comparison: comparison.localScores.quiz.overall, delta: comparison.localScores.quiz.overall - baseline.localScores.quiz.overall),
            AIEvaluationRegressionDelta(metric: "concept_map", baseline: baseline.localScores.conceptMap.overall, comparison: comparison.localScores.conceptMap.overall, delta: comparison.localScores.conceptMap.overall - baseline.localScores.conceptMap.overall),
            AIEvaluationRegressionDelta(metric: "learning_insights", baseline: baseline.localScores.learningInsights.overall, comparison: comparison.localScores.learningInsights.overall, delta: comparison.localScores.learningInsights.overall - baseline.localScores.learningInsights.overall),
            AIEvaluationRegressionDelta(metric: "json_validity", baseline: baseline.localScores.knowledgeSnapshot.overall, comparison: comparison.localScores.knowledgeSnapshot.overall, delta: comparison.localScores.knowledgeSnapshot.overall - baseline.localScores.knowledgeSnapshot.overall)
        ]

        let latencyDelta = comparison.performanceMetrics.generationTime - baseline.performanceMetrics.generationTime
        let memoryDelta = comparison.performanceMetrics.memoryUsageMB - baseline.performanceMetrics.memoryUsageMB
        let hallucinationDelta = comparison.performanceMetrics.hallucinationCount - baseline.performanceMetrics.hallucinationCount
        let jsonFailures = [baseline, comparison].filter { $0.localScores.knowledgeSnapshot.parsingSuccess < 1 || $0.localScores.knowledgeSnapshot.schemaValidation < 1 }.count
        let alerts = scoreDeltas.filter { $0.delta < -0.05 }.map { "\($0.metric) regressed by \(formatDelta($0.delta))" }

        return AIEvaluationRegressionReport(
            generatedAt: Date(),
            title: "\(baseline.modelName) vs \(comparison.modelName)",
            baselineModel: baseline.modelName,
            comparisonModel: comparison.modelName,
            baselinePromptVersion: baseline.promptVersion,
            comparisonPromptVersion: comparison.promptVersion,
            scoreDeltas: scoreDeltas,
            latencyDelta: latencyDelta,
            memoryDeltaMB: memoryDelta,
            jsonFailures: jsonFailures,
            hallucinationCountDelta: hallucinationDelta,
            alerts: alerts
        )
    }

    func benchmarkReport(from runs: [AIEvaluationRunManifest], datasetName: String) -> AIEvaluationBenchmarkReport {
        let summary = runs.map { manifest -> AIEvaluationBenchmarkRanking in
            let noteCount = max(1, manifest.resultCount)
            let averageOverall = manifest.averageOverallScore
            let averageSummary = manifest.noteResults.map { $0.localScores.summary.overall }.reduce(0, +) / Double(noteCount)
            let averageFlashcards = manifest.noteResults.map { $0.localScores.flashcards.overall }.reduce(0, +) / Double(noteCount)
            let averageQuiz = manifest.noteResults.map { $0.localScores.quiz.overall }.reduce(0, +) / Double(noteCount)
            let averageConceptMap = manifest.noteResults.map { $0.localScores.conceptMap.overall }.reduce(0, +) / Double(noteCount)
            let averageInsights = manifest.noteResults.map { $0.localScores.learningInsights.overall }.reduce(0, +) / Double(noteCount)
            let speed = manifest.averageTokensPerSecond
            let memory = manifest.averageMemoryUsageMB
            let jsonValidity = manifest.noteResults.map { $0.localScores.knowledgeSnapshot.overall }.reduce(0, +) / Double(noteCount)

            return AIEvaluationBenchmarkRanking(
                rank: 0,
                modelName: manifest.modelName,
                promptVersion: manifest.promptVersion,
                overallQuality: averageOverall,
                summaryQuality: averageSummary,
                flashcardQuality: averageFlashcards,
                quizQuality: averageQuiz,
                conceptMapQuality: averageConceptMap,
                learningInsightsQuality: averageInsights,
                speed: speed,
                memory: memory,
                jsonValidity: jsonValidity
            )
        }

        let ranked = summary.sorted {
            if $0.overallQuality == $1.overallQuality {
                return $0.speed > $1.speed
            }
            return $0.overallQuality > $1.overallQuality
        }
        .enumerated()
        .map { index, item in
            var copy = item
            copy.rank = index + 1
            return copy
        }

        return AIEvaluationBenchmarkReport(
            generatedAt: Date(),
            datasetName: datasetName,
            noteCount: runs.reduce(0) { $0 + $1.resultCount },
            rankings: ranked,
            notes: [
                "Higher overall quality ranks above speed unless scores are tied.",
                "JSON validity and memory are reported alongside model quality."
            ]
        )
    }

    func promptImprovementReport(from noteResults: [AIEvaluationNoteResult], datasetName: String) -> AIEvaluationPromptImprovementReport {
        var recommendations: [AIEvaluationPromptImprovementRecommendation] = []

        let repeatedIssues = [
            ("summary", noteResults.filter { $0.localScores.summary.repetition < 0.75 }.count, "Summaries repeat phrases or re-state the note without compression."),
            ("flashcards", noteResults.filter { $0.localScores.flashcards.conceptCoverage < 0.75 }.count, "Flashcards miss core concepts."),
            ("quiz", noteResults.filter { $0.localScores.quiz.explanationPresence < 0.75 }.count, "Quizzes do not explain why answers are correct."),
            ("concept_map", noteResults.filter { $0.localScores.conceptMap.missingRelationships > 0.25 }.count, "Concept maps omit important links."),
            ("learning_insights", noteResults.filter { $0.localScores.learningInsights.actionability < 0.5 }.count, "Learning insights are not actionable enough.")
        ]

        for (prompt, count, problem) in repeatedIssues where count > 0 {
            recommendations.append(
                AIEvaluationPromptImprovementRecommendation(
                    affectedPrompt: prompt,
                    problem: problem,
                    evidence: "\(count) evaluated notes showed this weakness.",
                    recommendedImprovement: "Tighten the prompt constraints and ask for more specific, evidence-backed outputs.",
                    expectedBenefit: "Reduced repetition and better task coverage."
                )
            )
        }

        return AIEvaluationPromptImprovementReport(
            generatedAt: Date(),
            datasetName: datasetName,
            recommendations: recommendations
        )
    }

    private func explanation(for scores: AIEvaluationLocalScores) -> String {
        var parts: [String] = []
        parts.append("Summary score \(formatDecimal(scores.summary.overall)).")
        parts.append("Flashcards score \(formatDecimal(scores.flashcards.overall)).")
        parts.append("Quiz score \(formatDecimal(scores.quiz.overall)).")
        parts.append("Concept map score \(formatDecimal(scores.conceptMap.overall)).")
        parts.append("Learning insights score \(formatDecimal(scores.learningInsights.overall)).")
        parts.append("JSON validity score \(formatDecimal(scores.knowledgeSnapshot.overall)).")
        return parts.joined(separator: " ")
    }

    private func performanceSignals(from metrics: AIEvaluationPerformanceMetrics) -> [String] {
        var signals: [String] = []
        if metrics.generationTime > 0 {
            signals.append(metrics.generationTime > 2 ? "slow_generation" : "fast_generation")
        }
        if metrics.memoryUsageMB > 0 {
            signals.append(metrics.memoryUsageMB > 1500 ? "high_memory_usage" : "moderate_memory_usage")
        }
        if metrics.hallucinationCount > 0 {
            signals.append("hallucinations_detected")
        }
        return signals
    }

    private func formatDecimal(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func formatDelta(_ value: Double) -> String {
        String(format: "%.3f", abs(value))
    }
}

struct AIGoldStandardEvaluator: AIEvaluationGoldStandardEvaluator {
    let identifier = "gold-standard-evaluator"

    func evaluate(
        note: AIEvaluationNote,
        outputs: AIEvaluationOutputs,
        reference: AIEvaluationGoldStandardReference?
    ) async -> AIEvaluationSemanticEvaluationResult? {
        guard let reference else { return nil }

        let summaryScore = overlapScore(outputs.summary, reference.summary ?? "")
        let flashcardScore = overlapScore(outputs.flashcards.map(\.front).joined(separator: " "), reference.flashcards?.map(\.front).joined(separator: " ") ?? "")
        let quizScore = overlapScore(outputs.quiz.map(\.prompt).joined(separator: " "), reference.quiz?.map(\.prompt).joined(separator: " ") ?? "")
        let conceptScore = overlapScore(outputs.conceptMap.map(\.title).joined(separator: " "), reference.conceptMap?.map(\.title).joined(separator: " ") ?? "")
        let insightScore = overlapScore(outputs.learningInsights.keyConcepts.joined(separator: " "), reference.learningInsights?.keyConcepts.joined(separator: " ") ?? "")
        let semanticScores = AIEvaluationSemanticScores(
            accuracy: summaryScore,
            completeness: conceptScore,
            educationalUsefulness: max(summaryScore, insightScore),
            clarity: summaryScore,
            hallucinations: 1.0 - min(1.0, overlapScore(outputs.rawOutputs.summary, reference.summary ?? "")),
            organization: conceptScore,
            quizQuality: quizScore,
            flashcardQuality: flashcardScore,
            overall: average([summaryScore, flashcardScore, quizScore, conceptScore, insightScore])
        )

        return AIEvaluationSemanticEvaluationResult(
            evaluatorID: identifier,
            referenceID: reference.noteID,
            heuristicScores: AIEvaluationLocalScores(),
            semanticScores: semanticScores,
            heuristicScore: semanticScores.overall,
            semanticScore: semanticScores.overall,
            overallScore: semanticScores.overall,
            explanations: [
                "Gold-standard alignment was estimated from text overlap with the reference material.",
                "This evaluator is intentionally conservative and does not invent missing reference content."
            ],
            hallucinationCount: 0,
            latencySeconds: 0
        )
    }

    private func overlapScore(_ lhs: String, _ rhs: String) -> Double {
        let lhsTerms = Set(lhs.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let rhsTerms = Set(rhs.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        guard !lhsTerms.isEmpty, !rhsTerms.isEmpty else { return 0 }
        let overlap = lhsTerms.intersection(rhsTerms)
        return Double(overlap.count) / Double(max(lhsTerms.count, rhsTerms.count))
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct AINullCloudEvaluator: AIEvaluationCloudEvaluator {
    let identifier = "cloud-evaluator-placeholder"
    func evaluate(note: AIEvaluationNote, outputs: AIEvaluationOutputs, reference: AIEvaluationGoldStandardReference?) async -> AIEvaluationSemanticEvaluationResult? {
        nil
    }
}

struct AINullEmbeddingEvaluator: AIEvaluationEmbeddingEvaluator {
    let identifier = "embedding-evaluator-placeholder"
    func evaluate(note: AIEvaluationNote, outputs: AIEvaluationOutputs, reference: AIEvaluationGoldStandardReference?) async -> AIEvaluationSemanticEvaluationResult? {
        nil
    }
}
