//
//  NotesListView.swift
//  Notinq
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
                        .foregroundStyle(Color.textTertiary)

                    TextField("Search notes...", text: $searchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.10))

            } else {
                HStack(alignment: .center) {
                    Text("Notes")
                        .font(.system(size: 13, weight: .semibold))
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
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.10))
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.025),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 8)

            // 🔥 CONTENT SWITCH
            ScrollView {

                if appState.selectedMode == .search {

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(0..<8) { i in
                            Text("Search result \(i)")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.noteCard)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(14)

                } else {

                    VStack(spacing: 13) {
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
                                        .padding(.horizontal, 8)
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
                                .padding(12)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(.regularMaterial)
        .background(Color.bgNotesPane)
        .overlay(alignment: .leading) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.050),
                    Color.black.opacity(0.016),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 12)
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.035), radius: 14, x: -3, y: 0)
    }
}
