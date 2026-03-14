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
            AppSceneView()
        }
        .defaultSize(width: 1280, height: 900)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
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
