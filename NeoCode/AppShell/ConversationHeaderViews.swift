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
                HeaderPopoverMenu(width: 176) {
                    ForEach(allTools) { candidate in
                        let available = service.isAvailable(candidate)
                        HeaderPopoverMenuButton(
                            title: candidate.label,
                            isSelected: candidate.id == tool.id,
                            isDisabled: !available,
                            icon: {
                                WorkspaceToolIconView(tool: candidate)
                            },
                            action: {
                                onSelectTool(candidate)
                                dismiss()
                            }
                        )
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
                HeaderPopoverMenu(width: 148) {
                    HeaderPopoverMenuButton(
                        title: "Commit",
                        systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                        isDisabled: isBusy || !gitStatus.hasChanges,
                        action: {
                            onCommit()
                            dismiss()
                        }
                    )
                    HeaderPopoverMenuButton(
                        title: "Push",
                        systemImage: "arrow.up.circle",
                        isDisabled: isBusy || gitStatus.aheadCount == 0,
                        action: {
                            onPush()
                            dismiss()
                        }
                    )
                    HeaderPopoverMenuButton(
                        title: "Create PR",
                        systemImage: "arrow.triangle.pull",
                        isDisabled: true,
                        action: dismiss
                    )
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
            FloatingMenuPresenter(isPresented: isMenuOpen, onDismiss: onDismissMenu, content: {
                menuContent(onToggleMenu)
            })
        }
        .zIndex(isMenuOpen ? 10 : 0)
    }

    private var primaryForegroundColor: Color {
        isPrimaryDisabled ? NeoCodeTheme.textMuted : NeoCodeTheme.textPrimary
    }
}

private struct FloatingMenuPresenter<Content: View>: NSViewRepresentable {
    let isPresented: Bool
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchorView = nsView
        context.coordinator.update(
            isPresented: isPresented,
            onDismiss: onDismiss,
            content: AnyView(content())
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    final class Coordinator {
        weak var anchorView: NSView?
        private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
        private var panel: NSPanel?
        private var localMonitor: Any?
        private var onDismiss: (() -> Void)?

        func update(isPresented: Bool, onDismiss: @escaping () -> Void, content: AnyView) {
            guard let anchorView else {
                dismiss()
                return
            }

            self.onDismiss = onDismiss
            if isPresented {
                hostingController.rootView = content
                presentIfNeeded(from: anchorView)
                updateFrame(from: anchorView)
            } else {
                dismiss()
            }
        }

        func dismiss() {
            removeMonitor()
            if let parent = panel?.parent {
                parent.removeChildWindow(panel!)
            }
            panel?.orderOut(nil)
            panel = nil
        }

        private func presentIfNeeded(from anchorView: NSView) {
            if panel == nil {
                let panel = NSPanel(
                    contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: true
                )
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.level = .floating
                panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
                panel.hidesOnDeactivate = true
                panel.ignoresMouseEvents = false
                panel.contentView = hostingController.view
                self.panel = panel
                installMonitor()
            }

            if let panel,
               let window = anchorView.window,
               panel.parent !== window {
                window.addChildWindow(panel, ordered: .above)
            }

            panel?.orderFrontRegardless()
        }

        private func installMonitor() {
            guard localMonitor == nil else { return }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self, let panel else { return event }
                if event.window !== panel {
                    dismiss()
                    onDismiss?()
                }
                return event
            }
        }

        private func removeMonitor() {
            guard let localMonitor else { return }
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        private func updateFrame(from anchorView: NSView) {
            guard let panel,
                  let window = anchorView.window
            else { return }

            hostingController.view.layoutSubtreeIfNeeded()
            let fittingSize = hostingController.view.fittingSize
            hostingController.view.frame = CGRect(origin: .zero, size: fittingSize)

            let anchorFrameInWindow = anchorView.convert(anchorView.bounds, to: nil)
            let anchorFrameOnScreen = window.convertToScreen(anchorFrameInWindow)
            let panelOrigin = CGPoint(x: anchorFrameOnScreen.minX, y: anchorFrameOnScreen.minY - 6 - fittingSize.height)

            panel.setFrame(CGRect(origin: panelOrigin, size: fittingSize), display: true)
        }
    }
}

private struct HeaderPopoverMenu<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: () -> Content

    init(width: CGFloat = 220, @ViewBuilder content: @escaping () -> Content) {
        self.width = width
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(8)
        .frame(width: width, alignment: .leading)
        .background(NeoCodeTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NeoCodeTheme.lineStrong, lineWidth: 1)
        )
        .shadow(color: NeoCodeTheme.canvas.opacity(0.34), radius: 18, x: 0, y: 10)
    }
}

private struct HeaderPopoverMenuButton<Icon: View>: View {
    @State private var isHovering = false

    let title: String
    var systemImage: String?
    var isSelected = false
    var isDisabled = false
    @ViewBuilder var icon: () -> Icon
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool = false,
        isDisabled: Bool = false,
        @ViewBuilder icon: @escaping () -> Icon = { EmptyView() },
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(foregroundColor)
                        .frame(width: 16, height: 16)
                } else {
                    icon()
                        .frame(width: 16, height: 16)
                }

                Text(title)
                    .font(.neoAction)
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NeoCodeTheme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovering ? NeoCodeTheme.panelSoft : .clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
    }

    private var foregroundColor: Color {
        isDisabled ? NeoCodeTheme.textMuted : NeoCodeTheme.textPrimary
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
