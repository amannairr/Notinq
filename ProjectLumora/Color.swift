//
//  Color.swift
//  ProjectLumora
//
//  Created by Aman Nair on 21/04/26.
//

import SwiftUI

extension Color {
    static let bgPrimary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.11, alpha: 1.0)
            : NSColor(calibratedRed: 0.985, green: 0.982, blue: 0.972, alpha: 1.0)
    })
    static let bgRail = Color(red: 0.31, green: 0.345, blue: 0.4)
    static let bgSidebar = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.18, green: 0.17, blue: 0.16, alpha: 1.0)
            : NSColor(calibratedRed: 0.94, green: 0.925, blue: 0.9, alpha: 1.0)
    })
    static let bgNotesPane = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.20, green: 0.19, blue: 0.18, alpha: 1.0)
            : NSColor(calibratedRed: 0.965, green: 0.955, blue: 0.935, alpha: 1.0)
    })
    static let bgEditor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.14, alpha: 1.0)
            : NSColor(calibratedRed: 0.988, green: 0.985, blue: 0.975, alpha: 1.0)
    })
    static let bgElevated = Color.white.opacity(0.38)

    static let textPrimary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.88, green: 0.87, blue: 0.85, alpha: 1.0)
            : NSColor(calibratedRed: 0.22, green: 0.21, blue: 0.19, alpha: 1.0)
    })
    static let textSecondary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.67, green: 0.65, blue: 0.62, alpha: 1.0)
            : NSColor(calibratedRed: 0.48, green: 0.46, blue: 0.42, alpha: 1.0)
    })
    static let textTertiary = Color.textSecondary.opacity(0.72)
    static let railIcon = Color.white.opacity(0.78)
    static let railIconActive = Color.white.opacity(0.9)

    static let accent = Color(red: 0.42, green: 0.45, blue: 0.42)
    static let accentSoft = Color(red: 0.42, green: 0.45, blue: 0.42).opacity(0.12)
    static let selectionWarm = Color.black.opacity(0.055)
    static let hoverWarm = Color.black.opacity(0.032)

    static let borderSubtle = Color.black.opacity(0.025)
}
