//
//  SelectionToolbarView.swift
//  Notinq
//
//  Created by Aman Nair on 01/05/26.
//

import SwiftUI

struct SelectionToolbarView: View {

    var areProposalActionsDisabled = false
    var onSummarize: () -> Void
    var onExpand: () -> Void
    var onSimplify: () -> Void
    var onRewrite: () -> Void
    var onExplain: () -> Void
    var onExample: () -> Void
    var onAnalogy: () -> Void
    var onDontUnderstand: () -> Void
    var onFlashcards: () -> Void
    var onQuiz: () -> Void
    var onAdd: () -> Void
    var onCopy: () -> Void

    @State private var visible = false

    var body: some View {
        HStack(spacing: 10) {
            actionGroup {
                ActionIcon(name: "summary", label: "Summarize", action: onSummarize)
                actionPill("Expand", disabled: areProposalActionsDisabled, action: onExpand)
                actionPill("Simplify", disabled: areProposalActionsDisabled, action: onSimplify)
                ActionIcon(name: "rewrite", label: "Rewrite", action: onRewrite)
                ActionIcon(name: "explain", label: "Explain", disabled: areProposalActionsDisabled, action: onExplain)
                actionPill("Example", disabled: areProposalActionsDisabled, action: onExample)
                actionPill("Analogy", disabled: areProposalActionsDisabled, action: onAnalogy)
                actionPill("I Don't Understand This", disabled: areProposalActionsDisabled, action: onDontUnderstand)
            }

            Divider()
                .frame(height: 24)

            actionGroup {
                actionPill("Flashcards", action: onFlashcards)
                actionPill("Quiz", action: onQuiz)
                actionPill("Copy", action: onCopy)
                ActionIcon(name: "ask", label: "Ask AI", action: onAdd)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.borderSubtle.opacity(0.85), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
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

    static let actionLabels = [
        "Summarize",
        "Expand",
        "Simplify",
        "Rewrite",
        "Explain",
        "Example",
        "Analogy",
        "I Don't Understand This",
        "Flashcards",
        "Quiz",
        "Copy",
        "Ask AI"
    ]

    private func actionPill(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(Color.textSecondary)
            .opacity(disabled ? 0.45 : 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.hoverWarm.opacity(0.9))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.borderSubtle.opacity(0.45), lineWidth: 0.6)
            )
            .buttonStyle(.plain)
            .disabled(disabled)
            .help(title)
    }

    private func actionGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 7) {
            content()
        }
    }
}
