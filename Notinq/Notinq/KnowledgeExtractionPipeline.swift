import Foundation
import CryptoKit

enum KnowledgeProcessingStrategy: String, Codable, Sendable {
    case singlePass
    case mapReduce
    case hierarchical

    var maxTokens: Int32 {
        switch self {
        case .singlePass:
            return 512
        case .mapReduce:
            return 768
        case .hierarchical:
            return 1024
        }
    }

    var conceptLimit: Int {
        switch self {
        case .singlePass:
            return 18
        case .mapReduce:
            return 28
        case .hierarchical:
            return 36
        }
    }
}

struct KnowledgeExtractionResult: Sendable {
    var structuredKnowledge: StructuredKnowledge
    var canonicalExtraction: CanonicalExtractionPayload
    var snapshot: StudyKnowledgeSnapshot
    var strategy: KnowledgeProcessingStrategy
    var fromCache: Bool
    var structure: DocumentStructure
    var qualityMetrics: KnowledgeExtractionQualityMetrics
    var debugReport: KnowledgeExtractionDebugReport
}

struct KnowledgeExtractionRun: Sendable {
    var knowledge: StructuredKnowledge
    var canonicalExtraction: CanonicalExtractionPayload
    var structure: DocumentStructure
    var strategy: KnowledgeProcessingStrategy
    var fromCache: Bool
    var qualityMetrics: KnowledgeExtractionQualityMetrics
    var debugReport: KnowledgeExtractionDebugReport
}

final class KnowledgeExtractionEngine {
    static let shared = KnowledgeExtractionEngine()
    private static let extractionRevision = "knowledge-extraction-v4"

    private init() {}

    func extractKnowledge(noteTitle: String, noteText: String, notebookText: String = "") async -> StructuredKnowledge {
        await extractRun(noteTitle: noteTitle, noteText: noteText, notebookText: notebookText).knowledge
    }

    func extractKnowledge(from structure: DocumentStructure, notebookText: String = "") async -> StructuredKnowledge {
        await extractRun(from: structure, notebookText: notebookText).knowledge
    }

    func extractRun(noteTitle: String, noteText: String, notebookText: String = "") async -> KnowledgeExtractionRun {
        await chunkedExtractRun(noteTitle: noteTitle, noteText: noteText, notebookText: notebookText)
    }

    func extractRun(from structure: DocumentStructure, notebookText: String = "") async -> KnowledgeExtractionRun {
        await chunkedExtractRun(from: structure, notebookText: notebookText)
    }

    func inspectExtraction(from structure: DocumentStructure, notebookText: String = "") async -> KnowledgeExtractionDebugReport {
        await extractRun(from: structure, notebookText: notebookText).debugReport
    }

    private func chunkedExtractRun(noteTitle: String, noteText: String, notebookText: String) async -> KnowledgeExtractionRun {
        let structure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: noteText)
        let normalizedNoteText = structure.normalizedText
        let normalizedNotebookText = normalize(notebookText)
        let signature = signatureFor(noteTitle: noteTitle, noteText: normalizedNoteText, notebookText: normalizedNotebookText)
        let strategy = strategyFor(text: normalizedNoteText)
        let chunks = SemanticChunker.shared.chunk(
            title: noteTitle,
            structure: structure,
            contextLimit: Int(AIRuntimeConfig.current.llama.contextSize)
        )

        if let cached = KnowledgeExtractionCache.shared.cachedKnowledge(for: signature) {
            let validation = KnowledgeValidator.validate(payload: cached, structure: structure)
            let chunkRuns = buildCachedChunkReports(
                chunks: chunks,
                noteTitle: noteTitle,
                cachedKnowledge: cached,
                signature: signature,
                notebookText: normalizedNotebookText,
                strategy: strategy
            )
            let qualityMetrics = buildQualityMetrics(
                knowledge: cached,
                structure: structure,
                validation: validation,
                noiseSamples: noiseSamples(in: normalizedNoteText)
            )
            return KnowledgeExtractionRun(
                knowledge: cached,
                canonicalExtraction: cached.canonicalExtractionPayload(sourceReferences: sourceReferences(for: chunks, sourceSignature: signature)),
                structure: structure,
                strategy: strategyFor(text: normalizedNoteText),
                fromCache: true,
                qualityMetrics: qualityMetrics,
                debugReport: buildDebugReport(
                    noteTitle: noteTitle,
                    sourceSignature: signature,
                    strategy: strategyFor(text: normalizedNoteText),
                    fromCache: true,
                    knowledge: cached,
                    validation: validation,
                    metrics: qualityMetrics,
                    noiseSamples: noiseSamples(in: normalizedNoteText)
                ).updating(
                    chunkRuns: chunkRuns,
                    mergedKnowledge: cached,
                    validationWarnings: validation.issues.map { "\($0.field): \($0.message)" },
                    latency: 0,
                    retryCount: 0,
                    tokenCount: chunkRuns.reduce(0) { $0 + $1.tokenCount }
                )
            )
        }

        var knowledge = StructuredKnowledge()
        var chunkRuns: [KnowledgeExtractionChunkDebug] = []
        var totalLatency: TimeInterval = 0
        var totalTokens = 0
        var totalRetries = 0

        for chunk in chunks {
            let chunkStructure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: chunk.content)
            let heuristic = buildHeuristicKnowledge(
                noteTitle: noteTitle,
                structure: chunkStructure,
                notebookText: normalizedNotebookText,
                sourceSignature: "\(signature)#chunk-\(chunk.chunkIndex)",
                strategy: strategy
            )

            let chunkResult = await extractChunk(
                chunk: chunk,
                noteTitle: noteTitle,
                structure: chunkStructure,
                heuristic: heuristic,
                strategy: strategy
            )

            knowledge = mergeChunkKnowledge(knowledge, with: chunkResult.mergedKnowledge)
            chunkRuns.append(chunkResult.debug)
            totalLatency += chunkResult.debug.latency
            totalTokens += chunkResult.debug.tokenCount
            totalRetries += chunkResult.debug.retryCount
        }

        let globalRelationships = buildRelationships(
            concepts: knowledge.concepts,
            sentences: splitSentences(normalizedNoteText),
            sourceSignature: signature
        )
        if !globalRelationships.isEmpty {
            knowledge.relationships = mergeRelationships(knowledge.relationships + globalRelationships)
        }
        if knowledge.relationships.isEmpty && knowledge.concepts.count >= 2 {
            let sentences = splitSentences(normalizedNoteText)
            var fallbackRelationships: [KnowledgeRelationship] = []
            for (index, sentence) in sentences.enumerated() {
                let lower = sentence.lowercased()
                let matchedConcepts = knowledge.concepts.filter { concept in
                    ([concept.name] + concept.aliases).contains(where: { lower.contains($0.lowercased()) })
                }
                guard matchedConcepts.count >= 2 else { continue }
                let ordered = matchedConcepts.sorted {
                    let lhsRange = lower.range(of: $0.name.lowercased())?.lowerBound ?? lower.startIndex
                    let rhsRange = lower.range(of: $1.name.lowercased())?.lowerBound ?? lower.startIndex
                    return lhsRange < rhsRange
                }
                let source = ordered[0]
                let target = ordered[1]
                fallbackRelationships.append(
                    KnowledgeRelationship(
                        sourceID: source.id,
                        targetID: target.id,
                        relationKind: .relatedTo,
                        relation: KnowledgeRelationshipKind.relatedTo.rawValue,
                        sourceLocations: [
                            KnowledgeSourceLocation(
                                sectionID: knowledge.sourceLocations.first?.sectionID ?? signature,
                                sectionTitle: source.name,
                                lineStart: index + 1,
                                lineEnd: index + 1,
                                order: index,
                                snippet: sentence
                            )
                        ],
                        confidence: 0.45
                    )
                )
            }
            if !fallbackRelationships.isEmpty {
                knowledge.relationships = mergeRelationships(fallbackRelationships)
            }
        }
        knowledge.metadata.noteID = knowledge.metadata.noteID.isEmpty ? signature : knowledge.metadata.noteID
        knowledge.metadata.title = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        knowledge.metadata.approximateTokenCount = structure.complexity.tokenEstimate
        knowledge.metadata.sectionCount = structure.sections.count
        knowledge.metadata.sourceSignature = signature
        knowledge.title = knowledge.title.isEmpty ? noteTitle.trimmingCharacters(in: .whitespacesAndNewlines) : knowledge.title
        if knowledge.topics.isEmpty {
            knowledge.topics = extractTopics(from: noteTitle, text: normalizedNoteText)
        }
        knowledge = KnowledgeValidator.normalize(payload: knowledge)
        KnowledgeExtractionCache.shared.store(knowledge, for: signature)

        let finalValidation = KnowledgeValidator.validate(payload: knowledge, structure: structure)
        let qualityMetrics = buildQualityMetrics(
            knowledge: knowledge,
            structure: structure,
            validation: finalValidation,
            noiseSamples: noiseSamples(in: normalizedNoteText)
        )
        let debugReport = buildDebugReport(
            noteTitle: noteTitle,
            sourceSignature: signature,
            strategy: strategy,
            fromCache: false,
            knowledge: knowledge,
            validation: finalValidation,
            metrics: qualityMetrics,
            noiseSamples: noiseSamples(in: normalizedNoteText)
        ).updating(
            chunkRuns: chunkRuns,
            mergedKnowledge: knowledge,
            validationWarnings: finalValidation.issues.map { "\($0.field): \($0.message)" },
            latency: totalLatency,
            retryCount: totalRetries,
            tokenCount: totalTokens
        )

        return KnowledgeExtractionRun(
            knowledge: knowledge,
            canonicalExtraction: knowledge.canonicalExtractionPayload(sourceReferences: sourceReferences(for: chunks, sourceSignature: signature)),
            structure: structure,
            strategy: strategy,
            fromCache: false,
            qualityMetrics: qualityMetrics,
            debugReport: debugReport
        )
    }

    private func chunkedExtractRun(from structure: DocumentStructure, notebookText: String) async -> KnowledgeExtractionRun {
        let normalizedNoteText = structure.normalizedText
        let normalizedNotebookText = normalize(notebookText)
        let signature = signatureFor(noteTitle: structure.title, noteText: normalizedNoteText, notebookText: normalizedNotebookText)
        let strategy = strategyFor(text: normalizedNoteText)
        let chunks = SemanticChunker.shared.chunk(
            title: structure.title,
            structure: structure,
            contextLimit: Int(AIRuntimeConfig.current.llama.contextSize)
        )

        if let cached = KnowledgeExtractionCache.shared.cachedKnowledge(for: signature) {
            let validation = KnowledgeValidator.validate(payload: cached, structure: structure)
            let chunkRuns = buildCachedChunkReports(
                chunks: chunks,
                noteTitle: structure.title,
                cachedKnowledge: cached,
                signature: signature,
                notebookText: normalizedNotebookText,
                strategy: strategy
            )
            let qualityMetrics = buildQualityMetrics(
                knowledge: cached,
                structure: structure,
                validation: validation,
                noiseSamples: noiseSamples(in: normalizedNoteText)
            )
            return KnowledgeExtractionRun(
                knowledge: cached,
                canonicalExtraction: cached.canonicalExtractionPayload(sourceReferences: sourceReferences(for: chunks, sourceSignature: signature)),
                structure: structure,
                strategy: strategyFor(text: normalizedNoteText),
                fromCache: true,
                qualityMetrics: qualityMetrics,
                debugReport: buildDebugReport(
                    noteTitle: structure.title,
                    sourceSignature: signature,
                    strategy: strategyFor(text: normalizedNoteText),
                    fromCache: true,
                    knowledge: cached,
                    validation: validation,
                    metrics: qualityMetrics,
                    noiseSamples: noiseSamples(in: normalizedNoteText)
                ).updating(
                    chunkRuns: chunkRuns,
                    mergedKnowledge: cached,
                    validationWarnings: validation.issues.map { "\($0.field): \($0.message)" },
                    latency: 0,
                    retryCount: 0,
                    tokenCount: chunkRuns.reduce(0) { $0 + $1.tokenCount }
                )
            )
        }

        var knowledge = StructuredKnowledge()
        var chunkRuns: [KnowledgeExtractionChunkDebug] = []
        var totalLatency: TimeInterval = 0
        var totalTokens = 0
        var totalRetries = 0

        for chunk in chunks {
            let chunkStructure = DocumentPreprocessor.shared.preprocess(title: structure.title, text: chunk.content)
            let heuristic = buildHeuristicKnowledge(
                noteTitle: structure.title,
                structure: chunkStructure,
                notebookText: normalizedNotebookText,
                sourceSignature: "\(signature)#chunk-\(chunk.chunkIndex)",
                strategy: strategy
            )

            let chunkResult = await extractChunk(
                chunk: chunk,
                noteTitle: structure.title,
                structure: chunkStructure,
                heuristic: heuristic,
                strategy: strategy
            )

            knowledge = mergeChunkKnowledge(knowledge, with: chunkResult.mergedKnowledge)
            chunkRuns.append(chunkResult.debug)
            totalLatency += chunkResult.debug.latency
            totalTokens += chunkResult.debug.tokenCount
            totalRetries += chunkResult.debug.retryCount
        }

        let globalRelationships = buildRelationships(
            concepts: knowledge.concepts,
            sentences: splitSentences(normalizedNoteText),
            sourceSignature: signature
        )
        if !globalRelationships.isEmpty {
            knowledge.relationships = mergeRelationships(knowledge.relationships + globalRelationships)
        }
        if knowledge.relationships.isEmpty && knowledge.concepts.count >= 2 {
            let sentences = splitSentences(normalizedNoteText)
            var fallbackRelationships: [KnowledgeRelationship] = []
            for (index, sentence) in sentences.enumerated() {
                let lower = sentence.lowercased()
                let matchedConcepts = knowledge.concepts.filter { concept in
                    ([concept.name] + concept.aliases).contains(where: { lower.contains($0.lowercased()) })
                }
                guard matchedConcepts.count >= 2 else { continue }
                let ordered = matchedConcepts.sorted {
                    let lhsRange = lower.range(of: $0.name.lowercased())?.lowerBound ?? lower.startIndex
                    let rhsRange = lower.range(of: $1.name.lowercased())?.lowerBound ?? lower.startIndex
                    return lhsRange < rhsRange
                }
                let source = ordered[0]
                let target = ordered[1]
                fallbackRelationships.append(
                    KnowledgeRelationship(
                        sourceID: source.id,
                        targetID: target.id,
                        relationKind: .relatedTo,
                        relation: KnowledgeRelationshipKind.relatedTo.rawValue,
                        sourceLocations: [
                            KnowledgeSourceLocation(
                                sectionID: knowledge.sourceLocations.first?.sectionID ?? signature,
                                sectionTitle: source.name,
                                lineStart: index + 1,
                                lineEnd: index + 1,
                                order: index,
                                snippet: sentence
                            )
                        ],
                        confidence: 0.45
                    )
                )
            }
            if !fallbackRelationships.isEmpty {
                knowledge.relationships = mergeRelationships(fallbackRelationships)
            }
        }
        knowledge.metadata.noteID = knowledge.metadata.noteID.isEmpty ? signature : knowledge.metadata.noteID
        knowledge.metadata.title = structure.title.trimmingCharacters(in: .whitespacesAndNewlines)
        knowledge.metadata.approximateTokenCount = structure.complexity.tokenEstimate
        knowledge.metadata.sectionCount = structure.sections.count
        knowledge.metadata.sourceSignature = signature
        knowledge.title = knowledge.title.isEmpty ? structure.title.trimmingCharacters(in: .whitespacesAndNewlines) : knowledge.title
        if knowledge.topics.isEmpty {
            knowledge.topics = extractTopics(from: structure.title, text: normalizedNoteText)
        }
        knowledge = KnowledgeValidator.normalize(payload: knowledge)
        KnowledgeExtractionCache.shared.store(knowledge, for: signature)

        let finalValidation = KnowledgeValidator.validate(payload: knowledge, structure: structure)
        let qualityMetrics = buildQualityMetrics(
            knowledge: knowledge,
            structure: structure,
            validation: finalValidation,
            noiseSamples: noiseSamples(in: normalizedNoteText)
        )
        let debugReport = buildDebugReport(
            noteTitle: structure.title,
            sourceSignature: signature,
            strategy: strategy,
            fromCache: false,
            knowledge: knowledge,
            validation: finalValidation,
            metrics: qualityMetrics,
            noiseSamples: noiseSamples(in: normalizedNoteText)
        ).updating(
            chunkRuns: chunkRuns,
            mergedKnowledge: knowledge,
            validationWarnings: finalValidation.issues.map { "\($0.field): \($0.message)" },
            latency: totalLatency,
            retryCount: totalRetries,
            tokenCount: totalTokens
        )

        return KnowledgeExtractionRun(
            knowledge: knowledge,
            canonicalExtraction: knowledge.canonicalExtractionPayload(sourceReferences: sourceReferences(for: chunks, sourceSignature: signature)),
            structure: structure,
            strategy: strategy,
            fromCache: false,
            qualityMetrics: qualityMetrics,
            debugReport: debugReport
        )
    }

    func normalizedSignature(noteTitle: String, noteText: String, notebookText: String = "") -> String {
        signatureFor(noteTitle: noteTitle, noteText: normalize(noteText), notebookText: normalize(notebookText))
    }

    func clearCache() {
        KnowledgeExtractionCache.shared.clear()
    }

    func inspectExtraction(noteTitle: String, noteText: String, notebookText: String = "") async -> KnowledgeExtractionDebugReport {
        await extractRun(noteTitle: noteTitle, noteText: noteText, notebookText: notebookText).debugReport
    }

    private struct ChunkExtractionResult {
        var mergedKnowledge: StructuredKnowledge
        var canonicalExtraction: CanonicalExtractionPayload
        var debug: KnowledgeExtractionChunkDebug
    }

    private func extractChunk(
        chunk: SemanticChunk,
        noteTitle: String,
        structure: DocumentStructure,
        heuristic: StructuredKnowledge,
        strategy: KnowledgeProcessingStrategy
    ) async -> ChunkExtractionResult {
        let context = AIPromptContext(
            noteTitle: noteTitle,
            noteText: chunk.content,
            knowledgeJSON: nil,
            selectedText: nil,
            userRequest: nil
        )
        let request = PromptRegistry.shared.jsonRequest(for: .knowledgeExtraction, context: context, maxTokens: strategy.maxTokens)

        var merged = heuristic
        var rawResponse = ""
        var parsedJSON = ""
        var retryCount = 0
        var tokenCount = max(1, chunk.content.split { $0.isWhitespace || $0.isNewline }.count)
        var latency: TimeInterval = 0
        var validationWarnings: [String] = []
        let sourceReferences = sourceReferences(for: [chunk], sourceSignature: structure.sourceSignature)
        let heuristicCanonical = heuristic.canonicalExtractionPayload(sourceReferences: sourceReferences)
        let normalizedHeuristicCanonical = ExtractionValidator.normalize(payload: heuristicCanonical)
        let normalizedHeuristicLegacy = KnowledgeValidator.normalize(
            payload: StructuredKnowledge.fromCanonicalExtraction(
                normalizedHeuristicCanonical,
                title: noteTitle,
                sourceSignature: structure.sourceSignature,
                sourceType: strategy.rawValue,
                approximateTokenCount: structure.complexity.tokenEstimate,
                sectionCount: structure.sections.count,
                difficulty: heuristic.difficulty,
                keywords: heuristic.keywords,
                summaryHighlights: heuristic.summaryHighlights,
                examFocus: heuristic.examFocus,
                supportingEvidence: heuristic.supportingEvidence
            )
        )

        guard shouldUseProvider(for: chunk.content) else {
            return ChunkExtractionResult(
                mergedKnowledge: normalizedHeuristicLegacy,
                canonicalExtraction: normalizedHeuristicCanonical,
                debug: KnowledgeExtractionChunkDebug(
                    documentID: chunk.documentID,
                    chunkIndex: chunk.chunkIndex,
                    sectionName: chunk.sectionName,
                    paragraphIDs: chunk.paragraphIDs,
                    rawChunk: chunk.content,
                    prompt: request.prompt,
                    rawModelResponse: rawResponse,
                    parsedJSON: parsedJSON,
                    mergedKnowledge: normalizedHeuristicLegacy,
                    validationWarnings: validationWarnings,
                    latency: latency,
                    retryCount: retryCount,
                    tokenCount: tokenCount
                )
            )
        }

        do {
            let started = Date()
            let response = try await InferenceEngine.shared.generate(request)
            rawResponse = response.text
            latency = response.metrics?.generationTime ?? Date().timeIntervalSince(started)
            tokenCount = max(tokenCount, Int(response.metrics?.tokensPerSecond ?? 0 * max(response.metrics?.generationTime ?? 1, 0.0001)))

            let repaired = PromptRepairer.repairJSONString(rawResponse) ?? rawResponse
            parsedJSON = repaired
            if let data = repaired.data(using: .utf8),
               let payload = try? JSONDecoder().decode(CanonicalExtractionPayload.self, from: data) {
                let normalizedCanonical = ExtractionValidator.normalize(payload: payload)
                let validation = ExtractionValidator.validate(payload: normalizedCanonical)
                validationWarnings = validation.issues.map { "\($0.field): \($0.message)" }
                retryCount = validation.isValid ? 0 : 1
                let legacyPayload = StructuredKnowledge.fromCanonicalExtraction(
                    normalizedCanonical,
                    title: noteTitle,
                    sourceSignature: structure.sourceSignature,
                    sourceType: strategy.rawValue,
                    approximateTokenCount: structure.complexity.tokenEstimate,
                    sectionCount: structure.sections.count,
                    difficulty: heuristic.difficulty,
                    keywords: heuristic.keywords,
                    summaryHighlights: heuristic.summaryHighlights,
                    examFocus: heuristic.examFocus,
                    supportingEvidence: heuristic.supportingEvidence
                )
                merged = merge(payload: KnowledgeValidator.normalize(payload: legacyPayload), with: heuristic)

                if !validation.isValid {
                    let retryRequest = AIGenerationRequest(
                        prompt: request.prompt + "\n\n" + ExtractionValidator.buildRetryPrompt(for: validation),
                        systemPrompt: request.systemPrompt,
                        maxTokens: request.maxTokens,
                        temperature: 0.0,
                        topP: request.topP,
                        responseFormat: .json,
                        contextLimit: request.contextLimit,
                        metadata: request.metadata
                    )
                    if let retryResponse = try? await InferenceEngine.shared.generate(retryRequest) {
                        rawResponse = retryResponse.text
                        let retryRepaired = PromptRepairer.repairJSONString(rawResponse) ?? rawResponse
                        parsedJSON = retryRepaired
                        if let retryData = retryRepaired.data(using: .utf8),
                           let retryPayload = try? JSONDecoder().decode(CanonicalExtractionPayload.self, from: retryData) {
                            let normalizedRetry = ExtractionValidator.normalize(payload: retryPayload)
                            let retryLegacy = StructuredKnowledge.fromCanonicalExtraction(
                                normalizedRetry,
                                title: noteTitle,
                                sourceSignature: structure.sourceSignature,
                                sourceType: strategy.rawValue,
                                approximateTokenCount: structure.complexity.tokenEstimate,
                                sectionCount: structure.sections.count,
                                difficulty: heuristic.difficulty,
                                keywords: heuristic.keywords,
                                summaryHighlights: heuristic.summaryHighlights,
                                examFocus: heuristic.examFocus,
                                supportingEvidence: heuristic.supportingEvidence
                            )
                            merged = merge(payload: KnowledgeValidator.normalize(payload: retryLegacy), with: heuristic)
                            retryCount += 1
                        }
                        latency += retryResponse.metrics?.generationTime ?? 0
                        tokenCount += max(1, Int((retryResponse.metrics?.tokensPerSecond ?? 0) * max(retryResponse.metrics?.generationTime ?? 0, 0.0001)))
                    }
                }
            } else {
                validationWarnings = ["parsed_json: Could not decode chunk response into CanonicalExtractionPayload"]
                if let data = parsedJSON.data(using: .utf8),
                   let legacyPayload = try? JSONDecoder().decode(StructuredKnowledge.self, from: data) {
                    let normalizedLegacy = KnowledgeValidator.normalize(payload: legacyPayload)
                    merged = merge(payload: normalizedLegacy, with: heuristic)
                }
            }
        } catch {
            validationWarnings = ["provider_error: \(error.localizedDescription)"]
        }

        let normalizedMerged = KnowledgeValidator.normalize(payload: merged)
        return ChunkExtractionResult(
            mergedKnowledge: normalizedMerged,
            canonicalExtraction: ExtractionValidator.normalize(
                payload: normalizedMerged.canonicalExtractionPayload(sourceReferences: sourceReferences)
            ),
            debug: KnowledgeExtractionChunkDebug(
                documentID: chunk.documentID,
                chunkIndex: chunk.chunkIndex,
                sectionName: chunk.sectionName,
                paragraphIDs: chunk.paragraphIDs,
                rawChunk: chunk.content,
                prompt: request.prompt,
                rawModelResponse: rawResponse,
                parsedJSON: parsedJSON,
                mergedKnowledge: normalizedMerged,
                validationWarnings: validationWarnings,
                latency: latency,
                retryCount: retryCount,
                tokenCount: tokenCount
            )
        )
    }

    private func buildCachedChunkReports(
        chunks: [SemanticChunk],
        noteTitle: String,
        cachedKnowledge: StructuredKnowledge,
        signature: String,
        notebookText: String,
        strategy: KnowledgeProcessingStrategy
    ) -> [KnowledgeExtractionChunkDebug] {
        chunks.map { chunk in
            let chunkStructure = DocumentPreprocessor.shared.preprocess(title: noteTitle, text: chunk.content)
            let heuristic = buildHeuristicKnowledge(
                noteTitle: noteTitle,
                structure: chunkStructure,
                notebookText: notebookText,
                sourceSignature: "\(signature)#chunk-\(chunk.chunkIndex)",
                strategy: strategy
            )
            let merged = mergeChunkKnowledge(heuristic, with: cachedKnowledge)
            return KnowledgeExtractionChunkDebug(
                documentID: chunk.documentID,
                chunkIndex: chunk.chunkIndex,
                sectionName: chunk.sectionName,
                paragraphIDs: chunk.paragraphIDs,
                rawChunk: chunk.content,
                prompt: "",
                rawModelResponse: "",
                parsedJSON: "",
                mergedKnowledge: KnowledgeValidator.normalize(payload: merged),
                validationWarnings: [],
                latency: 0,
                retryCount: 0,
                tokenCount: max(1, chunk.content.split { $0.isWhitespace || $0.isNewline }.count)
            )
        }
    }

    private func mergeChunkKnowledge(_ left: StructuredKnowledge, with right: StructuredKnowledge) -> StructuredKnowledge {
        if left == StructuredKnowledge() { return right }
        if right == StructuredKnowledge() { return left }

        var merged = left
        merged.metadata = merge(metadata: left.metadata, with: right.metadata)
        merged.title = right.title.isEmpty ? left.title : right.title
        merged.topics = dedupeStrings(left.topics + right.topics)
        merged.sections = mergeSections(left.sections + right.sections)
        merged.concepts = mergeConcepts(left.concepts + right.concepts)
        merged.definitions = mergeDefinitions(left.definitions + right.definitions)
        merged.examples = mergeExamples(left.examples + right.examples)
        merged.processes = mergeProcesses(left.processes + right.processes)
        merged.relationships = mergeRelationships(left.relationships + right.relationships)
        merged.learningObjectives = mergeObjectives(left.learningObjectives + right.learningObjectives)
        merged.actionItems = mergeActionItems(left.actionItems + right.actionItems)
        merged.keywords = dedupeStrings(left.keywords + right.keywords)
        merged.confidence = max(left.confidence, right.confidence)
        merged.sourceLocations = mergeSourceLocations(left.sourceLocations + right.sourceLocations)
        merged.difficulty = right.difficulty
        merged.importance = max(left.importance, right.importance)
        merged.aliases = dedupeStrings(left.aliases + right.aliases)
        merged.procedures = dedupeStrings(left.procedures + right.procedures)
        merged.formulas = dedupeStrings(left.formulas + right.formulas)
        merged.importantFacts = dedupeStrings(left.importantFacts + right.importantFacts)
        merged.keyTerminology = dedupeStrings(left.keyTerminology + right.keyTerminology)
        merged.misconceptions = dedupeStrings(left.misconceptions + right.misconceptions)
        merged.prerequisites = dedupeStrings(left.prerequisites + right.prerequisites)
        merged.hierarchy = mergeSections(left.hierarchy + right.hierarchy)
        merged.supportingEvidence = dedupeStrings(left.supportingEvidence + right.supportingEvidence)
        merged.summaryHighlights = dedupeStrings(left.summaryHighlights + right.summaryHighlights)
        merged.examFocus = dedupeStrings(left.examFocus + right.examFocus)
        return KnowledgeValidator.normalize(payload: merged)
    }

    private func mergeSections(_ sections: [KnowledgeSection]) -> [KnowledgeSection] {
        var byKey: [String: KnowledgeSection] = [:]
        for section in sections {
            let key = normalizeConceptKey(section.title.isEmpty ? section.content : section.title)
            if let existing = byKey[key] {
                byKey[key] = mergeSection(existing, with: section)
            } else {
                byKey[key] = section
            }
        }
        return Array(byKey.values).sorted { $0.order < $1.order }
    }

    private func mergeSection(_ left: KnowledgeSection, with right: KnowledgeSection) -> KnowledgeSection {
        var merged = left
        if merged.title.isEmpty { merged.title = right.title }
        if merged.content.isEmpty { merged.content = right.content }
        merged.kind = merged.kind == .custom ? right.kind : merged.kind
        merged.order = min(merged.order, right.order)
        merged.children = mergeSections(left.children + right.children)
        merged.sourceLocations = mergeSourceLocations(left.sourceLocations + right.sourceLocations)
        return merged
    }

    private func mergeConcepts(_ concepts: [KnowledgeConcept]) -> [KnowledgeConcept] {
        var byKey: [String: KnowledgeConcept] = [:]
        for concept in concepts {
            let key = canonicalConceptKey(concept)
            if let existing = byKey[key] {
                byKey[key] = mergeConcept(existing, with: concept)
            } else {
                byKey[key] = concept
            }
        }
        return Array(byKey.values).sorted { $0.importance > $1.importance }
    }

    private func mergeConcept(_ left: KnowledgeConcept, with right: KnowledgeConcept) -> KnowledgeConcept {
        var merged = left
        if merged.name.isEmpty { merged.name = right.name }
        if merged.definition.count < right.definition.count { merged.definition = right.definition }
        merged.aliases = dedupeStrings(left.aliases + right.aliases)
        merged.relationships = dedupeStrings(left.relationships + right.relationships)
        merged.examples = dedupeStrings(left.examples + right.examples)
        merged.sourceLocations = mergeSourceLocations(left.sourceLocations + right.sourceLocations)
        merged.importance = max(left.importance, right.importance)
        merged.difficulty = max(left.difficulty, right.difficulty)
        merged.confidence = max(left.confidence, right.confidence)
        if merged.section.isEmpty { merged.section = right.section }
        if merged.source.isEmpty { merged.source = right.source }
        if merged.learningObjective.isEmpty { merged.learningObjective = right.learningObjective }
        merged.definitionEvidence = dedupeStrings(left.definitionEvidence + right.definitionEvidence)
        merged.aliasEvidence = dedupeStrings(left.aliasEvidence + right.aliasEvidence)
        if merged.sourceExcerpt.isEmpty { merged.sourceExcerpt = right.sourceExcerpt }
        return merged
    }

    private func mergeDefinitions(_ definitions: [KnowledgeDefinition]) -> [KnowledgeDefinition] {
        var byKey: [String: KnowledgeDefinition] = [:]
        for definition in definitions {
            let key = normalizeConceptKey(definition.term)
            if let existing = byKey[key] {
                byKey[key] = mergeDefinition(existing, with: definition)
            } else {
                byKey[key] = definition
            }
        }
        return Array(byKey.values)
    }

    private func mergeDefinition(_ left: KnowledgeDefinition, with right: KnowledgeDefinition) -> KnowledgeDefinition {
        var merged = left
        if merged.definition.count < right.definition.count { merged.definition = right.definition }
        merged.aliases = dedupeStrings(left.aliases + right.aliases)
        merged.sourceLocations = mergeSourceLocations(left.sourceLocations + right.sourceLocations)
        merged.confidence = max(left.confidence, right.confidence)
        return merged
    }

    private func mergeExamples(_ examples: [KnowledgeExample]) -> [KnowledgeExample] {
        var byKey: [String: KnowledgeExample] = [:]
        for example in examples {
            let key = normalizeConceptKey(example.conceptID + " " + example.example)
            if let existing = byKey[key] {
                byKey[key] = mergeExample(existing, with: example)
            } else {
                byKey[key] = example
            }
        }
        return Array(byKey.values)
    }

    private func mergeExample(_ left: KnowledgeExample, with right: KnowledgeExample) -> KnowledgeExample {
        var merged = left
        if merged.example.count < right.example.count { merged.example = right.example }
        merged.sourceLocations = mergeSourceLocations(left.sourceLocations + right.sourceLocations)
        merged.confidence = max(left.confidence, right.confidence)
        return merged
    }

    private func mergeProcesses(_ processes: [KnowledgeProcess]) -> [KnowledgeProcess] {
        var byKey: [String: KnowledgeProcess] = [:]
        for process in processes {
            let key = normalizeConceptKey(process.title)
            if let existing = byKey[key] {
                byKey[key] = mergeProcess(existing, with: process)
            } else {
                byKey[key] = process
            }
        }
        return Array(byKey.values)
    }

    private func mergeProcess(_ left: KnowledgeProcess, with right: KnowledgeProcess) -> KnowledgeProcess {
        var merged = left
        merged.steps = dedupeStrings(left.steps + right.steps)
        merged.sourceLocations = mergeSourceLocations(left.sourceLocations + right.sourceLocations)
        merged.confidence = max(left.confidence, right.confidence)
        return merged
    }

    private func mergeRelationships(_ relationships: [KnowledgeRelationship]) -> [KnowledgeRelationship] {
        var byKey: [String: KnowledgeRelationship] = [:]
        for relationship in relationships {
            let key = normalizeConceptKey("\(relationship.sourceID)|\(relationship.targetID)|\(relationship.relation)")
            if let existing = byKey[key] {
                byKey[key] = mergeRelationship(existing, with: relationship)
            } else {
                byKey[key] = relationship
            }
        }
        return Array(byKey.values)
    }

    private func mergeRelationship(_ left: KnowledgeRelationship, with right: KnowledgeRelationship) -> KnowledgeRelationship {
        var merged = left
        merged.sourceLocations = mergeSourceLocations(left.sourceLocations + right.sourceLocations)
        merged.confidence = max(left.confidence, right.confidence)
        return merged
    }

    private func mergeObjectives(_ objectives: [KnowledgeObjective]) -> [KnowledgeObjective] {
        var byKey: [String: KnowledgeObjective] = [:]
        for objective in objectives {
            let key = normalizeConceptKey(objective.objective)
            if let existing = byKey[key] {
                byKey[key] = mergeObjective(existing, with: objective)
            } else {
                byKey[key] = objective
            }
        }
        return Array(byKey.values)
    }

    private func mergeObjective(_ left: KnowledgeObjective, with right: KnowledgeObjective) -> KnowledgeObjective {
        var merged = left
        merged.relatedConceptIDs = dedupeStrings(left.relatedConceptIDs + right.relatedConceptIDs)
        merged.sourceLocations = mergeSourceLocations(left.sourceLocations + right.sourceLocations)
        merged.confidence = max(left.confidence, right.confidence)
        return merged
    }

    private func mergeActionItems(_ items: [KnowledgeActionItem]) -> [KnowledgeActionItem] {
        var byKey: [String: KnowledgeActionItem] = [:]
        for item in items {
            let key = normalizeConceptKey(item.title + " " + item.details)
            if let existing = byKey[key] {
                byKey[key] = mergeActionItem(existing, with: item)
            } else {
                byKey[key] = item
            }
        }
        return Array(byKey.values)
    }

    private func mergeActionItem(_ left: KnowledgeActionItem, with right: KnowledgeActionItem) -> KnowledgeActionItem {
        var merged = left
        if merged.details.count < right.details.count { merged.details = right.details }
        merged.sourceLocations = mergeSourceLocations(left.sourceLocations + right.sourceLocations)
        merged.confidence = max(left.confidence, right.confidence)
        return merged
    }

    private func mergeSourceLocations(_ locations: [KnowledgeSourceLocation]) -> [KnowledgeSourceLocation] {
        var seen = Set<String>()
        return locations.filter { location in
            let key = normalizeConceptKey("\(location.sectionID)|\(location.sectionTitle)|\(location.lineStart)|\(location.lineEnd)|\(location.snippet)")
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func canonicalConceptKey(_ concept: KnowledgeConcept) -> String {
        let candidate = concept.id.isEmpty ? concept.name : concept.id
        return normalizeConceptKey(candidate)
    }

    private func shouldUseProvider(for text: String) -> Bool {
        tokenEstimate(for: text) > 240 || text.count > 1_000
    }

    private func strategyFor(text: String) -> KnowledgeProcessingStrategy {
        let tokens = tokenEstimate(for: text)
        if tokens < 240 {
            return .singlePass
        }
        if tokens < 900 {
            return .mapReduce
        }
        return .hierarchical
    }

    private func buildHeuristicKnowledge(
        noteTitle: String,
        structure: DocumentStructure,
        notebookText: String,
        sourceSignature: String,
        strategy: KnowledgeProcessingStrategy
    ) -> StructuredKnowledge {
        let cleanedText = structure.cleanedText
        let sentences = splitSentences(cleanedText)
        let sectionLocations = structure.sections.enumerated().map { index, section in
            KnowledgeSourceLocation(
                sectionID: sourceSignature,
                sectionTitle: section.title.isEmpty ? section.content : section.title,
                lineStart: section.startLine + 1,
                lineEnd: section.endLine + 1,
                order: index,
                snippet: section.content
            )
        }

        let sections = structure.sections.enumerated().map { index, section in
            KnowledgeSection(
                title: section.title.isEmpty ? section.content : section.title,
                kind: mapSectionKind(section.kind),
                order: index,
                content: section.content,
                children: [],
                sourceLocations: [sectionLocations[index]]
            )
        }

        let headings = structure.headings.isEmpty
            ? cleanedText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { isLikelyHeading($0) }
            : structure.headings

        let topicCandidates = extractTopics(from: noteTitle, text: cleanedText)
        let conceptStrings = extractConcepts(from: cleanedText, limit: strategy.conceptLimit)
        let notebookConcepts = Set(extractConcepts(from: notebookText, limit: 18).map(normalizeConceptKey))
        let conceptCounts = frequencyMap(for: cleanedText)

        func conceptLocations(for concept: String) -> [KnowledgeSourceLocation] {
            let matches = sentences.enumerated().compactMap { index, sentence -> KnowledgeSourceLocation? in
                guard sentenceMatchesConcept(sentence, concept: concept, aliases: []) else { return nil }
                return KnowledgeSourceLocation(
                    sectionID: sourceSignature,
                    sectionTitle: sections.first?.title ?? noteTitle,
                    lineStart: index + 1,
                    lineEnd: index + 1,
                    order: index,
                    snippet: sentence
                )
            }
            return matches.isEmpty ? sectionLocations.prefix(1).map { $0 } : matches
        }

        func importance(for concept: String) -> Double {
            let normalized = normalizeConceptKey(concept)
            let frequency = Double(conceptCounts[normalized, default: 0])
            let headingBoost = headings.contains(where: { normalizeConceptKey($0).contains(normalized) }) ? 0.18 : 0
            let notebookBoost = notebookConcepts.contains(normalized) ? 0.12 : 0
            return min(1.0, 0.22 + frequency * 0.16 + headingBoost + notebookBoost)
        }

        func difficulty(for concept: String) -> Double {
            let wordCount = normalizeConceptKey(concept).split(separator: " ").count
            let formulaLike = concept.contains("=") || concept.contains("→") || concept.contains("->")
            var score = 0.2 + min(0.35, Double(wordCount) * 0.06)
            if formulaLike { score += 0.2 }
            if conceptLocations(for: concept).count <= 1 { score += 0.1 }
            return min(1.0, score)
        }

        func conceptRecord(_ concept: String) -> KnowledgeConcept {
            let sourceLocations = conceptLocations(for: concept)
            let definitionEvidence = definitionEvidence(for: concept, sentences: sentences)
            let aliasEvidence = aliasEvidence(for: concept, sentences: sentences)
            let definitionText = definitionText(for: concept, sentences: sentences)
            return KnowledgeConcept(
                name: displayConcept(concept),
                definition: definitionText,
                aliases: aliases(for: concept, sentences: sentences),
                category: "concept",
                section: sourceLocations.first?.sectionTitle ?? headings.first ?? noteTitle,
                source: sourceLocations.first?.sectionID ?? sourceSignature,
                definitionEvidence: definitionEvidence,
                aliasEvidence: aliasEvidence,
                sourceExcerpt: sourceLocations.first?.snippet ?? definitionText,
                importance: importance(for: concept),
                difficulty: difficulty(for: concept),
                relationships: relatedConceptTitles(for: concept, concepts: conceptStrings),
                examples: evidence(for: concept, sentences: sentences),
                learningObjective: learningObjective(for: concept, sentences: sentences),
                confidence: confidence(for: concept, sentences: sentences, definitionText: definitionText, aliasEvidence: aliasEvidence),
                sourceLocations: sourceLocations
            )
        }

        let concepts = conceptStrings.prefix(strategy.conceptLimit).map(conceptRecord(_:))
        let definitions = concepts.map { concept in
            KnowledgeDefinition(
                term: concept.name,
                definition: concept.definition,
                aliases: concept.aliases,
                sourceLocations: concept.sourceLocations,
                confidence: concept.confidence
            )
        }

        let examples = concepts.flatMap { concept in
            concept.examples.prefix(2).map { example in
                KnowledgeExample(
                    conceptID: concept.id,
                    example: example,
                    sourceLocations: concept.sourceLocations,
                    confidence: concept.confidence
                )
            }
        }

        let processes = extractProcessRecords(sentences: sentences, sections: sections)
        let relationships = buildRelationships(concepts: concepts, sentences: sentences, sourceSignature: sourceSignature)
        let learningObjectives = concepts.compactMap { concept -> KnowledgeObjective? in
            guard !concept.learningObjective.isEmpty else { return nil }
            return KnowledgeObjective(
                objective: concept.learningObjective,
                relatedConceptIDs: [concept.id],
                sourceLocations: concept.sourceLocations,
                confidence: concept.confidence
            )
        }

        let actionItems = extractActionItems(sentences: sentences, concepts: concepts)
        let keywords = dedupeStrings(topicCandidates + concepts.map(\.name))
        let supportingEvidence = Array(Set(concepts.flatMap(\.examples) + sentences.prefix(6))).prefix(24).map { String($0) }
        let summaryHighlights = extractSummaryHighlights(sentences: sentences, concepts: concepts.map(\.name))
        let examFocus = Array(concepts.prefix(6).map(\.name))
        let hierarchy = sections.isEmpty ? concepts.prefix(5).map { KnowledgeSection(title: $0.name, kind: .custom, order: 0, content: $0.definition, children: [], sourceLocations: $0.sourceLocations) } : sections

        return StructuredKnowledge(
            metadata: KnowledgeMetadata(
                noteID: sourceSignature,
                title: noteTitle,
                subject: subjectGuess(from: noteTitle, text: cleanedText),
                sourceType: "note",
                approximateTokenCount: structure.complexity.tokenEstimate,
                sectionCount: structure.sections.count,
                extractedAt: Date(),
                modelName: ModelManager.shared.activeModelIDDescription(),
                promptVersion: "\(AIPromptVersion.current.major).\(AIPromptVersion.current.minor).\(AIPromptVersion.current.patch)",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                gitCommit: gitCommitDescription(),
                sourceSignature: sourceSignature
            ),
            title: noteTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            topics: topicCandidates,
            sections: sections,
            concepts: concepts,
            definitions: definitions,
            examples: examples,
            processes: processes,
            relationships: relationships,
            learningObjectives: learningObjectives,
            actionItems: actionItems,
            keywords: keywords,
            confidence: confidenceFrom(concepts: concepts),
            sourceLocations: sectionLocations,
            difficulty: difficultyFrom(text: cleanedText, concepts: concepts.map(\.name)),
            importance: importanceFrom(concepts: concepts),
            aliases: aliases(for: noteTitle, sentences: []),
            procedures: sentences.filter { looksLikeProcedure($0) },
            formulas: sentences.filter { $0.contains("=") || $0.contains("→") || $0.contains("->") },
            importantFacts: extractImportantFacts(sentences: sentences),
            keyTerminology: keywords,
            misconceptions: extractMisconceptions(sentences: sentences),
            prerequisites: extractPrerequisites(sentences: sentences),
            hierarchy: hierarchy,
            supportingEvidence: supportingEvidence,
            summaryHighlights: summaryHighlights,
            examFocus: examFocus
        )
    }

    private func merge(payload: StructuredKnowledge, with fallback: StructuredKnowledge) -> StructuredKnowledge {
        var merged = fallback
        merged.metadata = merge(metadata: fallback.metadata, with: payload.metadata)
        merged.title = payload.title.isEmpty ? fallback.title : payload.title
        merged.topics = payload.topics.isEmpty ? fallback.topics : payload.topics
        merged.sections = payload.sections.isEmpty ? fallback.sections : payload.sections
        merged.concepts = payload.concepts.isEmpty ? fallback.concepts : payload.concepts
        merged.definitions = payload.definitions.isEmpty ? fallback.definitions : payload.definitions
        merged.examples = payload.examples.isEmpty ? fallback.examples : payload.examples
        merged.processes = payload.processes.isEmpty ? fallback.processes : payload.processes
        merged.relationships = payload.relationships.isEmpty ? fallback.relationships : payload.relationships
        merged.learningObjectives = payload.learningObjectives.isEmpty ? fallback.learningObjectives : payload.learningObjectives
        merged.actionItems = payload.actionItems.isEmpty ? fallback.actionItems : payload.actionItems
        merged.keywords = payload.keywords.isEmpty ? fallback.keywords : payload.keywords
        merged.confidence = payload.confidence == 0 ? fallback.confidence : payload.confidence
        merged.sourceLocations = payload.sourceLocations.isEmpty ? fallback.sourceLocations : payload.sourceLocations
        merged.difficulty = payload.difficulty
        merged.importance = payload.importance == 0 ? fallback.importance : payload.importance
        merged.aliases = payload.aliases.isEmpty ? fallback.aliases : payload.aliases
        merged.procedures = payload.procedures.isEmpty ? fallback.procedures : payload.procedures
        merged.formulas = payload.formulas.isEmpty ? fallback.formulas : payload.formulas
        merged.importantFacts = payload.importantFacts.isEmpty ? fallback.importantFacts : payload.importantFacts
        merged.keyTerminology = payload.keyTerminology.isEmpty ? fallback.keyTerminology : payload.keyTerminology
        merged.misconceptions = payload.misconceptions.isEmpty ? fallback.misconceptions : payload.misconceptions
        merged.prerequisites = payload.prerequisites.isEmpty ? fallback.prerequisites : payload.prerequisites
        merged.hierarchy = payload.hierarchy.isEmpty ? fallback.hierarchy : payload.hierarchy
        merged.supportingEvidence = payload.supportingEvidence.isEmpty ? fallback.supportingEvidence : payload.supportingEvidence
        merged.summaryHighlights = payload.summaryHighlights.isEmpty ? fallback.summaryHighlights : payload.summaryHighlights
        merged.examFocus = payload.examFocus.isEmpty ? fallback.examFocus : payload.examFocus
        return merged
    }

    private func merge(metadata fallback: KnowledgeMetadata, with payload: KnowledgeMetadata) -> KnowledgeMetadata {
        var merged = fallback
        if !payload.noteID.isEmpty { merged.noteID = payload.noteID }
        if !payload.title.isEmpty { merged.title = payload.title }
        if !payload.subject.isEmpty { merged.subject = payload.subject }
        if !payload.sourceType.isEmpty { merged.sourceType = payload.sourceType }
        if payload.approximateTokenCount > 0 { merged.approximateTokenCount = payload.approximateTokenCount }
        if payload.sectionCount > 0 { merged.sectionCount = payload.sectionCount }
        if payload.extractedAt != Date.distantPast { merged.extractedAt = payload.extractedAt }
        if !payload.modelName.isEmpty { merged.modelName = payload.modelName }
        if !payload.promptVersion.isEmpty { merged.promptVersion = payload.promptVersion }
        if !payload.appVersion.isEmpty { merged.appVersion = payload.appVersion }
        if !payload.gitCommit.isEmpty { merged.gitCommit = payload.gitCommit }
        if !payload.sourceSignature.isEmpty { merged.sourceSignature = payload.sourceSignature }
        return merged
    }

    private func extractProcessRecords(sentences: [String], sections: [KnowledgeSection]) -> [KnowledgeProcess] {
        let processSentences = sentences.filter { looksLikeProcedure($0) }
        guard !processSentences.isEmpty else { return [] }
        let locations = sections.first.map { [KnowledgeSourceLocation(sectionID: $0.id, sectionTitle: $0.title, lineStart: 1, lineEnd: 1, order: 0, snippet: processSentences.first ?? "")] } ?? []
        return [KnowledgeProcess(title: "Procedure", steps: processSentences.prefix(5).map { String($0) }, sourceLocations: locations, confidence: 0.7)]
    }

    private func extractActionItems(sentences: [String], concepts: [KnowledgeConcept]) -> [KnowledgeActionItem] {
        sentences.compactMap { sentence -> KnowledgeActionItem? in
            let lower = sentence.lowercased()
            guard lower.contains("review") || lower.contains("remember") || lower.contains("study") || lower.contains("practice") else { return nil }
            let matchedConcept = concepts.first(where: { lower.contains($0.name.lowercased()) })
            return KnowledgeActionItem(
                title: matchedConcept?.name ?? "Review",
                details: sentence,
                priority: lower.contains("must") || lower.contains("important") ? "high" : "medium",
                sourceLocations: matchedConcept?.sourceLocations ?? [],
                confidence: matchedConcept?.confidence ?? 0.55
            )
        }
    }

    private func extractSummaryHighlights(sentences: [String], concepts: [String]) -> [String] {
        let important = sentences.filter { sentence in
            let lower = sentence.lowercased()
            return [" is ", " are ", " must ", " should ", " key ", " important ", " definition", " formula", " example"].contains(where: lower.contains)
        }
        if !important.isEmpty {
            return Array(important.prefix(4))
        }
        return Array(concepts.prefix(4))
    }

    private func extractImportantFacts(sentences: [String]) -> [String] {
        let filtered = sentences.filter { sentence in
            let lower = sentence.lowercased()
            return lower.contains("important") || lower.contains("key") || lower.contains("must")
        }
        return Array(filtered.prefix(6))
    }

    private func extractMisconceptions(sentences: [String]) -> [String] {
        let filtered = sentences.filter { sentence in
            let lower = sentence.lowercased()
            return lower.contains("misconception") || lower.contains("common mistake") || lower.contains("do not") || lower.contains("don't")
        }
        return Array(filtered.prefix(4))
    }

    private func extractPrerequisites(sentences: [String]) -> [String] {
        let filtered = sentences.filter { sentence in
            let lower = sentence.lowercased()
            return lower.contains("prerequisite") || lower.contains("requires") || lower.contains("depends on") || lower.contains("before")
        }
        return Array(filtered.prefix(4))
    }

    private func buildRelationships(concepts: [KnowledgeConcept], sentences: [String], sourceSignature: String) -> [KnowledgeRelationship] {
        guard !concepts.isEmpty else { return [] }
        var relationships: [KnowledgeRelationship] = []
        for (index, sentence) in sentences.enumerated() {
            let lower = sentence.lowercased()
            let matchedConcepts = concepts.filter { concept in
                ([concept.name] + concept.aliases).contains(where: { lower.contains($0.lowercased()) })
            }
            guard matchedConcepts.count >= 2 else { continue }
            let kind = relationshipKind(for: lower)
            let endpoints = relationshipEndpoints(in: sentence, concepts: matchedConcepts, kind: kind)
            relationships.append(
                KnowledgeRelationship(
                    sourceID: endpoints.source.id,
                    targetID: endpoints.target.id,
                    relationKind: kind,
                    relation: kind.rawValue,
                    sourceLocations: [KnowledgeSourceLocation(sectionID: sourceSignature, sectionTitle: endpoints.source.name, lineStart: index + 1, lineEnd: index + 1, order: index, snippet: sentence)],
                    confidence: relationshipConfidence(for: sentence, kind: kind, source: endpoints.source, target: endpoints.target)
                )
            )
        }
        return relationships
    }

    private func confidence(for concept: String, sentences: [String], definitionText: String, aliasEvidence: [String]) -> Double {
        let aliases = aliases(for: concept, sentences: sentences)
        let evidenceCount = sentences.filter { sentence in
            sentenceMatchesConcept(sentence, concept: concept, aliases: aliases)
        }.count
        let definitionBoost = definitionText.isEmpty || normalizeConceptKey(definitionText) == normalizeConceptKey(concept) ? 0.0 : 0.2
        let aliasBoost = aliasEvidence.isEmpty ? 0.0 : 0.1
        let evidenceBoost = min(0.3, Double(evidenceCount) * 0.08)
        return min(1.0, 0.38 + definitionBoost + aliasBoost + evidenceBoost)
    }

    private func confidenceFrom(concepts: [KnowledgeConcept]) -> Double {
        guard !concepts.isEmpty else { return 0.5 }
        return concepts.map(\.confidence).reduce(0, +) / Double(concepts.count)
    }

    private func importanceFrom(concepts: [KnowledgeConcept]) -> Double {
        guard !concepts.isEmpty else { return 0.5 }
        return concepts.map(\.importance).reduce(0, +) / Double(concepts.count)
    }

    private func buildQualityMetrics(
        knowledge: StructuredKnowledge,
        structure: DocumentStructure,
        validation: KnowledgeValidationReport,
        noiseSamples: [String]
    ) -> KnowledgeExtractionQualityMetrics {
        let confidences = knowledge.concepts.map(\.confidence)
        let averageConfidence = confidences.isEmpty ? knowledge.confidence : confidences.reduce(0, +) / Double(confidences.count)
        let minimumConfidence = confidences.min() ?? knowledge.confidence
        let maximumConfidence = confidences.max() ?? knowledge.confidence
        let sourceLocationCount = knowledge.sourceLocations.count
            + knowledge.concepts.reduce(0) { $0 + $1.sourceLocations.count }
            + knowledge.definitions.reduce(0) { $0 + $1.sourceLocations.count }
            + knowledge.relationships.reduce(0) { $0 + $1.sourceLocations.count }

        return KnowledgeExtractionQualityMetrics(
            conceptCount: knowledge.concepts.count,
            definitionCount: knowledge.definitions.count,
            exampleCount: knowledge.examples.count,
            processCount: knowledge.processes.count,
            relationshipCount: knowledge.relationships.count,
            learningObjectiveCount: knowledge.learningObjectives.count,
            actionItemCount: knowledge.actionItems.count,
            aliasCount: knowledge.aliases.count + knowledge.concepts.reduce(0) { $0 + $1.aliases.count },
            keywordCount: knowledge.keywords.count,
            sourceLocationCount: sourceLocationCount,
            duplicateConceptCount: validation.duplicateConceptCount,
            duplicateDefinitionCount: validation.duplicateDefinitionCount,
            duplicateAliasCount: validation.duplicateAliasCount,
            duplicateRelationshipCount: validation.duplicateRelationshipCount,
            invalidReferenceCount: validation.invalidReferenceCount,
            emptyDefinitionCount: knowledge.definitions.filter { $0.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
            averageConceptConfidence: averageConfidence,
            minimumConceptConfidence: minimumConfidence,
            maximumConceptConfidence: maximumConfidence,
            confidenceCoverage: confidences.isEmpty ? 0 : Double(confidences.filter { $0 >= validation.confidenceFloor }.count) / Double(confidences.count),
            sectionCoverage: structure.complexity.headingCount == 0 ? 1.0 : min(1.0, Double(knowledge.sections.count) / Double(structure.complexity.headingCount)),
            noiseTokenCount: noiseSamples.count,
            canonicalRelationshipCounts: Dictionary(grouping: knowledge.relationships, by: { $0.relationKind.rawValue }).mapValues(\.count)
        )
    }

    private func sourceReferences(for chunks: [SemanticChunk], sourceSignature: String) -> [ExtractionSourceReference] {
        chunks.map { chunk in
            ExtractionSourceReference(
                chunkID: "\(sourceSignature)#chunk-\(chunk.chunkIndex)",
                documentID: sourceSignature,
                chunkIndex: chunk.chunkIndex,
                startOffset: nil,
                endOffset: nil
            )
        }
    }

    private func buildDebugReport(
        noteTitle: String,
        sourceSignature: String,
        strategy: KnowledgeProcessingStrategy,
        fromCache: Bool,
        knowledge: StructuredKnowledge,
        validation: KnowledgeValidationReport,
        metrics: KnowledgeExtractionQualityMetrics,
        noiseSamples: [String]
    ) -> KnowledgeExtractionDebugReport {
        KnowledgeExtractionDebugReport(
            title: noteTitle,
            sourceSignature: sourceSignature,
            strategy: strategy,
            fromCache: fromCache,
            validation: validation,
            metrics: metrics,
            topConcepts: Array(knowledge.concepts.sorted { $0.confidence > $1.confidence }.prefix(8)),
            topRelationships: Array(knowledge.relationships.sorted { $0.confidence > $1.confidence }.prefix(8)),
            sampleDefinitions: Array(knowledge.definitions.prefix(6)),
            sampleExamples: Array(knowledge.examples.prefix(6)),
            sampleObjectives: Array(knowledge.learningObjectives.prefix(6)),
            sampleActionItems: Array(knowledge.actionItems.prefix(6)),
            headingTrail: knowledge.sections.prefix(8).map { $0.title },
            discardedNoise: noiseSamples
        )
    }

    private func noiseSamples(in text: String) -> [String] {
        let tokens = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
        let candidates = tokens.filter { token in
            noiseTokens.contains(token) || genericEnglishWords.contains(token)
        }
        return dedupeStrings(candidates)
    }

    private func sentenceMatchesConcept(_ sentence: String, concept: String, aliases: [String]) -> Bool {
        let normalizedSentence = normalizeConceptKey(sentence)
        if normalizedSentence.contains(normalizeConceptKey(concept)) {
            return true
        }
        return aliases.contains(where: { alias in
            normalizedSentence.contains(normalizeConceptKey(alias))
        })
    }

    private func difficultyFrom(text: String, concepts: [String]) -> StudyKnowledgeDifficulty {
        let tokenCount = tokenEstimate(for: text)
        if tokenCount < 120 {
            return .intro
        }
        if tokenCount < 450 && concepts.count < 10 {
            return .intermediate
        }
        return .advanced
    }

    private func definitionText(for concept: String, sentences: [String]) -> String {
        let aliases = aliases(for: concept, sentences: sentences)
        if let definition = sentences.compactMap({ explicitDefinitionSentence(for: concept, aliases: aliases, in: $0) }).first {
            return definition
        }
        if let sentence = sentences.first(where: { sentence in
            sentenceMatchesConcept(sentence, concept: concept, aliases: aliases)
        }) {
            return sentenceFragment(sentence)
        }
        return displayConcept(concept)
    }

    private func definitionEvidence(for concept: String, sentences: [String]) -> [String] {
        let aliases = aliases(for: concept, sentences: sentences)
        let matches = sentences.filter { sentence in
            explicitDefinitionSentence(for: concept, aliases: aliases, in: sentence) != nil
        }
        if !matches.isEmpty {
            return Array(matches.prefix(2))
        }
        return Array(sentences.filter { sentenceMatchesConcept($0, concept: concept, aliases: aliases) }.prefix(2))
    }

    private func aliasEvidence(for concept: String, sentences: [String]) -> [String] {
        let aliases = aliases(for: concept, sentences: sentences)
        guard !aliases.isEmpty else { return [] }
        return Array(sentences.filter { sentence in
            sentenceMatchesConcept(sentence, concept: concept, aliases: aliases)
        }.prefix(2))
    }

    private func explicitDefinitionSentence(for concept: String, aliases: [String], in sentence: String) -> String? {
        let lower = sentence.lowercased()
        let candidates = [concept] + aliases
        let normalizedSentence = normalizeConceptKey(sentence)
        let triggers = [
            " is defined as ",
            " are defined as ",
            " can be defined as ",
            " is ",
            " are ",
            " means ",
            " refers to ",
            " consists of ",
            " is a ",
            " is an ",
            " are a ",
            " are an "
        ]

        guard candidates.contains(where: { candidate in
            normalizedSentence.contains(normalizeConceptKey(candidate))
        }) else { return nil }
        for trigger in triggers {
            guard let range = lower.range(of: trigger) else { continue }
            let head = sentence[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidates.contains(where: { candidate in
                let normalizedHead = normalizeConceptKey(head)
                let normalizedCandidate = normalizeConceptKey(candidate)
                return normalizedHead == normalizedCandidate
                    || normalizedHead.hasPrefix(normalizedCandidate)
                    || normalizedCandidate.hasPrefix(normalizedHead)
            }) else { continue }
            let tail = sentence[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return sentenceFragment(String(tail))
        }
        return nil
    }

    private func relationshipKind(for sentence: String) -> KnowledgeRelationshipKind {
        if sentence.contains("example of") || sentence.contains("for example") {
            return .exampleOf
        }
        if sentence.contains("compared to") || sentence.contains("compares to") || sentence.contains("versus") {
            return .comparesTo
        }
        if sentence.contains("causes") || sentence.contains("leads to") || sentence.contains("results in") || sentence.contains("triggers") {
            return .causes
        }
        if sentence.contains("part of") {
            return .partOf
        }
        if sentence.contains("contains") || sentence.contains("includes") {
            return .contains
        }
        if sentence.contains("requires") || sentence.contains("depends on") || sentence.contains("depends upon") {
            return .requires
        }
        if sentence.contains("uses") || sentence.contains("utilizes") {
            return .uses
        }
        if sentence.contains("produces") || sentence.contains("generates") || sentence.contains("creates") {
            return .produces
        }
        return .relatedTo
    }

    private func relationshipEndpoints(in sentence: String, concepts: [KnowledgeConcept], kind: KnowledgeRelationshipKind) -> (source: KnowledgeConcept, target: KnowledgeConcept) {
        let lower = sentence.lowercased()
        let ordered = concepts.sorted {
            let lhsRange = lower.range(of: $0.name.lowercased())?.lowerBound ?? lower.startIndex
            let rhsRange = lower.range(of: $1.name.lowercased())?.lowerBound ?? lower.startIndex
            return lhsRange < rhsRange
        }

        guard ordered.count >= 2 else {
            return (concepts[0], concepts[1])
        }

        switch kind {
        case .partOf, .exampleOf, .requires, .causes, .uses, .produces, .comparesTo, .relatedTo:
            return (ordered[0], ordered[1])
        case .contains:
            return (ordered[0], ordered[1])
        }
    }

    private func relationshipConfidence(for sentence: String, kind: KnowledgeRelationshipKind, source: KnowledgeConcept, target: KnowledgeConcept) -> Double {
        let lower = sentence.lowercased()
        var score = 0.52
        if lower.contains(kind.rawValue.lowercased()) {
            score += 0.12
        }
        if source.definition != source.name {
            score += 0.08
        }
        if target.definition != target.name {
            score += 0.08
        }
        if kind == .relatedTo {
            score -= 0.08
        }
        return min(1.0, max(0.25, score))
    }

    private func subjectGuess(from title: String, text: String) -> String {
        let candidates = [title] + extractTopics(from: title, text: text)
        return candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? "note"
    }

    private func mapSectionKind(_ kind: DocumentSectionKind) -> KnowledgeSectionKind {
        switch kind {
        case .heading:
            return .heading
        case .paragraph:
            return .paragraph
        case .list:
            return .list
        case .numberedSection:
            return .numberedSection
        case .codeBlock:
            return .codeBlock
        case .equation:
            return .equation
        case .table:
            return .table
        case .quote, .root:
            return .paragraph
        }
    }

    private func signatureFor(noteTitle: String, noteText: String, notebookText: String) -> String {
        let payload = [Self.extractionRevision, noteTitle, noteText, notebookText].joined(separator: "\u{241E}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func tokenEstimate(for text: String) -> Int {
        max(1, text.split { $0.isWhitespace || $0.isNewline }.count / 4)
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func splitSentences(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: ". ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func extractTopics(from title: String, text: String) -> [String] {
        var items: [String] = []
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if isMeaningfulCandidate(trimmedTitle) {
            items.append(trimmedTitle)
        }
        let headings = text.components(separatedBy: .newlines).filter { isLikelyHeading($0) && isMeaningfulCandidate($0) }
        items.append(contentsOf: headings.prefix(6))
        items.append(contentsOf: extractConcepts(from: text, limit: 5))
        return dedupeStrings(items).filter(isMeaningfulCandidate)
    }

    private func extractConcepts(from text: String, limit: Int) -> [String] {
        let sentences = splitSentences(text)
        var candidates: [String] = []
        for sentence in sentences {
            let words = sentence.split(separator: " ").map(String.init)
            if words.count <= 1 {
                continue
            }
            if sentence.contains(":") {
                let head = sentence.split(separator: ":", maxSplits: 1).first.map(String.init) ?? sentence
                candidates.append(head)
            }
            candidates.append(contentsOf: extractClauseHeadCandidates(from: sentence))
            candidates.append(contentsOf: extractTitleCaseSequences(from: sentence))
            if sentence.contains("=") || sentence.contains("→") || sentence.contains("->") {
                candidates.append(sentence)
            }
        }
        candidates.append(contentsOf: headings(from: text))
        return dedupeStrings(candidates)
            .filter(isMeaningfulCandidate)
            .prefix(limit)
            .map(displayConcept)
    }

    private func headings(from text: String) -> [String] {
        text.components(separatedBy: .newlines).filter { isLikelyHeading($0) }
    }

    private func extractTitleCaseSequences(from sentence: String) -> [String] {
        let words = sentence.split(separator: " ")
        var sequences: [String] = []
        var current: [String] = []
        for word in words {
            let token = String(word).trimmingCharacters(in: .punctuationCharacters)
            if token.first?.isUppercase == true || token.contains("-") || token.contains("+") {
                current.append(token)
            } else {
                if current.count >= 2 || isStandaloneAcronymCandidate(current.first ?? "") {
                    sequences.append(current.joined(separator: " "))
                }
                current.removeAll()
            }
        }
        if current.count >= 2 || isStandaloneAcronymCandidate(current.first ?? "") {
            sequences.append(current.joined(separator: " "))
        }
        return sequences.filter { $0.count > 2 && isMeaningfulCandidate($0) }
    }

    private func extractClauseHeadCandidates(from sentence: String) -> [String] {
        let patterns = [
            " is ",
            " are ",
            " means ",
            " refers to ",
            " involves ",
            " triggers ",
            " leads to ",
            " causes ",
            " produces ",
            " results in ",
            " protects ",
            " divides ",
            " form ",
            " forms ",
            " creates ",
            " create ",
            " contains ",
            " includes ",
            " allows ",
            " enables "
        ]

        let lower = sentence.lowercased()
        return patterns.compactMap { pattern in
            guard let range = lower.range(of: pattern) else { return nil }
            let head = sentence[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            return head.isEmpty ? nil : String(head)
        }
    }

    private func displayConcept(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeConceptKey(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func aliases(for concept: String, sentences: [String]) -> [String] {
        let components = concept.split(separator: " ").map(String.init)
        var aliasCandidates: [String] = []

        if components.count > 1 {
            aliasCandidates.append(components.joined(separator: "-"))
            aliasCandidates.append(components.joined(separator: "_"))
            let acronym = acronym(for: concept)
            if !acronym.isEmpty {
                aliasCandidates.append(acronym)
            }
        }

        for sentence in sentences where sentenceMatchesConcept(sentence, concept: concept, aliases: []) {
            aliasCandidates.append(contentsOf: parentheticalAliases(in: sentence, canonical: concept))
            aliasCandidates.append(contentsOf: slashAliases(in: sentence, canonical: concept))
        }

        return dedupeStrings(aliasCandidates).filter { candidate in
            normalizeConceptKey(candidate) != normalizeConceptKey(concept)
        }
    }

    private func frequencyMap(for text: String) -> [String: Int] {
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !noiseTokens.contains($0) }
        var counts: [String: Int] = [:]
        for word in words {
            counts[word, default: 0] += 1
        }
        return counts
    }

    private func bestSentence(for concept: String, in sentences: [String]) -> String? {
        let aliases = aliases(for: concept, sentences: sentences)
        return sentences.first(where: { sentence in
            sentenceMatchesConcept(sentence, concept: concept, aliases: aliases)
        })
    }

    private func sentenceFragment(_ sentence: String) -> String {
        sentence
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;"))
    }

    private func evidence(for concept: String, sentences: [String]) -> [String] {
        let aliases = aliases(for: concept, sentences: sentences)
        let matching = sentences.filter { sentenceMatchesConcept($0, concept: concept, aliases: aliases) }
        if !matching.isEmpty { return Array(matching.prefix(2)) }
        return [concept]
    }

    private func relatedConceptTitles(for concept: String, concepts: [String]) -> [String] {
        let normalized = normalizeConceptKey(concept)
        let related = concepts.filter { normalizeConceptKey($0) != normalized }
        return dedupeStrings(related).prefix(3).map(displayConcept)
    }

    private func learningObjective(for concept: String, sentences: [String]) -> String {
        if let sentence = sentences.first(where: { sentence in
            let lower = sentence.lowercased()
            return lower.contains("learn") || lower.contains("understand") || lower.contains("be able to") || lower.contains("objective")
        }) {
            return sentence
        }
        return "Understand \(displayConcept(concept))"
    }

    private func acronym(for concept: String) -> String {
        let words = concept
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty && !noiseTokens.contains($0.lowercased()) && !genericEnglishWords.contains($0.lowercased()) }
        guard words.count > 1 else { return "" }
        return words.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private func parentheticalAliases(in sentence: String, canonical: String) -> [String] {
        var aliases: [String] = []
        let pattern = #"\(([^()]{1,40})\)"#
        let normalizedCanonical = normalizeConceptKey(canonical)
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(sentence.startIndex..., in: sentence)
            for match in regex.matches(in: sentence, range: range) {
                guard match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: sentence) else { continue }
                let value = sentence[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty { continue }
                let normalizedSentence = normalizeConceptKey(sentence)
                let lowercaseValue = value.lowercased()
                if normalizedSentence.contains(normalizedCanonical) {
                    aliases.append(value)
                } else if acronym(for: canonical).lowercased() == lowercaseValue || value == value.uppercased() {
                    aliases.append(value)
                }
            }
        }
        return aliases
    }

    private func slashAliases(in sentence: String, canonical: String) -> [String] {
        guard sentence.contains("/") else { return [] }
        return sentence
            .components(separatedBy: CharacterSet(charactersIn: "/"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && normalizeConceptKey($0) != normalizeConceptKey(canonical) && isMeaningfulCandidate($0) }
    }

    private func dedupeStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizeConceptKey(cleaned)
            guard !cleaned.isEmpty, !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return cleaned
        }
    }

    private func isMeaningfulCandidate(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalizeConceptKey(cleaned)
        guard !key.isEmpty else { return false }
        if noiseTokens.contains(key) || noiseTokens.contains(cleaned.lowercased()) {
            return false
        }

        let words = key.split(separator: " ")
        if words.count == 1 {
            let word = String(words[0])
            if word.count <= 2 { return false }
            if noiseTokens.contains(word) { return false }
            let isAcronym = cleaned == cleaned.uppercased() && cleaned.count <= 6
            let looksTechnical = cleaned.contains(where: { $0.isNumber }) || cleaned.contains("-") || cleaned.contains("+")
            let looksSpecific = cleaned.count >= 4 && !genericEnglishWords.contains(word)
            return isAcronym || looksTechnical || looksSpecific
        }

        let informativeTokens = words.filter { token in
            let token = String(token)
            return !noiseTokens.contains(token) && !genericEnglishWords.contains(token) && !token.allSatisfy(\.isNumber)
        }

        return informativeTokens.count >= 1 && words.count <= 6 && words.contains(where: { token in
            let token = String(token)
            return !noiseTokens.contains(token) && !genericEnglishWords.contains(token)
        })
    }

    private func isStandaloneAcronymCandidate(_ token: String) -> Bool {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        let letters = cleaned.filter { $0.isLetter }
        return cleaned == cleaned.uppercased() && letters.count >= 2 && cleaned.count <= 8
    }

    private var noiseTokens: Set<String> {
        Self.noiseTokens
    }

    private static let noiseTokens: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "good", "hello", "hi", "how",
        "i", "if", "in", "is", "it", "let", "like", "me", "morning", "note", "notes", "now", "okay",
        "of", "on", "or", "our", "specifically", "study", "thanks", "the", "this", "to", "today", "we",
        "welcome", "what", "with", "you", "your", "everyone", "morning", "afternoon", "evening"
    ]

    private var genericEnglishWords: Set<String> {
        Self.genericEnglishWords
    }

    private static let genericEnglishWords: Set<String> = [
        "good", "today", "specifically", "morning", "everyone", "now", "today", "note", "study",
        "thing", "things", "stuff", "maybe", "really", "basically", "actually", "simply", "important",
        "useful", "general", "common", "section", "lecture", "class", "topic", "content"
    ]

    private func isLikelyHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.count > 90 { return false }
        if trimmed.hasPrefix("#") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
            return true
        }
        if trimmed.contains(".") || trimmed.contains("!") || trimmed.contains("?") {
            return false
        }
        let words = trimmed.split(separator: " ")
        return words.count <= 8 && trimmed.first?.isUppercase == true
    }

    private func looksLikeProcedure(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        return [" first ", " then ", " next ", " step ", " process ", " algorithm ", " workflow ", " procedure "].contains(where: lower.contains)
    }

    private func gitCommitDescription() -> String {
        return ""
    }
}

final class KnowledgeExtractionPipeline {
    static let shared = KnowledgeExtractionPipeline()

    private let engine = KnowledgeExtractionEngine.shared

    private init() {}

    func extractKnowledge(noteTitle: String, noteText: String, notebookText: String = "") async -> KnowledgeExtractionResult {
        let run = await engine.extractRun(noteTitle: noteTitle, noteText: noteText, notebookText: notebookText)
        return KnowledgeExtractionResult(
            structuredKnowledge: run.knowledge,
            canonicalExtraction: run.canonicalExtraction,
            snapshot: run.knowledge.legacySnapshotRepresentation(),
            strategy: run.strategy,
            fromCache: run.fromCache,
            structure: run.structure,
            qualityMetrics: run.qualityMetrics,
            debugReport: run.debugReport
        )
    }

    func normalizedSignature(noteTitle: String, noteText: String, notebookText: String = "") -> String {
        engine.normalizedSignature(noteTitle: noteTitle, noteText: noteText, notebookText: notebookText)
    }

    func clearCache() {
        engine.clearCache()
    }
}
