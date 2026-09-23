import Foundation

struct RetrievedChunk: Codable, Equatable, Sendable {
    var id: String
    var noteID: UUID
    var noteTitle: String
    var title: String
    var content: String
    var snippet: String
    var sourceType: RetrievalResult.SourceType
    var relevance: Double
}

struct KnowledgeGap: Codable, Equatable, Sendable {
    var concept: Concept
    var reason: String
    var severity: Double
    var missingPrerequisites: [Concept]
}

struct AdaptiveTutorContext: Codable, Equatable, Sendable {
    var question: String
    var retrievedNotes: [RetrievedChunk]
    var relevantConcepts: [Concept]
    var relationships: [ConceptRelationship]
    var weakConcepts: [Concept]
    var strongConcepts: [Concept]
    var prerequisites: [Concept]
    var missingPrerequisites: [Concept]
    var studyPlanRecommendations: [String]
    var masteryMap: [UUID: Double]
    var knowledgeGaps: [Concept]
    var relatedConcepts: [Concept]
    var reviewHistory: [ReviewEvent]
    var graphContext: GraphContext

    static let empty = AdaptiveTutorContext(
        question: "",
        retrievedNotes: [],
        relevantConcepts: [],
        relationships: [],
        weakConcepts: [],
        strongConcepts: [],
        prerequisites: [],
        missingPrerequisites: [],
        studyPlanRecommendations: [],
        masteryMap: [:],
        knowledgeGaps: [],
        relatedConcepts: [],
        reviewHistory: [],
        graphContext: .empty
    )
}
