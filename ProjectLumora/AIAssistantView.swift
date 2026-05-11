//
//  AIAssistantView.swift
//  ProjectLumora
//
//  Created by Aman Nair on 20/04/26.
//
import SwiftUI

struct AIAssistantView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text("AI")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Summarize") {}
            Button("Rewrite") {}
            Button("Extract Key Points") {}

            Spacer()
        }
        .padding(12)
    }
}
