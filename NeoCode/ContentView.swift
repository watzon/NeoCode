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

            ConversationScreen(selectedSessionID: store.selectedSessionID)
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
        .task(id: store.selectedProject?.id) {
            guard isRuntimeBootstrappingEnabled else { return }
            await store.connect(to: runtime)
        }
        .task(id: store.selectedSessionID) {
            guard isRuntimeBootstrappingEnabled else { return }
            await store.syncSelectedSession(using: runtime)
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
}

#Preview {
    ContentView()
        .environment(AppStore())
        .frame(width: 1440, height: 920)
}
