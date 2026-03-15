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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DashboardHeroCard(snapshot: store.dashboardSnapshot, status: store.dashboardStatus)

                if let snapshot = store.dashboardSnapshot,
                   snapshot.totalProjects > 0 {
                    // Stats Row - Redesigned with icons and glassmorphism
                    HStack(alignment: .top, spacing: 16) {
                        DashboardStatCard(
                            icon: "folder.fill",
                            iconColor: NeoCodeTheme.accent,
                            title: "Projects",
                            value: DashboardFormat.count(snapshot.totalProjects),
                            subtitle: "\(DashboardFormat.count(snapshot.indexedSessionCount)) of \(DashboardFormat.count(snapshot.knownSessionCount)) sessions cached",
                            gradient: [NeoCodeTheme.accent.opacity(0.15), NeoCodeTheme.accent.opacity(0.05)]
                        )
                        DashboardStatCard(
                            icon: "chart.bar.fill",
                            iconColor: NeoCodeTheme.success,
                            title: "Total Tokens",
                            value: DashboardFormat.count(snapshot.tokens.total),
                            subtitle: "Input, output, reasoning, and cache",
                            gradient: [NeoCodeTheme.success.opacity(0.15), NeoCodeTheme.success.opacity(0.05)]
                        )
                        DashboardStatCard(
                            icon: "message.fill",
                            iconColor: Color(red: 0.55, green: 0.65, blue: 0.85),
                            title: "Messages",
                            value: DashboardFormat.count(snapshot.totalMessages),
                            subtitle: "\(DashboardFormat.count(snapshot.userMessages)) user, \(DashboardFormat.count(snapshot.assistantMessages)) assistant",
                            gradient: [Color(red: 0.55, green: 0.65, blue: 0.85).opacity(0.15), Color(red: 0.55, green: 0.65, blue: 0.85).opacity(0.05)]
                        )
                        DashboardStatCard(
                            icon: "dollarsign.circle.fill",
                            iconColor: NeoCodeTheme.warning,
                            title: "Cost",
                            value: DashboardFormat.currency(snapshot.totalCost),
                            subtitle: snapshot.latestActivityAt.map { "Last activity \(DashboardFormat.relativeDate($0))" } ?? "Waiting for activity",
                            gradient: [NeoCodeTheme.warning.opacity(0.15), NeoCodeTheme.warning.opacity(0.05)]
                        )
                    }

                    // Main Content Grid
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
        .background(NeoCodeTheme.canvas)
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
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String
    let gradient: [Color]
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 36, height: 36)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(gradient[0])
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(iconColor.opacity(0.3), lineWidth: 1)
                        }
                    )
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(NeoCodeTheme.textPrimary)
                
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor.opacity(0.8))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            
            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(NeoCodeTheme.textMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                
                // Gradient overlay
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(
            color: isHovered ? iconColor.opacity(0.1) : Color.black.opacity(0.1),
            radius: isHovered ? 12 : 8,
            x: 0,
            y: isHovered ? 4 : 2
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
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
            VStack(alignment: .leading, spacing: 16) {
                DashboardTokenRow(
                    label: "Input",
                    value: snapshot.tokens.input,
                    total: snapshot.tokens.total,
                    icon: "arrow.down.circle.fill",
                    gradient: [NeoCodeTheme.accent, NeoCodeTheme.warning]
                )
                DashboardTokenRow(
                    label: "Output",
                    value: snapshot.tokens.output,
                    total: snapshot.tokens.total,
                    icon: "arrow.up.circle.fill",
                    gradient: [NeoCodeTheme.success, Color(red: 0.35, green: 0.85, blue: 0.65)]
                )
                DashboardTokenRow(
                    label: "Reasoning",
                    value: snapshot.tokens.reasoning,
                    total: snapshot.tokens.total,
                    icon: "brain.head.profile.fill",
                    gradient: [NeoCodeTheme.warning, Color(red: 0.95, green: 0.65, blue: 0.35)]
                )
                DashboardTokenRow(
                    label: "Cache",
                    value: snapshot.tokens.cacheRead + snapshot.tokens.cacheWrite,
                    total: snapshot.tokens.total,
                    icon: "externaldrive.fill.badge.icloud",
                    gradient: [Color(red: 0.55, green: 0.65, blue: 0.85), Color(red: 0.75, green: 0.85, blue: 0.95)]
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
    let icon: String
    let gradient: [Color]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(gradient[0])
                
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NeoCodeTheme.textPrimary)
                
                Spacer()
                
                Text(DashboardFormat.count(value))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(NeoCodeTheme.panelSoft)
                    
                    // Progress fill with gradient
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geometry.size.width * fraction, 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
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
                    
                    // Shine effect
                    if fraction > 0.1 {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geometry.size.width * fraction, 4))
                            .mask(
                                LinearGradient(
                                    colors: [Color.white, Color.clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
            }
            .frame(height: 10)
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
                        
                        if index < models.count - 1 {
                            Divider()
                                .background(NeoCodeTheme.line)
                                .padding(.vertical, 8)
                        }
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
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            Text("\(rank)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(rank <= 3 ? NeoCodeTheme.accent : NeoCodeTheme.textMuted)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(rank <= 3 ? NeoCodeTheme.accent.opacity(0.15) : NeoCodeTheme.panelSoft)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NeoCodeTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Label {
                        Text("\(DashboardFormat.count(model.tokens.total)) tokens")
                            .foregroundStyle(NeoCodeTheme.textMuted)
                    } icon: {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 9))
                    }
                    
                    Text("•")
                        .foregroundStyle(NeoCodeTheme.textMuted)
                    
                    Label {
                        Text(DashboardFormat.currency(model.totalCost))
                            .foregroundStyle(NeoCodeTheme.textMuted)
                    } icon: {
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: 9))
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
            }

            Spacer(minLength: 8)

            // Message count badge
            HStack(spacing: 4) {
                Image(systemName: "message.fill")
                    .font(.system(size: 10))
                Text(DashboardFormat.count(model.messageCount))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(NeoCodeTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(NeoCodeTheme.accent.opacity(0.15))
            )
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? NeoCodeTheme.panelSoft : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
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
                        
                        if index < tools.count - 1 {
                            Divider()
                                .background(NeoCodeTheme.line)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct DashboardToolRow: View {
    let tool: DashboardToolUsageSummary
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Tool icon placeholder
            Image(systemName: toolIcon(for: tool.name))
                .font(.system(size: 14))
                .foregroundStyle(NeoCodeTheme.success)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(NeoCodeTheme.success.opacity(0.15))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NeoCodeTheme.textPrimary)
                
                Text("Seen in \(DashboardFormat.count(tool.sessionCount)) sessions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NeoCodeTheme.textMuted)
            }

            Spacer(minLength: 8)

            // Call count with visual emphasis
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                Text(DashboardFormat.count(tool.callCount))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(NeoCodeTheme.success)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? NeoCodeTheme.panelSoft : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func toolIcon(for name: String) -> String {
        switch name.lowercased() {
        case let s where s.contains("read"): "doc.text.fill"
        case let s where s.contains("write"): "doc.badge.plus"
        case let s where s.contains("bash"), let s where s.contains("shell"), let s where s.contains("exec"): "terminal.fill"
        case let s where s.contains("git"): "arrow.triangle.branch"
        case let s where s.contains("search"): "magnifyingglass"
        case let s where s.contains("fetch"): "network"
        case let s where s.contains("edit"): "pencil"
        default: "wrench.fill"
        }
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
    @State private var isHovered = false

    var body: some View {
        Button {
            store.selectProject(project.id)
            store.selectDashboard()
        } label: {
            HStack(spacing: 14) {
                // Project icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? NeoCodeTheme.accent.opacity(0.2) : NeoCodeTheme.panelSoft)
                    
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? NeoCodeTheme.accent : NeoCodeTheme.textMuted)
                }
                .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(project.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? NeoCodeTheme.accent : NeoCodeTheme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        // Session coverage indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(coverageColor)
                                .frame(width: 6, height: 6)
                            Text("\(DashboardFormat.count(project.indexedSessionCount))/\(DashboardFormat.count(project.knownSessionCount))")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(NeoCodeTheme.textMuted)
                    }

                    HStack(spacing: 12) {
                        Label {
                            Text("\(DashboardFormat.count(project.totalMessages)) messages")
                                .foregroundStyle(NeoCodeTheme.textMuted)
                        } icon: {
                            Image(systemName: "message")
                                .font(.system(size: 9))
                        }
                        
                        Text("•")
                            .foregroundStyle(NeoCodeTheme.textMuted)
                        
                        Label {
                            Text("\(DashboardFormat.count(project.tokens.total)) tokens")
                                .foregroundStyle(NeoCodeTheme.textMuted)
                        } icon: {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 9))
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? NeoCodeTheme.accent.opacity(0.1) : Color.clear)
                    
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isSelected ? NeoCodeTheme.accent.opacity(0.4) : Color.clear,
                            lineWidth: 1
                        )
                }
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var coverageColor: Color {
        let ratio = Double(project.indexedSessionCount) / Double(max(project.knownSessionCount, 1))
        if ratio >= 1.0 {
            return NeoCodeTheme.success
        } else if ratio >= 0.5 {
            return NeoCodeTheme.warning
        } else {
            return NeoCodeTheme.textMuted
        }
    }
}

// MARK: - Glass Card Container

private struct DashboardGlassCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            content
        }
        .padding(20)
        .background(
            ZStack {
                // Base
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                
                // Border with gradient
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(
            color: Color.black.opacity(0.15),
            radius: isHovered ? 16 : 12,
            x: 0,
            y: isHovered ? 6 : 4
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Pills

private struct DashboardTimePill: View {
    let date: Date
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 10, weight: .medium))
            Text("Updated \(DashboardFormat.relativeDate(date))")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(NeoCodeTheme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            ZStack {
                Capsule(style: .continuous)
                    .fill(NeoCodeTheme.panelSoft)
                Capsule(style: .continuous)
                    .stroke(NeoCodeTheme.line, lineWidth: 1)
            }
        )
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct DashboardStatusPill: View {
    let status: DashboardRefreshStatus

    var body: some View {
        HStack(spacing: 8) {
            StatusIndicator(color: tint, isAnimating: status.phase == .refreshing)

            if let progress = status.progress {
                Text("\(DashboardFormat.count(status.processedSessions))/\(DashboardFormat.count(status.totalSessions))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(NeoCodeTheme.panelSoft)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tint)
                            .frame(width: geometry.size.width * CGFloat(progress))
                    }
                }
                .frame(width: 50, height: 6)
            } else {
                Text(status.title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NeoCodeTheme.textPrimary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            ZStack {
                Capsule(style: .continuous)
                    .fill(NeoCodeTheme.panelSoft)
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.4), lineWidth: 1)
            }
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

// MARK: - Empty States

private struct DashboardInlineEmptyState: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(NeoCodeTheme.textMuted)
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(NeoCodeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }
}

private struct DashboardEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [NeoCodeTheme.accent, NeoCodeTheme.warning],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [NeoCodeTheme.panelRaised, NeoCodeTheme.panel],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
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
