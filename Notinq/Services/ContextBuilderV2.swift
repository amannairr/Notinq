import Foundation

final class ContextBuilderV2 {
    private let retriever: HybridRetriever
    private let repository: KnowledgeRepository
    private let studentConceptService: StudentConceptService
    private let studyRepository: StudyRepository
    private let graphExpansion: GraphExpansionService
    private let graphContextBuilder: GraphContextBuilder
    private let gapDetector: KnowledgeGapDetector

    init(
        retriever: HybridRetriever = .shared,
        repository: KnowledgeRepository = .shared,
        studentConceptService: StudentConceptService = .shared,
        studyRepository: StudyRepository = .shared,
        graphExpansion: GraphExpansionService? = nil,
        graphContextBuilder: GraphContextBuilder? = nil,
        gapDetector: KnowledgeGapDetector? = nil
    ) {
        self.retriever = retriever
        self.repository = repository
        self.studentConceptService = studentConceptService
        self.studyRepository = studyRepository
        self.graphExpansion = graphExpansion ?? GraphExpansionService(repository: repository)
        self.graphContextBuilder = graphContextBuilder ?? GraphContextBuilder(repository: repository)
        self.gapDetector = gapDetector ?? KnowledgeGapDetector(repository: repository)
    }

    func buildAdaptiveContext(
        question: String,
        noteID: UUID?
    ) async throws -> AdaptiveTutorContext {
        let hits = retriever.retrieve(query: question, limit: 24)
        let scopedHits = noteID.map { id in hits.filter { $0.noteID == id } } ?? hits
        let retrievedNotes = scopedHits.map(Self.retrievedChunk(from:))
        let seedConcepts = try seedConcepts(from: scopedHits, question: question)
        let expandedConcepts = graphExpansion.expand(question: question, seedConcepts: seedConcepts)
        let relationships = graphExpansion.relationships(for: expandedConcepts)
        let prerequisites = graphExpansion.prerequisites(for: expandedConcepts)
        let mastery = try masteryRecords(noteID: noteID)
        let gaps = gapDetector.detectGaps(
            concepts: dedupeConcepts(expandedConcepts + prerequisites),
            relationships: relationships,
            mastery: mastery
        )
        let graphContext = graphContextBuilder.buildContext(query: question, maxConcepts: 20)

        let weakConcepts = concepts(matching: mastery.filter { $0.effectiveMasteryScore < 0.5 }, within: expandedConcepts + prerequisites)
        let strongConcepts = concepts(matching: mastery.filter { $0.effectiveMasteryScore >= 0.8 }, within: expandedConcepts + prerequisites)
        let missingPrerequisites = dedupeConcepts(gaps.flatMap { gap in
            gap.missingPrerequisites.isEmpty ? [gap.concept] : gap.missingPrerequisites
        })

        let graphConcepts = graphContext.concepts.compactMap(concept(from:))

        return AdaptiveTutorContext(
            question: question,
            retrievedNotes: retrievedNotes,
            relevantConcepts: Array(expandedConcepts.prefix(20)),
            relationships: Array(relationships.prefix(64)),
            weakConcepts: weakConcepts,
            strongConcepts: strongConcepts,
            prerequisites: prerequisites,
            missingPrerequisites: missingPrerequisites,
            studyPlanRecommendations: studyPlanRecommendations(from: gaps, prerequisites: prerequisites),
            masteryMap: masteryMap(from: mastery),
            knowledgeGaps: gaps.map(\.concept),
            relatedConcepts: Array(dedupeConcepts(expandedConcepts + graphConcepts).prefix(20)),
            reviewHistory: noteID.flatMap { try? studyRepository.reviewEvents(for: $0) } ?? [],
            graphContext: graphContext
        )
    }

    private func seedConcepts(from hits: [RetrievalHit], question: String) throws -> [Concept] {
        var concepts: [Concept] = []
        var seen: Set<UUID> = []

        for hit in hits {
            if let conceptID = hit.conceptID,
               let record = try repository.concept(for: conceptID),
               let concept = concept(from: record),
               seen.insert(concept.id).inserted {
                concepts.append(concept)
            }
        }

        for searchRecord in try repository.searchConcepts(query: question, limit: 8) {
            guard let record = try repository.concept(for: searchRecord.conceptID),
                  let concept = concept(from: record),
                  seen.insert(concept.id).inserted else { continue }
            concepts.append(concept)
        }

        return concepts
    }

    private func masteryRecords(noteID: UUID?) throws -> [StudentConceptRecord] {
        if let noteID {
            return try studyRepository.studentConcepts(for: noteID)
        }
        let weak = (try? studentConceptService.weakestConcepts(limit: 12)) ?? []
        let strong = (try? studentConceptService.strongestConcepts(limit: 12)) ?? []
        let recent = (try? studentConceptService.recentlyReviewedConcepts(limit: 12)) ?? []
        return dedupeMastery(weak + strong + recent)
    }

    private static func retrievedChunk(from hit: RetrievalHit) -> RetrievedChunk {
        RetrievedChunk(
            id: hit.chunkID ?? hit.id,
            noteID: hit.noteID,
            noteTitle: hit.noteTitle,
            title: hit.title,
            content: hit.content,
            snippet: hit.snippet,
            sourceType: hit.result.sourceType,
            relevance: hit.relevance
        )
    }

    private func concepts(matching records: [StudentConceptRecord], within concepts: [Concept]) -> [Concept] {
        let byID = Dictionary(uniqueKeysWithValues: concepts.map { ($0.id, $0) })
        let byName = Dictionary(uniqueKeysWithValues: concepts.map { (normalizedKey($0.name), $0) })
        return dedupeConcepts(records.compactMap { record in
            if let id = UUID(uuidString: record.conceptID), let concept = byID[id] {
                return concept
            }
            return byName[normalizedKey(record.conceptID)]
        })
    }

    private func masteryMap(from records: [StudentConceptRecord]) -> [UUID: Double] {
        records.reduce(into: [:]) { result, record in
            guard let id = UUID(uuidString: record.conceptID) else { return }
            result[id] = record.effectiveMasteryScore
        }
    }

    private func studyPlanRecommendations(from gaps: [KnowledgeGap], prerequisites: [Concept]) -> [String] {
        var recommendations = gaps.prefix(5).map { gap in
            "Review \(gap.concept.name): \(gap.reason.lowercased())."
        }
        if recommendations.isEmpty {
            recommendations = prerequisites.prefix(5).map { "Review prerequisite: \($0.name)." }
        }
        return recommendations
    }

    private func dedupeConcepts(_ concepts: [Concept]) -> [Concept] {
        var seen: Set<UUID> = []
        return concepts.filter { seen.insert($0.id).inserted }
    }

    private func concept(from record: CanonicalConceptRecord) -> Concept? {
        Concept(
            id: stableUUID(for: record.id),
            name: record.canonicalName,
            description: record.description,
            aliases: record.aliases,
            noteID: record.sourceReferences.compactMap(UUID.init(uuidString:)).first ?? stableUUID(for: "note-\(record.id)"),
            confidence: record.confidence,
            createdDate: Date(),
            updatedDate: Date(),
            embeddingID: record.id,
            importanceScore: record.confidence,
            difficultyScore: 1.0 - record.confidence
        )
    }

    private func stableUUID(for value: String) -> UUID {
        if let uuid = UUID(uuidString: value) {
            return uuid
        }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let suffix = String(format: "%012llx", hash & 0x0000ffffffffffff)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)") ?? UUID()
    }

    private func dedupeMastery(_ records: [StudentConceptRecord]) -> [StudentConceptRecord] {
        var seen: Set<String> = []
        return records.filter { seen.insert($0.conceptID).inserted }
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}
