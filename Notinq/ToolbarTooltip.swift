//
//  ToolbarTooltip.swift
//  Notinq
//
//  Created by Aman Nair on 12/05/26.
//

import SwiftUI

struct ToolbarTooltip: ViewModifier {

    let text: String

    func body(content: Content) -> some View {
        content
            .help(text)
    }
}
