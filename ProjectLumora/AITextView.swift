//
//  AITextView.swift
//  ProjectLumora
//
//  Created by Aman Nair on 01/05/26.
//

import SwiftUI
import AppKit

struct AITextView: NSViewRepresentable {
    
    @Binding var text: String
    var onSelectionChange: ((String, NSRange) -> Void)?
    
    var onReady: ((TextViewBridge) -> Void)?
    
    var onSummarize: (() -> Void)?
    var onRewrite: (() -> Void)?
    var onExplain: (() -> Void)?
    var onAdd: (() -> Void)?
    var onStyleChange: ((TextStyleState) -> Void)?
    var onAIBlockFollowUp: ((AIBlockFollowUp, AIBlockSelection) -> Void)?
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        let textView = AIBlockTextView()
        textView.allowsUndo = true

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesRuler = false
        textView.importsGraphics = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor(calibratedRed: 0.22, green: 0.21, blue: 0.19, alpha: 1.0)
        textView.backgroundColor = .clear
        textView.insertionPointColor = NSColor(calibratedRed: 0.30, green: 0.29, blue: 0.26, alpha: 1.0)
        textView.drawsBackground = false
        
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        textView.textContainerInset = NSSize(width: 0, height: 34)
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true
        
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        
        textView.textContainer?.widthTracksTextView = true
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 5.5
        paragraphStyle.paragraphSpacing = 10
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        textView.typingAttributes[.foregroundColor] = textView.textColor
        textView.defaultParagraphStyle = paragraphStyle

        scrollView.documentView = textView
        
        DispatchQueue.main.async {
            context.coordinator.bridge.textView = textView
            onReady?(context.coordinator.bridge)
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            configureReadingColumn(for: nsView, textView: textView)

            // Prevent SwiftUI state reconciliation from overwriting live streamed output.
            if context.coordinator.bridge.isAIStreamingActive {
                return
            }
            if textView.string != text {
                let selectedRange = textView.selectedRange()
                textView.string = text
                let length = (textView.string as NSString).length
                let safeLocation = min(selectedRange.location, length)
                textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, NSTextViewDelegate {
        
        var parent: AITextView
        let bridge = TextViewBridge()
        var selectionToolbar: NSView?
        var aiBlockActions: NSView?
        
        init(_ parent: AITextView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            bridge.textView = tv
            
            let range = tv.selectedRange()
            let style = bridge.getTextStyleState()
            parent.onStyleChange?(style)
            guard range.length > 0 else {
                hideToolbar()
                showAIBlockActionsIfNeeded(for: tv)
                parent.onSelectionChange?("", range)
                return
            }

            hideAIBlockActions()
            if let stringRange = Range(range, in: tv.string) {
                let selectedText = String(tv.string[stringRange])
                parent.onSelectionChange?(selectedText, range)
            }

            showSelectionToolbar(for: tv)
        }

        // DO NOT CHANGE EVER
        func hideToolbar() {
            selectionToolbar?.removeFromSuperview()
            selectionToolbar = nil
        }

        func hideAIBlockActions() {
            aiBlockActions?.removeFromSuperview()
            aiBlockActions = nil
        }

        // DO NOT CHANGE EVER
        func showSelectionToolbar(for textView: NSTextView) {
            selectionToolbar?.removeFromSuperview()

            let range = textView.selectedRange()
            guard range.length > 0 else { return }

            let selectionRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            let rectInWindow = textView.window?.convertFromScreen(selectionRect) ?? .zero
            let rectInTextView = textView.convert(rectInWindow, from: nil)

            let hosting = NSHostingView(
                rootView: SelectionToolbarView(
                    onSummarize: { self.parent.onSummarize?() },
                    onRewrite: { self.parent.onRewrite?() },
                    onExplain: { self.parent.onExplain?() },
                    onAdd: { self.parent.onAdd?() }
                )
            )

            hosting.layoutSubtreeIfNeeded()
            let fittingSize = hosting.fittingSize
            let toolbarWidth = max(160, fittingSize.width)
            let toolbarHeight = max(40, fittingSize.height)
            hosting.frame.size = NSSize(width: toolbarWidth, height: toolbarHeight)

            let horizontalPadding: CGFloat = 8
            var originX = rectInTextView.maxX - (toolbarWidth * 0.35)
            originX = max(horizontalPadding, min(textView.bounds.width - toolbarWidth - horizontalPadding, originX))

            var originY = rectInTextView.minY - toolbarHeight - 8
            if originY < 8 {
                originY = rectInTextView.maxY + 8
            }

            hosting.frame.origin = CGPoint(x: originX, y: originY)
            textView.addSubview(hosting)
            selectionToolbar = hosting
        }

        func showAIBlockActionsIfNeeded(for textView: NSTextView) {
            hideAIBlockActions()

            let cursor = textView.selectedRange().location
            guard let block = bridge.aiBlockSelection(containing: cursor) else { return }

            let hosting = NSHostingView(
                rootView: AIBlockInlineActionsView { followUp in
                    self.parent.onAIBlockFollowUp?(followUp, block)
                    self.hideAIBlockActions()
                }
            )

            hosting.layoutSubtreeIfNeeded()
            let fittingSize = hosting.fittingSize
            let actionWidth = max(260, fittingSize.width)
            let actionHeight = max(30, fittingSize.height)
            hosting.frame.size = NSSize(width: actionWidth, height: actionHeight)

            let blockRect = textView.firstRect(forCharacterRange: block.fullRange, actualRange: nil)
            let rectInWindow = textView.window?.convertFromScreen(blockRect) ?? .zero
            let rectInTextView = textView.convert(rectInWindow, from: nil)

            let horizontalPadding: CGFloat = 12
            let maxX = max(horizontalPadding, textView.bounds.width - actionWidth - horizontalPadding)
            let originX = min(max(horizontalPadding, rectInTextView.minX + 14), maxX)
            let originY = max(8, rectInTextView.maxY + 5)

            hosting.frame.origin = CGPoint(x: originX, y: originY)
            textView.addSubview(hosting)
            aiBlockActions = hosting
        }
        
        func textDidBeginEditing(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            bridge.textView = tv
        }
    }

    private func configureReadingColumn(for scrollView: NSScrollView, textView: NSTextView) {
        guard let textContainer = textView.textContainer else { return }

        let availableWidth = max(0, scrollView.contentSize.width)
        let outerInset: CGFloat = 26
        let minReadable: CGFloat = 720
        let maxReadable: CGFloat = 820

        let usableWidth = max(0, availableWidth - (outerInset * 2))
        let targetWidth = min(maxReadable, max(minReadable, usableWidth))
        let centeredInset = max(outerInset, (availableWidth - targetWidth) * 0.5)

        if abs(textContainer.containerSize.width - targetWidth) > 0.5 {
            textContainer.containerSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        if abs(textView.textContainerInset.width - centeredInset) > 0.5 {
            textView.textContainerInset = NSSize(width: centeredInset, height: 34)
        }
    }
}

struct AIBlockInlineActionsView: View {
    let action: (AIBlockFollowUp) -> Void
    @State private var visible = false

    var body: some View {
        HStack(spacing: 4) {
            inlineButton(.regenerate)
            inlineButton(.shorter)
            inlineButton(.moreDetailed)
            inlineButton(.continueWriting)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.thinMaterial)
        .background(Color.bgEditor.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.borderSubtle.opacity(0.7), lineWidth: 0.5)
        )
        .opacity(visible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.16)) {
                visible = true
            }
        }
    }

    private func inlineButton(_ followUp: AIBlockFollowUp) -> some View {
        Button(followUp.title) {
            action(followUp)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(Color.textSecondary)
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

final class AIBlockTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        drawAIBlockBackgrounds()
        super.draw(dirtyRect)
    }

    private func drawAIBlockBackgrounds() {
        guard let storage = textStorage,
              let layoutManager,
              let textContainer,
              storage.length > 0 else { return }

        var drawnBlockIDs = Set<String>()
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.enumerateAttribute(.aiBlockID, in: fullRange) { value, range, _ in
            guard let blockID = value as? String,
                  !drawnBlockIDs.contains(blockID) else { return }
            drawnBlockIDs.insert(blockID)

            let blockRange = self.fullRangeForBlock(id: blockID, in: storage)
            guard blockRange.length > 0 else { return }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: blockRange, actualCharacterRange: nil)
            var blockRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            blockRect.origin.x += textContainerOrigin.x - 10
            blockRect.origin.y += textContainerOrigin.y - 5
            blockRect.size.width += 20
            blockRect.size.height += 10

            NSColor(calibratedRed: 0.93, green: 0.91, blue: 0.86, alpha: 0.28).setFill()
            NSBezierPath(roundedRect: blockRect, xRadius: 8, yRadius: 8).fill()
        }
    }

    private func fullRangeForBlock(id blockID: String, in storage: NSTextStorage) -> NSRange {
        var lower: Int?
        var upper: Int?
        storage.enumerateAttribute(.aiBlockID, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard (value as? String) == blockID else { return }
            lower = min(lower ?? range.location, range.location)
            upper = max(upper ?? range.upperBound, range.upperBound)
        }

        guard let lower, let upper else { return NSRange(location: 0, length: 0) }
        return NSRange(location: lower, length: upper - lower)
    }
}
