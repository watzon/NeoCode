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
    @Environment(\.locale) private var locale
    @FocusState private var composerFocused: Bool
    // Measured height of the full overlaid prompt dock. We use this to add
    // extra scroll content at the bottom without changing the scroll view's own
    // frame, which keeps the scrollbar track reaching the full height of the
    // pane.
    @State private var promptOverlayHeight: CGFloat = 0
    @State private var textInputHeight: CGFloat = 36
    @State private var isPinnedToBottom = true
    @State private var isMaintainingPinnedPosition = false
    @State private var isAwaitingInitialScroll = true
    @State private var lastObservedTranscriptContentOffsetY: CGFloat?
    @State private var loadedMessageCount = 120
    @State private var isLoadingOlderMessages = false
    @State private var pendingRevertPreview: SessionRevertPreview?
    @State private var isPerformingRevert = false
    @State private var auxiliarySelectionIndex = 0
    @State private var auxiliaryScrollTargetID: String?
    @State private var dismissedAuxiliaryQuery: ComposerAuxiliaryDismissal?
    @State private var composerSelectionRequest: ComposerTextSelectionRequest?
    @State private var fileMentionResults: [ProjectFileSearchResult] = []
    @State private var fileSearchTask: Task<Void, Never>?
    @State private var scrollFollowUpTask: Task<Void, Never>?
    @State private var pinnedPositionResetTask: Task<Void, Never>?
    @State private var initialPresentationTask: Task<Void, Never>?
    @State private var olderMessagesTask: Task<Void, Never>?
    @State private var isTodoListPresented = false
    @State private var renderedGroups: [DisplayMessageGroup] = []

    private let scrollFixtureKey = "NEOCODE_UI_TEST_SCROLL_FIXTURE"

    private let bottomAnchorSpacerHeight: CGFloat = 1
    private let autoScrollThreshold: CGFloat = 72
    private let olderMessagesLoadThreshold: CGFloat = 300
    private let transcriptPageSize = 120
    private let transcriptColumnWidth: CGFloat = 820
    private let transcriptHorizontalInset: CGFloat = 32
    private let composerTopPadding: CGFloat = 8
    private let composerBottomPadding: CGFloat = 14
    private let composerControlSpacing: CGFloat = 12
    private let queuedMessageReservedHeight: CGFloat = 100
    private let queuedMessageStackOverlap: CGFloat = 20
    private let todoPanelBottomSpacing: CGFloat = 12
    private let todoPanelTitleHeight: CGFloat = 40
    private let todoPanelRowHeight: CGFloat = 58
    private let todoPanelMaxVisibleRows = 5
    private let loadingPromptFallbackHeight: CGFloat = 96
    private let permissionPromptFallbackHeight: CGFloat = 280
    private let questionPromptFallbackHeight: CGFloat = 360
    // This is intentional extra breathing room above the overlaid prompt UI.
    // Keep it inside scroll content via `contentBottomInset`; do not move this
    // to a safe area inset or external padding unless you also want the
    // scrollbar track to shrink.
    private let composerBottomClearance: CGFloat = 180
    private let promptOverlayBottomClearance: CGFloat = 40
    private let transcriptBottomPadding: CGFloat = 25
    private let scrollbarCompensation = ConversationLayout.scrollbarCompensation
    private let transcriptScrollSpaceName = "ConversationTranscriptScrollSpace"

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
                refreshRenderedGroups()
                refreshFileMentionResults()
                if ProcessInfo.processInfo.environment[scrollFixtureKey] == "1" {
                    isPinnedToBottom = false
                }
            }
            .task(id: sessionID) {
                await store.preparePrompt(for: sessionID)
            }
            .onChange(of: sessionID) { _, _ in
                prepareSessionPresentation(using: proxy)
                refreshRenderedGroups()
                composerFocused = promptSurface.isComposer
                isTodoListPresented = false
            }
            .onChange(of: promptSurface.id) { _, _ in
                composerFocused = promptSurface.isComposer
            }
            .onChange(of: store.todos(for: sessionID)) { _, todos in
                if todos.isEmpty {
                    isTodoListPresented = false
                }
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
                refreshRenderedGroups()
                guard oldValue != newValue, isPinnedToBottom else { return }
                maintainPinnedPosition(using: proxy, animated: true)
            }
            .onChange(of: loadedMessageCount) { _, _ in
                refreshRenderedGroups()
            }
            .onChange(of: store.loadingTranscriptSessionID) { _, _ in
                guard isAwaitingInitialScroll, !shouldShowTranscriptLoadingState else { return }

                refreshRenderedGroups()

                if transcriptCount > 0 {
                    completeInitialScroll(using: proxy)
                } else {
                    finishInitialPresentation()
                }
            }
            .onChange(of: promptOverlayHeight) { _, _ in
                guard isPinnedToBottom else { return }
                maintainPinnedPosition(using: proxy, animated: false)
            }
            .onChange(of: store.draft) { _, _ in
                if rawAuxiliaryTrigger == nil {
                    dismissedAuxiliaryQuery = nil
                }
            }
            .onChange(of: activeAuxiliaryTrigger) { _, _ in
                auxiliarySelectionIndex = 0
                auxiliaryScrollTargetID = nil
            }
            .onChange(of: showsAuxiliaryPopover) { _, isShowing in
                if isShowing {
                    auxiliarySelectionIndex = 0
                    auxiliaryScrollTargetID = nil
                }
            }
            .onChange(of: filteredAuxiliaryItemIDs) { _, ids in
                guard !ids.isEmpty else {
                    auxiliarySelectionIndex = 0
                    auxiliaryScrollTargetID = nil
                    return
                }
                auxiliarySelectionIndex = min(auxiliarySelectionIndex, ids.count - 1)
            }
            .onChange(of: activeFileSearchKey) { _, _ in
                refreshFileMentionResults()
            }
            .onDisappear {
                fileSearchTask?.cancel()
                scrollFollowUpTask?.cancel()
                pinnedPositionResetTask?.cancel()
                initialPresentationTask?.cancel()
                olderMessagesTask?.cancel()
            }
            .sheet(item: $pendingRevertPreview) { preview in
                RevertHistorySheet(
                    preview: preview,
                    isPerformingRevert: isPerformingRevert,
                    onCancel: {
                        guard !isPerformingRevert else { return }
                        pendingRevertPreview = nil
                    },
                    onConfirm: {
                        performRevert(using: preview)
                    }
                )
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
        store.selectedSession?.status.isActive == true
    }

    private var rawAuxiliaryTrigger: ComposerAuxiliaryTrigger? {
        guard promptSurface.isComposer,
              !isStopMode
        else {
            return nil
        }

        return ComposerAuxiliaryParser.activeTrigger(in: store.draft)
    }

    private var activeAuxiliaryTrigger: ComposerAuxiliaryTrigger? {
        guard let rawAuxiliaryTrigger,
              rawAuxiliaryTrigger.dismissal != dismissedAuxiliaryQuery
        else {
            return nil
        }

        return rawAuxiliaryTrigger
    }

    private var activeSlashQuery: String? {
        guard let activeAuxiliaryTrigger,
              activeAuxiliaryTrigger.kind == .slashCommand
        else {
            return nil
        }

        return activeAuxiliaryTrigger.query
    }

    private var activeFileMentionQuery: String? {
        guard let activeAuxiliaryTrigger,
              activeAuxiliaryTrigger.kind == .fileMention
        else {
            return nil
        }

        return activeAuxiliaryTrigger.query
    }

    private var slashCommands: [ComposerSlashCommand] {
        let local = LocalComposerSlashCommand.allCases.map { ComposerSlashCommand.local($0, locale: locale) }
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

    private var filteredFileMentionIDs: [String] {
        filteredFileMentions.map(\.id)
    }

    private var filteredFileMentions: [ProjectFileSearchResult] {
        guard activeFileMentionQuery != nil else { return [] }
        return fileMentionResults
    }

    private var filteredAuxiliaryItemIDs: [String] {
        guard let activeAuxiliaryTrigger else { return [] }

        switch activeAuxiliaryTrigger.kind {
        case .slashCommand:
            return filteredSlashCommandIDs
        case .fileMention:
            return filteredFileMentionIDs
        }
    }

    private var activeFileSearchKey: String? {
        guard let query = activeFileMentionQuery,
              let projectPath = store.selectedProject?.path
        else {
            return nil
        }

        return "\(projectPath)|\(query)"
    }

    private var showsAuxiliaryPopover: Bool {
        activeAuxiliaryTrigger != nil
    }

    private func dismissAuxiliaryPopover() -> Bool {
        guard let activeAuxiliaryTrigger else { return false }
        dismissedAuxiliaryQuery = activeAuxiliaryTrigger.dismissal
        return true
    }

    private func moveAuxiliarySelection(_ delta: Int) -> Bool {
        guard showsAuxiliaryPopover else { return false }
        guard !filteredAuxiliaryItemIDs.isEmpty else { return true }

        let count = filteredAuxiliaryItemIDs.count
        auxiliarySelectionIndex = (auxiliarySelectionIndex + delta + count) % count
        auxiliaryScrollTargetID = filteredAuxiliaryItemIDs[auxiliarySelectionIndex]
        return true
    }

    private func confirmAuxiliarySelection() -> Bool {
        guard let activeAuxiliaryTrigger else { return false }

        switch activeAuxiliaryTrigger.kind {
        case .slashCommand:
            guard !filteredSlashCommands.isEmpty else { return true }
            let index = min(auxiliarySelectionIndex, filteredSlashCommands.count - 1)
            insertSlashCommand(filteredSlashCommands[index])
        case .fileMention:
            guard !filteredFileMentions.isEmpty else { return true }
            let index = min(auxiliarySelectionIndex, filteredFileMentions.count - 1)
            insertFileMention(filteredFileMentions[index], trigger: activeAuxiliaryTrigger)
        }

        return true
    }

    private func insertSlashCommand(_ command: ComposerSlashCommand) {
        let updatedText = "/\(command.name) "
        applyComposerReplacement(ComposerAuxiliaryReplacement(text: updatedText, cursorLocation: updatedText.count))
    }

    private func insertFileMention(_ file: ProjectFileSearchResult, trigger: ComposerAuxiliaryTrigger) {
        applyComposerReplacement(trigger.applyingReplacement("@\(file.relativePath) ", to: store.draft))
    }

    private func applyComposerReplacement(_ replacement: ComposerAuxiliaryReplacement) {
        dismissedAuxiliaryQuery = nil
        store.draft = replacement.text
        auxiliarySelectionIndex = 0
        auxiliaryScrollTargetID = nil
        composerSelectionRequest = ComposerTextSelectionRequest(text: replacement.text, cursorLocation: replacement.cursorLocation)
    }

    private func refreshFileMentionResults() {
        fileSearchTask?.cancel()

        guard let query = activeFileMentionQuery,
              let projectPath = store.selectedProject?.path
        else {
            fileMentionResults = []
            return
        }

        fileSearchTask = Task {
            let results = await ProjectFileSearchService.shared.searchFiles(in: projectPath, query: query)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard activeFileMentionQuery == query,
                      store.selectedProject?.path == projectPath
                else {
                    return
                }

                fileMentionResults = results
            }
        }
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
                        if hasOlderMessages || isLoadingOlderMessages {
                            olderMessagesLoadControl(using: proxy)
                        }

                        if let error = store.lastError {
                            InlineStatusView(text: error, tone: .warning)
                        }

                        VStack(alignment: .leading, spacing: 18) {
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
                .background {
                    // Attach inside the scroll content hierarchy so AppKit scroll
                    // notifications track real transcript movement instead of only
                    // firing when SwiftUI re-renders the outer container.
                    TranscriptScrollObserver { metrics in
                        DispatchQueue.main.async {
                            updateTranscriptScrollMetrics(metrics, using: proxy)
                        }
                    }
                }
            }
            .accessibilityIdentifier("conversation.transcript.scrollView")
            .background(.clear)
            .coordinateSpace(name: transcriptScrollSpaceName)

            if showsNewSessionEmptyState {
                NewSessionEmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            } else if shouldShowTranscriptLoadingState {
                TranscriptLoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }

            if ProcessInfo.processInfo.environment[scrollFixtureKey] == "1" {
                Text("UI Scroll Fixture Ready")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityLabel("UI Scroll Fixture Ready")
                    .accessibilityIdentifier("ui.scrollFixture.ready")
                    .allowsHitTesting(false)
            }

            if ProcessInfo.processInfo.environment[scrollFixtureKey] == "1", !isPinnedToBottom {
                Text("UI Scroll Fixture Back To Bottom Visible")
                    .font(.system(size: 1))
                    .opacity(0.01)
                    .accessibilityLabel("UI Scroll Fixture Back To Bottom Visible")
                    .accessibilityIdentifier("ui.scrollFixture.backToBottomVisible")
                    .allowsHitTesting(false)
            }

            composerOverlay(using: proxy)
        }
        .accessibilityIdentifier("conversation.transcript.container")
    }

    @ViewBuilder
    private func transcriptGroupView(_ group: DisplayMessageGroup) -> some View {
        switch group {
        case .message(let message):
            MessageRowView(
                message: message,
                showsMetadataHeader: true,
                onRevert: {
                    beginRevertFlow(for: message)
                    composerFocused = false
                }
            )
        case .userTurn(let messages):
            UserTurnView(
                messages: messages,
                onRevert: { message in
                    beginRevertFlow(for: message)
                    composerFocused = false
                }
            )
        case .assistantTurn(let messages):
            AssistantTurnView(messages: messages)
        case .compaction(let messages):
            CompactionSummarySectionView(messages: messages)
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
            if let activeAuxiliaryTrigger {
                Group {
                    switch activeAuxiliaryTrigger.kind {
                    case .slashCommand:
                        ComposerSlashCommandsPopover(
                            commands: filteredSlashCommands,
                            selectedIndex: auxiliarySelectionIndex,
                            scrollTargetID: auxiliaryScrollTargetID,
                            onHoverIndex: { auxiliarySelectionIndex = $0 },
                            onSelect: insertSlashCommand
                        )
                    case .fileMention:
                        ComposerFileMentionsPopover(
                            files: filteredFileMentions,
                            selectedIndex: auxiliarySelectionIndex,
                            scrollTargetID: auxiliaryScrollTargetID,
                            onHoverIndex: { auxiliarySelectionIndex = $0 },
                            onSelect: { insertFileMention($0, trigger: activeAuxiliaryTrigger) }
                        )
                    }
                }
                .frame(width: transcriptColumnWidth)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                .zIndex(2)
            }

            if !store.queuedMessages(for: sessionID).isEmpty {
                QueuedMessagesView(
                    messages: store.queuedMessages(for: sessionID),
                    onEdit: { store.editQueuedMessage(id: $0, in: sessionID) },
                    onRemove: { store.removeQueuedMessage(id: $0, in: sessionID) },
                    onDeliveryModeChange: { id, mode in
                        store.updateQueuedMessageDeliveryMode(id: id, to: mode, in: sessionID)
                        guard mode == .steer else { return }
                        Task {
                            await store.sendQueuedSteerMessageIfPossible(id: id, in: sessionID, using: runtime)
                        }
                    }
                )
                .frame(width: transcriptColumnWidth)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                .zIndex(1)
            }

            if isTodoListPresented, !store.todos(for: sessionID).isEmpty {
                ComposerTodoPanel(items: store.todos(for: sessionID))
                    .frame(width: transcriptColumnWidth)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                    .zIndex(1)
            }

            SessionPromptAreaView(
                surface: promptSurface,
                draftText: draftBinding,
                selectionRequest: $composerSelectionRequest,
                isTodoListPresented: $isTodoListPresented,
                composerFocused: $composerFocused,
                textInputHeight: $textInputHeight,
                onConfirmAuxiliarySelection: confirmAuxiliarySelection,
                onMoveAuxiliarySelection: moveAuxiliarySelection,
                onCancelAuxiliaryUI: dismissAuxiliaryPopover,
                onSend: {
                    _ = dismissAuxiliaryPopover()
                    maintainPinnedPosition(using: proxy, animated: false)
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
        .readHeight {
            guard abs(promptOverlayHeight - $0) > 0.5 else { return }
            promptOverlayHeight = $0
        }
        .animation(.easeOut(duration: 0.16), value: showsAuxiliaryPopover)
    }

    private func backToBottomButton(using proxy: ScrollViewProxy) -> some View {
                Button {
                    maintainPinnedPosition(using: proxy, animated: true)
                } label: {
                    Label(localized("Back to bottom", locale: locale), systemImage: "arrow.down")
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
        .accessibilityIdentifier("conversation.backToBottom")
    }

    @ViewBuilder
    private func olderMessagesLoadControl(using proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            if isLoadingOlderMessages {
                ProgressView()
                    .controlSize(.small)

                Text(localized("Loading older messages...", locale: locale))
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
            } else {
                Button {
                    loadOlderMessages(using: proxy)
                } label: {
                    Text(localized("Load older messages", locale: locale))
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(NeoCodeTheme.panelRaised)
                        )
                        .overlay(
                            Capsule()
                                .stroke(NeoCodeTheme.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Text(remainingOlderMessagesLabel)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 4)
    }

    private var bottomAnchorID: String {
        "bottom-\(sessionID)"
    }

    private var contentBottomInset: CGFloat {
        // This spacer lives inside the scroll content on purpose. It clears the
        // overlaid composer while keeping the scroll view and scrollbar track at
        // their original height. Keep a fallback floor for non-composer prompt
        // surfaces so transcript rows still clear the overlay even if the live
        // height measurement lags or under-reports during transitions.
        max(
            bottomAnchorSpacerHeight,
            max(promptOverlayHeight, promptOverlayFallbackHeight) + queuedMessagesBottomInset + todoPanelBottomInset + bottomClearance + transcriptBottomPadding
        )
    }

    private var todoPanelBottomInset: CGFloat {
        let todoCount = store.todos(for: sessionID).count
        guard isTodoListPresented, todoCount > 0 else { return 0 }
        let visibleRows = min(todoCount, todoPanelMaxVisibleRows)
        return todoPanelBottomSpacing + todoPanelTitleHeight + CGFloat(visibleRows) * todoPanelRowHeight
    }

    private var queuedMessagesBottomInset: CGFloat {
        let queuedCount = store.queuedMessages(for: sessionID).count
        guard queuedCount > 0 else { return 0 }
        return queuedMessageReservedHeight + CGFloat(max(queuedCount - 1, 0)) * queuedMessageStackOverlap
    }

    private var promptOverlayFallbackHeight: CGFloat {
        switch promptSurface {
        case .composer:
            return 0
        case .loading:
            return loadingPromptFallbackHeight
        case .permission:
            return permissionPromptFallbackHeight
        case .question:
            return questionPromptFallbackHeight
        }
    }

    private var bottomClearance: CGFloat {
        switch promptSurface {
        case .composer:
            return composerBottomClearance
        case .loading, .permission, .question:
            return promptOverlayBottomClearance
        }
    }

    private var session: SessionSummary? {
        store.sessionSummary(for: sessionID)
    }

    private var transcript: [ChatMessage] {
        store.visibleTranscript(for: sessionID)
    }

    private var transcriptCount: Int {
        transcript.count
    }

    private var hasOlderMessages: Bool {
        loadedMessageCount < transcriptCount
    }

    private var transcriptRevision: Int {
        store.transcriptRevisionToken(for: sessionID)
    }

    private var remainingOlderMessagesLabel: String {
        let remaining = max(transcriptCount - loadedMessageCount, 0)
        guard remaining > 0 else { return "" }

        let format = localized(
            remaining == 1 ? "%@ earlier message hidden" : "%@ earlier messages hidden",
            locale: locale
        )

        return String(format: format, String(remaining))
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
        transcriptCount == 0
            && store.lastError == nil
            && session?.isEphemeral == true
    }

    private var shouldShowTranscriptLoadingState: Bool {
        session?.isEphemeral != true
            && transcriptCount == 0
            && store.lastError == nil
            && store.loadingTranscriptSessionID == sessionID
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        scrollFollowUpTask?.cancel()
        performScrollToBottom(using: proxy, animated: animated)
        scrollFollowUpTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            performScrollToBottom(using: proxy, animated: animated)
        }
    }

    private func maintainPinnedPosition(using proxy: ScrollViewProxy, animated: Bool) {
        isMaintainingPinnedPosition = true
        scrollToBottom(using: proxy, animated: animated)

        pinnedPositionResetTask?.cancel()
        pinnedPositionResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            isMaintainingPinnedPosition = false
        }
    }

    private func schedulePinnedStateUpdate(_ nextPinnedState: Bool) {
        guard nextPinnedState != isPinnedToBottom else { return }
        isPinnedToBottom = nextPinnedState
    }

    private func updateTranscriptScrollMetrics(_ metrics: TranscriptScrollMetrics, using proxy: ScrollViewProxy) {
        guard !isAwaitingInitialScroll else { return }

        let previousOffsetY = lastObservedTranscriptContentOffsetY
        lastObservedTranscriptContentOffsetY = metrics.contentOffsetY

        if metrics.contentOffsetY <= olderMessagesLoadThreshold {
            olderMessagesTask?.cancel()
            olderMessagesTask = Task { @MainActor in
                guard !Task.isCancelled else { return }
                loadOlderMessages(using: proxy)
            }
        }

        let nextPinnedState = TranscriptScrollPinning.nextPinnedState(
            for: metrics,
            previousOffsetY: previousOffsetY,
            isMaintainingPinnedPosition: isMaintainingPinnedPosition,
            autoScrollThreshold: autoScrollThreshold
        )

        Task { @MainActor in
            schedulePinnedStateUpdate(nextPinnedState)
        }
    }

    private func loadOlderMessages(using proxy: ScrollViewProxy) {
        guard hasOlderMessages, !isLoadingOlderMessages, !isAwaitingInitialScroll else { return }
        isLoadingOlderMessages = true

        let anchorID = renderedGroups.first?.id
        loadedMessageCount = min(transcriptCount, loadedMessageCount + transcriptPageSize)

        Task { @MainActor in
            if let anchorID {
                proxy.scrollTo(anchorID, anchor: .top)
            }
            isLoadingOlderMessages = false
        }
    }

    private func resetLoadedMessageWindow() {
        loadedMessageCount = min(transcriptPageSize, transcriptCount)
        isLoadingOlderMessages = false
    }

    private func refreshRenderedGroups() {
        renderedGroups = buildDisplayMessageGroups(from: Array(transcript.suffix(loadedMessageCount)))
    }

    private func prepareSessionPresentation(using proxy: ScrollViewProxy) {
        pendingRevertPreview = nil
        isPerformingRevert = false
        isPinnedToBottom = true
        isMaintainingPinnedPosition = false
        isAwaitingInitialScroll = true
        lastObservedTranscriptContentOffsetY = nil
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

        initialPresentationTask?.cancel()
        initialPresentationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            finishInitialPresentation()
        }
    }

    private func performScrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    private func finishInitialPresentation() {
        guard isAwaitingInitialScroll else { return }
        isAwaitingInitialScroll = false
    }

    private func beginRevertFlow(for message: ChatMessage) {
        guard let preview = store.revertPreview(for: message.id, in: sessionID) else {
            return
        }

        if preview.changedFiles.isEmpty {
            performRevert(using: preview)
        } else {
            pendingRevertPreview = preview
        }
    }

    private func performRevert(using preview: SessionRevertPreview) {
        guard !isPerformingRevert else { return }
        isPerformingRevert = true

        Task {
            let didRevert = await store.revertMessage(messageID: preview.targetPartID, in: sessionID, using: runtime)
            await MainActor.run {
                isPerformingRevert = false
                if didRevert {
                    pendingRevertPreview = nil
                    composerFocused = true
                }
            }
        }
    }
}

private struct RevertHistorySheet: View {
    @Environment(\.locale) private var locale
    let preview: SessionRevertPreview
    let isPerformingRevert: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private let maxVisibleChanges = 5
    private let changeRowHeight: CGFloat = 46
    private let changeRowSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("Revert to this point", locale: locale))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(NeoCodeTheme.textPrimary)

                    Text(summaryText)
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NeoCodeTheme.textMuted)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(NeoCodeTheme.panelSoft))
                }
                .buttonStyle(.plain)
                .disabled(isPerformingRevert)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(localized("File changes that will be reverted", locale: locale))
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: changeRowSpacing) {
                        ForEach(preview.changedFiles) { change in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(change.path)
                                    .font(.neoMonoSmall)
                                    .foregroundStyle(NeoCodeTheme.textPrimary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                if change.additions > 0 {
                                    Text("+\(change.additions)")
                                        .font(.neoMonoSmall)
                                        .foregroundStyle(NeoCodeTheme.success)
                                }

                                if change.deletions > 0 {
                                    Text("-\(change.deletions)")
                                        .font(.neoMonoSmall)
                                        .foregroundStyle(NeoCodeTheme.warning)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(NeoCodeTheme.panelRaised)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(NeoCodeTheme.line, lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
                .frame(height: changeListHeight)
            }

            Text(localized("This matches the TUI behavior: the transcript rewinds, the prompt comes back into the composer, and file edits after that point are rolled back.", locale: locale))
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(localized("Cancel", locale: locale), action: onCancel)
                    .buttonStyle(.plain)
                    .font(.neoAction)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .disabled(isPerformingRevert)

                Spacer(minLength: 0)

                Button(action: onConfirm) {
                    Text(localized(isPerformingRevert ? "Reverting..." : "Revert", locale: locale))
                        .font(.neoAction)
                        .foregroundStyle(NeoCodeTheme.canvas)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isPerformingRevert ? NeoCodeTheme.textMuted : NeoCodeTheme.textPrimary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isPerformingRevert)
            }
        }
        .padding(22)
        .frame(width: 520, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(NeoCodeTheme.panel)
    }

    private var changeListHeight: CGFloat {
        let visibleChangeCount = min(preview.changedFiles.count, maxVisibleChanges)
        let rowHeights = CGFloat(visibleChangeCount) * changeRowHeight
        let totalSpacing = CGFloat(max(visibleChangeCount - 1, 0)) * changeRowSpacing
        return rowHeights + totalSpacing
    }

    private var summaryText: String {
        let laterPrompts = max(preview.affectedPromptCount - 1, 0)
        if laterPrompts == 0 {
            return localized("This removes this prompt from the transcript and restores it to the composer.", locale: locale)
        }

        return String(
            format: localized("This removes this prompt and %@ later %@ from the transcript and restores it to the composer.", locale: locale),
            String(laterPrompts),
            localized(laterPrompts == 1 ? "prompt" : "prompts", locale: locale)
        )
    }
}

private struct NewSessionEmptyStateView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 24) {
            DraftReactiveMetaballOrb(
                size: 100,
                text: store.draft,
                renderScale: 1.0,
                internalResolutionScale: 1.15,
                animationInterval: 1.0 / 20.0
            )
            .frame(width: 120, height: 112)

            VStack(spacing: 10) {
                Text(localized("Build something cool", locale: locale))
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text(localized("Start by describing a task, asking a question, or pasting in code. Your first message will kick off the session.", locale: locale))
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
