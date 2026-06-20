//
//  ModeBarView.swift
//  Notinq
//
//  Created by Aman Nair on 01/05/26.
//

import SwiftUI

enum AppMode: String, CaseIterable {
    case notes, ai, study, search
}

struct ModeBarView: View {

    @Binding var selectedMode: AppMode
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 22) {

            // Logo
            Text("E")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.railIconActive)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Modes
            VStack(spacing: 16) {
                ModeItem(icon: "note.text", mode: .notes, selectedMode: $selectedMode)
                ModeItem(icon: "sparkles", mode: .ai, selectedMode: $selectedMode)
                ModeItem(icon: "book", mode: .study, selectedMode: $selectedMode)
                ModeItem(icon: "magnifyingglass", mode: .search, selectedMode: $selectedMode)
            }

            Spacer()

            // 🔥 Profile + Settings (moved here)
            VStack(spacing: 16) {

                Button(action: {
                    // profile click
                }) {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)

                ModeUtilityButton(icon: "gearshape") {
                    appState.isSettingsOpen = true
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 48)
        .padding(.bottom, 18)
        .frame(width: 80)
        .background(Color.modebarBG)
        .shadow(
            color: .black.opacity(0.08),
            radius: 16,
            x: 3,
            y: 0
        )
    }
}

// MARK: - Mode Item (REAL BUTTON)
struct ModeItem: View {

    let icon: String
    let mode: AppMode
    @Binding var selectedMode: AppMode

    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button {
            selectedMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(selectedMode == mode ? Color.railIconActive : Color.railIcon)
                .frame(width: 36, height: 36)
                .background(
                    selectedMode == mode
                    ? Color.white.opacity(0.18)
                    : (hover ? Color.white.opacity(0.09) : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            selectedMode == mode
                            ? Color.white.opacity(0.14)
                            : Color.clear,
                            lineWidth: 0.5
                        )
                )
                .scaleEffect(pressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.14), value: hover)
                .animation(.easeInOut(duration: 0.14), value: selectedMode)
        }
        .buttonStyle(.plain)

        .toolbarTooltip(modeTooltip)

        .onHover { hover = $0 }

        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    private var modeTooltip: String {
        switch mode {
        case .notes:
            return "Notes"

        case .ai:
            return "AI Assistant"

        case .study:
            return "Study"

        case .search:
            return "Search"
        }
    }
}

// MARK: - Utility Button
struct ModeUtilityButton: View {

    let icon: String
    let action: () -> Void

    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.railIcon)
                .frame(width: 36, height: 36)
                .background(hover ? Color.white.opacity(0.09) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .scaleEffect(pressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.14), value: hover)
        }
        .buttonStyle(.plain)

        .toolbarTooltip("Settings")

        .onHover { hover = $0 }

        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

