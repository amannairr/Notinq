import Foundation

struct KnowledgeChunkRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var noteID: UUID?
    var documentID: String
    var chunkIndex: Int
    var sectionName: String
    var content: String
    var startLine: Int
    var endLine: Int
    var provenanceNoteID: UUID?
}

struct CanonicalConceptRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var canonicalName: String
    var aliases: [String]
    var sourceReferences: [String]
    var confidence: Double
    var description: String
}

struct CanonicalConcept: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var canonicalName: String
    var aliases: [String]
    var createdAt: Date
    var updatedAt: Date
}

struct KnowledgeEntityRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var conceptID: String
    var label: String
    var entityType: String
    var confidence: Double
}

struct KnowledgeRelationshipRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var sourceConceptID: String
    var targetConceptID: String
    var relationType: String
    var confidence: Double
    var provenance: [String]
}

struct KnowledgeSummaryRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var noteID: UUID?
    var conceptID: String?
    var summaryType: String
    var body: String
    var createdAt: Date
}

struct KnowledgeGraphRecord: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var noteID: UUID?
    var concepts: [CanonicalConceptRecord]
    var entities: [KnowledgeEntityRecord]
    var relationships: [KnowledgeRelationshipRecord]
    var summaries: [KnowledgeSummaryRecord]
}
