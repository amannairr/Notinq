import Foundation

final class ConceptExtractionService {
    struct ExtractionError: LocalizedError {
        var errorDescription: String? { "The knowledge graph response could not be decoded." }
    }

    func extractGraph(from note: KnowledgeGraphNoteInput, completion: @escaping (Result<KnowledgeGraphExtractionPayload, Error>) -> Void) {
        Task {
            let snapshot = await AIService.shared.extractKnowledge(
                noteTitle: note.title,
                noteText: note.text
            )
            let payload = KnowledgeGraphExtractionPayload(
                concepts: snapshot.concepts.map {
                    KnowledgeGraphExtractionConcept(
                        name: $0.title,
                        description: $0.summary,
                        aliases: $0.aliases,
                        importance: $0.importance,
                        difficulty: $0.difficulty
                    )
                },
                relationships: snapshot.relationships.map {
                    KnowledgeGraphExtractionRelationship(
                        source: $0.sourceTitle,
                        target: $0.targetTitle,
                        type: ConceptRelationshipType(rawValue: $0.relation) ?? .relatedTo,
                        confidence: $0.confidence
                    )
                }
            )
            completion(.success(payload))
        }
    }

    func cancelCurrentExtraction() {
        AIService.shared.cancelGeneration()
    }
}
