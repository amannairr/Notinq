//
//  ToolbarTooltip.swift
//  Notinq
//
//  Created by Aman Nair on 12/05/26.
//

import SwiftUI

struct ToolbarTooltip: ViewModifier {

    let text: String
    @State private var hover = false

    func body(content: Content) -> some View {

        content
            .overlay(alignment: .top) {

                if hover {
                    Text(text)
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
                        .offset(y: -38)
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
    }
}
