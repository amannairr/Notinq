import Foundation

enum StudyTaskReason: String, Codable, CaseIterable, Sendable {
    case weakConcept
    case missingPrerequisite
    case examPreparation
    case reviewDue
    case highDependencyConcept

    var title: String {
        switch self {
        case .weakConcept: return "Weak concept"
        case .missingPrerequisite: return "Missing prerequisite"
        case .examPreparation: return "Exam preparation"
        case .reviewDue: return "Review due"
        case .highDependencyConcept: return "High dependency concept"
        }
    }
}

struct StudyTask: Identifiable, Codable, Equatable, Sendable {
    var id: String { concept.lowercased() + "-" + reason.rawValue }
    let concept: String
    let priority: Double
    let reason: StudyTaskReason
    let estimatedMinutes: Int
    let prerequisiteDepth: Int
    var isCompleted: Bool = false

    var reasonText: String { reason.title }
}

struct StudySession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let tasks: [StudyTask]
    let plannedMinutes: Int
    let completedTasks: Int
    let completedMinutes: Int

    init(id: UUID = UUID(), title: String, tasks: [StudyTask]) {
        self.id = id
        self.title = title
        self.tasks = tasks
        self.plannedMinutes = tasks.reduce(0) { $0 + $1.estimatedMinutes }
        self.completedTasks = tasks.filter(\.isCompleted).count
        self.completedMinutes = tasks.filter(\.isCompleted).reduce(0) { $0 + $1.estimatedMinutes }
    }

    var completionRate: Double {
        guard tasks.isEmpty == false else { return 0 }
        return Double(completedTasks) / Double(tasks.count)
    }
}

struct StudyPlan: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let sessions: [StudySession]

    init(id: UUID = UUID(), title: String, sessions: [StudySession]) {
        self.id = id
        self.title = title
        self.sessions = sessions
    }

    var tasks: [StudyTask] { sessions.flatMap(\.tasks) }
    var completedTasks: Int { sessions.reduce(0) { $0 + $1.completedTasks } }
    var completedMinutes: Int { sessions.reduce(0) { $0 + $1.completedMinutes } }
    var plannedMinutes: Int { sessions.reduce(0) { $0 + $1.plannedMinutes } }

    var completionRate: Double {
        guard tasks.isEmpty == false else { return 0 }
        return Double(completedTasks) / Double(tasks.count)
    }
}

nonisolated final class StudyPlannerService {
    private let studentKnowledgeService: StudentKnowledgeService
    private let recommendationEngine: LearningRecommendationEngine
    private let graphExplanationService: GraphExplanationService
    private let repository: KnowledgeRepository
    private let reviewScheduler: ReviewScheduler
    private let defaultTaskMinutes = 15

    init(
        studentKnowledgeService: StudentKnowledgeService = StudentKnowledgeService(),
        recommendationEngine: LearningRecommendationEngine = LearningRecommendationEngine(),
        graphExplanationService: GraphExplanationService = GraphExplanationService(),
        reviewScheduler: ReviewScheduler? = nil,
        repository: KnowledgeRepository = .shared
    ) {
        self.studentKnowledgeService = studentKnowledgeService
        self.recommendationEngine = recommendationEngine
        self.graphExplanationService = graphExplanationService
        self.repository = repository
        self.reviewScheduler = reviewScheduler ?? ReviewScheduler(
            studentConceptService: studentKnowledgeService.conceptService,
            knowledgeRepository: repository
        )
    }

    func dailyPlan(maxMinutes: Int = 60) -> StudyPlan {
        let tasks = prioritizedTasks(limitMinutes: maxMinutes)
        return StudyPlan(title: "Today's Plan", sessions: [StudySession(title: "Today", tasks: tasks)])
    }

    func weeklyPlan(days: Int = 7, minutesPerDay: Int = 45) -> StudyPlan {
        let boundedDays = max(1, min(days, 14))
        let candidates = prioritizedTasks(limitMinutes: boundedDays * minutesPerDay)
        let sessions = split(tasks: candidates, days: boundedDays, minutesPerDay: minutesPerDay, titlePrefix: "Day")
        return StudyPlan(title: "Weekly Study Plan", sessions: sessions)
    }

    func examPreparationPlan(
        targetConcepts: [String],
        daysRemaining: Int,
        minutesPerDay: Int
    ) -> StudyPlan {
        let boundedDays = max(1, min(daysRemaining, 90))
        let boundedMinutes = max(10, min(minutesPerDay, 240))
        let mastery = studentKnowledgeService.conceptMastery(limit: 1_000)
        let tasks = targetConcepts.flatMap { target in
            tasksForExamTarget(target, masteryScores: mastery, daysRemaining: boundedDays)
        }
        let ordered = merged(tasks: tasks)
            .sorted(by: taskSort)
            .prefix(boundedDays * max(1, boundedMinutes / defaultTaskMinutes))
            .map { $0 }
        let sessions = split(tasks: ordered, days: boundedDays, minutesPerDay: boundedMinutes, titlePrefix: "Day")
        return StudyPlan(title: "Exam Preparation", sessions: sessions)
    }

    func reviewPlan(limit: Int = 8) -> StudyPlan {
        let tasks = reviewScheduler.scheduledReviews(limit: limit).enumerated().map { index, review in
            StudyTask(
                concept: review.conceptName,
                priority: 0.95 + review.urgency - Double(index) * 0.01,
                reason: .reviewDue,
                estimatedMinutes: defaultTaskMinutes,
                prerequisiteDepth: 0
            )
        }
        return StudyPlan(title: "Review Plan", sessions: [StudySession(title: "Review", tasks: merged(tasks: tasks).sorted(by: taskSort))])
    }

    func studyNext(for concept: String, limit: Int = 4) -> [StudyTask] {
        let prerequisites = graphExplanationService.prerequisiteChain(for: concept).enumerated().map { index, name in
            StudyTask(
                concept: name,
                priority: 0.88 - Double(index) * 0.03,
                reason: .missingPrerequisite,
                estimatedMinutes: defaultTaskMinutes,
                prerequisiteDepth: index
            )
        }
        let dependents = ((try? repository.canonicalConcept(named: concept))
            .flatMap { try? repository.ancestors(of: $0.id, depth: 2, limit: limit) } ?? [])
            .map(\.canonicalName)
            .filter { $0.localizedCaseInsensitiveCompare(concept) != .orderedSame }
            .enumerated()
            .map { index, name in
                StudyTask(
                    concept: name,
                    priority: 0.58 - Double(index) * 0.03,
                    reason: .highDependencyConcept,
                    estimatedMinutes: defaultTaskMinutes,
                    prerequisiteDepth: index + 1
                )
            }

        return merged(tasks: prerequisites + dependents)
            .sorted(by: taskSort)
            .prefix(max(1, limit))
            .map { $0 }
    }

    private func prioritizedTasks(limitMinutes: Int) -> [StudyTask] {
        let overdueTasks = reviewScheduler.overdue(limit: 8).enumerated().map { index, review in
            StudyTask(
                concept: review.conceptName,
                priority: 1.20 + review.urgency - Double(index) * 0.01,
                reason: .reviewDue,
                estimatedMinutes: defaultTaskMinutes,
                prerequisiteDepth: -1
            )
        }
        let dueTodayTasks = reviewScheduler.dueToday(limit: 8).enumerated().map { index, review in
            StudyTask(
                concept: review.conceptName,
                priority: 0.76 + review.urgency * 0.05 - Double(index) * 0.01,
                reason: .reviewDue,
                estimatedMinutes: defaultTaskMinutes,
                prerequisiteDepth: -1
            )
        }
        let weakTasks = recommendationEngine.recommendedWeakAreas(limit: 8).flatMap { weakConcept in
            dependencyAwareTasks(for: weakConcept, weakConceptPriority: 0.9)
        }
        let reviewTasks = recommendationEngine.recommendedReviews(limit: 8).enumerated().map { index, concept in
            StudyTask(
                concept: concept,
                priority: 0.74 - Double(index) * 0.02,
                reason: .reviewDue,
                estimatedMinutes: defaultTaskMinutes,
                prerequisiteDepth: 0
            )
        }
        let bottleneckTasks = recommendationEngine.importantConcepts(limit: 6).map { item in
            StudyTask(
                concept: item.conceptName,
                priority: 0.62 + min(0.2, Double(item.downstreamCount) * 0.02),
                reason: .highDependencyConcept,
                estimatedMinutes: defaultTaskMinutes,
                prerequisiteDepth: item.prerequisiteCount
            )
        }

        return merged(tasks: overdueTasks + dueTodayTasks + weakTasks + reviewTasks + bottleneckTasks)
            .sorted(by: taskSort)
            .prefix(max(1, limitMinutes / defaultTaskMinutes))
            .map { $0 }
    }

    private func dependencyAwareTasks(for weakConcept: String, weakConceptPriority: Double) -> [StudyTask] {
        let prerequisites = graphExplanationService.prerequisiteChain(for: weakConcept)
        let prerequisiteTasks = prerequisites.enumerated().map { index, name in
            StudyTask(
                concept: name,
                priority: weakConceptPriority + 0.05 - Double(index) * 0.01,
                reason: .missingPrerequisite,
                estimatedMinutes: defaultTaskMinutes,
                prerequisiteDepth: index
            )
        }
        let weakTask = StudyTask(
            concept: weakConcept,
            priority: weakConceptPriority,
            reason: .weakConcept,
            estimatedMinutes: defaultTaskMinutes,
            prerequisiteDepth: prerequisites.count
        )
        return prerequisiteTasks + [weakTask]
    }

    private func tasksForExamTarget(_ target: String, masteryScores: [String: Double], daysRemaining: Int) -> [StudyTask] {
        let prerequisites = graphExplanationService.prerequisiteChain(for: target)
        let orderedNames = (prerequisites + [target]).uniquedForStudyPlanning()
        return orderedNames.enumerated().map { index, name in
            let mastery = masteryScores[name] ?? masteryScores[name.lowercased()] ?? 0.5
            let dependencyDepth = max(0, orderedNames.count - index - 1)
            let depthWeight = Double(dependencyDepth) * 0.03
            let timePressure = daysRemaining <= 7 ? 0.08 : 0
            return StudyTask(
                concept: name,
                priority: 0.72 + (1.0 - mastery) * 0.22 + depthWeight + timePressure - Double(index) * 0.01,
                reason: index == orderedNames.count - 1 ? .examPreparation : .missingPrerequisite,
                estimatedMinutes: defaultTaskMinutes,
                prerequisiteDepth: index
            )
        }
    }

    private func split(tasks: [StudyTask], days: Int, minutesPerDay: Int, titlePrefix: String) -> [StudySession] {
        var sessions: [StudySession] = []
        var remaining = tasks
        for day in 1...days {
            var dayTasks: [StudyTask] = []
            var minutes = 0
            while let next = remaining.first, minutes + next.estimatedMinutes <= minutesPerDay {
                dayTasks.append(next)
                minutes += next.estimatedMinutes
                remaining.removeFirst()
            }
            sessions.append(StudySession(title: "\(titlePrefix) \(day)", tasks: dayTasks))
        }
        return sessions
    }

    private func merged(tasks: [StudyTask]) -> [StudyTask] {
        var bestByConcept: [String: StudyTask] = [:]
        for task in tasks {
            let key = normalized(task.concept)
            if let existing = bestByConcept[key] {
                if duplicateTaskSort(task, existing) {
                    bestByConcept[key] = task
                }
            } else {
                bestByConcept[key] = task
            }
        }
        return Array(bestByConcept.values)
    }

    private func taskSort(_ lhs: StudyTask, _ rhs: StudyTask) -> Bool {
        let lhsReasonRank = sortReasonRank(lhs)
        let rhsReasonRank = sortReasonRank(rhs)
        if lhsReasonRank != rhsReasonRank {
            return lhsReasonRank > rhsReasonRank
        }
        if lhs.prerequisiteDepth != rhs.prerequisiteDepth {
            return lhs.prerequisiteDepth < rhs.prerequisiteDepth
        }
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        if lhs.reason.rawValue != rhs.reason.rawValue {
            return lhs.reason.rawValue < rhs.reason.rawValue
        }
        return lhs.concept.localizedCaseInsensitiveCompare(rhs.concept) == .orderedAscending
    }

    private func sortReasonRank(_ task: StudyTask) -> Int {
        if task.reason == .reviewDue && task.priority >= 1.0 {
            return 6
        }
        switch task.reason {
        case .missingPrerequisite: return 5
        case .weakConcept: return 4
        case .reviewDue: return 3
        case .examPreparation: return 2
        case .highDependencyConcept: return 1
        }
    }

    private func duplicateTaskSort(_ lhs: StudyTask, _ rhs: StudyTask) -> Bool {
        if isHighPriorityReview(lhs), !isHighPriorityReview(rhs) {
            return true
        }
        if isHighPriorityReview(rhs), !isHighPriorityReview(lhs) {
            return false
        }
        let lhsReason = duplicateReasonRank(lhs.reason)
        let rhsReason = duplicateReasonRank(rhs.reason)
        if lhsReason != rhsReason {
            return lhsReason > rhsReason
        }
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        return lhs.prerequisiteDepth > rhs.prerequisiteDepth
    }

    private func isHighPriorityReview(_ task: StudyTask) -> Bool {
        task.reason == .reviewDue && task.priority >= 1.0
    }

    private func duplicateReasonRank(_ reason: StudyTaskReason) -> Int {
        switch reason {
        case .missingPrerequisite: return 5
        case .weakConcept: return 4
        case .examPreparation: return 3
        case .highDependencyConcept: return 2
        case .reviewDue: return 1
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}

private extension Array where Element == String {
    func uniquedForStudyPlanning() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
