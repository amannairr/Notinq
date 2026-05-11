//
//  highlightText.swift
//  ProjectLumora
//
//  Created by Aman Nair on 01/05/26.
//

import Foundation
import SwiftUI

func highlightText(_ text: String, query: String) -> AttributedString {
    var attributed = AttributedString(text)

    guard !query.isEmpty else { return attributed }

    let lowerText = text.lowercased()
    let lowerQuery = query.lowercased()

    var searchRange = lowerText.startIndex..<lowerText.endIndex

    while let range = lowerText.range(of: lowerQuery, options: [], range: searchRange) {
        if let attrRange = Range(range, in: attributed) {
            attributed[attrRange].font = .system(size: 13, weight: .bold)
        }
        searchRange = range.upperBound..<lowerText.endIndex
    }

    return attributed
}
