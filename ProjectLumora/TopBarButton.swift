//
//  TopBarButton.swift
//  ProjectLumora
//
//  Created by Aman Nair on 21/04/26.
//

import SwiftUI

struct TopBarButton: View {

    let icon: String
    let label: String
    let action: () -> Void

    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    pressed
                    ? Color.black.opacity(0.07)
                    : (hover ? Color.hoverWarm : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .scaleEffect(pressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.14), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(label) // 🔥 tooltip
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}
