import Foundation

enum ResearchEventType: String, Codable, CaseIterable, Sendable {
    case proposalGenerated
    case proposalAccepted
    case proposalRejected
    case proposalEdited
    case teachMeStarted
    case teachMeCompleted
    case teachMeQuestionAnswered
    case knowledgeGapDetected
    case knowledgeGapIgnored
    case knowledgeGapResolved
    case questionGenerated
    case questionAnswered
    case writingMetricsUpdated
}

enum ResearchMetadataValue: Codable, Equatable, Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    var description: String {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum ValueType: String, Codable {
        case string
        case int
        case double
        case bool
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)
        switch type {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .int:
            self = .int(try container.decode(Int.self, forKey: .value))
        case .double:
            self = .double(try container.decode(Double.self, forKey: .value))
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .int(let value):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

struct ResearchEvent: Identifiable, Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let id: UUID
    let schemaVersion: Int
    let timestamp: Date
    let eventType: ResearchEventType
    let metadata: [String: ResearchMetadataValue]
    let sessionID: UUID
    let noteID: UUID?

    init(
        id: UUID = UUID(),
        schemaVersion: Int = ResearchEvent.currentSchemaVersion,
        timestamp: Date = Date(),
        eventType: ResearchEventType,
        metadata: [String: ResearchMetadataValue] = [:],
        sessionID: UUID,
        noteID: UUID? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.eventType = eventType
        self.metadata = metadata
        self.sessionID = sessionID
        self.noteID = noteID
    }
}

struct ResearchEventStatistics: Equatable, Sendable {
    let totalEvents: Int
    let proposalsGenerated: Int
    let proposalsAccepted: Int
    let proposalsRejected: Int
    let proposalsEdited: Int
    let knowledgeGapsDetected: Int
    let knowledgeGapsResolved: Int
    let questionsAnswered: Int
    let teachMeSessionsCompleted: Int

    static let empty = ResearchEventStatistics(events: [])

    init(events: [ResearchEvent]) {
        totalEvents = events.count
        proposalsGenerated = Self.count(.proposalGenerated, in: events)
        proposalsAccepted = Self.count(.proposalAccepted, in: events)
        proposalsRejected = Self.count(.proposalRejected, in: events)
        proposalsEdited = Self.count(.proposalEdited, in: events)
        knowledgeGapsDetected = Self.count(.knowledgeGapDetected, in: events)
        knowledgeGapsResolved = Self.count(.knowledgeGapResolved, in: events)
        questionsAnswered = Self.count(.questionAnswered, in: events)
        teachMeSessionsCompleted = Self.count(.teachMeCompleted, in: events)
    }

    private static func count(_ eventType: ResearchEventType, in events: [ResearchEvent]) -> Int {
        events.filter { $0.eventType == eventType }.count
    }
}

final class ResearchEventStore {
    static let shared = ResearchEventStore()

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "notinq.research.events.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func append(_ event: ResearchEvent) {
        var events = allEvents()
        events.append(event)
        save(events)
    }

    func allEvents() -> [ResearchEvent] {
        guard let data = defaults.data(forKey: storageKey),
              let events = try? decoder.decode([ResearchEvent].self, from: data) else {
            return []
        }
        return events
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    func jsonExportData() throws -> Data {
        try encoder.encode(allEvents())
    }

    func jsonExportString() -> String {
        guard let data = try? jsonExportData() else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    func csvExportString() -> String {
        let header = "id,schemaVersion,timestamp,eventType,sessionID,noteID,metadata"
        let rows = allEvents().map { event in
            [
                event.id.uuidString,
                String(event.schemaVersion),
                Self.iso8601Formatter.string(from: event.timestamp),
                event.eventType.rawValue,
                event.sessionID.uuidString,
                event.noteID?.uuidString ?? "",
                metadataJSONString(event.metadata)
            ]
            .map(Self.csvEscape)
            .joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    func csvExportData() -> Data {
        Data(csvExportString().utf8)
    }

    func statistics() -> ResearchEventStatistics {
        ResearchEventStatistics(events: allEvents())
    }

    private func save(_ events: [ResearchEvent]) {
        guard let data = try? encoder.encode(events) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func metadataJSONString(_ metadata: [String: ResearchMetadataValue]) -> String {
        guard let data = try? encoder.encode(metadata) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private nonisolated static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static let iso8601Formatter = ISO8601DateFormatter()
}

struct ResearchInstrumentationService {
    static let shared = ResearchInstrumentationService()
    static let enabledPreferenceKey = "researchInstrumentationEnabled"
    static let sessionIDPreferenceKey = "researchInstrumentationSessionID"

    var store: ResearchEventStore
    var defaults: UserDefaults

    init(
        store: ResearchEventStore = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get {
            defaults.object(forKey: Self.enabledPreferenceKey) == nil
                ? true
                : defaults.bool(forKey: Self.enabledPreferenceKey)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.enabledPreferenceKey)
        }
    }

    var sessionID: UUID {
        if let raw = defaults.string(forKey: Self.sessionIDPreferenceKey),
           let stored = UUID(uuidString: raw) {
            return stored
        }
        let fresh = UUID()
        defaults.set(fresh.uuidString, forKey: Self.sessionIDPreferenceKey)
        return fresh
    }

    func record(_ eventType: ResearchEventType, noteID: UUID? = nil, metadata: [String: ResearchMetadataValue] = [:], timestamp: Date = Date()) {
        guard isEnabled else { return }
        store.append(
            ResearchEvent(
                timestamp: timestamp,
                eventType: eventType,
                metadata: metadata,
                sessionID: sessionID,
                noteID: noteID
            )
        )
    }

    func recordProposalGenerated(proposal: AIProposal, latency: TimeInterval?) {
        var metadata = proposalMetadata(proposal)
        if let latency {
            metadata["generationLatencyMs"] = .int(Int((latency * 1000).rounded()))
        }
        metadata["generatedCharacterCount"] = .int(proposal.generatedText.count)
        record(.proposalGenerated, noteID: proposal.originatingNoteID, metadata: metadata, timestamp: proposal.createdAt)
        recordKnowledgeGapsDetected(from: proposal)
    }

    func recordProposalAccepted(proposal: AIProposal, finalText: String, editSignalType: LearningSignalType?) {
        var metadata = proposalMetadata(proposal)
        metadata["generatedCharacterCount"] = .int(proposal.generatedText.count)
        metadata["acceptedCharacterCount"] = .int(finalText.count)
        if let editSignalType {
            metadata["editType"] = .string(editSignalType.rawValue)
            metadata["editDistanceEstimate"] = .int(Self.levenshteinDistance(proposal.generatedText, finalText))
            record(.proposalEdited, noteID: proposal.originatingNoteID, metadata: metadata)
        }
        record(.proposalAccepted, noteID: proposal.originatingNoteID, metadata: metadata)
        recordWritingMetrics(
            manualCharactersWritten: 0,
            aiCharactersAccepted: finalText.count,
            aiCharactersEdited: editSignalType == nil ? 0 : finalText.count,
            noteID: proposal.originatingNoteID
        )
    }

    func recordProposalRejected(proposal: AIProposal) {
        var metadata = proposalMetadata(proposal)
        metadata["generatedCharacterCount"] = .int(proposal.generatedText.count)
        record(.proposalRejected, noteID: proposal.originatingNoteID, metadata: metadata)
    }

    func recordTeachMeStarted(session: TeachMeSession, noteID: UUID? = nil) {
        var metadata = teachMeMetadata(session)
        metadata["state"] = .string(session.state.rawValue)
        record(.teachMeStarted, noteID: noteID, metadata: metadata, timestamp: session.startedAt ?? Date())
        if let question = session.activeQuestion {
            recordQuestionGenerated(question: question, questionType: "teachMe", noteID: noteID)
        }
    }

    func recordTeachMeCompleted(session: TeachMeSession, noteID: UUID? = nil) {
        var metadata = teachMeMetadata(session)
        if let startedAt = session.startedAt, let updatedAt = session.updatedAt {
            metadata["sessionDurationSeconds"] = .int(Int(updatedAt.timeIntervalSince(startedAt).rounded()))
        }
        record(.teachMeCompleted, noteID: noteID, metadata: metadata, timestamp: session.updatedAt ?? Date())
    }

    func recordTeachMeQuestionAnswered(question: TeachMeQuestion, response: TeachMeResponse, session: TeachMeSession? = nil, noteID: UUID? = nil) {
        let followUpRequired = response.evaluation != .correct && ((session?.followUpCount ?? 0) < 1)
        let responseTime = Int(response.submittedAt.timeIntervalSince(question.generatedAt).rounded())
        let metadata: [String: ResearchMetadataValue] = [
            "concept": .string(question.conceptName),
            "conceptID": .string(question.conceptID),
            "correctnessState": .string(response.evaluation.rawValue),
            "followUpRequired": .bool(followUpRequired),
            "responseTimeSeconds": .int(max(0, responseTime))
        ]
        record(.teachMeQuestionAnswered, noteID: noteID, metadata: metadata, timestamp: response.submittedAt)
        recordQuestionAnswered(
            questionType: "teachMe",
            correctness: response.evaluation.rawValue,
            responseTimeSeconds: max(0, responseTime),
            noteID: noteID,
            timestamp: response.submittedAt
        )
    }

    func recordQuestionGenerated(question: TeachMeQuestion, questionType: String, noteID: UUID? = nil) {
        record(
            .questionGenerated,
            noteID: noteID,
            metadata: [
                "questionType": .string(questionType),
                "concept": .string(question.conceptName),
                "conceptID": .string(question.conceptID)
            ],
            timestamp: question.generatedAt
        )
    }

    func recordQuestionGenerated(questionType: String, concept: String, conceptID: String, noteID: UUID? = nil, timestamp: Date = Date()) {
        record(
            .questionGenerated,
            noteID: noteID,
            metadata: [
                "questionType": .string(questionType),
                "concept": .string(concept),
                "conceptID": .string(conceptID)
            ],
            timestamp: timestamp
        )
    }

    func recordQuestionAnswered(questionType: String, correctness: String, responseTimeSeconds: Int, noteID: UUID? = nil, timestamp: Date = Date()) {
        record(
            .questionAnswered,
            noteID: noteID,
            metadata: [
                "questionType": .string(questionType),
                "correctness": .string(correctness),
                "responseTimeSeconds": .int(responseTimeSeconds)
            ],
            timestamp: timestamp
        )
    }

    func recordKnowledgeGapDetected(concept: String, heuristic: String, noteID: UUID? = nil) {
        record(
            .knowledgeGapDetected,
            noteID: noteID,
            metadata: [
                "concept": .string(concept),
                "detectionHeuristic": .string(heuristic)
            ]
        )
    }

    func recordKnowledgeGapIgnored(concept: String, heuristic: String, noteID: UUID? = nil) {
        record(
            .knowledgeGapIgnored,
            noteID: noteID,
            metadata: [
                "concept": .string(concept),
                "detectionHeuristic": .string(heuristic)
            ]
        )
    }

    func recordKnowledgeGapResolved(concept: String, resolutionMethod: String, noteID: UUID? = nil) {
        record(
            .knowledgeGapResolved,
            noteID: noteID,
            metadata: [
                "concept": .string(concept),
                "resolutionMethod": .string(resolutionMethod)
            ]
        )
    }

    func recordWritingMetrics(manualCharactersWritten: Int, aiCharactersAccepted: Int, aiCharactersEdited: Int, noteID: UUID? = nil) {
        record(
            .writingMetricsUpdated,
            noteID: noteID,
            metadata: [
                "manualCharactersWritten": .int(max(0, manualCharactersWritten)),
                "aiCharactersAccepted": .int(max(0, aiCharactersAccepted)),
                "aiCharactersEdited": .int(max(0, aiCharactersEdited))
            ]
        )
    }

    func jsonExportString() -> String {
        store.jsonExportString()
    }

    func jsonExportData() throws -> Data {
        try store.jsonExportData()
    }

    func csvExportString() -> String {
        store.csvExportString()
    }

    func csvExportData() -> Data {
        store.csvExportData()
    }

    func statistics() -> ResearchEventStatistics {
        store.statistics()
    }

    private func proposalMetadata(_ proposal: AIProposal) -> [String: ResearchMetadataValue] {
        var metadata: [String: ResearchMetadataValue] = [
            "proposalID": .string(proposal.id.uuidString),
            "aiActionType": .string(proposal.action.rawValue),
            "proposalStatus": .string(proposal.status.rawValue),
            "proposalState": .string(proposal.state.rawValue)
        ]
        if let studyFeature = proposal.provenance.studyFeature {
            metadata["studyFeature"] = .string(studyFeature)
        }
        if let sourceConcept = proposal.provenance.sourceConcept {
            metadata["sourceConcept"] = .string(sourceConcept)
        }
        if let sourceItemID = proposal.provenance.sourceItemID {
            metadata["sourceItemID"] = .string(sourceItemID)
        }
        if let sourceItemTitle = proposal.provenance.sourceItemTitle {
            metadata["sourceItemTitle"] = .string(sourceItemTitle)
        }
        return metadata
    }

    private func teachMeMetadata(_ session: TeachMeSession) -> [String: ResearchMetadataValue] {
        var metadata: [String: ResearchMetadataValue] = [
            "teachMeSessionID": .string(session.id.uuidString),
            "answerCount": .int(session.answerHistory.count),
            "followUpCount": .int(session.followUpCount)
        ]
        if let activeConceptName = session.activeConceptName {
            metadata["concept"] = .string(activeConceptName)
        }
        if let activeConceptID = session.activeConceptID {
            metadata["conceptID"] = .string(activeConceptID)
        }
        return metadata
    }

    private func recordKnowledgeGapsDetected(from proposal: AIProposal) {
        guard let context = proposal.adaptiveExplanationContext else { return }
        for gap in context.identifiedKnowledgeGaps {
            recordKnowledgeGapDetected(concept: gap, heuristic: "adaptiveContext", noteID: proposal.originatingNoteID)
        }
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(min(previous[j] + 1, current[j - 1] + 1), substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
