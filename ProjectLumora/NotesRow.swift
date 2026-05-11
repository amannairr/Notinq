//
//  NotesRow.swift
//  ProjectLumora
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
                    .fill(isSelected ? Color.accent.opacity(0.7) : Color.clear)
                    .frame(width: 3)
                    .cornerRadius(2)

                VStack(alignment: .leading, spacing: 6) {

                    HStack {
                        Text(title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(Color.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text("2m")
                            .font(.system(size: 10))
                            .foregroundColor(Color.textTertiary)
                    }

                    Text(preview)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        Color.accent.opacity(0.075),
                        Color.accent.opacity(0.045)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if hover {
                Color.hoverWarm
            } else {
                Color.clear
            }
        }
    }
}
