//
//  CircleButton.swift
//  Notinq
//
//  Created by Aman Nair on 21/04/26.
//

import SwiftUI

struct CircleButton: View {

    let icon: String
    let label: String?
    var action: () -> Void = {}

    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(Color.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            pressed
                            ? Color.black.opacity(0.07)
                            : (hover ? Color.bgElevated : Color.clear)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(hover ? Color.borderSubtle.opacity(0.65) : Color.clear, lineWidth: 0.5)
                )
                .scaleEffect(pressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.14), value: hover)
        }
        .buttonStyle(.plain)
        .help(label ?? iconTooltip)
        .onHover { hover = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    private var iconTooltip: String {
        switch icon {
        case "plus":
            return "Add"
        case "sidebar.left":
            return "Collapse pane"
        default:
            return icon
        }
    }
}
