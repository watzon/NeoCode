import SwiftUI

struct PrimaryContentScreen: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.isDashboardSelected {
            DashboardScreen()
        } else {
            ConversationScreen(selectedSessionID: store.selectedSessionID)
        }
    }
}

struct DashboardScreen: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DashboardHeroCard(snapshot: store.dashboardSnapshot, status: store.dashboardStatus)

                if let snapshot = store.dashboardSnapshot,
                   snapshot.totalProjects > 0 {
                    HStack(alignment: .top, spacing: 16) {
                        DashboardMetricCard(
                            title: "Projects",
                            value: DashboardFormat.count(snapshot.totalProjects),
                            detail: "\(DashboardFormat.count(snapshot.indexedSessionCount)) of \(DashboardFormat.count(snapshot.knownSessionCount)) sessions cached",
                            accent: NeoCodeTheme.accent
                        )
                        DashboardMetricCard(
                            title: "Total Tokens",
                            value: DashboardFormat.count(snapshot.tokens.total),
                            detail: "Input, output, reasoning, and cache usage",
                            accent: NeoCodeTheme.success
                        )
                        DashboardMetricCard(
                            title: "Messages",
                            value: DashboardFormat.count(snapshot.totalMessages),
                            detail: "\(DashboardFormat.count(snapshot.userMessages)) user, \(DashboardFormat.count(snapshot.assistantMessages)) assistant",
                            accent: NeoCodeTheme.textPrimary
                        )
                        DashboardMetricCard(
                            title: "Cost",
                            value: DashboardFormat.currency(snapshot.totalCost),
                            detail: snapshot.latestActivityAt.map { "Last activity \(DashboardFormat.relativeDate($0))" } ?? "Waiting for session activity",
                            accent: NeoCodeTheme.warning
                        )
                    }

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 16) {
                            DashboardTokenBreakdownCard(snapshot: snapshot)
                            DashboardProjectsCard(projects: snapshot.projects)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)

                        VStack(alignment: .leading, spacing: 16) {
                            DashboardModelsCard(models: Array(snapshot.topModels.prefix(8)))
                            DashboardToolsCard(tools: Array(snapshot.topTools.prefix(8)))
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                } else if store.projects.isEmpty {
                    DashboardEmptyState(
                        title: "Add your first project",
                        detail: "Use the folder button in the Threads sidebar to add a workspace. NeoCode will build your dashboard from the sessions it discovers there."
                    )
                } else {
                    DashboardEmptyState(
                        title: "Preparing the dashboard",
                        detail: "NeoCode is scanning your tracked projects and building a reusable usage cache. As soon as the first summaries land, they will appear here."
                    )
                }
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
    }
}

private struct DashboardHeroCard: View {
    let snapshot: DashboardSnapshot?
    let status: DashboardRefreshStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dashboard")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(NeoCodeTheme.textPrimary)

                    Text(subtitle)
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                HStack(spacing: 10) {
                    if status.isVisible {
                        DashboardStatusPill(status: status)
                    }

                    if let snapshot {
                        DashboardPill(label: "Updated \(DashboardFormat.relativeDate(snapshot.generatedAt))")
                    }
                }
            }

            if status.isVisible {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)

                        Text(status.detail)
                            .font(.neoBody)
                            .foregroundStyle(NeoCodeTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let progress = status.progress {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .tint(NeoCodeTheme.accent)

                            HStack(spacing: 12) {
                                Text("\(DashboardFormat.count(status.processedSessions)) of \(DashboardFormat.count(status.totalSessions)) sessions summarized")

                                if let currentProjectName = status.currentProjectName {
                                    Text(currentProjectName)
                                }

                                if let currentSessionTitle = status.currentSessionTitle {
                                    Text(currentSessionTitle)
                                        .lineLimit(1)
                                }
                            }
                            .font(.neoMonoSmall)
                            .foregroundStyle(NeoCodeTheme.textMuted)
                        }
                    }
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            NeoCodeTheme.panelRaised,
                            NeoCodeTheme.panel,
                            NeoCodeTheme.panelRaised.opacity(0.96),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(NeoCodeTheme.lineStrong, lineWidth: 1)
                )
        )
    }

    private var subtitle: String {
        if let snapshot,
           snapshot.knownSessionCount > 0 {
            return "A cached view of model mix, token totals, tool usage, and project activity across your tracked OpenCode workspaces."
        }

        return "NeoCode keeps a historical usage cache so the dashboard can load instantly on future launches and only refresh the sessions that changed."
    }

    private var statusColor: Color {
        switch status.phase {
        case .idle:
            NeoCodeTheme.textMuted
        case .priming:
            NeoCodeTheme.accent
        case .refreshing:
            NeoCodeTheme.success
        case .failed:
            NeoCodeTheme.warning
        }
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.neoMeta)
                .foregroundStyle(NeoCodeTheme.textMuted)

            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(accent)

            Text(detail)
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .padding(18)
        .background(DashboardCardBackground())
    }
}

private struct DashboardTokenBreakdownCard: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        DashboardCard(title: "Token Breakdown", detail: "A quick read on where model usage is accumulating.") {
            VStack(alignment: .leading, spacing: 12) {
                DashboardTokenRow(label: "Input", value: snapshot.tokens.input, total: snapshot.tokens.total, tint: NeoCodeTheme.accent)
                DashboardTokenRow(label: "Output", value: snapshot.tokens.output, total: snapshot.tokens.total, tint: NeoCodeTheme.success)
                DashboardTokenRow(label: "Reasoning", value: snapshot.tokens.reasoning, total: snapshot.tokens.total, tint: NeoCodeTheme.warning)
                DashboardTokenRow(label: "Cache", value: snapshot.tokens.cacheRead + snapshot.tokens.cacheWrite, total: snapshot.tokens.total, tint: NeoCodeTheme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct DashboardModelsCard: View {
    let models: [DashboardModelUsageSummary]

    var body: some View {
        DashboardCard(title: "Most Used Models", detail: "Ranked by assistant message count, with token and cost totals attached.") {
            if models.isEmpty {
                DashboardInlineEmptyState(label: "No assistant usage has been cached yet.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(models) { model in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(model.displayName)
                                    .font(.neoAction)
                                    .foregroundStyle(NeoCodeTheme.textPrimary)
                                    .lineLimit(1)

                                Spacer(minLength: 12)

                                Text(DashboardFormat.count(model.messageCount))
                                    .font(.neoMonoSmall)
                                    .foregroundStyle(NeoCodeTheme.textMuted)
                            }

                            Text("\(DashboardFormat.count(model.tokens.total)) tokens - \(DashboardFormat.currency(model.totalCost))")
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.textSecondary)
                        }

                        if model.id != models.last?.id {
                            Divider()
                                .overlay(NeoCodeTheme.lineSoft)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct DashboardToolsCard: View {
    let tools: [DashboardToolUsageSummary]

    var body: some View {
        DashboardCard(title: "Tool Activity", detail: "A count of the tools that appear most often in your assistant runs.") {
            if tools.isEmpty {
                DashboardInlineEmptyState(label: "No tool activity has been cached yet.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(tools) { tool in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tool.name)
                                    .font(.neoAction)
                                    .foregroundStyle(NeoCodeTheme.textPrimary)
                                Text("Seen in \(DashboardFormat.count(tool.sessionCount)) sessions")
                                    .font(.neoMonoSmall)
                                    .foregroundStyle(NeoCodeTheme.textMuted)
                            }

                            Spacer(minLength: 12)

                            Text(DashboardFormat.count(tool.callCount))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(NeoCodeTheme.accent)
                        }

                        if tool.id != tools.last?.id {
                            Divider()
                                .overlay(NeoCodeTheme.lineSoft)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct DashboardProjectsCard: View {
    @Environment(AppStore.self) private var store

    let projects: [DashboardProjectUsageSummary]

    var body: some View {
        DashboardCard(title: "Projects", detail: "Per-project coverage and activity based on the cached session summaries.") {
            if projects.isEmpty {
                DashboardInlineEmptyState(label: "No tracked projects are ready yet.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(projects) { project in
                        Button {
                            store.selectProject(project.id)
                            store.selectDashboard()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(project.name)
                                        .font(.neoAction)
                                        .foregroundStyle(NeoCodeTheme.textPrimary)
                                        .lineLimit(1)

                                    Spacer(minLength: 12)

                                    Text("\(DashboardFormat.count(project.indexedSessionCount))/\(DashboardFormat.count(project.knownSessionCount))")
                                        .font(.neoMonoSmall)
                                        .foregroundStyle(NeoCodeTheme.textMuted)
                                }

                                Text("\(DashboardFormat.count(project.totalMessages)) messages - \(DashboardFormat.count(project.tokens.total)) tokens")
                                    .font(.neoMonoSmall)
                                    .foregroundStyle(NeoCodeTheme.textSecondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(store.selectedProjectID == project.id ? NeoCodeTheme.panelSoft : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.neoTitle)
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text(detail)
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(18)
        .background(DashboardCardBackground())
    }
}

private struct DashboardCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(NeoCodeTheme.panelRaised.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NeoCodeTheme.line, lineWidth: 1)
            )
    }
}

private struct DashboardTokenRow: View {
    let label: String
    let value: Int
    let total: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.neoAction)
                    .foregroundStyle(NeoCodeTheme.textPrimary)
                Spacer()
                Text(DashboardFormat.count(value))
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textMuted)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NeoCodeTheme.panelSoft)
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
    }

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(Double(value) / Double(total))
    }
}

private struct DashboardPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.neoMonoSmall)
            .foregroundStyle(NeoCodeTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(NeoCodeTheme.panelSoft)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(NeoCodeTheme.line, lineWidth: 1)
                    )
            )
    }
}

private struct DashboardStatusPill: View {
    let status: DashboardRefreshStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)

            if let progress = status.progress {
                Text("\(DashboardFormat.count(status.processedSessions))/\(DashboardFormat.count(status.totalSessions))")
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .frame(width: 56)
            } else {
                Text(status.title)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textPrimary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(NeoCodeTheme.panelSoft)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var tint: Color {
        switch status.phase {
        case .idle:
            NeoCodeTheme.textMuted
        case .priming:
            NeoCodeTheme.accent
        case .refreshing:
            NeoCodeTheme.success
        case .failed:
            NeoCodeTheme.warning
        }
    }
}

private struct DashboardInlineEmptyState: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.neoBody)
            .foregroundStyle(NeoCodeTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

private struct DashboardEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(NeoCodeTheme.textPrimary)

            Text(detail)
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DashboardCardBackground())
    }
}

private enum DashboardFormat {
    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func count(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000).replacingOccurrences(of: ".0", with: "")
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000).replacingOccurrences(of: ".0", with: "")
        }
        return integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func currency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func relativeDate(_ value: Date) -> String {
        relativeFormatter.localizedString(for: value, relativeTo: .now)
    }
}
