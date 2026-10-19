//
//  TextViewBridge.swift
//  Notinq
//
//  Created by Aman Nair on 02/05/26.
//

import AppKit
import AVFoundation
import Foundation

struct TextStyleState {
    var isBold: Bool = false
    var isItalic: Bool = false
    var isUnderline: Bool = false
    var headingLevel: HeadingLevel = .body
    var fontFamily: String = "System"
    var fontSize: CGFloat = 16
    var lineSpacing: CGFloat = 5.5
}

enum HeadingLevel {
    case body, subheading, heading
}

enum AIBlockFollowUp {
    case regenerate
    case shorter
    case moreDetailed
    case continueWriting

    var title: String {
        switch self {
        case .regenerate: return "Regenerate"
        case .shorter: return "Shorter"
        case .moreDetailed: return "More detailed"
        case .continueWriting: return "Continue writing"
        }
    }
}

struct AIBlockSelection {
    let id: String
    let actionTitle: String
    let content: String
    let fullRange: NSRange
    let contentRange: NSRange
    let sourceInfo: AIBlockSourceInfo?
}

extension NSAttributedString.Key {
    static let aiBlockID = NSAttributedString.Key("NotinqAIBlockID")
    static let aiBlockRole = NSAttributedString.Key("NotinqAIBlockRole")
    static let aiBlockActionTitle = NSAttributedString.Key("NotinqAIBlockActionTitle")
    static let aiBlockInsertedAt = NSAttributedString.Key("NotinqAIBlockInsertedAt")
    static let aiBlockActionRawValue = NSAttributedString.Key("NotinqAIBlockActionRawValue")
    static let aiBlockCreatedAt = NSAttributedString.Key("NotinqAIBlockCreatedAt")
    static let aiBlockSourceReference = NSAttributedString.Key("NotinqAIBlockSourceReference")
}

extension HeadingLevel {
    var label: String {
        switch self {
        case .body: return "Body"
        case .subheading: return "Subheading"
        case .heading: return "Heading"
        }
    }
}

class TextViewBridge {

    weak var textView: NSTextView?
    private var whisperManager: WhisperManager?
    private var transcriptionEngine: TranscriptionEngine?
    private var audioStreamManager: AudioStreamManager?
    private var editorInsertionManager: EditorInsertionManager?
    private var isLiveTranscribing = false
    private var llamaNotificationToken: NSObjectProtocol?
    var isAIStreamingActive: Bool {
        false
    }

    init() {
        llamaNotificationToken = NotificationCenter.default.addObserver(
            forName: .notinqAIWillUseLlama,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopLiveTranscription()
        }
    }

    deinit {
        if let token = llamaNotificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - FOCUS

    func focus() {
        textView?.window?.makeFirstResponder(textView)
    }
    
    // MARK: - Text Style State
    func getTextStyleState() -> TextStyleState {
        guard let tv = textView else { return TextStyleState() }

        let range = tv.selectedRange()
        guard !tv.string.isEmpty else { return TextStyleState() }

        let index = range.length > 0 ? range.location : max(range.location - 1, 0)
        guard index < tv.string.count else { return TextStyleState() }

        guard let attributes = tv.textStorage?.attributes(at: index, effectiveRange: nil) else {
            return TextStyleState()
        }

        var state = TextStyleState()

        if let font = attributes[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            state.isBold = traits.contains(.boldFontMask)
            state.isItalic = traits.contains(.italicFontMask)
            state.fontFamily = font.familyName ?? font.fontName
            state.fontSize = font.pointSize

            let size = font.pointSize
            if size >= 22 {
                state.headingLevel = .heading
            } else if size >= 17 {
                state.headingLevel = .subheading
            } else {
                state.headingLevel = .body
            }
        }

        if attributes[.underlineStyle] != nil {
            state.isUnderline = true
        }

        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            state.lineSpacing = paragraphStyle.lineSpacing
        }

        return state
    }

    func applyTypingAttributes(font: NSFont? = nil, underline: Bool? = nil) {
        guard let tv = textView else { return }

        var attrs = tv.typingAttributes

        if let font {
            attrs[.font] = font
        }

        if let underline {
            if underline {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                attrs.removeValue(forKey: .underlineStyle)
            }
        }

        tv.typingAttributes = attrs
    }
    
    // MARK: - SELECTION RECT (FIXED)

    /// Returns selection rect in WINDOW coordinates (correct base for UI)
    func getSelectionRect() -> CGRect? {
        guard let tv = textView else { return nil }

        let range = tv.selectedRange()
        guard range.length > 0 else { return nil }

        return tv.firstRect(forCharacterRange: range, actualRange: nil)
    }

    // MARK: - UNDO / REDO (FIXED)

    func undo() {
        guard let tv = textView else { return }
        focus()
        tv.undoManager?.undo()
    }

    func redo() {
        guard let tv = textView else { return }
        focus()
        tv.undoManager?.redo()
    }

    // MARK: - INSERTION (UNDO SAFE)

    func insertBelowSelection(_ text: String) {
        guard let tv = textView,
              let storage = tv.textStorage else { return }

        focus()

        let range = tv.selectedRange()
        let insertionIndex = range.location + range.length

        let prefix = insertionIndex > 0 ? "\n\n" : ""
        let insertionText = prefix + text

        let attributed = NSAttributedString(
            string: insertionText,
            attributes: tv.typingAttributes
        )

        storage.beginEditing()
        storage.replaceCharacters(
            in: NSRange(location: insertionIndex, length: 0),
            with: attributed
        )
        storage.endEditing()

        let cursor = insertionIndex + attributed.length
        tv.setSelectedRange(NSRange(location: cursor, length: 0))
        tv.didChangeText()
    }

    func selectedTextAndRange() -> (text: String, range: NSRange)? {
        guard let tv = textView else { return nil }
        let range = tv.selectedRange()
        guard range.length > 0 else { return nil }
        let selected = (tv.string as NSString).substring(with: range)
        let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (trimmed, range)
    }

    func selectedTextOrDocumentContext(fallback: String) -> (text: String, range: NSRange) {
        if let selection = selectedTextAndRange() {
            return selection
        }

        guard let tv = textView else {
            let text = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text, NSRange(location: (fallback as NSString).length, length: 0))
        }

        let document = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = document.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : document
        let insertionLocation = tv.selectedRange().location
        return (context, NSRange(location: insertionLocation, length: 0))
    }

    func aiBlockSelection(containing location: Int) -> AIBlockSelection? {
        guard let tv = textView,
              let storage = tv.textStorage,
              storage.length > 0 else { return nil }

        let index = min(max(location, 0), storage.length - 1)
        let attributes = storage.attributes(at: index, effectiveRange: nil)
        let blockID = attributes[.aiBlockID] as? String
            ?? (index > 0 ? storage.attributes(at: index - 1, effectiveRange: nil)[.aiBlockID] as? String : nil)
        guard let blockID else { return nil }

        let fullRange = fullRangeForAIBlock(id: blockID, in: storage)
        guard fullRange.length > 0 else { return nil }

        let contentRange = contentRangeForAIBlock(id: blockID, in: storage, within: fullRange)
        guard contentRange.length > 0 else { return nil }

        let content = (tv.string as NSString)
            .substring(with: contentRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let title = actionTitleForAIBlock(id: blockID, in: storage, within: fullRange)
        return AIBlockSelection(
            id: blockID,
            actionTitle: title,
            content: content,
            fullRange: fullRange,
            contentRange: contentRange,
            sourceInfo: sourceInfoForAIBlock(id: blockID, in: storage, within: fullRange)
        )
    }

    func makeAIProposal(
        action: AIEditorAction,
        response: String,
        selectionRange: NSRange,
        originatingNoteID: UUID? = nil,
        originatingRequestID: UUID = UUID(),
        documentSnapshot: DocumentSnapshot? = nil,
        provenance: AIProposalProvenance = AIProposalProvenance(),
        adaptiveExplanationContext: AdaptiveExplanationContext? = nil
    ) -> AIProposal? {
        guard let tv = textView, let storage = tv.textStorage else { return nil }
        let cleaned = Self.cleanGeneratedText(response)
        guard !cleaned.isEmpty else { return nil }

        let clampedSelection = clampedRange(selectionRange, textLength: storage.length)
        let originalText = clampedSelection.length > 0
            ? (tv.string as NSString).substring(with: clampedSelection)
            : ""
        let insertionIndex = safeInsertionIndex(after: clampedSelection, textLength: storage.length)
        tv.setSelectedRange(clampedSelection)

        return AIProposal(
            action: action,
            originalText: originalText,
            generatedText: cleaned,
            insertionRange: NSRange(location: insertionIndex, length: 0),
            originalSelectionRange: clampedSelection,
            originatingNoteID: originatingNoteID,
            originatingRequestID: originatingRequestID,
            documentSnapshot: documentSnapshot,
            provenance: provenance,
            adaptiveExplanationContext: adaptiveExplanationContext,
            state: .ready
        )
    }

    func acceptAIProposal(_ proposal: AIProposal, editedText: String? = nil) -> AIProposal {
        var accepted = proposal
        let content = TextViewBridge.cleanGeneratedText(editedText ?? proposal.generatedText)
        guard let tv = textView,
              let storage = tv.textStorage,
              !content.isEmpty else {
            return accepted
        }

        let insertionIndex = min(max(0, proposal.insertionLocation), storage.length)
        insertAIBlock(
            actionTitle: proposal.action.blockTitle,
            action: proposal.action,
            content: content,
            insertionIndex: insertionIndex,
            preserveSelection: proposal.originalSelectionRange,
            sourceReference: SourceReference(proposal: proposal),
            createdAt: proposal.createdAt
        )

        accepted.generatedText = content
        accepted.status = editedText == nil ? .accepted : .edited
        accepted.state = .accepted
        return accepted
    }

    func editAIProposal(_ proposal: AIProposal, generatedText: String) -> AIProposal {
        var edited = proposal
        edited.generatedText = generatedText
        edited.status = .edited
        if edited.state != .stale {
            edited.state = .ready
        }
        return edited
    }

    func rejectAIProposal(_ proposal: AIProposal) -> AIProposal {
        var rejected = proposal
        rejected.status = .rejected
        rejected.state = .rejected
        return rejected
    }

    func restoreSelection(for proposal: AIProposal) {
        guard let tv = textView,
              let storage = tv.textStorage else { return }
        let restoredSelection = clampedRange(proposal.originalSelectionRange, textLength: storage.length)
        tv.setSelectedRange(restoredSelection)
        tv.scrollRangeToVisible(restoredSelection)
    }

    private func insertAIBlock(
        actionTitle: String,
        action: AIEditorAction?,
        content: String,
        insertionIndex: Int,
        preserveSelection: NSRange?,
        sourceReference: SourceReference? = nil,
        createdAt: Date = Date()
    ) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let blockID = UUID().uuidString
        let insertString = makeAIBlock(
            actionTitle: actionTitle,
            action: action,
            blockID: blockID,
            content: content,
            leadingSpacing: leadingSpacing(at: insertionIndex, in: tv.string),
            trailingSpacing: "\n",
            sourceReference: sourceReference,
            createdAt: createdAt
        )
        let insertionRange = NSRange(location: insertionIndex, length: 0)
        let undoManager = tv.undoManager
        undoManager?.disableUndoRegistration()
        guard tv.shouldChangeText(in: insertionRange, replacementString: insertString.string) else {
            undoManager?.enableUndoRegistration()
            return
        }

        let previousText = NSAttributedString(attributedString: storage)
        let previousSelection = tv.selectedRange()
        storage.beginEditing()
        storage.replaceCharacters(in: insertionRange, with: insertString)
        storage.endEditing()
        markRecentInsertion(in: tv, range: NSRange(location: insertionIndex, length: insertString.length))
        undoManager?.enableUndoRegistration()

        let cursor = insertionIndex + insertString.length - 1
        if let preserveSelection {
            let restoredSelection = clampedRange(preserveSelection, textLength: storage.length)
            tv.setSelectedRange(restoredSelection)
        } else {
            tv.setSelectedRange(NSRange(location: cursor, length: 0))
        }
        registerUndoForAIBlockInsertion(
            in: tv,
            previousText: previousText,
            previousSelection: previousSelection
        )
        tv.didChangeText()
        tv.scrollRangeToVisible(NSRange(location: max(0, cursor - 1), length: 1))
    }

    private func registerUndoForAIBlockInsertion(
        in textView: NSTextView,
        previousText: NSAttributedString,
        previousSelection: NSRange
    ) {
        guard let undoManager = textView.undoManager else { return }
        let currentText = NSAttributedString(attributedString: textView.attributedString())
        let currentSelection = textView.selectedRange()
        undoManager.registerUndo(withTarget: textView) { target in
            guard let storage = target.textStorage else { return }
            target.setSelectedRange(NSRange(location: 0, length: 0))
            storage.beginEditing()
            storage.setAttributedString(previousText)
            storage.endEditing()
            target.setSelectedRange(self.clampedRange(previousSelection, textLength: storage.length))
            target.didChangeText()
            target.undoManager?.registerUndo(withTarget: target) { redoTarget in
                guard let redoStorage = redoTarget.textStorage else { return }
                redoTarget.setSelectedRange(NSRange(location: 0, length: 0))
                redoStorage.beginEditing()
                redoStorage.setAttributedString(currentText)
                redoStorage.endEditing()
                redoTarget.setSelectedRange(self.clampedRange(currentSelection, textLength: redoStorage.length))
                redoTarget.didChangeText()
            }
        }
        undoManager.setActionName("Insert AI Proposal")
        if textView.window == nil {
            while undoManager.groupingLevel > 0 {
                undoManager.endUndoGrouping()
            }
        }
    }

    // MARK: - AI BLOCK FORMATTING

    private func makeAIBlock(
        actionTitle: String,
        action: AIEditorAction?,
        blockID: String,
        content: String,
        leadingSpacing: String,
        trailingSpacing: String,
        sourceReference: SourceReference?,
        createdAt: Date
    ) -> NSAttributedString {
        let block = NSMutableAttributedString()
        block.append(
            makeAIBlockHeader(
                actionTitle: actionTitle,
                action: action,
                blockID: blockID,
                leadingSpacing: leadingSpacing,
                sourceReference: sourceReference,
                createdAt: createdAt
            )
        )
        block.append(
            renderMarkdownContent(
                content,
                blockID: blockID,
                action: action,
                actionTitle: actionTitle,
                sourceReference: sourceReference,
                createdAt: createdAt
            )
        )
        block.append(NSAttributedString(string: trailingSpacing, attributes: normalTypingAttributes()))
        return block
    }

    private func makeAIBlockHeader(
        actionTitle: String,
        action: AIEditorAction?,
        blockID: String,
        leadingSpacing: String,
        sourceReference: SourceReference?,
        createdAt: Date
    ) -> NSAttributedString {
        let block = NSMutableAttributedString()
        if !leadingSpacing.isEmpty {
            block.append(NSAttributedString(string: leadingSpacing, attributes: normalTypingAttributes()))
        }

        block.append(
            aiGeneratedBadge(
                actionTitle: actionTitle,
                action: action,
                blockID: blockID,
                sourceReference: sourceReference,
                createdAt: createdAt
            )
        )
        block.append(NSAttributedString(string: "\n", attributes: normalTypingAttributes()))
        return block
    }

    private func aiBlockLabelAttributes(
        blockID: String,
        actionTitle: String,
        action: AIEditorAction?,
        sourceReference: SourceReference?,
        createdAt: Date
    ) -> [NSAttributedString.Key: Any] {
        var attributes = aiBlockBaseAttributes(
            blockID: blockID,
            role: "label",
            action: action,
            actionTitle: actionTitle,
            sourceReference: sourceReference,
            createdAt: createdAt
        )
        attributes[.font] = NSFont.systemFont(ofSize: 11, weight: .semibold)
        attributes[.foregroundColor] = NSColor(calibratedRed: 0.38, green: 0.45, blue: 0.48, alpha: 1.0)
        attributes[.backgroundColor] = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.24, green: 0.27, blue: 0.29, alpha: 0.88)
                : NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.95, alpha: 0.96)
        }
        return attributes
    }

    private func aiBlockContentAttributes(
        blockID: String,
        action: AIEditorAction?,
        actionTitle: String,
        sourceReference: SourceReference?,
        createdAt: Date
    ) -> [NSAttributedString.Key: Any] {
        var attributes = aiBlockBaseAttributes(
            blockID: blockID,
            role: "content",
            action: action,
            actionTitle: actionTitle,
            sourceReference: sourceReference,
            createdAt: createdAt
        )
        attributes[.font] = NSFont.systemFont(ofSize: 15.5, weight: .regular)
        attributes[.foregroundColor] = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.90, green: 0.89, blue: 0.87, alpha: 1.0)
                : NSColor(calibratedRed: 0.22, green: 0.22, blue: 0.21, alpha: 1.0)
        }
        return attributes
    }

    private func aiBlockBaseAttributes(
        blockID: String,
        role: String,
        action: AIEditorAction?,
        actionTitle: String,
        sourceReference: SourceReference?,
        createdAt: Date
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4.5
        paragraph.paragraphSpacing = 7
        paragraph.paragraphSpacingBefore = role == "label" ? 8 : 0
        paragraph.firstLineHeadIndent = 14
        paragraph.headIndent = 14
        paragraph.tailIndent = -14

        var attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .aiBlockID: blockID,
            .aiBlockRole: role,
            .aiBlockActionTitle: actionTitle,
            .aiBlockInsertedAt: Date(),
            .aiBlockCreatedAt: createdAt
        ]
        if let action {
            attributes[.aiBlockActionRawValue] = action.rawValue
        }
        if let sourceReference,
           let encodedSourceReference = sourceReference.encodedString() {
            attributes[.aiBlockSourceReference] = encodedSourceReference
        }
        return attributes
    }

    private func aiGeneratedBadge(
        actionTitle: String,
        action: AIEditorAction?,
        blockID: String,
        sourceReference: SourceReference?,
        createdAt: Date
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) {
            let attachment = NSTextAttachment()
            attachment.image = symbol
            attachment.bounds = CGRect(x: 0, y: -1, width: 11, height: 11)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " "))
        }

        let label = "\(actionTitle) · Generated"
        result.append(
            NSAttributedString(
                string: label,
                attributes: aiBlockLabelAttributes(
                    blockID: blockID,
                    actionTitle: actionTitle,
                    action: action,
                    sourceReference: sourceReference,
                    createdAt: createdAt
                )
            )
        )
        return result
    }

    private func normalTypingAttributes() -> [NSAttributedString.Key: Any] {
        guard let tv = textView else { return [:] }
        var attributes = tv.typingAttributes
        attributes[.backgroundColor] = nil
        attributes[.aiBlockID] = nil
        attributes[.aiBlockRole] = nil
        attributes[.aiBlockActionTitle] = nil
        attributes[.aiBlockActionRawValue] = nil
        attributes[.aiBlockCreatedAt] = nil
        attributes[.aiBlockSourceReference] = nil
        return attributes
    }

    static func cleanGeneratedText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let rawLines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var cleanedLines: [String] = []
        var previousWasEmpty = false
        var lastMeaningfulLine: String?
        var lastSectionTitle: String?

        for line in rawLines {
            let normalizedLine = line
            if normalizedLine.isEmpty {
                if previousWasEmpty || cleanedLines.isEmpty {
                    continue
                }
                cleanedLines.append("")
                previousWasEmpty = true
                continue
            }

            previousWasEmpty = false

            if isPromptArtifactLine(normalizedLine) {
                continue
            }

            if let semanticTitle = semanticSectionTitle(for: normalizedLine) {
                if lastSectionTitle == semanticTitle {
                    continue
                }
                cleanedLines.append("## \(semanticTitle)")
                lastSectionTitle = semanticTitle
                lastMeaningfulLine = semanticTitle
                continue
            }

            if normalizedLine == lastMeaningfulLine {
                continue
            }

            cleanedLines.append(normalizedLine)
            lastMeaningfulLine = normalizedLine
            lastSectionTitle = nil
        }

        let cleaned = cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return LlamaContext.sanitizeOutputText(cleaned)
    }

    private func renderMarkdownContent(
        _ content: String,
        blockID: String,
        action: AIEditorAction?,
        actionTitle: String,
        sourceReference: SourceReference?,
        createdAt: Date
    ) -> NSAttributedString {
        MarkdownRichTextRenderer.render(
            content,
            baseFontSize: 15.5,
            baseAttributes: aiBlockContentAttributes(
                blockID: blockID,
                action: action,
                actionTitle: actionTitle,
                sourceReference: sourceReference,
                createdAt: createdAt
            )
        )
    }

    private func leadingSpacing(at insertionIndex: Int, in text: String) -> String {
        guard insertionIndex > 0 else { return "" }
        let prefix = (text as NSString).substring(to: min(insertionIndex, (text as NSString).length))
        if prefix.hasSuffix("\n\n") { return "" }
        if prefix.hasSuffix("\n") { return "\n" }
        return "\n\n"
    }

    private func safeInsertionIndex(after range: NSRange, textLength: Int) -> Int {
        let location = min(max(0, range.location), textLength)
        let length = min(max(0, range.length), textLength - location)
        return location + length
    }

    private func clampedRange(_ range: NSRange, textLength: Int) -> NSRange {
        let location = min(max(0, range.location), textLength)
        let length = min(max(0, range.length), textLength - location)
        return NSRange(location: location, length: length)
    }

    private func markRecentInsertion(in textView: NSTextView, range: NSRange) {
        guard let storage = textView.textStorage, range.length > 0 else { return }
        let highlightUntil = Date().addingTimeInterval(0.9)
        storage.addAttribute(.aiBlockInsertedAt, value: highlightUntil, range: range)
        textView.needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak textView] in
            textView?.needsDisplay = true
        }
    }

    private static func isPromptArtifactLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let artifactPhrases = [
            "student response",
            "avoid repetition",
            "final sentence",
            "generated:",
            "you are helping edit a student note",
            "note context:",
            "selected text:",
            "instruction:",
            "please provide your answer clearly",
            "do not use the exact words",
            "to be clear,",
            "the selected passage",
            "you are not editing the note",
            "note:",
            "notes:"
        ]
        return artifactPhrases.contains { lower.contains($0) }
    }

    private static func semanticSectionTitle(for line: String) -> String? {
        let normalized = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        return [
            "question": "Question",
            "questions": "Question",
            "answer": "Answer",
            "answers": "Answer",
            "explanation": "Explanation",
            "explanations": "Explanation",
            "summary": "Summary",
            "summaries": "Summary",
            "key point": "Key Points",
            "key points": "Key Points",
            "keypoints": "Key Points",
            "flashcard": "Flashcards",
            "flashcards": "Flashcards",
            "quiz": "Quiz",
            "review": "Review",
            "reviews": "Review",
            "example": "Example",
            "examples": "Example",
            "notes": "Notes",
            "note": "Notes"
        ][normalized]
    }

    private func fullRangeForAIBlock(id blockID: String, in storage: NSTextStorage) -> NSRange {
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

    private func contentRangeForAIBlock(id blockID: String, in storage: NSTextStorage, within fullRange: NSRange) -> NSRange {
        var lower: Int?
        var upper: Int?
        storage.enumerateAttributes(in: fullRange) { attributes, range, _ in
            guard (attributes[.aiBlockID] as? String) == blockID,
                  (attributes[.aiBlockRole] as? String) == "content" else { return }
            lower = min(lower ?? range.location, range.location)
            upper = max(upper ?? range.upperBound, range.upperBound)
        }

        guard let lower, let upper else { return NSRange(location: fullRange.upperBound, length: 0) }
        return NSRange(location: lower, length: upper - lower)
    }

    private func actionTitleForAIBlock(id blockID: String, in storage: NSTextStorage, within fullRange: NSRange) -> String {
        var title = "AI"
        storage.enumerateAttributes(in: fullRange) { attributes, _, stop in
            guard (attributes[.aiBlockID] as? String) == blockID,
                  let actionTitle = attributes[.aiBlockActionTitle] as? String else { return }
            title = actionTitle
            stop.pointee = true
        }
        return title
    }

    private func sourceInfoForAIBlock(id blockID: String, in storage: NSTextStorage, within fullRange: NSRange) -> AIBlockSourceInfo? {
        var sourceInfo: AIBlockSourceInfo?
        storage.enumerateAttributes(in: fullRange) { attributes, _, stop in
            guard (attributes[.aiBlockID] as? String) == blockID else { return }
            guard let encodedSourceReference = attributes[.aiBlockSourceReference] as? String,
                  let sourceReference = SourceReference.decoded(from: encodedSourceReference) else { return }
            let actionTitle = attributes[.aiBlockActionTitle] as? String ?? "AI"
            let actionRawValue = attributes[.aiBlockActionRawValue] as? String
            let createdAt = attributes[.aiBlockCreatedAt] as? Date
                ?? attributes[.aiBlockInsertedAt] as? Date
                ?? Date()
            sourceInfo = AIBlockSourceInfo(
                blockID: blockID,
                actionTitle: actionTitle,
                actionRawValue: actionRawValue,
                createdAt: createdAt,
                sourceReference: sourceReference
            )
            stop.pointee = true
        }
        return sourceInfo
    }

    private func isValidRange(_ range: NSRange, in storage: NSTextStorage) -> Bool {
        range.location >= 0 && range.length >= 0 && range.upperBound <= storage.length
    }

    // MARK: - TYPOGRAPHY SYSTEM (NEW)

    func applyFont(size: CGFloat, weight: NSFont.Weight = .regular) {
        guard let tv = textView,
              let storage = tv.textStorage else { return }

        focus()

        let range = tv.selectedRange()
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        if range.length == 0 {
            applyTypingAttributes(font: font)
            return
        }

        storage.beginEditing()
        storage.addAttribute(.font, value: font, range: range)
        storage.endEditing()
    }

    func setBody() {
        applyFont(size: 15, weight: .regular)
    }

    func setSubheading() {
        applyFont(size: 18, weight: .medium)
    }

    func setHeading() {
        applyFont(size: 24, weight: .semibold)
    }

    func setFontFamily(_ familyName: String) {
        guard let tv = textView,
              let storage = tv.textStorage else { return }
        focus()

        let range = tv.selectedRange()
        let currentFont = (tv.typingAttributes[.font] as? NSFont) ?? tv.font ?? NSFont.systemFont(ofSize: 16)
        let size = currentFont.pointSize
        let weight = NSFontManager.shared.weight(of: currentFont)
        let font = familyName == ".AppleSystemUIFont"
            ? NSFont.systemFont(ofSize: size)
            : (NSFontManager.shared.font(
                withFamily: familyName,
                traits: [],
                weight: weight,
                size: size
            ) ?? NSFont.systemFont(ofSize: size))

        if range.length == 0 {
            applyTypingAttributes(font: font)
            return
        }

        storage.beginEditing()
        storage.addAttribute(.font, value: font, range: range)
        storage.endEditing()
        tv.didChangeText()
    }

    func setFontSize(_ size: CGFloat) {
        guard let tv = textView,
              let storage = tv.textStorage else { return }
        focus()

        let clampedSize = min(32, max(12, size))
        let range = tv.selectedRange()
        let currentFont = (tv.typingAttributes[.font] as? NSFont) ?? tv.font ?? NSFont.systemFont(ofSize: 16)
        let font = NSFontManager.shared.convert(currentFont, toSize: clampedSize)

        if range.length == 0 {
            applyTypingAttributes(font: font)
            return
        }

        storage.beginEditing()
        storage.addAttribute(.font, value: font, range: range)
        storage.endEditing()
        tv.didChangeText()
    }

    func setLineSpacing(_ spacing: CGFloat) {
        guard let tv = textView,
              let storage = tv.textStorage else { return }
        focus()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = spacing
        paragraph.paragraphSpacing = spacing + 4

        let range = tv.selectedRange()
        if range.length == 0 {
            tv.typingAttributes[.paragraphStyle] = paragraph
            tv.defaultParagraphStyle = paragraph
            return
        }

        storage.beginEditing()
        storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
        storage.endEditing()
        tv.didChangeText()
    }

    // MARK: - INLINE STYLES

    func toggleBold() {
        guard let tv = textView else { return }
        focus()

        let range = tv.selectedRange()
        if range.length == 0 {
            let current = getTextStyleState().isBold
            let font = NSFont.systemFont(
                ofSize: tv.font?.pointSize ?? 15,
                weight: current ? .regular : .bold
            )
            applyTypingAttributes(font: font)
            return
        }

        toggleTrait(.boldFontMask)
    }

    func toggleItalic() {
        guard let tv = textView else { return }
        focus()

        let range = tv.selectedRange()
        if range.length == 0 {
            let current = getTextStyleState().isItalic
            let manager = NSFontManager.shared
            let base = (tv.typingAttributes[.font] as? NSFont)
                ?? tv.font
                ?? NSFont.systemFont(ofSize: 15)
            let next = current
                ? manager.convert(base, toNotHaveTrait: .italicFontMask)
                : manager.convert(base, toHaveTrait: .italicFontMask)
            applyTypingAttributes(font: next)
            return
        }

        toggleTrait(.italicFontMask)
    }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        guard let tv = textView,
              let storage = tv.textStorage else { return }

        focus()

        let range = tv.selectedRange()
        guard range.length > 0 else { return }

        let manager = NSFontManager.shared

        storage.beginEditing()

        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let currentFont =
                (value as? NSFont)
                ?? tv.font
                ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)

            let traits = manager.traits(of: currentFont)
            let converted = traits.contains(trait)
                ? manager.convert(currentFont, toNotHaveTrait: trait)
                : manager.convert(currentFont, toHaveTrait: trait)
            storage.addAttribute(.font, value: converted, range: subrange)
        }

        storage.endEditing()
    }

    func toggleUnderline() {
        guard let tv = textView,
              let storage = tv.textStorage else { return }

        focus()

        let range = tv.selectedRange()
        if range.length == 0 {
            let current = getTextStyleState().isUnderline
            applyTypingAttributes(underline: !current)
            return
        }

        storage.beginEditing()

        storage.enumerateAttribute(.underlineStyle, in: range) { value, subrange, _ in
            if value == nil {
                storage.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: subrange
                )
            } else {
                storage.removeAttribute(.underlineStyle, range: subrange)
            }
        }

        storage.endEditing()
    }

    // MARK: - LISTS

    func insertBulletList() {
        guard let tv = textView else { return }

        focus()

        let range = tv.selectedRange()
        let text = tv.string as NSString

        let lines = text.substring(with: range).components(separatedBy: "\n")

        let newText = lines.map { "• \($0)" }.joined(separator: "\n")

        tv.insertText(newText, replacementRange: range)
    }

    func insertNumberedList() {
        guard let tv = textView else { return }

        focus()

        let range = tv.selectedRange()
        let text = tv.string as NSString

        let lines = text.substring(with: range).components(separatedBy: "\n")

        let newText = lines.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        tv.insertText(newText, replacementRange: range)
    }

    // MARK: - CLEAR FORMATTING

    func clearFormatting() {
        guard let tv = textView,
              let storage = tv.textStorage else { return }

        focus()

        let range = tv.selectedRange()
        guard range.length > 0 else { return }

        storage.beginEditing()
        storage.setAttributes([:], range: range)
        storage.endEditing()
    }

    // MARK: - Live Transcription

    func startLiveTranscription(modelPath: String = "models/ggml-base.en.bin") -> Bool {
        guard !isLiveTranscribing, let textView else { return false }
        guard ensureMicrophonePermission(textView: textView) else { return false }
        guard let resolvedModelPath = resolveModelPath(modelPath) else {
            insertStatusMessage(
                textView: textView,
                message: "[Whisper model not found at \(modelPath)]"
            )
            return false
        }

        guard WhisperManager.isBackendAvailable else {
            insertStatusMessage(
                textView: textView,
                message: "[Whisper backend unavailable: whisper.cpp not linked in target]"
            )
            return false
        }

        // Keep Whisper lightweight: cap to 4 threads to avoid saturating CPU while editing.
        AIModelManager.shared.unloadLlama(reason: "starting whisper transcription")
        let whisperThreads = min(4, ProcessInfo.processInfo.activeProcessorCount)
        guard let whisperManager = WhisperManager(modelPath: resolvedModelPath, threads: whisperThreads) else {
            insertStatusMessage(
                textView: textView,
                message: "[Whisper failed to initialize from \(resolvedModelPath)]"
            )
            return false
        }
        guard let audioStreamManager = AudioStreamManager() else {
            insertStatusMessage(
                textView: textView,
                message: "[Microphone stream initialization failed]"
            )
            return false
        }

        let insertionManager = EditorInsertionManager(textView: textView)
        let transcriptionEngine = TranscriptionEngine(whisperManager: whisperManager)

        transcriptionEngine.onPartial = { [weak insertionManager] text in
            DispatchQueue.main.async {
                insertionManager?.applyPartial(text)
            }
        }
        transcriptionEngine.onRefined = { [weak insertionManager] text in
            DispatchQueue.main.async {
                insertionManager?.applyRefined(text)
            }
        }
        audioStreamManager.onSamples = { [weak transcriptionEngine] samples in
            transcriptionEngine?.append(samples: samples)
        }

        self.whisperManager = whisperManager
        self.transcriptionEngine = transcriptionEngine
        self.audioStreamManager = audioStreamManager
        self.editorInsertionManager = insertionManager

        insertionManager.beginSession()

        do {
            try audioStreamManager.start()
            isLiveTranscribing = true
            return true
        } catch {
            insertStatusMessage(
                textView: textView,
                message: "[Microphone access denied or unavailable]"
            )
            resetTranscriptionState()
            return false
        }
    }

    private func ensureMicrophonePermission(textView: NSTextView) -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self, weak textView] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard let textView else { return }
                    if granted {
                        self.insertStatusMessage(
                            textView: textView,
                            message: "[Microphone permission granted. Start transcription again.]"
                        )
                    } else {
                        self.insertStatusMessage(
                            textView: textView,
                            message: "[Microphone permission denied. Enable it in System Settings > Privacy & Security > Microphone.]"
                        )
                    }
                }
            }
            insertStatusMessage(
                textView: textView,
                message: "[Requesting microphone permission…]"
            )
            return false
        case .denied, .restricted:
            insertStatusMessage(
                textView: textView,
                message: "[Microphone permission denied. Enable it in System Settings > Privacy & Security > Microphone.]"
            )
            return false
        @unknown default:
            return false
        }
    }

    func stopLiveTranscription() {
        guard isLiveTranscribing else { return }
        audioStreamManager?.stop()

        transcriptionEngine?.finalize { [weak self] finalText in
            DispatchQueue.main.async {
                self?.editorInsertionManager?.finalize(finalText)
                self?.resetTranscriptionState()
            }
        }
    }

    private func resetTranscriptionState() {
        whisperManager?.shutdown()
        whisperManager = nil
        transcriptionEngine = nil
        audioStreamManager = nil
        editorInsertionManager = nil
        isLiveTranscribing = false
    }

    private func resolveModelPath(_ modelPath: String) -> String? {
        let fm = FileManager.default
        if modelPath.hasPrefix("/") {
            return fm.fileExists(atPath: modelPath) ? modelPath : nil
        }

        let candidates: [String] = [
            "\(fm.currentDirectoryPath)/\(modelPath)",
            "\(fm.currentDirectoryPath)/Notinq/\(modelPath)",
            "\(fm.currentDirectoryPath)/ggml-base.en.bin",
            "\(fm.currentDirectoryPath)/Models/ggml-base.en.bin",
            "\(fm.currentDirectoryPath)/models/ggml-base.en.bin",
            "\(NSHomeDirectory())/Documents/Notinq/\(modelPath)",
            "\(NSHomeDirectory())/Documents/Notinq/Models/ggml-base.en.bin",
            "\(NSHomeDirectory())/Documents/Notinq/models/ggml-base.en.bin",
            "\(NSHomeDirectory())/Notinq/\(modelPath)"
        ]

        for candidate in candidates where fm.fileExists(atPath: candidate) {
            return candidate
        }

        let url = URL(fileURLWithPath: modelPath)
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        if let bundled = Bundle.main.path(forResource: name, ofType: ext.isEmpty ? nil : ext) {
            return bundled
        }

        return nil
    }

    private func insertStatusMessage(textView: NSTextView, message: String) {
        let cleaned = message.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let window = textView.window {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Transcription"
            alert.informativeText = cleaned
            alert.beginSheetModal(for: window)
        }
    }
}
