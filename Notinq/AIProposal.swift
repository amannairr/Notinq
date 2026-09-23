import Foundation

/// Editor-scoped AI actions that produce proposals before changing the note.
enum AIEditorAction: String, CaseIterable, Codable, Sendable {
    case expand
    case explain
    case simplify
    case example
    case analogy
    case dontUnderstand

    var blockTitle: String {
        switch self {
        case .expand: return "Expansion"
        case .explain: return "Explanation"
        case .simplify: return "Simplification"
        case .example: return "Example"
        case .analogy: return "Analogy"
        case .dontUnderstand: return "Adaptive Explanation"
        }
    }

    var displayTitle: String {
        switch self {
        case .expand: return "Expand"
        case .explain: return "Explain"
        case .simplify: return "Simplify"
        case .example: return "Example"
        case .analogy: return "Analogy"
        case .dontUnderstand: return "I Don't Understand This"
        }
    }

    var progressTitle: String {
        switch self {
        case .expand: return "Expanding"
        case .explain: return "Explaining"
        case .simplify: return "Simplifying"
        case .example: return "Creating example"
        case .analogy: return "Creating analogy"
        case .dontUnderstand: return "Checking level"
        }
    }

    var previewTitle: String {
        switch self {
        case .expand: return "EXPANDED"
        case .explain: return "EXPLAINED"
        case .simplify: return "SIMPLIFIED"
        case .example: return "EXAMPLE"
        case .analogy: return "ANALOGY"
        case .dontUnderstand: return "ADAPTIVE EXPLANATION"
        }
    }
}

enum AIProposalStatus: String, Sendable {
    case pending
    case accepted
    case rejected
    case edited
}

enum ProposalState: String, Codable, Sendable {
    case idle
    case generating
    case ready
    case accepted
    case rejected
    case stale
    case invalidated
}

struct DocumentSnapshot: Equatable, Sendable {
    let noteID: UUID?
    let contentHash: String
    let documentVersion: Int
    let capturedAt: Date

    init(
        noteID: UUID?,
        content: String,
        documentVersion: Int? = nil,
        capturedAt: Date = Date()
    ) {
        let contentHash = Self.hash(content)
        self.noteID = noteID
        self.contentHash = contentHash
        self.documentVersion = documentVersion ?? Self.version(from: contentHash)
        self.capturedAt = capturedAt
    }

    func matches(_ current: DocumentSnapshot) -> Bool {
        noteID == current.noteID &&
        (contentHash == current.contentHash || documentVersion == current.documentVersion)
    }

    static func hash(_ content: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in content.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func version(from hash: String) -> Int {
        Int(hash.suffix(8), radix: 16) ?? 0
    }
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
    let originatingNoteID: UUID?
    let originatingRequestID: UUID
    let createdAt: Date
    let documentSnapshot: DocumentSnapshot?
    let provenance: AIProposalProvenance
    let adaptiveExplanationContext: AdaptiveExplanationContext?
    var status: AIProposalStatus
    var state: ProposalState

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
        originatingNoteID: UUID? = nil,
        originatingRequestID: UUID = UUID(),
        createdAt: Date = Date(),
        documentSnapshot: DocumentSnapshot? = nil,
        provenance: AIProposalProvenance = AIProposalProvenance(),
        adaptiveExplanationContext: AdaptiveExplanationContext? = nil,
        status: AIProposalStatus = .pending,
        state: ProposalState = .ready
    ) {
        self.id = id
        self.action = action
        self.originalText = originalText
        self.generatedText = generatedText
        self.insertionRange = insertionRange
        self.originalSelectionRange = originalSelectionRange
        self.originatingNoteID = originatingNoteID
        self.originatingRequestID = originatingRequestID
        self.createdAt = createdAt
        self.documentSnapshot = documentSnapshot
        self.provenance = provenance
        self.adaptiveExplanationContext = adaptiveExplanationContext
        self.status = status
        self.state = state
    }

    func updating(state: ProposalState, status: AIProposalStatus? = nil) -> AIProposal {
        var proposal = self
        proposal.state = state
        if let status {
            proposal.status = status
        }
        return proposal
    }
}
