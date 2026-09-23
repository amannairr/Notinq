import Foundation

enum RetrievalSourceType: String, Codable, Sendable {
    case note
    case chunk
    case concept
    case relationship
}

struct RetrievalSource: Codable, Equatable, Sendable {
    var type: RetrievalSourceType
    var id: String
    var title: String
    var noteID: UUID?
    var noteTitle: String?
    var chunkID: String?
    var conceptID: String?
    var relationshipID: String?
    var location: String?
    var summary: String
}

struct CitationReference: Codable, Equatable, Sendable {
    var sourceType: RetrievalResult.SourceType
    var sourceID: String
    var noteTitle: String
    var conceptName: String?
    var snippet: String
}

struct RetrievalResult: Identifiable, Codable, Equatable, Sendable {
    enum SourceType: String, Codable, Sendable {
        case note
        case chunk
        case concept
        case relationship
    }

    var id: String
    var noteID: UUID
    var noteTitle: String
    var kind: RetrievalHit.Kind
    var chunkID: String?
    var conceptID: String?
    var relationshipID: String?
    var score: Double
    var sourceType: SourceType
    var title: String
    var snippet: String
    var content: String
    var updatedAt: Date?
    var folderID: UUID?
    var folderTitle: String?
    var provenance: [String]
    var sources: [RetrievalSource]

    var citation: CitationReference {
        let primarySource = sources.first
        return CitationReference(
            sourceType: sourceType,
            sourceID: primarySource?.id ?? id,
            noteTitle: primarySource?.noteTitle ?? noteTitle,
            conceptName: conceptID == nil ? nil : title,
            snippet: primarySource?.summary ?? snippet
        )
    }
}

struct RetrievalHit: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case note
        case chunk
        case concept
    }
    
    var id: String
    var kind: Kind
    var noteID: UUID
    var noteTitle: String
    var chunkID: String?
    var conceptID: String?
    var folderID: UUID?
    var folderTitle: String?
    var title: String
    var snippet: String
    var content: String
    var relevance: Double
    var updatedAt: Date?
    var relationshipID: String?
    var provenance: [String] = []
    var sources: [RetrievalSource] = []
    
    var result: RetrievalResult {
        let sourceType: RetrievalResult.SourceType
        
        if relationshipID != nil {
            sourceType = .relationship
        } else {
            switch kind {
            case .note:
                sourceType = .note
            case .chunk:
                sourceType = .chunk
            case .concept:
                sourceType = .concept
            }
        }
        
        return RetrievalResult(
            id: id,
            noteID: noteID,
            noteTitle: noteTitle,
            kind: kind,
            chunkID: chunkID,
            conceptID: conceptID,
            relationshipID: relationshipID,
            score: relevance,
            sourceType: sourceType,
            title: title,
            snippet: snippet,
            content: content,
            updatedAt: updatedAt,
            folderID: folderID,
            folderTitle: folderTitle,
            provenance: provenance,
            sources: sources
        )
    }   // closes result property
}   // closes RetrievalHit struct


final class LexicalRetriever {
    static let shared = LexicalRetriever()

    private let noteRepository: NoteRepository
    private let knowledgeRepository: KnowledgeRepository

    init(noteRepository: NoteRepository = .shared, knowledgeRepository: KnowledgeRepository = .shared) {
        self.noteRepository = noteRepository
        self.knowledgeRepository = knowledgeRepository
    }

    func retrieve(query: String, limit: Int = 12) -> [RetrievalHit] {
        do {
            let noteHits = try noteRepository.searchNotes(query: query, limit: limit)
            let chunkHits = try knowledgeRepository.searchChunks(query: query, limit: limit)

            let noteResults = noteHits.map {
                RetrievalHit(
                    id: "note:\($0.noteID.uuidString)",
                    kind: .note,
                    noteID: $0.noteID,
                    noteTitle: $0.noteTitle,
                    chunkID: nil,
                    conceptID: nil,
                    folderID: $0.folderID,
                    folderTitle: $0.folderTitle,
                    title: $0.noteTitle,
                    snippet: $0.snippet,
                    content: $0.content,
                    relevance: $0.rank,
                    updatedAt: $0.updatedAt,
                    relationshipID: nil,
                    provenance: ["folder:\($0.folderID.uuidString)"],
                    sources: [
                        RetrievalSource(
                            type: .note,
                            id: "note:\($0.noteID.uuidString)",
                            title: $0.noteTitle,
                            noteID: $0.noteID,
                            noteTitle: $0.noteTitle,
                            chunkID: nil,
                            conceptID: nil,
                            relationshipID: nil,
                            location: nil,
                            summary: $0.snippet
                        )
                    ]
                )
            }

            let chunkResults = chunkHits.map {
                RetrievalHit(
                    id: "chunk:\($0.chunkID)",
                    kind: .chunk,
                    noteID: $0.noteID,
                    noteTitle: $0.noteTitle,
                    chunkID: $0.chunkID,
                    conceptID: nil,
                    folderID: nil,
                    folderTitle: nil,
                    title: "\($0.noteTitle) • \($0.sectionName)",
                    snippet: $0.snippet,
                    content: $0.content,
                    relevance: $0.rank,
                    updatedAt: $0.updatedAt,
                    relationshipID: nil,
                    provenance: ["chunk:\($0.chunkID)", "note:\($0.noteID.uuidString)"],
                    sources: [
                        RetrievalSource(
                            type: .chunk,
                            id: "chunk:\($0.chunkID)",
                            title: $0.sectionName.isEmpty ? $0.noteTitle : $0.sectionName,
                            noteID: $0.noteID,
                            noteTitle: $0.noteTitle,
                            chunkID: $0.chunkID,
                            conceptID: nil,
                            relationshipID: nil,
                            location: $0.sectionName.isEmpty ? nil : $0.sectionName,
                            summary: $0.snippet
                        )
                    ]
                )
            }

            return noteResults + chunkResults
        } catch {
            return []
        }
    }
}

final class VectorRetriever {
    static let shared = VectorRetriever()

    private init() {}

    func retrieve(query: String, limit: Int = 10) -> [RetrievalHit] {
        _ = query
        _ = limit
        return []
    }
}

final class GraphRetriever {
    static let shared = GraphRetriever()

    private let knowledgeRepository: KnowledgeRepository
    private let graphService: KnowledgeGraphService
    private let maxTraversalDepth: Int
    private let maxTraversalConcepts: Int

    init(
        knowledgeRepository: KnowledgeRepository = .shared,
        graphService: KnowledgeGraphService? = nil,
        maxTraversalDepth: Int = 2,
        maxTraversalConcepts: Int = 12
    ) {
        self.knowledgeRepository = knowledgeRepository
        self.graphService = graphService ?? KnowledgeGraphService(repository: knowledgeRepository)
        self.maxTraversalDepth = max(1, min(maxTraversalDepth, 4))
        self.maxTraversalConcepts = max(1, min(maxTraversalConcepts, 48))
    }

    func retrieve(query: String, limit: Int = 10) -> [RetrievalHit] {
        do {
            let seedConcepts = try knowledgeRepository.searchConcepts(query: query, limit: max(1, limit / 2))
            var hits: [RetrievalHit] = []
            var visitedConceptIDs: Set<String> = []
            var visitedNoteIDs: Set<UUID> = []
            var visitedChunkIDs: Set<String> = []

            for concept in seedConcepts {
                hits.append(makeConceptHit(concept: concept, relationshipID: nil, confidenceBonus: 0.12))
                visitedConceptIDs.insert(concept.conceptID)

                let relationships = (try? knowledgeRepository.relationships(containing: concept.conceptID, limit: 4)) ?? []
                for relationship in relationships.prefix(4) {
                    let relatedConceptID = relationship.sourceConceptID == concept.conceptID
                        ? relationship.targetConceptID
                        : relationship.sourceConceptID
                    guard visitedConceptIDs.contains(relatedConceptID) == false else { continue }

                    if let relatedConcept = try knowledgeRepository.concept(for: relatedConceptID) {
                        visitedConceptIDs.insert(relatedConceptID)
                        hits.append(makeConceptHit(concept: relatedConcept, relationshipID: relationship.id, confidenceBonus: relationship.confidence * 0.25))

                        let relatedNoteIDs = relatedConcept.sourceReferences.compactMap { UUID(uuidString: $0) }
                        for noteID in relatedNoteIDs.prefix(2) {
                            guard visitedNoteIDs.insert(noteID).inserted else { continue }
                            let noteTitle = (try? knowledgeRepository.noteTitle(for: noteID)) ?? relatedConcept.canonicalName
                            hits.append(
                                RetrievalHit(
                                    id: "note:\(noteID.uuidString)",
                                    kind: .note,
                                    noteID: noteID,
                                    noteTitle: noteTitle,
                                    chunkID: nil,
                                    conceptID: relatedConcept.id,
                                    folderID: nil,
                                    folderTitle: nil,
                                    title: noteTitle,
                                    snippet: relatedConcept.description.isEmpty ? relatedConcept.canonicalName : relatedConcept.description,
                                    content: relatedConcept.description,
                                    relevance: max(0.24, concept.rank * 0.52 + relationship.confidence * 0.28),
                                    updatedAt: nil,
                                    relationshipID: relationship.id,
                                    provenance: [
                                        "relationship:\(relationship.id)",
                                        "concept:\(relatedConcept.id)",
                                        "note:\(noteID.uuidString)"
                                    ],
                                    sources: [
                                        RetrievalSource(
                                            type: .relationship,
                                            id: "relationship:\(relationship.id)",
                                            title: relationship.relationType,
                                            noteID: noteID,
                                            noteTitle: noteTitle,
                                            chunkID: nil,
                                            conceptID: relatedConcept.id,
                                            relationshipID: relationship.id,
                                            location: nil,
                                            summary: "\(relationship.relationType) between \(relationship.sourceConceptID) and \(relationship.targetConceptID)"
                                        ),
                                        RetrievalSource(
                                            type: .concept,
                                            id: "concept:\(relatedConcept.id)",
                                            title: relatedConcept.canonicalName,
                                            noteID: noteID,
                                            noteTitle: noteTitle,
                                            chunkID: nil,
                                            conceptID: relatedConcept.id,
                                            relationshipID: relationship.id,
                                            location: nil,
                                            summary: relatedConcept.description.isEmpty ? relatedConcept.canonicalName : relatedConcept.description
                                        )
                                    ]
                                )
                            )

                            let chunks = (try? knowledgeRepository.chunks(for: noteID)) ?? []
                            for chunk in chunks.prefix(2) {
                                guard visitedChunkIDs.insert(chunk.id).inserted else { continue }
                                hits.append(
                                    RetrievalHit(
                                        id: "chunk:\(chunk.id)",
                                        kind: .chunk,
                                        noteID: noteID,
                                        noteTitle: noteTitle,
                                        chunkID: chunk.id,
                                        conceptID: relatedConcept.id,
                                        folderID: nil,
                                        folderTitle: nil,
                                        title: chunk.sectionName.isEmpty ? noteTitle : "\(noteTitle) • \(chunk.sectionName)",
                                        snippet: String(chunk.content.prefix(220)),
                                        content: chunk.content,
                                        relevance: max(0.2, concept.rank * 0.42 + relationship.confidence * 0.22),
                                        updatedAt: nil,
                                        relationshipID: relationship.id,
                                        provenance: [
                                            "relationship:\(relationship.id)",
                                            "note:\(noteID.uuidString)",
                                            "chunk:\(chunk.id)"
                                        ],
                                        sources: [
                                            RetrievalSource(
                                                type: .relationship,
                                                id: "relationship:\(relationship.id)",
                                                title: relationship.relationType,
                                                noteID: noteID,
                                                noteTitle: noteTitle,
                                                chunkID: chunk.id,
                                                conceptID: relatedConcept.id,
                                                relationshipID: relationship.id,
                                                location: chunk.sectionName.isEmpty ? nil : chunk.sectionName,
                                                summary: relationship.relationType
                                            ),
                                            RetrievalSource(
                                                type: .chunk,
                                                id: "chunk:\(chunk.id)",
                                                title: chunk.sectionName.isEmpty ? noteTitle : chunk.sectionName,
                                                noteID: noteID,
                                                noteTitle: noteTitle,
                                                chunkID: chunk.id,
                                                conceptID: relatedConcept.id,
                                                relationshipID: relationship.id,
                                                location: chunk.sectionName.isEmpty ? nil : chunk.sectionName,
                                                summary: String(chunk.content.prefix(220))
                                            )
                                        ]
                                    )
                                )
                            }
                        }
                    }
                }

                let traversalConcepts = (
                    (try? graphService.descendants(of: concept.conceptID, depth: maxTraversalDepth, limit: maxTraversalConcepts)) ?? []
                ) + (
                    (try? graphService.ancestors(of: concept.conceptID, depth: maxTraversalDepth, limit: maxTraversalConcepts / 2)) ?? []
                ) + (
                    (try? graphService.neighbors(of: concept.conceptID, limit: maxTraversalConcepts / 2)) ?? []
                )

                for relatedConcept in traversalConcepts {
                    guard visitedConceptIDs.insert(relatedConcept.id).inserted else { continue }
                    hits.append(makeConceptHit(concept: relatedConcept, relationshipID: nil, confidenceBonus: relatedConcept.confidence * 0.18))

                    let relatedNoteIDs = relatedConcept.sourceReferences.compactMap { UUID(uuidString: $0) }
                    for noteID in relatedNoteIDs.prefix(2) {
                        guard visitedNoteIDs.insert(noteID).inserted else { continue }
                        let noteTitle = (try? knowledgeRepository.noteTitle(for: noteID)) ?? relatedConcept.canonicalName
                        hits.append(
                            RetrievalHit(
                                id: "note:\(noteID.uuidString)",
                                kind: .note,
                                noteID: noteID,
                                noteTitle: noteTitle,
                                chunkID: nil,
                                conceptID: relatedConcept.id,
                                folderID: nil,
                                folderTitle: nil,
                                title: noteTitle,
                                snippet: relatedConcept.description.isEmpty ? relatedConcept.canonicalName : relatedConcept.description,
                                content: relatedConcept.description,
                                relevance: max(0.2, concept.rank * 0.42 + relatedConcept.confidence * 0.22),
                                updatedAt: nil,
                                relationshipID: nil,
                                provenance: [
                                    "concept:\(relatedConcept.id)",
                                    "note:\(noteID.uuidString)",
                                    "graph-depth:\(maxTraversalDepth)"
                                ],
                                sources: [
                                    RetrievalSource(
                                        type: .concept,
                                        id: "concept:\(relatedConcept.id)",
                                        title: relatedConcept.canonicalName,
                                        noteID: noteID,
                                        noteTitle: noteTitle,
                                        chunkID: nil,
                                        conceptID: relatedConcept.id,
                                        relationshipID: nil,
                                        location: nil,
                                        summary: relatedConcept.description.isEmpty ? relatedConcept.canonicalName : relatedConcept.description
                                    )
                                ]
                            )
                        )
                    }
                }
            }

            return hits
        } catch {
            return []
        }
    }

    private func makeConceptHit(concept: ConceptSearchRecord, relationshipID: String?, confidenceBonus: Double) -> RetrievalHit {
        let canonicalConcept = CanonicalConceptRecord(
            id: concept.conceptID,
            canonicalName: concept.canonicalName,
            aliases: concept.aliases,
            sourceReferences: concept.noteIDs.map(\.uuidString),
            confidence: concept.rank,
            description: concept.description
        )
        return makeConceptHit(concept: canonicalConcept, relationshipID: relationshipID, confidenceBonus: confidenceBonus)
    }

    private func makeConceptHit(concept: CanonicalConceptRecord, relationshipID: String?, confidenceBonus: Double) -> RetrievalHit {
        let noteIDs = concept.sourceReferences.compactMap { UUID(uuidString: $0) }
        let noteID = noteIDs.first ?? UUID()
        let noteTitle = (try? knowledgeRepository.noteTitle(for: noteID)) ?? concept.canonicalName
        let snippet = concept.description.isEmpty ? concept.aliases.joined(separator: ", ") : concept.description
        return RetrievalHit(
            id: "concept:\(concept.id)",
            kind: .concept,
            noteID: noteID,
            noteTitle: noteTitle,
            chunkID: nil,
            conceptID: concept.id,
            folderID: nil,
            folderTitle: nil,
            title: concept.canonicalName,
            snippet: snippet,
            content: concept.description,
            relevance: concept.confidence + confidenceBonus,
            updatedAt: nil,
            relationshipID: relationshipID,
            provenance: noteIDs.map { "note:\($0.uuidString)" } + (relationshipID.map { ["relationship:\($0)"] } ?? []),
            sources: noteIDs.map { relatedNoteID in
                RetrievalSource(
                    type: relationshipID == nil ? .concept : .relationship,
                    id: relationshipID.map { "relationship:\($0)" } ?? "concept:\(concept.id)",
                    title: concept.canonicalName,
                    noteID: relatedNoteID,
                    noteTitle: (try? knowledgeRepository.noteTitle(for: relatedNoteID)) ?? concept.canonicalName,
                    chunkID: nil,
                    conceptID: concept.id,
                    relationshipID: relationshipID,
                    location: nil,
                    summary: snippet
                )
            }
        )
    }
}

final class HybridRetriever {
    static let shared = HybridRetriever()

    private let lexicalRetriever: LexicalRetriever
    private let graphRetriever: GraphRetriever
    private let vectorRetriever: VectorRetriever
    private let studentConceptService: StudentConceptService

    init(
        lexicalRetriever: LexicalRetriever = .shared,
        graphRetriever: GraphRetriever = .shared,
        vectorRetriever: VectorRetriever = .shared,
        studentConceptService: StudentConceptService = .shared
    ) {
        self.lexicalRetriever = lexicalRetriever
        self.graphRetriever = graphRetriever
        self.vectorRetriever = vectorRetriever
        self.studentConceptService = studentConceptService
    }

    func retrieve(query: String, limit: Int = 24) -> [RetrievalHit] {
        let lexical = lexicalRetriever.retrieve(query: query, limit: limit)
        let graph = graphRetriever.retrieve(query: query, limit: limit)
        let vector = vectorRetriever.retrieve(query: query, limit: limit)
        return merge(rank(lexical: lexical, graph: graph, vector: vector, query: query, limit: limit), limit: limit)
    }

    func retrieveResults(query: String, limit: Int = 24) -> [RetrievalResult] {
        retrieve(query: query, limit: limit).map { $0.result }
    }

    func retrieveChunks(query: String, limit: Int = 10) -> [KnowledgeChunkRecord] {
        retrieve(query: query, limit: limit)
            .filter { $0.kind == .chunk }
            .prefix(limit)
            .compactMap { hit in
                guard let chunkID = hit.chunkID else { return nil }
                return KnowledgeChunkRecord(
                    id: chunkID,
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
    }

    func retrieveSources(query: String, limit: Int = 24) -> [RetrievalSource] {
        retrieve(query: query, limit: limit).flatMap { $0.sources }
    }

    private func rank(lexical: [RetrievalHit], graph: [RetrievalHit], vector: [RetrievalHit], query: String, limit: Int) -> [RetrievalHit] {
        /*
         Ranking formula:
         finalScore = sourceBase + lexicalOverlap + sourceCoverage + relationshipBoost + masteryBoost + queryMatchBoost
         - FTS note/chunk results start highest because they already carry bm25-style signal.
         - Concept and relationship results get a slightly lower base so direct text matches stay on top.
         - Low-mastery concepts receive a small boost so the tutor can surface weak areas first.
         */
        let queryTokens = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.isEmpty == false })
        let masteryLookup = Dictionary(
            (try? studentConceptService.recentlyReviewedConcepts(limit: 32))?.map { ($0.conceptID, $0.masteryScore) } ?? [],
            uniquingKeysWith: max
        )

        return (lexical.map { weighted($0, base: 1.0, queryTokens: queryTokens, masteryLookup: masteryLookup) }
            + graph.map { weighted($0, base: 0.86, queryTokens: queryTokens, masteryLookup: masteryLookup) }
            + vector.map { weighted($0, base: 0.5, queryTokens: queryTokens, masteryLookup: masteryLookup) })
        .sorted {
            if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        .prefix(limit)
        .map { $0 }
    }

    private func weighted(_ hit: RetrievalHit, base: Double, queryTokens: Set<String>, masteryLookup: [String: Double]) -> RetrievalHit {
        var copy = hit
        let normalizedQuery = queryTokens.joined(separator: " ")
        let sourceBoost = min(0.12, Double(hit.sources.count) * 0.04)
        let relationshipBoost = hit.relationshipID == nil ? 0.0 : 0.08
        let kindBoost: Double = switch hit.kind {
        case .note: 0.08
        case .chunk: 0.12
        case .concept: 0.16
        }
        let haystack = (hit.title + " " + hit.snippet + " " + hit.content).lowercased()
        let queryBoost = queryTokens.contains(where: { haystack.contains($0) }) ? 0.08 : 0.0
        let exactNoteMatchBoost: Double = {
            guard hit.kind == .note, normalizedQuery.isEmpty == false else { return 0.0 }
            let normalizedTitle = hit.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedContent = hit.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedTitle == normalizedQuery || normalizedContent == normalizedQuery {
                return 3.0
            }
            return normalizedTitle.contains(normalizedQuery) || normalizedContent.contains(normalizedQuery) ? 3.0 : 0.0
        }()
        let masteryScore = masteryLookup[hit.conceptID ?? ""] ?? masteryLookup[hit.noteID.uuidString] ?? 0.5
        let masteryBoost = hit.kind == .concept || hit.kind == .chunk ? (1.0 - masteryScore) * 0.1 : 0.0
        let normalizedSourceRelevance = hit.relevance / (abs(hit.relevance) + 1.0)
        copy.relevance = normalizedSourceRelevance + base + sourceBoost + relationshipBoost + kindBoost + queryBoost + exactNoteMatchBoost + masteryBoost
        return copy
    }

    private func merge(_ hits: [RetrievalHit], limit: Int) -> [RetrievalHit] {
        var bestByID: [String: RetrievalHit] = [:]
        for hit in hits {
            guard let existing = bestByID[hit.id] else {
                bestByID[hit.id] = hit
                continue
            }

            var merged = existing
            merged.relevance = max(existing.relevance, hit.relevance)
            merged.provenance = Array(Set(existing.provenance + hit.provenance)).sorted()
            merged.sources = mergeSources(existing.sources + hit.sources)
            merged.updatedAt = merged.updatedAt ?? hit.updatedAt
            merged.relationshipID = merged.relationshipID ?? hit.relationshipID
            if merged.noteTitle.isEmpty {
                merged.noteTitle = hit.noteTitle
            }
            if merged.snippet.isEmpty {
                merged.snippet = hit.snippet
            }
            if merged.content.isEmpty {
                merged.content = hit.content
            }
            bestByID[hit.id] = merged
        }

        return bestByID.values
            .sorted {
                if $0.relevance != $1.relevance { return $0.relevance > $1.relevance }
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    private func mergeSources(_ sources: [RetrievalSource]) -> [RetrievalSource] {
        var bestByID: [String: RetrievalSource] = [:]
        for source in sources {
            bestByID[source.id] = bestByID[source.id] ?? source
        }
        return bestByID.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
