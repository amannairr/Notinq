//
//  AppState.swift
//  Notinq
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
        save()
    }

    func createNoteInSelectedFolder() {
        guard let folderIndex = selectedFolderIndex else { return }
        let noteNumber = folders[folderIndex].notes.count + 1
        let note = NoteFile(title: "Note \(noteNumber)", content: "")
        folders[folderIndex].notes.append(note)
        selectedNoteID = note.id
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
        }
        save()
    }

    func selectFolder(_ folderID: UUID) {
        guard selectedFolderID != folderID else { return }
        selectedFolderID = folderID
        if let folder = folders.first(where: { $0.id == folderID }),
           let firstNote = folder.notes.first {
            selectedNoteID = firstNote.id
        } else {
            selectedNoteID = nil
        }
    }

    func selectNote(_ noteID: UUID) {
        guard note(for: noteID) != nil else { return }
        selectedNoteID = noteID
    }

    func noteContent(for noteID: UUID) -> String {
        note(for: noteID)?.content ?? ""
    }

    func noteTitle(for noteID: UUID) -> String {
        note(for: noteID)?.title ?? "Untitled Note"
    }

    func noteUpdatedAt(for noteID: UUID) -> Date? {
        note(for: noteID)?.updatedAt
    }

    func studyData(for noteID: UUID) -> NoteStudyData {
        note(for: noteID)?.studyData ?? NoteStudyData()
    }

    func updateLearningInsights(_ learningInsights: LectureCompletenessAnalysis, for noteID: UUID) {
        mutateStudyData(for: noteID) { studyData in
            studyData.learningInsights = learningInsights
            studyData.lastGeneratedAt = learningInsights.generatedAt
        }
    }

    func updateNoteContent(_ newContent: String, for noteID: UUID) {
        guard let location = noteLocation(for: noteID) else { return }
        var updatedFolders = folders
        guard updatedFolders[location.folderIndex].notes[location.noteIndex].content != newContent else { return }

        updatedFolders[location.folderIndex].notes[location.noteIndex].content = newContent
        updatedFolders[location.folderIndex].notes[location.noteIndex].updatedAt = Date()
        folders = updatedFolders
        save()
    }

    func updateStudyData(_ newStudyData: NoteStudyData, for noteID: UUID) {
        guard let location = noteLocation(for: noteID) else { return }
        var updatedFolders = folders
        guard updatedFolders[location.folderIndex].notes[location.noteIndex].studyData != newStudyData else { return }

        updatedFolders[location.folderIndex].notes[location.noteIndex].studyData = newStudyData
        folders = updatedFolders
        save()
    }

    func mutateStudyData(for noteID: UUID, _ mutation: (inout NoteStudyData) -> Void) {
        guard let location = noteLocation(for: noteID) else { return }
        var updatedFolders = folders
        var studyData = updatedFolders[location.folderIndex].notes[location.noteIndex].studyData
        mutation(&studyData)
        guard updatedFolders[location.folderIndex].notes[location.noteIndex].studyData != studyData else { return }

        updatedFolders[location.folderIndex].notes[location.noteIndex].studyData = studyData
        folders = updatedFolders
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

    private func noteLocation(for noteID: UUID) -> (folderIndex: Int, noteIndex: Int)? {
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

    private func ensureSelection() {
        if folders.isEmpty {
            folders = [
                NoteFolder(title: "General", notes: [
                    NoteFile(title: "Note 1", content: ""),
                    NoteFile(title: "Note 2", content: "")
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

        if let selectedNoteID, note(for: selectedNoteID) != nil {
            return
        }
        selectedNoteID = folders.first(where: { $0.id == selectedFolderID })?.notes.first?.id
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
        let directory = baseURL.appendingPathComponent("Notinq", isDirectory: true)
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
    var studyData: NoteStudyData

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case updatedAt
        case studyData
    }

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        updatedAt: Date = Date(),
        studyData: NoteStudyData = NoteStudyData()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.updatedAt = updatedAt
        self.studyData = studyData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        studyData = try container.decodeIfPresent(NoteStudyData.self, forKey: .studyData) ?? NoteStudyData()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(studyData, forKey: .studyData)
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
