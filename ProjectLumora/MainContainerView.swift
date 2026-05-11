//
//  ContentView.swift
//  ProjectLumora
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
    @State private var sidebarWidth: CGFloat = 220
    @State private var listWidth: CGFloat = 300

    @State private var sidebarLastDragX: CGFloat?
    @State private var listLastDragX: CGFloat?
    @State private var isSidebarCollapsed = false
    @State private var isNotesCollapsed = false

    var body: some View {
        ZStack {

            HStack(spacing: 0) {

                ModeBarView(selectedMode: $appState.selectedMode)
                    .frame(width: 76)

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
                        .background(Color.bgSidebar)
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
                                    sidebarWidth = clamp(sidebarWidth + delta, min: 180, max: 320)
                                }
                                sidebarLastDragX = currentX
                            }
                        },
                        onEnd: {
                            sidebarLastDragX = nil
                        },
                        onDoubleClick: {
                            sidebarWidth = 220
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
                            listWidth = 300
                        }
                    )
                }

                ZStack {
                    EditorView().opacity(appState.selectedMode == .notes || appState.selectedMode == .ai || appState.selectedMode == .study ? 1 : 0)
                    SearchView().opacity(appState.selectedMode == .search ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgEditor)
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
                .fill(Color.borderSubtle.opacity(0.65))
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
