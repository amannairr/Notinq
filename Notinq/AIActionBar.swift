//
//  AIActionBar.swift
//  Notinq
//
//  Created by Aman Nair on 01/05/26.
//

import SwiftUI

struct AIActionBar: View {

    let onSummarize: () -> Void
    let onRewrite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Summarize", action: onSummarize)
            Button("Rewrite", action: onRewrite)
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity, alignment: .center) 
    }
}
