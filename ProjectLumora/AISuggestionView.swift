//
//  AISuggestionView.swift
//  ProjectLumora
//
//  Created by Aman Nair on 01/05/26.
//

import SwiftUI

struct AISuggestionView: View {

    let suggestion: String
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            Text("AI Suggestion")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(suggestion)

            HStack {
                Button("Reject", action: onReject)
                    .foregroundColor(.red)

                Spacer()

                Button("Accept", action: onAccept)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 10)
    }
}
