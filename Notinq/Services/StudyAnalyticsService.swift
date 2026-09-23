import Foundation

final class StudyAnalyticsService {
    static let shared = StudyAnalyticsService()

    private let studentConceptService: StudentConceptService
    private let reviewEventStore: ReviewEventStore

    init(
        studentConceptService: StudentConceptService = .shared,
        reviewEventStore: ReviewEventStore = .shared
    ) {
        self.studentConceptService = studentConceptService
        self.reviewEventStore = reviewEventStore
    }

    func weakestConcepts(limit: Int = 10) -> [StudentConceptRecord] {
        ((try? studentConceptService.weakestConcepts(limit: limit)) ?? [])
            .sorted { $0.effectiveMasteryScore < $1.effectiveMasteryScore }
    }

    func strongestConcepts(limit: Int = 10) -> [StudentConceptRecord] {
        ((try? studentConceptService.strongestConcepts(limit: limit)) ?? [])
            .sorted { $0.effectiveMasteryScore > $1.effectiveMasteryScore }
    }

    func recentlyReviewedConcepts(limit: Int = 10) -> [StudentConceptRecord] {
        ((try? studentConceptService.recentlyReviewedConcepts(limit: limit)) ?? [])
            .sorted { ($0.lastReviewed ?? .distantPast) > ($1.lastReviewed ?? .distantPast) }
    }

    func conceptsNeedingReview(limit: Int = 10) -> [StudentConceptRecord] {
        ((try? studentConceptService.conceptsNeedingReview(limit: limit)) ?? [])
            .sorted {
                if $0.effectiveMasteryScore != $1.effectiveMasteryScore {
                    return $0.effectiveMasteryScore < $1.effectiveMasteryScore
                }
                return ($0.lastReviewed ?? .distantPast) < ($1.lastReviewed ?? .distantPast)
            }
    }

    func reviewHistory(for conceptID: String) -> [ReviewEvent] {
        (try? reviewEventStore.history(for: conceptID)) ?? []
    }
}
