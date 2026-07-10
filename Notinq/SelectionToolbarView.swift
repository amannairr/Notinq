//
//  SelectionToolbarView.swift
//  Notinq
//
//  Created by Aman Nair on 01/05/26.
//

import SwiftUI

struct SelectionToolbarView: View {

    var onSummarize: () -> Void
    var onRewrite: () -> Void
    var onExplain: () -> Void
    var onAdd: () -> Void

    @State private var visible = false

    var body: some View {
        HStack(spacing: 6) {
            ActionIcon(name: "summary", label: "Summarize", action: onSummarize)
            ActionIcon(name: "rewrite", label: "Rewrite", action: onRewrite)
            ActionIcon(name: "explain", label: "Explain", action: onExplain)
            ActionIcon(name: "ask", label: "Ask AI", action: onAdd)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        .scaleEffect(visible ? 1 : 0.92)
        .opacity(visible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.18)) {
                visible = true
            }
        }
    }
}
