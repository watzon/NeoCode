//
//  NeoCodeUITestsLaunchTests.swift
//  NeoCodeUITests
//
//  Created by Chris W on 3/13/26.
//

import XCTest
import AppKit

final class NeoCodeUITestsLaunchTests: XCTestCase {
    private let targetBundleIdentifier = "tech.watzon.NeoCode"
    private let uiTestModeKey = "NEOCODE_UI_TEST_MODE"
    private var launchedApplication: XCUIApplication?

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if let launchedApplication, launchedApplication.state != .notRunning {
            launchedApplication.terminate()
        }
        launchedApplication = nil
    }

    @MainActor
    func testLaunch() throws {
        try skipIfTargetAppIsAlreadyRunning()

        let app = configuredApplication()
        launchedApplication = app
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func configuredApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[uiTestModeKey] = "1"
        return app
    }

    private func skipIfTargetAppIsAlreadyRunning() throws {
        let runningApplications = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleIdentifier)
        if !runningApplications.isEmpty {
            throw XCTSkip("Quit NeoCode before running UI tests so XCTest does not force-terminate your active app session.")
        }
    }
}
