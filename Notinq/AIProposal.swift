import Foundation

/// Editor-scoped AI actions that produce proposals before changing the note.
enum AIEditorAction: String, CaseIterable, Sendable {
    case expand
    case explain

    var blockTitle: String {
        switch self {
        case .expand: return "Expansion"
        case .explain: return "Explanation"
        }
    }
}

enum AIProposalStatus: String, Sendable {
    case pending
    case accepted
    case rejected
    case edited
}

struct AIProposalProvenance: Equatable, Sendable {
    var sourceNoteRange: NSRange?
    var transcriptReference: String?
    var slideReference: String?

    init(
        sourceNoteRange: NSRange? = nil,
        transcriptReference: String? = nil,
        slideReference: String? = nil
    ) {
        self.sourceNoteRange = sourceNoteRange
        self.transcriptReference = transcriptReference
        self.slideReference = slideReference
    }
}

struct AIProposal: Identifiable, Equatable, Sendable {
    let id: UUID
    let action: AIEditorAction
    let originalText: String
    var generatedText: String
    let insertionRange: NSRange
    let originalSelectionRange: NSRange
    let createdAt: Date
    let provenance: AIProposalProvenance
    var status: AIProposalStatus

    var insertionLocation: Int {
        insertionRange.location
    }

    init(
        id: UUID = UUID(),
        action: AIEditorAction,
        originalText: String,
        generatedText: String,
        insertionRange: NSRange,
        originalSelectionRange: NSRange,
        createdAt: Date = Date(),
        provenance: AIProposalProvenance = AIProposalProvenance(),
        status: AIProposalStatus = .pending
    ) {
        self.id = id
        self.action = action
        self.originalText = originalText
        self.generatedText = generatedText
        self.insertionRange = insertionRange
        self.originalSelectionRange = originalSelectionRange
        self.createdAt = createdAt
        self.provenance = provenance
        self.status = status
    }
}
