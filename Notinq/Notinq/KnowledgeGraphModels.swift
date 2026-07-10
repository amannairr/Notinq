import Foundation

enum ConceptRelationshipType: String, Codable, CaseIterable, Identifiable, Sendable {
    case prerequisite
    case dependsOn
    case partOf
    case exampleOf
    case relatedTo
    case causes
    case contrastsWith
    case extends
    case applicationOf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prerequisite: return "Prerequisite"
        case .dependsOn: return "Depends On"
        case .partOf: return "Part Of"
        case .exampleOf: return "Example Of"
        case .relatedTo: return "Related To"
        case .causes: return "Causes"
        case .contrastsWith: return "Contrasts With"
        case .extends: return "Extends"
        case .applicationOf: return "Application Of"
        }
    }
}

struct Concept: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var description: String
    var aliases: [String] = []
    var noteID: UUID
    var confidence: Double
    var createdDate: Date = Date()
    var updatedDate: Date = Date()
    var embeddingID: String? = nil
    var importanceScore: Double
    var difficultyScore: Double
}

struct ConceptRelationship: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var sourceConceptID: UUID
    var destinationConceptID: UUID
    var type: ConceptRelationshipType
    var confidence: Double
}

struct KnowledgeGraph: Identifiable, Codable, Equatable, Sendable {
    var noteID: UUID
    var concepts: [Concept]
    var relationships: [ConceptRelationship]
    var lastUpdated: Date

    var id: UUID { noteID }
}

struct KnowledgeGraphNoteInput: Sendable {
    let noteID: UUID
    let title: String
    let text: String
    let updatedAt: Date
}

struct KnowledgeGraphExtractionPayload: Codable, Equatable, Sendable {
    var concepts: [KnowledgeGraphExtractionConcept] = []
    var relationships: [KnowledgeGraphExtractionRelationship] = []
}

struct KnowledgeGraphExtractionConcept: Codable, Equatable, Sendable {
    var name: String
    var description: String
    var aliases: [String] = []
    var importance: Double = 0.5
    var difficulty: Double = 0.5
}

struct KnowledgeGraphExtractionRelationship: Codable, Equatable, Sendable {
    var source: String
    var target: String
    var type: ConceptRelationshipType
    var confidence: Double = 0.5
}

struct KnowledgeGraphStatusSnapshot: Equatable, Sendable {
    var isGenerating: Bool = false
    var message: String?
    var lastUpdated: Date?
}

