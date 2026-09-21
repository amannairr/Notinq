import Combine
import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    struct Step: Identifiable, Equatable {
        let id: Int
        let title: String
        let message: String
        let actionTitle: String
    }

    static let completionKey = "hasCompletedOnboarding"

    @Published private(set) var currentStepIndex = 0
    @Published private(set) var isCompleted: Bool

    let steps: [Step] = [
        Step(
            id: 0,
            title: "Welcome to Notinq",
            message: "Capture notes, build understanding, and turn your knowledge graph into study guidance.",
            actionTitle: "Continue"
        ),
        Step(
            id: 1,
            title: "Create your first note",
            message: "Start with a lecture, reading, or rough idea. Notinq keeps the editor ready and out of your way.",
            actionTitle: "Continue"
        ),
        Step(
            id: 2,
            title: "Understand the Knowledge Graph",
            message: "Concepts and relationships are extracted locally so related ideas can connect across notes.",
            actionTitle: "Continue"
        ),
        Step(
            id: 3,
            title: "Use the Dashboard",
            message: "See weak areas, review priorities, retention risk, and graph-backed study recommendations.",
            actionTitle: "Continue"
        ),
        Step(
            id: 4,
            title: "Ask the Adaptive Tutor",
            message: "Tutor responses can use your notes, graph context, prerequisites, and mastery state.",
            actionTitle: "Finish"
        )
    ]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isCompleted = defaults.bool(forKey: Self.completionKey)
    }

    var currentStep: Step {
        steps[min(currentStepIndex, steps.count - 1)]
    }

    var progressText: String {
        "\(currentStepIndex + 1) of \(steps.count)"
    }

    var canGoBack: Bool {
        currentStepIndex > 0
    }

    var isLastStep: Bool {
        currentStepIndex == steps.count - 1
    }

    func advance() {
        if isLastStep {
            complete()
        } else {
            currentStepIndex += 1
        }
    }

    func goBack() {
        guard canGoBack else { return }
        currentStepIndex -= 1
    }

    func skip() {
        complete()
    }

    func resetForTesting() {
        defaults.removeObject(forKey: Self.completionKey)
        currentStepIndex = 0
        isCompleted = false
    }

    private func complete() {
        defaults.set(true, forKey: Self.completionKey)
        isCompleted = true
    }
}
