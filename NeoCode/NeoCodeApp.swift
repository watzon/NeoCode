//
//  NeoCodeApp.swift
//  NeoCode
//
//  Created by Chris W on 3/13/26.
//

import SwiftUI

@main
struct NeoCodeApp: App {
    var body: some Scene {
        WindowGroup {
            if AppTestMode.isUnitTestHost {
                UnitTestHostView()
            } else {
                AppSceneView()
            }
        }
        .defaultSize(width: 1280, height: 900)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
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
            .frame(minWidth: 980, minHeight: 600)
    }
}

private struct AppSceneView: View {
    @State private var store = AppStore()
    @State private var runtime = OpenCodeRuntime()

    var body: some View {
        ContentView()
            .frame(minWidth: 980, minHeight: 600)
            .environment(store)
            .environment(runtime)
            .preferredColorScheme(.dark)
    }
}
