import Foundation

final class AdaptivePromptBuilder {
    func buildPrompt(from context: AdaptiveTutorContext) -> String {
        [
            "Student Knowledge State",
            masterySection(title: "KNOWN WELL", concepts: context.strongConcepts),
            masterySection(title: "WEAK", concepts: context.weakConcepts + context.knowledgeGaps),
            masterySection(title: "MISSING PREREQUISITES", concepts: context.missingPrerequisites),
            graphSection(from: context),
            notesSection(from: context),
            studyPlanSection(from: context),
            "User Question\n\(context.question)",
            instructionSection
        ]
        .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        .joined(separator: "\n\n")
    }

    private func masterySection(title: String, concepts: [Concept]) -> String {
        let names = dedupeConcepts(concepts).prefix(12).map { "- \($0.name)" }
        return ([title] + (names.isEmpty ? ["- None available"] : Array(names))).joined(separator: "\n")
    }

    private func graphSection(from context: AdaptiveTutorContext) -> String {
        let graphText = context.graphContext.graphPromptRepresentation()
        if graphText.isEmpty == false {
            return "GRAPH CONTEXT\n\(graphText)"
        }

        let nameByID = Dictionary(uniqueKeysWithValues: context.relatedConcepts.map { ($0.id, $0.name) })
        let relationshipLines = context.relationships.prefix(24).compactMap { relationship -> String? in
            guard let source = nameByID[relationship.sourceConceptID],
                  let target = nameByID[relationship.destinationConceptID] else { return nil }
            return "\(source)\n  \(relationship.type.rawValue.uppercased()) -> \(target)"
        }
        return (["GRAPH CONTEXT"] + (relationshipLines.isEmpty ? ["No graph relationships available."] : relationshipLines)).joined(separator: "\n")
    }

    private func notesSection(from context: AdaptiveTutorContext) -> String {
        let chunks = context.retrievedNotes.prefix(8).map { chunk in
            "- \(chunk.noteTitle): \(chunk.snippet.isEmpty ? String(chunk.content.prefix(240)) : chunk.snippet)"
        }
        return (["Retrieved Note Context"] + (chunks.isEmpty ? ["- No retrieved note context available."] : Array(chunks))).joined(separator: "\n")
    }

    private func studyPlanSection(from context: AdaptiveTutorContext) -> String {
        guard context.studyPlanRecommendations.isEmpty == false else { return "" }
        return (["Study Plan Recommendations"] + context.studyPlanRecommendations.prefix(6).map { "- \($0)" }).joined(separator: "\n")
    }

    private var instructionSection: String {
        """
        Instruction
        Adapt the explanation to the student's current knowledge.
        Avoid re-teaching concepts already mastered.
        Explain weak prerequisite concepts when necessary.
        Build on concepts the student already understands.
        Prefer graph relationships over isolated note text when they conflict.
        """
    }

    private func dedupeConcepts(_ concepts: [Concept]) -> [Concept] {
        var seen: Set<UUID> = []
        return concepts.filter { seen.insert($0.id).inserted }
    }
}
