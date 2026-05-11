//
//  AssistantPanel.swift
//  ProjectLumora
//
//  Created by Aman Nair on 02/05/26.
//

import SwiftUI

struct AssistantPanel: View {

    @Binding var input: String
    var onClose: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 10) {

            HStack {
                TextField("Ask about your notes...", text: $input)
                    .textFieldStyle(.plain)

                Button("Ask") {
                    onSubmit()
                }
            }

            HStack {
                Spacer()
                Button("Close", action: onClose)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 20)
        .padding()
    }
}
