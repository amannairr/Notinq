import Foundation

struct AIProposalGenerationResult {
    var generatedText: String
    var adaptiveExplanationContext: AdaptiveExplanationContext?
}

protocol AIProposalGenerating {
    @discardableResult
    func generate(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String,
        noteID: UUID?,
        requestID: UUID,
        completion: @escaping (UUID, AIProposalGenerationResult) -> Void
    ) -> Task<Void, Never>?
}

struct LiveAIProposalGenerator: AIProposalGenerating {
    @discardableResult
    func generate(
        action: AIEditorAction,
        selectedText: String,
        noteContext: String,
        noteID: UUID?,
        requestID: UUID,
        completion: @escaping (UUID, AIProposalGenerationResult) -> Void
    ) -> Task<Void, Never>? {
        AIService.shared.editorProposal(
            action: action,
            selectedText: selectedText,
            noteContext: noteContext,
            noteID: noteID,
            completion: { result in
                completion(requestID, result)
            }
        )
    }
}

@MainActor
final class AIProposalCoordinator {
    private(set) var proposal: AIProposal?
    private(set) var isGenerating = false
    private(set) var activeRequestID: UUID?
    private(set) var activeNoteID: UUID?
    private(set) var state: ProposalState = .idle

    private let bridge: TextViewBridge
    private let generator: any AIProposalGenerating
    private var activeGenerationTask: Task<Void, Never>?

    init(bridge: TextViewBridge, generator: any AIProposalGenerating) {
        self.bridge = bridge
        self.generator = generator
    }

    @discardableResult
    func beginExpand(noteContext: String, noteID: UUID?) -> UUID? {
        begin(action: .expand, noteContext: noteContext, noteID: noteID)
    }

    @discardableResult
    func beginExpand(
        selection: (text: String, range: NSRange),
        noteContext: String,
        noteID: UUID?
    ) -> UUID? {
        begin(action: .expand, selection: selection, noteContext: noteContext, noteID: noteID)
    }

    @discardableResult
    func begin(action: AIEditorAction, noteContext: String, noteID: UUID?) -> UUID? {
        guard proposal == nil else { return nil }
        guard let selection = bridge.selectedTextAndRange() else { return nil }
        return begin(action: action, selection: selection, noteContext: noteContext, noteID: noteID)
    }

    @discardableResult
    func begin(
        action: AIEditorAction,
        selection: (text: String, range: NSRange),
        noteContext: String,
        noteID: UUID?,
        documentSnapshot: DocumentSnapshot? = nil,
        requestID: UUID = UUID()
    ) -> UUID? {
        guard !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard proposal == nil else { return nil }
        cancelActiveGeneration(markInvalidated: true)

        isGenerating = true
        state = .generating
        activeRequestID = requestID
        activeNoteID = noteID
        let sourceRange = selection.range
        activeGenerationTask = generator.generate(
            action: action,
            selectedText: selection.text,
            noteContext: noteContext,
            noteID: noteID,
            requestID: requestID
        ) { [weak self] completedRequestID, response in
            guard let self else { return }
            guard self.activeRequestID == completedRequestID,
                  self.activeNoteID == noteID else {
                self.state = .invalidated
                return
            }
            self.isGenerating = false
            self.activeGenerationTask = nil
            let adaptiveContext = response.adaptiveExplanationContext ?? (action == .dontUnderstand ? .unavailable() : nil)
            let proposal = self.bridge.makeAIProposal(
                action: action,
                response: response.generatedText,
                selectionRange: sourceRange,
                originatingNoteID: noteID,
                originatingRequestID: completedRequestID,
                documentSnapshot: documentSnapshot,
                provenance: AIProposalProvenance(sourceNoteRange: sourceRange),
                adaptiveExplanationContext: adaptiveContext
            )
            self.proposal = proposal
            self.state = proposal == nil ? .idle : .ready
            if proposal == nil {
                self.activeRequestID = nil
                self.activeNoteID = nil
            }
        }
        return requestID
    }

    func editProposal(text: String) {
        guard let proposal else { return }
        self.proposal = bridge.editAIProposal(proposal, generatedText: text)
    }

    @discardableResult
    func acceptProposal(
        selectedNoteID: UUID?,
        currentSnapshot: DocumentSnapshot? = nil,
        editedText: String? = nil
    ) -> AIProposal? {
        guard let proposal else { return nil }
        guard proposal.originatingNoteID == selectedNoteID,
              proposal.originatingRequestID == activeRequestID else {
            self.proposal = proposal.updating(state: .invalidated)
            state = .invalidated
            return nil
        }
        if let originalSnapshot = proposal.documentSnapshot,
           let currentSnapshot,
           !originalSnapshot.matches(currentSnapshot) {
            self.proposal = proposal.updating(state: .stale)
            state = .stale
            return nil
        }
        let accepted = bridge.acceptAIProposal(proposal, editedText: editedText)
        self.proposal = nil
        activeRequestID = nil
        activeNoteID = nil
        state = .accepted
        return accepted
    }

    @discardableResult
    func rejectProposal() -> AIProposal? {
        guard let proposal else {
            invalidateActiveRequest()
            return nil
        }
        cancelActiveGeneration(markInvalidated: false)
        let rejected = bridge.rejectAIProposal(proposal)
        bridge.restoreSelection(for: rejected)
        self.proposal = nil
        activeRequestID = nil
        activeNoteID = nil
        state = .rejected
        return rejected
    }

    func invalidateActiveRequest() {
        cancelActiveGeneration(markInvalidated: true)
        isGenerating = false
        activeRequestID = nil
        activeNoteID = nil
        state = .invalidated
    }

    func noteDidChange(to noteID: UUID?) {
        if activeNoteID == noteID && (proposal == nil || proposal?.originatingNoteID == noteID) {
            return
        }
        proposal = nil
        invalidateActiveRequest()
    }

    private func cancelActiveGeneration(markInvalidated: Bool) {
        activeGenerationTask?.cancel()
        activeGenerationTask = nil
        if markInvalidated, isGenerating {
            state = .invalidated
        }
    }
}
