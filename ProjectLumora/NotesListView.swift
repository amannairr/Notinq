//
//  NotesListView.swift
//  ProjectLumora
//
//  Created by Aman Nair on 20/04/26.
//

import SwiftUI
import AppKit

struct NotesListView: View {

    @EnvironmentObject var appState: AppState
    @Binding var isCollapsed: Bool
    @State private var searchQuery = ""
    @State private var renamingNoteID: UUID?
    @State private var noteDraftName = ""

    var body: some View {
        VStack(spacing: 0) {

            // 🔥 HEADER SWITCHES BASED ON MODE
            if appState.selectedMode == .search {

                HStack {
                    Image(systemName: "magnifyingglass")

                    TextField("Search notes...", text: $searchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            } else {
                HStack(alignment: .center) {
                    Text("Notes")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        CircleButton(icon: "plus") {
                            appState.createNoteInSelectedFolder()
                        }
                        CircleButton(icon: "sidebar.left") {
                            isCollapsed = true
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Divider().overlay(Color.borderSubtle.opacity(0.7))

            // 🔥 CONTENT SWITCH
            ScrollView {

                if appState.selectedMode == .search {

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<8) { i in
                            Text("Search result \(i)")
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.hoverWarm)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(12)

                } else {

                    VStack(spacing: 8) {
                        if let selectedFolderID = appState.selectedFolderID,
                           let folder = appState.folders.first(where: { $0.id == selectedFolderID }) {
                            ForEach(folder.notes) { note in
                                if renamingNoteID == note.id {
                                    TextField("Note name", text: $noteDraftName)
                                        .textFieldStyle(.roundedBorder)
                                        .onSubmit {
                                            appState.renameNote(note.id, to: noteDraftName)
                                            renamingNoteID = nil
                                        }
                                        .padding(.horizontal, 6)
                                } else {
                                    NotesRow(
                                            title: note.title,
                                            preview: note.content.isEmpty ? "Empty note" : note.content,
                                            isSelected: appState.selectedNoteID == note.id
                                        ) {
                                            appState.selectNote(note.id)
                                        }
                                        .contextMenu {
                                            Button("Rename") {
                                                renamingNoteID = note.id
                                                noteDraftName = note.title
                                            }
                                            Button("Delete", role: .destructive) {
                                                appState.deleteNote(note.id)
                                            }
                                        }
                                }
                            }
                        }
                        if appState.selectedFolderID == nil {
                            Text("Create a folder to start")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color.bgNotesPane)
    }
}
