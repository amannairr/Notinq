import AppKit
import SwiftUI
import XCTest
@testable import Notinq

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
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()

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

    func testStudyOverflowAffordanceAppearsWhenContentExceedsViewport() {
        XCTAssertFalse(StudyView.verticalOverflowAffordanceVisible(contentHeight: 480, viewportHeight: 640))
        XCTAssertTrue(StudyView.verticalOverflowAffordanceVisible(contentHeight: 980, viewportHeight: 640))
    }

    func testStudyViewUsesEdgeToEdgeOuterChrome() {
        XCTAssertEqual(StudyView.outerChromePadding, 0)
        XCTAssertEqual(StudyView.outerChromeCornerRadius, 0)
    }

    func testSupplementalStudySectionsBehaveLikeSingleOpenAccordion() {
        var activeSection: SupplementalStudySection?

        XCTAssertNil(activeSection)

        activeSection = StudyView.toggledSupplementalSection(
            activeSection: activeSection,
            section: .learningMemory
        )
        XCTAssertEqual(activeSection, .learningMemory)

        activeSection = StudyView.toggledSupplementalSection(
            activeSection: activeSection,
            section: .knowledgeGaps
        )
        XCTAssertEqual(activeSection, .knowledgeGaps)

        activeSection = StudyView.toggledSupplementalSection(
            activeSection: activeSection,
            section: .knowledgeGaps
        )
        XCTAssertNil(activeSection)
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
