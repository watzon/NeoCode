import AppKit
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
        VStack(spacing: 0) {
            DashboardHeader(snapshot: store.dashboardSnapshot, status: store.dashboardStatus)
                .zIndex(50)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let snapshot = store.dashboardSnapshot,
                       snapshot.totalProjects > 0 {
                        Text("Welcome to NeoCode!")
                            .font(.system(size: 28, weight: .bold, design: .default))
                            .foregroundStyle(NeoCodeTheme.textPrimary)

                        HStack(alignment: .top, spacing: 12) {
                            DashboardStatCard(
                                title: "Projects",
                                value: DashboardFormat.count(snapshot.totalProjects),
                                subtitle: "\(DashboardFormat.count(snapshot.indexedSessionCount)) of \(DashboardFormat.count(snapshot.knownSessionCount)) cached"
                            )
                            DashboardStatCard(
                                title: "Tokens",
                                value: DashboardFormat.count(snapshot.tokens.total),
                                subtitle: "Total usage"
                            )
                            DashboardStatCard(
                                title: "Messages",
                                value: DashboardFormat.count(snapshot.totalMessages),
                                subtitle: "\(DashboardFormat.count(snapshot.userMessages)) user · \(DashboardFormat.count(snapshot.assistantMessages)) assistant"
                            )
                            DashboardStatCard(
                                title: "Cost",
                                value: DashboardFormat.currency(snapshot.totalCost),
                                subtitle: snapshot.latestActivityAt.map { "Last activity \(DashboardFormat.relativeDate($0))" } ?? "No activity"
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
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
        }
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(NeoCodeTheme.panel)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .stroke(NeoCodeTheme.line, lineWidth: 1)
            )
        )
    }
}

// MARK: - Header Section

private struct DashboardHeader: View {
    let snapshot: DashboardSnapshot?
    let status: DashboardRefreshStatus

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Dashboard")
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundStyle(NeoCodeTheme.textPrimary)

            Spacer(minLength: 24)

            HStack(spacing: 12) {
                if status.isVisible {
                    DashboardStatusPill(status: status)
                }

                if let snapshot {
                    DashboardTimePill(date: snapshot.generatedAt)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(WindowDragRegion())
    }
}

// MARK: - Hero Section

private struct DashboardHeroCard: View {
    let snapshot: DashboardSnapshot?
    let status: DashboardRefreshStatus
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [NeoCodeTheme.accent, NeoCodeTheme.warning],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Dashboard")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(NeoCodeTheme.textPrimary)
                    }

                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(NeoCodeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }

                Spacer(minLength: 16)

                HStack(spacing: 12) {
                    if status.isVisible {
                        DashboardStatusPill(status: status)
                    }

                    if let snapshot {
                        DashboardTimePill(date: snapshot.generatedAt)
                    }
                }
            }

            if status.isVisible {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        StatusIndicator(color: statusColor, isAnimating: status.phase == .refreshing)

                        Text(status.detail)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NeoCodeTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let progress = status.progress {
                        VStack(alignment: .leading, spacing: 10) {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(NeoCodeTheme.panelSoft)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            LinearGradient(
                                                colors: [NeoCodeTheme.accent, NeoCodeTheme.warning],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geometry.size.width * CGFloat(progress))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0.3),
                                                            Color.white.opacity(0)
                                                        ],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                        )
                                }
                            }
                            .frame(height: 8)

                            HStack(spacing: 16) {
                                Label {
                                    Text("\(DashboardFormat.count(status.processedSessions)) of \(DashboardFormat.count(status.totalSessions)) sessions")
                                        .foregroundStyle(NeoCodeTheme.textMuted)
                                } icon: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(NeoCodeTheme.success)
                                }

                                if let currentProjectName = status.currentProjectName {
                                    Label {
                                        Text(currentProjectName)
                                            .foregroundStyle(NeoCodeTheme.textMuted)
                                    } icon: {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(NeoCodeTheme.accent)
                                    }
                                }

                                if let currentSessionTitle = status.currentSessionTitle {
                                    Label {
                                        Text(currentSessionTitle)
                                            .lineLimit(1)
                                            .foregroundStyle(NeoCodeTheme.textMuted)
                                    } icon: {
                                        Image(systemName: "bubble.left.fill")
                                            .foregroundStyle(Color(red: 0.55, green: 0.65, blue: 0.85))
                                    }
                                }
                            }
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
        .background(
            ZStack {
                // Base gradient
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                NeoCodeTheme.panelRaised,
                                NeoCodeTheme.panel
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Subtle glow effect
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                NeoCodeTheme.accent.opacity(0.3),
                                NeoCodeTheme.accent.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
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

// MARK: - Status Indicator

private struct StatusIndicator: View {
    let color: Color
    let isAnimating: Bool
    @State private var scale = 1.0

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0.3)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 6
                )
            )
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
            )
            .scaleEffect(scale)
            .onAppear {
                if isAnimating {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        scale = 1.2
                    }
                }
            }
    }
}

// MARK: - Stat Cards

private struct DashboardStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .default))
                .foregroundStyle(NeoCodeTheme.textPrimary)
            
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NeoCodeTheme.textSecondary)
            
            Text(subtitle)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(NeoCodeTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Token Breakdown Card

private struct DashboardTokenBreakdownCard: View {
    let snapshot: DashboardSnapshot

    var body: some View {
        DashboardGlassCard(title: "Token Breakdown", subtitle: "Model usage distribution across categories") {
            VStack(alignment: .leading, spacing: 12) {
                DashboardTokenRow(
                    label: "Input",
                    value: snapshot.tokens.input,
                    total: snapshot.tokens.total
                )
                DashboardTokenRow(
                    label: "Output",
                    value: snapshot.tokens.output,
                    total: snapshot.tokens.total
                )
                DashboardTokenRow(
                    label: "Reasoning",
                    value: snapshot.tokens.reasoning,
                    total: snapshot.tokens.total
                )
                DashboardTokenRow(
                    label: "Cache",
                    value: snapshot.tokens.cacheRead + snapshot.tokens.cacheWrite,
                    total: snapshot.tokens.total
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Token Row

private struct DashboardTokenRow: View {
    let label: String
    let value: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                
                Spacer()
                
                Text(DashboardFormat.count(value))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(NeoCodeTheme.textPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(NeoCodeTheme.panelSoft)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(NeoCodeTheme.accent.opacity(0.7))
                        .frame(width: max(geometry.size.width * fraction, 2))
                }
            }
            .frame(height: 6)
        }
    }

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(Double(value) / Double(total))
    }
}

// MARK: - Models Card

private struct DashboardModelsCard: View {
    let models: [DashboardModelUsageSummary]

    var body: some View {
        DashboardGlassCard(title: "Most Used Models", subtitle: "Ranked by assistant message count") {
            if models.isEmpty {
                DashboardInlineEmptyState(label: "No assistant usage has been cached yet.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                        DashboardModelRow(model: model, rank: index + 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct DashboardModelRow: View {
    let model: DashboardModelUsageSummary
    let rank: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(rank <= 3 ? NeoCodeTheme.accent : NeoCodeTheme.textMuted)
                .frame(width: 20, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeoCodeTheme.textPrimary)
                    .lineLimit(1)

                Text("\(DashboardFormat.count(model.tokens.total)) tokens · \(DashboardFormat.currency(model.totalCost))")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(NeoCodeTheme.textMuted)
            }

            Spacer(minLength: 8)

            Text(DashboardFormat.count(model.messageCount))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(NeoCodeTheme.accent)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Tools Card

private struct DashboardToolsCard: View {
    let tools: [DashboardToolUsageSummary]

    var body: some View {
        DashboardGlassCard(title: "Tool Activity", subtitle: "Most frequently used tools") {
            if tools.isEmpty {
                DashboardInlineEmptyState(label: "No tool activity has been cached yet.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                        DashboardToolRow(tool: tool)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct DashboardToolRow: View {
    let tool: DashboardToolUsageSummary

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text("\(DashboardFormat.count(tool.sessionCount)) sessions")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(NeoCodeTheme.textMuted)
            }

            Spacer(minLength: 8)

            Text(DashboardFormat.count(tool.callCount))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(NeoCodeTheme.textSecondary)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Projects Card

private struct DashboardProjectsCard: View {
    @Environment(AppStore.self) private var store

    let projects: [DashboardProjectUsageSummary]

    var body: some View {
        DashboardGlassCard(title: "Projects", subtitle: "Per-project activity summary") {
            if projects.isEmpty {
                DashboardInlineEmptyState(label: "No tracked projects are ready yet.")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(projects) { project in
                        DashboardProjectRow(project: project, isSelected: store.selectedProjectID == project.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct DashboardProjectRow: View {
    @Environment(AppStore.self) private var store
    
    let project: DashboardProjectUsageSummary
    let isSelected: Bool

    var body: some View {
        Button {
            store.selectProject(project.id)
            store.selectDashboard()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelected ? NeoCodeTheme.accent : NeoCodeTheme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        Text("\(DashboardFormat.count(project.indexedSessionCount))/\(DashboardFormat.count(project.knownSessionCount))")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(NeoCodeTheme.textMuted)
                    }

                    Text("\(DashboardFormat.count(project.totalMessages)) messages · \(DashboardFormat.count(project.tokens.total)) tokens")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(NeoCodeTheme.textMuted)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glass Card Container

private struct DashboardGlassCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
            }

            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }
}

// MARK: - Pills

private struct DashboardTimePill: View {
    let date: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 9))
            Text("Updated \(DashboardFormat.relativeDate(date))")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
        }
        .foregroundStyle(NeoCodeTheme.textMuted)
    }
}

private struct DashboardStatusPill: View {
    let status: DashboardRefreshStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.phase == .refreshing ? NeoCodeTheme.accent : NeoCodeTheme.textMuted)
                .frame(width: 6, height: 6)

            if let progress = status.progress {
                Text("\(DashboardFormat.count(status.processedSessions))/\(DashboardFormat.count(status.totalSessions))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
            } else {
                Text(status.title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
            }
        }
    }
}

// MARK: - Empty States

private struct DashboardInlineEmptyState: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(NeoCodeTheme.textMuted)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(NeoCodeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

private struct DashboardEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }
}

// MARK: - Formatters

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
