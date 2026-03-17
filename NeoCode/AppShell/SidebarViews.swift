import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppSidebarView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.isSettingsSelected {
                SettingsSidebarView()
            } else {
                ThreadsSidebarView()
            }
        }
        .background(SidebarChrome())
    }
}

private struct ThreadsSidebarView: View {
    @Environment(AppStore.self) private var store
    @State private var isPickingProject = false
    @State private var draggedProjectID: ProjectSummary.ID?
    @State private var dropTargetProjectID: ProjectSummary.ID?
    @State private var isBottomDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowDragRegion()
                .frame(height: 52)

            SidebarActionBar(
                isDashboardSelected: store.isDashboardSelected,
                onDashboard: {
                    store.selectDashboard()
                },
                onSettings: {
                    store.openSettings()
                }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ThreadsSectionHeader(onAddProject: { isPickingProject = true })

                    if store.projects.isEmpty {
                        EmptyProjectsSidebarView(onAddProject: { isPickingProject = true })
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(store.projects) { project in
                                ProjectTreeNode(
                                    project: project,
                                    isDropTarget: dropTargetProjectID == project.id,
                                    isBeingDragged: draggedProjectID == project.id
                                )
                                .onDrag {
                                    dropTargetProjectID = nil
                                    isBottomDropTarget = false
                                    draggedProjectID = project.id
                                    return NSItemProvider(object: project.id.uuidString as NSString)
                                }
                                .onDrop(
                                    of: [.text],
                                    delegate: ProjectSidebarDropDelegate(
                                        targetProjectID: project.id,
                                        draggedProjectID: $draggedProjectID,
                                        dropTargetProjectID: $dropTargetProjectID,
                                        isBottomDropTarget: $isBottomDropTarget,
                                        store: store
                                    )
                                )
                            }

                            ProjectSidebarBottomDropTarget(isActive: isBottomDropTarget && draggedProjectID != nil)
                                .onDrop(
                                    of: [.text],
                                    delegate: ProjectSidebarBottomDropDelegate(
                                        draggedProjectID: $draggedProjectID,
                                        dropTargetProjectID: $dropTargetProjectID,
                                        isTargeted: $isBottomDropTarget,
                                        store: store
                                    )
                                )
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
        .background(.clear)
        .fileImporter(
            isPresented: $isPickingProject,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result,
               let url = urls.first {
                store.addProject(directoryURL: url)
            }
        }
    }
}

struct EmptyProjectsSidebarView: View {
    let onAddProject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No projects yet")
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textPrimary)

            Text("Add a project folder to start tracking its threads in NeoCode.")
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Add project", action: onAddProject)
                .buttonStyle(.plain)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.accent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeoCodeTheme.panelSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }
}

struct SidebarActionBar: View {
    let isDashboardSelected: Bool
    let onDashboard: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarActionButton(
                label: "Dashboard",
                systemImage: "rectangle.grid.2x2",
                isSelected: isDashboardSelected,
                action: onDashboard
            )
            SidebarActionButton(label: "Settings", systemImage: "gearshape", action: onSettings)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}

struct SidebarActionButton: View {
    let label: String
    let systemImage: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.neoAction)
                .foregroundStyle(isSelected ? NeoCodeTheme.accent : NeoCodeTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? NeoCodeTheme.panelSoft : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
    }
}

struct ThreadsSectionHeader: View {
    let onAddProject: () -> Void

    var body: some View {
        HStack {
            Text("Threads")
                .font(.neoMeta)
                .foregroundStyle(NeoCodeTheme.textMuted)

            Spacer()

            Button(action: onAddProject) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Add project")
        }
    }
}

struct ProjectTreeNode: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime
    @State private var isHovering = false
    @State private var showsAllSessions = false

    private let workspaceToolService = WorkspaceToolService()

    let project: ProjectSummary
    var isDropTarget = false
    var isBeingDragged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: toggleCollapsed) {
                    Image(systemName: disclosureIcon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NeoCodeTheme.textMuted)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .help(store.isProjectCollapsed(project.id) ? "Expand project" : "Collapse project")

                Text(project.name)
                    .font(.neoBody)
                    .foregroundStyle(isSelectedProject ? NeoCodeTheme.textPrimary : NeoCodeTheme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                projectActions
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(selectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                store.selectProject(project.id)
            }
            .onHover { isHovering = $0 }

            if !store.isProjectCollapsed(project.id) {
                VStack(alignment: .leading, spacing: 2) {
                    if shouldShowSessionSyncIndicator {
                        ProjectSessionSyncRow()
                    }

                    ForEach(project.displayedSessions(showAll: showsAllSessions)) { session in
                        SessionTreeRow(session: session, isSelected: store.selectedSessionID == session.id)
                            .onTapGesture {
                                store.selectSession(session.id)
                            }
                    }

                    if project.hasHiddenSessions {
                        Button(action: toggleSessionExpansion) {
                            Text(sessionExpansionLabel)
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }
                }
                .padding(.leading, 14)
            }
        }
        .overlay(alignment: .top) {
            if isDropTarget {
                Capsule()
                    .fill(NeoCodeTheme.accent)
                    .frame(height: 3)
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            }
        }
        .opacity(isBeingDragged ? 0.7 : 1)
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
    }

    private var disclosureIcon: String {
        store.isProjectCollapsed(project.id) ? "chevron.right" : "chevron.down"
    }

    private var isSelectedProject: Bool {
        store.selectedProjectID == project.id
    }

    private var selectionBackground: some ShapeStyle {
        if isSelectedProject {
            return AnyShapeStyle(NeoCodeTheme.panelSoft)
        }

        if isHovering {
            return AnyShapeStyle(NeoCodeTheme.panelSoft.opacity(SidebarLayout.hoverFillOpacity))
        }

        return AnyShapeStyle(.clear)
    }

    private var projectActions: some View {
        HStack(spacing: 10) {
            Button {
                Task { await store.createSession(in: project.id, using: runtime) }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    Task { await store.refreshSessions(in: project.id, using: runtime) }
                } label: {
                    Label("Refresh Threads", systemImage: "arrow.clockwise")
                }

                Divider()

                Button("Open Project", action: openProject)
                Button("Reveal in Finder", action: revealProject)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .frame(width: 12, height: 12)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .opacity(isHovering ? 1 : 0)
        .allowsHitTesting(isHovering)
        .accessibilityHidden(!isHovering)
        .frame(width: 42, alignment: .trailing)
    }

    private func toggleCollapsed() {
        store.toggleProjectCollapsed(project.id)
    }

    private func toggleSessionExpansion() {
        withAnimation(.easeInOut(duration: 0.16)) {
            showsAllSessions.toggle()
        }
    }

    private var sessionExpansionLabel: String {
        if showsAllSessions {
            return "Show less"
        }

        let hiddenSessionLabel = project.hiddenSessionCount == 1 ? "1 more" : "\(project.hiddenSessionCount) more"
        return "Show \(hiddenSessionLabel)"
    }

    private var shouldShowSessionSyncIndicator: Bool {
        project.sessions.isEmpty && store.isSessionListSyncing(for: project.id)
    }

    private func openProject() {
        let availableTools = workspaceToolService.projectOpenTools()

        let resolvedToolID = store.preferredWorkspaceToolID(
            for: project.id,
            availableToolIDs: availableTools.map(\.id)
        ) ?? workspaceToolService.defaultProjectOpenTool(from: availableTools)?.id

        if let resolvedToolID,
           let tool = availableTools.first(where: { $0.id == resolvedToolID }) {
            workspaceToolService.openProject(at: project.path, with: tool)
            return
        }

        NSWorkspace.shared.open(projectURL)
    }

    private func revealProject() {
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    private var projectURL: URL {
        URL(fileURLWithPath: project.path)
    }
}

struct SessionTreeRow: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var renameTitle = ""

    let session: SessionSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(session.title)
                .font(.neoBody)
                .foregroundStyle(isSelected ? NeoCodeTheme.textPrimary : NeoCodeTheme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            trailingAccessory
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SidebarLayout.selectionCornerRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .contextMenu {
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

    @ViewBuilder
    private var trailingAccessory: some View {
        HStack(spacing: 6) {
            if let statusLabel {
                SidebarSessionStatusBadge(label: statusLabel, tone: statusTone)
            }

            ZStack(alignment: .trailing) {
                Text(relativeAge)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textMuted)
                    .opacity(isHovering ? 0 : 1)

                sessionMenuButton
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)
            }
            .fixedSize()
        }
        .fixedSize()
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
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var selectionBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(NeoCodeTheme.panelSoft)
        }

        if isHovering {
            return AnyShapeStyle(NeoCodeTheme.panelSoft.opacity(SidebarLayout.hoverFillOpacity))
        }

        return AnyShapeStyle(.clear)
    }

    private var relativeAge: String {
        let seconds = max(0, Int(Date().timeIntervalSince(session.lastUpdatedAt)))

        if seconds < 60 {
            return "now"
        }

        let minute = 60
        let hour = 60 * minute
        let day = 24 * hour
        let week = 7 * day

        switch seconds {
        case ..<hour:
            return "\(seconds / minute)m"
        case ..<day:
            return "\(seconds / hour)h"
        case ..<week:
            return "\(seconds / day)d"
        default:
            return "\(seconds / week)w"
        }
    }

    private var statusLabel: String? {
        switch session.status {
        case .idle:
            return nil
        case .running:
            return "working"
        case .attention:
            return "needs input"
        }
    }

    private var statusTone: SidebarSessionStatusBadge.Tone {
        switch session.status {
        case .idle, .running:
            return .accent
        case .attention:
            return .warning
        }
    }
}

struct SidebarSessionStatusBadge: View {
    enum Tone {
        case accent
        case warning
    }

    let label: String
    let tone: Tone

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(foreground)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.neoMonoSmall)
                .lineLimit(1)
        }
            .foregroundStyle(foreground)
            .padding(.leading, 6)
            .padding(.trailing, 7)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(background)
                    .overlay(Capsule().stroke(NeoCodeTheme.line, lineWidth: 1))
            )
            .fixedSize()
            .accessibilityLabel("Status: \(label)")
    }

    private var foreground: Color {
        switch tone {
        case .accent:
            NeoCodeTheme.accent
        case .warning:
            NeoCodeTheme.warning
        }
    }

    private var background: Color {
        switch tone {
        case .accent:
            NeoCodeTheme.accentDim.opacity(0.45)
        case .warning:
            NeoCodeTheme.warning.opacity(0.12)
        }
    }
}

private struct ProjectSessionSyncRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Syncing threads...")
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textMuted)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Syncing threads")
    }
}

private enum SidebarLayout {
    static let selectionCornerRadius: CGFloat = 6
    static let hoverFillOpacity: Double = 0.45
}

private struct ProjectSidebarBottomDropTarget: View {
    let isActive: Bool

    var body: some View {
        Capsule()
            .fill(isActive ? NeoCodeTheme.accent : NeoCodeTheme.accent.opacity(0.001))
            .frame(height: isActive ? 3 : 10)
            .padding(.horizontal, 6)
            .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

private struct ProjectSidebarDropDelegate: DropDelegate {
    let targetProjectID: ProjectSummary.ID
    @Binding var draggedProjectID: ProjectSummary.ID?
    @Binding var dropTargetProjectID: ProjectSummary.ID?
    @Binding var isBottomDropTarget: Bool
    let store: AppStore

    func dropEntered(info: DropInfo) {
        guard let draggedProjectID,
              draggedProjectID != targetProjectID
        else {
            return
        }

        isBottomDropTarget = false
        dropTargetProjectID = targetProjectID

        withAnimation(.easeInOut(duration: 0.14)) {
            store.moveProject(draggedProjectID, before: targetProjectID)
        }
    }

    func dropExited(info: DropInfo) {
        guard dropTargetProjectID == targetProjectID else { return }
        dropTargetProjectID = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetProjectID = nil
        isBottomDropTarget = false
        draggedProjectID = nil
        return true
    }
}

private struct ProjectSidebarBottomDropDelegate: DropDelegate {
    @Binding var draggedProjectID: ProjectSummary.ID?
    @Binding var dropTargetProjectID: ProjectSummary.ID?
    @Binding var isTargeted: Bool
    let store: AppStore

    func dropEntered(info: DropInfo) {
        guard let draggedProjectID else { return }

        dropTargetProjectID = nil
        isTargeted = true

        withAnimation(.easeInOut(duration: 0.14)) {
            store.moveProjectToEnd(draggedProjectID)
        }
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        dropTargetProjectID = nil
        draggedProjectID = nil
        return true
    }
}

private struct SidebarChrome: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
    }
}
