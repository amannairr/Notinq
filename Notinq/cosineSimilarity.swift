//
//  cosineSimilarity.swift
//  Notinq
//
//  Created by Aman Nair on 01/05/26.
//

import Foundation

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    let dot = zip(a, b).map(*).reduce(0, +)
    let magA = sqrt(a.map { $0 * $0 }.reduce(0, +))
    let magB = sqrt(b.map { $0 * $0 }.reduce(0, +))
    let denominator = magA * magB
    guard denominator > 0 else { return 0 }
    return dot / denominator
}
