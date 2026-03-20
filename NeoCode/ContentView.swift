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
    @Environment(AppUpdateService.self) private var updateService
    @Environment(\.scenePhase) private var scenePhase
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
        .background(
            Group {
                if NeoCodeTheme.isSidebarTranslucent {
                    NeoCodeTheme.canvas.opacity(NeoCodeTheme.windowWashOpacity)
                } else {
                    NeoCodeTheme.canvas
                }
            }
            .ignoresSafeArea()
        )
        .background(WindowChromeConfigurator(updateService: updateService))
        .overlay(alignment: .topTrailing) {
            if let runtimeStartupMessage {
                StatusToast(message: runtimeStartupMessage)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
            } else if let toastMessage {
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
        .onChange(of: selectedRuntimeFailureMessage) { _, newValue in
            showToast(newValue)
        }
    }

    private var selectedRuntimeFailureMessage: String? {
        runtime.failureMessage(for: store.selectedProject?.path)
    }

    private var runtimeStartupMessage: String? {
        guard let projectPath = store.selectedProject?.path,
              case .starting = runtime.state(for: projectPath) else {
            return nil
        }

        let detail = runtime.detailLabel(for: projectPath)
        let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
        return detail == projectName ? nil : detail
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
        let bootstrappingEnabled = isRuntimeBootstrappingEnabled
        let skipsForSettings = store.isSettingsSelected

        await withTaskCancellationHandler {
            guard bootstrappingEnabled else { return }
            guard !skipsForSettings else { return }

            await store.syncSelection(using: runtime)
        } onCancel: {}
    }

    private func runDashboardRefreshTask(for taskKey: String) async {
        let bootstrappingEnabled = isRuntimeBootstrappingEnabled
        let isSettingsSelected = store.isSettingsSelected
        let isDashboardSelected = store.isDashboardSelected

        await withTaskCancellationHandler {
            guard bootstrappingEnabled else { return }

            if isSettingsSelected {
                store.suspendDashboardRefresh()
            } else if isDashboardSelected {
                await store.startDashboard(using: runtime)
            } else {
                store.suspendDashboardRefresh()
            }
        } onCancel: {}
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
            + ":\(scenePhaseTaskKey)"
            + ":\(store.lifecycleRefreshToken)"
    }

    private var selectionSyncTaskKey: String {
        if let settingsSection = store.selectedSettingsSection {
            return "settings:\(settingsSection.rawValue)"
        }

        let projectID = store.selectedProject?.id.uuidString ?? "none"
        let sessionID = store.selectedSessionID ?? "dashboard"
        return "\(projectID):\(sessionID):\(scenePhaseTaskKey):\(store.lifecycleRefreshToken)"
    }

    private var scenePhaseTaskKey: String {
        switch scenePhase {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }
}

#Preview {
    ContentView()
        .environment(AppStore())
        .environment(OpenCodeRuntime())
        .environment(AppUpdateService())
        .frame(width: 1440, height: 920)
}
