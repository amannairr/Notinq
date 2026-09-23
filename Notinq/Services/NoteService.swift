import Foundation

final class NoteService {
    static let shared = NoteService()

    private let repository: NoteRepositoryProtocol
    private let knowledgeService: KnowledgeSyncing
    private let queue = DispatchQueue(label: "notinq.note.service", qos: .userInitiated)

    init(
        repository: NoteRepositoryProtocol = NoteRepository(),
        knowledgeService: KnowledgeSyncing = KnowledgeService.shared
    ) {
        self.repository = repository
        self.knowledgeService = knowledgeService
    }

    func loadFolders() -> [NoteFolder] {
        queue.sync {
            (try? repository.loadFolders()) ?? []
        }
    }

    func saveFolders(_ folders: [NoteFolder]) {
        queue.sync {
            let previousFolders = (try? repository.loadFolders()) ?? []
            guard (try? repository.saveFolders(folders)) != nil else { return }
            syncKnowledge(previousFolders: previousFolders, currentFolders: folders)
        }
    }

    func replaceFolders(_ folders: [NoteFolder]) {
        saveFolders(folders)
    }

    func updateFolderTitle(_ folderID: UUID, title: String, folders: inout [NoteFolder]) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].title = title
        saveFolders(folders)
    }

    func updateNoteContent(_ noteID: UUID, content: String, folders: inout [NoteFolder]) {
        guard let location = location(for: noteID, folders: folders) else { return }
        folders[location.folderIndex].notes[location.noteIndex].content = content
        folders[location.folderIndex].notes[location.noteIndex].updatedAt = Date()
        saveFolders(folders)
    }

    func updateStudyData(_ noteID: UUID, studyData: NoteStudyData, folders: inout [NoteFolder]) {
        guard let location = location(for: noteID, folders: folders) else { return }
        folders[location.folderIndex].notes[location.noteIndex].studyData = studyData
        saveFolders(folders)
    }

    func renameNote(_ noteID: UUID, title: String, folders: inout [NoteFolder]) {
        guard let location = location(for: noteID, folders: folders) else { return }
        folders[location.folderIndex].notes[location.noteIndex].title = title
        folders[location.folderIndex].notes[location.noteIndex].updatedAt = Date()
        saveFolders(folders)
    }

    func deleteNote(_ noteID: UUID, folders: inout [NoteFolder]) {
        guard let location = location(for: noteID, folders: folders) else { return }
        folders[location.folderIndex].notes.remove(at: location.noteIndex)
        if folders[location.folderIndex].notes.isEmpty {
            folders[location.folderIndex].notes.append(NoteFile(title: "Note 1", content: ""))
        }
        saveFolders(folders)
    }

    func deleteFolder(_ folderID: UUID, folders: inout [NoteFolder]) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders.remove(at: index)
        saveFolders(folders)
    }

    func createFolder(named title: String, folders: inout [NoteFolder]) -> NoteFolder {
        let folder = NoteFolder(title: title, notes: [NoteFile(title: "Note 1", content: "")])
        folders.append(folder)
        saveFolders(folders)
        return folder
    }

    func createNote(in folderID: UUID, folders: inout [NoteFolder]) -> NoteFile? {
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return nil }
        let noteNumber = folders[folderIndex].notes.count + 1
        let note = NoteFile(title: "Note \(noteNumber)", content: "")
        folders[folderIndex].notes.append(note)
        saveFolders(folders)
        return note
    }

    private func location(for noteID: UUID, folders: [NoteFolder]) -> (folderIndex: Int, noteIndex: Int)? {
        guard let folderIndex = folders.firstIndex(where: { folder in
            folder.notes.contains(where: { $0.id == noteID })
        }) else {
            return nil
        }
        guard let noteIndex = folders[folderIndex].notes.firstIndex(where: { $0.id == noteID }) else {
            return nil
        }
        return (folderIndex, noteIndex)
    }

    private func syncKnowledge(previousFolders: [NoteFolder], currentFolders: [NoteFolder]) {
        let previousSnapshots = Dictionary(previousFolders.flatMap { folder in
            folder.notes.map { note in
                (note.id, NoteSnapshot(id: note.id, title: note.title, content: note.content, updatedAt: note.updatedAt))
            }
        }, uniquingKeysWith: { first, _ in first })

        let currentSnapshots = currentFolders.flatMap { folder in
            folder.notes.map { note in
                NoteSnapshot(
                    id: note.id,
                    title: note.title,
                    content: note.content,
                    updatedAt: note.updatedAt
                )
            }
        }

        let currentNoteIDs = Set(currentSnapshots.map(\.id))
        let removedNoteIDs = Set(previousSnapshots.keys).subtracting(currentNoteIDs)

        for removedNoteID in removedNoteIDs {
            knowledgeService.removeKnowledge(for: removedNoteID)
        }

        // saveFolders() rewrites note rows, which clears note-linked knowledge rows.
        // Reingest every remaining note so the knowledge store stays in sync.
        for snapshot in currentSnapshots {
            knowledgeService.ingest(note: KnowledgeIngestionRequest(
                noteID: snapshot.id,
                title: snapshot.title,
                content: snapshot.content,
                updatedAt: snapshot.updatedAt
            ))
        }
    }

    private struct NoteSnapshot {
        let id: UUID
        let title: String
        let content: String
        let updatedAt: Date

        init(id: UUID, title: String, content: String, updatedAt: Date) {
            self.id = id
            self.title = title
            self.content = content
            self.updatedAt = updatedAt
        }
    }
}
