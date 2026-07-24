//
//  SelectionToolbarView.swift
//  Notinq
//
//  Created by Aman Nair on 01/05/26.
//

import SwiftUI

struct SelectionToolbarView: View {

    var onSummarize: () -> Void
    var onSimplify: () -> Void
    var onRewrite: () -> Void
    var onExplain: () -> Void
    var onFlashcards: () -> Void
    var onQuiz: () -> Void
    var onAdd: () -> Void
    var onCopy: () -> Void

    @State private var visible = false

    var body: some View {
        HStack(spacing: 8) {
            ActionIcon(name: "summary", label: "Summarize", action: onSummarize)
            actionPill("Simplify", action: onSimplify)
            ActionIcon(name: "rewrite", label: "Rewrite", action: onRewrite)
            ActionIcon(name: "explain", label: "Explain", action: onExplain)
            actionPill("Flashcards", action: onFlashcards)
            actionPill("Quiz", action: onQuiz)
            actionPill("Copy", action: onCopy)
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

    static func isVisible(for selectionRange: NSRange) -> Bool {
        selectionRange.length > 0
    }

    private func actionPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.hoverWarm)
            .clipShape(Capsule())
            .buttonStyle(.plain)
            .help(title)
    }
}
