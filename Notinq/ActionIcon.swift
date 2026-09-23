//
//  ActionIcon.swift
//  Notinq
//
//  Created by Aman Nair on 02/05/26.
//

import SwiftUI

struct ActionIcon: View {

    let name: String
    let label: String
    var disabled = false
    let action: () -> Void

    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {

            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .opacity(disabled ? 0.45 : (hover ? 1 : 0.8))

                .frame(width: 32, height: 32)
                .background(
                    pressed
                    ? Color.black.opacity(0.07)
                    : (hover ? Color.hoverWarm : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .scaleEffect(pressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.14), value: hover)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hover = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .help(label) // 🔥 macOS native tooltip
    }
}
