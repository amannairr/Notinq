import Foundation
import Combine

struct KnowledgeGraphExplorerNode: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let description: String
    let aliases: [String]
    let importance: Double
    let difficulty: Double
    let mastery: Double
    let retention: Double
    let retentionRisk: String
    let relationshipCount: Int
    let blockedTopics: [String]

    var isWeak: Bool { mastery < 0.5 }
    var isStrong: Bool { mastery >= 0.8 }
}

struct KnowledgeGraphExplorerEdge: Identifiable, Equatable, Sendable {
    let id: String
    let sourceID: String
    let targetID: String
    let relationshipType: String
    let confidence: Double
}

struct KnowledgeGraphExplorerPath: Equatable, Sendable {
    let conceptNames: [String]
    let relationshipTypes: [String]
}

@MainActor
final class KnowledgeGraphExplorerViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [ConceptSearchRecord] = []
    @Published private(set) var nodes: [KnowledgeGraphExplorerNode] = []
    @Published private(set) var edges: [KnowledgeGraphExplorerEdge] = []
    @Published private(set) var selectedNode: KnowledgeGraphExplorerNode?
    @Published private(set) var explanation = ConceptExplanation(
        conceptName: "",
        aliases: [],
        prerequisites: [],
        dependents: [],
        relatedConcepts: [],
        incomingRelationships: [],
        outgoingRelationships: []
    )
    @Published private(set) var studyRecommendations: [String] = []
    @Published private(set) var studyNextTasks: [StudyTask] = []
    @Published private(set) var bottlenecks: [GraphExamPreparationItem] = []
    @Published private(set) var pathResult: KnowledgeGraphExplorerPath?
    @Published var targetQuery = ""
    @Published var radius = 2

    private let repository: KnowledgeRepository
    private let visualizationService: GraphVisualizationService
    private let explanationService: GraphExplanationService
    private let recommendationEngine: LearningRecommendationEngine
    private let studyPlannerService: StudyPlannerService
    private let studentConceptService: StudentConceptService
    private let retentionEngine: RetentionEngine
    private let maxSearchResults = 12
    private let maxGraphRadius = 3
    private let maxGraphNodes = 48
    private let maxGraphEdges = 96

    init(
        repository: KnowledgeRepository = .shared,
        visualizationService: GraphVisualizationService? = nil,
        explanationService: GraphExplanationService? = nil,
        recommendationEngine: LearningRecommendationEngine? = nil,
        studyPlannerService: StudyPlannerService? = nil,
        studentConceptService: StudentConceptService = .shared,
        retentionEngine: RetentionEngine? = nil
    ) {
        self.repository = repository
        self.visualizationService = visualizationService ?? GraphVisualizationService(repository: repository)
        self.explanationService = explanationService ?? GraphExplanationService(repository: repository)
        self.recommendationEngine = recommendationEngine ?? LearningRecommendationEngine(
            repository: repository,
            studentConceptService: studentConceptService
        )
        self.studyPlannerService = studyPlannerService ?? StudyPlannerService(
            recommendationEngine: self.recommendationEngine,
            graphExplanationService: self.explanationService,
            repository: repository
        )
        self.studentConceptService = studentConceptService
        self.retentionEngine = retentionEngine ?? RetentionEngine(studentConceptService: studentConceptService)
    }

    func loadInitialGraph() {
        bottlenecks = recommendationEngine.importantConcepts(limit: 8)
        let firstConcept = (try? repository.searchRecentConcepts(limit: 1).first)?.conceptID
        if let firstConcept {
            selectConcept(firstConcept)
        } else {
            nodes = []
            edges = []
            selectedNode = nil
            explanation = emptyExplanation()
            studyRecommendations = []
            studyNextTasks = []
        }
    }

    func searchConcepts() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            searchResults = (try? repository.searchRecentConcepts(limit: maxSearchResults)) ?? []
            return
        }

        if let canonical = try? repository.canonicalConcept(named: trimmed),
           let record = try? repository.concept(for: canonical.id) {
            searchResults = [ConceptSearchRecord(
                conceptID: record.id,
                canonicalName: record.canonicalName,
                description: record.description,
                aliases: record.aliases,
                noteIDs: record.sourceReferences.compactMap(UUID.init(uuidString:)),
                rank: 1.0
            )]
            selectConcept(record.id)
            return
        }

        searchResults = (try? repository.searchConcepts(query: trimmed, limit: maxSearchResults)) ?? []
        if let first = searchResults.first {
            selectConcept(first.conceptID)
        }
    }

    func selectConcept(_ identifier: String) {
        guard let concept = resolveConcept(identifier) else { return }
        selectedNode = node(for: concept, edgeCounts: currentEdgeCounts())
        explanation = explanationService.explainConcept(concept.canonicalName)
        studyRecommendations = recommendationEngine.recommendedPrerequisites(for: concept.canonicalName, limit: 6)
        studyNextTasks = studyPlannerService.studyNext(for: concept.canonicalName, limit: 5)
        loadNeighborhood(around: concept.id)
    }

    func setRadius(_ newRadius: Int) {
        radius = max(1, min(maxGraphRadius, newRadius))
        if let selectedNode {
            loadNeighborhood(around: selectedNode.id)
        }
    }

    func findConnection() {
        guard let selectedNode else { return }
        let trimmedTarget = targetQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTarget.isEmpty == false else {
            pathResult = nil
            return
        }

        guard let path = explanationService.findPath(from: selectedNode.name, to: trimmedTarget) else {
            pathResult = nil
            return
        }

        pathResult = KnowledgeGraphExplorerPath(
            conceptNames: path.nodes.map(\.canonicalName),
            relationshipTypes: path.relationships.map(\.relationType)
        )
    }

    private func loadNeighborhood(around conceptID: String) {
        let graph = visualizationService.subgraphAroundConcept(conceptID, radius: radius)
        let boundedNodes = Array(graph.nodes.prefix(maxGraphNodes))
        let allowedNodeIDs = Set(boundedNodes.map(\.id))
        let boundedEdges = graph.edges
            .filter { allowedNodeIDs.contains($0.sourceID) && allowedNodeIDs.contains($0.targetID) }
            .prefix(maxGraphEdges)
        let edgeCounts = boundedEdges.reduce(into: [String: Int]()) { result, edge in
            result[edge.sourceID, default: 0] += 1
            result[edge.targetID, default: 0] += 1
        }

        nodes = boundedNodes.compactMap { graphNode in
            guard let concept = try? repository.concept(for: graphNode.id) else { return nil }
            return node(for: concept, edgeCounts: edgeCounts)
        }
        edges = boundedEdges.map {
            KnowledgeGraphExplorerEdge(
                id: $0.id,
                sourceID: $0.sourceID,
                targetID: $0.targetID,
                relationshipType: $0.relationshipType,
                confidence: $0.confidence
            )
        }

        if let selected = selectedNode,
           let refreshed = nodes.first(where: { $0.id == selected.id }) {
            selectedNode = refreshed
        } else if let first = nodes.first {
            selectedNode = first
        }
    }

    private func node(for concept: CanonicalConceptRecord, edgeCounts: [String: Int]) -> KnowledgeGraphExplorerNode {
        let relationshipCount = edgeCounts[concept.id]
            ?? ((try? repository.relationships(containing: concept.id, limit: 256).count) ?? 0)
        let record = masteryRecord(for: concept)
        let mastery = record?.effectiveMasteryScore ?? 0.5
        let retention = record.map { retentionEngine.retentionScore(for: $0) } ?? 0.5
        let blockedTopics = recommendationEngine.learningGaps(limit: 12, blockedTopicLimit: 6)
            .first { $0.weakConcept.localizedCaseInsensitiveCompare(concept.canonicalName) == .orderedSame }?
            .blockedTopics ?? []

        return KnowledgeGraphExplorerNode(
            id: concept.id,
            name: concept.canonicalName,
            description: concept.description,
            aliases: concept.aliases,
            importance: min(1.0, max(0.0, concept.confidence + min(0.3, Double(relationshipCount) * 0.04))),
            difficulty: max(0.0, min(1.0, 1.0 - mastery)),
            mastery: mastery,
            retention: retention,
            retentionRisk: retentionRisk(for: retention),
            relationshipCount: relationshipCount,
            blockedTopics: blockedTopics
        )
    }

    private func masteryRecord(for concept: CanonicalConceptRecord) -> StudentConceptRecord? {
        let records = masteryRecords()
        if let byID = records.first(where: { $0.conceptID == concept.id }) {
            return byID
        }
        if let byName = records.first(where: { normalized($0.conceptID) == normalized(concept.canonicalName) }) {
            return byName
        }
        return nil
    }

    private func retentionRisk(for retention: Double) -> String {
        if retention < 0.35 { return "High Risk" }
        if retention < 0.65 { return "Medium Risk" }
        return "Low Risk"
    }

    private func masteryRecords() -> [StudentConceptRecord] {
        let weak = (try? studentConceptService.weakestConcepts(limit: 128)) ?? []
        let strong = (try? studentConceptService.strongestConcepts(limit: 128)) ?? []
        let recent = (try? studentConceptService.recentlyReviewedConcepts(limit: 128)) ?? []
        var recordsByID: [String: StudentConceptRecord] = [:]
        for record in weak + strong + recent {
            recordsByID[record.conceptID] = record
        }
        return Array(recordsByID.values)
    }

    private func currentEdgeCounts() -> [String: Int] {
        edges.reduce(into: [String: Int]()) { result, edge in
            result[edge.sourceID, default: 0] += 1
            result[edge.targetID, default: 0] += 1
        }
    }

    private func resolveConcept(_ identifier: String) -> CanonicalConceptRecord? {
        if let concept = try? repository.concept(for: identifier) {
            return concept
        }
        guard let canonical = try? repository.canonicalConcept(named: identifier) else { return nil }
        return try? repository.concept(for: canonical.id)
    }

    private func emptyExplanation() -> ConceptExplanation {
        ConceptExplanation(
            conceptName: "",
            aliases: [],
            prerequisites: [],
            dependents: [],
            relatedConcepts: [],
            incomingRelationships: [],
            outgoingRelationships: []
        )
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}
