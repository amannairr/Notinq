//
//  SideBarView.swift
//  ProjectLumora
//
//  Created by Aman Nair on 20/04/26.
//

import SwiftUI

struct SidebarView: View {

    @EnvironmentObject var appState: AppState
    @Binding var isCollapsed: Bool
    @State private var renamingFolderID: UUID?
    @State private var folderDraftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack {
                Text("Folders")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                Spacer()
                CircleButton(icon: "plus") {
                    appState.createFolder()
                }
                CircleButton(icon: "sidebar.left") {
                    isCollapsed = true
                }
            }

            VStack(spacing: 10) {
                ForEach(appState.folders) { folder in
                    if renamingFolderID == folder.id {
                        TextField("Folder name", text: $folderDraftName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                appState.renameFolder(folder.id, to: folderDraftName)
                                renamingFolderID = nil
                            }
                    } else {
                        SidebarItem(
                            title: folder.title,
                            isSelected: appState.selectedFolderID == folder.id
                        ) {
                            appState.selectFolder(folder.id)
                        }
                        .contextMenu {
                            Button("Rename") {
                                renamingFolderID = folder.id
                                folderDraftName = folder.title
                            }
                            Button("Delete", role: .destructive) {
                                appState.deleteFolder(folder.id)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(16)
    }
}
