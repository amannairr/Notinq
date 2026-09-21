import Foundation

protocol AIProposalGenerating {
    func generate(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String,
        noteID: UUID?,
        completion: @escaping (String) -> Void
    )
}

struct LiveAIProposalGenerator: AIProposalGenerating {
    func generate(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String,
        noteID: UUID?,
        completion: @escaping (String) -> Void
    ) {
        AIService.shared.editorProposal(
            action: action,
            selectedText: selectedText,
            noteContext: noteContext,
            noteID: noteID,
            completion: completion
        )
    }
}

@MainActor
final class AIProposalCoordinator {
    private(set) var proposal: AIProposal?
    private(set) var isGenerating = false

    private let bridge: TextViewBridge
    private let generator: any AIProposalGenerating

    init(bridge: TextViewBridge, generator: any AIProposalGenerating) {
        self.bridge = bridge
        self.generator = generator
    }

    func beginExpand(noteContext: String, noteID: UUID?) {
        guard !isGenerating else { return }
        guard let selection = bridge.selectedTextAndRange() else { return }
        beginExpand(selection: selection, noteContext: noteContext, noteID: noteID)
    }

    func beginExpand(
        selection: (text: String, range: NSRange),
        noteContext: String,
        noteID: UUID?
    ) {
        guard !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isGenerating else { return }

        isGenerating = true
        let sourceRange = selection.range
        generator.generate(
            action: .expand,
            selectedText: selection.text,
            noteContext: noteContext,
            noteID: noteID
        ) { [weak self] response in
            guard let self else { return }
            self.isGenerating = false
            self.proposal = self.bridge.makeAIProposal(
                action: .expand,
                response: response,
                selectionRange: sourceRange,
                provenance: AIProposalProvenance(sourceNoteRange: sourceRange)
            )
        }
    }

    func editProposal(text: String) {
        guard let proposal else { return }
        self.proposal = bridge.editAIProposal(proposal, generatedText: text)
    }

    @discardableResult
    func acceptProposal(editedText: String? = nil) -> AIProposal? {
        guard let proposal else { return nil }
        let accepted = bridge.acceptAIProposal(proposal, editedText: editedText)
        self.proposal = nil
        return accepted
    }

    @discardableResult
    func rejectProposal() -> AIProposal? {
        guard let proposal else { return nil }
        let rejected = bridge.rejectAIProposal(proposal)
        bridge.restoreSelection(for: rejected)
        self.proposal = nil
        return rejected
    }
}
