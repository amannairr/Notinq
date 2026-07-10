//
//  EditorToolBar.swift
//  Notinq
//
//  Created by Aman Nair on 20/04/26.
//

import SwiftUI
import AppKit

struct EditorTopBar: View {

    var bridge: TextViewBridge?
    @Binding var styleState: TextStyleState
    var onAskAI: () -> Void = {}
    var onGenerateStudyMaterials: () -> Void = {}
    var onAnalyzeLecture: () -> Void = {}
    var onUpdateKnowledgeGraph: () -> Void = {}
    var isGeneratingStudyMaterials: Bool = false
    var isKnowledgeGraphGenerating: Bool = false
    var canGenerateStudyMaterials: Bool = true
    var canUpdateKnowledgeGraph: Bool = true
    @State private var isMicActive = false

    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
    private let fontSizes: [CGFloat] = [13, 14, 15, 16, 18, 20, 24, 28]
    private let lineSpacingOptions: [(String, CGFloat)] = [
        ("Compact", 3.5),
        ("Comfort", 5.5),
        ("Open", 8.0)
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {

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
                .toolbarTooltip("Text Style")

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
                .toolbarTooltip("Font Family")

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
                .toolbarTooltip("Font Size")

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
                .toolbarTooltip("Line Spacing")

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

                Spacer(minLength: 0)

                // ✨ AI
                Button(action: onGenerateStudyMaterials) {
                    HStack(spacing: 7) {
                        if isGeneratingStudyMaterials {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "book.pages")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(isGeneratingStudyMaterials ? "Generating..." : "Generate Study Materials")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(canGenerateStudyMaterials ? Color.white : Color.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Group {
                            if canGenerateStudyMaterials {
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.24, green: 0.49, blue: 0.59),
                                        Color(red: 0.30, green: 0.62, blue: 0.53)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            } else {
                                Color.hoverWarm
                            }
                        }
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingStudyMaterials)
                .toolbarTooltip("Generate Study Materials")

                Button(action: onAnalyzeLecture) {
                    HStack(spacing: 7) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Analyze Lecture")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.49, blue: 0.86),
                                Color(red: 0.27, green: 0.62, blue: 0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canGenerateStudyMaterials)
                .toolbarTooltip("Open Learning Insights")

                Button(action: onUpdateKnowledgeGraph) {
                    HStack(spacing: 7) {
                        if isKnowledgeGraphGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "circle.grid.2x2")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(isKnowledgeGraphGenerating ? "Updating..." : "Update Graph")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(canUpdateKnowledgeGraph ? Color.white : Color.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Group {
                            if canUpdateKnowledgeGraph {
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.27, green: 0.43, blue: 0.55),
                                        Color(red: 0.34, green: 0.56, blue: 0.68)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            } else {
                                Color.hoverWarm
                            }
                        }
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isKnowledgeGraphGenerating || !canUpdateKnowledgeGraph)
                .toolbarTooltip("Update Knowledge Graph")

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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .background(Color.bgEditor.opacity(0.92))
        .clipShape(Rectangle())
        .shadow(color: .black.opacity(0.018), radius: 8, x: 0, y: 4)
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
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            hover
                            ? Color.borderSubtle.opacity(0.7)
                            : Color.clear,
                            lineWidth: 0.5
                        )
                )
                .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)

        .overlay(alignment: .top) {

            if hover {
                tooltip
                    .offset(y: -38)
                    .allowsHitTesting(false)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.96)
                        )
                    )
                    .zIndex(1000)
            }
        }

        .onHover { hovering in
            withAnimation(
                .spring(
                    response: 0.18,
                    dampingFraction: 0.82
                )
            ) {
                hover = hovering
            }
        }

        .onLongPressGesture(
            minimumDuration: 0,
            pressing: { pressing in
                isPressed = pressing
            },
            perform: {}
        )

        .animation(
            .spring(
                response: 0.18,
                dampingFraction: 0.82
            ),
            value: hover
        )
    }

    private var backgroundColor: Color {
        if isPressed {
            return Color.black.opacity(0.07)
        } else if hover {
            return Color.bgElevated
        } else {
            return Color.clear
        }
    }

    private var tooltip: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.92))
            .fixedSize() // IMPORTANT
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        Color.white.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: .black.opacity(0.18),
                radius: 10,
                x: 0,
                y: 4
            )
    }
}

extension View {

    func toolbarTooltip(_ text: String) -> some View {
        modifier(ToolbarTooltip(text: text))
    }
}
