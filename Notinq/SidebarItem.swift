//
//  SideBarItem.swift
//  Notinq
//
//  Created by Aman Nair on 21/04/26.
//

import SwiftUI

struct SidebarItem: View {

    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? Color.accent : Color.textTertiary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                ? Color.selectionWarm
                : (hover ? Color.hoverWarm : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.clear, lineWidth: 0.5)
            )
            .animation(.easeInOut(duration: 0.14), value: hover)
            .animation(.easeInOut(duration: 0.14), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
