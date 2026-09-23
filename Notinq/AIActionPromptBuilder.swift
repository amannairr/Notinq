import Foundation

struct AIActionPromptBuilder {
    func prompt(action: AIEditorAction, selectedText: String, noteContext: String) -> String {
        prompt(action: action, selectedText: selectedText, noteContext: noteContext, adaptiveContext: nil)
    }

    func prompt(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String,
        adaptiveContext: AdaptiveExplanationContext?
    ) -> String {
        if action == .dontUnderstand {
            return dontUnderstandPrompt(
                selectedText: selectedText,
                noteContext: noteContext,
                adaptiveContext: adaptiveContext
            )
        }

        return [
            instruction(for: action),
            "Preserve meaning and important terminology from the selected text.",
            "Use surrounding note context only to improve terminology, coherence, and level; do not let unrelated context override the selected idea.",
            "Do not invent facts not supported by the selected text or surrounding note context.",
            "Return clean Markdown suitable for rich text rendering.",
            "Selected text:",
            selectedText,
            "Surrounding note context:",
            String(noteContext.prefix(1_500))
        ].joined(separator: "\n\n")
    }

    private func dontUnderstandPrompt(
        selectedText: String,
        noteContext: String,
        adaptiveContext: AdaptiveExplanationContext?
    ) -> String {
        let context = adaptiveContext ?? .unavailable()
        return [
            "STUDENT CONTEXT",
            studentContextSection(context),
            "LEARNING HISTORY",
            learningHistorySection(context),
            "KNOWLEDGE GAPS",
            knowledgeGapsSection(context),
            "MASTERY STATE",
            masteryStateSection(context),
            "SELECTED CONTENT",
            selectedText,
            "SOURCE MATERIAL",
            sourceMaterialSection(context, fallbackNoteContext: noteContext),
            "TASK",
            "Explain the selected content at the appropriate level. Explain any missing prerequisite before depending on it. Keep the explanation concise enough to insert into study notes.",
            "GROUNDING RULES",
            groundingRulesSection,
            "BEHAVIOR RULES",
            learningBehaviorRulesSection
        ].joined(separator: "\n\n")
    }

    private func studentContextSection(_ context: AdaptiveExplanationContext) -> String {
        [
            "Learner level: \(context.inferredLearnerLevel)",
            "Weak concepts: \(context.weakConcepts.isEmpty ? "None available" : context.weakConcepts.joined(separator: ", "))",
            "Strong concepts: \(context.strongConcepts.isEmpty ? "None available" : context.strongConcepts.joined(separator: ", "))",
            "Missing prerequisites: \(context.missingPrerequisites.isEmpty ? "None available" : context.missingPrerequisites.joined(separator: ", "))",
            "Confidence: \(confidenceLabel(context.confidence))"
        ].joined(separator: "\n")
    }

    private func sourceMaterialSection(_ context: AdaptiveExplanationContext, fallbackNoteContext: String) -> String {
        let groundedSources = context.retrievedNoteSources.filter { !$0.groundingText.isEmpty }
        if groundedSources.isEmpty {
            let fallback = fallbackNoteContext.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fallback.isEmpty else {
                return "Source grounding unavailable."
            }
            return [
                "Source grounding unavailable.",
                "Surrounding note context only:",
                String(fallback.prefix(1_200))
            ].joined(separator: "\n")
        }

        return groundedSources.prefix(4).map { source in
            let title = source.sectionTitle.map { "\(source.noteTitle) — \($0)" } ?? source.noteTitle
            return [
                "Source: \(title)",
                "Source ID: \(source.sourceID)",
                "Source type: \(source.sourceType)",
                "Relevant excerpt:",
                String(source.groundingText.prefix(700))
            ].joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func learningHistorySection(_ context: AdaptiveExplanationContext) -> String {
        guard !context.historicallyHelpfulConcepts.isEmpty || !context.historicallyConfusingConcepts.isEmpty else {
            return "Learning history unavailable."
        }

        return [
            "Historically Helpful Concepts: \(context.historicallyHelpfulConcepts.isEmpty ? "None available" : context.historicallyHelpfulConcepts.joined(separator: ", "))",
            "Historically Confusing Concepts: \(context.historicallyConfusingConcepts.isEmpty ? "None available" : context.historicallyConfusingConcepts.joined(separator: ", "))",
            "Prior helpful explanations: \(context.priorHelpfulExplanationsCount)",
            "Prior confusing explanations: \(context.priorConfusingExplanationsCount)"
        ].joined(separator: "\n")
    }

    private func knowledgeGapsSection(_ context: AdaptiveExplanationContext) -> String {
        guard !context.identifiedKnowledgeGaps.isEmpty else {
            return "Likely missing concepts:\n- Knowledge gaps unavailable"
        }
        return (["Likely missing concepts:"] + context.identifiedKnowledgeGaps.map { "- \($0)" }).joined(separator: "\n")
    }

    private func masteryStateSection(_ context: AdaptiveExplanationContext) -> String {
        guard !context.masteryStates.isEmpty else {
            return "Mastery unavailable."
        }

        return context.masteryStates
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { concept, state in
                [
                    "Concept: \(concept)",
                    "State: \(state.displayTitle)"
                ].joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }

    private var groundingRulesSection: String {
        [
            "- Prefer supplied source material.",
            "- Preserve the meaning of the student's notes.",
            "- Do not invent facts and attribute them to the notes.",
            "- Do not cite sources that were not supplied.",
            "- If the supplied material is insufficient, say so rather than fabricating support.",
            "- Explain the missing prerequisite before depending on it.",
            "- Keep the explanation useful for studying.",
            "- Return clean Markdown suitable for rich text rendering."
        ].joined(separator: "\n")
    }

    private var learningBehaviorRulesSection: String {
        [
            "- If a concept appears historically confusing, explain its prerequisite first, reduce complexity, use more examples, and avoid skipping steps.",
            "- If a concept appears historically helpful, allow a slightly more advanced explanation and avoid repeating overly basic definitions.",
            "- If mastery state is struggling, use a simpler explanation and more examples.",
            "- If mastery state is needsPractice, reinforce prerequisites before advancing.",
            "- If mastery state is familiar, keep the explanation concise.",
            "- If mastery state is mastered, provide only a brief refresh.",
            "- Explicitly address identified knowledge gaps before explaining the target concept.",
            "- Build the explanation from prerequisite upward and explain why each prerequisite matters.",
            "- Avoid assuming mastery of identified gaps.",
            "- Do not claim the learning history proves mastery; use it only to adjust explanation style."
        ].joined(separator: "\n")
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        switch confidence {
        case ..<0.34:
            return "Low (\(Int((confidence * 100).rounded()))%)"
        case ..<0.67:
            return "Medium (\(Int((confidence * 100).rounded()))%)"
        default:
            return "High (\(Int((confidence * 100).rounded()))%)"
        }
    }

    private func instruction(for action: AIEditorAction) -> String {
        switch action {
        case .expand:
            return "Expand the selected idea into clearer educational prose. Add useful explanation without unnecessary verbosity."
        case .explain:
            return "Explain the selected content clearly. Include what the concept means and why it matters in concise educational language."
        case .simplify:
            return "Simplify the selected content. Use easier wording and lower the reading difficulty while preserving meaning."
        case .example:
            return "Generate one concrete educational example tied directly to the selected concept."
        case .analogy:
            return "Generate one intuitive educational analogy for the selected concept. Avoid misleading comparisons and clarify the useful limits of the analogy when needed."
        case .dontUnderstand:
            return "The student is confused by the selected content. First infer the student's current level from weak concepts, strong concepts, missing prerequisites, mastery, and retrieved note context. Use that level check to calibrate the response, then explain the selected content at that level, filling only the prerequisites needed to understand it."
        }
    }
}
