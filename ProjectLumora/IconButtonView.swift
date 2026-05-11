//
//  IconButtonView.swift
//  ProjectLumora
//
//  Created by Aman Nair on 01/05/26.
//

import SwiftUI

struct IconButton: View {

    let icon: String
    let label: String
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    hover ? Color.hoverWarm : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeInOut(duration: 0.14), value: hover)
        .help(label) 
    }
}
