import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @Environment(AppStore.self) private var store
    @State private var isImportingFiles = false
    @State private var isCreatingBranch = false
    @State private var newBranchName = ""
    @State private var textViewHeight: CGFloat = 36

    @Binding var text: String
    let onSend: () -> Void
    let onStop: () -> Void

    private let contentWidth: CGFloat = 820

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                if !store.attachedFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.attachedFiles) { attachment in
                                ComposerAttachmentChip(attachment: attachment) {
                                    store.removeAttachment(id: attachment.id)
                                }
                            }
                        }
                    }
                }

                GrowingTextView(
                    text: $text,
                    measuredHeight: $textViewHeight,
                    onPrimaryAction: primaryAction,
                    allowsEmptyPrimaryAction: isStopMode
                )
                    .frame(height: textViewHeight)

                HStack(alignment: .center, spacing: 8) {
                    Menu {
                        Button("Attach Files...") {
                            isImportingFiles = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(NeoCodeTheme.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)

                    SearchableComposerDropdown(
                        title: store.selectedModel?.title ?? "Select model",
                        items: store.availableModels,
                        emptyMessage: "No models found.",
                        placeholder: "Search models",
                        isSearchable: true
                    ) { model in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.title)
                                .font(.neoBody)
                                .foregroundStyle(NeoCodeTheme.textPrimary)
                            Text(model.providerID)
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.textMuted)
                        }
                    } searchableText: { model in
                        [model.title, model.providerID, model.modelID]
                    } onSelect: { model in
                        store.selectedModelID = model.id
                        store.refreshThinkingLevels()
                    }

                    SearchableComposerDropdown(
                        title: store.selectedAgent.isEmpty ? "Agent" : store.displayAgentName(store.selectedAgent),
                        items: store.availableAgents.map { ComposerDropdownOption(id: $0, title: store.displayAgentName($0)) },
                        emptyMessage: "No agents available.",
                        placeholder: "Search agents",
                        isSearchable: false
                    ) { option in
                        Text(option.title)
                            .font(.neoBody)
                            .foregroundStyle(NeoCodeTheme.textPrimary)
                    } searchableText: { option in
                        [option.title, option.id]
                    } onSelect: { option in
                        store.selectedAgent = option.id
                    }

                    SearchableComposerDropdown(
                        title: store.selectedThinkingLevel ?? "Reasoning",
                        items: store.availableThinkingLevels.map { ComposerDropdownOption(id: $0, title: $0) },
                        emptyMessage: "No variants available.",
                        placeholder: "Search reasoning",
                        isSearchable: false
                    ) { option in
                        Text(option.title)
                            .font(.neoBody)
                            .foregroundStyle(NeoCodeTheme.textPrimary)
                    } searchableText: { option in
                        [option.title]
                    } onSelect: { option in
                        store.selectedThinkingLevel = option.id
                    }

                    Spacer(minLength: 12)

                    Button(action: primaryAction) {
                        Image(systemName: primaryActionSymbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(primaryActionForeground)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(primaryActionBackground))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canTriggerPrimaryAction)
                    .help(primaryActionHelp)
                    .accessibilityLabel(primaryActionHelp)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(NeoCodeTheme.panelRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(NeoCodeTheme.line, lineWidth: 1)
                    )
            )

            HStack {
                Spacer()

                if let sessionID = store.selectedSession?.id {
                    YoloModeToggleButton(
                        isEnabled: store.isYoloModeEnabled(for: sessionID),
                        toggle: {
                            store.setYoloMode(!store.isYoloModeEnabled(for: sessionID), for: sessionID)
                        }
                    )
                }

                if store.selectedSession != nil {
                    Spacer()
                        .frame(width: 8)
                }

                SearchableComposerDropdown(
                    title: store.selectedBranch,
                    items: store.availableBranches.map { ComposerDropdownOption(id: $0, title: $0) },
                    emptyMessage: "No branches found.",
                    placeholder: "Search branches",
                    isSearchable: false,
                    rowContent: { option in
                        Text(option.title)
                            .font(.neoBody)
                            .foregroundStyle(NeoCodeTheme.textPrimary)
                    },
                    searchableText: { option in
                        [option.title]
                    },
                    onSelect: { option in
                        store.selectedBranch = option.id
                    },
                    footer: {
                        AnyView(
                            VStack(spacing: 8) {
                                Divider()

                                Button("Create Branch...") {
                                    newBranchName = ""
                                    isCreatingBranch = true
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        )
                    }
                )
            }
        }
        .frame(maxWidth: contentWidth)
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                store.addAttachments(from: urls)
            }
        }
        .alert("Create Branch", isPresented: $isCreatingBranch) {
            TextField("Branch name", text: $newBranchName)
            Button("Cancel", role: .cancel) {
                newBranchName = ""
            }
            Button("Create") {
                store.createBranch(named: newBranchName)
            }
        } message: {
            Text("Create a new branch for this session.")
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isStopMode: Bool {
        store.selectedSession?.status == .running
    }

    private var canTriggerPrimaryAction: Bool {
        isStopMode || canSend
    }

    private var primaryAction: () -> Void {
        isStopMode ? onStop : onSend
    }

    private var primaryActionSymbol: String {
        isStopMode ? "stop.fill" : "arrow.up"
    }

    private var primaryActionForeground: Color {
        NeoCodeTheme.canvas
    }

    private var primaryActionBackground: Color {
        if isStopMode {
            return NeoCodeTheme.warning
        }
        return canSend ? NeoCodeTheme.textPrimary : NeoCodeTheme.accentDim
    }

    private var primaryActionHelp: String {
        isStopMode ? "Stop current response" : "Send message"
    }
}

private struct YoloModeToggleButton: View {
    let isEnabled: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: isEnabled ? "flame.fill" : "flame")
                    .font(.system(size: 12, weight: .semibold))
                Text("YOLO")
                    .font(.neoMonoSmall)
            }
            .foregroundStyle(isEnabled ? NeoCodeTheme.canvas : NeoCodeTheme.warning)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(isEnabled ? NeoCodeTheme.warning : NeoCodeTheme.panel)
                    .overlay(
                        Capsule()
                            .stroke(isEnabled ? NeoCodeTheme.warning.opacity(0.75) : NeoCodeTheme.line, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(isEnabled ? "YOLO mode enabled: auto-approve all permission prompts for this session." : "Enable YOLO mode to auto-approve all permission prompts for this session.")
        .accessibilityLabel("YOLO mode")
        .accessibilityValue(isEnabled ? "On" : "Off")
    }
}

private struct ComposerTextInputHeightKey: EnvironmentKey {
    static let defaultValue: Binding<CGFloat>? = nil
}

extension EnvironmentValues {
    var composerTextInputHeight: Binding<CGFloat>? {
        get { self[ComposerTextInputHeightKey.self] }
        set { self[ComposerTextInputHeightKey.self] = newValue }
    }
}

extension View {
    func textInputHeight(_ binding: Binding<CGFloat>) -> some View {
        environment(\.composerTextInputHeight, binding)
    }
}

struct GrowingTextView: NSViewRepresentable {
    @Environment(\.composerTextInputHeight) private var externalHeight
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let onPrimaryAction: () -> Void
    let allowsEmptyPrimaryAction: Bool

    private let minimumHeight: CGFloat = 36
    private let maximumHeight: CGFloat = 140

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = NSColor(NeoCodeTheme.textPrimary)
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text

            if text.isEmpty {
                context.coordinator.updateMeasuredHeight(minimumHeight)
                return
            }
        }
        context.coordinator.recalculateHeight(for: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView

        init(_ parent: GrowingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight(for: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let insertsNewline = commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertLineBreak(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))

            guard insertsNewline else { return false }

            let shiftPressed = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            if shiftPressed {
                return false
            }

            let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard parent.allowsEmptyPrimaryAction || !trimmed.isEmpty else { return true }

            parent.onPrimaryAction()
            return true
        }

        func recalculateHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return }

            layoutManager.ensureLayout(for: textContainer)
            let height = max(parent.minimumHeight, min(parent.maximumHeight, ceil(layoutManager.usedRect(for: textContainer).height + 8)))
            updateMeasuredHeight(height)
        }

        func updateMeasuredHeight(_ height: CGFloat) {
            let externalHeight = parent.externalHeight?.wrappedValue ?? height
            guard abs(parent.measuredHeight - height) > 1 || abs(externalHeight - height) > 1 else { return }

            DispatchQueue.main.async {
                self.parent.measuredHeight = height
                self.parent.externalHeight?.wrappedValue = height
            }
        }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TranscriptScrollMetrics: Equatable {
    let contentOffsetY: CGFloat
    let contentHeight: CGFloat
    let visibleMaxY: CGFloat
}

extension View {
    func readHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self, perform: onChange)
    }
}

struct ComposerPillLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.neoMonoSmall)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(NeoCodeTheme.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(NeoCodeTheme.panelSoft)
                .overlay(Capsule().stroke(NeoCodeTheme.line, lineWidth: 1))
        )
    }
}

struct SearchableComposerDropdown<Item: Identifiable, RowContent: View>: View where Item.ID == String {
    let title: String
    let items: [Item]
    let emptyMessage: String
    let placeholder: String
    let isSearchable: Bool
    @ViewBuilder let rowContent: (Item) -> RowContent
    let searchableText: (Item) -> [String]
    let onSelect: (Item) -> Void
    let footer: (() -> AnyView)?

    @State private var isOpen = false
    @State private var query = ""

    init(
        title: String,
        items: [Item],
        emptyMessage: String,
        placeholder: String,
        isSearchable: Bool,
        @ViewBuilder rowContent: @escaping (Item) -> RowContent,
        searchableText: @escaping (Item) -> [String],
        onSelect: @escaping (Item) -> Void,
        footer: (() -> AnyView)? = nil
    ) {
        self.title = title
        self.items = items
        self.emptyMessage = emptyMessage
        self.placeholder = placeholder
        self.isSearchable = isSearchable
        self.rowContent = rowContent
        self.searchableText = searchableText
        self.onSelect = onSelect
        self.footer = footer
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            ComposerPillLabel(title: title)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                if isSearchable {
                    TextField(placeholder, text: $query)
                        .textFieldStyle(.plain)
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(NeoCodeTheme.panelSoft)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                                )
                        )
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if filteredItems.isEmpty {
                            Text(emptyMessage)
                                .font(.neoBody)
                                .foregroundStyle(NeoCodeTheme.textMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(filteredItems, id: \.id) { item in
                                Button {
                                    onSelect(item)
                                    query = ""
                                    isOpen = false
                                } label: {
                                    rowContent(item)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 9)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(width: 280, height: 260)

                if let footer {
                    footer()
                }
            }
            .padding(12)
            .background(NeoCodeTheme.panel)
        }
    }

    private var filteredItems: [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { item in
            searchableText(item).contains { value in
                value.localizedCaseInsensitiveContains(trimmed)
            }
        }
    }
}

struct ComposerDropdownOption: Identifiable, Hashable {
    let id: String
    let title: String
}

struct ComposerAttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NeoCodeTheme.textMuted)

            Text(attachment.name)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .lineLimit(1)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NeoCodeTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(NeoCodeTheme.panelSoft)
                .overlay(Capsule().stroke(NeoCodeTheme.line, lineWidth: 1))
        )
    }
}

struct InlineStatusView: View {
    enum Tone {
        case neutral
        case warning
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.neoMonoSmall)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(NeoCodeTheme.line, lineWidth: 1)
                    )
            )
    }

    private var foreground: Color {
        switch tone {
        case .neutral: NeoCodeTheme.textSecondary
        case .warning: NeoCodeTheme.warning
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: NeoCodeTheme.panel
        case .warning: NeoCodeTheme.warning.opacity(0.12)
        }
    }
}

struct EmptyConversationView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(NeoCodeTheme.panelRaised)
                    .frame(width: 76, height: 76)
                    .overlay(Circle().stroke(NeoCodeTheme.line, lineWidth: 1))

                Image(systemName: "terminal")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(NeoCodeTheme.accent)
            }

            VStack(spacing: 10) {
                Text(store.projects.isEmpty ? "Add your first project" : "Start a thread")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text(store.projects.isEmpty
                     ? "Use the project button in the Threads sidebar to add a folder. NeoCode will only show threads for projects you explicitly add."
                     : "Create a new thread or select one from the sidebar to begin chatting with the OpenCode runtime.")
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct HeaderStatusView: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(runtime.statusLabel(for: store.selectedProject?.path))
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textMuted)
        }
    }

    private var statusColor: Color {
        switch runtime.state(for: store.selectedProject?.path) {
        case .idle:
            NeoCodeTheme.textMuted
        case .starting:
            NeoCodeTheme.accent
        case .running:
            NeoCodeTheme.success
        case .failed:
            NeoCodeTheme.warning
        }
    }
}

struct ErrorToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NeoCodeTheme.warning)

            Text(message)
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(NeoCodeTheme.warning.opacity(0.45), lineWidth: 1)
                )
        )
        .frame(maxWidth: 360, alignment: .trailing)
        .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 6)
    }
}

struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = NSSize(width: 980, height: 600)
    }
}
