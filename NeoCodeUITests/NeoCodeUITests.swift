//
//  NeoCodeUITests.swift
//  NeoCodeUITests
//
//  Created by Chris W on 3/13/26.
//

import XCTest
import AppKit

final class NeoCodeUITests: XCTestCase {
    private let targetBundleIdentifier = "tech.watzon.NeoCode"
    private let uiTestModeKey = "NEOCODE_UI_TEST_MODE"
    private let scrollFixtureKey = "NEOCODE_UI_TEST_SCROLL_FIXTURE"
    private var launchedApplication: XCUIApplication?

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        if let launchedApplication, launchedApplication.state != .notRunning {
            launchedApplication.terminate()
        }
        launchedApplication = nil
    }

    @MainActor
    func testExample() throws {
        try skipIfTargetAppIsAlreadyRunning()

        let app = configuredApplication()
        launchedApplication = app
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        try skipIfTargetAppIsAlreadyRunning()

        measure(metrics: [XCTApplicationLaunchMetric()]) {
            configuredApplication().launch()
        }

        terminateLaunchedApplicationsIfNeeded()
    }

    @MainActor
    func testBackToBottomAppearsAfterScrollingTranscriptFixture() throws {
        try skipIfTargetAppIsAlreadyRunning()

        let app = configuredApplication(scrollFixture: true)
        launchedApplication = app
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let transcript = app.scrollViews["conversation.transcript.scrollView"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))

        let backToBottomButton = app.buttons["conversation.backToBottom"]
        XCTAssertFalse(backToBottomButton.exists)

        transcript.click()
        transcript.typeKey(.pageUp, modifierFlags: [])
        transcript.typeKey(.pageUp, modifierFlags: [])

        let appeared = backToBottomButton.waitForExistence(timeout: 2)
        XCTAssertTrue(appeared, "Expected back-to-bottom button after paging upward in the transcript fixture.")
    }

    private func configuredApplication(scrollFixture: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[uiTestModeKey] = "1"
        if scrollFixture {
            app.launchEnvironment[scrollFixtureKey] = "1"
        }
        return app
    }

    private func skipIfTargetAppIsAlreadyRunning() throws {
        let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleIdentifier)
        if !runningApplications.isEmpty {
            throw XCTSkip("Quit NeoCode before running UI tests so XCTest does not force-terminate your active app session.")
        }
    }

    private func terminateLaunchedApplicationsIfNeeded() {
        NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleIdentifier)
            .forEach { $0.terminate() }
    }
}
