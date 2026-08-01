import Foundation

struct KnowledgeMetadata: Codable, Equatable, Sendable {
    var noteID: String = ""
    var title: String = ""
    var subject: String = ""
    var sourceType: String = "note"
    var approximateTokenCount: Int = 0
    var sectionCount: Int = 0
    var extractedAt: Date = Date()
    var modelName: String = ""
    var promptVersion: String = ""
    var appVersion: String = ""
    var gitCommit: String = ""
    var sourceSignature: String = ""
}

enum KnowledgeSectionKind: String, Codable, CaseIterable, Sendable {
    case heading
    case paragraph
    case list
    case numberedSection
    case codeBlock
    case equation
    case table
    case custom
}

struct KnowledgeSourceLocation: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var sectionID: String = ""
    var sectionTitle: String = ""
    var lineStart: Int = 0
    var lineEnd: Int = 0
    var order: Int = 0
    var snippet: String = ""
}

struct KnowledgeSection: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var title: String = ""
    var kind: KnowledgeSectionKind = .custom
    var order: Int = 0
    var content: String = ""
    var children: [KnowledgeSection] = []
    var sourceLocations: [KnowledgeSourceLocation] = []
}

struct KnowledgeConcept: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var name: String = ""
    var definition: String = ""
    var aliases: [String] = []
    var category: String = "concept"
    var section: String = ""
    var source: String = ""
    var definitionEvidence: [String] = []
    var aliasEvidence: [String] = []
    var sourceExcerpt: String = ""
    var importance: Double = 0.5
    var difficulty: Double = 0.5
    var relationships: [String] = []
    var examples: [String] = []
    var learningObjective: String = ""
    var confidence: Double = 0.5
    var sourceLocations: [KnowledgeSourceLocation] = []
}

struct KnowledgeDefinition: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var term: String = ""
    var definition: String = ""
    var aliases: [String] = []
    var sourceLocations: [KnowledgeSourceLocation] = []
    var confidence: Double = 0.5
}

struct KnowledgeExample: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var conceptID: String = ""
    var example: String = ""
    var sourceLocations: [KnowledgeSourceLocation] = []
    var confidence: Double = 0.5
}

struct KnowledgeProcess: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var title: String = ""
    var steps: [String] = []
    var sourceLocations: [KnowledgeSourceLocation] = []
    var confidence: Double = 0.5
}

struct KnowledgeObjective: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var objective: String = ""
    var relatedConceptIDs: [String] = []
    var sourceLocations: [KnowledgeSourceLocation] = []
    var confidence: Double = 0.5
}

enum KnowledgeRelationshipKind: String, Codable, CaseIterable, Sendable {
    case requires = "REQUIRES"
    case causes = "CAUSES"
    case partOf = "PART_OF"
    case contains = "CONTAINS"
    case relatedTo = "RELATED_TO"
    case exampleOf = "EXAMPLE_OF"
    case comparesTo = "COMPARES_TO"
    case uses = "USES"
    case produces = "PRODUCES"
}

struct KnowledgeRelationship: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var sourceID: String = ""
    var targetID: String = ""
    var relationKind: KnowledgeRelationshipKind = .relatedTo
    var relation: String = KnowledgeRelationshipKind.relatedTo.rawValue
    var sourceLocations: [KnowledgeSourceLocation] = []
    var confidence: Double = 0.5
}

struct KnowledgeActionItem: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var title: String = ""
    var details: String = ""
    var priority: String = "medium"
    var sourceLocations: [KnowledgeSourceLocation] = []
    var confidence: Double = 0.5
}

struct StructuredKnowledge: Codable, Equatable, Sendable {
    var metadata: KnowledgeMetadata = KnowledgeMetadata()
    var title: String = ""
    var topics: [String] = []
    var sections: [KnowledgeSection] = []
    var concepts: [KnowledgeConcept] = []
    var definitions: [KnowledgeDefinition] = []
    var examples: [KnowledgeExample] = []
    var processes: [KnowledgeProcess] = []
    var relationships: [KnowledgeRelationship] = []
    var learningObjectives: [KnowledgeObjective] = []
    var actionItems: [KnowledgeActionItem] = []
    var keywords: [String] = []
    var confidence: Double = 0.5
    var sourceLocations: [KnowledgeSourceLocation] = []
    var difficulty: StudyKnowledgeDifficulty = .intermediate
    var importance: Double = 0.5
    var aliases: [String] = []
    var procedures: [String] = []
    var formulas: [String] = []
    var importantFacts: [String] = []
    var keyTerminology: [String] = []
    var misconceptions: [String] = []
    var prerequisites: [String] = []
    var hierarchy: [KnowledgeSection] = []
    var supportingEvidence: [String] = []
    var summaryHighlights: [String] = []
    var examFocus: [String] = []

    var hasContent: Bool {
        !title.isEmpty
            || !topics.isEmpty
            || !sections.isEmpty
            || !concepts.isEmpty
            || !definitions.isEmpty
            || !examples.isEmpty
            || !processes.isEmpty
            || !relationships.isEmpty
            || !learningObjectives.isEmpty
            || !actionItems.isEmpty
            || !keywords.isEmpty
            || !supportingEvidence.isEmpty
            || !summaryHighlights.isEmpty
            || !examFocus.isEmpty
    }
}

struct KnowledgeExtractionQualityMetrics: Codable, Equatable, Sendable {
    var conceptCount: Int = 0
    var definitionCount: Int = 0
    var exampleCount: Int = 0
    var processCount: Int = 0
    var relationshipCount: Int = 0
    var learningObjectiveCount: Int = 0
    var actionItemCount: Int = 0
    var aliasCount: Int = 0
    var keywordCount: Int = 0
    var sourceLocationCount: Int = 0
    var duplicateConceptCount: Int = 0
    var duplicateDefinitionCount: Int = 0
    var duplicateAliasCount: Int = 0
    var duplicateRelationshipCount: Int = 0
    var invalidReferenceCount: Int = 0
    var emptyDefinitionCount: Int = 0
    var averageConceptConfidence: Double = 0
    var minimumConceptConfidence: Double = 0
    var maximumConceptConfidence: Double = 0
    var confidenceCoverage: Double = 0
    var sectionCoverage: Double = 0
    var noiseTokenCount: Int = 0
    var canonicalRelationshipCounts: [String: Int] = [:]
}

struct KnowledgeExtractionDebugReport: Codable, Equatable, Sendable {
    var title: String = ""
    var sourceSignature: String = ""
    var strategy: KnowledgeProcessingStrategy = .singlePass
    var fromCache: Bool = false
    var validation: KnowledgeValidationReport?
    var metrics: KnowledgeExtractionQualityMetrics = KnowledgeExtractionQualityMetrics()
    var topConcepts: [KnowledgeConcept] = []
    var topRelationships: [KnowledgeRelationship] = []
    var sampleDefinitions: [KnowledgeDefinition] = []
    var sampleExamples: [KnowledgeExample] = []
    var sampleObjectives: [KnowledgeObjective] = []
    var sampleActionItems: [KnowledgeActionItem] = []
    var headingTrail: [String] = []
    var discardedNoise: [String] = []
    var chunkRuns: [KnowledgeExtractionChunkDebug] = []
    var mergedKnowledge: StructuredKnowledge = StructuredKnowledge()
    var validationWarnings: [String] = []
    var latency: TimeInterval = 0
    var retryCount: Int = 0
    var tokenCount: Int = 0
}

struct KnowledgeExtractionChunkDebug: Codable, Equatable, Sendable {
    var documentID: String = ""
    var chunkIndex: Int = 0
    var sectionName: String = ""
    var paragraphIDs: [String] = []
    var rawChunk: String = ""
    var prompt: String = ""
    var rawModelResponse: String = ""
    var parsedJSON: String = ""
    var mergedKnowledge: StructuredKnowledge = StructuredKnowledge()
    var validationWarnings: [String] = []
    var latency: TimeInterval = 0
    var retryCount: Int = 0
    var tokenCount: Int = 0
}

extension KnowledgeExtractionDebugReport {
    func updating(
        chunkRuns: [KnowledgeExtractionChunkDebug]? = nil,
        mergedKnowledge: StructuredKnowledge? = nil,
        validationWarnings: [String]? = nil,
        latency: TimeInterval? = nil,
        retryCount: Int? = nil,
        tokenCount: Int? = nil
    ) -> KnowledgeExtractionDebugReport {
        var copy = self
        if let chunkRuns { copy.chunkRuns = chunkRuns }
        if let mergedKnowledge { copy.mergedKnowledge = mergedKnowledge }
        if let validationWarnings { copy.validationWarnings = validationWarnings }
        if let latency { copy.latency = latency }
        if let retryCount { copy.retryCount = retryCount }
        if let tokenCount { copy.tokenCount = tokenCount }
        return copy
    }
}

typealias ExtractedKnowledgeConcept = KnowledgeConcept
typealias ExtractedKnowledgeNode = KnowledgeSection
typealias ExtractedKnowledgePayload = StructuredKnowledge

extension StructuredKnowledge {
    func legacySnapshotRepresentation() -> StudyKnowledgeSnapshot {
        func item(
            title: String,
            summary: String,
            evidence: [String],
            importance: Double,
            difficulty: Double,
            aliases: [String],
            relatedTitles: [String],
            category: String
        ) -> StudyKnowledgeItem {
            StudyKnowledgeItem(
                title: title,
                summary: summary,
                evidence: evidence,
                importance: importance,
                difficulty: difficulty,
                aliases: aliases,
                relatedTitles: relatedTitles,
                category: category
            )
        }

        let conceptItems = concepts.map { concept in
            item(
                title: concept.name,
                summary: concept.definition.isEmpty ? concept.name : concept.definition,
                evidence: concept.examples.isEmpty ? concept.sourceLocations.map { $0.snippet }.filter { !$0.isEmpty } : concept.examples,
                importance: concept.importance,
                difficulty: concept.difficulty,
                aliases: concept.aliases,
                relatedTitles: concept.relationships,
                category: concept.category
            )
        }

        let definitionItems = definitions.map { definition in
            item(
                title: definition.term,
                summary: definition.definition,
                evidence: definition.sourceLocations.map { $0.snippet }.filter { !$0.isEmpty },
                importance: 0.7,
                difficulty: 0.5,
                aliases: definition.aliases,
                relatedTitles: [],
                category: "definition"
            )
        }

        let exampleItems = examples.map { example in
            item(
                title: example.conceptID.isEmpty ? "Example" : example.conceptID,
                summary: example.example,
                evidence: example.sourceLocations.map { $0.snippet }.filter { !$0.isEmpty },
                importance: 0.55,
                difficulty: 0.4,
                aliases: [],
                relatedTitles: [],
                category: "example"
            )
        }

        let relationshipItems = relationships.map { relationship in
            StudyKnowledgeRelationship(
                sourceTitle: relationship.sourceID,
                targetTitle: relationship.targetID,
                relation: relationship.relation,
                confidence: relationship.confidence
            )
        }

        return StudyKnowledgeSnapshot(
            title: title,
            sourceSignature: metadata.sourceSignature,
            cleanedText: supportingEvidence.joined(separator: "\n"),
            normalizedText: supportingEvidence.joined(separator: "\n"),
            topics: topics,
            concepts: conceptItems,
            definitions: definitionItems,
            relationships: relationshipItems,
            examples: exampleItems,
            procedures: procedures.map { item(title: $0, summary: $0, evidence: [$0], importance: 0.5, difficulty: 0.5, aliases: [], relatedTitles: [], category: "procedure") },
            formulas: formulas.map { item(title: $0, summary: $0, evidence: [$0], importance: 0.6, difficulty: 0.6, aliases: [], relatedTitles: [], category: "formula") },
            importantFacts: importantFacts.map { item(title: $0, summary: $0, evidence: [$0], importance: 0.65, difficulty: 0.45, aliases: [], relatedTitles: [], category: "important_fact") },
            keyTerms: keyTerminology.map { item(title: $0, summary: $0, evidence: [$0], importance: 0.6, difficulty: 0.4, aliases: [], relatedTitles: [], category: "key_term") },
            misconceptions: misconceptions.map { item(title: $0, summary: $0, evidence: [$0], importance: 0.45, difficulty: 0.5, aliases: [], relatedTitles: [], category: "misconception") },
            prerequisites: prerequisites.map { item(title: $0, summary: $0, evidence: [$0], importance: 0.5, difficulty: 0.45, aliases: [], relatedTitles: [], category: "prerequisite") },
            hierarchy: hierarchy.map { section in
                StudyKnowledgeNode(title: section.title, summary: section.content, children: section.children.map { child in
                    StudyKnowledgeNode(title: child.title, summary: child.content, children: [])
                })
            },
            difficulty: difficulty,
            supportingExamples: exampleItems.prefix(4).map { $0 },
            supportingEvidence: supportingEvidence,
            summaryHighlights: summaryHighlights,
            examFocus: examFocus,
            tokenEstimate: metadata.approximateTokenCount,
            extractionStrategy: metadata.sourceType
        )
    }
}

extension StudyKnowledgeSnapshot {
    func structuredKnowledgeRepresentation() -> StructuredKnowledge {
        let section = KnowledgeSection(
            title: title,
            kind: .custom,
            order: 0,
            content: cleanedText,
            children: [],
            sourceLocations: []
        )

        let conceptItems = concepts.map { item in
            KnowledgeConcept(
                name: item.title,
                definition: item.summary,
                aliases: item.aliases,
                category: item.category.isEmpty ? "concept" : item.category,
                section: item.category,
                source: sourceSignature,
                importance: item.importance,
                difficulty: item.difficulty,
                relationships: item.relatedTitles,
                examples: item.evidence,
                learningObjective: item.summary,
                confidence: min(1.0, max(0.0, item.importance)),
                sourceLocations: item.evidence.enumerated().map { index, evidence in
                    KnowledgeSourceLocation(
                        sectionID: "concept_\(index)",
                        sectionTitle: item.title,
                        lineStart: index + 1,
                        lineEnd: index + 1,
                        order: index,
                        snippet: evidence
                    )
                }
            )
        }
        let conceptIDByTitle = Dictionary(uniqueKeysWithValues: zip(concepts.map(\.title), conceptItems.map(\.id)))
        let titleByConceptID = Dictionary(uniqueKeysWithValues: zip(conceptItems.map(\.id), conceptItems.map(\.name)))

        let definitionItems = definitions.map { item in
            KnowledgeDefinition(
                term: item.title,
                definition: item.summary,
                aliases: item.aliases,
                sourceLocations: item.evidence.enumerated().map { index, evidence in
                    KnowledgeSourceLocation(
                        sectionID: "definition_\(index)",
                        sectionTitle: item.title,
                        lineStart: index + 1,
                        lineEnd: index + 1,
                        order: index,
                        snippet: evidence
                    )
                },
                confidence: min(1.0, max(0.0, item.importance))
            )
        }

        let exampleItems = examples.map { item in
            KnowledgeExample(
                conceptID: conceptIDByTitle[item.title] ?? item.title,
                example: item.summary,
                sourceLocations: item.evidence.enumerated().map { index, evidence in
                    KnowledgeSourceLocation(
                        sectionID: "example_\(index)",
                        sectionTitle: item.title,
                        lineStart: index + 1,
                        lineEnd: index + 1,
                        order: index,
                        snippet: evidence
                    )
                },
                confidence: min(1.0, max(0.0, item.importance))
            )
        }

        let processes = procedures.map { item in
            KnowledgeProcess(
                title: item.title,
                steps: item.summary.split(separator: " ").map(String.init),
                sourceLocations: item.evidence.enumerated().map { index, evidence in
                    KnowledgeSourceLocation(
                        sectionID: "process_\(index)",
                        sectionTitle: item.title,
                        lineStart: index + 1,
                        lineEnd: index + 1,
                        order: index,
                        snippet: evidence
                    )
                },
                confidence: min(1.0, max(0.0, item.importance))
            )
        }

        let relationshipItems = relationships.map { relationship in
            KnowledgeRelationship(
                sourceID: titleByConceptID[conceptIDByTitle[relationship.sourceTitle] ?? relationship.sourceTitle] ?? relationship.sourceTitle,
                targetID: titleByConceptID[conceptIDByTitle[relationship.targetTitle] ?? relationship.targetTitle] ?? relationship.targetTitle,
                relation: relationship.relation.uppercased().replacingOccurrences(of: " ", with: "_"),
                sourceLocations: [],
                confidence: relationship.confidence
            )
        }

        let objectives = keyTerms.map { item in
            KnowledgeObjective(
                objective: item.title,
                relatedConceptIDs: item.relatedTitles.compactMap { conceptIDByTitle[$0] ?? titleByConceptID[$0] },
                sourceLocations: [],
                confidence: min(1.0, max(0.0, item.importance))
            )
        }

        return StructuredKnowledge(
            metadata: KnowledgeMetadata(
                noteID: sourceSignature,
                title: title,
                subject: title,
                sourceType: extractionStrategy.isEmpty ? "note" : extractionStrategy,
                approximateTokenCount: tokenEstimate,
                sectionCount: hierarchy.count,
                extractedAt: Date(),
                modelName: "",
                promptVersion: "",
                appVersion: "",
                gitCommit: "",
                sourceSignature: sourceSignature
            ),
            title: title,
            topics: topics,
            sections: hierarchy.isEmpty ? [section] : hierarchy.map { node in
                KnowledgeSection(
                    title: node.title,
                    kind: .custom,
                    order: 0,
                    content: node.summary,
                    children: node.children.map { child in
                        KnowledgeSection(
                            title: child.title,
                            kind: .custom,
                            order: 0,
                            content: child.summary,
                            children: [],
                            sourceLocations: []
                        )
                    },
                    sourceLocations: []
                )
            },
            concepts: conceptItems,
            definitions: definitionItems,
            examples: exampleItems,
            processes: processes,
            relationships: relationshipItems,
            learningObjectives: objectives,
            actionItems: [],
            keywords: Array(Set(topics + keyTerms.map(\.title))).sorted(),
            confidence: 0.5,
            sourceLocations: [],
            difficulty: difficulty,
            importance: concepts.map(\.importance).max() ?? 0.5,
            aliases: [],
            procedures: procedures.map(\.summary),
            formulas: formulas.map(\.summary),
            importantFacts: importantFacts.map(\.summary),
            keyTerminology: keyTerms.map(\.title),
            misconceptions: misconceptions.map(\.summary),
            prerequisites: prerequisites.map(\.summary),
            hierarchy: hierarchy.map { node in
                KnowledgeSection(
                    title: node.title,
                    kind: .custom,
                    order: 0,
                    content: node.summary,
                    children: node.children.map { child in
                        KnowledgeSection(title: child.title, kind: .custom, order: 0, content: child.summary, children: [], sourceLocations: [])
                    },
                    sourceLocations: []
                )
            },
            supportingEvidence: supportingEvidence,
            summaryHighlights: summaryHighlights,
            examFocus: examFocus
        )
    }
}
