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
    var onDidBecomeActive: (() -> Void)?
    var onWillTerminate: (() -> Void)?

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

    func applicationWillTerminate(_ notification: Notification) {
        onWillTerminate?()
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
    @State private var store = AppStore()
    @State private var runtime = OpenCodeRuntime()
    @State private var updateService = AppUpdateService()
    let appDelegate: AppDelegate

    var body: some View {
        ContentView()
            .frame(minWidth: 980, minHeight: 600)
            .environment(store)
            .environment(runtime)
            .environment(updateService)
            .onAppear {
                NeoCodeTheme.configure(with: store.appSettings.appearance)
                appDelegate.onDidBecomeActive = {
                    store.handleApplicationDidBecomeActive()
                }
                appDelegate.onWillTerminate = {
                    store.flushPendingProjectPersistence()
                    runtime.stop()
                    ManagedProcessRegistry.shared.terminateAll()
                }
            }
    }
}
