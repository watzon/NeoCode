import AppKit
import SwiftUI

struct SessionHeaderView: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime
    @Environment(\.locale) private var locale
    @State private var isRenaming = false
    @State private var isCommitSheetPresented = false
    @State private var renameTitle = ""
    @State private var workspaceTools: [WorkspaceTool] = []
    @State private var openMenu: HeaderMenu?

    private let workspaceToolService = WorkspaceToolService()

    let session: SessionSummary

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 8) {
                Text(session.title)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                sessionMenuButton
            }

            Spacer(minLength: 24)

            HStack(spacing: 10) {
                if let selectedWorkspaceTool {
                    WorkspaceToolSplitButton(
                        tool: selectedWorkspaceTool,
                        allTools: workspaceTools,
                        service: workspaceToolService,
                        projectPath: projectPath,
                        isMenuOpen: openMenu == .workspaceTools,
                        onToggleMenu: {
                            openMenu = openMenu == .workspaceTools ? nil : .workspaceTools
                        },
                        onDismissMenu: {
                            if openMenu == .workspaceTools {
                                openMenu = nil
                            }
                        },
                        onSelectTool: selectWorkspaceTool
                    )
                }

                if store.gitStatus.isRepository {
                    GitActionsSplitButton(
                        gitStatus: store.gitStatus,
                        commitPreview: store.gitCommitPreview,
                        operationState: store.currentGitOperationState,
                        isBusy: store.isPerformingGitOperation,
                        isMenuOpen: openMenu == .gitActions,
                        onPrimaryAction: handlePrimaryGitAction,
                        onCommit: {
                            isCommitSheetPresented = true
                        },
                        onPush: {
                            Task {
                                _ = await store.pushChanges()
                            }
                        },
                        onToggleMenu: {
                            openMenu = openMenu == .gitActions ? nil : .gitActions
                        },
                        onDismissMenu: {
                            if openMenu == .gitActions {
                                openMenu = nil
                            }
                        }
                    )
                }

                Rectangle()
                    .fill(NeoCodeTheme.line)
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, 2)

                SessionStatsMenuButton(
                    stats: store.sessionStats(for: session.id),
                    isMenuOpen: openMenu == .sessionStats,
                    onToggleMenu: {
                        openMenu = openMenu == .sessionStats ? nil : .sessionStats
                    },
                    onDismissMenu: {
                        if openMenu == .sessionStats {
                            openMenu = nil
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(WindowDragRegion())
        .task(id: projectPath) {
            await refreshHeaderState()
        }
        .sheet(isPresented: $isCommitSheetPresented) {
            GitCommitSheet(isPresented: $isCommitSheetPresented)
                .environment(store)
                .environment(runtime)
        }
        .alert(localized("Rename Thread", locale: locale), isPresented: $isRenaming) {
            TextField(localized("Thread name", locale: locale), text: $renameTitle)
                .neoWritingToolsDisabled()
            Button(localized("Cancel", locale: locale), role: .cancel) {
                renameTitle = session.title
            }
            Button(localized("Save", locale: locale)) {
                let newTitle = renameTitle
                Task {
                    await store.renameSession(session.id, to: newTitle, using: runtime)
                }
            }
        } message: {
            Text(localized("Give this thread a new name.", locale: locale))
        }
    }

    private enum HeaderMenu {
        case workspaceTools
        case gitActions
        case sessionStats
    }

    private var sessionMenuButton: some View {
        Menu {
            SessionActionMenuContent(
                canCompact: store.canCompactSession(session.id),
                onCompact: {
                    Task {
                        _ = await store.compactSession(session.id, using: runtime)
                    }
                },
                onRename: {
                    renameTitle = session.title
                    isRenaming = true
                },
                onDelete: {
                    Task {
                        await store.deleteSession(session.id, using: runtime)
                    }
                }
            )
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NeoCodeTheme.textMuted)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var projectPath: String {
        store.project(for: session.id)?.path ?? store.selectedProject?.path ?? ""
    }

    private var projectID: ProjectSummary.ID? {
        store.project(for: session.id)?.id ?? store.selectedProject?.id
    }

    private var selectedWorkspaceTool: WorkspaceTool? {
        guard !workspaceTools.isEmpty else { return nil }

        if let resolvedToolID = store.preferredWorkspaceToolID(
            for: projectID,
            availableToolIDs: workspaceTools.map(\.id)
        ),
           let tool = workspaceTools.first(where: { $0.id == resolvedToolID }) {
            return tool
        }

        if let tool = workspaceToolService.defaultProjectOpenTool(from: workspaceTools) {
            return tool
        }

        return workspaceTools.first
    }

    private func refreshHeaderState() async {
        guard !projectPath.isEmpty else {
            workspaceTools = []
            return
        }

        workspaceTools = workspaceToolService.projectOpenTools()
        await store.refreshGitCommitPreview(showLoadingIndicator: false, projectPathOverride: projectPath)
    }

    private func selectWorkspaceTool(_ tool: WorkspaceTool) {
        guard let projectID else { return }
        store.setPreferredEditorID(tool.id, for: projectID)
        workspaceToolService.openProject(at: projectPath, with: tool)
    }

    private func handlePrimaryGitAction() {
        switch store.gitStatus.primaryAction {
        case .commit:
            isCommitSheetPresented = true
        case .push:
            Task {
                _ = await store.pushChanges()
            }
        }
    }
}

struct SessionActionMenuContent: View {
    @Environment(\.locale) private var locale
    let canCompact: Bool
    let onCompact: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(localized("Rename", locale: locale), action: onRename)
        Button(localized("Compact", locale: locale), action: onCompact)
            .disabled(!canCompact)
        Divider()
        Button(localized("Delete", locale: locale), role: .destructive, action: onDelete)
    }
}

private struct WorkspaceToolSplitButton: View {
    let tool: WorkspaceTool
    let allTools: [WorkspaceTool]
    let service: WorkspaceToolService
    let projectPath: String
    let isMenuOpen: Bool
    let onToggleMenu: () -> Void
    let onDismissMenu: () -> Void
    let onSelectTool: (WorkspaceTool) -> Void

    var body: some View {
        HeaderSplitControl(
            systemImage: nil,
            icon: {
                WorkspaceToolIconView(tool: tool)
            },
            label: {
                Text(tool.label)
            },
            primaryAction: {
                service.openProject(at: projectPath, with: tool)
            },
            isPrimaryDisabled: false,
            isMenuOpen: isMenuOpen,
            onToggleMenu: onToggleMenu,
            onDismissMenu: onDismissMenu,
            menuContent: { dismiss in
                DropdownMenuSurface(width: 176) {
                    ForEach(allTools) { candidate in
                        let available = service.isAvailable(candidate)
                        DropdownMenuRow(isSelected: candidate.id == tool.id, isDisabled: !available, action: {
                            onSelectTool(candidate)
                            dismiss()
                        }) {
                            HStack(spacing: 10) {
                                WorkspaceToolIconView(tool: candidate)
                                    .frame(width: 16, height: 16)

                                Text(candidate.label)
                                    .font(.neoAction)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        )
    }
}

private struct GitActionsSplitButton: View {
    @Environment(\.locale) private var locale
    let gitStatus: GitRepositoryStatus
    let commitPreview: GitCommitPreview?
    let operationState: AppStore.GitOperationState?
    let isBusy: Bool
    let isMenuOpen: Bool
    let onPrimaryAction: () -> Void
    let onCommit: () -> Void
    let onPush: () -> Void
    let onToggleMenu: () -> Void
    let onDismissMenu: () -> Void

    var body: some View {
        HeaderSplitControl(
            systemImage: gitStatus.primaryAction.systemImage,
            icon: { EmptyView() },
            label: {
                HStack(spacing: 6) {
                    Text(operationState.map { "\(localized($0.title, locale: locale))..." } ?? localized(gitStatus.primaryAction.title, locale: locale))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if shouldShowCommitStats, let commitPreview {
                        CommitStatInlineView(
                            additions: commitPreview.totalAdditions,
                            deletions: commitPreview.totalDeletions
                        )
                    }
                }
            },
            primaryAction: onPrimaryAction,
            isPrimaryDisabled: isBusy || !gitStatus.isPrimaryActionEnabled,
            isMenuOpen: isMenuOpen,
            onToggleMenu: onToggleMenu,
            onDismissMenu: onDismissMenu,
            menuContent: { dismiss in
                DropdownMenuSurface(width: 148) {
                    DropdownMenuRow(isDisabled: isBusy || !gitStatus.hasChanges, action: {
                        onCommit()
                        dismiss()
                    }) {
                        Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 16, height: 16)

                        Text(localized("Commit", locale: locale))
                            .font(.neoAction)
                            .lineLimit(1)
                    }
                    DropdownMenuRow(isDisabled: isBusy || gitStatus.aheadCount == 0, action: {
                        onPush()
                        dismiss()
                    }) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 16, height: 16)

                        Text(localized("Push", locale: locale))
                            .font(.neoAction)
                            .lineLimit(1)
                    }
                    DropdownMenuRow(isDisabled: true, action: dismiss) {
                        Image(systemName: "arrow.triangle.pull")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 16, height: 16)

                        Text(localized("Create PR", locale: locale))
                            .font(.neoAction)
                            .lineLimit(1)
                    }
                }
            }
        )
    }

    private var shouldShowCommitStats: Bool {
        operationState == nil && gitStatus.primaryAction == .commit && gitStatus.hasChanges
    }
}

private struct CommitStatInlineView: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 4) {
            if additions > 0 {
                Text("+\(additions)")
                    .foregroundStyle(Color(red: 0.48, green: 0.94, blue: 0.56))
            }

            if deletions > 0 {
                Text("-\(deletions)")
                    .foregroundStyle(Color(red: 0.96, green: 0.52, blue: 0.43))
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
    }
}

private struct SessionStatsMenuButton: View {
    @Environment(\.locale) private var locale
    let stats: SessionStatsSnapshot?
    let isMenuOpen: Bool
    let onToggleMenu: () -> Void
    let onDismissMenu: () -> Void

    private let controlSize: CGFloat = 32
    private let visualSize: CGFloat = 28
    private let ringLineWidth: CGFloat = 3

    var body: some View {
        Button(action: onToggleMenu) {
            ZStack {
                Circle()
                    .stroke(baseRingColor, style: StrokeStyle(lineWidth: ringLineWidth))

                if let progress = ringProgress {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                } else {
                    Circle()
                        .stroke(NeoCodeTheme.textMuted, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round, dash: [2.5, 3.5]))
                        .opacity(0.6)
                }

                Circle()
                    .fill(centerDotColor)
                    .frame(width: 6, height: 6)
            }
            .frame(width: visualSize, height: visualSize)
            .background(
                Circle()
                    .fill(isMenuOpen ? NeoCodeTheme.panelSoft : NeoCodeTheme.panelRaised)
                    .overlay(
                        Circle()
                            .stroke(isMenuOpen ? NeoCodeTheme.lineStrong : NeoCodeTheme.line, lineWidth: 1)
                    )
            )
            .frame(width: controlSize, height: controlSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .neoTooltip(helpText)
        .accessibilityLabel(localized("Session stats", locale: locale))
        .accessibilityValue(accessibilityValue)
        .background {
            AnchoredFloatingPanelPresenter(isPresented: isMenuOpen, direction: .down, onDismiss: onDismissMenu) {
                SessionStatsDropdown(stats: stats)
            }
        }
        .zIndex(isMenuOpen ? 10 : 0)
    }

    private var ringProgress: CGFloat? {
        guard let remaining = stats?.remainingContextFraction else { return nil }
        if remaining <= 0 { return 0.001 }
        return CGFloat(remaining)
    }

    private var ringColor: Color {
        guard let remaining = stats?.remainingContextFraction else { return NeoCodeTheme.textMuted }
        switch remaining {
        case 0.5...:
            return NeoCodeTheme.success
        case 0.2...:
            return NeoCodeTheme.accent
        default:
            return NeoCodeTheme.warning
        }
    }

    private var baseRingColor: Color {
        isMenuOpen ? NeoCodeTheme.lineStrong : NeoCodeTheme.line
    }

    private var centerDotColor: Color {
        stats == nil ? NeoCodeTheme.textMuted : ringColor
    }

    private var helpText: String {
        guard let stats else { return localized("Session stats unavailable", locale: locale) }
        if let remaining = stats.percentRemaining {
            return String(format: localized("%lld%% context remaining", locale: locale), remaining)
        }
        return localized("Session stats", locale: locale)
    }

    private var accessibilityValue: String {
        guard let stats else { return localized("Unavailable", locale: locale) }
        if let remaining = stats.percentRemaining {
            return String(format: localized("%lld percent context remaining", locale: locale), remaining)
        }
        return localized("Context limit unavailable", locale: locale)
    }
}

private struct SessionStatsDropdown: View {
    @Environment(\.locale) private var locale
    let stats: SessionStatsSnapshot?

    var body: some View {
        DropdownMenuSurface(width: 260) {
            VStack(alignment: .leading, spacing: 12) {
                if let stats {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("Session Stats", locale: locale))
                            .font(.neoAction)
                            .foregroundStyle(NeoCodeTheme.textPrimary)

                        Text(contextSummary(for: stats))
                            .font(.neoMonoSmall)
                            .foregroundStyle(NeoCodeTheme.textSecondary)
                    }

                    statRow(localized("Context used", locale: locale), value: count(stats.contextUsedTokens))
                    statRow(localized("Context limit", locale: locale), value: optionalCount(stats.contextWindow))
                    statRow(localized("Context remaining", locale: locale), value: optionalCount(stats.remainingContextTokens))
                    statRow(localized("Usage", locale: locale), value: optionalPercent(stats.percentUsed))
                    statRow(localized(stats.isProjectedAfterCompaction ? "Last request" : "Total tokens", locale: locale), value: count(stats.totalContextTokens))
                    statRow(localized("Input", locale: locale), value: count(stats.inputTokens))
                    statRow(localized("Output", locale: locale), value: count(stats.outputTokens))
                    statRow(localized("Reasoning", locale: locale), value: count(stats.reasoningTokens))
                    statRow(localized("Cache", locale: locale), value: "\(count(stats.cacheReadTokens)) / \(count(stats.cacheWriteTokens))")
                    statRow(localized("Cost", locale: locale), value: currency(stats.totalCost))
                    statRow(localized("Provider", locale: locale), value: stats.providerID ?? "-")
                    statRow(localized("Model", locale: locale), value: stats.modelDisplayName)
                    statRow(localized("Last activity", locale: locale), value: time(stats.lastActivityAt))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("Session Stats", locale: locale))
                            .font(.neoAction)
                            .foregroundStyle(NeoCodeTheme.textPrimary)

                        Text(localized("Stats will appear after the session records assistant usage.", locale: locale))
                            .font(.neoBody)
                            .foregroundStyle(NeoCodeTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private func statRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.neoMeta)
                .foregroundStyle(NeoCodeTheme.textSecondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func contextSummary(for stats: SessionStatsSnapshot) -> String {
        let remaining = optionalCount(stats.remainingContextTokens)
        let usage = optionalPercent(stats.percentUsed)
        if stats.isProjectedAfterCompaction {
            return String(format: localized("%@ remaining - %@ used - projected after compaction", locale: locale), remaining, usage)
        }

        return String(format: localized("%@ remaining - %@ used", locale: locale), remaining, usage)
    }

    private func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private func optionalCount(_ value: Int?) -> String {
        guard let value else { return "-" }
        return count(value)
    }

    private func optionalPercent(_ value: Int?) -> String {
        guard let value else { return "-" }
        return "\(value)%"
    }

    private func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(locale))
    }

    private func time(_ value: Date?) -> String {
        guard let value else { return "-" }
        return value.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }
}

private struct HeaderSplitControl<Icon: View, Label: View, MenuContent: View>: View {
    let systemImage: String?
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let label: () -> Label
    let primaryAction: () -> Void
    let isPrimaryDisabled: Bool
    let isMenuOpen: Bool
    let onToggleMenu: () -> Void
    let onDismissMenu: () -> Void
    let menuContent: (@escaping () -> Void) -> MenuContent

    var body: some View {
        HStack(spacing: 0) {
            Button(action: primaryAction) {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(primaryForegroundColor)
                    }

                    icon()

                    label()
                        .font(.neoAction)
                        .foregroundStyle(primaryForegroundColor)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isPrimaryDisabled)

            Rectangle()
                .fill(NeoCodeTheme.line)
                .frame(width: 1, height: 16)

            Button(action: onToggleMenu) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .frame(width: 28, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background {
            AnchoredFloatingPanelPresenter(isPresented: isMenuOpen, direction: .down, onDismiss: onDismissMenu, content: {
                menuContent(onToggleMenu)
            })
        }
        .zIndex(isMenuOpen ? 10 : 0)
    }

    private var primaryForegroundColor: Color {
        isPrimaryDisabled ? NeoCodeTheme.textMuted : NeoCodeTheme.textPrimary
    }
}
