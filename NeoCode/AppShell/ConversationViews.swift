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
    @State private var promptOverlayHeight: CGFloat = 0
    @State private var textInputHeight: CGFloat = 36
    @State private var isPinnedToBottom = true
    @State private var isMaintainingPinnedPosition = false
    @State private var isAwaitingInitialScroll = true
    @State private var loadedMessageCount = 120
    @State private var isLoadingOlderMessages = false
    @State private var editingMessageID: String?
    @State private var editingText = ""

    private let bottomAnchorSpacerHeight: CGFloat = 1
    private let autoScrollThreshold: CGFloat = 72
    private let olderMessagesLoadThreshold: CGFloat = 48
    private let transcriptPageSize = 120
    private let transcriptColumnWidth: CGFloat = 820
    private let transcriptHorizontalInset: CGFloat = 32
    private let composerTopPadding: CGFloat = 34
    private let composerBottomPadding: CGFloat = 14
    private let composerControlSpacing: CGFloat = 12
    private let scrollbarCompensation = ConversationLayout.scrollbarCompensation

    let sessionID: String

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if let session {
                    SessionHeaderView(session: session)

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
                    if newValue > 0 {
                        completeInitialScroll(using: proxy)
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
            .onChange(of: promptOverlayHeight) { _, _ in
                guard isPinnedToBottom else { return }
                maintainPinnedPosition(using: proxy, animated: false)
            }
        }
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { store.draft },
            set: { store.draft = $0 }
        )
    }

    private func transcriptScrollView(using proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let error = store.lastError {
                        InlineStatusView(text: error, tone: .warning)
                    }

                    if store.isLoadingSessions {
                        InlineStatusView(text: "Loading session transcript...", tone: .neutral)
                    }

                    ForEach(renderedGroups) { group in
                        transcriptGroupView(group)
                    }
                }

                Color.clear
                    .frame(height: bottomAnchorSpacerHeight)
                    .id(bottomAnchorID)
            }
            .padding(.horizontal, transcriptHorizontalInset)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: transcriptColumnWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(.clear)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerOverlay(using: proxy)
        }
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
                onBeginEdit: {
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
            VStack(alignment: .center, spacing: composerControlSpacing) {
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
                .opacity(isPinnedToBottom ? 0 : 1)
                .allowsHitTesting(!isPinnedToBottom)
                .accessibilityHidden(isPinnedToBottom)
                .zIndex(1)

                SessionPromptAreaView(
                    surface: promptSurface,
                    draftText: draftBinding,
                    composerFocused: $composerFocused,
                    textInputHeight: $textInputHeight,
                    onSend: {
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
            .readHeight { promptOverlayHeight = $0 }

            Color.clear
                .frame(width: scrollbarCompensation, height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomAnchorID: String {
        "bottom-\(sessionID)"
    }

    private var renderedGroups: [DisplayMessageGroup] {
        let visibleMessages = Array((session?.transcript ?? []).suffix(loadedMessageCount))
        var groups: [DisplayMessageGroup] = []
        var currentAssistantTurn: [ChatMessage] = []

        func flushAssistantTurn() {
            guard !currentAssistantTurn.isEmpty else { return }
            groups.append(.assistantTurn(currentAssistantTurn))
            currentAssistantTurn.removeAll(keepingCapacity: true)
        }

        for message in visibleMessages {
            if message.role == .assistant || message.role == .tool {
                currentAssistantTurn.append(message)
            } else {
                flushAssistantTurn()
                groups.append(.message(message))
            }
        }

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

        if transcriptCount > 0 {
            completeInitialScroll(using: proxy)
        }
    }

    private func completeInitialScroll(using proxy: ScrollViewProxy) {
        guard isAwaitingInitialScroll else { return }
        maintainPinnedPosition(using: proxy, animated: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isAwaitingInitialScroll = false
        }
    }

    private func clearInlineEditing() {
        editingMessageID = nil
        editingText = ""
    }
}

enum ConversationLayout {
    static let assistantContentWidth: CGFloat = .infinity
    static let scrollbarCompensation: CGFloat = NSScroller.scrollerWidth(
        for: .regular,
        scrollerStyle: NSScroller.preferredScrollerStyle
    )
}
