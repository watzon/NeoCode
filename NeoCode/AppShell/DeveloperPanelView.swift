import AppKit
import SwiftUI

struct DeveloperPanelView: View {
    static let windowID = "developer-panel"

    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime
    @Environment(AppLogStore.self) private var appLogStore
    @Environment(\.locale) private var locale

    @State private var copiedSnapshot = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overviewCard

                if let snapshot = store.selectedSessionDebugSnapshot {
                    sessionCard(snapshot)
                    sessionEventsCard(snapshot)
                } else {
                    emptySessionCard
                }

                logsCard
            }
            .padding(22)
        }
        .background(NeoCodeTheme.canvas.ignoresSafeArea())
        .background(DeveloperPanelWindowConfigurator())
        .frame(minWidth: 920, minHeight: 720)
        .task {
            appLogStore.start()
        }
    }

    private var overviewCard: some View {
        DeveloperPanelCard(title: localized("Developer Panel", locale: locale)) {
            VStack(alignment: .leading, spacing: 14) {
                Text(localized("Use this panel to inspect app state, force lightweight refreshes, and jump straight to the app and daemon log files.", locale: locale))
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    DeveloperPill(
                        title: localized("App log", locale: locale),
                        value: appLogStore.captureStatus,
                        tone: appLogStore.lastCaptureError == nil ? .accent : .warning
                    )

                    DeveloperPill(
                        title: localized("Selected session", locale: locale),
                        value: store.selectedSession?.title ?? localized("None", locale: locale),
                        tone: store.selectedSession == nil ? .muted : .accent
                    )
                }

                DeveloperKeyValueRow(label: localized("App log file", locale: locale), value: appLogStore.appLogFilePath)
                DeveloperKeyValueRow(label: localized("Daemon log file", locale: locale), value: appLogStore.daemonLogFilePath)

                HStack(spacing: 10) {
                    Button(localized("Reveal app log", locale: locale)) {
                        reveal(url: URL(fileURLWithPath: appLogStore.appLogFilePath))
                    }
                    .buttonStyle(.borderedProminent)

                    Button(localized("Reveal daemon log", locale: locale)) {
                        reveal(url: URL(fileURLWithPath: appLogStore.daemonLogFilePath))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func sessionCard(_ snapshot: SessionDebugSnapshot) -> some View {
        DeveloperPanelCard(title: localized("Selected Session", locale: locale)) {
            VStack(alignment: .leading, spacing: 14) {
                Text(snapshot.sessionTitle)
                    .font(.neoTitle)
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text(snapshot.sessionID)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textMuted)
                    .textSelection(.enabled)

                if let possibleStuckReason = snapshot.possibleStuckReason {
                    Text(possibleStuckReason)
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.warning)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(NeoCodeTheme.warning.opacity(0.12))
                        )
                }

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                    debugMetric(title: localized("Status", locale: locale), value: snapshot.sessionStatus.rawValue)
                    debugMetric(title: localized("Live activity", locale: locale), value: sessionActivityLabel(snapshot.liveActivity))
                    debugMetric(title: localized("Actively responding", locale: locale), value: yesNo(snapshot.isActivelyResponding))
                    debugMetric(title: localized("Local activity", locale: locale), value: yesNo(snapshot.hasLocalActivity))
                    debugMetric(title: localized("In-progress parts", locale: locale), value: String(snapshot.inProgressMessageCount))
                    debugMetric(title: localized("Blocking in-progress", locale: locale), value: String(snapshot.blockingInProgressMessageCount))
                    debugMetric(title: localized("Background in-progress", locale: locale), value: String(snapshot.nonBlockingInProgressMessageCount))
                    debugMetric(title: localized("Buffered deltas", locale: locale), value: String(snapshot.bufferedDeltaCount))
                    debugMetric(title: localized("Pending permissions", locale: locale), value: String(snapshot.pendingPermissionCount))
                    debugMetric(title: localized("Pending questions", locale: locale), value: String(snapshot.pendingQuestionCount))
                    debugMetric(title: localized("Queued messages", locale: locale), value: String(snapshot.queuedMessageCount))
                    debugMetric(title: localized("Transcript messages", locale: locale), value: String(snapshot.transcriptMessageCount))
                    debugMetric(title: localized("Transcript revision", locale: locale), value: String(snapshot.transcriptRevision))
                    debugMetric(title: localized("Last live event", locale: locale), value: formattedDiagnosticDate(snapshot.lastLiveEventAt, fallback: snapshot.lastLiveEventLabel ?? localized("None", locale: locale)))
                    debugMetric(title: localized("Last transcript refresh", locale: locale), value: formattedDiagnosticDate(snapshot.lastTranscriptRefreshAt))
                    debugMetric(title: localized("Last message completion", locale: locale), value: formattedDiagnosticDate(snapshot.lastCompletedMessageAt))
                    debugMetric(title: localized("Last updated", locale: locale), value: snapshot.lastUpdatedAt.formatted(date: .abbreviated, time: .standard))
                }

                inProgressDiagnosticsCard(snapshot)

                HStack(spacing: 10) {
                    Button(localized("Refresh selected session", locale: locale)) {
                        Task {
                            await store.debugRefreshSelectedSession(using: runtime)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button(localized("Clear local activity", locale: locale)) {
                        store.clearSelectedSessionLocalActivityForDebugging()
                    }
                    .buttonStyle(.bordered)

                    Button(copiedSnapshot ? localized("Copied", locale: locale) : localized("Copy snapshot", locale: locale)) {
                        copy(snapshot.copySummary)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func sessionEventsCard(_ snapshot: SessionDebugSnapshot) -> some View {
        DeveloperPanelCard(title: localized("Recent Session Events", locale: locale)) {
            VStack(alignment: .leading, spacing: 10) {
                if snapshot.recentEvents.isEmpty {
                    Text(localized("No session debug events recorded yet.", locale: locale))
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textMuted)
                } else {
                    ForEach(snapshot.recentEvents.reversed()) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.textMuted)
                                .frame(width: 92, alignment: .leading)

                            Text(event.category.uppercased())
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.accent)
                                .frame(width: 84, alignment: .leading)

                            Text(event.message)
                                .font(.neoBody)
                                .foregroundStyle(NeoCodeTheme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 6)

                        Divider()
                            .overlay(NeoCodeTheme.line)
                    }
                }
            }
        }
    }

    private func inProgressDiagnosticsCard(_ snapshot: SessionDebugSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if snapshot.inProgressDiagnostics.isEmpty {
                Text(localized("No in-progress transcript items are currently being tracked.", locale: locale))
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textMuted)
            } else {
                ForEach(snapshot.inProgressDiagnostics) { diagnostic in
                    HStack(alignment: .top, spacing: 12) {
                        Text(diagnostic.category.rawValue.uppercased())
                            .font(.neoMonoSmall)
                            .foregroundStyle(diagnostic.isBlocking ? NeoCodeTheme.warning : NeoCodeTheme.accent)
                            .frame(width: 150, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(diagnostic.title)
                                .font(.neoBody)
                                .foregroundStyle(NeoCodeTheme.textPrimary)

                            Text(diagnostic.isBlocking ? localized("Blocking", locale: locale) : localized("Non-blocking background work", locale: locale))
                                .font(.neoMeta)
                                .foregroundStyle(NeoCodeTheme.textMuted)

                            Text("reason: \(diagnostic.blockingReason.rawValue) | role: \(diagnostic.role) | message: \(diagnostic.messageID ?? "none")")
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.textMuted)
                                .textSelection(.enabled)

                            Text("part time: \(diagnostic.itemTimestamp.formatted(date: .abbreviated, time: .standard)) | message completed: \(formattedDiagnosticDate(diagnostic.parentMessageCompletedAt))")
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.textMuted)
                                .textSelection(.enabled)

                            if let detail = diagnostic.detail {
                                Text(detail)
                                    .font(.neoMonoSmall)
                                    .foregroundStyle(NeoCodeTheme.textSecondary)
                                    .textSelection(.enabled)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)

                    Divider()
                        .overlay(NeoCodeTheme.line)
                }
            }
        }
    }

    private var emptySessionCard: some View {
        DeveloperPanelCard(title: localized("Selected Session", locale: locale)) {
            Text(localized("Select a thread in the main window to inspect its live session state here.", locale: locale))
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textSecondary)
        }
    }

    private var logsCard: some View {
        DeveloperPanelCard(title: localized("Recent App Logs", locale: locale)) {
            VStack(alignment: .leading, spacing: 10) {
                if let lastCaptureError = appLogStore.lastCaptureError {
                    Text(lastCaptureError)
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.warning)
                }

                let filteredEntries = appLogStore.recentEntries(matching: store.selectedSessionID, limit: 80)
                if filteredEntries.isEmpty {
                    Text(localized("No app logs matched the current selection yet.", locale: locale))
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textMuted)
                } else {
                    ForEach(filteredEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Text(entry.date.formatted(date: .omitted, time: .standard))
                                    .font(.neoMonoSmall)
                                    .foregroundStyle(NeoCodeTheme.textMuted)

                                Text(entry.level.uppercased())
                                    .font(.neoMonoSmall)
                                    .foregroundStyle(logTone(for: entry.level))

                                Text(entry.category)
                                    .font(.neoMonoSmall)
                                    .foregroundStyle(NeoCodeTheme.accent)
                            }

                            Text(entry.message)
                                .font(.neoBody)
                                .foregroundStyle(NeoCodeTheme.textPrimary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 6)

                        Divider()
                            .overlay(NeoCodeTheme.line)
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 160), spacing: 12),
            GridItem(.flexible(minimum: 160), spacing: 12),
            GridItem(.flexible(minimum: 160), spacing: 12),
        ]
    }

    private func debugMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.neoMeta)
                .foregroundStyle(NeoCodeTheme.textMuted)

            Text(value)
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NeoCodeTheme.panelSoft)
        )
    }

    private func sessionActivityLabel(_ activity: OpenCodeSessionActivity?) -> String {
        guard let activity else { return localized("None", locale: locale) }

        switch activity {
        case .idle:
            return localized("Idle", locale: locale)
        case .busy:
            return localized("Busy", locale: locale)
        case .retry(let attempt, _, let next):
            return "Retry #\(attempt) in \(Int(next.rounded()))s"
        }
    }

    private func yesNo(_ value: Bool) -> String {
        value ? localized("Yes", locale: locale) : localized("No", locale: locale)
    }

    private func formattedDiagnosticDate(_ date: Date?, fallback: String? = nil) -> String {
        if let date {
            return date.formatted(date: .abbreviated, time: .standard)
        }

        return fallback ?? localized("None", locale: locale)
    }

    private func logTone(for level: String) -> Color {
        switch level {
        case "fault", "error":
            return NeoCodeTheme.warning
        case "notice":
            return NeoCodeTheme.accent
        default:
            return NeoCodeTheme.textMuted
        }
    }

    private func reveal(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedSnapshot = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                copiedSnapshot = false
            }
        }
    }
}

private struct DeveloperPanelWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        window.isRestorable = false
    }
}

private struct DeveloperPanelCard<Content: View>: View {
    let title: String

    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.neoTitle)
                .foregroundStyle(NeoCodeTheme.textPrimary)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(NeoCodeTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }
}

private struct DeveloperKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.neoMeta)
                .foregroundStyle(NeoCodeTheme.textMuted)

            Text(value)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .textSelection(.enabled)
        }
    }
}

private struct DeveloperPill: View {
    enum Tone {
        case accent
        case warning
        case muted
    }

    let title: String
    let value: String
    let tone: Tone

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.neoMeta)
                .foregroundStyle(NeoCodeTheme.textMuted)

            Text(value)
                .font(.neoBody)
                .foregroundStyle(foregroundColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
    }

    private var foregroundColor: Color {
        switch tone {
        case .accent:
            return NeoCodeTheme.accent
        case .warning:
            return NeoCodeTheme.warning
        case .muted:
            return NeoCodeTheme.textSecondary
        }
    }

    private var backgroundColor: Color {
        switch tone {
        case .accent:
            return NeoCodeTheme.accent.opacity(0.14)
        case .warning:
            return NeoCodeTheme.warning.opacity(0.14)
        case .muted:
            return NeoCodeTheme.panelSoft
        }
    }
}
