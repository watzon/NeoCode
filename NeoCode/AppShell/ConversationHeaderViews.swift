import AppKit
import SwiftUI

struct SessionHeaderView: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime
    @State private var isRenaming = false
    @State private var isCommitSheetPresented = false
    @State private var renameTitle = ""
    @State private var workspaceTools: [WorkspaceTool] = []
    @State private var openMenu: HeaderMenu?

    private let workspaceToolService = WorkspaceToolService()

    let session: SessionSummary

    var body: some View {
        ZStack(alignment: .topLeading) {
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
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .task(id: projectPath) {
            await refreshHeaderState()
        }
        .sheet(isPresented: $isCommitSheetPresented) {
            GitCommitSheet(isPresented: $isCommitSheetPresented)
                .environment(store)
                .environment(runtime)
        }
        .alert("Rename Thread", isPresented: $isRenaming) {
            TextField("Thread name", text: $renameTitle)
            Button("Cancel", role: .cancel) {
                renameTitle = session.title
            }
            Button("Save") {
                let newTitle = renameTitle
                Task {
                    await store.renameSession(session.id, to: newTitle, using: runtime)
                }
            }
        } message: {
            Text("Give this thread a new name.")
        }
    }

    private enum HeaderMenu {
        case workspaceTools
        case gitActions
    }

    private var sessionMenuButton: some View {
        Menu {
            SessionActionMenuContent(
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

        if let projectID,
           let preferredEditorID = store.preferredEditorID(for: projectID),
           let tool = workspaceTools.first(where: { $0.id == preferredEditorID }) {
            return tool
        }

        return workspaceTools.first
    }

    private func refreshHeaderState() async {
        guard !projectPath.isEmpty else {
            workspaceTools = []
            return
        }

        let discoveredTools = workspaceToolService.discoveredTools()
        workspaceTools = discoveredTools

        if let projectID,
           let defaultToolID = workspaceToolService.defaultToolID(from: discoveredTools),
           store.preferredEditorID(for: projectID) == nil,
           discoveredTools.contains(where: { $0.id == defaultToolID }) {
            store.setPreferredEditorID(defaultToolID, for: projectID)
        }
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
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("Rename", action: onRename)
        Divider()
        Button("Delete", role: .destructive, action: onDelete)
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
            title: tool.label,
            systemImage: nil,
            icon: {
                WorkspaceToolIconView(tool: tool)
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
    let gitStatus: GitRepositoryStatus
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
            title: operationState.map { "\($0.title)..." } ?? gitStatus.primaryAction.title,
            systemImage: gitStatus.primaryAction.systemImage,
            icon: { EmptyView() },
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

                        Text("Commit")
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

                        Text("Push")
                            .font(.neoAction)
                            .lineLimit(1)
                    }
                    DropdownMenuRow(isDisabled: true, action: dismiss) {
                        Image(systemName: "arrow.triangle.pull")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 16, height: 16)

                        Text("Create PR")
                            .font(.neoAction)
                            .lineLimit(1)
                    }
                }
            }
        )
    }
}

private struct HeaderSplitControl<Icon: View, MenuContent: View>: View {
    let title: String
    let systemImage: String?
    @ViewBuilder let icon: () -> Icon
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

                    Text(title)
                        .font(.neoAction)
                        .foregroundStyle(primaryForegroundColor)
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

private struct WorkspaceToolIconView: View {
    let tool: WorkspaceTool

    private let service = WorkspaceToolService()

    var body: some View {
        Group {
            if let image = service.icon(for: tool) {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: tool.fallbackSystemImage)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
            }
        }
        .frame(width: 16, height: 16)
    }
}
