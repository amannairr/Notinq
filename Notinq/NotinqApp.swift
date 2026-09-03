//
//  NotinqApp.swift
//  Notinq
//
//  Created by Aman Nair on 11/04/26.
//

import SwiftUI

@main
struct NotinqApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainContainerView(appState: appState)
                .background(WindowAccessor())
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            NotinqCommands(appState: appState)
        }
    }
}

struct NotinqCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") {
                appState.createNoteInSelectedFolder()
                appState.selectedMode = .notes
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Navigate") {
            Button("Notes") {
                appState.selectedMode = .notes
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("AI") {
                appState.selectedMode = .ai
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Study") {
                appState.selectedMode = .study
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("Search") {
                appState.selectedMode = .search
            }
            .keyboardShortcut("4", modifiers: .command)
        }

        CommandMenu("Tools") {
            Button("Command Palette") {
                appState.toggleCommandBar()
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Open Learning Insights") {
                appState.openLearningInsights()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Generate Study Materials") {
                appState.requestStudyGeneration()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        }

        CommandMenu("Settings") {
            Button("Preferences") {
                appState.isSettingsOpen = true
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
