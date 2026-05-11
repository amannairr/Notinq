//
//  CommandBarView.swift
//  ProjectLumora
//
//  Created by Aman Nair on 21/04/26.
//

import SwiftUI

struct CommandBarView: View {

    @Binding var isVisible: Bool
    @State private var query = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { isVisible = false }

            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")

                    TextField("Ask AI or run a command...", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 20)
                .frame(width: 520)
            }
        }
    }
}
