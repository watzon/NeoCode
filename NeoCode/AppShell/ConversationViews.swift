import AppKit
import SwiftUI

struct ConversationScreen: View {
    @Environment(AppStore.self) private var store

    let selectedSessionID: String?

    var body: some View {
        Group {
            if let sessionID = selectedSessionID {
                ConversationView(sessionID: sessionID)
            } else {
                EmptyConversationView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct ConversationView: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime
    @FocusState private var composerFocused: Bool
    // Measured height of the overlaid composer dock. We use this to add extra
    // scroll content at the bottom without changing the scroll view's own frame,
    // which keeps the scrollbar track reaching the full height of the pane.
    @State private var promptDockHeight: CGFloat = 0
    @State private var textInputHeight: CGFloat = 36
    @State private var isPinnedToBottom = true
    @State private var isMaintainingPinnedPosition = false
    @State private var isAwaitingInitialScroll = true
    @State private var loadedMessageCount = 120
    @State private var isLoadingOlderMessages = false
    @State private var editingMessageID: String?
    @State private var editingText = ""
    @State private var slashSelectionIndex = 0
    @State private var slashScrollTargetID: String?
    @State private var dismissedSlashQuery: String?
    @State private var slashSelectionRequest: ComposerTextSelectionRequest?

    private let bottomAnchorSpacerHeight: CGFloat = 1
    private let autoScrollThreshold: CGFloat = 72
    private let olderMessagesLoadThreshold: CGFloat = 48
    private let transcriptPageSize = 120
    private let transcriptColumnWidth: CGFloat = 820
    private let transcriptHorizontalInset: CGFloat = 32
    private let composerTopPadding: CGFloat = 8
    private let composerBottomPadding: CGFloat = 14
    private let composerControlSpacing: CGFloat = 12
    // This is intentional extra breathing room above the overlaid composer.
    // Keep it inside scroll content via `contentBottomInset`; do not move this
    // to a safe area inset or external padding unless you also want the
    // scrollbar track to shrink.
    private let transcriptBottomClearance: CGFloat = 160
    private let scrollbarCompensation = ConversationLayout.scrollbarCompensation

    let sessionID: String

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if let session {
                    SessionHeaderView(session: session)
                        .zIndex(50)

                    GeometryReader { _ in
                        transcriptScrollView(using: proxy)
                    }
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.82, blendDuration: 0.12), value: isPinnedToBottom)
            .onAppear {
                composerFocused = promptSurface.isComposer
                prepareSessionPresentation(using: proxy)
            }
            .task(id: sessionID) {
                await store.preparePrompt(for: sessionID)
            }
            .onChange(of: sessionID) { _, _ in
                prepareSessionPresentation(using: proxy)
                composerFocused = promptSurface.isComposer
            }
            .onChange(of: promptSurface.id) { _, _ in
                composerFocused = promptSurface.isComposer
            }
            .onChange(of: transcriptCount) { oldValue, newValue in
                if isAwaitingInitialScroll {
                    loadedMessageCount = min(newValue, transcriptPageSize)
                    if shouldShowTranscriptLoadingState {
                        return
                    }

                    if newValue > 0 {
                        completeInitialScroll(using: proxy)
                    } else {
                        finishInitialPresentation()
                    }
                    return
                }

                if loadedMessageCount >= oldValue {
                    loadedMessageCount = newValue
                } else {
                    loadedMessageCount = min(max(loadedMessageCount, transcriptPageSize), newValue)
                }
            }
            .onChange(of: transcriptRevision) { oldValue, newValue in
                guard oldValue != newValue, isPinnedToBottom else { return }
                maintainPinnedPosition(using: proxy, animated: true)
            }
            .onChange(of: transcriptRevision) { _, _ in
                guard let editingMessageID,
                      let session,
                      session.transcript.contains(where: { $0.id == editingMessageID })
                else {
                    clearInlineEditing()
                    return
                }
            }
            .onChange(of: store.loadingTranscriptSessionID) { _, _ in
                guard isAwaitingInitialScroll, !shouldShowTranscriptLoadingState else { return }

                if transcriptCount > 0 {
                    completeInitialScroll(using: proxy)
                } else {
                    finishInitialPresentation()
                }
            }
            .onChange(of: promptDockHeight) { _, _ in
                guard isPinnedToBottom else { return }
                maintainPinnedPosition(using: proxy, animated: false)
            }
            .onChange(of: store.draft) { _, _ in
                if rawSlashQuery == nil {
                    dismissedSlashQuery = nil
                }
            }
            .onChange(of: activeSlashQuery) { _, _ in
                slashSelectionIndex = 0
                slashScrollTargetID = nil
            }
            .onChange(of: showsSlashPopover) { _, isShowing in
                if isShowing {
                    slashSelectionIndex = 0
                    slashScrollTargetID = nil
                }
            }
            .onChange(of: filteredSlashCommandIDs) { _, ids in
                guard !ids.isEmpty else {
                    slashSelectionIndex = 0
                    slashScrollTargetID = nil
                    return
                }
                slashSelectionIndex = min(slashSelectionIndex, ids.count - 1)
            }
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { store.draft },
            set: { store.draft = $0 }
        )
    }

    private var isStopMode: Bool {
        store.selectedSession?.status == .running
    }

    private var rawSlashQuery: String? {
        guard promptSurface.isComposer,
              !isStopMode,
              store.draft.hasPrefix("/")
        else {
            return nil
        }

        let remainder = store.draft.dropFirst()
        guard !remainder.contains(where: { $0.isWhitespace }) else {
            return nil
        }

        return String(remainder)
    }

    private var activeSlashQuery: String? {
        guard let rawSlashQuery,
              rawSlashQuery != dismissedSlashQuery
        else {
            return nil
        }

        return rawSlashQuery
    }

    private var slashCommands: [ComposerSlashCommand] {
        let local = LocalComposerSlashCommand.allCases.map(ComposerSlashCommand.local)
        let remote = store.availableCommands.map { command in
            let badgeTitle: String?
            switch command.source {
            case "skill":
                badgeTitle = "skill"
            case "mcp":
                badgeTitle = "mcp"
            default:
                badgeTitle = nil
            }

            return ComposerSlashCommand(
                kind: .remote,
                name: command.name,
                title: command.name,
                description: command.trimmedDescription,
                badgeTitle: badgeTitle,
                keywords: [command.name, command.trimmedDescription].compactMap { $0 } + command.hints
            )
        }

        return (local + remote).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var filteredSlashCommands: [ComposerSlashCommand] {
        guard let query = activeSlashQuery else { return [] }
        guard !query.isEmpty else { return slashCommands }

        let normalizedQuery = query.lowercased()
        return slashCommands.filter { command in
            command.keywords.contains(where: { $0.lowercased().contains(normalizedQuery) })
        }
    }

    private var filteredSlashCommandIDs: [String] {
        filteredSlashCommands.map(\.id)
    }

    private var showsSlashPopover: Bool {
        activeSlashQuery != nil
    }

    private func dismissSlashPopover() -> Bool {
        guard let activeSlashQuery else { return false }
        dismissedSlashQuery = activeSlashQuery
        return true
    }

    private func moveSlashCommandSelection(_ delta: Int) -> Bool {
        guard showsSlashPopover else { return false }
        guard !filteredSlashCommands.isEmpty else { return true }

        let count = filteredSlashCommands.count
        slashSelectionIndex = (slashSelectionIndex + delta + count) % count
        slashScrollTargetID = filteredSlashCommands[slashSelectionIndex].id
        return true
    }

    private func confirmSlashCommandSelection() -> Bool {
        guard showsSlashPopover else { return false }
        guard !filteredSlashCommands.isEmpty else { return true }

        let index = min(slashSelectionIndex, filteredSlashCommands.count - 1)
        insertSlashCommand(filteredSlashCommands[index])
        return true
    }

    private func insertSlashCommand(_ command: ComposerSlashCommand) {
        let updatedText = "/\(command.name) "
        dismissedSlashQuery = nil
        store.draft = updatedText
        slashSelectionIndex = 0
        slashSelectionRequest = ComposerTextSelectionRequest(text: updatedText, cursorLocation: updatedText.count)
    }

    private func transcriptScrollView(using proxy: ScrollViewProxy) -> some View {
        // The composer is drawn as an overlay pinned to the bottom of this ZStack.
        // That preserves the scroll view's full-height scrollbar track while the
        // transcript itself reserves room with `contentBottomInset`.
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if shouldShowTranscriptLoadingState {
                        Color.clear
                            .frame(height: contentBottomInset)
                            .id(bottomAnchorID)
                    } else {
                        if let error = store.lastError {
                            InlineStatusView(text: error, tone: .warning)
                        }

                        if store.isLoadingSessions {
                            InlineStatusView(text: "Loading session transcript...", tone: .neutral)
                        }

                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(renderedGroups) { group in
                                transcriptGroupView(group)
                            }
                        }

                        Color.clear
                            .frame(height: contentBottomInset)
                            .id(bottomAnchorID)
                    }
                }
                .padding(.horizontal, transcriptHorizontalInset)
                .padding(.top, 24)
                .padding(.bottom, 0)
                .frame(maxWidth: transcriptColumnWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(.clear)
            .onScrollGeometryChange(for: TranscriptScrollMetrics.self) { geometry in
                TranscriptScrollMetrics(
                    contentOffsetY: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    visibleMaxY: geometry.visibleRect.maxY
                )
            } action: { _, metrics in
                guard !isAwaitingInitialScroll else { return }

                if metrics.contentOffsetY <= olderMessagesLoadThreshold {
                    loadOlderMessages(using: proxy)
                }

                let nextPinnedState: Bool
                if isMaintainingPinnedPosition {
                    nextPinnedState = true
                } else {
                    let distanceToBottom = max(0, metrics.contentHeight - metrics.visibleMaxY)
                    nextPinnedState = distanceToBottom <= autoScrollThreshold
                }
                schedulePinnedStateUpdate(nextPinnedState)
            }

            if showsNewSessionEmptyState {
                NewSessionEmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            } else if shouldShowTranscriptLoadingState {
                TranscriptLoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }

            composerOverlay(using: proxy)
        }
    }

    @ViewBuilder
    private func transcriptGroupView(_ group: DisplayMessageGroup) -> some View {
        switch group {
        case .message(let message):
            MessageRowView(
                sessionID: sessionID,
                message: message,
                editingText: $editingText,
                isEditing: editingMessageID == message.id,
                showsMetadataHeader: true,
                onBeginEdit: {
                    editingMessageID = message.id
                    editingText = message.text
                    composerFocused = false
                },
                onCancelEdit: clearInlineEditing,
                onFinishEdit: clearInlineEditing
            )
        case .userTurn(let messages):
            UserTurnView(
                sessionID: sessionID,
                messages: messages,
                editingText: $editingText,
                editingMessageID: editingMessageID,
                onBeginEdit: { message in
                    editingMessageID = message.id
                    editingText = message.text
                    composerFocused = false
                },
                onCancelEdit: clearInlineEditing,
                onFinishEdit: clearInlineEditing
            )
        case .assistantTurn(let messages):
            AssistantTurnView(messages: messages)
        }
    }

    private func composerOverlay(using proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            composerDock(using: proxy)
                .overlay(alignment: .top) {
                    if !isPinnedToBottom {
                        backToBottomButton(using: proxy)
                            .offset(y: -(composerControlSpacing + 42))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(1)
                    }
                }

            Color.clear
                .frame(width: scrollbarCompensation, height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func composerDock(using proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .center, spacing: composerControlSpacing) {
            if showsSlashPopover {
                ComposerSlashCommandsPopover(
                    commands: filteredSlashCommands,
                    selectedIndex: slashSelectionIndex,
                    scrollTargetID: slashScrollTargetID,
                    onHoverIndex: { slashSelectionIndex = $0 },
                    onSelect: insertSlashCommand
                )
                .frame(width: transcriptColumnWidth)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                .zIndex(2)
            }

            SessionPromptAreaView(
                surface: promptSurface,
                draftText: draftBinding,
                slashSelectionRequest: $slashSelectionRequest,
                composerFocused: $composerFocused,
                textInputHeight: $textInputHeight,
                onConfirmAuxiliarySelection: confirmSlashCommandSelection,
                onMoveAuxiliarySelection: moveSlashCommandSelection,
                onCancelAuxiliaryUI: dismissSlashPopover,
                onSend: {
                    _ = dismissSlashPopover()
                    let shouldRemainPinned = isPinnedToBottom
                    if shouldRemainPinned {
                        scrollToBottom(using: proxy, animated: false)
                    }
                    Task {
                        await store.sendDraft(using: runtime)
                    }
                },
                onStop: {
                    Task {
                        await store.stopSelectedSession(using: runtime)
                    }
                }
            )
            .readHeight { promptDockHeight = $0 }
        }
        .padding(.horizontal, transcriptHorizontalInset)
        .frame(maxWidth: transcriptColumnWidth)
        .padding(.top, composerTopPadding)
        .padding(.bottom, composerBottomPadding)
        .background(
            LinearGradient(
                colors: [NeoCodeTheme.panel.opacity(0), NeoCodeTheme.panel.opacity(0.28), NeoCodeTheme.panel.opacity(0.76), NeoCodeTheme.panel],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.easeOut(duration: 0.16), value: showsSlashPopover)
    }

    private func backToBottomButton(using proxy: ScrollViewProxy) -> some View {
        Button {
            maintainPinnedPosition(using: proxy, animated: true)
        } label: {
            Label("Back to bottom", systemImage: "arrow.down")
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .background(
                    Capsule()
                        .fill(NeoCodeTheme.panelRaised.opacity(0.72))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [NeoCodeTheme.textPrimary.opacity(0.18), NeoCodeTheme.line, NeoCodeTheme.lineSoft.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: NeoCodeTheme.canvas.opacity(0.22), radius: 18, x: 0, y: 10)
                .shadow(color: NeoCodeTheme.textPrimary.opacity(0.06), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var bottomAnchorID: String {
        "bottom-\(sessionID)"
    }

    private var contentBottomInset: CGFloat {
        // This spacer lives inside the scroll content on purpose. It clears the
        // overlaid composer while keeping the scroll view and scrollbar track at
        // their original height.
        max(bottomAnchorSpacerHeight, promptDockHeight + transcriptBottomClearance)
    }

    private var renderedGroups: [DisplayMessageGroup] {
        let visibleMessages = Array((session?.transcript ?? []).suffix(loadedMessageCount))
        var groups: [DisplayMessageGroup] = []
        var currentUserTurn: [ChatMessage] = []
        var currentAssistantTurn: [ChatMessage] = []

        func flushUserTurn() {
            guard !currentUserTurn.isEmpty else { return }
            groups.append(.userTurn(currentUserTurn))
            currentUserTurn.removeAll(keepingCapacity: true)
        }

        func flushAssistantTurn() {
            guard !currentAssistantTurn.isEmpty else { return }
            groups.append(.assistantTurn(currentAssistantTurn))
            currentAssistantTurn.removeAll(keepingCapacity: true)
        }

        for message in visibleMessages {
            if message.role == .assistant || message.role == .tool {
                flushUserTurn()
                currentAssistantTurn.append(message)
            } else if message.role == .user {
                flushAssistantTurn()
                currentUserTurn.append(message)
            } else {
                flushUserTurn()
                flushAssistantTurn()
                groups.append(.message(message))
            }
        }

        flushUserTurn()
        flushAssistantTurn()

        return groups
    }

    private var session: SessionSummary? {
        store.projects
            .flatMap(\.sessions)
            .first(where: { $0.id == sessionID })
    }

    private var transcriptCount: Int {
        session?.transcript.count ?? 0
    }

    private var hasOlderMessages: Bool {
        loadedMessageCount < transcriptCount
    }

    private var transcriptRevision: String {
        guard let session else { return "" }
        return session.transcript.map { message in
            "\(message.id):\(message.text.count):\(message.isInProgress ? 1 : 0):\(message.timestamp.timeIntervalSinceReferenceDate)"
        }.joined(separator: "|")
    }

    private var promptSurface: SessionPromptSurface {
        if let request = store.pendingPermission(for: sessionID) {
            return .permission(request)
        }

        if let request = store.pendingQuestion(for: sessionID) {
            return .question(request)
        }

        if !store.isPromptReady {
            return .loading(store.promptLoadingText)
        }

        return .composer
    }

    private var showsNewSessionEmptyState: Bool {
        transcriptCount == 0 && store.lastError == nil && !store.isLoadingSessions
    }

    private var shouldShowTranscriptLoadingState: Bool {
        isAwaitingInitialScroll && store.loadingTranscriptSessionID == sessionID
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if animated {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
        }
    }

    private func maintainPinnedPosition(using proxy: ScrollViewProxy, animated: Bool) {
        isMaintainingPinnedPosition = true
        scrollToBottom(using: proxy, animated: animated)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            isMaintainingPinnedPosition = false
        }
    }

    private func schedulePinnedStateUpdate(_ nextPinnedState: Bool) {
        guard nextPinnedState != isPinnedToBottom else { return }
        isPinnedToBottom = nextPinnedState
    }

    private func loadOlderMessages(using proxy: ScrollViewProxy) {
        guard hasOlderMessages, !isLoadingOlderMessages, !isAwaitingInitialScroll else { return }
        isLoadingOlderMessages = true

        let anchorID = renderedGroups.first?.id
        loadedMessageCount = min(transcriptCount, loadedMessageCount + transcriptPageSize)

        DispatchQueue.main.async {
            if let anchorID {
                proxy.scrollTo(anchorID, anchor: .top)
            }
            DispatchQueue.main.async {
                isLoadingOlderMessages = false
            }
        }
    }

    private func resetLoadedMessageWindow() {
        loadedMessageCount = min(transcriptPageSize, transcriptCount)
        isLoadingOlderMessages = false
    }

    private func prepareSessionPresentation(using proxy: ScrollViewProxy) {
        clearInlineEditing()
        isPinnedToBottom = true
        isMaintainingPinnedPosition = false
        isAwaitingInitialScroll = true
        resetLoadedMessageWindow()

        if shouldShowTranscriptLoadingState {
            return
        }

        if transcriptCount > 0 {
            completeInitialScroll(using: proxy)
        } else {
            finishInitialPresentation()
        }
    }

    private func completeInitialScroll(using proxy: ScrollViewProxy) {
        guard isAwaitingInitialScroll else { return }
        maintainPinnedPosition(using: proxy, animated: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            finishInitialPresentation()
        }
    }

    private func finishInitialPresentation() {
        guard isAwaitingInitialScroll else { return }
        isAwaitingInitialScroll = false
    }

    private func clearInlineEditing() {
        editingMessageID = nil
        editingText = ""
    }
}

private struct NewSessionEmptyStateView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.dashed")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(NeoCodeTheme.textSecondary)

            VStack(spacing: 8) {
                Text("Build something cool")
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text("Start by describing a task, asking a question, or pasting in code. Your first message will kick off the session.")
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
        }
    }
}

private struct TranscriptLoadingView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .tint(NeoCodeTheme.textSecondary)
    }
}

enum ConversationLayout {
    static let assistantContentWidth: CGFloat = .infinity
    static let scrollbarCompensation: CGFloat = NSScroller.scrollerWidth(
        for: .regular,
        scrollerStyle: NSScroller.preferredScrollerStyle
    )
}
