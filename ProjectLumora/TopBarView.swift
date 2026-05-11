//
//  TopBarView.swift
//  ProjectLumora
//
//  Created by Aman Nair on 20/04/26.
//

import SwiftUI

struct TopBarView: View {

    @Binding var showCommandBar: Bool

    var body: some View {
        HStack(spacing: 16) {

            Text("Evidra")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 8) {

                TopBarButton(icon: "plus", label: "New Note") {
                    // TODO: Wire up note creation action.
                }
                TopBarButton(icon: "square.and.arrow.up", label: "Share") {
                    // TODO: Wire up share action.
                }

                Divider().frame(height: 14)

                TopBarButton(icon: "sparkles", label: "AI Command Bar") {
                    showCommandBar.toggle()
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.borderSubtle),
            alignment: .bottom
        )
    }
}
