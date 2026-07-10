import Foundation

final class ConceptExtractionService {
    struct ExtractionError: LocalizedError {
        var errorDescription: String? { "The knowledge graph response could not be decoded." }
    }

    func extractGraph(from note: KnowledgeGraphNoteInput, completion: @escaping (Result<KnowledgeGraphExtractionPayload, Error>) -> Void) {
        let prompt = buildPrompt(for: note)
        let contextLength = max(256, max(note.text.count, note.title.count))

        AIService.shared.run(prompt: prompt, contextLength: contextLength, kind: .knowledgeGraphExtraction) { response in
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = cleaned.data(using: .utf8) else {
                completion(.failure(ExtractionError()))
                return
            }

            do {
                let payload = try JSONDecoder().decode(KnowledgeGraphExtractionPayload.self, from: data)
                completion(.success(payload))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func cancelCurrentExtraction() {
        AIService.shared.cancelGeneration()
    }

    private func buildPrompt(for note: KnowledgeGraphNoteInput) -> String {
        """
        You are an educational knowledge extraction system.
        Analyze the note.
        Extract:
        • Important concepts
        • Short description of each concept
        • Synonyms if applicable
        • Difficulty (0-1)
        • Importance (0-1)
        • Relationships
        Return ONLY valid JSON.
        Never include markdown.
        Ignore filler text.
        Ignore headings that are not actual concepts.

        Note title:
        \(note.title)

        Note content:
        \(note.text)

        Return this JSON shape exactly:
        {
          "concepts": [
            {
              "name": "Gradient Descent",
              "description": "Optimization algorithm minimizing loss.",
              "aliases": ["GD"],
              "importance": 0.94,
              "difficulty": 0.72
            }
          ],
          "relationships": [
            {
              "source": "Gradient Descent",
              "target": "Loss Function",
              "type": "dependsOn",
              "confidence": 0.85
            }
          ]
        }
        """
    }
}
