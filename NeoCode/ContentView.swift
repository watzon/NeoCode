//
//  ContentView.swift
//  NeoCode
//
//  Created by Chris W on 3/13/26.
//

import OSLog
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime
    @Environment(AppUpdateService.self) private var updateService
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
        .background(WindowChromeConfigurator(updateService: updateService))
        .overlay(alignment: .topTrailing) {
            if let toastMessage {
                ErrorToast(message: toastMessage)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: selectionSyncTaskKey) {
            await runSelectionSyncTask(for: selectionSyncTaskKey)
        }
        .task(id: dashboardRefreshTaskKey) {
            await runDashboardRefreshTask(for: dashboardRefreshTaskKey)
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

    private func runSelectionSyncTask(for taskKey: String) async {
        let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "ContentView")
        let bootstrappingEnabled = isRuntimeBootstrappingEnabled
        let skipsForSettings = store.isSettingsSelected

        await withTaskCancellationHandler {
            guard bootstrappingEnabled else { return }
            guard !skipsForSettings else {
                logger.debug("Skipping selection sync for settings key=\(taskKey, privacy: .public)")
                return
            }

            logger.debug("Starting selection sync key=\(taskKey, privacy: .public)")
            await store.syncSelection(using: runtime)
            logger.debug("Finished selection sync key=\(taskKey, privacy: .public)")
        } onCancel: {
            logger.info(
                "Selection sync task cancelled key=\(taskKey, privacy: .public) bootstrapping=\(bootstrappingEnabled, privacy: .public) settings=\(skipsForSettings, privacy: .public)"
            )
        }
    }

    private func runDashboardRefreshTask(for taskKey: String) async {
        let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "ContentView")
        let bootstrappingEnabled = isRuntimeBootstrappingEnabled
        let isSettingsSelected = store.isSettingsSelected
        let isDashboardSelected = store.isDashboardSelected

        await withTaskCancellationHandler {
            guard bootstrappingEnabled else { return }

            if isSettingsSelected {
                logger.debug("Suspending dashboard refresh for settings key=\(taskKey, privacy: .public)")
                store.suspendDashboardRefresh()
            } else if isDashboardSelected {
                logger.debug("Starting dashboard refresh task key=\(taskKey, privacy: .public)")
                await store.startDashboard(using: runtime)
                logger.debug("Finished dashboard refresh task key=\(taskKey, privacy: .public)")
            } else {
                logger.debug("Suspending dashboard refresh outside dashboard key=\(taskKey, privacy: .public)")
                store.suspendDashboardRefresh()
            }
        } onCancel: {
            logger.info(
                "Dashboard task cancelled key=\(taskKey, privacy: .public) bootstrapping=\(bootstrappingEnabled, privacy: .public) settings=\(isSettingsSelected, privacy: .public) dashboard=\(isDashboardSelected, privacy: .public)"
            )
        }
    }

    private var isRuntimeBootstrappingEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment[uiTestModeKey] != "1"
            && environment["XCTestConfigurationFilePath"] == nil
    }

    private var dashboardRefreshTaskKey: String {
        let mode: String
        if store.isSettingsSelected {
            mode = "settings"
        } else if store.isDashboardSelected {
            mode = "dashboard"
        } else {
            mode = "conversation"
        }

        return "\(mode)-\(store.dashboardProjectSignature)"
    }

    private var selectionSyncTaskKey: String {
        if let settingsSection = store.selectedSettingsSection {
            return "settings:\(settingsSection.rawValue)"
        }

        let projectID = store.selectedProject?.id.uuidString ?? "none"
        let sessionID = store.selectedSessionID ?? "dashboard"
        return "\(projectID):\(sessionID)"
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
        .environment(OpenCodeRuntime())
        .environment(AppUpdateService())
        .frame(width: 1440, height: 920)
}
