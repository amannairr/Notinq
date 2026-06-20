//
//  InlineAIView.swift
//  Notinq
//
//  Created by Aman Nair on 01/05/26.
//

import SwiftUI

struct InlineAIView: View {

    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            Text("AI Suggestion")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(text)
                .font(.system(size: 13))
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
