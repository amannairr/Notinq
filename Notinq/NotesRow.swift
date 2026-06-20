//
//  NotesRow.swift
//  Notinq
//
//  Created by Aman Nair on 21/04/26.
//

import SwiftUI

struct NotesRow: View {

    let title: String
    let preview: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {

                // Optional accent bar (very subtle, premium detail)
                Rectangle()
                    .fill(isSelected ? Color.accent.opacity(0.62) : Color.clear)
                    .frame(width: 3, height: 44)
                    .cornerRadius(2)

                VStack(alignment: .leading, spacing: 7) {

                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(.system(size: 13.5, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text("2m")
                            .font(.system(size: 10))
                            .foregroundColor(Color.textTertiary.opacity(0.78))
                    }

                    Text(preview)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color.textSecondary.opacity(0.88))
                        .lineLimit(2)
                        .lineSpacing(2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(isSelected ? Color.borderSubtle.opacity(0.50) : Color.noteCardStroke.opacity(0.70), lineWidth: 0.5)
            )
            .shadow(
                color: .black.opacity(isSelected ? 0.070 : 0.026),
                radius: isSelected ? 14 : 8,
                x: 0,
                y: isSelected ? 7 : 3
            )
            .animation(.easeInOut(duration: 0.14), value: hover)
            .animation(.easeInOut(duration: 0.14), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var backgroundView: some View {
        Group {
            if isSelected {
                LinearGradient(
                    colors: [
                        Color.noteCardSelected,
                        Color.noteCardSelected.opacity(0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if hover {
                Color.noteCard.opacity(0.98)
            } else {
                Color.noteCard.opacity(0.82)
            }
        }
    }
}
