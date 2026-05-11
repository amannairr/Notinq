//
//  EditorToolBar.swift
//  ProjectLumora
//
//  Created by Aman Nair on 20/04/26.
//

import SwiftUI
import AppKit

struct EditorTopBar: View {

    var bridge: TextViewBridge?
    @Binding var styleState: TextStyleState
    var onAskAI: () -> Void = {}
    @State private var isMicActive = false

    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
    private let fontSizes: [CGFloat] = [13, 14, 15, 16, 18, 20, 24, 28]
    private let lineSpacingOptions: [(String, CGFloat)] = [
        ("Compact", 3.5),
        ("Comfort", 5.5),
        ("Open", 8.0)
    ]

    var body: some View {
        HStack(spacing: 10) {

            // 🔤 TYPOGRAPHY DROPDOWN
            Menu {
                Button("Body") {
                    styleState.headingLevel = .body
                    bridge?.setBody()
                }

                Button("Subheading") {
                    styleState.headingLevel = .subheading
                    bridge?.setSubheading()
                }

                Button("Heading") {
                    styleState.headingLevel = .heading
                    bridge?.setHeading()
                }

            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "textformat")
                    Text(styleState.headingLevel.label)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.hoverWarm)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .help("Text Style")

            Menu {
                Button("System") {
                    styleState.fontFamily = "System"
                    bridge?.setFontFamily(".AppleSystemUIFont")
                }
                Divider()
                ForEach(fontFamilies, id: \.self) { family in
                    Button(family) {
                        styleState.fontFamily = family
                        bridge?.setFontFamily(family)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "textformat.size")
                    Text(styleState.fontFamily == "System" ? "System" : styleState.fontFamily)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(Color.textSecondary)
                .frame(maxWidth: 122)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.hoverWarm)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .help("Font Family")

            Menu {
                ForEach(fontSizes, id: \.self) { size in
                    Button("\(Int(size)) pt") {
                        styleState.fontSize = size
                        bridge?.setFontSize(size)
                    }
                }
            } label: {
                Text("\(Int(styleState.fontSize))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.textSecondary)
                    .frame(width: 34, height: 26)
                    .background(Color.hoverWarm)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .help("Font Size")

            Menu {
                ForEach(lineSpacingOptions, id: \.0) { option in
                    Button(option.0) {
                        styleState.lineSpacing = option.1
                        bridge?.setLineSpacing(option.1)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Color.hoverWarm)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .help("Line Spacing")

            Divider().frame(height: 16)

            // 🔠 INLINE STYLES (TOGGLE)
            ToolbarToggleButton(
                icon: "bold",
                isActive: styleState.isBold,
                label: "Bold"
            ) {
                bridge?.toggleBold()
            }

            ToolbarToggleButton(
                icon: "italic",
                isActive: styleState.isItalic,
                label: "Italic"
            ) {
                bridge?.toggleItalic()
            }

            ToolbarToggleButton(
                icon: "underline",
                isActive: styleState.isUnderline,
                label: "Underline"
            ) {
                bridge?.toggleUnderline()
            }

            Divider().frame(height: 16)

            // 📋 LISTS
            ToolbarButton(icon: "list.bullet", label: "Bullet List") {
                bridge?.insertBulletList()
            }

            ToolbarButton(icon: "list.number", label: "Numbered List") {
                bridge?.insertNumberedList()
            }

            Divider().frame(height: 16)

            // 🔄 UNDO / REDO
            ToolbarButton(icon: "arrow.uturn.backward", label: "Undo") {
                bridge?.undo()
            }

            ToolbarButton(icon: "arrow.uturn.forward", label: "Redo") {
                bridge?.redo()
            }

            Divider().frame(height: 16)

            // 🧹 CLEAR
            ToolbarButton(icon: "eraser", label: "Clear Formatting") {
                bridge?.clearFormatting()
            }

            Spacer()

            // ✨ AI
            ToolbarButton(icon: "sparkles", label: "Ask AI") {
                onAskAI()
            }

            ToolbarToggleButton(
                icon: isMicActive ? "mic.fill" : "mic",
                isActive: isMicActive,
                label: isMicActive ? "Stop Dictation" : "Start Dictation"
            ) {
                if isMicActive {
                    bridge?.stopLiveTranscription()
                    isMicActive = false
                } else {
                    isMicActive = bridge?.startLiveTranscription(modelPath: "Models/ggml-base.en.bin") ?? false
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .background(Color.bgEditor.opacity(0.72))
        .onDisappear {
            if isMicActive {
                bridge?.stopLiveTranscription()
                isMicActive = false
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if let event = NSApp.currentEvent {
                        NSApp.keyWindow?.performDrag(with: event)
                    }
                }
        )
    }
}

// MARK: - REAL BUTTON
struct ToolbarButton: View {

    let icon: String
    let label: String
    let action: () -> Void

    @State private var hover = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.textSecondary)
                .frame(width: 26, height: 26)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .scaleEffect(isPressed ? 0.96 : 1.0)
                .animation(.easeInOut(duration: 0.14), value: hover)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover = $0 }
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .help(label) // ✅ works now
    }

    private var backgroundColor: Color {
        if isPressed {
            return Color.black.opacity(0.07)
        } else if hover {
            return Color.hoverWarm
        } else {
            return Color.clear
        }
    }
}
