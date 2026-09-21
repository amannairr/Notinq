import Foundation
import Combine

struct DashboardReviewRecommendation: Identifiable, Equatable, Sendable {
    var id: String { concept }
    let concept: String
    let reason: String
}

@MainActor
final class LearningDashboardViewModel: ObservableObject {
    @Published private(set) var masteryScore: Double = 0
    @Published private(set) var retentionScore: Double = 0
    @Published private(set) var confidenceScore: Double = 0
    @Published private(set) var examReadiness: Double = 0
    @Published private(set) var studyStreak: Int = 0
    @Published private(set) var weakTopics: [String] = []
    @Published private(set) var strongTopics: [String] = []
    @Published private(set) var recommendedReviews: [DashboardReviewRecommendation] = []
    @Published private(set) var todaysPlan: [StudyTask] = []
    @Published private(set) var dueReviews: [ScheduledReview] = []
    @Published private(set) var learningGaps: [LearningGapVisualizationItem] = []
    @Published private(set) var graphStatistics = KnowledgeGraphStatistics(conceptCount: 0, relationshipCount: 0, connectedComponents: 0, averageDegree: 0)
    @Published private(set) var isLoading = false
    @Published private(set) var loadDurationMilliseconds: Double = 0

    private let studentKnowledgeService: StudentKnowledgeService
    private let recommendationEngine: LearningRecommendationEngine
    private let studyPlannerService: StudyPlannerService
    private let reviewScheduler: ReviewScheduler

    init(
        studentKnowledgeService: StudentKnowledgeService = StudentKnowledgeService(),
        recommendationEngine: LearningRecommendationEngine = LearningRecommendationEngine(),
        studyPlannerService: StudyPlannerService = StudyPlannerService(),
        reviewScheduler: ReviewScheduler = ReviewScheduler()
    ) {
        self.studentKnowledgeService = studentKnowledgeService
        self.recommendationEngine = recommendationEngine
        self.studyPlannerService = studyPlannerService
        self.reviewScheduler = reviewScheduler
    }

    func load() {
        guard isLoading == false else { return }
        isLoading = true
        Task {
            await loadNow()
        }
    }

    func loadNow() async {
        let service = studentKnowledgeService
        let recommendations = recommendationEngine
        let planner = studyPlannerService
        let scheduler = reviewScheduler
        let snapshot = await Task.detached(priority: .userInitiated) {
            let start = Date()
            let summary = service.summary()
            let stats = service.graphStatistics()
            let plan = planner.dailyPlan(maxMinutes: 60).tasks
            let dueReviews = scheduler.scheduledReviews(limit: 8)
            let reviews = recommendations.recommendedReviews(limit: 8).map { concept in
                DashboardReviewRecommendation(
                    concept: concept,
                    reason: "Low mastery or due for review based on student progress."
                )
            }
            let gaps = recommendations.learningGaps(limit: 6)
            let elapsed = Date().timeIntervalSince(start) * 1_000
            return (summary, stats, plan, dueReviews, reviews, gaps, elapsed)
        }.value

        masteryScore = snapshot.0.overallMastery
        retentionScore = snapshot.0.retentionScore
        confidenceScore = snapshot.0.confidenceScore
        examReadiness = snapshot.0.examReadiness
        studyStreak = snapshot.0.studyStreak
        weakTopics = snapshot.0.weakTopics
        strongTopics = snapshot.0.strongTopics
        todaysPlan = snapshot.2
        dueReviews = snapshot.3
        recommendedReviews = snapshot.4
        learningGaps = snapshot.5
        graphStatistics = snapshot.1
        loadDurationMilliseconds = snapshot.6
        isLoading = false
    }
}
