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
    @State private var toolbarContentWidth: CGFloat = 0
    @State private var toolbarScrollOffset: CGFloat = 0
    @State private var toolbarScrollView: NSScrollView?

    static let toolbarTooltipLabels: [String] = [
        "Text Style",
        "Font Family",
        "Font Size",
        "Line Spacing",
        "Bold",
        "Italic",
        "Underline",
        "Bullet List",
        "Numbered List",
        "Undo",
        "Redo",
        "Clear Formatting",
        "Generate Study Materials",
        "Open Learning Insights",
        "Update Knowledge Graph",
        "Ask AI",
        "Start Dictation"
    ]

    private let fontFamilies = NSFontManager.shared.availableFontFamilies.sorted()
    private let fontSizes: [CGFloat] = [13, 14, 15, 16, 18, 20, 24, 28]
    private let lineSpacingOptions: [(String, CGFloat)] = [
        ("Compact", 3.5),
        ("Comfort", 5.5),
        ("Open", 8.0)
    ]

    var body: some View {
        GeometryReader { proxy in
            let overflowButtonWidth: CGFloat = 34
            let viewportWidth = max(0, proxy.size.width - (overflowButtonWidth * 2))
            let contentWidth = toolbarContentWidth

            let showLeadingCue = Self.toolbarLeadingFadeVisible(
                horizontalOffset: toolbarScrollOffset
            )

            let showTrailingCue = Self.toolbarTrailingFadeVisible(
                contentWidth: contentWidth,
                viewportWidth: viewportWidth,
                horizontalOffset: toolbarScrollOffset
            )

            HStack(spacing: 0) {
                overflowButtonSlot(edge: .leading, isVisible: showLeadingCue)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        toolbarSection {
                            leadingToolbarControls
                        }

                        toolbarSection {
                            trailingToolbarControls
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 24)
                    .background(renderedToolbarWidthReader)
                    .background(horizontalOffsetReader(binding: $toolbarScrollOffset, scrollView: $toolbarScrollView))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

                overflowButtonSlot(edge: .trailing, isVisible: showTrailingCue)
            }
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
        }
    }

    @ViewBuilder
    private var leadingToolbarControls: some View {
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

        ToolbarButton(icon: "list.bullet", label: "Bullet List") {
            bridge?.insertBulletList()
        }

        ToolbarButton(icon: "list.number", label: "Numbered List") {
            bridge?.insertNumberedList()
        }

        Divider().frame(height: 16)

        ToolbarButton(icon: "arrow.uturn.backward", label: "Undo") {
            bridge?.undo()
        }

        ToolbarButton(icon: "arrow.uturn.forward", label: "Redo") {
            bridge?.redo()
        }

        Divider().frame(height: 16)

        ToolbarButton(icon: "eraser", label: "Clear Formatting") {
            bridge?.clearFormatting()
        }
    }

    @ViewBuilder
    private var trailingToolbarControls: some View {
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

    private func widthReader(binding: Binding<CGFloat>) -> some View {
        EmptyView()
    }

    static func toolbarOverflowAffordanceVisible(contentWidth: CGFloat, viewportWidth: CGFloat) -> Bool {
        contentWidth > viewportWidth + 1
    }

    static func toolbarTrailingFadeVisible(contentWidth: CGFloat, viewportWidth: CGFloat, horizontalOffset: CGFloat) -> Bool {
        guard toolbarOverflowAffordanceVisible(contentWidth: contentWidth, viewportWidth: viewportWidth) else {
            return false
        }

        return horizontalOffset + viewportWidth < contentWidth - 1
    }

    static func toolbarLeadingFadeVisible(horizontalOffset: CGFloat) -> Bool {
        horizontalOffset > 1
    }

    static func toolbarScrollTarget(
        currentOffset: CGFloat,
        contentWidth: CGFloat,
        viewportWidth: CGFloat,
        edge: HorizontalEdge
    ) -> CGFloat {
        let maxOffset = max(0, contentWidth - viewportWidth)
        guard maxOffset > 0 else { return 0 }

        let step = max(120, viewportWidth * 0.72)
        let proposedOffset: CGFloat
        switch edge {
        case .leading:
            proposedOffset = currentOffset - step
        case .trailing:
            proposedOffset = currentOffset + step
        }
        return min(max(0, proposedOffset), maxOffset)
    }

    private func toolbarOverflowButton(edge: HorizontalEdge) -> some View {
        Button {
            scrollToolbar(edge: edge)
        } label: {
            Image(systemName: edge == .leading ? "chevron.left" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.bgEditor.opacity(0.96))
                )
                .overlay(
                    Circle()
                        .stroke(Color.borderSubtle.opacity(0.35), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func overflowButtonSlot(edge: HorizontalEdge, isVisible: Bool) -> some View {
        ZStack {
            if isVisible {
                toolbarOverflowButton(edge: edge)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: 34, height: 34)
        .animation(.easeInOut(duration: 0.18), value: isVisible)
    }

    private func chevronFade(edge: ChevronDirection) -> some View {
        Image(systemName: edge == .left ? "chevron.left" : "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.textSecondary.opacity(0.82))
            .frame(width: 18, height: 18)
    }

    private func horizontalOffsetReader(binding: Binding<CGFloat>, scrollView: Binding<NSScrollView?>) -> some View {
        HorizontalScrollOffsetReader(offset: binding, scrollView: scrollView)
            .frame(width: 0, height: 0)
    }

    @ViewBuilder
    private func toolbarSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .fixedSize(horizontal: true, vertical: false)
    }

    private var renderedToolbarWidthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: ToolbarContentWidthPreferenceKey.self, value: proxy.size.width)
        }
        .onPreferenceChange(ToolbarContentWidthPreferenceKey.self) { newValue in
            if abs(toolbarContentWidth - newValue) > 0.5 {
                toolbarContentWidth = newValue
            }
        }
    }

    private func scrollToolbar(edge: HorizontalEdge) {
        guard let scrollView = toolbarScrollView else { return }

        let clipView = scrollView.contentView
        let visibleWidth = clipView.bounds.width
        let currentX = clipView.bounds.origin.x
        let contentWidth = scrollView.documentView?.bounds.width ?? 0
        let targetX = Self.toolbarScrollTarget(
            currentOffset: currentX,
            contentWidth: contentWidth,
            viewportWidth: visibleWidth,
            edge: edge
        )

        clipView.animator().setBoundsOrigin(NSPoint(x: targetX, y: clipView.bounds.origin.y))
        scrollView.reflectScrolledClipView(clipView)
    }
}

enum HorizontalEdge {
    case leading
    case trailing
}

private enum ChevronDirection {
    case left
    case right
}

private struct HorizontalScrollOffsetReader: NSViewRepresentable {
    @Binding var offset: CGFloat
    @Binding var scrollView: NSScrollView?

    func makeNSView(context: Context) -> OffsetTrackingView {
        let view = OffsetTrackingView()
        view.onOffsetChange = { offset in
            self.offset = offset
        }
        view.onScrollViewChange = { scrollView in
            self.scrollView = scrollView
        }
        return view
    }

    func updateNSView(_ nsView: OffsetTrackingView, context: Context) {
        nsView.onOffsetChange = { offset in
            self.offset = offset
        }
        nsView.onScrollViewChange = { scrollView in
            self.scrollView = scrollView
        }
    }
}

private struct ToolbarContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private final class OffsetTrackingView: NSView {
    var onOffsetChange: ((CGFloat) -> Void)?
    var onScrollViewChange: ((NSScrollView?) -> Void)?
    private weak var observedScrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installIfNeeded()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        installIfNeeded()
    }

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    private func installIfNeeded() {
        guard let scrollView = enclosingScrollView else { return }
        guard observedScrollView !== scrollView else { return }

        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }

        observedScrollView = scrollView
        onScrollViewChange?(scrollView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self, weak scrollView] _ in
            guard let self, let scrollView else { return }
            self.onOffsetChange?(scrollView.contentView.bounds.origin.x)
        }
        onOffsetChange?(scrollView.contentView.bounds.origin.x)
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
