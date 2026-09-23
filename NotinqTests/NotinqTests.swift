import AppKit
import SwiftUI
import XCTest
@testable import Notinq

private func makeProposalBridge(text: String, selection: NSRange) -> (TextViewBridge, NSTextView) {
    let bridge = TextViewBridge()
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
    textView.isRichText = true
    textView.allowsUndo = true
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.textContainerInset = NSSize(width: 24, height: 20)
    textView.string = text
    textView.setSelectedRange(selection)
    bridge.textView = textView
    return (bridge, textView)
}

private final class MockAIProposalGenerator: AIProposalGenerating {
    var response: String
    var adaptiveExplanationContext: AdaptiveExplanationContext?
    private(set) var action: AIEditorAction?
    private(set) var selectedText = ""
    private(set) var noteContext = ""
    private(set) var noteID: UUID?

    init(response: String, adaptiveExplanationContext: AdaptiveExplanationContext? = nil) {
        self.response = response
        self.adaptiveExplanationContext = adaptiveExplanationContext
    }

    func generate(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String,
        noteID: UUID?,
        requestID: UUID,
        completion: @escaping (UUID, AIProposalGenerationResult) -> Void
    ) -> Task<Void, Never>? {
        self.action = action
        self.selectedText = selectedText
        self.noteContext = noteContext
        self.noteID = noteID
        completion(
            requestID,
            AIProposalGenerationResult(
                generatedText: response,
                adaptiveExplanationContext: adaptiveExplanationContext
            )
        )
        return nil
    }
}

private final class DeferredAIProposalGenerator: AIProposalGenerating {
    private(set) var requestIDs: [UUID] = []
    private var completions: [UUID: (UUID, AIProposalGenerationResult) -> Void] = [:]

    func generate(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String,
        noteID: UUID?,
        requestID: UUID,
        completion: @escaping (UUID, AIProposalGenerationResult) -> Void
    ) -> Task<Void, Never>? {
        requestIDs.append(requestID)
        completions[requestID] = completion
        return nil
    }

    func complete(
        requestID: UUID,
        response: String = "Deferred response.",
        adaptiveExplanationContext: AdaptiveExplanationContext? = nil
    ) {
        completions[requestID]?(
            requestID,
            AIProposalGenerationResult(generatedText: response, adaptiveExplanationContext: adaptiveExplanationContext)
        )
    }
}

private final class CancellableAIProposalGenerator: AIProposalGenerating {
    private(set) var requestIDs: [UUID] = []
    private(set) var tasks: [UUID: Task<Void, Never>] = [:]
    private var completions: [UUID: (UUID, AIProposalGenerationResult) -> Void] = [:]

    func generate(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String,
        noteID: UUID?,
        requestID: UUID,
        completion: @escaping (UUID, AIProposalGenerationResult) -> Void
    ) -> Task<Void, Never>? {
        requestIDs.append(requestID)
        completions[requestID] = completion
        let task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        tasks[requestID] = task
        return task
    }

    func complete(requestID: UUID, response: String) {
        completions[requestID]?(
            requestID,
            AIProposalGenerationResult(generatedText: response, adaptiveExplanationContext: nil)
        )
    }

    func isCancelled(_ requestID: UUID) -> Bool {
        tasks[requestID]?.isCancelled ?? false
    }
}

@MainActor
final class NotinqTests: XCTestCase {

    func testEditorCanvasFillsContainerWithoutPaddingOrBorder() {
        let host = NSHostingView(
            rootView: AnyView(
                AITextView(
                    documentID: UUID(),
                    documentText: "One\nTwo\nThree"
                )
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 960, height: 720)

        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()

        let scrollView = descendants(of: host)
            .compactMap { $0 as? NSScrollView }
            .first { $0.documentView is NSTextView }

        XCTAssertNotNil(scrollView)
        guard let scrollView, let textView = scrollView.documentView as? NSTextView else {
            return
        }

        XCTAssertEqual(scrollView.borderType, .noBorder)
        XCTAssertEqual(scrollView.contentInsets.top, 0)
        XCTAssertEqual(scrollView.contentInsets.left, 0)
        XCTAssertEqual(scrollView.contentInsets.bottom, 72)
        XCTAssertEqual(scrollView.contentInsets.right, 0)
        XCTAssertEqual(scrollView.frame.origin.x, 0)
        XCTAssertEqual(scrollView.frame.origin.y, 0)
        XCTAssertEqual(scrollView.frame.width, host.bounds.width)
        XCTAssertEqual(scrollView.frame.height, host.bounds.height)
        XCTAssertEqual(textView.textContainerInset.width, 24)
        XCTAssertEqual(textView.textContainerInset.height, 24)
        XCTAssertEqual(textView.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(textView.frame.height, scrollView.bounds.height - scrollView.contentInsets.bottom)
        XCTAssertEqual(textView.frame.width, scrollView.bounds.width)
    }

    func testEditorDoesNotRenderANoteHeadingAboveTheTextView() {
        let appState = AppState()
        let folder = NoteFolder(
            title: "General",
            notes: [
                NoteFile(title: "Note 1", content: "Heading removal check")
            ]
        )
        appState.folders = [folder]
        appState.selectedFolderID = folder.id
        appState.selectedNoteID = folder.notes.first?.id
        appState.selectedMode = .notes

        let host = NSHostingView(
            rootView: AnyView(
                EditorView()
                    .environmentObject(appState)
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 1280, height: 900)

        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let ready = expectation(description: "Editor hierarchy attached")
        DispatchQueue.main.async {
            window.contentView = host
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            ready.fulfill()
        }
        wait(for: [ready], timeout: 1.0)

        let noteHeadingFields = descendants(of: host)
            .compactMap { $0 as? NSTextField }
            .filter { $0.stringValue == "Note 1" }

        XCTAssertTrue(noteHeadingFields.isEmpty)
    }

    func testEditorToolbarControlsExposeNativeTooltips() {
        let expectedToolTips: Set<String> = [
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

        XCTAssertTrue(expectedToolTips.isSubset(of: Set(EditorTopBar.toolbarTooltipLabels)))
    }

    func testToolbarOverflowAffordanceAppearsWhenContentExceedsViewport() {
        XCTAssertFalse(EditorTopBar.toolbarOverflowAffordanceVisible(contentWidth: 480, viewportWidth: 640))
        XCTAssertTrue(EditorTopBar.toolbarOverflowAffordanceVisible(contentWidth: 980, viewportWidth: 640))
        XCTAssertFalse(EditorTopBar.toolbarLeadingFadeVisible(horizontalOffset: 0))
        XCTAssertTrue(EditorTopBar.toolbarLeadingFadeVisible(horizontalOffset: 12))
        XCTAssertTrue(EditorTopBar.toolbarTrailingFadeVisible(contentWidth: 980, viewportWidth: 640, horizontalOffset: 0))
        XCTAssertFalse(EditorTopBar.toolbarTrailingFadeVisible(contentWidth: 980, viewportWidth: 640, horizontalOffset: 340))
    }

    func testGeneratedTextCleanupRemovesPromptArtifactsAndDuplicateSections() {
        let cleaned = TextViewBridge.cleanGeneratedText("""
        Summary:
        This is the first summary.

        Summary:
        This is the first summary.

        Student response
        Avoid repetition
        Final sentence
        Generated:

        Question:
        What is backpropagation?

        Question:
        What is backpropagation?
        """)

        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("Student response"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("Avoid repetition"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("Final sentence"))
        XCTAssertFalse(cleaned.localizedCaseInsensitiveContains("Generated:"))
        XCTAssertEqual(cleaned.components(separatedBy: "## Summary").count - 1, 1)
        XCTAssertEqual(cleaned.components(separatedBy: "## Question").count - 1, 1)
    }

    func testSelectionToolbarVisibilityDependsOnSelectionLength() {
        XCTAssertFalse(SelectionToolbarView.isVisible(for: NSRange(location: 0, length: 0)))
        XCTAssertTrue(SelectionToolbarView.isVisible(for: NSRange(location: 4, length: 12)))
    }

    func testExpandAppearsForNonEmptySelection() {
        XCTAssertTrue(SelectionToolbarView.isVisible(for: NSRange(location: 4, length: 12)))
        XCTAssertTrue(SelectionToolbarView.actionLabels.contains("Expand"))
        XCTAssertTrue(SelectionToolbarView.actionLabels.contains("I Don't Understand This"))
    }

    func testExpandDoesNotAppearForEmptySelection() {
        XCTAssertFalse(SelectionToolbarView.isVisible(for: NSRange(location: 4, length: 0)))
    }

    func testStudyOverflowAffordanceAppearsWhenContentExceedsViewport() {
        XCTAssertFalse(StudyView.verticalOverflowAffordanceVisible(contentHeight: 480, viewportHeight: 640))
        XCTAssertTrue(StudyView.verticalOverflowAffordanceVisible(contentHeight: 980, viewportHeight: 640))
    }

    func testStudyViewUsesEdgeToEdgeOuterChrome() {
        XCTAssertEqual(StudyView.outerChromePadding, 0)
        XCTAssertEqual(StudyView.outerChromeCornerRadius, 0)
    }

    func testSupplementalStudySectionsBehaveLikeSingleOpenAccordion() {
        XCTAssertEqual(SupplementalStudySection.allCases.count, 8)
        XCTAssertEqual(SupplementalStudySection.teachMe.rawValue, "Teach Me")
        XCTAssertEqual(SupplementalStudySection.learningMemory.rawValue, "Learning Memory")
        XCTAssertEqual(SupplementalStudySection.knowledgeGaps.icon, "exclamationmark.triangle")
        XCTAssertEqual(SupplementalStudySection.examPrep.id, "Exam Prep")
    }

    func testStudyScrollBottomPaddingGrowsWhenOverflowIsPresent() {
        XCTAssertEqual(StudyView.studyScrollBottomPadding(hasOverflow: false), 72)
        XCTAssertEqual(StudyView.studyScrollBottomPadding(hasOverflow: true), 180)
        XCTAssertGreaterThan(StudyView.studyScrollBottomPadding(hasOverflow: true), StudyView.studyScrollBottomPadding(hasOverflow: false))
    }

    func testFlashcardNavigationStaysWithinDeckBounds() {
        XCTAssertEqual(StudyView.previousFlashcardIndex(currentIndex: 0, cardCount: 4), 0)
        XCTAssertEqual(StudyView.previousFlashcardIndex(currentIndex: 2, cardCount: 4), 1)
        XCTAssertEqual(StudyView.nextFlashcardIndex(currentIndex: 0, cardCount: 4), 1)
        XCTAssertEqual(StudyView.nextFlashcardIndex(currentIndex: 3, cardCount: 4), 3)
    }

    func testEditorToolbarScrollTargetClampsToContentBounds() {
        let viewportWidth: CGFloat = 320
        let contentWidth: CGFloat = 840
        let maxOffset = contentWidth - viewportWidth

        let trailingTarget = EditorTopBar.toolbarScrollTarget(
            currentOffset: 0,
            contentWidth: contentWidth,
            viewportWidth: viewportWidth,
            edge: .trailing
        )
        XCTAssertEqual(trailingTarget, min(maxOffset, max(120, viewportWidth * 0.72)), accuracy: 0.0001)

        let leadingTarget = EditorTopBar.toolbarScrollTarget(
            currentOffset: trailingTarget,
            contentWidth: contentWidth,
            viewportWidth: viewportWidth,
            edge: .leading
        )
        XCTAssertGreaterThanOrEqual(leadingTarget, 0)
        XCTAssertLessThan(leadingTarget, trailingTarget)

        let clampedTarget = EditorTopBar.toolbarScrollTarget(
            currentOffset: 999,
            contentWidth: contentWidth,
            viewportWidth: viewportWidth,
            edge: .trailing
        )
        XCTAssertEqual(clampedTarget, maxOffset, accuracy: 0.0001)
    }

    func testFlashcardFlipStateAndCompletionHelpersAreDeterministic() {
        XCTAssertEqual(StudyView.flashcardFace(for: false), .front)
        XCTAssertEqual(StudyView.flashcardFace(for: true), .back)
        XCTAssertFalse(StudyView.flashcardSessionCompleted(currentIndex: 0, cardCount: 4))
        XCTAssertTrue(StudyView.flashcardSessionCompleted(currentIndex: 3, cardCount: 4))
    }

    func testFlashcardProgressClampsAndLabelsTheCurrentCard() {
        XCTAssertEqual(StudyView.flashcardProgressValue(currentIndex: 0, cardCount: 0), 0)
        XCTAssertEqual(StudyView.flashcardProgressLabel(currentIndex: 0, cardCount: 0), "0 of 0 cards")
        XCTAssertEqual(StudyView.flashcardProgressValue(currentIndex: 1, cardCount: 4), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StudyView.flashcardProgressLabel(currentIndex: 1, cardCount: 4), "2 of 4 cards")
    }

    func testFlashcardControlsDisableWhenLockedOrEmpty() {
        XCTAssertTrue(StudyView.flashcardControlsDisabled(cardCount: 0, isLocked: false))
        XCTAssertTrue(StudyView.flashcardControlsDisabled(cardCount: 4, isLocked: true))
        XCTAssertFalse(StudyView.flashcardControlsDisabled(cardCount: 4, isLocked: false))
    }

    func testFlashcardDeckRefreshDetectionUsesIdentifiers() {
        let first = [UUID(), UUID()]
        let same = first
        let different = [UUID(), UUID()]

        XCTAssertFalse(StudyView.flashcardDeckChanged(previousIDs: first, currentIDs: same))
        XCTAssertTrue(StudyView.flashcardDeckChanged(previousIDs: first, currentIDs: different))
    }

    func testStudyInspectorProgressUsesCurrentStreakInputWhenProvided() {
        let inspector = StudyInspectorView(
            noteTitle: "Lecture Note",
            insights: sampleAnalysis(),
            knowledgeGaps: [],
            learningMemory: [],
            progress: StudyProgress(flashcardsCreated: 3, flashcardsReviewed: 2),
            summaryPack: StudySummaryPack(),
            examReadiness: ExamReadinessScore(score: 0, breakdown: []),
            onSelectConcept: { _ in },
            onSelectGap: { _ in },
            onExplainConcept: { _ in },
            onGenerateSection: { _ in },
            onInsertConcept: { _ in },
            onLearnGap: { _ in },
            onGenerateGapNotes: { _ in },
            onCreateGapFlashcards: { _ in },
            onStartReviewSession: { },
            onOpenFocusWorkspace: { _ in },
            streaks: StudyStreakSummary(currentStreak: 7)
        )

        XCTAssertNotNil(inspector)
    }

    func testDocumentSyncPreservesSelectionInsteadOfResettingIt() {
        let representable = AITextView(documentID: UUID(), documentText: "Alpha beta gamma")
        let coordinator = representable.makeCoordinator()

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.string = "Alpha beta gamma"
        textView.setSelectedRange(NSRange(location: 6, length: 4))

        coordinator.bridge.textView = textView

        coordinator.replaceDocumentText(in: textView, with: "Alpha beta gamma delta")

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 4))
        XCTAssertEqual(textView.string, "Alpha beta gamma delta")
    }

    func testDocumentSyncSkipsReplacementWhenTheVisibleTextAlreadyMatchesTheModel() {
        XCTAssertFalse(
            AITextView.shouldReplaceDocumentText(
                currentText: "Answer",
                renderedDocumentText: "Answer",
                incomingText: "Answer"
            )
        )

        XCTAssertFalse(
            AITextView.shouldReplaceDocumentText(
                currentText: "Answer",
                renderedDocumentText: nil,
                incomingText: "Answer"
            )
        )

        XCTAssertTrue(
            AITextView.shouldReplaceDocumentText(
                currentText: "Answer",
                renderedDocumentText: "Answer",
                incomingText: "Answer**"
            )
        )
    }

    func testDocumentSyncRendersMarkdownIntoEditableContent() {
        let representable = AITextView(documentID: UUID(), documentText: "# Heading 1\n\n**Bold** and *italic*\n\n## Question\nAnswer:")
        let coordinator = representable.makeCoordinator()

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 24, height: 20)

        coordinator.bridge.textView = textView
        coordinator.replaceDocumentText(
            in: textView,
            with: "# Heading 1\n\n**Bold** and *italic*\n\n## Question\nAnswer:"
        )

        XCTAssertFalse(textView.string.contains("# "))
        XCTAssertFalse(textView.string.contains("**"))
        XCTAssertFalse(textView.string.contains("##"))
        XCTAssertTrue(textView.string.contains("Heading 1"))
        XCTAssertTrue(textView.string.contains("Question"))
        XCTAssertTrue(textView.isEditable)

        let headingFont = textView.textStorage?.attribute(.font, at: (textView.string as NSString).range(of: "Heading 1").location, effectiveRange: nil) as? NSFont
        let bodyFont = textView.textStorage?.attribute(.font, at: (textView.string as NSString).range(of: "Bold").location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(headingFont)
        XCTAssertNotNil(bodyFont)
        if let headingFont, let bodyFont {
            XCTAssertGreaterThan(headingFont.pointSize, bodyFont.pointSize)
        }
    }

    func testFormattingFocusSelectionAndScrollingRemainFunctional() {
        let bridge = TextViewBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 140))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 280, height: 140))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        textView.isRichText = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.string = (0..<90).map { "Line \($0)" }.joined(separator: "\n")
        textView.frame = NSRect(x: 0, y: 0, width: 280, height: 2400)
        textView.setSelectedRange(NSRange(location: 0, length: 6))
        bridge.textView = textView

        let window = NSWindow(
            contentRect: scrollView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.layoutIfNeeded()

        bridge.focus()
        XCTAssertTrue(window.firstResponder === textView)

        bridge.toggleBold()
        let boldFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(boldFont)
        if let boldFont {
            XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
        }
        XCTAssertEqual(bridge.selectedTextAndRange()?.text, "Line 0")

        XCTAssertGreaterThan(textView.frame.height, scrollView.contentView.bounds.height)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        bridge.insertBelowSelection("Inserted line")
        window.layoutIfNeeded()
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 1200))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.y, 0)
    }

    func testMarkdownRendererConvertsCommonFormattingSyntax() {
        let rendered = MarkdownRichTextRenderer.render("""
        # Heading 1

        **Bold** and *italic* and `code`

        - Item one
        - Item two

        > Quote line
        """)

        XCTAssertFalse(rendered.string.contains("**"))
        XCTAssertFalse(rendered.string.contains("# "))
        XCTAssertFalse(rendered.string.contains("`"))
        XCTAssertTrue(rendered.string.contains("Heading 1"))
        XCTAssertTrue(rendered.string.contains("• Item one"))

        let headingRange = (rendered.string as NSString).range(of: "Heading 1")
        let bodyRange = (rendered.string as NSString).range(of: "Bold")
        let codeRange = (rendered.string as NSString).range(of: "code")

        let headingFont = rendered.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont
        let bodyFont = rendered.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont
        let codeFont = rendered.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont

        XCTAssertNotNil(headingFont)
        XCTAssertNotNil(bodyFont)
        XCTAssertNotNil(codeFont)
        if let headingFont, let bodyFont, let codeFont {
            XCTAssertGreaterThan(headingFont.pointSize, bodyFont.pointSize)
            XCTAssertTrue(codeFont.fontName.lowercased().contains("mono") || codeFont.fontName.lowercased().contains("code"))
        }
    }

    func testMarkdownRendererStylesSemanticSectionHeaders() {
        let rendered = MarkdownRichTextRenderer.render("""
        ## Question

        What is backpropagation?

        Answer:
        It updates weights using error gradients.
        """)

        let questionRange = (rendered.string as NSString).range(of: "Question")
        let answerRange = (rendered.string as NSString).range(of: "Answer")
        XCTAssertNotEqual(questionRange.location, NSNotFound)
        XCTAssertNotEqual(answerRange.location, NSNotFound)

        let questionBackground = rendered.attribute(.backgroundColor, at: questionRange.location, effectiveRange: nil) as? NSColor
        let answerForeground = rendered.attribute(.foregroundColor, at: answerRange.location, effectiveRange: nil) as? NSColor
        let bodyFont = rendered.attribute(.font, at: (rendered.string as NSString).range(of: "What is backpropagation?").location, effectiveRange: nil) as? NSFont
        let questionFont = rendered.attribute(.font, at: questionRange.location, effectiveRange: nil) as? NSFont

        XCTAssertNotNil(questionBackground)
        XCTAssertNotNil(answerForeground)
        XCTAssertNotNil(bodyFont)
        XCTAssertNotNil(questionFont)
        if let bodyFont, let questionFont {
            XCTAssertGreaterThan(questionFont.pointSize, bodyFont.pointSize)
        }
    }

    func testSearchResultsReturnRealNoteCards() {
        let appState = AppState()
        let folder = NoteFolder(
            title: "Machine Learning",
            notes: [
                NoteFile(title: "Neural Networks", content: "Backpropagation improves training stability.", updatedAt: Date(timeIntervalSinceNow: -3600)),
                NoteFile(title: "Spare Note", content: "Completely unrelated content.", updatedAt: Date(timeIntervalSinceNow: -7200))
            ]
        )
        appState.folders = [folder]

        let results = SearchView.searchResults(
            query: "backpropagation",
            folders: appState.folders,
            currentNoteOnly: false,
            selectedNoteID: nil
        )

        XCTAssertEqual(results.first?.title, "Neural Networks")
        XCTAssertEqual(results.first?.folderTitle, "Machine Learning")
        XCTAssertTrue(results.first?.preview.lowercased().contains("backpropagation") == true)
        XCTAssertGreaterThan(results.first?.relevance ?? 0, 0)
    }

    func testAIInsertionRendersMarkdownInsteadOfRawMarkers() {
        let bridge = TextViewBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.string = "Start"
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        bridge.textView = textView

        bridge.insertAIResult(
            action: .summarize,
            response: """
            # Heading 1

            **Bold** and *italic*

            - Item one
            - Item two
            """,
            selectionRange: NSRange(location: textView.string.count, length: 0)
        )

        XCTAssertFalse(textView.string.contains("**"))
        XCTAssertFalse(textView.string.contains("# "))
        XCTAssertTrue(textView.string.contains("Heading 1"))
        XCTAssertTrue(textView.string.contains("• Item one"))

        let headingRange = (textView.string as NSString).range(of: "Heading 1")
        let headingFont = textView.textStorage?.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(headingFont)
        if let headingFont {
            XCTAssertGreaterThan(headingFont.pointSize, 20)
        }
    }

    func testAIInsertionMarksRecentlyInsertedContentForHighlighting() {
        let bridge = TextViewBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.string = "Prompt"
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        bridge.textView = textView

        bridge.insertAIResult(
            action: .summarize,
            response: "Summary:\nA concise result.",
            selectionRange: NSRange(location: textView.string.count, length: 0)
        )

        let insertedRange = NSRange(location: 6, length: textView.string.count - 6)
        let highlightDate = textView.textStorage?.attribute(.aiBlockInsertedAt, at: insertedRange.location, effectiveRange: nil) as? Date
        XCTAssertNotNil(highlightDate)
        XCTAssertEqual(textView.selectedRange().length, 0)
        XCTAssertTrue(textView.string.contains("Summary"))
    }

    func testAIGeneratedBadgeUsesSemanticStylingAndRemainsEditable() {
        let bridge = TextViewBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.string = "Prompt"
        textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        bridge.textView = textView

        bridge.insertAIResult(
            action: .ask,
            response: """
            ## Question
            What is backpropagation?

            Answer:
            It updates weights using gradients.
            """,
            selectionRange: NSRange(location: textView.string.count, length: 0)
        )

        let renderedText = textView.string
        XCTAssertFalse(renderedText.contains("##"))
        XCTAssertFalse(renderedText.contains("**"))
        XCTAssertTrue(renderedText.contains("Question"))
        XCTAssertTrue(renderedText.contains("Answer"))

        let questionRange = (renderedText as NSString).range(of: "Question")
        let questionBackground = textView.textStorage?.attribute(.backgroundColor, at: questionRange.location, effectiveRange: nil) as? NSColor
        let questionRole = textView.textStorage?.attribute(.aiBlockRole, at: questionRange.location, effectiveRange: nil) as? String
        XCTAssertEqual(questionRole, "content")
        XCTAssertNotNil(questionBackground)

        textView.setSelectedRange(questionRange)
        bridge.toggleBold()
        let boldFont = textView.textStorage?.attribute(.font, at: questionRange.location, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(boldFont)
        XCTAssertEqual(textView.selectedRange(), questionRange)
        XCTAssertTrue(textView.isEditable)
    }

    func testAIProposalGenerationDoesNotModifyDocumentContent() {
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))

        let proposal = bridge.makeAIProposal(
            action: .expand,
            response: "Expanded beta",
            selectionRange: textView.selectedRange(),
            provenance: AIProposalProvenance(
                sourceNoteRange: NSRange(location: 6, length: 4),
                transcriptReference: "transcript-placeholder",
                slideReference: "slide-placeholder"
            )
        )

        XCTAssertEqual(textView.string, "Alpha beta gamma")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 4))
        XCTAssertEqual(proposal?.status, .pending)
        XCTAssertEqual(proposal?.originalText, "beta")
        XCTAssertEqual(proposal?.insertionLocation, 10)
        XCTAssertEqual(proposal?.provenance.sourceNoteRange, NSRange(location: 6, length: 4))
        XCTAssertEqual(proposal?.provenance.transcriptReference, "transcript-placeholder")
        XCTAssertEqual(proposal?.provenance.slideReference, "slide-placeholder")
    }

    func testAcceptingAIProposalModifiesDocumentContent() {
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta", selection: NSRange(location: 6, length: 4))
        guard let proposal = bridge.makeAIProposal(
            action: .expand,
            response: "Expanded idea.",
            selectionRange: textView.selectedRange()
        ) else {
            XCTFail("Expected proposal")
            return
        }

        let accepted = bridge.acceptAIProposal(proposal)

        XCTAssertEqual(accepted.status, .accepted)
        XCTAssertTrue(textView.string.contains("Expansion"))
        XCTAssertTrue(textView.string.contains("Expanded idea."))
    }

    func testRejectingAIProposalLeavesDocumentUnchanged() {
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta", selection: NSRange(location: 6, length: 4))
        guard let proposal = bridge.makeAIProposal(
            action: .explain,
            response: "An explanation.",
            selectionRange: textView.selectedRange()
        ) else {
            XCTFail("Expected proposal")
            return
        }

        let rejected = bridge.rejectAIProposal(proposal)

        XCTAssertEqual(rejected.status, .rejected)
        XCTAssertEqual(textView.string, "Alpha beta")
    }

    func testEditingThenAcceptingAIProposalInsertsEditedContent() {
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta", selection: NSRange(location: 6, length: 4))
        guard let proposal = bridge.makeAIProposal(
            action: .explain,
            response: "Original generated text.",
            selectionRange: textView.selectedRange()
        ) else {
            XCTFail("Expected proposal")
            return
        }

        let edited = bridge.editAIProposal(proposal, generatedText: "Edited generated text.")
        let accepted = bridge.acceptAIProposal(edited)

        XCTAssertEqual(edited.status, .edited)
        XCTAssertEqual(accepted.status, .accepted)
        XCTAssertTrue(textView.string.contains("Edited generated text."))
        XCTAssertFalse(textView.string.contains("Original generated text."))
    }

    func testAIProposalFlowPreservesOriginalSelection() {
        let originalSelection = NSRange(location: 6, length: 4)
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: originalSelection)
        guard let proposal = bridge.makeAIProposal(
            action: .expand,
            response: "Expanded beta.",
            selectionRange: textView.selectedRange()
        ) else {
            XCTFail("Expected proposal")
            return
        }

        XCTAssertEqual(textView.selectedRange(), originalSelection)
        _ = bridge.acceptAIProposal(proposal)
        XCTAssertEqual(textView.selectedRange(), originalSelection)
    }

    func testAIProposalRestoresCapturedSelectionIfSelectionDriftsDuringGeneration() {
        let originalSelection = NSRange(location: 6, length: 4)
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: originalSelection)

        textView.setSelectedRange(NSRange(location: 0, length: 5))
        guard let proposal = bridge.makeAIProposal(
            action: .expand,
            response: "Expanded beta.",
            selectionRange: originalSelection
        ) else {
            XCTFail("Expected proposal")
            return
        }

        XCTAssertEqual(proposal.originalText, "beta")
        XCTAssertEqual(proposal.originalSelectionRange, originalSelection)
        XCTAssertEqual(textView.selectedRange(), originalSelection)

        _ = bridge.acceptAIProposal(proposal)
        XCTAssertEqual(textView.selectedRange(), originalSelection)
    }

    func testAcceptedAIProposalRendersMarkdownInsteadOfRawMarkdown() {
        let (bridge, textView) = makeProposalBridge(text: "Start", selection: NSRange(location: 5, length: 0))
        guard let proposal = bridge.makeAIProposal(
            action: .explain,
            response: """
            ## Explanation
            **Bold** detail

            - First
            """,
            selectionRange: textView.selectedRange()
        ) else {
            XCTFail("Expected proposal")
            return
        }

        _ = bridge.acceptAIProposal(proposal)

        XCTAssertFalse(textView.string.contains("##"))
        XCTAssertFalse(textView.string.contains("**"))
        XCTAssertTrue(textView.string.contains("Explanation"))
        XCTAssertTrue(textView.string.contains("Bold detail"))
        XCTAssertTrue(textView.string.contains("• First"))
    }

    func testAcceptedAIProposalAppliesAIInsertionAttributes() {
        let (bridge, textView) = makeProposalBridge(text: "Prompt", selection: NSRange(location: 6, length: 0))
        guard let proposal = bridge.makeAIProposal(
            action: .expand,
            response: "Expanded idea.",
            selectionRange: textView.selectedRange()
        ) else {
            XCTFail("Expected proposal")
            return
        }

        _ = bridge.acceptAIProposal(proposal)

        let insertedRange = (textView.string as NSString).range(of: "Expanded idea.")
        let role = textView.textStorage?.attribute(NSAttributedString.Key.aiBlockRole, at: insertedRange.location, effectiveRange: nil) as? String
        let insertedAt = textView.textStorage?.attribute(NSAttributedString.Key.aiBlockInsertedAt, at: insertedRange.location, effectiveRange: nil) as? Date
        XCTAssertEqual(role, "content")
        XCTAssertNotNil(insertedAt)
    }

    func testExpandTapCreatesAIProposalWithMockResponse() {
        let noteID = UUID()
        let (bridge, _) = makeProposalBridge(text: "Photosynthesis uses light.", selection: NSRange(location: 0, length: 14))
        let generator = MockAIProposalGenerator(response: "Photosynthesis uses light energy to drive sugar production.")
        let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

        coordinator.beginExpand(noteContext: "Photosynthesis uses light. Chlorophyll absorbs photons.", noteID: noteID)

        XCTAssertEqual(generator.action, .expand)
        XCTAssertEqual(generator.selectedText, "Photosynthesis")
        XCTAssertEqual(generator.noteID, noteID)
        XCTAssertEqual(coordinator.proposal?.action, .expand)
        XCTAssertEqual(coordinator.proposal?.status, .pending)
        XCTAssertEqual(coordinator.proposal?.originalText, "Photosynthesis")
        XCTAssertEqual(coordinator.proposal?.generatedText, "Photosynthesis uses light energy to drive sugar production.")
    }

    func testExpandProposalGenerationDoesNotModifyDocumentContent() {
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Beta is expanded with context.")
        )

        coordinator.beginExpand(noteContext: textView.string, noteID: UUID())

        XCTAssertEqual(textView.string, "Alpha beta gamma")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 4))
        XCTAssertNotNil(coordinator.proposal)
    }

    func testExpandProposalPreviewDoesNotModifyDocumentContent() {
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let proposal = bridge.makeAIProposal(
            action: .expand,
            response: "Beta is expanded.",
            selectionRange: textView.selectedRange()
        )

        XCTAssertNotNil(proposal)
        XCTAssertTrue(AIProposalPreviewView.actionLabels.contains("Accept"))
        XCTAssertTrue(AIProposalPreviewView.actionLabels.contains("Edit"))
        XCTAssertTrue(AIProposalPreviewView.actionLabels.contains("Reject"))
        XCTAssertEqual(textView.string, "Alpha beta gamma")
    }

    func testEditingExpandProposalDoesNotModifyDocumentContent() {
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Original expansion.")
        )

        coordinator.beginExpand(noteContext: textView.string, noteID: UUID())
        coordinator.editProposal(text: "Edited expansion.")

        XCTAssertEqual(textView.string, "Alpha beta gamma")
        XCTAssertEqual(coordinator.proposal?.generatedText, "Edited expansion.")
        XCTAssertEqual(coordinator.proposal?.status, .edited)
    }

    func testAcceptingExpandProposalInsertsGeneratedContentCorrectly() {
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Beta is the second Greek letter.")
        )

        let noteID = UUID()
        coordinator.beginExpand(noteContext: textView.string, noteID: noteID)
        let accepted = coordinator.acceptProposal(selectedNoteID: noteID)

        XCTAssertEqual(accepted?.status, .accepted)
        XCTAssertTrue(textView.string.contains("Alpha beta"))
        XCTAssertTrue(textView.string.contains("Expansion"))
        XCTAssertTrue(textView.string.contains("Beta is the second Greek letter."))
        XCTAssertTrue(textView.string.contains("gamma"))
    }

    func testRejectingExpandProposalLeavesDocumentUnchanged() {
        let originalSelection = NSRange(location: 6, length: 4)
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: originalSelection)
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Beta is expanded.")
        )

        coordinator.beginExpand(noteContext: textView.string, noteID: UUID())
        let rejected = coordinator.rejectProposal()

        XCTAssertEqual(rejected?.status, .rejected)
        XCTAssertEqual(textView.string, "Alpha beta gamma")
        XCTAssertEqual(textView.selectedRange(), originalSelection)
        XCTAssertNil(coordinator.proposal)
    }

    func testEditingThenAcceptingExpandProposalInsertsEditedContent() {
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Original expansion.")
        )

        let noteID = UUID()
        coordinator.beginExpand(noteContext: textView.string, noteID: noteID)
        coordinator.editProposal(text: "Edited expansion.")
        let accepted = coordinator.acceptProposal(selectedNoteID: noteID)

        XCTAssertEqual(accepted?.status, .accepted)
        XCTAssertTrue(textView.string.contains("Edited expansion."))
        XCTAssertFalse(textView.string.contains("Original expansion."))
    }

    func testAcceptedExpandProposalRendersMarkdownInsteadOfRawMarkdown() {
        let (bridge, textView) = makeProposalBridge(text: "Start beta", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: """
            ## Explanation
            **Beta** connects to:
            - Alpha
            """)
        )

        let noteID = UUID()
        coordinator.beginExpand(noteContext: textView.string, noteID: noteID)
        _ = coordinator.acceptProposal(selectedNoteID: noteID)

        XCTAssertFalse(textView.string.contains("##"))
        XCTAssertFalse(textView.string.contains("**"))
        XCTAssertTrue(textView.string.contains("Explanation"))
        XCTAssertTrue(textView.string.contains("• Alpha"))
    }

    func testAcceptedExpandProposalReceivesAIInsertionAttributes() {
        let (bridge, textView) = makeProposalBridge(text: "Start beta", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Beta expansion.")
        )

        let noteID = UUID()
        coordinator.beginExpand(noteContext: textView.string, noteID: noteID)
        _ = coordinator.acceptProposal(selectedNoteID: noteID)

        let insertedRange = (textView.string as NSString).range(of: "Beta expansion.")
        let role = textView.textStorage?.attribute(NSAttributedString.Key.aiBlockRole, at: insertedRange.location, effectiveRange: nil) as? String
        let insertedAt = textView.textStorage?.attribute(NSAttributedString.Key.aiBlockInsertedAt, at: insertedRange.location, effectiveRange: nil) as? Date
        XCTAssertEqual(role, "content")
        XCTAssertNotNil(insertedAt)
    }

    func testExpandSelectionPreservationAcrossRejectAndAccept() {
        let originalSelection = NSRange(location: 6, length: 4)
        let (rejectBridge, rejectTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: originalSelection)
        let rejectCoordinator = AIProposalCoordinator(
            bridge: rejectBridge,
            generator: MockAIProposalGenerator(response: "Beta is expanded.")
        )

        rejectCoordinator.beginExpand(noteContext: rejectTextView.string, noteID: UUID())
        XCTAssertEqual(rejectTextView.selectedRange(), originalSelection)
        _ = rejectCoordinator.rejectProposal()
        XCTAssertEqual(rejectTextView.selectedRange(), originalSelection)

        let (acceptBridge, acceptTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: originalSelection)
        let acceptCoordinator = AIProposalCoordinator(
            bridge: acceptBridge,
            generator: MockAIProposalGenerator(response: "Beta is expanded.")
        )

        let acceptNoteID = UUID()
        acceptCoordinator.beginExpand(noteContext: acceptTextView.string, noteID: acceptNoteID)
        _ = acceptCoordinator.acceptProposal(selectedNoteID: acceptNoteID)

        XCTAssertTrue(acceptTextView.string.contains("Beta is expanded."))
        XCTAssertEqual(acceptTextView.selectedRange(), originalSelection)
    }

    func testExpandPromptUsesSelectedTextAndContextWithoutOverridingSelection() {
        let prompt = AIService.editorProposalPrompt(
            action: .expand,
            selectedText: "Gradient descent updates weights.",
            noteContext: "Neural network notes mention loss functions."
        )

        XCTAssertTrue(prompt.contains("Expand the selected idea"))
        XCTAssertTrue(prompt.contains("Do not invent facts"))
        XCTAssertTrue(prompt.contains("Selected text:"))
        XCTAssertTrue(prompt.contains("Gradient descent updates weights."))
        XCTAssertTrue(prompt.contains("Surrounding note context:"))
        XCTAssertTrue(prompt.contains("do not let unrelated context override the selected idea"))
    }

    func testEditorActionFrameworkCreatesProposalForEveryAction() {
        for action in AIEditorAction.allCases {
            let (bridge, _) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
            let generator = MockAIProposalGenerator(response: "\(action.displayTitle) response.")
            let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

            coordinator.begin(action: action, noteContext: "Alpha beta gamma", noteID: UUID())

            XCTAssertEqual(generator.action, action)
            XCTAssertEqual(coordinator.proposal?.action, action)
            XCTAssertEqual(coordinator.proposal?.status, .pending)
            XCTAssertEqual(coordinator.proposal?.originalText, "beta")
        }
    }

    func testEditorActionFrameworkDoesNotMutateDocumentBeforeAccept() {
        for action in AIEditorAction.allCases {
            let originalSelection = NSRange(location: 6, length: 4)
            let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: originalSelection)
            let coordinator = AIProposalCoordinator(
                bridge: bridge,
                generator: MockAIProposalGenerator(response: "\(action.displayTitle) response.")
            )

            coordinator.begin(action: action, noteContext: textView.string, noteID: UUID())
            coordinator.editProposal(text: "Edited \(action.displayTitle) response.")

            XCTAssertEqual(textView.string, "Alpha beta gamma")
            XCTAssertEqual(textView.selectedRange(), originalSelection)
            XCTAssertEqual(coordinator.proposal?.status, .edited)
        }
    }

    func testEditorActionFrameworkAcceptRejectAndEditAcceptUseSharedProposalFlow() {
        let originalSelection = NSRange(location: 6, length: 4)

        for action in AIEditorAction.allCases {
            let (acceptBridge, acceptTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: originalSelection)
            let acceptCoordinator = AIProposalCoordinator(
                bridge: acceptBridge,
                generator: MockAIProposalGenerator(response: "**\(action.displayTitle)** response.")
            )
            let acceptNoteID = UUID()
            acceptCoordinator.begin(action: action, noteContext: acceptTextView.string, noteID: acceptNoteID)
            _ = acceptCoordinator.acceptProposal(selectedNoteID: acceptNoteID)

            XCTAssertTrue(acceptTextView.string.contains(action.blockTitle))
            XCTAssertTrue(acceptTextView.string.contains("\(action.displayTitle) response."))
            XCTAssertFalse(acceptTextView.string.contains("**"))
            let acceptedRange = (acceptTextView.string as NSString).range(of: "\(action.displayTitle) response.")
            let acceptedRole = acceptTextView.textStorage?.attribute(.aiBlockRole, at: acceptedRange.location, effectiveRange: nil) as? String
            let acceptedAt = acceptTextView.textStorage?.attribute(.aiBlockInsertedAt, at: acceptedRange.location, effectiveRange: nil) as? Date
            XCTAssertEqual(acceptedRole, "content")
            XCTAssertNotNil(acceptedAt)
            XCTAssertEqual(acceptTextView.selectedRange(), originalSelection)

            let (rejectBridge, rejectTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: originalSelection)
            let rejectCoordinator = AIProposalCoordinator(
                bridge: rejectBridge,
                generator: MockAIProposalGenerator(response: "\(action.displayTitle) response.")
            )
            rejectCoordinator.begin(action: action, noteContext: rejectTextView.string, noteID: UUID())
            _ = rejectCoordinator.rejectProposal()
            XCTAssertEqual(rejectTextView.string, "Alpha beta gamma")
            XCTAssertEqual(rejectTextView.selectedRange(), originalSelection)

            let (editBridge, editTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: originalSelection)
            let editCoordinator = AIProposalCoordinator(
                bridge: editBridge,
                generator: MockAIProposalGenerator(response: "Original \(action.displayTitle) response.")
            )
            let editNoteID = UUID()
            editCoordinator.begin(action: action, noteContext: editTextView.string, noteID: editNoteID)
            editCoordinator.editProposal(text: "Edited \(action.displayTitle) response.")
            _ = editCoordinator.acceptProposal(selectedNoteID: editNoteID)
            XCTAssertTrue(editTextView.string.contains("Edited \(action.displayTitle) response."))
            XCTAssertFalse(editTextView.string.contains("Original \(action.displayTitle) response."))
        }
    }

    func testEditorActionPromptBuilderUsesCorrectTemplateForEachAction() {
        let selectedText = "Gradient descent updates weights."
        let noteContext = "Neural network notes mention loss functions."
        let expectations: [AIEditorAction: String] = [
            .expand: "Expand the selected idea",
            .explain: "why it matters",
            .simplify: "lower the reading difficulty",
            .example: "concrete educational example",
            .analogy: "intuitive educational analogy",
            .dontUnderstand: "STUDENT CONTEXT"
        ]

        for action in AIEditorAction.allCases {
            let prompt = AIActionPromptBuilder().prompt(
                action: action,
                selectedText: selectedText,
                noteContext: noteContext
            )

            XCTAssertTrue(prompt.contains(expectations[action] ?? ""))
            XCTAssertTrue(prompt.contains(action == .dontUnderstand ? "SELECTED CONTENT" : "Selected text:"))
            XCTAssertTrue(prompt.contains(selectedText))
            if action == .dontUnderstand {
                XCTAssertTrue(prompt.contains("SOURCE MATERIAL"))
                XCTAssertTrue(prompt.contains("GROUNDING RULES"))
            } else {
                XCTAssertTrue(prompt.contains("Surrounding note context:"))
                XCTAssertTrue(prompt.contains(noteContext))
            }
            XCTAssertTrue(prompt.contains("Return clean Markdown"))
        }
    }

    func testProposalPreviewLabelsGeneratedContentByAction() {
        XCTAssertEqual(AIEditorAction.expand.previewTitle, "EXPANDED")
        XCTAssertEqual(AIEditorAction.explain.previewTitle, "EXPLAINED")
        XCTAssertEqual(AIEditorAction.simplify.previewTitle, "SIMPLIFIED")
        XCTAssertEqual(AIEditorAction.example.previewTitle, "EXAMPLE")
        XCTAssertEqual(AIEditorAction.analogy.previewTitle, "ANALOGY")
        XCTAssertEqual(AIEditorAction.dontUnderstand.previewTitle, "ADAPTIVE EXPLANATION")
    }

    func testDontUnderstandPromptAdaptsBeforeExplaining() {
        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "Backpropagation applies the chain rule.",
            noteContext: "The student has already studied derivatives but struggles with neural network layers."
        )

        XCTAssertTrue(prompt.contains("STUDENT CONTEXT"))
        XCTAssertTrue(prompt.contains("Learner level: Unknown"))
        XCTAssertTrue(prompt.contains("SOURCE MATERIAL"))
        XCTAssertTrue(prompt.contains("Source grounding unavailable"))
        XCTAssertTrue(prompt.contains("GROUNDING RULES"))
        XCTAssertTrue(prompt.contains("Explain the selected content at the appropriate level"))
        XCTAssertTrue(prompt.contains("Backpropagation applies the chain rule."))
    }

    func testDontUnderstandProposalAttachesAdaptiveContext() {
        let context = AdaptiveExplanationContext(
            weakConcepts: ["Chain Rule"],
            strongConcepts: ["Derivatives"],
            missingPrerequisites: ["Partial Derivatives"],
            retrievedNoteSources: [
                AdaptiveExplanationSource(noteTitle: "Backpropagation Notes", sectionTitle: "Gradients", snippet: "Chain rule through layers.")
            ],
            inferredLearnerLevel: "Needs prerequisite support",
            confidence: 0.72
        )
        let (bridge, textView) = makeProposalBridge(text: "Backpropagation applies the chain rule.", selection: NSRange(location: 0, length: 15))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Adaptive explanation.", adaptiveExplanationContext: context)
        )

        coordinator.begin(action: .dontUnderstand, noteContext: textView.string, noteID: UUID())

        XCTAssertEqual(coordinator.proposal?.adaptiveExplanationContext, context)
        XCTAssertEqual(coordinator.proposal?.adaptiveExplanationContext?.missingPrerequisites.first, "Partial Derivatives")
    }

    func testAdaptiveContextSurvivesAcceptRejectAndEdit() {
        let context = AdaptiveExplanationContext(
            weakConcepts: ["Recursion"],
            strongConcepts: ["Functions"],
            missingPrerequisites: ["Call Stack"],
            retrievedNoteSources: [AdaptiveExplanationSource(noteTitle: "Algorithms", snippet: "Recursive calls use stack frames.")],
            inferredLearnerLevel: "Developing understanding",
            confidence: 0.68
        )
        let selection = NSRange(location: 6, length: 4)

        let (acceptBridge, acceptTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: selection)
        let acceptCoordinator = AIProposalCoordinator(
            bridge: acceptBridge,
            generator: MockAIProposalGenerator(response: "Adaptive beta.", adaptiveExplanationContext: context)
        )
        let acceptNoteID = UUID()
        acceptCoordinator.begin(action: .dontUnderstand, noteContext: acceptTextView.string, noteID: acceptNoteID)
        let accepted = acceptCoordinator.acceptProposal(selectedNoteID: acceptNoteID)
        XCTAssertEqual(accepted?.adaptiveExplanationContext, context)

        let (rejectBridge, rejectTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: selection)
        let rejectCoordinator = AIProposalCoordinator(
            bridge: rejectBridge,
            generator: MockAIProposalGenerator(response: "Adaptive beta.", adaptiveExplanationContext: context)
        )
        rejectCoordinator.begin(action: .dontUnderstand, noteContext: rejectTextView.string, noteID: UUID())
        let rejected = rejectCoordinator.rejectProposal()
        XCTAssertEqual(rejected?.adaptiveExplanationContext, context)

        let (editBridge, editTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: selection)
        let editCoordinator = AIProposalCoordinator(
            bridge: editBridge,
            generator: MockAIProposalGenerator(response: "Adaptive beta.", adaptiveExplanationContext: context)
        )
        editCoordinator.begin(action: .dontUnderstand, noteContext: editTextView.string, noteID: UUID())
        editCoordinator.editProposal(text: "Edited adaptive beta.")
        XCTAssertEqual(editCoordinator.proposal?.adaptiveExplanationContext, context)
    }

    func testAdaptiveProposalPreviewDisplaysMetadata() {
        let context = AdaptiveExplanationContext(
            weakConcepts: ["Neural Network Layers"],
            strongConcepts: ["Derivatives"],
            missingPrerequisites: ["Chain Rule"],
            retrievedNoteSources: [AdaptiveExplanationSource(noteTitle: "Machine Learning Lecture", snippet: "Backpropagation uses gradients.")],
            inferredLearnerLevel: "Needs prerequisite support",
            confidence: 0.74
        )

        let lines = AIProposalPreviewView.adaptedUsingLines(from: context)

        XCTAssertTrue(lines.contains("Missing prerequisite:\nChain Rule"))
        XCTAssertTrue(lines.contains("Weak concept:\nNeural Network Layers"))
        XCTAssertTrue(lines.contains("Known concept:\nDerivatives"))
        XCTAssertTrue(lines.contains("Sources:\nMachine Learning Lecture"))
        XCTAssertTrue(lines.contains("Learner level:\nNeeds prerequisite support"))
        XCTAssertTrue(lines.contains("Confidence:\nHigh"))
    }

    func testDontUnderstandProposalUsesFallbackWhenAdaptiveDataUnavailable() {
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Fallback explanation.")
        )

        coordinator.begin(action: .dontUnderstand, noteContext: textView.string, noteID: UUID())

        XCTAssertEqual(coordinator.proposal?.adaptiveExplanationContext, .unavailable())
        let lines = AIProposalPreviewView.adaptedUsingLines(from: .unavailable())
        XCTAssertTrue(lines.contains("Learner level:\nUnknown"))
        XCTAssertTrue(lines.contains("Adaptive data unavailable"))
    }

    func testDontUnderstandPromptContainsSourceBackedSectionsAndExcerpts() {
        let context = makeSourceBackedAdaptiveContext()
        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "Backpropagation applies the chain rule.",
            noteContext: "Neural network lecture notes.",
            adaptiveContext: context
        )

        XCTAssertTrue(prompt.contains("STUDENT CONTEXT"))
        XCTAssertTrue(prompt.contains("Missing prerequisites: Chain Rule"))
        XCTAssertTrue(prompt.contains("Weak concepts: Partial Derivatives"))
        XCTAssertTrue(prompt.contains("Learner level: Needs prerequisite support"))
        XCTAssertTrue(prompt.contains("SOURCE MATERIAL"))
        XCTAssertTrue(prompt.contains("Source: Lecture 4 — Backpropagation — Gradients"))
        XCTAssertTrue(prompt.contains("the chain rule allows gradients to propagate backward through layers"))
        XCTAssertTrue(prompt.contains("GROUNDING RULES"))
        XCTAssertTrue(prompt.contains("Do not cite sources that were not supplied"))
        XCTAssertTrue(prompt.contains("If the supplied material is insufficient"))
    }

    func testDontUnderstandProposalIncludesRetrievedSourceContent() {
        let context = makeSourceBackedAdaptiveContext()
        let (bridge, textView) = makeProposalBridge(text: "Backpropagation uses chain rule.", selection: NSRange(location: 0, length: 15))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Source-backed explanation.", adaptiveExplanationContext: context)
        )

        coordinator.begin(action: .dontUnderstand, noteContext: textView.string, noteID: UUID())

        let source = coordinator.proposal?.adaptiveExplanationContext?.retrievedNoteSources.first
        XCTAssertEqual(source?.noteTitle, "Lecture 4 — Backpropagation")
        XCTAssertEqual(source?.sectionTitle, "Gradients")
        XCTAssertEqual(source?.sourceType, "chunk")
        XCTAssertTrue(source?.groundingText.contains("chain rule allows gradients") == true)
    }

    func testSourceMetadataSurvivesAcceptRejectAndEditAccept() {
        let context = makeSourceBackedAdaptiveContext()
        let selection = NSRange(location: 6, length: 4)

        let (acceptBridge, acceptTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: selection)
        let acceptCoordinator = AIProposalCoordinator(
            bridge: acceptBridge,
            generator: MockAIProposalGenerator(response: "Adaptive beta.", adaptiveExplanationContext: context)
        )
        let acceptNoteID = UUID()
        acceptCoordinator.begin(action: .dontUnderstand, noteContext: acceptTextView.string, noteID: acceptNoteID)
        let accepted = acceptCoordinator.acceptProposal(selectedNoteID: acceptNoteID)
        XCTAssertEqual(accepted?.adaptiveExplanationContext?.retrievedNoteSources.first?.sourceID, "chunk-backprop-4")

        let (rejectBridge, rejectTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: selection)
        let rejectCoordinator = AIProposalCoordinator(
            bridge: rejectBridge,
            generator: MockAIProposalGenerator(response: "Adaptive beta.", adaptiveExplanationContext: context)
        )
        rejectCoordinator.begin(action: .dontUnderstand, noteContext: rejectTextView.string, noteID: UUID())
        let rejected = rejectCoordinator.rejectProposal()
        XCTAssertEqual(rejected?.adaptiveExplanationContext?.retrievedNoteSources.first?.sourceID, "chunk-backprop-4")
        XCTAssertEqual(rejectTextView.string, "Alpha beta gamma")

        let (editBridge, editTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: selection)
        let editCoordinator = AIProposalCoordinator(
            bridge: editBridge,
            generator: MockAIProposalGenerator(response: "Adaptive beta.", adaptiveExplanationContext: context)
        )
        let editNoteID = UUID()
        editCoordinator.begin(action: .dontUnderstand, noteContext: editTextView.string, noteID: editNoteID)
        editCoordinator.editProposal(text: "Edited adaptive beta.")
        let editedAccepted = editCoordinator.acceptProposal(selectedNoteID: editNoteID)
        XCTAssertEqual(editedAccepted?.adaptiveExplanationContext?.retrievedNoteSources.first?.sourceID, "chunk-backprop-4")
        XCTAssertTrue(editTextView.string.contains("Edited adaptive beta."))
    }

    func testNoSourceFallbackDoesNotFabricateSourceInformation() {
        let context = AdaptiveExplanationContext(
            weakConcepts: ["Limits"],
            missingPrerequisites: ["Continuity"],
            inferredLearnerLevel: "Developing understanding",
            confidence: 0.42
        )
        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "A derivative is a limit.",
            noteContext: "",
            adaptiveContext: context
        )

        XCTAssertTrue(prompt.contains("Source grounding unavailable"))
        XCTAssertFalse(prompt.contains("Source:"))
        XCTAssertFalse(prompt.contains("Lecture 4"))
    }

    func testMissingAdaptiveContextDoesNotCrashSourceBackedPrompt() {
        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "A derivative is a limit.",
            noteContext: "",
            adaptiveContext: nil
        )

        XCTAssertTrue(prompt.contains("Learner level: Unknown"))
        XCTAssertTrue(prompt.contains("Source grounding unavailable"))
        XCTAssertTrue(prompt.contains("A derivative is a limit."))
    }

    func testAdaptivePreviewDisplaysSourceTitlesMissingPrerequisiteAndLearnerLevel() {
        let lines = AIProposalPreviewView.adaptedUsingLines(from: makeSourceBackedAdaptiveContext())

        XCTAssertTrue(lines.contains("Sources:\nLecture 4 — Backpropagation — Gradients"))
        XCTAssertTrue(lines.contains("Missing prerequisite:\nChain Rule"))
        XCTAssertTrue(lines.contains("Learner level:\nNeeds prerequisite support"))
    }

    func testStaleCompletionCannotInstallSourceBackedProposal() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let generator = DeferredAIProposalGenerator()
        let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

        let staleRequestID = coordinator.begin(action: .dontUnderstand, noteContext: textView.string, noteID: noteID)
        coordinator.invalidateActiveRequest()
        if let staleRequestID {
            generator.complete(
                requestID: staleRequestID,
                response: "Late source-backed response.",
                adaptiveExplanationContext: makeSourceBackedAdaptiveContext()
            )
        }

        XCTAssertNil(coordinator.proposal)
        XCTAssertEqual(textView.string, "Alpha beta gamma")
    }

    func testSourceBackedProposalCannotCrossNoteBoundaries() {
        let noteA = UUID()
        let noteB = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Source-backed beta.", adaptiveExplanationContext: makeSourceBackedAdaptiveContext())
        )

        coordinator.begin(action: .dontUnderstand, noteContext: textView.string, noteID: noteA)
        let accepted = coordinator.acceptProposal(selectedNoteID: noteB)

        XCTAssertNil(accepted)
        XCTAssertEqual(coordinator.proposal?.state, .invalidated)
        XCTAssertEqual(textView.string, "Alpha beta gamma")
    }

    func testConceptProfileAggregatesHelpfulSignalsCorrectly() {
        let signals = [
            makeLearningSignal(conceptIDs: ["chain-rule"], type: .markedHelpful),
            makeLearningSignal(conceptIDs: ["chain-rule"], type: .markedHelpful),
            makeLearningSignal(conceptIDs: ["chain-rule"], type: .accepted)
        ]

        let profile = ConceptLearningProfileBuilder().profile(for: "chain-rule", signals: signals)

        XCTAssertEqual(profile.helpfulCount, 2)
        XCTAssertEqual(profile.acceptCount, 1)
        XCTAssertEqual(profile.helpfulRatio, 1)
        XCTAssertNotNil(profile.lastInteractionDate)
    }

    func testConceptProfileAggregatesConfusedSignalsCorrectly() {
        let signals = [
            makeLearningSignal(conceptIDs: ["chain-rule"], type: .markedStillConfused),
            makeLearningSignal(conceptIDs: ["chain-rule"], type: .requestedAgain),
            makeLearningSignal(conceptIDs: ["chain-rule"], type: .heavilyEdited)
        ]

        let profile = ConceptLearningProfileBuilder().profile(for: "chain-rule", signals: signals)

        XCTAssertEqual(profile.confusedCount, 1)
        XCTAssertEqual(profile.requestedAgainCount, 1)
        XCTAssertEqual(profile.heavilyEditedCount, 1)
        XCTAssertEqual(profile.confusionRatio, 1)
    }

    func testProfileBuilderHandlesEmptySignalsAndMultipleConcepts() {
        let builder = ConceptLearningProfileBuilder()
        let empty = builder.profile(for: "chain-rule", signals: [])
        XCTAssertEqual(empty.conceptID, "chain-rule")
        XCTAssertEqual(empty.helpfulCount, 0)

        let profiles = builder.profiles(
            for: ["chain-rule", "partial-derivatives"],
            signals: [
                makeLearningSignal(conceptIDs: ["chain-rule"], type: .markedHelpful),
                makeLearningSignal(conceptIDs: ["partial-derivatives"], type: .markedStillConfused)
            ]
        )

        XCTAssertEqual(profiles["chain-rule"]?.helpfulCount, 1)
        XCTAssertEqual(profiles["partial-derivatives"]?.confusedCount, 1)
    }

    func testAdaptiveContextIncludesHistoricallyHelpfulAndConfusingConcepts() {
        var context = makeSourceBackedAdaptiveContext()
        let profiles = ConceptLearningProfileBuilder().profiles(
            for: context.conceptIDs,
            signals: [
                makeLearningSignal(conceptIDs: ["chain-rule"], type: .markedHelpful),
                makeLearningSignal(conceptIDs: ["partial-derivatives"], type: .markedStillConfused)
            ]
        )

        context.applyLearningProfiles(
            Array(profiles.values),
            conceptNameByID: [
                "chain-rule": "Chain Rule",
                "partial-derivatives": "Partial Derivatives"
            ]
        )

        XCTAssertEqual(context.historicallyHelpfulConcepts, ["Chain Rule"])
        XCTAssertEqual(context.historicallyConfusingConcepts, ["Partial Derivatives"])
        XCTAssertEqual(context.priorHelpfulExplanationsCount, 1)
        XCTAssertEqual(context.priorConfusingExplanationsCount, 1)
    }

    func testRequestedAgainElevatesHistoricallyConfusingConcept() {
        var context = AdaptiveExplanationContext(conceptIDs: ["chain-rule"])
        let profiles = ConceptLearningProfileBuilder().profiles(
            for: context.conceptIDs,
            signals: [
                makeLearningSignal(conceptIDs: ["chain-rule"], type: .requestedAgain),
                makeLearningSignal(conceptIDs: ["chain-rule"], type: .requestedAgain)
            ]
        )

        context.applyLearningProfiles(Array(profiles.values), conceptNameByID: ["chain-rule": "Chain Rule"])

        XCTAssertEqual(context.historicallyConfusingConcepts, ["Chain Rule"])
        XCTAssertEqual(context.priorConfusingExplanationsCount, 2)
    }

    func testDontUnderstandPromptContainsLearningHistorySection() {
        var context = makeSourceBackedAdaptiveContext()
        context.historicallyHelpfulConcepts = ["Chain Rule"]
        context.historicallyConfusingConcepts = ["Partial Derivatives"]
        context.priorHelpfulExplanationsCount = 2
        context.priorConfusingExplanationsCount = 1

        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "Backpropagation uses the chain rule.",
            noteContext: "",
            adaptiveContext: context
        )

        XCTAssertTrue(prompt.contains("LEARNING HISTORY"))
        XCTAssertTrue(prompt.contains("Historically Helpful Concepts: Chain Rule"))
        XCTAssertTrue(prompt.contains("Historically Confusing Concepts: Partial Derivatives"))
        XCTAssertTrue(prompt.contains("Prior helpful explanations: 2"))
        XCTAssertTrue(prompt.contains("Prior confusing explanations: 1"))
    }

    func testLearningHistoryPromptRulesAdaptHelpfulAndConfusingConcepts() {
        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "Backpropagation uses the chain rule.",
            noteContext: "",
            adaptiveContext: makeSourceBackedAdaptiveContext()
        )

        XCTAssertTrue(prompt.contains("If a concept appears historically confusing"))
        XCTAssertTrue(prompt.contains("reduce complexity"))
        XCTAssertTrue(prompt.contains("use more examples"))
        XCTAssertTrue(prompt.contains("If a concept appears historically helpful"))
        XCTAssertTrue(prompt.contains("slightly more advanced explanation"))
    }

    func testPreviewDisplaysLearningHistoryAndFallback() {
        var context = makeSourceBackedAdaptiveContext()
        context.historicallyHelpfulConcepts = ["Chain Rule"]
        context.historicallyConfusingConcepts = ["Partial Derivatives"]

        let lines = AIProposalPreviewView.adaptedUsingLines(from: context)
        XCTAssertTrue(lines.contains("Learning history:\nPreviously helpful: Chain Rule\nPreviously confusing: Partial Derivatives"))

        let fallbackLines = AIProposalPreviewView.adaptedUsingLines(from: makeSourceBackedAdaptiveContext())
        XCTAssertTrue(fallbackLines.contains("Learning history:\nLearning history unavailable"))
    }

    func testHelpfulFeedbackAffectsFutureContext() {
        let store = makeLearningSignalStore()
        let recorder = LearningSignalRecorder(store: store)
        let proposal = makeLearningSignalProposal()
        _ = recorder.recordHelpful(proposal: proposal)

        var context = AdaptiveExplanationContext(conceptIDs: ["concept-a"])
        let profiles = ConceptLearningProfileBuilder().profiles(for: context.conceptIDs, signals: store.allSignals())
        context.applyLearningProfiles(Array(profiles.values), conceptNameByID: ["concept-a": "Weak Concept"])

        XCTAssertEqual(context.historicallyHelpfulConcepts, ["Weak Concept"])
        XCTAssertEqual(context.historicallyConfusingConcepts, [])
    }

    func testStillConfusedFeedbackAffectsFutureContext() {
        let store = makeLearningSignalStore()
        let recorder = LearningSignalRecorder(store: store)
        let proposal = makeLearningSignalProposal()
        _ = recorder.recordStillConfused(proposal: proposal)

        var context = AdaptiveExplanationContext(conceptIDs: ["concept-a"])
        let profiles = ConceptLearningProfileBuilder().profiles(for: context.conceptIDs, signals: store.allSignals())
        context.applyLearningProfiles(Array(profiles.values), conceptNameByID: ["concept-a": "Weak Concept"])

        XCTAssertEqual(context.historicallyHelpfulConcepts, [])
        XCTAssertEqual(context.historicallyConfusingConcepts, ["Weak Concept"])
    }

    func testMissingLearningHistoryDoesNotCrash() {
        var context = AdaptiveExplanationContext(conceptIDs: [])
        let profiles = ConceptLearningProfileBuilder().profiles(for: context.conceptIDs, signals: [])
        context.applyLearningProfiles(Array(profiles.values))

        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "A derivative is a limit.",
            noteContext: "",
            adaptiveContext: context
        )

        XCTAssertTrue(prompt.contains("Learning history unavailable"))
        XCTAssertTrue(context.historicallyHelpfulConcepts.isEmpty)
        XCTAssertTrue(context.historicallyConfusingConcepts.isEmpty)
    }

    func testMasteryBuilderProducesMasteredState() {
        let profile = ConceptLearningProfile(
            conceptID: "chain-rule",
            helpfulCount: 3,
            acceptCount: 2,
            lightlyEditedCount: 1
        )

        let mastery = ConceptMasteryBuilder().mastery(for: profile)

        XCTAssertEqual(mastery.masteryState, .mastered)
        XCTAssertGreaterThanOrEqual(mastery.masteryScore, 0.8)
    }

    func testMasteryBuilderProducesFamiliarState() {
        let profile = ConceptLearningProfile(
            conceptID: "chain-rule",
            helpfulCount: 1,
            acceptCount: 1
        )

        let mastery = ConceptMasteryBuilder().mastery(for: profile)

        XCTAssertEqual(mastery.masteryState, .familiar)
        XCTAssertGreaterThanOrEqual(mastery.masteryScore, 0.6)
        XCTAssertLessThan(mastery.masteryScore, 0.8)
    }

    func testMasteryBuilderProducesNeedsPracticeState() {
        let mastery = ConceptMasteryBuilder().mastery(for: ConceptLearningProfile(conceptID: "chain-rule"))

        XCTAssertEqual(mastery.masteryState, .needsPractice)
        XCTAssertEqual(mastery.masteryScore, 0.5)
    }

    func testMasteryBuilderProducesStrugglingState() {
        let profile = ConceptLearningProfile(
            conceptID: "chain-rule",
            confusedCount: 2,
            rejectCount: 1,
            heavilyEditedCount: 1,
            requestedAgainCount: 1
        )

        let mastery = ConceptMasteryBuilder().mastery(for: profile)

        XCTAssertEqual(mastery.masteryState, .struggling)
        XCTAssertLessThan(mastery.masteryScore, 0.4)
    }

    func testHelpfulSignalsIncreaseMastery() {
        let baseline = ConceptMasteryBuilder().mastery(for: ConceptLearningProfile(conceptID: "chain-rule"))
        let helpful = ConceptMasteryBuilder().mastery(
            for: ConceptLearningProfile(conceptID: "chain-rule", helpfulCount: 1)
        )

        XCTAssertGreaterThan(helpful.masteryScore, baseline.masteryScore)
    }

    func testConfusedSignalsDecreaseMastery() {
        let baseline = ConceptMasteryBuilder().mastery(for: ConceptLearningProfile(conceptID: "chain-rule"))
        let confused = ConceptMasteryBuilder().mastery(
            for: ConceptLearningProfile(conceptID: "chain-rule", confusedCount: 1)
        )

        XCTAssertLessThan(confused.masteryScore, baseline.masteryScore)
    }

    func testRequestedAgainPenalizesMastery() {
        let baseline = ConceptMasteryBuilder().mastery(for: ConceptLearningProfile(conceptID: "chain-rule"))
        let requestedAgain = ConceptMasteryBuilder().mastery(
            for: ConceptLearningProfile(conceptID: "chain-rule", requestedAgainCount: 2)
        )

        XCTAssertLessThan(requestedAgain.masteryScore, baseline.masteryScore)
    }

    func testAdaptiveContextIncludesMasteryStates() {
        var context = makeSourceBackedAdaptiveContext()
        let profiles = ConceptLearningProfileBuilder().profiles(
            for: context.conceptIDs,
            signals: [
                makeLearningSignal(conceptIDs: ["chain-rule"], type: .markedHelpful),
                makeLearningSignal(conceptIDs: ["chain-rule"], type: .markedHelpful),
                makeLearningSignal(conceptIDs: ["chain-rule"], type: .markedHelpful),
                makeLearningSignal(conceptIDs: ["chain-rule"], type: .accepted),
                makeLearningSignal(conceptIDs: ["chain-rule"], type: .accepted),
                makeLearningSignal(conceptIDs: ["partial-derivatives"], type: .markedStillConfused),
                makeLearningSignal(conceptIDs: ["partial-derivatives"], type: .markedStillConfused),
                makeLearningSignal(conceptIDs: ["partial-derivatives"], type: .rejected),
                makeLearningSignal(conceptIDs: ["partial-derivatives"], type: .heavilyEdited),
                makeLearningSignal(conceptIDs: ["partial-derivatives"], type: .requestedAgain)
            ]
        )

        context.applyLearningProfiles(
            Array(profiles.values),
            conceptNameByID: [
                "chain-rule": "Chain Rule",
                "partial-derivatives": "Partial Derivatives"
            ]
        )

        XCTAssertEqual(context.masteryStates["Chain Rule"], .mastered)
        XCTAssertEqual(context.masteryStates["Partial Derivatives"], .struggling)
    }

    func testDontUnderstandPromptContainsMasterySection() {
        var context = makeSourceBackedAdaptiveContext()
        context.masteryStates = [
            "Chain Rule": .mastered,
            "Partial Derivatives": .struggling
        ]

        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "Backpropagation uses the chain rule.",
            noteContext: "",
            adaptiveContext: context
        )

        XCTAssertTrue(prompt.contains("MASTERY STATE"))
        XCTAssertTrue(prompt.contains("Concept: Chain Rule"))
        XCTAssertTrue(prompt.contains("State: Mastered"))
        XCTAssertTrue(prompt.contains("Concept: Partial Derivatives"))
        XCTAssertTrue(prompt.contains("State: Struggling"))
        XCTAssertTrue(prompt.contains("If mastery state is struggling"))
        XCTAssertTrue(prompt.contains("If mastery state is needsPractice"))
        XCTAssertTrue(prompt.contains("If mastery state is familiar"))
        XCTAssertTrue(prompt.contains("If mastery state is mastered"))
    }

    func testAdaptivePreviewDisplaysMasteryStates() {
        var context = makeSourceBackedAdaptiveContext()
        context.masteryStates = [
            "Chain Rule": .mastered,
            "Partial Derivatives": .struggling
        ]

        let lines = AIProposalPreviewView.adaptedUsingLines(from: context)

        XCTAssertTrue(lines.contains("Mastery:\nChain Rule — Mastered\nPartial Derivatives — Struggling"))
    }

    func testMissingMasteryUsesFallback() {
        let context = AdaptiveExplanationContext()
        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "A derivative is a limit.",
            noteContext: "",
            adaptiveContext: context
        )
        let lines = AIProposalPreviewView.adaptedUsingLines(from: context)

        XCTAssertTrue(prompt.contains("Mastery unavailable"))
        XCTAssertTrue(lines.contains("Mastery:\nMastery unavailable"))
    }

    func testMasteryRemainsDeterministicForSameSignals() {
        let timestamp = Date(timeIntervalSince1970: 42)
        let profile = ConceptLearningProfile(
            conceptID: "chain-rule",
            helpfulCount: 2,
            confusedCount: 1,
            acceptCount: 1,
            rejectCount: 1,
            lightlyEditedCount: 1,
            heavilyEditedCount: 1,
            requestedAgainCount: 1,
            lastInteractionDate: timestamp
        )
        let builder = ConceptMasteryBuilder()

        let first = builder.mastery(for: profile)
        let second = builder.mastery(for: profile)

        XCTAssertEqual(first, second)
    }

    func testKnowledgeGapsAppearInAdaptiveContext() {
        let context = makeSourceBackedAdaptiveContext()

        XCTAssertEqual(context.identifiedKnowledgeGaps, ["Chain Rule", "Partial Derivatives"])
    }

    func testKnowledgeGapsPrioritizePrerequisitesOverWeakConcepts() {
        let context = AdaptiveExplanationContext(
            weakConcepts: ["Partial Derivatives", "Gradient Flow"],
            missingPrerequisites: ["Chain Rule"]
        )

        XCTAssertEqual(context.identifiedKnowledgeGaps, ["Chain Rule", "Partial Derivatives", "Gradient Flow"])
    }

    func testHistoricallyConfusingConceptBecomesKnowledgeGap() {
        var context = AdaptiveExplanationContext(
            conceptIDs: ["gradient-flow"],
            weakConcepts: [],
            missingPrerequisites: []
        )
        let profiles = ConceptLearningProfileBuilder().profiles(
            for: context.conceptIDs,
            signals: [makeLearningSignal(conceptIDs: ["gradient-flow"], type: .markedStillConfused)]
        )

        context.applyLearningProfiles(Array(profiles.values), conceptNameByID: ["gradient-flow": "Gradient Flow"])

        XCTAssertEqual(context.historicallyConfusingConcepts, ["Gradient Flow"])
        XCTAssertEqual(context.identifiedKnowledgeGaps, ["Gradient Flow"])
    }

    func testDontUnderstandPromptContainsKnowledgeGapSection() {
        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "Backpropagation uses the chain rule.",
            noteContext: "",
            adaptiveContext: makeSourceBackedAdaptiveContext()
        )

        XCTAssertTrue(prompt.contains("KNOWLEDGE GAPS"))
        XCTAssertTrue(prompt.contains("Likely missing concepts:"))
        XCTAssertTrue(prompt.contains("- Chain Rule"))
        XCTAssertTrue(prompt.contains("Explicitly address identified knowledge gaps"))
        XCTAssertTrue(prompt.contains("Build the explanation from prerequisite upward"))
    }

    func testAdaptivePreviewDisplaysKnowledgeGaps() {
        let lines = AIProposalPreviewView.adaptedUsingLines(from: makeSourceBackedAdaptiveContext())

        XCTAssertTrue(lines.contains("Knowledge gaps:\nChain Rule\nPartial Derivatives"))
    }

    func testGapDeduplicationPreventsRepeatedConcepts() {
        let context = AdaptiveExplanationContext(
            weakConcepts: ["Chain Rule", "Partial Derivatives"],
            missingPrerequisites: ["Chain Rule"],
            historicallyConfusingConcepts: ["Partial Derivatives", "Gradient Flow"]
        )

        XCTAssertEqual(context.identifiedKnowledgeGaps, ["Chain Rule", "Partial Derivatives", "Gradient Flow"])
    }

    func testMissingGapDataUsesFallbackText() {
        let context = AdaptiveExplanationContext()
        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "A derivative is a limit.",
            noteContext: "",
            adaptiveContext: context
        )
        let lines = AIProposalPreviewView.adaptedUsingLines(from: context)

        XCTAssertTrue(prompt.contains("Knowledge gaps unavailable"))
        XCTAssertTrue(lines.contains("Knowledge gaps:\nKnowledge gaps unavailable"))
    }

    func testKnowledgeGapContextSurvivesAcceptRejectAndEditAccept() {
        let context = makeSourceBackedAdaptiveContext()
        let selection = NSRange(location: 6, length: 4)

        let (acceptBridge, acceptTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: selection)
        let acceptCoordinator = AIProposalCoordinator(
            bridge: acceptBridge,
            generator: MockAIProposalGenerator(response: "Adaptive beta.", adaptiveExplanationContext: context)
        )
        let acceptNoteID = UUID()
        acceptCoordinator.begin(action: .dontUnderstand, noteContext: acceptTextView.string, noteID: acceptNoteID)
        let accepted = acceptCoordinator.acceptProposal(selectedNoteID: acceptNoteID)
        XCTAssertEqual(accepted?.adaptiveExplanationContext?.identifiedKnowledgeGaps, ["Chain Rule", "Partial Derivatives"])

        let (rejectBridge, rejectTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: selection)
        let rejectCoordinator = AIProposalCoordinator(
            bridge: rejectBridge,
            generator: MockAIProposalGenerator(response: "Adaptive beta.", adaptiveExplanationContext: context)
        )
        rejectCoordinator.begin(action: .dontUnderstand, noteContext: rejectTextView.string, noteID: UUID())
        let rejected = rejectCoordinator.rejectProposal()
        XCTAssertEqual(rejected?.adaptiveExplanationContext?.identifiedKnowledgeGaps, ["Chain Rule", "Partial Derivatives"])
        XCTAssertEqual(rejectTextView.string, "Alpha beta gamma")

        let (editBridge, editTextView) = makeProposalBridge(text: "Alpha beta gamma", selection: selection)
        let editCoordinator = AIProposalCoordinator(
            bridge: editBridge,
            generator: MockAIProposalGenerator(response: "Adaptive beta.", adaptiveExplanationContext: context)
        )
        let editNoteID = UUID()
        editCoordinator.begin(action: .dontUnderstand, noteContext: editTextView.string, noteID: editNoteID)
        editCoordinator.editProposal(text: "Edited adaptive beta.")
        let editedAccepted = editCoordinator.acceptProposal(selectedNoteID: editNoteID)
        XCTAssertEqual(editedAccepted?.adaptiveExplanationContext?.identifiedKnowledgeGaps, ["Chain Rule", "Partial Derivatives"])
        XCTAssertTrue(editTextView.string.contains("Edited adaptive beta."))
    }

    func testSourceBackedExplanationStillIncludesKnowledgeGaps() {
        let context = makeSourceBackedAdaptiveContext()
        let prompt = AIActionPromptBuilder().prompt(
            action: .dontUnderstand,
            selectedText: "Backpropagation uses the chain rule.",
            noteContext: "",
            adaptiveContext: context
        )

        XCTAssertTrue(prompt.contains("SOURCE MATERIAL"))
        XCTAssertTrue(prompt.contains("the chain rule allows gradients to propagate backward through layers"))
        XCTAssertTrue(prompt.contains("KNOWLEDGE GAPS"))
        XCTAssertTrue(prompt.contains("- Chain Rule"))
    }

    func testLearningHistoryCanPromoteGapWhenRequestedAgain() {
        var context = AdaptiveExplanationContext(conceptIDs: ["chain-rule"])
        let profiles = ConceptLearningProfileBuilder().profiles(
            for: context.conceptIDs,
            signals: [
                makeLearningSignal(conceptIDs: ["chain-rule"], type: .requestedAgain),
                makeLearningSignal(conceptIDs: ["chain-rule"], type: .requestedAgain)
            ]
        )

        context.applyLearningProfiles(Array(profiles.values), conceptNameByID: ["chain-rule": "Chain Rule"])

        XCTAssertEqual(context.historicallyConfusingConcepts, ["Chain Rule"])
        XCTAssertEqual(context.identifiedKnowledgeGaps, ["Chain Rule"])
    }

    func testLateProposalCompletionIgnoredAfterNoteSwitch() {
        let noteA = UUID()
        let noteB = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let generator = DeferredAIProposalGenerator()
        let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

        let requestID = coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteA)
        coordinator.noteDidChange(to: noteB)
        if let requestID {
            generator.complete(requestID: requestID, response: "Late expansion.")
        }

        XCTAssertNil(coordinator.proposal)
        XCTAssertNil(coordinator.activeRequestID)
        XCTAssertFalse(coordinator.isGenerating)
        XCTAssertEqual(textView.string, "Alpha beta gamma")
    }

    func testLateProposalCompletionIgnoredAfterNewRequest() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let generator = DeferredAIProposalGenerator()
        let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

        let staleRequestID = coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteID)
        coordinator.invalidateActiveRequest()
        let currentRequestID = coordinator.begin(action: .explain, noteContext: textView.string, noteID: noteID)

        if let staleRequestID {
            generator.complete(requestID: staleRequestID, response: "Stale expansion.")
        }
        XCTAssertNil(coordinator.proposal)

        if let currentRequestID {
            generator.complete(requestID: currentRequestID, response: "Current explanation.")
        }

        XCTAssertEqual(coordinator.proposal?.action, .explain)
        XCTAssertEqual(coordinator.proposal?.generatedText, "Current explanation.")
        XCTAssertEqual(coordinator.proposal?.originatingRequestID, currentRequestID)
    }

    func testPendingProposalBlocksNewGeneration() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let generator = MockAIProposalGenerator(response: "First response.")
        let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

        let firstRequestID = coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteID)
        let secondRequestID = coordinator.begin(action: .explain, noteContext: textView.string, noteID: noteID)

        XCTAssertNotNil(firstRequestID)
        XCTAssertNil(secondRequestID)
        XCTAssertEqual(coordinator.proposal?.action, .expand)
        XCTAssertEqual(generator.action, .expand)
    }

    func testRejectInvalidatesOutstandingRequest() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Generated response.")
        )

        coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteID)
        XCTAssertNotNil(coordinator.activeRequestID)

        let rejected = coordinator.rejectProposal()

        XCTAssertEqual(rejected?.status, .rejected)
        XCTAssertNil(coordinator.proposal)
        XCTAssertNil(coordinator.activeRequestID)
        XCTAssertNil(coordinator.activeNoteID)
    }

    func testProposalClearedOnNoteChange() {
        let noteA = UUID()
        let noteB = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Generated response.")
        )

        coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteA)
        XCTAssertNotNil(coordinator.proposal)

        coordinator.noteDidChange(to: noteB)

        XCTAssertNil(coordinator.proposal)
        XCTAssertNil(coordinator.activeRequestID)
        XCTAssertNil(coordinator.activeNoteID)
    }

    func testAcceptFailsAcrossNoteBoundary() {
        let noteA = UUID()
        let noteB = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Generated response.")
        )

        coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteA)
        let accepted = coordinator.acceptProposal(selectedNoteID: noteB)

        XCTAssertNil(accepted)
        XCTAssertEqual(coordinator.proposal?.state, .invalidated)
        XCTAssertEqual(textView.string, "Alpha beta gamma")
    }

    func testDuplicateFeedbackSignalsNotRecorded() {
        let store = makeLearningSignalStore()
        let recorder = LearningSignalRecorder(store: store)
        let proposal = makeLearningSignalProposal()

        _ = recorder.recordHelpful(proposal: proposal)
        _ = recorder.recordHelpful(proposal: proposal)
        _ = recorder.recordStillConfused(proposal: proposal)
        _ = recorder.recordStillConfused(proposal: proposal)

        XCTAssertEqual(store.signals(for: proposal.id).map(\.signalType), [.markedHelpful, .markedStillConfused])
    }

    func testOnlyCurrentRequestMayInstallProposal() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let generator = DeferredAIProposalGenerator()
        let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

        let staleRequestID = coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteID)
        coordinator.invalidateActiveRequest()
        let currentRequestID = coordinator.begin(action: .analogy, noteContext: textView.string, noteID: noteID)

        if let staleRequestID {
            generator.complete(requestID: staleRequestID, response: "Stale response.")
        }
        if let currentRequestID {
            generator.complete(requestID: currentRequestID, response: "Current analogy.")
        }

        XCTAssertEqual(coordinator.proposal?.action, .analogy)
        XCTAssertEqual(coordinator.proposal?.generatedText, "Current analogy.")
        XCTAssertEqual(coordinator.proposal?.originatingRequestID, currentRequestID)
    }

    func testProposalBecomesStaleAfterDocumentChange() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Generated beta.")
        )
        let originalSnapshot = DocumentSnapshot(noteID: noteID, content: textView.string)

        coordinator.begin(
            action: .expand,
            selection: (text: "beta", range: NSRange(location: 6, length: 4)),
            noteContext: textView.string,
            noteID: noteID,
            documentSnapshot: originalSnapshot
        )
        textView.string = "Alpha beta changed"
        let currentSnapshot = DocumentSnapshot(noteID: noteID, content: textView.string)

        let accepted = coordinator.acceptProposal(selectedNoteID: noteID, currentSnapshot: currentSnapshot)

        XCTAssertNil(accepted)
        XCTAssertEqual(coordinator.proposal?.state, .stale)
        XCTAssertFalse(textView.string.contains("Generated beta."))
    }

    func testAcceptRefusesStaleProposal() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Generated beta.")
        )
        let originalSnapshot = DocumentSnapshot(noteID: noteID, content: textView.string)

        coordinator.begin(
            action: .expand,
            selection: (text: "beta", range: NSRange(location: 6, length: 4)),
            noteContext: textView.string,
            noteID: noteID,
            documentSnapshot: originalSnapshot
        )

        let accepted = coordinator.acceptProposal(
            selectedNoteID: noteID,
            currentSnapshot: DocumentSnapshot(noteID: noteID, content: "Alpha beta gamma plus edit")
        )

        XCTAssertNil(accepted)
        XCTAssertEqual(coordinator.proposal?.state, .stale)
        XCTAssertEqual(textView.string, "Alpha beta gamma")
    }

    func testProposalStoresDocumentSnapshot() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let snapshot = DocumentSnapshot(noteID: noteID, content: textView.string)
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Generated beta.")
        )

        coordinator.begin(
            action: .expand,
            selection: (text: "beta", range: NSRange(location: 6, length: 4)),
            noteContext: textView.string,
            noteID: noteID,
            documentSnapshot: snapshot
        )

        XCTAssertEqual(coordinator.proposal?.documentSnapshot, snapshot)
        XCTAssertEqual(coordinator.proposal?.state, .ready)
    }

    func testCoordinatorRejectsCrossNoteAccept() {
        let noteA = UUID()
        let noteB = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let coordinator = AIProposalCoordinator(
            bridge: bridge,
            generator: MockAIProposalGenerator(response: "Generated beta.")
        )

        coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteA)
        let accepted = coordinator.acceptProposal(selectedNoteID: noteB)

        XCTAssertNil(accepted)
        XCTAssertEqual(coordinator.proposal?.state, .invalidated)
        XCTAssertEqual(textView.string, "Alpha beta gamma")
    }

    func testRejectCancelsOutstandingGeneration() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let generator = CancellableAIProposalGenerator()
        let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

        let requestID = coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteID)
        let rejected = coordinator.rejectProposal()

        XCTAssertNil(rejected)
        XCTAssertEqual(requestID.map(generator.isCancelled), true)
        XCTAssertEqual(coordinator.state, .invalidated)
    }

    func testNoteSwitchCancelsOutstandingGeneration() {
        let noteA = UUID()
        let noteB = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let generator = CancellableAIProposalGenerator()
        let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

        let requestID = coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteA)
        coordinator.noteDidChange(to: noteB)

        XCTAssertEqual(requestID.map(generator.isCancelled), true)
        XCTAssertEqual(coordinator.state, .invalidated)
        XCTAssertNil(coordinator.proposal)
    }

    func testNewGenerationCancelsPreviousGeneration() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let generator = CancellableAIProposalGenerator()
        let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

        let firstRequestID = coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteID)
        let secondRequestID = coordinator.begin(action: .explain, noteContext: textView.string, noteID: noteID)

        XCTAssertNotNil(firstRequestID)
        XCTAssertNotNil(secondRequestID)
        XCTAssertNotEqual(firstRequestID, secondRequestID)
        XCTAssertEqual(firstRequestID.map(generator.isCancelled), true)
        XCTAssertEqual(coordinator.activeRequestID, secondRequestID)
        XCTAssertEqual(coordinator.state, .generating)
        coordinator.invalidateActiveRequest()
    }

    func testInvalidatedCompletionCannotBecomeReady() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let generator = DeferredAIProposalGenerator()
        let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

        let requestID = coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteID)
        coordinator.invalidateActiveRequest()
        if let requestID {
            generator.complete(requestID: requestID, response: "Late response.")
        }

        XCTAssertNil(coordinator.proposal)
        XCTAssertEqual(coordinator.state, .invalidated)
        XCTAssertEqual(textView.string, "Alpha beta gamma")
    }

    func testProposalStateTransitionsRemainValid() {
        let noteID = UUID()
        let (bridge, textView) = makeProposalBridge(text: "Alpha beta gamma", selection: NSRange(location: 6, length: 4))
        let generator = DeferredAIProposalGenerator()
        let coordinator = AIProposalCoordinator(bridge: bridge, generator: generator)

        let requestID = coordinator.begin(action: .expand, noteContext: textView.string, noteID: noteID)
        XCTAssertEqual(coordinator.state, .generating)

        if let requestID {
            generator.complete(requestID: requestID, response: "Generated beta.")
        }
        XCTAssertEqual(coordinator.state, .ready)
        XCTAssertEqual(coordinator.proposal?.state, .ready)

        let accepted = coordinator.acceptProposal(selectedNoteID: noteID)
        XCTAssertEqual(accepted?.state, .accepted)
        XCTAssertEqual(coordinator.state, .accepted)
    }

    func testDocumentSnapshotUsesCurrentVersion() {
        let noteID = UUID()
        let first = DocumentSnapshot(noteID: noteID, content: "Alpha beta gamma")
        let same = DocumentSnapshot(noteID: noteID, content: "Alpha beta gamma")
        let changed = DocumentSnapshot(noteID: noteID, content: "Alpha beta changed")

        XCTAssertEqual(first.contentHash, same.contentHash)
        XCTAssertEqual(first.documentVersion, same.documentVersion)
        XCTAssertTrue(first.matches(same))
        XCTAssertNotEqual(first.contentHash, changed.contentHash)
        XCTAssertFalse(first.matches(changed))
    }

    func testLearningSignalAcceptCreatesSignal() {
        let store = makeLearningSignalStore()
        let recorder = LearningSignalRecorder(store: store)
        let proposal = makeLearningSignalProposal(generatedText: "Generated explanation.")

        let signal = recorder.recordAccepted(proposal: proposal, finalText: "Generated explanation.")

        XCTAssertEqual(signal.signalType, .accepted)
        XCTAssertEqual(signal.proposalID, proposal.id)
        XCTAssertEqual(signal.sourceAction, .dontUnderstand)
        XCTAssertEqual(signal.conceptIDs, ["concept-a"])
        XCTAssertEqual(store.signals(for: proposal.id), [signal])
    }

    func testLearningSignalRejectCreatesSignal() {
        let store = makeLearningSignalStore()
        let recorder = LearningSignalRecorder(store: store)
        let proposal = makeLearningSignalProposal()

        let signal = recorder.recordRejected(proposal: proposal)

        XCTAssertEqual(signal.signalType, .rejected)
        XCTAssertLessThan(signal.confidenceDelta, 0)
        XCTAssertEqual(store.signals(for: proposal.id), [signal])
    }

    func testLearningSignalEditedAcceptCreatesCorrectSignalType() {
        let store = makeLearningSignalStore()
        let recorder = LearningSignalRecorder(store: store)
        let lightlyEditedProposal = makeLearningSignalProposal(generatedText: "Generated explanation.")
        let heavilyEditedProposal = makeLearningSignalProposal(generatedText: "Generated explanation.")

        let lightSignal = recorder.recordAccepted(
            proposal: lightlyEditedProposal,
            finalText: "Generated explanation!"
        )
        let heavySignal = recorder.recordAccepted(
            proposal: heavilyEditedProposal,
            finalText: "A completely different explanation with a new structure."
        )

        XCTAssertEqual(lightSignal.signalType, .lightlyEdited)
        XCTAssertEqual(heavySignal.signalType, .heavilyEdited)
    }

    func testAdaptiveFeedbackCreatesHelpfulAndStillConfusedSignals() {
        let store = makeLearningSignalStore()
        let recorder = LearningSignalRecorder(store: store)
        let proposal = makeLearningSignalProposal()

        let helpful = recorder.recordHelpful(proposal: proposal)
        let stillConfused = recorder.recordStillConfused(proposal: proposal)

        XCTAssertEqual(helpful.signalType, .markedHelpful)
        XCTAssertGreaterThan(helpful.confidenceDelta, 0)
        XCTAssertEqual(stillConfused.signalType, .markedStillConfused)
        XCTAssertLessThan(stillConfused.confidenceDelta, 0)
        XCTAssertEqual(store.signals(for: proposal.id).map(\.signalType), [.markedHelpful, .markedStillConfused])
    }

    func testLearningSignalsPersistLocally() {
        let suiteName = "notinq.learning.signals.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LearningSignalStore(defaults: defaults, storageKey: "signals")
        let proposal = makeLearningSignalProposal()
        let signal = LearningSignal(
            proposalID: proposal.id,
            conceptIDs: ["concept-a"],
            signalType: .accepted,
            confidenceDelta: 0.05,
            sourceAction: .dontUnderstand
        )

        store.append(signal)
        let reloadedStore = LearningSignalStore(defaults: defaults, storageKey: "signals")

        XCTAssertEqual(reloadedStore.allSignals(), [signal])
    }

    func testAdaptiveExplanationFeedbackOnlyAppearsForDontUnderstand() {
        let adaptiveProposal = makeLearningSignalProposal(action: .dontUnderstand)
        let explainProposal = makeLearningSignalProposal(action: .explain)

        XCTAssertTrue(AdaptiveExplanationFeedbackView.isVisible(for: adaptiveProposal))
        XCTAssertFalse(AdaptiveExplanationFeedbackView.isVisible(for: explainProposal))
        XCTAssertFalse(AdaptiveExplanationFeedbackView.isVisible(for: nil))
    }

    private func makeLearningSignalStore() -> LearningSignalStore {
        let suiteName = "notinq.learning.signals.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return LearningSignalStore(defaults: defaults, storageKey: "signals")
    }

    private func makeSourceBackedAdaptiveContext() -> AdaptiveExplanationContext {
        AdaptiveExplanationContext(
            conceptIDs: ["chain-rule", "partial-derivatives"],
            weakConcepts: ["Partial Derivatives"],
            strongConcepts: ["Derivatives"],
            missingPrerequisites: ["Chain Rule"],
            retrievedNoteSources: [
                AdaptiveExplanationSource(
                    sourceID: "chunk-backprop-4",
                    sourceType: "chunk",
                    noteID: UUID(uuidString: "11111111-1111-4111-8111-111111111111"),
                    noteTitle: "Lecture 4 — Backpropagation",
                    sectionTitle: "Gradients",
                    snippet: "Chain rule through layers.",
                    relevantExcerpt: "In backpropagation, the chain rule allows gradients to propagate backward through layers."
                )
            ],
            inferredLearnerLevel: "Needs prerequisite support",
            confidence: 0.72
        )
    }

    private func makeLearningSignal(
        conceptIDs: [String],
        type: LearningSignalType,
        timestamp: Date = Date()
    ) -> LearningSignal {
        LearningSignal(
            proposalID: UUID(),
            conceptIDs: conceptIDs,
            timestamp: timestamp,
            signalType: type,
            confidenceDelta: 0,
            sourceAction: .dontUnderstand
        )
    }

    private func makeLearningSignalProposal(
        action: AIEditorAction = .dontUnderstand,
        generatedText: String = "Generated explanation."
    ) -> AIProposal {
        AIProposal(
            action: action,
            originalText: "Original concept",
            generatedText: generatedText,
            insertionRange: NSRange(location: 16, length: 0),
            originalSelectionRange: NSRange(location: 0, length: 16),
            adaptiveExplanationContext: AdaptiveExplanationContext(
                conceptIDs: ["concept-a"],
                weakConcepts: ["Weak Concept"],
                strongConcepts: ["Known Concept"],
                missingPrerequisites: ["Prerequisite"],
                retrievedNoteSources: [AdaptiveExplanationSource(noteTitle: "Source Note")],
                inferredLearnerLevel: "Needs prerequisite support",
                confidence: 0.7
            )
        )
    }

    func testSemanticStudyColorsAdaptToAppearances() {
        let lightAppearance = NSAppearance(named: .aqua)
        let darkAppearance = NSAppearance(named: .darkAqua)
        XCTAssertNotNil(lightAppearance)
        XCTAssertNotNil(darkAppearance)

        guard let lightAppearance, let darkAppearance else { return }

        let lightNotes = resolvedRGBComponents(Color.resolvedNotesPaneBackground(for: lightAppearance))
        let darkNotes = resolvedRGBComponents(Color.resolvedNotesPaneBackground(for: darkAppearance))
        XCTAssertGreaterThan(lightNotes.red + lightNotes.green + lightNotes.blue, darkNotes.red + darkNotes.green + darkNotes.blue)

        let lightSurface = resolvedRGBComponents(Color.resolvedStudySurface(for: lightAppearance))
        let darkSurface = resolvedRGBComponents(Color.resolvedStudySurface(for: darkAppearance))
        XCTAssertNotEqual(lightSurface.red, darkSurface.red)
        XCTAssertNotEqual(lightSurface.green, darkSurface.green)
        XCTAssertNotEqual(lightSurface.blue, darkSurface.blue)

        let lightRaised = resolvedRGBComponents(Color.resolvedStudySurfaceRaised(for: lightAppearance))
        let darkRaised = resolvedRGBComponents(Color.resolvedStudySurfaceRaised(for: darkAppearance))
        XCTAssertNotEqual(lightRaised.red, darkRaised.red)
        XCTAssertNotEqual(lightRaised.green, darkRaised.green)
        XCTAssertNotEqual(lightRaised.blue, darkRaised.blue)

        let lightBorder = resolvedRGBComponents(Color.resolvedStudyBorderSoft(for: lightAppearance))
        let darkBorder = resolvedRGBComponents(Color.resolvedStudyBorderSoft(for: darkAppearance))
        XCTAssertLessThan(lightBorder.alpha, darkBorder.alpha)
    }

    func testKnowledgeGraphColorsAdaptToAppearances() {
        let lightAppearance = NSAppearance(named: .aqua)
        let darkAppearance = NSAppearance(named: .darkAqua)
        XCTAssertNotNil(lightAppearance)
        XCTAssertNotNil(darkAppearance)

        guard let lightAppearance, let darkAppearance else { return }

        let lightSurface = resolvedRGBComponents(Color.resolvedGraphSurface(for: lightAppearance))
        let darkSurface = resolvedRGBComponents(Color.resolvedGraphSurface(for: darkAppearance))
        XCTAssertGreaterThan(lightSurface.red + lightSurface.green + lightSurface.blue, darkSurface.red + darkSurface.green + darkSurface.blue)

        let lightRaised = resolvedRGBComponents(Color.resolvedGraphSurfaceRaised(for: lightAppearance))
        let darkRaised = resolvedRGBComponents(Color.resolvedGraphSurfaceRaised(for: darkAppearance))
        XCTAssertNotEqual(lightRaised.red, darkRaised.red)
        XCTAssertNotEqual(lightRaised.green, darkRaised.green)
        XCTAssertNotEqual(lightRaised.blue, darkRaised.blue)

        let lightBorder = resolvedRGBComponents(Color.resolvedGraphBorderSoft(for: lightAppearance))
        let darkBorder = resolvedRGBComponents(Color.resolvedGraphBorderSoft(for: darkAppearance))
        XCTAssertNotEqual(lightBorder.alpha, darkBorder.alpha)
    }

    func testLearningInsightsPanelFitsWithinTheEditorPane() {
        let editorPaneSize = CGSize(width: 980, height: 780)
        let panelSize = MainContainerView.learningInsightsPanelSize(for: editorPaneSize)

        XCTAssertLessThanOrEqual(panelSize.width, editorPaneSize.width - 36)
        XCTAssertLessThanOrEqual(panelSize.height, editorPaneSize.height)
    }

    func testLearningInsightsPhaseAndButtonAvailabilityReflectLoadingStates() {
        XCTAssertEqual(LearningInsightsAnalysisPhase.idle.statusText, "Add a transcript or slide notes, then run the analysis.")
        XCTAssertEqual(LearningInsightsAnalysisPhase.loading.statusText, "Analyzing lecture sources...")
        XCTAssertEqual(LearningInsightsAnalysisPhase.ready.statusText, "Analysis updated.")
        XCTAssertEqual(LearningInsightsAnalysisPhase.empty.statusText, "No lecture concepts were identified.")
        XCTAssertEqual(LearningInsightsAnalysisPhase.failure("Bad request").statusText, "Bad request")

        XCTAssertTrue(LearningInsightsButtonAvailability.canAnalyze(isAnalyzing: false, hasSourceText: true))
        XCTAssertFalse(LearningInsightsButtonAvailability.canAnalyze(isAnalyzing: true, hasSourceText: true))
        XCTAssertFalse(LearningInsightsButtonAvailability.canAnalyze(isAnalyzing: false, hasSourceText: false))

        XCTAssertTrue(LearningInsightsButtonAvailability.canGenerate(isAnalyzing: false, hasConceptSelection: true))
        XCTAssertFalse(LearningInsightsButtonAvailability.canGenerate(isAnalyzing: true, hasConceptSelection: true))
        XCTAssertFalse(LearningInsightsButtonAvailability.canGenerate(isAnalyzing: false, hasConceptSelection: false))

        XCTAssertTrue(LearningInsightsButtonAvailability.canInsert(isAnalyzing: false, hasGeneratedPreview: true))
        XCTAssertFalse(LearningInsightsButtonAvailability.canInsert(isAnalyzing: true, hasGeneratedPreview: true))
        XCTAssertFalse(LearningInsightsButtonAvailability.canInsert(isAnalyzing: false, hasGeneratedPreview: false))
    }

    func testLearningInsightsWorkspaceModelPreventsDuplicateAnalyzeRequestsWhileLoading() {
        var analyzerCalls = 0
        let saveExpectation = expectation(description: "analysis saved")
        let model = makeLearningInsightsWorkspaceModel(
            analyzer: { input in
                analyzerCalls += 1
                Thread.sleep(forTimeInterval: 0.15)
                return self.sampleAnalysis(summary: "Completed \(input.sources.count) sources")
            },
            onSaveAnalysis: { _ in
                saveExpectation.fulfill()
            }
        )

        model.analyzeLecture(transcript: "Transcript text", slides: "Slide text")
        XCTAssertTrue(model.isAnalyzing)
        model.analyzeLecture(transcript: "Transcript text", slides: "Slide text")

        wait(for: [saveExpectation], timeout: 2.0)

        XCTAssertEqual(analyzerCalls, 1)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.statusMessage, "Completed 2 sources")
        XCTAssertNotNil(model.analysis)
        XCTAssertTrue(model.hasSelectedConcept)
    }

    func testLearningInsightsWorkspaceModelRetriesAfterFailureAndRefreshesState() {
        var analyzerCalls = 0
        let saveExpectation = expectation(description: "analysis saved after retry")
        let model = makeLearningInsightsWorkspaceModel(
            analyzer: { _ in
                analyzerCalls += 1
                if analyzerCalls == 1 {
                    struct Failure: Error {}
                    throw Failure()
                }
                return self.sampleAnalysis(summary: "Recovered on retry")
            },
            onSaveAnalysis: { _ in
                saveExpectation.fulfill()
            }
        )

        model.analyzeLecture(transcript: "Transcript text", slides: "Slide text")

        let failureExpectation = expectation(for: NSPredicate { _, _ in
            if case .failure = model.phase {
                return true
            }
            return false
        }, evaluatedWith: NSObject())
        wait(for: [failureExpectation], timeout: 2.0)

        if case .failure(let message) = model.phase {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("Expected failure phase")
        }

        model.retryAnalysis(transcript: "Transcript text", slides: "Slide text")
        wait(for: [saveExpectation], timeout: 2.0)

        XCTAssertEqual(analyzerCalls, 2)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.statusMessage, "Recovered on retry")
        XCTAssertNotNil(model.analysis)
    }

    func testLearningInsightsWorkspaceModelGeneratesAndInsertsPreview() {
        let insertionExpectation = expectation(description: "inserted preview")
        let model = makeLearningInsightsWorkspaceModel(
            initialAnalysis: sampleAnalysis(),
            onInsertIntoNote: { preview in
                XCTAssertFalse(preview.isEmpty)
                insertionExpectation.fulfill()
            }
        )

        guard let concept = model.analysis?.missingConcepts.first ?? model.analysis?.partiallyCapturedConcepts.first ?? model.analysis?.wellCoveredConcepts.first else {
            XCTFail("Expected a concept from the seeded analysis")
            return
        }

        model.generatePreview(for: concept, mode: .flashcards)
        XCTAssertEqual(model.previewMode, .flashcards)
        XCTAssertFalse(model.generatedPreview.isEmpty)
        XCTAssertTrue(model.generatedPreview.contains(concept.title))

        model.insertGeneratedPreview()
        wait(for: [insertionExpectation], timeout: 1.0)
        XCTAssertEqual(model.statusMessage, "Inserted the generated content into the note.")
    }

    func testSearchNavigationHelperClampsToAvailableResults() {
        XCTAssertEqual(SearchView.selectedResultIndex(currentIndex: nil, direction: .up, resultCount: 3), 0)
        XCTAssertEqual(SearchView.selectedResultIndex(currentIndex: nil, direction: .down, resultCount: 3), 1)
        XCTAssertEqual(SearchView.selectedResultIndex(currentIndex: 0, direction: .up, resultCount: 3), 0)
        XCTAssertEqual(SearchView.selectedResultIndex(currentIndex: 2, direction: .down, resultCount: 3), 2)
    }

    func testSearchResultsSupportFuzzyQueries() {
        let appState = AppState()
        let folder = NoteFolder(
            title: "Machine Learning",
            notes: [
                NoteFile(title: "Neural Networks", content: "Backpropagation improves training stability.", updatedAt: Date()),
                NoteFile(title: "References", content: "Unrelated content.", updatedAt: Date())
            ]
        )
        appState.folders = [folder]

        let results = SearchView.searchResults(
            query: "backprop",
            folders: appState.folders,
            currentNoteOnly: false,
            selectedNoteID: nil
        )

        XCTAssertEqual(results.first?.title, "Neural Networks")
        XCTAssertTrue(results.first?.preview.lowercased().contains("backpropagation") == true)
    }

    func testCommandPaletteFilteringSurfacesRelevantActions() {
        let filtered = CommandBarView.filteredActions(
            for: "insghts",
            actions: CommandPaletteAction.defaultActions
        )

        XCTAssertEqual(filtered.first?.title, "Open Learning Insights")
    }

    func testShortcutRoutingMapsCoreAppCommands() {
        XCTAssertEqual(
            MainContainerView.shortcutAction(forCharacters: "k", modifiers: [.command]),
            .commandBar
        )
        XCTAssertEqual(
            MainContainerView.shortcutAction(forCharacters: "1", modifiers: [.command]),
            .notes
        )
        XCTAssertEqual(
            MainContainerView.shortcutAction(forCharacters: ",", modifiers: [.command]),
            .settings
        )
    }

    func testStudyGenerationRequestAdvancesAndClearsAppState() {
        let appState = AppState()

        appState.requestStudyGeneration()

        XCTAssertEqual(appState.selectedMode, .study)
        XCTAssertNotNil(appState.pendingStudyGenerationRequestID)

        appState.consumeStudyGenerationRequest()

        XCTAssertNil(appState.pendingStudyGenerationRequestID)
    }

    func testLearningInsightsWorkspaceModelTransitionsToReadyAndFailureStates() {
        let successModel = LearningInsightsWorkspaceModel(
            noteTitle: "Lecture Note",
            studentNotes: "Student notes",
            initialAnalysis: nil,
            onSaveAnalysis: { _ in },
            onInsertIntoNote: { _ in },
            analyzer: { input in
                XCTAssertEqual(input.sources.count, 2)
                return self.sampleAnalysis(summary: "Completed \(input.sources.count) sources")
            }
        )

        successModel.analyzeLecture(transcript: "Transcript", slides: "Slides")
        waitUntil(timeout: 1.0) {
            if case .ready = successModel.phase {
                return true
            }
            return false
        }
        XCTAssertEqual(successModel.statusMessage, "Completed 2 sources")

        let failureModel = LearningInsightsWorkspaceModel(
            noteTitle: "Lecture Note",
            studentNotes: "Student notes",
            initialAnalysis: nil,
            onSaveAnalysis: { _ in },
            onInsertIntoNote: { _ in },
            analyzer: { _ in
                throw NSError(domain: "NotinqTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to analyze"])
            }
        )

        failureModel.analyzeLecture(transcript: "Transcript", slides: "Slides")
        waitUntil(timeout: 1.0) {
            if case .failure(let message) = failureModel.phase {
                return message == "Unable to analyze"
            }
            return false
        }

        if case .failure(let message) = failureModel.phase {
            XCTAssertEqual(message, "Unable to analyze")
        } else {
            XCTFail("Expected failure phase")
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTFail("Condition was not met before timeout")
    }

    private func makeLearningInsightsWorkspaceModel(
        initialAnalysis: LectureCompletenessAnalysis? = nil,
        analyzer: @escaping (LectureAnalysisInput) throws -> LectureCompletenessAnalysis = { _ in
            LectureCompletenessAnalysis(summary: "Ready")
        },
        onSaveAnalysis: @escaping (LectureCompletenessAnalysis) -> Void = { _ in },
        onInsertIntoNote: @escaping (String) -> Void = { _ in }
    ) -> LearningInsightsWorkspaceModel {
        LearningInsightsWorkspaceModel(
            noteTitle: "Lecture Note",
            studentNotes: "Student notes about backpropagation.",
            initialAnalysis: initialAnalysis,
            onSaveAnalysis: onSaveAnalysis,
            onInsertIntoNote: onInsertIntoNote,
            analyzer: analyzer
        )
    }

    private func sampleAnalysis(summary: String = "Study analysis ready") -> LectureCompletenessAnalysis {
        let missing = LectureCoverageItem(
            title: "Backpropagation",
            state: .missing,
            whatWasMissed: "The error signal propagation step.",
            whyItMatters: "It is how neural networks learn.",
            shortExplanation: "Backpropagation moves error gradients backward.",
            suggestedAddition: "Add a concise note on gradient flow and weight updates.",
            importance: 1.0,
            evidence: ["Lecture transcript line 12"],
            matchScore: 0.92,
            noteSummary: "Not currently represented in the note."
        )
        let partial = LectureCoverageItem(
            title: "Gradient Descent",
            state: .partial,
            whatWasMissed: "The optimization loop details.",
            whyItMatters: "It is the core training step.",
            shortExplanation: "Gradient descent minimizes loss over time.",
            suggestedAddition: "Include the learning rate and update rule.",
            importance: 0.8,
            evidence: ["Slide 4"],
            matchScore: 0.74,
            noteSummary: "Mentioned briefly."
        )
        let covered = LectureCoverageItem(
            title: "Activation Functions",
            state: .covered,
            whatWasMissed: "Nothing major.",
            whyItMatters: "They add non-linearity.",
            shortExplanation: "Activation functions shape neuron output.",
            suggestedAddition: "Keep the current note as is.",
            importance: 0.6,
            evidence: ["Notes page 2"],
            matchScore: 0.88,
            noteSummary: "Covered well."
        )

        return LectureCompletenessAnalysis(
            completenessScore: 0.72,
            lectureConceptCount: 3,
            noteConceptCount: 2,
            missingConcepts: [missing],
            partiallyCapturedConcepts: [partial],
            wellCoveredConcepts: [covered],
            missingVisualContent: [],
            reviewPriority: [
                LectureReviewPriorityItem(rank: 1, title: missing.title, reason: "Highest gap score.", state: .missing, importance: 1.0),
                LectureReviewPriorityItem(rank: 2, title: partial.title, reason: "Worth fleshing out.", state: .partial, importance: 0.8)
            ],
            summary: summary,
            generatedAt: Date()
        )
    }

    private func resolvedRGBComponents(_ color: NSColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let resolved = color.usingColorSpace(.deviceRGB) ?? color
        return (resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent)
    }

}

final class DocumentPreprocessingAndValidationTests: XCTestCase {
    func testDocumentPreprocessorIdentifiesSectionsAndComplexity() {
        let text = """
        # Biology 101

        1. Cell structure
        2. DNA replication

        ```swift
        let x = 2 + 2
        ```

        Energy = mass * c^2
        | Term | Definition | Example |
        | Cell | Basic unit | Animal cell |
        """

        let structure = DocumentPreprocessor.shared.preprocess(title: "Biology 101", text: text)

        XCTAssertEqual(structure.title, "Biology 101")
        XCTAssertFalse(structure.sections.isEmpty)
        XCTAssertFalse(structure.headings.isEmpty)
        XCTAssertEqual(structure.codeBlocks.count, 1)
        XCTAssertGreaterThanOrEqual(structure.equations.count, 1)
        XCTAssertGreaterThanOrEqual(structure.tables.count, 1)
        XCTAssertGreaterThan(structure.complexity.tokenEstimate, 0)
        XCTAssertGreaterThan(structure.complexity.complexityScore, 0)
    }

    func testKnowledgeExtractionValidatorFlagsDuplicatesAndLowCoverage() {
        let payload = StructuredKnowledge(
            metadata: KnowledgeMetadata(title: "Biology 101", sourceType: "note"),
            title: "Biology 101",
            topics: ["Biology"],
            concepts: [
                KnowledgeConcept(name: "Cell", definition: "Basic unit of life", confidence: 0.9),
                KnowledgeConcept(name: "Cell", definition: "Basic unit of life", confidence: 0.2)
            ],
            definitions: [
                KnowledgeDefinition(term: "Cell", definition: "Basic unit of life", confidence: 0.8),
                KnowledgeDefinition(term: "Cell", definition: "Basic unit of life", confidence: 0.8)
            ],
            relationships: [
                KnowledgeRelationship(sourceID: "cell-1", targetID: "organism-1", relation: "includes", confidence: 0.8),
                KnowledgeRelationship(sourceID: "cell-1", targetID: "organism-1", relation: "includes", confidence: 0.8)
            ]
        )
        let structure = DocumentPreprocessor.shared.preprocess(title: "Biology 101", text: "Chapter 1\nCell theory")

        let normalized = KnowledgeValidator.normalize(payload: payload)
        let report = KnowledgeValidator.validate(payload: normalized, structure: structure)

        XCTAssertTrue(report.duplicateConceptCount > 0)
        XCTAssertTrue(report.duplicateRelationshipCount > 0)
        XCTAssertFalse(report.isValid)
        XCTAssertTrue(report.shouldRetry)
    }
}

@MainActor
final class AIEvaluationRegressionTests: XCTestCase {
    func testSampleNotesExposeStableUniqueIdentifiers() throws {
        XCTAssertEqual(AIEvaluationSamples.notes.count, 10)

        let identifiers = AIEvaluationSamples.notes.map(\.id)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)

        let lectureNotes = AIEvaluationSamples.notesBySet[.lecture] ?? []
        XCTAssertFalse(lectureNotes.isEmpty)
        XCTAssertTrue(lectureNotes.allSatisfy { $0.tags.contains("lecture") })
    }

    func testReviewPromptIncludesRequiredScoringGuidance() {
        let result = makeNoteResult(overallScore: 0.74)
        let prompt = AIEvaluationReviewPromptBuilder.build(for: result)

        XCTAssertTrue(prompt.contains("accuracy"))
        XCTAssertTrue(prompt.contains("flashcard quality"))
        XCTAssertTrue(prompt.contains(result.noteName))
        XCTAssertTrue(prompt.contains("Return structured JSON"))
    }

    func testComparisonReportHighlightsScoreDeltas() {
        let runner = AIEvaluationRunner()
        let baseline = makeManifest(modelName: "Phi-4 Mini", noteID: "computer-science-lecture-01", score: 0.58, noteName: "Computer Science Lecture")
        let comparison = makeManifest(modelName: "Qwen 2.5", noteID: "computer-science-lecture-01", score: 0.83, noteName: "Computer Science Lecture")

        let report = runner.compare(baseline: baseline, comparison: comparison)

        XCTAssertEqual(report.title, "Phi-4 Mini vs Qwen 2.5")
        XCTAssertEqual(report.comparisons.count, 1)
        XCTAssertEqual(report.comparisons.first?.title, "Computer Science Lecture")
        XCTAssertEqual(report.comparisons.first?.scoreDelta ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertTrue(report.comparisons.first?.improvements.first?.contains("improved") == true)
    }

    func testRegressionReportCapturesPerformanceAndScoreDeltas() {
        let runner = AIEvaluationRunner()
        var baseline = makeNoteResult(overallScore: 0.55)
        baseline.performanceMetrics.generationTime = 6.0
        baseline.performanceMetrics.memoryUsageMB = 900

        var comparison = makeNoteResult(overallScore: 0.81)
        comparison.performanceMetrics.generationTime = 4.0
        comparison.performanceMetrics.memoryUsageMB = 850

        let report = runner.regressionReport(baseline: baseline, comparison: comparison)

        XCTAssertEqual(report.baselineModel, baseline.modelName)
        XCTAssertEqual(report.comparisonModel, comparison.modelName)
        XCTAssertEqual(report.scoreDeltas.first?.metric, "overall")
        XCTAssertEqual(report.latencyDelta, -2.0, accuracy: 0.0001)
        XCTAssertEqual(report.memoryDeltaMB, -50.0, accuracy: 0.0001)
    }

    func testBenchmarkReportRanksModelsByQuality() {
        let runner = AIEvaluationRunner()
        let first = makeManifest(modelName: "Phi-4 Mini", noteID: "biology-lecture-01", score: 0.65, noteName: "Biology Lecture")
        let second = makeManifest(modelName: "Qwen 2.5", noteID: "biology-lecture-01", score: 0.85, noteName: "Biology Lecture")

        let report = runner.benchmarkReport(from: [first, second], datasetName: "Lecture Notes")

        XCTAssertEqual(report.datasetName, "Lecture Notes")
        XCTAssertEqual(report.rankings.first?.modelName, "Qwen 2.5")
        XCTAssertEqual(report.rankings.first?.rank, 1)
        XCTAssertEqual(report.rankings.last?.modelName, "Phi-4 Mini")
    }

    func testPromptImprovementReportFindsRepeatedWeaknesses() {
        let runner = AIEvaluationRunner()
        var result = makeNoteResult(overallScore: 0.52)
        result.localScores.summary.repetition = 0.2
        result.localScores.flashcards.conceptCoverage = 0.4
        result.localScores.quiz.explanationPresence = 0.2
        result.localScores.conceptMap.missingRelationships = 0.7
        result.localScores.learningInsights.actionability = 0.2

        let report = runner.promptImprovementReport(from: [result], datasetName: "Lecture Notes")

        XCTAssertFalse(report.recommendations.isEmpty)
        XCTAssertTrue(report.recommendations.contains { $0.affectedPrompt == "summary" })
        XCTAssertTrue(report.recommendations.contains { $0.affectedPrompt == "quiz" })
    }

    func testGoldStandardEvaluatorProducesCombinedSemanticReport() async {
        let note = AIEvaluationSamples.notes.first!
        let engine = AIEvaluationEngine()
        let outputs = AIEvaluationOutputs(
            summary: "Binary search trees support ordered traversal.",
            flashcards: [StudyFlashcard(type: .definition, front: "BST", back: "Ordered traversal", whyItMatters: "Searches rely on it")],
            quiz: [StudyQuizQuestion(type: .multipleChoice, prompt: "What does a BST support?", options: ["Ordered traversal", "Random access"], correctAnswer: "Ordered traversal", explanation: "BSTs are ordered.", keywords: ["BST"])],
            conceptMap: [StudyConceptNode(title: "Binary Search Trees", children: [])],
            learningInsights: StudyInsights(keyConcepts: ["BST"], importantConcepts: ["Traversal"], frequentTerms: [StudyTerm(term: "tree", count: 2)], potentialExamTopics: ["Operations"], knowledgeGaps: ["Balancing"]),
            knowledgeSnapshot: StudyKnowledgeSnapshot(title: note.title)
        )
        let reference = AIEvaluationGoldStandardReference(
            noteID: note.id,
            subject: note.subject,
            summary: "Binary search trees support ordered traversal.",
            flashcards: outputs.flashcards,
            quiz: outputs.quiz,
            conceptMap: outputs.conceptMap,
            learningInsights: outputs.learningInsights,
            knowledgeSnapshot: outputs.knowledgeSnapshot
        )

        let bundle = await engine.combinedReport(
            note: note,
            outputs: outputs,
            localScores: makeLocalScores(overall: 0.8),
            performanceMetrics: AIEvaluationPerformanceMetrics(generationTime: 1.2, tokensPerSecond: 10, memoryUsageMB: 1200, contextSize: 4096, modelLoadTime: 0.5, latencyByFeature: [:], hallucinationCount: 0),
            reference: reference
        )

        XCTAssertNotNil(bundle.semantic)
        XCTAssertGreaterThan(bundle.combined.overallScore, 0)
    }

    func testPromptVersionComparisonHighlightsChangedPrompts() throws {
        let runner = AIEvaluationRunner()
        let baselineVersion = "1.0.0"
        let comparisonVersion = "1.0.1"
        let baselineSnapshots = [
            AIPromptSnapshotEntry(
                identifier: "summary",
                promptVersion: baselineVersion,
                systemPrompt: "Summarize carefully.",
                outputDescription: "Short summary",
                contentHash: "baseline",
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                changedPrompts: []
            )
        ]
        let comparisonSnapshots = [
            AIPromptSnapshotEntry(
                identifier: "summary",
                promptVersion: comparisonVersion,
                systemPrompt: "Summarize carefully and briefly.",
                outputDescription: "Short summary",
                contentHash: "comparison",
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
                changedPrompts: ["system_prompt"]
            )
        ]

        _ = try runner.storage.savePromptVersionSnapshot(baselineSnapshots, promptVersion: baselineVersion)
        _ = try runner.storage.savePromptVersionSnapshot(comparisonSnapshots, promptVersion: comparisonVersion)

        let report = runner.comparePromptVersions(baselineVersion: baselineVersion, comparisonVersion: comparisonVersion)

        XCTAssertEqual(report?.baselinePromptVersion, baselineVersion)
        XCTAssertEqual(report?.comparisonPromptVersion, comparisonVersion)
        XCTAssertEqual(report?.changes.first?.identifier, "summary")
        XCTAssertTrue(report?.changes.first?.changedPrompts.contains("system_prompt") == true)
    }

    private func makeNoteResult(overallScore: Double) -> AIEvaluationNoteResult {
        let note = AIEvaluationSamples.notes.first!
        return AIEvaluationNoteResult(
            id: "\(note.id)-\(UUID().uuidString)",
            noteID: note.id,
            noteName: note.title,
            evaluationDate: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "1.0",
            gitCommit: "abc1234",
            modelName: "Local Model",
            modelIdentifier: "local-model",
            promptVersion: "knowledge-extraction-v1",
            noteSet: AIEvaluationNoteSet.all.rawValue,
            rawNote: note.rawNote,
            promptsUsed: [
                AIEvaluationPromptSnapshot(
                    feature: "summary",
                    promptVersion: "summary-v1",
                    systemPrompt: "system",
                    userPrompt: "user",
                    outputDescription: "summary",
                    responseFormat: "text"
                )
            ],
            outputs: AIEvaluationOutputs(
                summary: "Concise summary",
                flashcards: [
                    StudyFlashcard(type: .definition, front: "What is BST?", back: "A tree...", whyItMatters: "Supports search")
                ],
                quiz: [
                    StudyQuizQuestion(type: .multipleChoice, prompt: "Which structure is balanced?", options: ["AVL", "Stack"], correctAnswer: "AVL", explanation: "AVL is balanced.", keywords: ["AVL"])
                ],
                conceptMap: [
                    StudyConceptNode(title: "Trees", children: [])
                ],
                learningInsights: StudyInsights(
                    keyConcepts: ["Trees"],
                    importantConcepts: ["Balancing"],
                    frequentTerms: [StudyTerm(term: "tree", count: 3)],
                    potentialExamTopics: ["Traversal"],
                    knowledgeGaps: ["Balancing tradeoffs"]
                ),
                knowledgeSnapshot: StudyKnowledgeSnapshot(title: "Computer Science Lecture")
            ),
            generationSettings: .default,
            localScores: makeLocalScores(overall: overallScore)
        )
    }

    private func makeManifest(modelName: String, noteID: String, score: Double, noteName: String) -> AIEvaluationRunManifest {
        let result = AIEvaluationNoteResult(
            id: "\(noteID)-\(modelName)",
            noteID: noteID,
            noteName: noteName,
            evaluationDate: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "1.0",
            gitCommit: "abc1234",
            modelName: modelName,
            modelIdentifier: modelName.lowercased(),
            promptVersion: "knowledge-extraction-v1",
            noteSet: AIEvaluationNoteSet.all.rawValue,
            rawNote: "Sample",
            promptsUsed: [],
            outputs: AIEvaluationOutputs(summary: "Summary"),
            generationSettings: .default,
            localScores: makeLocalScores(overall: score)
        )

        return AIEvaluationRunManifest(
            evaluationDate: Date(timeIntervalSince1970: 1_700_000_000),
            noteSet: AIEvaluationNoteSet.all.rawValue,
            appVersion: "1.0",
            gitCommit: "abc1234",
            modelName: modelName,
            modelIdentifier: modelName.lowercased(),
            promptVersion: "knowledge-extraction-v1",
            resultCount: 1,
            averageOverallScore: score,
            noteResults: [result]
        )
    }

    private func makeLocalScores(overall: Double) -> AIEvaluationLocalScores {
        var scores = AIEvaluationLocalScores()
        scores.summary = AIEvaluationFeatureScores(coverage: 0.8, repetition: 0.9, readability: 0.8, length: 0.7, structure: 0.9, overall: overall)
        scores.flashcards = AIEvaluationFlashcardScores(duplicates: 0.9, answerLength: 0.8, conceptCoverage: 0.8, specificity: 0.9, overall: overall)
        scores.quiz = AIEvaluationQuizScores(duplicateQuestions: 0.9, explanationPresence: 0.8, optionCount: 0.9, answerPresence: 0.9, overall: overall)
        scores.conceptMap = AIEvaluationConceptMapScores(disconnectedNodes: 0.8, missingRelationships: 0.9, duplication: 0.8, hierarchy: 0.9, overall: overall)
        scores.learningInsights = AIEvaluationInsightScores(missingConcepts: 0.8, repetition: 0.9, actionability: 0.8, overall: overall)
        scores.knowledgeSnapshot = AIEvaluationJSONScores(parsingSuccess: 1, schemaValidation: 1, completeness: 1, overall: overall)
        scores.overall = overall
        return scores
    }

    func testTeachMeSessionStateTransitions() {
        let engine = TeachMeEngine()
        let context = AdaptiveExplanationContext(identifiedKnowledgeGaps: ["Chain Rule"])

        let started = engine.startSession(adaptiveContext: context)
        XCTAssertEqual(started.state, .question)
        XCTAssertEqual(started.activeConceptName, "Chain Rule")

        let answering = engine.beginAnswering(started)
        XCTAssertEqual(answering.state, .answering)

        let feedback = engine.submitAnswer("The chain rule connects nested functions to derivatives.", for: answering)
        XCTAssertEqual(feedback.state, .feedback)
        XCTAssertEqual(feedback.answerHistory.count, 1)
    }

    func testTeachMeQuestionGeneration() {
        let engine = TeachMeEngine()
        let source = AdaptiveExplanationSource(noteTitle: "Lecture 4", relevantExcerpt: "The chain rule supports backpropagation.")
        let context = AdaptiveExplanationContext(
            identifiedKnowledgeGaps: ["Chain Rule"],
            retrievedNoteSources: [source]
        )

        let session = engine.startSession(adaptiveContext: context)

        XCTAssertEqual(session.activeQuestion?.conceptID, "chain rule")
        XCTAssertEqual(session.activeQuestion?.conceptName, "Chain Rule")
        XCTAssertEqual(session.activeQuestion?.originatingKnowledgeGap, "Chain Rule")
        XCTAssertEqual(session.activeQuestion?.sourceReferences.first?.noteTitle, "Lecture 4")
        XCTAssertTrue(session.activeQuestion?.question.contains("Chain Rule") ?? false)
    }

    func testTeachMeCorrectPathCompletes() {
        let engine = TeachMeEngine()
        let session = engine.beginAnswering(
            engine.startSession(adaptiveContext: AdaptiveExplanationContext(identifiedKnowledgeGaps: ["Gradient Descent"]))
        )

        let feedback = engine.submitAnswer(
            "Gradient descent adjusts parameters step by step to reduce loss in the model.",
            for: session
        )
        let complete = engine.advanceAfterFeedback(feedback)

        XCTAssertEqual(feedback.answerHistory.last?.evaluation, .correct)
        XCTAssertEqual(complete.state, .complete)
    }

    func testTeachMeIncorrectPathProducesFollowUp() {
        let engine = TeachMeEngine()
        let session = engine.beginAnswering(
            engine.startSession(adaptiveContext: AdaptiveExplanationContext(identifiedKnowledgeGaps: ["Partial Derivatives"]))
        )

        let feedback = engine.submitAnswer("No idea", for: session)
        let followUp = engine.advanceAfterFeedback(feedback)

        XCTAssertEqual(feedback.answerHistory.last?.evaluation, .incorrect)
        XCTAssertEqual(followUp.state, .question)
        XCTAssertEqual(followUp.followUpCount, 1)
        XCTAssertTrue(followUp.activeQuestion?.question.hasPrefix("Follow-up") ?? false)
    }

    func testTeachMePartiallyCorrectPathProducesFollowUp() {
        let engine = TeachMeEngine()
        let session = engine.beginAnswering(
            engine.startSession(adaptiveContext: AdaptiveExplanationContext(identifiedKnowledgeGaps: ["Backpropagation"]))
        )

        let feedback = engine.submitAnswer("It moves errors backward", for: session)
        let followUp = engine.advanceAfterFeedback(feedback)

        XCTAssertEqual(feedback.answerHistory.last?.evaluation, .partiallyCorrect)
        XCTAssertEqual(followUp.state, .question)
        XCTAssertEqual(followUp.followUpCount, 1)
    }

    func testTeachMeCompletionPathAfterFollowUp() {
        let engine = TeachMeEngine()
        let firstQuestion = engine.beginAnswering(
            engine.startSession(adaptiveContext: AdaptiveExplanationContext(identifiedKnowledgeGaps: ["Normalization"]))
        )
        let firstFeedback = engine.submitAnswer("Unsure", for: firstQuestion)
        let followUpQuestion = engine.beginAnswering(engine.advanceAfterFeedback(firstFeedback))
        let secondFeedback = engine.submitAnswer("Still unsure", for: followUpQuestion)
        let complete = engine.advanceAfterFeedback(secondFeedback)

        XCTAssertEqual(complete.state, .complete)
        XCTAssertEqual(complete.answerHistory.count, 2)
    }

    func testTeachMeSessionPersistence() throws {
        var studyData = NoteStudyData()
        studyData.teachMeSession = TeachMeEngine().startSession(
            adaptiveContext: AdaptiveExplanationContext(identifiedKnowledgeGaps: ["Indexes"])
        )

        let encoded = try JSONEncoder().encode(studyData)
        let decoded = try JSONDecoder().decode(NoteStudyData.self, from: encoded)

        XCTAssertEqual(decoded.teachMeSession?.state, .question)
        XCTAssertEqual(decoded.teachMeSession?.activeConceptName, "Indexes")
    }

    func testTeachMeLearningSignalRecording() {
        let defaults = UserDefaults(suiteName: "TeachMeLearningSignalRecording-\(UUID().uuidString)")!
        let store = LearningSignalStore(defaults: defaults, storageKey: "signals")
        let recorder = LearningSignalRecorder(store: store)
        let question = TeachMeQuestion(
            conceptID: "chain rule",
            conceptName: "Chain Rule",
            question: "What is the key idea?"
        )

        recorder.recordTeachMeAttempt(question: question)
        recorder.recordTeachMeEvaluation(question: question, evaluation: .correct)

        let signals = store.allSignals()
        XCTAssertEqual(signals.map(\.signalType), [.questionAttempted, .questionCorrect])
        XCTAssertEqual(signals.flatMap(\.conceptIDs), ["chain rule", "chain rule"])
    }

    func testTeachMePrioritizesKnowledgeGap() {
        let context = AdaptiveExplanationContext(
            identifiedKnowledgeGaps: ["Chain Rule"],
            historicallyConfusingConcepts: ["Gradient Descent"],
            masteryStates: ["loss function": .struggling]
        )

        let candidate = TeachMeEngine().selectConcept(adaptiveContext: context, manualConcept: "Manual Topic")

        XCTAssertEqual(candidate?.conceptName, "Chain Rule")
        XCTAssertEqual(candidate?.source, .knowledgeGap)
    }

    func testTeachMeUsesMasteryFallbackWhenNoGapsExist() {
        let context = AdaptiveExplanationContext(
            masteryStates: [
                "derivative": .struggling,
                "matrix": .mastered
            ]
        )

        let candidate = TeachMeEngine().selectConcept(adaptiveContext: context, manualConcept: "Manual Topic")

        XCTAssertEqual(candidate?.conceptName, "derivative")
        XCTAssertEqual(candidate?.source, .weakMastery)
    }

}
