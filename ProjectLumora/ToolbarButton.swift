//
//  ToolbarButton.swift
//  ProjectLumora
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
                .foregroundColor(isActive ? Color.textPrimary : Color.textSecondary)
                .frame(width: 26, height: 26)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .scaleEffect(isPressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.14), value: hover)
                .animation(.easeInOut(duration: 0.14), value: isActive)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .help(label) // ✅ now works
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.selectionWarm
        } else if isPressed {
            return Color.black.opacity(0.07)
        } else if hover {
            return Color.hoverWarm
        } else {
            return Color.clear
        }
    }
}
