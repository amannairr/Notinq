import XCTest
@testable import Notinq

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        defaultsSuiteName = "OnboardingViewModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        super.tearDown()
    }

    func testFirstLaunchStartsIncomplete() {
        let viewModel = OnboardingViewModel(defaults: defaults)

        XCTAssertFalse(viewModel.isCompleted)
        XCTAssertEqual(viewModel.currentStepIndex, 0)
        XCTAssertEqual(viewModel.currentStep.title, "Welcome to Notinq")
    }

    func testAdvanceCompletesAndPersistsFinalStep() {
        let viewModel = OnboardingViewModel(defaults: defaults)

        while !viewModel.isLastStep {
            viewModel.advance()
        }
        viewModel.advance()

        XCTAssertTrue(viewModel.isCompleted)
        XCTAssertTrue(defaults.bool(forKey: OnboardingViewModel.completionKey))
    }

    func testSkipCompletesWithoutBlockingFutureLaunches() {
        var viewModel = OnboardingViewModel(defaults: defaults)
        viewModel.skip()

        XCTAssertTrue(viewModel.isCompleted)

        viewModel = OnboardingViewModel(defaults: defaults)
        XCTAssertTrue(viewModel.isCompleted)
    }
}
