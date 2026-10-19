import Foundation

/// Editor-scoped AI actions that produce proposals before changing the note.
enum AIEditorAction: String, CaseIterable, Codable, Sendable {
    case summarize
    case expand
    case explain
    case simplify
    case rewrite
    case example
    case analogy
    case ask
    case dontUnderstand

    var blockTitle: String {
        switch self {
        case .summarize: return "Summary"
        case .expand: return "Expansion"
        case .explain: return "Explanation"
        case .simplify: return "Simplification"
        case .rewrite: return "Rewrite"
        case .example: return "Example"
        case .analogy: return "Analogy"
        case .ask: return "Ask AI"
        case .dontUnderstand: return "Adaptive Explanation"
        }
    }

    var displayTitle: String {
        switch self {
        case .summarize: return "Summarize"
        case .expand: return "Expand"
        case .explain: return "Explain"
        case .simplify: return "Simplify"
        case .rewrite: return "Rewrite"
        case .example: return "Example"
        case .analogy: return "Analogy"
        case .ask: return "Ask AI"
        case .dontUnderstand: return "I Don't Understand This"
        }
    }

    var progressTitle: String {
        switch self {
        case .summarize: return "Summarizing"
        case .expand: return "Expanding"
        case .explain: return "Explaining"
        case .simplify: return "Simplifying"
        case .rewrite: return "Rewriting"
        case .example: return "Creating example"
        case .analogy: return "Creating analogy"
        case .ask: return "Thinking"
        case .dontUnderstand: return "Checking level"
        }
    }

    var previewTitle: String {
        switch self {
        case .summarize: return "SUMMARY"
        case .expand: return "EXPANDED"
        case .explain: return "EXPLAINED"
        case .simplify: return "SIMPLIFIED"
        case .rewrite: return "REWRITTEN"
        case .example: return "EXAMPLE"
        case .analogy: return "ANALOGY"
        case .ask: return "ANSWER"
        case .dontUnderstand: return "ADAPTIVE EXPLANATION"
        }
    }
}

enum AIProposalStatus: String, Codable, Sendable {
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
    var studyFeature: String?
    var sourceConcept: String?
    var sourceItemID: String?
    var sourceItemTitle: String?

    init(
        sourceNoteRange: NSRange? = nil,
        transcriptReference: String? = nil,
        slideReference: String? = nil,
        studyFeature: String? = nil,
        sourceConcept: String? = nil,
        sourceItemID: String? = nil,
        sourceItemTitle: String? = nil
    ) {
        self.sourceNoteRange = sourceNoteRange
        self.transcriptReference = transcriptReference
        self.slideReference = slideReference
        self.studyFeature = studyFeature
        self.sourceConcept = sourceConcept
        self.sourceItemID = sourceItemID
        self.sourceItemTitle = sourceItemTitle
    }
}

struct SourceReference: Codable, Equatable, Sendable {
    var noteRange: NSRange?
    var sourceTextExcerpt: String
    var transcriptTimestamp: String?
    var slideReference: String?
    var studyFeature: String?
    var sourceConcept: String?
    var sourceItemID: String?
    var sourceItemTitle: String?

    var locationLabel: String {
        if let noteRange {
            return "Characters \(noteRange.location)-\(noteRange.location + noteRange.length)"
        }
        if let transcriptTimestamp, !transcriptTimestamp.isEmpty {
            return transcriptTimestamp
        }
        if let slideReference, !slideReference.isEmpty {
            return slideReference
        }
        return "Selected source"
    }

    init(
        noteRange: NSRange? = nil,
        sourceTextExcerpt: String,
        transcriptTimestamp: String? = nil,
        slideReference: String? = nil,
        studyFeature: String? = nil,
        sourceConcept: String? = nil,
        sourceItemID: String? = nil,
        sourceItemTitle: String? = nil
    ) {
        self.noteRange = noteRange
        self.sourceTextExcerpt = sourceTextExcerpt
        self.transcriptTimestamp = transcriptTimestamp
        self.slideReference = slideReference
        self.studyFeature = studyFeature
        self.sourceConcept = sourceConcept
        self.sourceItemID = sourceItemID
        self.sourceItemTitle = sourceItemTitle
    }

    init(proposal: AIProposal) {
        self.init(
            noteRange: proposal.provenance.sourceNoteRange ?? proposal.originalSelectionRange,
            sourceTextExcerpt: proposal.originalText,
            transcriptTimestamp: proposal.provenance.transcriptReference,
            slideReference: proposal.provenance.slideReference,
            studyFeature: proposal.provenance.studyFeature,
            sourceConcept: proposal.provenance.sourceConcept,
            sourceItemID: proposal.provenance.sourceItemID,
            sourceItemTitle: proposal.provenance.sourceItemTitle
        )
    }

    private enum CodingKeys: String, CodingKey {
        case noteRangeLocation
        case noteRangeLength
        case sourceTextExcerpt
        case transcriptTimestamp
        case slideReference
        case studyFeature
        case sourceConcept
        case sourceItemID
        case sourceItemTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let location = try container.decodeIfPresent(Int.self, forKey: .noteRangeLocation)
        let length = try container.decodeIfPresent(Int.self, forKey: .noteRangeLength)
        if let location, let length {
            noteRange = NSRange(location: location, length: length)
        } else {
            noteRange = nil
        }
        sourceTextExcerpt = try container.decode(String.self, forKey: .sourceTextExcerpt)
        transcriptTimestamp = try container.decodeIfPresent(String.self, forKey: .transcriptTimestamp)
        slideReference = try container.decodeIfPresent(String.self, forKey: .slideReference)
        studyFeature = try container.decodeIfPresent(String.self, forKey: .studyFeature)
        sourceConcept = try container.decodeIfPresent(String.self, forKey: .sourceConcept)
        sourceItemID = try container.decodeIfPresent(String.self, forKey: .sourceItemID)
        sourceItemTitle = try container.decodeIfPresent(String.self, forKey: .sourceItemTitle)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(noteRange?.location, forKey: .noteRangeLocation)
        try container.encodeIfPresent(noteRange?.length, forKey: .noteRangeLength)
        try container.encode(sourceTextExcerpt, forKey: .sourceTextExcerpt)
        try container.encodeIfPresent(transcriptTimestamp, forKey: .transcriptTimestamp)
        try container.encodeIfPresent(slideReference, forKey: .slideReference)
        try container.encodeIfPresent(studyFeature, forKey: .studyFeature)
        try container.encodeIfPresent(sourceConcept, forKey: .sourceConcept)
        try container.encodeIfPresent(sourceItemID, forKey: .sourceItemID)
        try container.encodeIfPresent(sourceItemTitle, forKey: .sourceItemTitle)
    }

    func encodedString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decoded(from encodedString: String?) -> SourceReference? {
        guard let encodedString,
              let data = encodedString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SourceReference.self, from: data)
    }
}

struct AIBlockSourceInfo: Codable, Equatable, Sendable {
    var blockID: String
    var actionTitle: String
    var actionRawValue: String?
    var createdAt: Date
    var sourceReference: SourceReference

    var displayActionTitle: String {
        if let actionRawValue,
           let action = AIEditorAction(rawValue: actionRawValue) {
            return action.displayTitle
        }
        return actionTitle
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
