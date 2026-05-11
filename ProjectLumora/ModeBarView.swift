//
//  ModeBarView.swift
//  ProjectLumora
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
        VStack(spacing: 20) {

            // Logo
            Text("E")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.railIconActive)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Modes
            VStack(spacing: 12) {
                ModeItem(icon: "note.text", mode: .notes, selectedMode: $selectedMode)
                ModeItem(icon: "sparkles", mode: .ai, selectedMode: $selectedMode)
                ModeItem(icon: "book", mode: .study, selectedMode: $selectedMode)
                ModeItem(icon: "magnifyingglass", mode: .search, selectedMode: $selectedMode)
            }

            Spacer()

            // 🔥 Profile + Settings (moved here)
            VStack(spacing: 12) {

                Button(action: {
                    // profile click
                }) {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                ModeUtilityButton(icon: "gearshape") {
                    appState.isSettingsOpen = true
                }
            }
            .padding(.bottom, 10)
        }
        .padding(.vertical, 16)
        .frame(width: 76)
        .padding(.leading, 6)
        .background(
            Color.bgRail
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
                    ? Color.white.opacity(0.14)
                    : (hover ? Color.white.opacity(0.08) : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .scaleEffect(pressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.14), value: hover)
                .animation(.easeInOut(duration: 0.14), value: selectedMode)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
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
                .background(hover ? Color.white.opacity(0.08) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .scaleEffect(pressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.14), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}
