import Foundation

struct KnowledgeContext: Codable, Equatable, Sendable {
    var noteID: UUID?
    var noteTitle: String
    var notePreview: String
    var retrievedNotes: [NoteSearchRecord]
    var retrievedChunks: [KnowledgeChunkRecord]
    var concepts: [CanonicalConceptRecord]
    var relationships: [KnowledgeRelationshipRecord]
    var relatedConcepts: [CanonicalConceptRecord]
    var retrievalSources: [RetrievalSource]
    var citations: [CitationReference]
    var studentConcepts: [StudentConceptRecord]
    var recentReviewHistory: [ReviewEvent]
    var tutorContext: TutorContext
    var graphContext: GraphContext?

    var knowledgeJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    func graphPromptRepresentation() -> String {
        graphContext?.graphPromptRepresentation() ?? ""
    }
}

struct TutorConceptContext: Codable, Equatable, Sendable {
    var conceptID: String
    var conceptTitle: String
    var masteryScore: Double
    var confidenceScore: Double
    var reviewCount: Int
    var mistakeCount: Int
    var lastReviewed: Date?

    var explanationStyle: String {
        switch masteryScore {
        case ..<0.35:
            return "beginner"
        case ..<0.7:
            return "intermediate"
        default:
            return "advanced"
        }
    }
}

struct TutorContext: Codable, Equatable, Sendable {
    var noteID: UUID?
    var noteTitle: String
    var focusConcepts: [TutorConceptContext]
    var evidenceSources: [RetrievalSource] = []
    var citations: [CitationReference] = []
    var evidenceSummary: String = ""
    var recentReviewHistory: [ReviewEvent] = []

    var explanationStyle: String {
        let average = focusConcepts.map(\.masteryScore).reduce(0, +) / Double(max(1, focusConcepts.count))
        switch average {
        case ..<0.35:
            return "beginner"
        case ..<0.7:
            return "intermediate"
        default:
            return "advanced"
        }
    }

    var guidanceSummary: String {
        let concepts = focusConcepts.prefix(5).map { "\($0.conceptTitle): \($0.explanationStyle) (\(Int(($0.masteryScore * 100).rounded()))%)" }
        let evidence = evidenceSources.prefix(4).map { $0.title }.filter { $0.isEmpty == false }
        let evidenceLine = evidence.isEmpty ? nil : "Evidence sources: " + evidence.joined(separator: ", ")
        let masteryLine = concepts.isEmpty
            ? "No mastery data available."
            : "Recommended explanation style: \(explanationStyle). " + concepts.joined(separator: "; ")
        return [masteryLine, evidenceSummary.isEmpty ? nil : evidenceSummary, evidenceLine]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

extension KnowledgeContext {
    func studySnapshotRepresentation() -> StudyKnowledgeSnapshot {
        let conceptTitles = concepts.map(\.canonicalName)
        let noteTitles = retrievedNotes.map(\.noteTitle)
        let relationshipItems = relationships.prefix(12).map { relationship in
            StudyKnowledgeRelationship(
                sourceTitle: relationship.sourceConceptID,
                targetTitle: relationship.targetConceptID,
                relation: relationship.relationType,
                confidence: relationship.confidence
            )
        }
        let weakest = studentConcepts.sorted { $0.masteryScore < $1.masteryScore }.prefix(6).map { $0.conceptID }
        let mastered = studentConcepts.sorted { $0.masteryScore > $1.masteryScore }.prefix(6).map { $0.conceptID }
        return StudyKnowledgeSnapshot(
            title: noteTitle,
            sourceSignature: noteID?.uuidString ?? noteTitle,
            cleanedText: notePreview,
            normalizedText: notePreview.lowercased(),
            topics: Array((conceptTitles + noteTitles).prefix(6)),
            concepts: concepts.prefix(10).map { concept in
                StudyKnowledgeItem(
                    title: concept.canonicalName,
                    summary: concept.description.isEmpty ? concept.canonicalName : concept.description,
                    evidence: concept.sourceReferences,
                    importance: concept.confidence,
                    difficulty: concept.confidence < 0.4 ? 0.3 : (concept.confidence < 0.7 ? 0.5 : 0.8),
                    aliases: concept.aliases,
                    relatedTitles: relationships.filter { $0.sourceConceptID == concept.id }.map { $0.targetConceptID },
                    category: "concept"
                )
            },
            definitions: concepts.prefix(8).map { concept in
                StudyKnowledgeItem(
                    title: concept.canonicalName,
                    summary: concept.description.isEmpty ? concept.canonicalName : concept.description,
                    evidence: concept.sourceReferences,
                    importance: concept.confidence,
                    difficulty: concept.confidence < 0.4 ? 0.3 : (concept.confidence < 0.7 ? 0.5 : 0.8),
                    aliases: concept.aliases,
                    relatedTitles: [],
                    category: "definition"
                )
            },
            relationships: relationshipItems,
            examples: [],
            procedures: [],
            formulas: [],
            importantFacts: mastered.map { StudyKnowledgeItem(title: $0, summary: "Mastery is improving.", importance: 0.5, category: "fact") },
            keyTerms: (concepts.prefix(10).map { StudyKnowledgeItem(title: $0.canonicalName, summary: $0.description, importance: $0.confidence, aliases: $0.aliases, category: "term") }),
            misconceptions: weakest.map { StudyKnowledgeItem(title: $0, summary: "Needs review.", importance: 0.2, category: "misconception") },
            prerequisites: [],
            hierarchy: [],
            difficulty: .intermediate,
            supportingExamples: retrievedChunks.prefix(6).map {
                StudyKnowledgeItem(
                    title: $0.sectionName.isEmpty ? "Chunk" : $0.sectionName,
                    summary: $0.content,
                    evidence: [$0.id],
                    importance: 0.5,
                    difficulty: 0.5,
                    category: "example"
                )
            },
            supportingEvidence: retrievedChunks.prefix(6).map { $0.content },
            summaryHighlights: [notePreview],
            examFocus: weakest,
            tokenEstimate: notePreview.split(separator: " ").count,
            extractionStrategy: "sqlite-context"
        )
    }
}

final class ContextBuilder {
    static let shared = ContextBuilder()

    private let knowledgeRepository: KnowledgeRepository
    private let studyRepository: StudyRepository
    private let studentConceptService: StudentConceptService
    private let hybridRetriever: HybridRetriever
    private let graphContextBuilder: GraphContextBuilder

    init(
        knowledgeRepository: KnowledgeRepository = .shared,
        studyRepository: StudyRepository = .shared,
        studentConceptService: StudentConceptService = .shared,
        hybridRetriever: HybridRetriever = .shared,
        graphContextBuilder: GraphContextBuilder? = nil
    ) {
        self.knowledgeRepository = knowledgeRepository
        self.studyRepository = studyRepository
        self.studentConceptService = studentConceptService
        self.hybridRetriever = hybridRetriever
        self.graphContextBuilder = graphContextBuilder ?? GraphContextBuilder(repository: knowledgeRepository)
    }

    func build(noteID: UUID? = nil, title: String, text: String) -> KnowledgeContext {
        let preview = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        let query = [title, text].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let retrievalResults = hybridRetriever.retrieveResults(query: query.isEmpty ? title : query, limit: 24)
        let citations = retrievalResults.map { $0.citation }

        let noteResults = retrievalResults
            .filter { $0.kind == .note }
            .map { hit in
                NoteSearchRecord(
                    noteID: hit.noteID,
                    folderID: hit.folderID ?? UUID(),
                    folderTitle: hit.folderTitle ?? "General",
                    noteTitle: hit.noteTitle.isEmpty ? hit.title : hit.noteTitle,
                    snippet: hit.snippet,
                    content: hit.content,
                    updatedAt: hit.updatedAt ?? Date(),
                    rank: hit.score
                )
            }

        let retrievedChunks = retrievalResults
            .filter { $0.kind == .chunk }
            .map { hit in
                KnowledgeChunkRecord(
                    id: hit.chunkID ?? hit.id,
                    noteID: hit.noteID,
                    documentID: hit.noteID.uuidString,
                    chunkIndex: 0,
                    sectionName: hit.title,
                    content: hit.content,
                    startLine: 0,
                    endLine: 0,
                    provenanceNoteID: hit.noteID
                )
            }

        let conceptRecords: [CanonicalConceptRecord] = retrievalResults
            .filter { $0.kind == .concept }
            .compactMap { hit in
                if let conceptID = hit.conceptID, let concept = try? knowledgeRepository.concept(for: conceptID) {
                    return concept
                }
                return CanonicalConceptRecord(
                    id: hit.conceptID ?? hit.id,
                    canonicalName: hit.title,
                    aliases: [],
                    sourceReferences: hit.sources.compactMap { $0.noteID?.uuidString },
                    confidence: hit.score,
                    description: hit.content
                )
            }

        let relationships = deduplicateRelationships(conceptRecords.flatMap { concept in
            (try? knowledgeRepository.relationships(containing: concept.id, limit: 6)) ?? []
        })
        let graphContext = graphContextBuilder.buildContext(query: query.isEmpty ? title : query)
        let graphConcepts = mergeConcepts(conceptRecords, graphContext.concepts)
        let graphRelationships = deduplicateRelationships(relationships + graphContext.relationships)

        let retrievalSources = deduplicateSources(retrievalResults.flatMap { $0.sources })
        let mastery = noteID.flatMap { try? studyRepository.studentConcepts(for: $0) }
            ?? (try? studentConceptService.recentlyReviewedConcepts(limit: 6)) ?? []
        let recentReviewHistory = noteID.flatMap { try? studyRepository.reviewEvents(for: $0) } ?? []
        let conceptTitleByID = Dictionary(uniqueKeysWithValues: graphConcepts.map { ($0.id, $0.canonicalName) })
        let tutorContext = TutorContext(
            noteID: noteID,
            noteTitle: title,
            focusConcepts: mastery.map {
                TutorConceptContext(
                    conceptID: $0.conceptID,
                    conceptTitle: conceptTitleByID[$0.conceptID] ?? $0.conceptID,
                    masteryScore: $0.effectiveMasteryScore,
                    confidenceScore: $0.confidenceScore,
                    reviewCount: $0.reviewCount,
                    mistakeCount: $0.mistakeCount,
                    lastReviewed: $0.lastReviewed
                )
            },
            evidenceSources: Array(retrievalSources.prefix(8)),
            citations: Array(citations.prefix(8)),
            evidenceSummary: retrievalSources.isEmpty
                ? "No retrieved evidence available."
                : "Retrieved evidence includes: " + retrievalSources.prefix(5).map { $0.title }.joined(separator: ", "),
            recentReviewHistory: recentReviewHistory.prefix(12).map { $0 }
        )

        return KnowledgeContext(
            noteID: noteID,
            noteTitle: title,
            notePreview: preview,
            retrievedNotes: noteResults,
            retrievedChunks: retrievedChunks,
            concepts: graphConcepts,
            relationships: graphRelationships,
            relatedConcepts: graphContext.concepts,
            retrievalSources: Array(retrievalSources.prefix(16)),
            citations: Array(citations.prefix(16)),
            studentConcepts: mastery,
            recentReviewHistory: recentReviewHistory.prefix(12).map { $0 },
            tutorContext: tutorContext,
            graphContext: graphContext
        )
    }

    private func deduplicateSources(_ sources: [RetrievalSource]) -> [RetrievalSource] {
        var seen: Set<String> = []
        return sources.filter { source in
            seen.insert(source.id).inserted
        }
    }

    private func deduplicateRelationships(_ relationships: [KnowledgeRelationshipRecord]) -> [KnowledgeRelationshipRecord] {
        var seen: Set<String> = []
        return relationships.filter { relationship in
            seen.insert(relationship.id).inserted
        }
    }

    private func mergeConcepts(_ primary: [CanonicalConceptRecord], _ secondary: [CanonicalConceptRecord]) -> [CanonicalConceptRecord] {
        var seen: Set<String> = []
        return (primary + secondary).filter { concept in
            seen.insert(concept.id).inserted
        }
    }
}
