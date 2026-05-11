import AppKit
import Foundation

final class EditorInsertionManager {
    private weak var textView: NSTextView?
    private var liveRange: NSRange?
    private var previousDisplayedText = ""

    init(textView: NSTextView) {
        self.textView = textView
    }

    func beginSession() {
        guard let textView else { return }
        let insertionRange = textView.selectedRange()
        textView.insertText("[Listening…]", replacementRange: insertionRange)
        let start = insertionRange.location
        liveRange = NSRange(location: start, length: "[Listening…]".utf16.count)
        previousDisplayedText = "[Listening…]"
    }

    func applyPartial(_ text: String) {
        apply(text: text, fullReplace: false)
    }

    func applyRefined(_ text: String) {
        apply(text: text, fullReplace: true)
    }

    func finalize(_ text: String) {
        apply(text: text, fullReplace: true)
        previousDisplayedText = ""
        liveRange = nil
    }

    private func apply(text: String, fullReplace: Bool) {
        guard let textView, let range = liveRange else { return }

        if fullReplace {
            replace(in: textView, range: range, with: text)
            return
        }

        let old = previousDisplayedText
        let new = text
        let oldChars = Array(old)
        let newChars = Array(new)

        var prefix = 0
        while prefix < oldChars.count && prefix < newChars.count && oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }

        var oldSuffix = oldChars.count
        var newSuffix = newChars.count
        while oldSuffix > prefix && newSuffix > prefix && oldChars[oldSuffix - 1] == newChars[newSuffix - 1] {
            oldSuffix -= 1
            newSuffix -= 1
        }

        let replaceLocation = range.location + oldChars[..<prefix].map { String($0) }.joined().utf16.count
        let replaceLength = oldChars[prefix..<oldSuffix].map { String($0) }.joined().utf16.count
        let replacement = newChars[prefix..<newSuffix].map { String($0) }.joined()

        textView.shouldChangeText(in: NSRange(location: replaceLocation, length: replaceLength), replacementString: replacement)
        textView.textStorage?.replaceCharacters(in: NSRange(location: replaceLocation, length: replaceLength), with: replacement)
        textView.didChangeText()

        liveRange = NSRange(location: range.location, length: new.utf16.count)
        previousDisplayedText = new
    }

    private func replace(in textView: NSTextView, range: NSRange, with text: String) {
        textView.shouldChangeText(in: range, replacementString: text)
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        liveRange = NSRange(location: range.location, length: text.utf16.count)
        previousDisplayedText = text
    }
}
