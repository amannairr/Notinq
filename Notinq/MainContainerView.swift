//
//  ContentView.swift
//  Notinq
//
//  Created by Aman Nair on 11/04/26.
//

import SwiftUI
import SwiftData
import AppKit

struct MainContainerView: View {

    @StateObject private var appState = AppState()
    @State private var showCommandBar = false
    @State private var selectedMode: AppMode = .notes

    // Panel widths
    @State private var sidebarWidth: CGFloat = 230
    @State private var listWidth: CGFloat = 328

    @State private var sidebarLastDragX: CGFloat?
    @State private var listLastDragX: CGFloat?
    @State private var isSidebarCollapsed = false
    @State private var isNotesCollapsed = false

    var body: some View {
        ZStack {

            HStack(spacing: 0) {

                ModeBarView(selectedMode: $appState.selectedMode)
                    .frame(width: 80)

                if isSidebarCollapsed {
                    collapsedBar(
                        icon: "sidebar.right",
                        tooltip: "Show sidebar",
                        colors: [Color.bgSidebar, Color.bgSidebar]
                    ) {
                        isSidebarCollapsed = false
                    }
                } else {
                    SidebarView(isCollapsed: $isSidebarCollapsed)
                        .frame(width: sidebarWidth)
                }

                // 🔥 HANDLE 1
                if !isSidebarCollapsed {
                    resizeHandle(
                        onDragChanged: { currentX in
                            if sidebarLastDragX == nil {
                                sidebarLastDragX = currentX
                            }
                            if let lastX = sidebarLastDragX {
                                let delta = currentX - lastX
                                withTransaction(Transaction(animation: nil)) {
                                    sidebarWidth = clamp(sidebarWidth + delta, min: 196, max: 320)
                                }
                                sidebarLastDragX = currentX
                            }
                        },
                        onEnd: {
                            sidebarLastDragX = nil
                        },
                        onDoubleClick: {
                            sidebarWidth = 230
                        }
                    )
                }

                if isNotesCollapsed {
                    collapsedBar(
                        icon: "sidebar.right",
                        tooltip: "Show notes list",
                        colors: [Color.bgNotesPane, Color.bgNotesPane]
                    ) {
                        isNotesCollapsed = false
                    }
                } else {
                    NotesListView(isCollapsed: $isNotesCollapsed)
                        .frame(width: listWidth)
                        .background(Color.clear)
                }

                // 🔥 HANDLE 2
                if !isNotesCollapsed {
                    resizeHandle(
                        onDragChanged: { currentX in
                            if listLastDragX == nil {
                                listLastDragX = currentX
                            }
                            if let lastX = listLastDragX {
                                let delta = currentX - lastX
                                withTransaction(Transaction(animation: nil)) {
                                    listWidth = clamp(listWidth + delta, min: 260, max: 420)
                                }
                                listLastDragX = currentX
                            }
                        },
                        onEnd: {
                            listLastDragX = nil
                        },
                        onDoubleClick: {
                            listWidth = 328
                        }
                    )
                }

                ZStack {
                    switch appState.selectedMode {
                    case .notes:
                        EditorView()
                    case .ai:
                        AIWorkspaceView(
                            noteTitle: currentNoteTitle,
                            noteText: currentNoteText,
                            lastUpdatedAt: currentNoteUpdatedAt
                        )
                    case .study:
                        StudyView(
                            noteID: appState.selectedNoteID,
                            noteTitle: currentNoteTitle,
                            selectedText: "",
                            noteHasContent: !currentNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            studyData: currentStudyData,
                            isGenerating: false,
                            generationStatus: "Generate Study Materials",
                            generationSummary: nil,
                            statusMessage: nil,
                            statusTone: .neutral,
                            onGenerateMaterials: {
                                appState.selectedMode = .study
                            },
                            onClose: {
                                appState.selectedMode = .notes
                            },
                            onExplainSimply: {},
                            onGiveExample: {},
                            onCompareConcepts: {},
                            onCreateAnalogy: {},
                            onMarkFlashcardReviewed: { _ in },
                            onRecordQuizAttempt: { _, _, _ in },
                            onEvaluateTestMe: { _, _, completion in
                                completion(
                                    StudyTutorEvaluation(
                                        verdict: .almost,
                                        feedback: "Not implemented",
                                        explanation: "",
                                        modelAnswer: "",
                                        awardedPoint: 0
                                    )
                                )
                            },
                            onRecordTestMeSession: { _, _, _ in }
                        )
                    case .search:
                        SearchView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgEditor)
                .shadow(color: .black.opacity(0.045), radius: 22, x: -10, y: 0)
                .animation(.easeInOut(duration: 0.15), value: appState.selectedMode)
            }

            if showCommandBar {
                CommandBarView(isVisible: $showCommandBar)
            }

            if appState.isSettingsOpen {
                SettingsOverlayView()
                    .environmentObject(appState)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .background(Color.bgPrimary)
        .environmentObject(appState)
        .onAppear {
            setupKeyboardShortcuts()
        }
    }

    private var currentNoteID: UUID? {
        appState.selectedNoteID
    }

    private var currentNoteTitle: String {
        guard let currentNoteID else { return "Untitled Note" }
        return appState.noteTitle(for: currentNoteID)
    }

    private var currentNoteText: String {
        guard let currentNoteID else { return "" }
        return appState.noteContent(for: currentNoteID)
    }

    private var currentNoteUpdatedAt: Date? {
        guard let currentNoteID else { return nil }
        return appState.noteUpdatedAt(for: currentNoteID)
    }

    private var currentStudyData: NoteStudyData {
        guard let currentNoteID else { return NoteStudyData() }
        return appState.studyData(for: currentNoteID)
    }
}

//////////////////////////////////////////////////////////////
// MARK: - RESIZE HANDLE
//////////////////////////////////////////////////////////////

extension MainContainerView {

    func resizeHandle(
        onDragChanged: @escaping (CGFloat) -> Void,
        onEnd: @escaping () -> Void,
        onDoubleClick: @escaping () -> Void
    ) -> some View {

        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 1)

            Rectangle()
                .fill(Color.clear)
                .frame(width: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    onDragChanged(value.location.x)
                }
                .onEnded { _ in
                    onEnd()
                }
        )
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
    }

    func collapsedBar(
        icon: String,
        tooltip: String,
        colors: [Color],
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 18, height: 34)
                    .background(Color.hoverWarm)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help(tooltip)
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .frame(minWidth: 32, idealWidth: 32, maxWidth: 32, minHeight: 0, idealHeight: nil, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        )
    }
}

//////////////////////////////////////////////////////////////
// MARK: - HELPERS
//////////////////////////////////////////////////////////////

extension MainContainerView {

    func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }

}

//////////////////////////////////////////////////////////////
// MARK: - Keyboard Shortcuts
//////////////////////////////////////////////////////////////

extension MainContainerView {

    func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in

            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "1": appState.selectedMode = .notes
                case "2": appState.selectedMode = .ai
                case "3": appState.selectedMode = .study
                case "4": appState.selectedMode = .search
                case "k": showCommandBar.toggle()
                default: break
                }
            }

            return event
        }
    }
}
