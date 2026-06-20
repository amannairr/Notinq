//
//  SideBarView.swift
//  Notinq
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
        VStack(alignment: .leading, spacing: 18) {

            HStack {
                Text("Folders")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.textPrimary)
                Spacer()
                CircleButton(icon: "plus") {
                    appState.createFolder()
                }
                CircleButton(icon: "sidebar.left") {
                    isCollapsed = true
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 6)

            VStack(spacing: 9) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .background(Color.bgSidebar)
        .overlay {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.014),
                    Color.white.opacity(0.006),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.014), radius: 8, x: 1, y: 0)
    }
}
