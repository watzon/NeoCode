//
//  NeoCodeApp.swift
//  NeoCode
//
//  Created by Chris W on 3/13/26.
//

import AppKit
import SwiftUI

@main
struct NeoCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            if AppTestMode.isUnitTestHost {
                UnitTestHostView()
            } else {
                AppSceneView(appDelegate: appDelegate)
            }
        }
        .defaultSize(width: 1280, height: 900)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    enum TerminationIntent {
        case userQuit
        case updateRelaunch
    }

    var onDidBecomeActive: (() -> Void)?
    var onWillTerminate: (() -> Void)?
    var terminationWarningProvider: (() -> AppTerminationWarningContext?)?
    var onUpdateTerminationCancelled: (() -> Void)?

    private var terminationIntent: TerminationIntent = .userQuit

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AppTestMode.isUnitTestHost else { return }

        NSApp.setActivationPolicy(.prohibited)
        DispatchQueue.main.async {
            NSApp.windows.forEach { window in
                window.alphaValue = 0
                window.ignoresMouseEvents = true
                window.orderOut(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        onDidBecomeActive?()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let warning = terminationWarningProvider?() else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText =
            terminationIntent == .updateRelaunch
            ? "Install update and restart NeoCode?"
            : "Quit NeoCode?"
        alert.informativeText = terminationAlertMessage(for: warning, intent: terminationIntent)
        alert.addButton(
            withTitle: terminationIntent == .updateRelaunch ? "Install and Restart" : "Quit")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            return .terminateNow
        }

        if terminationIntent == .updateRelaunch {
            terminationIntent = .userQuit
            onUpdateTerminationCancelled?()
        }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        if terminationIntent == .updateRelaunch {
            relaunchApplication()
        }
        onWillTerminate?()
    }

    func requestUpdateRelaunch() {
        terminationIntent = .updateRelaunch
        NSApp.terminate(nil)
    }

    private func terminationAlertMessage(
        for warning: AppTerminationWarningContext, intent: TerminationIntent
    ) -> String {
        let intro: String
        switch intent {
        case .userQuit:
            intro =
                "NeoCode still has active sessions. Quitting now may interrupt responses or leave pending questions unanswered."
        case .updateRelaunch:
            intro =
                "NeoCode needs to close to finish installing the update, but active sessions are still running. Restarting now may interrupt responses or leave pending questions unanswered."
        }

        let preview = warning.sessions.prefix(5).map { session in
            "- \(session.sessionTitle) - \(session.projectName) (\(session.reason))"
        }.joined(separator: "\n")

        let moreCount = warning.count - min(warning.count, 5)
        let suffix = moreCount > 0 ? "\n...and \(moreCount) more." : ""

        return "\(intro)\n\nActive sessions:\n\(preview)\(suffix)"
    }

    private func relaunchApplication() {
        let appPath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; open -n \"\(appPath)\""]
        try? process.run()
    }
}

private enum AppTestMode {
    private static let uiTestModeKey = "NEOCODE_UI_TEST_MODE"

    static var isUnitTestHost: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment[uiTestModeKey] != "1"
            && environment["XCTestConfigurationFilePath"] != nil
    }
}

private enum AppUITestFixture {
    private static let scrollFixtureKey = "NEOCODE_UI_TEST_SCROLL_FIXTURE"

    static var scrollFixtureSessionID: String? {
        guard ProcessInfo.processInfo.environment[scrollFixtureKey] == "1" else { return nil }
        return "ses_ui_scroll_fixture"
    }

    static func makeStoreIfNeeded() -> AppStore? {
        guard let sessionID = scrollFixtureSessionID else { return nil }

        let now = Date(timeIntervalSince1970: 1_773_935_000)
        let transcript = (0..<80).flatMap { index -> [ChatMessage] in
            let timestamp = now.addingTimeInterval(Double(index) * 30)
            return [
                ChatMessage(
                    id: "fixture-user-\(index)",
                    messageID: "fixture-user-msg-\(index)",
                    role: .user,
                    text: "User prompt \(index)",
                    timestamp: timestamp,
                    emphasis: .normal
                ),
                ChatMessage(
                    id: "fixture-assistant-\(index)",
                    messageID: "fixture-assistant-msg-\(index)",
                    role: .assistant,
                    text: "Assistant response \(index)\n\n" + String(repeating: "This is fixture transcript content for UI scrolling. ", count: 10),
                    timestamp: timestamp.addingTimeInterval(5),
                    emphasis: .normal
                ),
            ]
        }

        let store = AppStore(projects: [
            ProjectSummary(
                name: "NeoCode UI Tests",
                path: "/tmp/NeoCodeUITests",
                sessions: [
                    SessionSummary(
                        id: sessionID,
                        title: "Scroll Fixture",
                        lastUpdatedAt: now,
                        transcript: transcript
                    ),
                ]
            ),
        ])
        if let projectID = store.projects.first?.id {
            store.selectedProjectID = projectID
            store.selectedContent = .session(sessionID)
        }
        return store
    }
}

private struct UnitTestHostView: View {
    var body: some View {
        Color.clear
            .frame(minWidth: 1, minHeight: 1)
            .onAppear {
                DispatchQueue.main.async {
                    NSApp.windows.forEach { window in
                        window.alphaValue = 0
                        window.ignoresMouseEvents = true
                        window.orderOut(nil)
                    }
                }
            }
    }
}

private struct AppSceneView: View {
    @State private var store: AppStore
    @State private var runtime = OpenCodeRuntime()
    @State private var updateService = AppUpdateService()
    let appDelegate: AppDelegate

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        _store = State(initialValue: AppUITestFixture.makeStoreIfNeeded() ?? AppStore())
    }

    var body: some View {
        ContentView()
            .frame(minWidth: 1165, minHeight: 875)
            .environment(store)
            .environment(runtime)
            .environment(updateService)
            .environment(\.locale, store.appSettings.general.appLanguage.locale)
            .task(id: store.appSettings.general.opencodeExecutablePath) {
                runtime.preferredExecutablePath = store.appSettings.general.opencodeExecutablePath
            }
            .onAppear {
                NeoCodeTheme.configure(with: store.appSettings.appearance)
                appDelegate.onDidBecomeActive = {
                    store.handleApplicationDidBecomeActive()
                }
                appDelegate.terminationWarningProvider = {
                    store.terminationWarningContext()
                }
                appDelegate.onUpdateTerminationCancelled = {
                    updateService.handleTerminationCancelledDuringInstall()
                }
                appDelegate.onWillTerminate = {
                    store.flushPendingProjectPersistence()
                    runtime.stop()
                    ManagedProcessRegistry.shared.terminateAll()
                }
            }
    }
}
