//
//  ContentView.swift
//  NeoCode
//
//  Created by Chris W on 3/13/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime
    @State private var toastMessage: String?

    private let uiTestModeKey = "NEOCODE_UI_TEST_MODE"

    var body: some View {
        HStack(spacing: 0) {
            AppSidebarView()
                .frame(width: 318)

            PrimaryContentScreen()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(NeoCodeTheme.canvas.ignoresSafeArea())
        .background(WindowChromeConfigurator())
        .overlay(alignment: .topTrailing) {
            if let toastMessage {
                ErrorToast(message: toastMessage)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: selectionSyncTaskKey) {
            guard isRuntimeBootstrappingEnabled else { return }
            await store.syncSelection(using: runtime)
        }
        .task(id: dashboardRefreshTaskKey) {
            guard isRuntimeBootstrappingEnabled else { return }

            if store.isDashboardSelected {
                await store.startDashboard(using: runtime)
            } else {
                store.suspendDashboardRefresh()
            }
        }
        .onChange(of: store.lastError) { _, newValue in
            showToast(newValue)
        }
        .onChange(of: runtime.userFacingError) { _, newValue in
            showToast(newValue)
        }
    }

    private func showToast(_ message: String?) {
        guard let message, !message.isEmpty else { return }

        withAnimation(.easeOut(duration: 0.18)) {
            toastMessage = message
        }

        Task {
            try? await Task.sleep(for: .seconds(4))
            if toastMessage == message {
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.18)) {
                        toastMessage = nil
                    }
                }
            }
        }
    }

    private var isRuntimeBootstrappingEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment[uiTestModeKey] != "1"
            && environment["XCTestConfigurationFilePath"] == nil
    }

    private var dashboardRefreshTaskKey: String {
        "\(store.isDashboardSelected)-\(store.dashboardProjectSignature)"
    }

    private var selectionSyncTaskKey: String {
        let projectID = store.selectedProject?.id.uuidString ?? "none"
        let sessionID = store.selectedSessionID ?? "dashboard"
        return "\(projectID):\(sessionID)"
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
        .frame(width: 1440, height: 920)
}
