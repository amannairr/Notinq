//
//  SideBarItem.swift
//  ProjectLumora
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
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.textPrimary)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected
                    ? Color.selectionWarm
                    : (hover ? Color.hoverWarm : Color.clear)
                )
                .animation(.easeInOut(duration: 0.14), value: hover)
                .animation(.easeInOut(duration: 0.14), value: isSelected)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
