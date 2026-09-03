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

enum ExtractionRelationshipType: String, Codable, CaseIterable, Sendable {
    case prerequisiteOf = "PREREQUISITE_OF"
    case partOf = "PART_OF"
    case exampleOf = "EXAMPLE_OF"
    case causes = "CAUSES"
    case dependsOn = "DEPENDS_ON"
    case relatedTo = "RELATED_TO"

    static let allowedValues: Set<String> = Set(allCases.map(\.rawValue))

    static func normalized(from rawValue: String) -> ExtractionRelationshipType? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        switch normalized {
        case "prerequisite of", "prerequisite", "requires", "required by", "depends on", "depends upon", "depend on":
            return .dependsOn
        case "part of", "contains", "includes", "component of", "member of":
            return .partOf
        case "example of", "for example", "example", "instance of":
            return .exampleOf
        case "causes", "cause", "leads to", "results in", "triggers", "produces":
            return .causes
        case "related to", "related", "associated with", "linked to":
            return .relatedTo
        default:
            return ExtractionRelationshipType(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        }
    }

    func bridgedRelationshipKind() -> KnowledgeRelationshipKind {
        switch self {
        case .prerequisiteOf, .dependsOn:
            return .requires
        case .partOf:
            return .partOf
        case .exampleOf:
            return .exampleOf
        case .causes:
            return .causes
        case .relatedTo:
            return .relatedTo
        }
    }

    func bridgedGraphRelationshipType() -> ConceptRelationshipType {
        switch self {
        case .prerequisiteOf:
            return .prerequisite
        case .partOf:
            return .partOf
        case .exampleOf:
            return .exampleOf
        case .causes:
            return .causes
        case .dependsOn:
            return .dependsOn
        case .relatedTo:
            return .relatedTo
        }
    }
}

struct ExtractionSourceReference: Codable, Equatable, Sendable {
    var chunkID: String
    var documentID: String
    var chunkIndex: Int
    var startOffset: Int?
    var endOffset: Int?
}

struct ExtractionConcept: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var descriptionText: String?
    var importanceScore: Double
    var confidenceScore: Double
    var aliases: [String]
    var sourceChunkIDs: [String]

    init(
        id: String,
        name: String,
        descriptionText: String? = nil,
        importanceScore: Double = 0.5,
        confidenceScore: Double = 0.5,
        aliases: [String] = [],
        sourceChunkIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.descriptionText = descriptionText
        self.importanceScore = importanceScore
        self.confidenceScore = confidenceScore
        self.aliases = aliases
        self.sourceChunkIDs = sourceChunkIDs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case descriptionText = "description"
        case importanceScore = "importance_score"
        case confidenceScore = "confidence_score"
        case aliases
        case sourceChunkIDs = "source_chunk_ids"
    }
}

struct ExtractionRelationship: Codable, Equatable, Sendable {
    var sourceID: String
    var targetID: String
    var relationshipType: ExtractionRelationshipType
    var confidenceScore: Double
    var sourceChunkIDs: [String]

    init(
        sourceID: String,
        targetID: String,
        relationshipType: ExtractionRelationshipType,
        confidenceScore: Double = 0.5,
        sourceChunkIDs: [String] = []
    ) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.relationshipType = relationshipType
        self.confidenceScore = confidenceScore
        self.sourceChunkIDs = sourceChunkIDs
    }

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case targetID = "target_id"
        case relationshipType = "relationship_type"
        case confidenceScore = "confidence_score"
        case sourceChunkIDs = "source_chunk_ids"
    }
}

struct ExtractionFact: Codable, Equatable, Sendable {
    var id: String
    var statement: String
    var confidenceScore: Double
    var conceptIDs: [String]
    var sourceChunkIDs: [String]

    init(
        id: String,
        statement: String,
        confidenceScore: Double = 0.5,
        conceptIDs: [String] = [],
        sourceChunkIDs: [String] = []
    ) {
        self.id = id
        self.statement = statement
        self.confidenceScore = confidenceScore
        self.conceptIDs = conceptIDs
        self.sourceChunkIDs = sourceChunkIDs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case statement
        case confidenceScore = "confidence_score"
        case conceptIDs = "concept_ids"
        case sourceChunkIDs = "source_chunk_ids"
    }
}

struct CanonicalExtractionPayload: Codable, Equatable, Sendable {
    var concepts: [ExtractionConcept] = []
    var facts: [ExtractionFact] = []
    var relationships: [ExtractionRelationship] = []
    var sourceReferences: [ExtractionSourceReference] = []

    var isEmpty: Bool {
        concepts.isEmpty && facts.isEmpty && relationships.isEmpty && sourceReferences.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case concepts
        case facts
        case relationships
        case sourceReferences = "source_references"
    }
}

struct ConceptResolver {
    struct Resolution: Sendable {
        var concepts: [ExtractionConcept]
        var aliasToConceptID: [String: String]
        var normalizedNameToConceptID: [String: String]
    }

    func resolve(_ concepts: [ExtractionConcept]) -> Resolution {
        var canonicalConcepts: [ExtractionConcept] = []
        var aliasToConceptID: [String: String] = [:]
        var normalizedNameToConceptID: [String: String] = [:]

        for concept in concepts {
            let cleaned = sanitize(concept)
            guard !cleaned.name.isEmpty else { continue }

            let normalizedName = Self.normalizedKey(for: cleaned.name)
            let normalizedAliases = cleaned.aliases.map { Self.normalizedKey(for: $0) }
            let matchIndex = canonicalConcepts.firstIndex(where: { existing in
                let existingKey = Self.normalizedKey(for: existing.name)
                return existingKey == normalizedName
                    || existing.aliases.map { Self.normalizedKey(for: $0) }.contains(normalizedName)
                    || normalizedAliases.contains(existingKey)
                    || existing.aliases.contains(where: { alias in
                        normalizedAliases.contains(Self.normalizedKey(for: alias))
                    })
            })

            if let matchIndex {
                canonicalConcepts[matchIndex] = merge(canonicalConcepts[matchIndex], with: cleaned)
            } else {
                canonicalConcepts.append(cleaned)
            }
        }

        for concept in canonicalConcepts {
            let canonicalID = concept.id
            let normalizedName = Self.normalizedKey(for: concept.name)
            normalizedNameToConceptID[normalizedName] = canonicalID
            aliasToConceptID[normalizedName] = canonicalID
            for alias in concept.aliases {
                aliasToConceptID[Self.normalizedKey(for: alias)] = canonicalID
            }
        }

        return Resolution(
            concepts: canonicalConcepts,
            aliasToConceptID: aliasToConceptID,
            normalizedNameToConceptID: normalizedNameToConceptID
        )
    }

    private func sanitize(_ concept: ExtractionConcept) -> ExtractionConcept {
        var concept = concept
        concept.id = concept.id.trimmingCharacters(in: .whitespacesAndNewlines)
        concept.name = concept.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let description = concept.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            concept.descriptionText = description
        } else {
            concept.descriptionText = nil
        }
        concept.importanceScore = clamp(concept.importanceScore)
        concept.confidenceScore = clamp(concept.confidenceScore)
        concept.aliases = Self.dedupeStrings(concept.aliases)
        concept.sourceChunkIDs = Self.dedupeStrings(concept.sourceChunkIDs)
        if concept.id.isEmpty {
            concept.id = deterministicID(for: concept.name)
        }
        return concept
    }

    private func merge(_ lhs: ExtractionConcept, with rhs: ExtractionConcept) -> ExtractionConcept {
        var concept = lhs
        if concept.id.isEmpty { concept.id = rhs.id }
        if concept.name.isEmpty { concept.name = rhs.name }
        if concept.descriptionText == nil || concept.descriptionText?.isEmpty == true {
            concept.descriptionText = rhs.descriptionText
        } else if let rhsDescription = rhs.descriptionText, !rhsDescription.isEmpty, rhsDescription.count > (concept.descriptionText?.count ?? 0) {
            concept.descriptionText = rhsDescription
        }
        concept.importanceScore = max(concept.importanceScore, rhs.importanceScore)
        concept.confidenceScore = max(concept.confidenceScore, rhs.confidenceScore)
        concept.aliases = Self.dedupeStrings(concept.aliases + rhs.aliases + [rhs.name]).filter {
            Self.normalizedKey(for: $0) != Self.normalizedKey(for: concept.name)
        }
        concept.sourceChunkIDs = Self.dedupeStrings(concept.sourceChunkIDs + rhs.sourceChunkIDs)
        return concept
    }

    private func deterministicID(for name: String) -> String {
        let normalized = Self.normalizedKey(for: name)
        guard !normalized.isEmpty else { return UUID().uuidString }
        return normalized.replacingOccurrences(of: " ", with: "-")
    }

    private func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }

    private static func dedupeStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Self.normalizedKey(for: trimmed)
            guard !trimmed.isEmpty, !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return trimmed
        }
    }

    private static func normalizedKey(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension StructuredKnowledge {
    func canonicalExtractionPayload(sourceReferences: [ExtractionSourceReference] = []) -> CanonicalExtractionPayload {
        let canonicalSourceReferences = sourceReferences.isEmpty ? inferSourceReferences() : sourceReferences
        let canonicalSourceIDs = Set(canonicalSourceReferences.map(\.chunkID))

        let canonicalConcepts = concepts.map { concept in
            ExtractionConcept(
                id: concept.id,
                name: concept.name,
                descriptionText: concept.definition.isEmpty ? nil : concept.definition,
                importanceScore: concept.importance,
                confidenceScore: concept.confidence,
                aliases: concept.aliases,
                sourceChunkIDs: Self.dedupeStrings(concept.sourceLocations.map(\.sectionID).filter { canonicalSourceIDs.isEmpty || canonicalSourceIDs.contains($0) })
            )
        }

        let canonicalRelationships: [ExtractionRelationship] = relationships.compactMap { relationship in
            guard let type = ExtractionRelationshipType.normalized(from: relationship.relationKind.rawValue)
                ?? ExtractionRelationshipType.normalized(from: relationship.relation) else { return nil }
            return ExtractionRelationship(
                sourceID: relationship.sourceID,
                targetID: relationship.targetID,
                relationshipType: type,
                confidenceScore: relationship.confidence,
                sourceChunkIDs: Self.dedupeStrings(relationship.sourceLocations.map(\.sectionID).filter { canonicalSourceIDs.isEmpty || canonicalSourceIDs.contains($0) })
            )
        }

        let canonicalFacts = importantFacts.enumerated().map { index, fact in
            let matchedConceptIDs = concepts.compactMap { concept -> String? in
                let names = [concept.name] + concept.aliases
                return names.contains(where: { fact.lowercased().contains($0.lowercased()) }) ? concept.id : nil
            }
            let sourceIDs = matchedConceptIDs.flatMap { conceptID in
                concepts.first(where: { $0.id == conceptID })?.sourceLocations.map(\.sectionID) ?? []
            }
            let fallbackSourceIDs = sourceIDs.isEmpty ? sourceLocations.map(\.sectionID) : sourceIDs
            return ExtractionFact(
                id: "fact-\(index)-\(String(fact.lowercased().prefix(24)).replacingOccurrences(of: " ", with: "-"))",
                statement: fact,
                confidenceScore: confidence,
                conceptIDs: Self.dedupeStrings(matchedConceptIDs),
                sourceChunkIDs: Self.dedupeStrings(fallbackSourceIDs.filter { canonicalSourceIDs.isEmpty || canonicalSourceIDs.contains($0) })
            )
        }

        return CanonicalExtractionPayload(
            concepts: canonicalConcepts,
            facts: canonicalFacts,
            relationships: canonicalRelationships,
            sourceReferences: canonicalSourceReferences
        )
    }

    static func fromCanonicalExtraction(
        _ payload: CanonicalExtractionPayload,
        title: String,
        sourceSignature: String,
        sourceType: String = "note",
        subject: String = "",
        approximateTokenCount: Int = 0,
        sectionCount: Int = 0,
        difficulty: StudyKnowledgeDifficulty = .intermediate,
        keywords: [String] = [],
        summaryHighlights: [String] = [],
        examFocus: [String] = [],
        supportingEvidence: [String] = []
    ) -> StructuredKnowledge {
        let resolved = ConceptResolver().resolve(payload.concepts)
        let conceptsByID = Dictionary(uniqueKeysWithValues: resolved.concepts.map { ($0.id, $0) })
        let conceptsByNormalizedName = Dictionary(uniqueKeysWithValues: resolved.concepts.map { (Self.normalizedKey(for: $0.name), $0) })
        let sourceReferencesByID = Dictionary(uniqueKeysWithValues: payload.sourceReferences.map { ($0.chunkID, $0) })

        func sourceLocations(for chunkIDs: [String], title: String, snippet: String = "") -> [KnowledgeSourceLocation] {
            Self.dedupeStrings(chunkIDs).enumerated().map { index, chunkID in
                let reference = sourceReferencesByID[chunkID]
                return KnowledgeSourceLocation(
                    id: "src-\(chunkID)-\(index)",
                    sectionID: chunkID,
                    sectionTitle: reference?.documentID.isEmpty == false ? reference?.documentID ?? title : title,
                    lineStart: reference.map { $0.chunkIndex + 1 } ?? (index + 1),
                    lineEnd: reference.map { $0.chunkIndex + 1 } ?? (index + 1),
                    order: reference?.chunkIndex ?? index,
                    snippet: snippet
                )
            }
        }

        let legacyConcepts = resolved.concepts.map { concept in
            KnowledgeConcept(
                id: concept.id,
                name: concept.name,
                definition: concept.descriptionText ?? concept.name,
                aliases: concept.aliases,
                category: "concept",
                section: sourceSignature,
                source: concept.sourceChunkIDs.first ?? sourceSignature,
                definitionEvidence: concept.descriptionText.map { [$0] } ?? [],
                aliasEvidence: concept.aliases,
                sourceExcerpt: concept.descriptionText ?? concept.name,
                importance: concept.importanceScore,
                difficulty: 0.5,
                relationships: [],
                examples: concept.descriptionText.map { [$0] } ?? [],
                learningObjective: concept.descriptionText ?? concept.name,
                confidence: concept.confidenceScore,
                sourceLocations: sourceLocations(for: concept.sourceChunkIDs, title: concept.name, snippet: concept.descriptionText ?? concept.name)
            )
        }

        let legacyConceptIDByName = Dictionary(uniqueKeysWithValues: legacyConcepts.map { (Self.normalizedKey(for: $0.name), $0.id) })
        let legacyConceptNameByID = Dictionary(uniqueKeysWithValues: legacyConcepts.map { ($0.id, $0.name) })

        let legacyRelationships = payload.relationships.compactMap { relationship -> KnowledgeRelationship? in
            let sourceID = relationship.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetID = relationship.targetID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceID.isEmpty, !targetID.isEmpty else { return nil }

            let sourceConcept = conceptsByID[sourceID] ?? conceptsByNormalizedName[Self.normalizedKey(for: sourceID)]
            let targetConcept = conceptsByID[targetID] ?? conceptsByNormalizedName[Self.normalizedKey(for: targetID)]
            let sourceLegacyID = sourceConcept.map { legacyConceptIDByName[Self.normalizedKey(for: $0.name)] ?? $0.id } ?? sourceID
            let targetLegacyID = targetConcept.map { legacyConceptIDByName[Self.normalizedKey(for: $0.name)] ?? $0.id } ?? targetID

            return KnowledgeRelationship(
                id: "rel-\(sourceLegacyID)-\(targetLegacyID)-\(relationship.relationshipType.rawValue.lowercased())",
                sourceID: sourceLegacyID,
                targetID: targetLegacyID,
                relationKind: relationship.relationshipType.bridgedRelationshipKind(),
                relation: relationship.relationshipType.rawValue,
                sourceLocations: sourceLocations(for: relationship.sourceChunkIDs, title: legacyConceptNameByID[sourceLegacyID] ?? sourceLegacyID),
                confidence: relationship.confidenceScore
            )
        }

        let factStatements = Self.dedupeStrings(payload.facts.map(\.statement))
        let sectionLocations = payload.sourceReferences.map { reference in
            KnowledgeSourceLocation(
                id: "src-\(reference.chunkID)",
                sectionID: reference.chunkID,
                sectionTitle: reference.documentID,
                lineStart: reference.chunkIndex + 1,
                lineEnd: reference.chunkIndex + 1,
                order: reference.chunkIndex,
                snippet: ""
            )
        }

        let sections: [KnowledgeSection] = sectionLocations.isEmpty ? [KnowledgeSection(
            id: sourceSignature,
            title: title,
            kind: .custom,
            order: 0,
            content: supportingEvidence.joined(separator: "\n"),
            children: [],
            sourceLocations: []
        )] : sectionLocations.enumerated().map { index, location in
            KnowledgeSection(
                id: location.sectionID,
                title: location.sectionTitle.isEmpty ? title : location.sectionTitle,
                kind: .custom,
                order: index,
                content: location.snippet,
                children: [],
                sourceLocations: [location]
            )
        }

        return StructuredKnowledge(
            metadata: KnowledgeMetadata(
                noteID: sourceSignature,
                title: title,
                subject: subject,
                sourceType: sourceType,
                approximateTokenCount: approximateTokenCount,
                sectionCount: sectionCount,
                extractedAt: Date(),
                modelName: "",
                promptVersion: "",
                appVersion: "",
                gitCommit: "",
                sourceSignature: sourceSignature
            ),
            title: title,
            topics: Self.dedupeStrings(keywords + legacyConcepts.map(\.name)),
            sections: sections,
            concepts: legacyConcepts,
            definitions: legacyConcepts.map { concept in
                KnowledgeDefinition(
                    id: concept.id,
                    term: concept.name,
                    definition: concept.definition,
                    aliases: concept.aliases,
                    sourceLocations: concept.sourceLocations,
                    confidence: concept.confidence
                )
            },
            examples: legacyConcepts.flatMap { concept in
                concept.examples.map { example in
                    KnowledgeExample(
                        id: "\(concept.id)-example-\(String(example.lowercased().prefix(16)).replacingOccurrences(of: " ", with: "-"))",
                        conceptID: concept.id,
                        example: example,
                        sourceLocations: concept.sourceLocations,
                        confidence: concept.confidence
                    )
                }
            },
            processes: [],
            relationships: legacyRelationships,
            learningObjectives: legacyConcepts.compactMap { concept in
                let objective = concept.learningObjective.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !objective.isEmpty else { return nil }
                return KnowledgeObjective(
                    id: concept.id,
                    objective: objective,
                    relatedConceptIDs: [concept.id],
                    sourceLocations: concept.sourceLocations,
                    confidence: concept.confidence
                )
            },
            actionItems: [],
            keywords: Self.dedupeStrings(keywords + legacyConcepts.flatMap { $0.aliases }),
            confidence: legacyConcepts.map(\.confidence).reduce(0, +) / Double(max(legacyConcepts.count, 1)),
            sourceLocations: sectionLocations,
            difficulty: difficulty,
            importance: legacyConcepts.map(\.importance).max() ?? 0.5,
            aliases: Self.dedupeStrings(legacyConcepts.flatMap { $0.aliases }),
            procedures: [],
            formulas: [],
            importantFacts: factStatements,
            keyTerminology: Self.dedupeStrings(legacyConcepts.map(\.name) + keywords),
            misconceptions: [],
            prerequisites: [],
            hierarchy: sections,
            supportingEvidence: supportingEvidence,
            summaryHighlights: summaryHighlights,
            examFocus: examFocus
        )
    }

    private func inferSourceReferences() -> [ExtractionSourceReference] {
        let locations = sourceLocations
            + concepts.flatMap(\.sourceLocations)
            + definitions.flatMap(\.sourceLocations)
            + relationships.flatMap(\.sourceLocations)
        let uniqueChunkIDs = Self.dedupeStrings(locations.map(\.sectionID))
        return uniqueChunkIDs.enumerated().map { index, chunkID in
            ExtractionSourceReference(
                chunkID: chunkID,
                documentID: metadata.sourceSignature.isEmpty ? metadata.noteID : metadata.sourceSignature,
                chunkIndex: index,
                startOffset: nil,
                endOffset: nil
            )
        }
    }

    private static func normalizedKey(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func dedupeStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Self.normalizedKey(for: trimmed)
            guard !trimmed.isEmpty, !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return trimmed
        }
    }
}
