//
//  AppState.swift
//  ProjectLumora
//
//  Created by Aman Nair on 01/05/26.
//

import Combine
import Foundation

enum AIMode: String, CaseIterable {
    case auto
    case local
    case advancedCloud = "advanced_cloud"
}

enum DefaultActionStyle: String, CaseIterable {
    case concise
    case detailed
    case bulletPoints = "bullet_points"
}

class AppState: ObservableObject {
    @Published var selectedNoteContent: String = ""
    @Published var selectedMode: AppMode = .notes
    @Published var folders: [NoteFolder] = []
    @Published var selectedFolderID: UUID?
    @Published var selectedNoteID: UUID?
    @Published var isSettingsOpen: Bool = false
    @Published var isLoggedIn: Bool = false
    @Published var userEmail: String?
    @Published var aiMode: AIMode = .auto
    @Published var defaultActionStyle: DefaultActionStyle = .concise
    @Published var enableStreamingResponses: Bool = false
    @Published var allowCloudAIForComplexTasks: Bool = true
    @Published var privateNotesMode: Bool = false
    @Published var autoInsertTranscription: Bool = true
    @Published var useVoiceAsAICommandInput: Bool = false

    private let storageFileName = "lumora-notes.json"
    private let defaults = UserDefaults.standard

    init() {
        load()
        loadPreferences()
        ensureSelection()
        refreshAuthState()
    }

    func loadPreferences() {
        if let rawAIMode = defaults.string(forKey: "aiMode"),
           let storedAIMode = AIMode(rawValue: rawAIMode) {
            aiMode = storedAIMode
        }
        if let rawStyle = defaults.string(forKey: "defaultActionStyle"),
           let storedStyle = DefaultActionStyle(rawValue: rawStyle) {
            defaultActionStyle = storedStyle
        }
        enableStreamingResponses = defaults.bool(forKey: "enableStreamingResponses")
        allowCloudAIForComplexTasks = defaults.object(forKey: "allowCloudAIForComplexTasks") == nil ? true : defaults.bool(forKey: "allowCloudAIForComplexTasks")
        privateNotesMode = defaults.bool(forKey: "privateNotesMode")
        autoInsertTranscription = defaults.object(forKey: "autoInsertTranscription") == nil ? true : defaults.bool(forKey: "autoInsertTranscription")
        useVoiceAsAICommandInput = defaults.bool(forKey: "useVoiceAsAICommandInput")
    }

    func persistPreferences() {
        defaults.set(aiMode.rawValue, forKey: "aiMode")
        defaults.set(defaultActionStyle.rawValue, forKey: "defaultActionStyle")
        defaults.set(enableStreamingResponses, forKey: "enableStreamingResponses")
        defaults.set(allowCloudAIForComplexTasks, forKey: "allowCloudAIForComplexTasks")
        defaults.set(privateNotesMode, forKey: "privateNotesMode")
        defaults.set(autoInsertTranscription, forKey: "autoInsertTranscription")
        defaults.set(useVoiceAsAICommandInput, forKey: "useVoiceAsAICommandInput")
    }

    func refreshAuthState() {
        isLoggedIn = AuthService.shared.isLoggedIn
        userEmail = AuthService.shared.userEmail
    }

    func createFolder() {
        let newFolder = NoteFolder(title: "Folder \(folders.count + 1)", notes: [
            NoteFile(title: "Note 1", content: "")
        ])
        folders.append(newFolder)
        selectedFolderID = newFolder.id
        selectedNoteID = newFolder.notes.first?.id
        selectedNoteContent = newFolder.notes.first?.content ?? ""
        save()
    }

    func createNoteInSelectedFolder() {
        guard let folderIndex = selectedFolderIndex else { return }
        let noteNumber = folders[folderIndex].notes.count + 1
        let note = NoteFile(title: "Note \(noteNumber)", content: "")
        folders[folderIndex].notes.append(note)
        selectedNoteID = note.id
        selectedNoteContent = note.content
        save()
    }

    func renameFolder(_ folderID: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[index].title = trimmed
        save()
    }

    func deleteFolder(_ folderID: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders.remove(at: index)
        ensureSelection()
        save()
    }

    func renameNote(_ noteID: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let folderIndex = folders.firstIndex(where: { folder in
            folder.notes.contains(where: { $0.id == noteID })
        }) else { return }
        guard let noteIndex = folders[folderIndex].notes.firstIndex(where: { $0.id == noteID }) else { return }
        folders[folderIndex].notes[noteIndex].title = trimmed
        folders[folderIndex].notes[noteIndex].updatedAt = Date()
        save()
    }

    func deleteNote(_ noteID: UUID) {
        guard let folderIndex = folders.firstIndex(where: { folder in
            folder.notes.contains(where: { $0.id == noteID })
        }) else { return }
        guard let noteIndex = folders[folderIndex].notes.firstIndex(where: { $0.id == noteID }) else { return }
        folders[folderIndex].notes.remove(at: noteIndex)

        if folders[folderIndex].notes.isEmpty {
            folders[folderIndex].notes.append(NoteFile(title: "Note 1", content: ""))
        }

        if selectedNoteID == noteID {
            selectedNoteID = folders[folderIndex].notes.first?.id
            selectedNoteContent = folders[folderIndex].notes.first?.content ?? ""
        }
        save()
    }

    func selectFolder(_ folderID: UUID) {
        guard selectedFolderID != folderID else { return }
        selectedFolderID = folderID
        if let folder = folders.first(where: { $0.id == folderID }),
           let firstNote = folder.notes.first {
            selectedNoteID = firstNote.id
            selectedNoteContent = firstNote.content
        } else {
            selectedNoteID = nil
            selectedNoteContent = ""
        }
    }

    func selectNote(_ noteID: UUID) {
        guard let note = note(for: noteID) else { return }
        selectedNoteID = noteID
        selectedNoteContent = note.content
    }

    func updateSelectedNoteContent(_ newContent: String) {
        guard let selectedNoteID else { return }
        guard let folderIndex = folders.firstIndex(where: { folder in
            folder.notes.contains(where: { $0.id == selectedNoteID })
        }) else { return }
        guard let noteIndex = folders[folderIndex].notes.firstIndex(where: { $0.id == selectedNoteID }) else { return }
        guard folders[folderIndex].notes[noteIndex].content != newContent else { return }

        folders[folderIndex].notes[noteIndex].content = newContent
        folders[folderIndex].notes[noteIndex].updatedAt = Date()
        selectedNoteContent = newContent
        save()
    }

    private var selectedFolderIndex: Int? {
        guard let selectedFolderID else { return nil }
        return folders.firstIndex(where: { $0.id == selectedFolderID })
    }

    private func note(for noteID: UUID) -> NoteFile? {
        for folder in folders {
            if let note = folder.notes.first(where: { $0.id == noteID }) {
                return note
            }
        }
        return nil
    }

    private func ensureSelection() {
        if folders.isEmpty {
            folders = [
                NoteFolder(title: "General", notes: [
                    NoteFile(title: "Welcome", content: "Start writing your notes here."),
                    NoteFile(title: "Ideas", content: "")
                ])
            ]
        }

        if selectedFolderID == nil || !folders.contains(where: { $0.id == selectedFolderID }) {
            selectedFolderID = folders.first?.id
        }

        if let selectedFolderID,
           let folder = folders.first(where: { $0.id == selectedFolderID }) {
            if selectedNoteID == nil || !folder.notes.contains(where: { $0.id == selectedNoteID }) {
                selectedNoteID = folder.notes.first?.id
            }
        }

        if let selectedNoteID, let note = note(for: selectedNoteID) {
            selectedNoteContent = note.content
        } else {
            selectedNoteContent = ""
        }
        save()
    }

    private func save() {
        let payload = NotesStoragePayload(
            folders: folders,
            selectedFolderID: selectedFolderID,
            selectedNoteID: selectedNoteID
        )
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save notes: \(error)")
        }
    }

    private func load() {
        do {
            let data = try Data(contentsOf: storageURL)
            let payload = try JSONDecoder().decode(NotesStoragePayload.self, from: data)
            folders = payload.folders
            selectedFolderID = payload.selectedFolderID
            selectedNoteID = payload.selectedNoteID
        } catch {
            folders = []
        }
    }

    private var storageURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = baseURL.appendingPathComponent("ProjectLumora", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent(storageFileName)
    }
}

struct NoteFile: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, content: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.updatedAt = updatedAt
    }
}

struct NoteFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var notes: [NoteFile]

    init(id: UUID = UUID(), title: String, notes: [NoteFile]) {
        self.id = id
        self.title = title
        self.notes = notes
    }
}

private struct NotesStoragePayload: Codable {
    var folders: [NoteFolder]
    var selectedFolderID: UUID?
    var selectedNoteID: UUID?
}
