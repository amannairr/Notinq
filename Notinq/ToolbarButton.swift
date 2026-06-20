//
//  ToolbarButton.swift
//  Notinq
//
//  Created by Aman Nair on 02/05/26.
//

import SwiftUI

struct ToolbarToggleButton: View {

    let icon: String
    let isActive: Bool
    let label: String
    let action: () -> Void

    @State private var hover = false
    @State private var isPressed = false

    var body: some View {

        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(
                    isActive
                    ? Color.accentColor
                    : Color.textSecondary
                )
                .frame(width: 26, height: 26)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            hover
                            ? Color.borderSubtle.opacity(0.7)
                            : Color.clear,
                            lineWidth: 0.5
                        )
                )
                .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)

        .overlay(alignment: .top) {

            if hover {
                tooltip
                    .offset(x: 0, y: -38)
                    .allowsHitTesting(false)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.96)
                        )
                    )
                    .zIndex(1000)
            }
        }

        .onHover { hovering in
            withAnimation(
                .spring(
                    response: 0.18,
                    dampingFraction: 0.82
                )
            ) {
                hover = hovering
            }
        }

        .onLongPressGesture(
            minimumDuration: 0,
            pressing: { pressing in
                isPressed = pressing
            },
            perform: {}
        )

        .animation(
            .spring(
                response: 0.18,
                dampingFraction: 0.82
            ),
            value: hover
        )
    }

    private var backgroundColor: Color {

        if isPressed {
            return Color.black.opacity(0.07)
        }

        if isActive {
            return Color.accentColor.opacity(0.14)
        }

        if hover {
            return Color.bgElevated
        }

        return Color.clear
    }

    private var tooltip: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.92))
            .fixedSize()
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        Color.white.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: .black.opacity(0.18),
                radius: 10,
                x: 0,
                y: 4
            )
    }
}
