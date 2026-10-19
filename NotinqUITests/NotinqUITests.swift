//
//  NotinqUITests.swift
//  NotinqUITests
//
//  Created by Aman Nair on 11/04/26.
//

import XCTest

final class NotinqUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesForStudentWorkflowSmoke() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testCaptureReleaseCandidateScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        attachScreenshot(named: "01-launch-editor", app: app)

        app.typeKey("3", modifierFlags: .command)
        _ = app.staticTexts["Study Map"].waitForExistence(timeout: 2)
        attachScreenshot(named: "02-after-command-3", app: app)
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
