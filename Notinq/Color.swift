//
//  Color.swift
//  Notinq
//
//  Created by Aman Nair on 21/04/26.
//

import SwiftUI
import AppKit

extension Color {
    static let bgPrimary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.105, green: 0.112, blue: 0.122, alpha: 1.0)
            : NSColor(calibratedRed: 0.922, green: 0.922, blue: 0.922, alpha: 1.0)
    })
    static let bgRail = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.115, green: 0.127, blue: 0.145, alpha: 0.96)
            : NSColor(calibratedRed: 0.380, green: 0.427, blue: 0.502, alpha: 0.96)
    })
    static let bgSidebar = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.145, green: 0.144, blue: 0.138, alpha: 0.93)
            : NSColor(calibratedRed: 0.949, green: 0.945, blue: 0.933, alpha: 0.96)
    })
    static let bgNotesPane = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.196, green: 0.202, blue: 0.200, alpha: 0.98)
            : NSColor(calibratedRed: 0.922, green: 0.922, blue: 0.922, alpha: 0.98)
    })
    static let bgEditor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.128, green: 0.132, blue: 0.136, alpha: 1.0)
            : NSColor(calibratedRed: 0.988, green: 0.988, blue: 0.988, alpha: 1.0)
    })
    static let studySurface = Color(nsColor: .controlBackgroundColor)
    static let studySurfaceRaised = Color(nsColor: .textBackgroundColor)
    static let studySurfaceMuted = Color(nsColor: .underPageBackgroundColor)
    static let studyBorder = Color(nsColor: .separatorColor)
    static let studyBorderSoft = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1.0, alpha: 0.14)
            : NSColor(calibratedWhite: 0.0, alpha: 0.05)
    })
    static let graphSurface = Color(nsColor: .windowBackgroundColor)
    static let graphSurfaceRaised = Color(nsColor: .textBackgroundColor)
    static let graphSurfaceMuted = Color(nsColor: .controlBackgroundColor)
    static let graphBorderSoft = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1.0, alpha: 0.12)
            : NSColor(calibratedWhite: 0.0, alpha: 0.06)
    })
    static let bgElevated = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1.0, alpha: 0.055)
            : NSColor(calibratedWhite: 1.0, alpha: 0.62)
    })
    static let noteCard = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.238, green: 0.244, blue: 0.240, alpha: 0.84)
            : NSColor(calibratedRed: 0.973, green: 0.973, blue: 0.973, alpha: 0.98)
    })
    static let noteCardSelected = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.280, green: 0.292, blue: 0.286, alpha: 0.92)
            : NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.996, alpha: 1.0)
    })
    static let noteCardStroke = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1.0, alpha: 0.10)
            : NSColor(calibratedWhite: 1.0, alpha: 0.62)
    })

    static let textPrimary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.88, green: 0.87, blue: 0.85, alpha: 1.0)
            : NSColor(calibratedRed: 0.216, green: 0.216, blue: 0.216, alpha: 1.0)
    })
    static let textSecondary = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.67, green: 0.65, blue: 0.62, alpha: 1.0)
            : NSColor(calibratedRed: 0.471, green: 0.471, blue: 0.471, alpha: 1.0)
    })
    static let textTertiary = Color.textSecondary.opacity(0.72)
    static let railIcon = Color.white.opacity(0.78)
    static let railIconActive = Color.white
    static let modebarBG = Color(red: 0.227, green: 0.514, blue: 0.592) // #3a8397

    static let accent = Color(red: 0.38, green: 0.45, blue: 0.48)
    static let accentSoft = Color(red: 0.38, green: 0.45, blue: 0.48).opacity(0.13)
    static let selectionWarm = Color.black.opacity(0.06)
    static let hoverWarm = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1.0, alpha: 0.055)
            : NSColor(calibratedWhite: 0.0, alpha: 0.045)
    })

    static let borderSubtle = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1.0, alpha: 0.12)
            : NSColor(calibratedWhite: 0.0, alpha: 0.07)
    })

    static func resolvedNotesPaneBackground(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.196, green: 0.202, blue: 0.200, alpha: 0.98)
            : NSColor(calibratedRed: 0.922, green: 0.922, blue: 0.922, alpha: 0.98)
    }

    static func resolvedStudySurface(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.18, alpha: 1.0)
            : NSColor(calibratedWhite: 0.95, alpha: 1.0)
    }

    static func resolvedStudySurfaceRaised(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.22, alpha: 1.0)
            : NSColor(calibratedWhite: 0.98, alpha: 1.0)
    }

    static func resolvedStudySurfaceMuted(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.24, alpha: 1.0)
            : NSColor(calibratedWhite: 0.97, alpha: 1.0)
    }

    static func resolvedStudyBorderSoft(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1.0, alpha: 0.14)
            : NSColor(calibratedWhite: 0.0, alpha: 0.05)
    }

    static func resolvedGraphSurface(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.18, alpha: 1.0)
            : NSColor(calibratedWhite: 0.985, alpha: 1.0)
    }

    static func resolvedGraphSurfaceRaised(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.23, alpha: 1.0)
            : NSColor(calibratedWhite: 1.0, alpha: 1.0)
    }

    static func resolvedGraphSurfaceMuted(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.21, alpha: 1.0)
            : NSColor(calibratedWhite: 0.96, alpha: 1.0)
    }

    static func resolvedGraphBorderSoft(for appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1.0, alpha: 0.12)
            : NSColor(calibratedWhite: 0.0, alpha: 0.06)
    }
}
