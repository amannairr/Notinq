import Foundation
import Combine

enum GraphMasteryState: String, CaseIterable, Identifiable, Codable, Sendable {
    case mastered
    case familiar
    case needsPractice
    case struggling

    var id: String { rawValue }

    static func state(for mastery: Double) -> GraphMasteryState {
        if mastery >= 0.8 { return .mastered }
        if mastery >= 0.55 { return .familiar }
        if mastery >= 0.35 { return .needsPractice }
        return .struggling
    }
}

enum GraphGapStatus: String, CaseIterable, Identifiable, Codable, Sendable {
    case active
    case ignored
    case resolved

    var id: String { rawValue }
}

struct GraphExplorerViewport: Codable, Equatable, Sendable {
    var offsetX: Double = 0
    var offsetY: Double = 0
    var scale: Double = 1
}

struct GraphExplorerFilterState: Codable, Equatable, Sendable {
    var masteryStates: Set<GraphMasteryState> = Set(GraphMasteryState.allCases)
    var gapStatuses: Set<GraphGapStatus> = Set(GraphGapStatus.allCases)
    var minimumConfidence: Double = 0
    var textQuery: String = ""
}

struct GraphProvenanceReference: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let excerpt: String
}

struct GraphProvenanceSummary: Equatable, Sendable {
    let sourceCount: Int
    let confidence: Double
    let references: [GraphProvenanceReference]
}

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
    let provenance: GraphProvenanceSummary

    var isWeak: Bool { mastery < 0.5 }
    var isStrong: Bool { mastery >= 0.8 }
    var masteryState: GraphMasteryState { GraphMasteryState.state(for: mastery) }
    var gapStatus: GraphGapStatus { isWeak || blockedTopics.isEmpty == false ? .active : .resolved }
}

struct KnowledgeGraphExplorerEdge: Identifiable, Equatable, Sendable {
    let id: String
    let sourceID: String
    let targetID: String
    let relationshipType: String
    let confidence: Double
    let provenance: GraphProvenanceSummary
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
    @Published private(set) var selectedEdge: KnowledgeGraphExplorerEdge?
    @Published var showProvenanceOverlay = false
    @Published var filterState: GraphExplorerFilterState {
        didSet { persistExplorerState() }
    }
    @Published var viewport: GraphExplorerViewport {
        didSet { persistExplorerState() }
    }
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
    private let userDefaults: UserDefaults
    private let maxSearchResults = 12
    private let maxGraphRadius = 3
    private let maxGraphNodes = 48
    private let maxGraphEdges = 96
    private static let filterStateKey = "KnowledgeGraphExplorer.filterState"
    private static let viewportKey = "KnowledgeGraphExplorer.viewport"

    var filteredNodes: [KnowledgeGraphExplorerNode] {
        GraphExplorerFiltering.filteredNodes(nodes, filter: filterState)
    }

    var filteredEdges: [KnowledgeGraphExplorerEdge] {
        let visibleNodeIDs = Set(filteredNodes.map(\.id))
        return GraphExplorerFiltering.filteredEdges(edges, visibleNodeIDs: visibleNodeIDs, filter: filterState)
    }

    init(
        repository: KnowledgeRepository = .shared,
        visualizationService: GraphVisualizationService? = nil,
        explanationService: GraphExplanationService? = nil,
        recommendationEngine: LearningRecommendationEngine? = nil,
        studyPlannerService: StudyPlannerService? = nil,
        studentConceptService: StudentConceptService = .shared,
        retentionEngine: RetentionEngine? = nil,
        userDefaults: UserDefaults = .standard
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
        self.userDefaults = userDefaults
        self.filterState = Self.decode(GraphExplorerFilterState.self, from: userDefaults.data(forKey: Self.filterStateKey)) ?? GraphExplorerFilterState()
        self.viewport = Self.decode(GraphExplorerViewport.self, from: userDefaults.data(forKey: Self.viewportKey)) ?? GraphExplorerViewport()
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
        selectedEdge = nil
        explanation = explanationService.explainConcept(concept.canonicalName)
        studyRecommendations = recommendationEngine.recommendedPrerequisites(for: concept.canonicalName, limit: 6)
        studyNextTasks = studyPlannerService.studyNext(for: concept.canonicalName, limit: 5)
        loadNeighborhood(around: concept.id)
    }

    func selectEdge(_ edgeID: String) {
        guard let edge = edges.first(where: { $0.id == edgeID }) else { return }
        selectedEdge = edge
        selectedNode = nil
    }

    func updateViewport(scale: Double? = nil, offsetX: Double? = nil, offsetY: Double? = nil) {
        viewport = GraphExplorerViewport(
            offsetX: offsetX ?? viewport.offsetX,
            offsetY: offsetY ?? viewport.offsetY,
            scale: max(0.35, min(3.0, scale ?? viewport.scale))
        )
    }

    func fitToContent() {
        viewport = GraphExplorerViewport()
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
                confidence: $0.confidence,
                provenance: provenanceSummary(for: $0)
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
            blockedTopics: blockedTopics,
            provenance: provenanceSummary(for: concept)
        )
    }

    private func provenanceSummary(for concept: CanonicalConceptRecord) -> GraphProvenanceSummary {
        let references = concept.sourceReferences.prefix(4).compactMap { sourceID -> GraphProvenanceReference? in
            guard let noteID = UUID(uuidString: sourceID) else { return nil }
            let title = (try? repository.noteTitle(for: noteID)) ?? "Source"
            let excerpt = (try? repository.chunks(for: noteID).first?.content).map(Self.truncatedExcerpt) ?? ""
            return GraphProvenanceReference(id: sourceID, title: title, excerpt: excerpt)
        }
        return GraphProvenanceSummary(sourceCount: concept.sourceReferences.count, confidence: concept.confidence, references: references)
    }

    private func provenanceSummary(for edge: GraphVisualizationEdge) -> GraphProvenanceSummary {
        let relationship = (try? repository.relationships(containing: edge.sourceID, limit: 256))?
            .first { $0.id == edge.id }
        let provenanceIDs = relationship?.provenance ?? []
        let references = provenanceIDs.prefix(4).compactMap { sourceID -> GraphProvenanceReference? in
            guard let noteID = UUID(uuidString: sourceID) else { return nil }
            let title = (try? repository.noteTitle(for: noteID)) ?? "Source"
            let excerpt = (try? repository.chunks(for: noteID).first?.content).map(Self.truncatedExcerpt) ?? ""
            return GraphProvenanceReference(id: sourceID, title: title, excerpt: excerpt)
        }
        return GraphProvenanceSummary(sourceCount: provenanceIDs.count, confidence: edge.confidence, references: references)
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

    private func persistExplorerState() {
        userDefaults.set(Self.encode(filterState), forKey: Self.filterStateKey)
        userDefaults.set(Self.encode(viewport), forKey: Self.viewportKey)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func truncatedExcerpt(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 140 else { return trimmed }
        return String(trimmed.prefix(137)) + "..."
    }
}

enum GraphExplorerFiltering {
    static func filteredNodes(
        _ nodes: [KnowledgeGraphExplorerNode],
        filter: GraphExplorerFilterState
    ) -> [KnowledgeGraphExplorerNode] {
        let query = filter.textQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return nodes.filter { node in
            guard filter.masteryStates.contains(node.masteryState) else { return false }
            guard filter.gapStatuses.contains(node.gapStatus) else { return false }
            guard query.isEmpty == false else { return true }
            return node.name.localizedCaseInsensitiveContains(query)
                || node.aliases.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    static func filteredEdges(
        _ edges: [KnowledgeGraphExplorerEdge],
        visibleNodeIDs: Set<String>,
        filter: GraphExplorerFilterState
    ) -> [KnowledgeGraphExplorerEdge] {
        edges.filter { edge in
            visibleNodeIDs.contains(edge.sourceID)
                && visibleNodeIDs.contains(edge.targetID)
                && edge.confidence >= filter.minimumConfidence
        }
    }
}
