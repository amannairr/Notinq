import Foundation

struct KnowledgeIngestionRequest: Sendable {
    let noteID: UUID
    let title: String
    let content: String
    let updatedAt: Date
}

protocol KnowledgeSyncing {
    func ingest(note: KnowledgeIngestionRequest)
    func removeKnowledge(for noteID: UUID)
}

final class KnowledgeService {
    static let shared = KnowledgeService()

    private let knowledgeRepository: KnowledgeRepository

    private init(knowledgeRepository: KnowledgeRepository = .shared) {
        self.knowledgeRepository = knowledgeRepository
    }

    func ingest(note: KnowledgeIngestionRequest) {
        Task {
            let structure = DocumentPreprocessor.shared.preprocess(title: note.title, text: note.content)
            let chunks = SemanticChunker.shared.chunk(
                title: note.title,
                structure: structure,
                contextLimit: Int(AIRuntimeConfig.current.llama.contextSize)
            )
            let extraction = await KnowledgeExtractionEngine.shared.extractRun(noteTitle: note.title, noteText: note.content).knowledge
            try? knowledgeRepository.persist(
                noteID: note.noteID,
                noteTitle: note.title,
                noteContent: note.content,
                chunks: chunks,
                extraction: extraction.hasContent ? extraction : nil
            )
        }
    }

    func removeKnowledge(for noteID: UUID) {
        Task {
            try? StudyRepository.shared.remove(noteID: noteID)
            try? knowledgeRepository.remove(noteID: noteID)
        }
    }

    func buildContext(noteID: UUID?, title: String, text: String) -> KnowledgeContext {
        ContextBuilder.shared.build(noteID: noteID, title: title, text: text)
    }
}

extension KnowledgeService: KnowledgeSyncing {}
