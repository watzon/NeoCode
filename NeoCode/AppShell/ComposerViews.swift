import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ComposerView: View {
    @Environment(AppStore.self) private var store
    @State private var isImportingFiles = false
    @State private var isCreatingBranch = false
    @State private var newBranchName = ""
    @State private var textViewHeight: CGFloat = ComposerLayout.minimumTextViewHeight

    @Binding var text: String
    @Binding var selectionRequest: ComposerTextSelectionRequest?
    let onConfirmAuxiliarySelection: () -> Bool
    let onMoveAuxiliarySelection: (Int) -> Bool
    let onCancelAuxiliaryUI: () -> Bool
    let onSend: () -> Void
    let onStop: () -> Void

    private let contentWidth: CGFloat = 820

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            composerCard

            HStack(alignment: .center, spacing: 0) {
                if let activityState {
                    ComposerActivityIndicator(state: activityState)
                        .transition(.opacity)
                }

                Spacer(minLength: 0)

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

                if store.selectedProject != nil {
                    if store.gitStatus.isRepository {
                        NeoCodeSelect(
                            title: store.selectedBranch,
                            selectedID: store.selectedBranch,
                            items: store.availableBranches.map { ComposerDropdownOption(id: $0, title: $0) },
                            emptyMessage: "No branches found.",
                            placeholder: "Search branches",
                            isSearchable: false,
                            direction: .up,
                            menuWidth: 240,
                            rowContent: { option in
                                Text(option.title)
                                    .font(.neoBody)
                                    .foregroundStyle(NeoCodeTheme.textPrimary)
                            },
                            searchableText: { option in
                                [option.title]
                            },
                            onSelect: { option in
                                Task {
                                    await store.switchBranch(named: option.id)
                                }
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
                        .disabled(store.isPerformingGitOperation)
                    } else {
                        Button(action: {
                            Task {
                                await store.initializeGitRepository()
                            }
                        }) {
                            Text("Create Git Repository")
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(NeoCodeTheme.panelSoft)
                                        .overlay(Capsule().stroke(NeoCodeTheme.line, lineWidth: 1))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isPerformingGitOperation)
                    }
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activityState)
        }
        .frame(width: contentWidth, alignment: .leading)
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    await store.addAttachments(from: urls)
                }
            }
        }
        .alert("Create Branch", isPresented: $isCreatingBranch) {
            TextField("Branch name", text: $newBranchName)
            Button("Cancel", role: .cancel) {
                newBranchName = ""
            }
            Button("Create") {
                Task {
                    await store.createBranch(named: newBranchName)
                }
            }
        } message: {
            Text("Create a new branch for this session.")
        }
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty {
                textViewHeight = ComposerLayout.minimumTextViewHeight
            }
        }
    }

    private var composerCard: some View {
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
                selectionRequest: $selectionRequest,
                projectPath: store.selectedProject?.path,
                onPrimaryAction: handlePrimaryAction,
                onConfirmAuxiliarySelection: onConfirmAuxiliarySelection,
                onMoveAuxiliarySelection: onMoveAuxiliarySelection,
                onCancelAuxiliaryUI: onCancelAuxiliaryUI,
                allowsEmptyPrimaryAction: isStopMode,
                onImportAttachments: importAttachments
            )
            .frame(height: textViewHeight)

            HStack(alignment: .center, spacing: 8) {
                NeoCodeMenuButton(direction: .up) { isPresented in
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(NeoCodeTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isPresented ? NeoCodeTheme.panelSoft : NeoCodeTheme.panelRaised)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isPresented ? NeoCodeTheme.lineStrong : NeoCodeTheme.line, lineWidth: 1)
                                )
                        )
                        .animation(.easeOut(duration: 0.16), value: isPresented)
                } menuContent: { dismiss in
                    DropdownMenuSurface(width: 176) {
                        DropdownMenuRow(action: {
                            isImportingFiles = true
                            dismiss()
                        }) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 16, height: 16)

                            Text("Attach Files...")
                                .font(.neoAction)
                                .lineLimit(1)
                        }
                    }
                }
                .accessibilityLabel("More actions")

                NeoCodeSelect(
                    title: store.selectedModel?.title ?? "Select model",
                    selectedID: store.selectedModelID,
                    items: store.sortedAvailableModels,
                    emptyMessage: "No models found.",
                    placeholder: "Search models",
                    isSearchable: true,
                    direction: .up,
                    menuWidth: 320,
                    showsSelectionIndicator: false
                ) { model in
                    let isFavorited = store.isFavoriteModel(id: model.id)
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NeoCodeTheme.accent)
                            .opacity(store.selectedModelID == model.id ? 1 : 0)
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.title)
                                .font(.neoBody)
                                .foregroundStyle(NeoCodeTheme.textPrimary)
                            Text(model.providerID)
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.textMuted)
                        }
                        Spacer()
                        Button {
                            store.toggleFavoriteModel(id: model.id)
                        } label: {
                            Image(systemName: isFavorited ? "star.fill" : "star")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(isFavorited ? NeoCodeTheme.accent : NeoCodeTheme.textMuted)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help(isFavorited ? "Remove from favorites" : "Add to favorites")
                    }
                } searchableText: { model in
                    [model.title, model.providerID, model.modelID]
                } onSelect: { model in
                    store.selectedModelID = model.id
                    store.refreshThinkingLevels()
                }

                NeoCodeSelect(
                    title: store.selectedAgent.isEmpty ? "Agent" : store.displayAgentName(store.selectedAgent),
                    selectedID: store.selectedAgent.isEmpty ? nil : store.selectedAgent,
                    items: store.availableAgents.map { ComposerDropdownOption(id: $0, title: store.displayAgentName($0)) },
                    emptyMessage: "No agents available.",
                    placeholder: "Search agents",
                    isSearchable: false,
                    direction: .up,
                    menuWidth: 220
                ) { option in
                    Text(option.title)
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textPrimary)
                } searchableText: { option in
                    [option.title, option.id]
                } onSelect: { option in
                    store.selectedAgent = option.id
                }

                if !store.availableThinkingLevels.isEmpty {
                    NeoCodeSelect(
                        title: store.selectedThinkingLevel ?? "Reasoning",
                        selectedID: store.selectedThinkingLevel,
                        items: store.availableThinkingLevels.map { ComposerDropdownOption(id: $0, title: $0) },
                        emptyMessage: "No variants available.",
                        placeholder: "Search reasoning",
                        isSearchable: false,
                        direction: .up,
                        menuWidth: 220
                    ) { option in
                        Text(option.title)
                            .font(.neoBody)
                            .foregroundStyle(NeoCodeTheme.textPrimary)
                    } searchableText: { option in
                        [option.title]
                    } onSelect: { option in
                        store.selectedThinkingLevel = option.id
                    }
                }

                Spacer(minLength: 12)

                Button(action: handlePrimaryAction) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.attachedFiles.isEmpty
    }

    private var isStopMode: Bool {
        store.selectedSession?.status == .running
    }

    private var activityState: ComposerActivityState? {
        if let activity = store.selectedSessionActivity {
            switch activity {
            case .busy:
                return .thinking
            case .retry:
                return .retrying
            case .idle:
                break
            }
        }

        if store.selectedSession?.status == .running {
            return .thinking
        }

        return nil
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

    private func handlePrimaryAction() {
        guard canTriggerPrimaryAction else { return }

        if !isStopMode {
            textViewHeight = ComposerLayout.minimumTextViewHeight
        }

        primaryAction()
    }

    private func importAttachments(_ items: [ComposerAttachmentImportItem]) {
        Task {
            await store.addAttachments(from: items)
        }
    }
}

private enum ComposerLayout {
    static let minimumTextViewHeight: CGFloat = 36
}

private enum ComposerActivityState: Equatable {
    case thinking
    case retrying

    var title: String {
        switch self {
        case .thinking:
            return "thinking"
        case .retrying:
            return "retrying"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .thinking:
            return "Agent is working"
        case .retrying:
            return "Agent is retrying"
        }
    }

    var helpText: String {
        switch self {
        case .thinking:
            return "The agent is still working."
        case .retrying:
            return "The agent is retrying after a temporary interruption."
        }
    }

    var primaryTint: Color {
        switch self {
        case .thinking:
            return NeoCodeTheme.accent
        case .retrying:
            return NeoCodeTheme.warning
        }
    }

    var secondaryTint: Color {
        switch self {
        case .thinking:
            return NeoCodeTheme.success
        case .retrying:
            return NeoCodeTheme.accent
        }
    }
}

struct ComposerTextSelectionRequest: Equatable {
    let id = UUID()
    let text: String
    let cursorLocation: Int
}

private struct ComposerActivityIndicator: View {
    let state: ComposerActivityState

    var body: some View {
        MetaballOrb(size: 32)
            .help(state.helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Agent activity")
            .accessibilityValue(state.accessibilityValue)
    }
}

struct MetaballOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let size: CGFloat

    var body: some View {
        Group {
            if reduceMotion {
                staticOrb()
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    orbCanvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size, height: size)
        .drawingGroup(opaque: false, colorMode: .linear)
    }

    private func staticOrb() -> some View {
        Canvas(rendersAsynchronously: true) { context, size in
            drawOrb(in: &context, size: size, time: 0)
        }
    }

    private func orbCanvas(time: TimeInterval) -> some View {
        Canvas(rendersAsynchronously: true) { context, size in
            drawOrb(in: &context, size: size, time: time)
        }
    }

    private func drawOrb(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = min(size.width, size.height) / 120.0

        // Define distinct colored blobs that fuse together like the reference image
        // Each blob: (baseX, baseY, phase, speed, radius, color, intensity)
        struct Blob {
            let baseX: CGFloat
            let baseY: CGFloat
            let phase: Double
            let speed: Double
            let baseRadius: CGFloat
            let color: Color
            let intensity: CGFloat
            let orbitRadius: CGFloat
            let orbitSpeed: Double
        }

        let blobs: [Blob] = [
            // Core - bright yellow center
            Blob(baseX: 0, baseY: 0, phase: 0, speed: 0.9, baseRadius: 22, color: Color(red: 1.0, green: 0.85, blue: 0.1), intensity: 1.0, orbitRadius: 3, orbitSpeed: 0.7),

            // Inner red-orange blobs (2 of them) - fuse with core
            Blob(baseX: 18, baseY: 5, phase: 1.2, speed: 0.8, baseRadius: 18, color: Color(red: 1.0, green: 0.25, blue: 0.15), intensity: 0.95, orbitRadius: 5, orbitSpeed: -0.6),
            Blob(baseX: -8, baseY: 16, phase: 2.1, speed: 0.75, baseRadius: 16, color: Color(red: 1.0, green: 0.35, blue: 0.12), intensity: 0.9, orbitRadius: 4, orbitSpeed: 0.55),

            // Mid magenta/pink blob
            Blob(baseX: -15, baseY: -8, phase: 0.8, speed: 0.65, baseRadius: 19, color: Color(red: 0.95, green: 0.2, blue: 0.45), intensity: 0.85, orbitRadius: 6, orbitSpeed: -0.5),

            // Outer purple/indigo blobs (2 of them) - fuse with the cluster
            Blob(baseX: -22, baseY: 5, phase: 3.5, speed: 0.5, baseRadius: 20, color: Color(red: 0.35, green: 0.05, blue: 0.65), intensity: 0.75, orbitRadius: 7, orbitSpeed: 0.45),
            Blob(baseX: 8, baseY: -20, phase: 1.8, speed: 0.55, baseRadius: 18, color: Color(red: 0.45, green: 0.08, blue: 0.75), intensity: 0.8, orbitRadius: 5, orbitSpeed: -0.4),

            // Extra satellite blobs for more organic shape
            Blob(baseX: 20, baseY: -12, phase: 4.2, speed: 0.7, baseRadius: 14, color: Color(red: 0.85, green: 0.15, blue: 0.35), intensity: 0.7, orbitRadius: 4, orbitSpeed: 0.6),
            Blob(baseX: -5, baseY: 22, phase: 2.8, speed: 0.6, baseRadius: 15, color: Color(red: 0.55, green: 0.1, blue: 0.7), intensity: 0.65, orbitRadius: 5, orbitSpeed: -0.55),
        ]

        // Draw blobs from back (cool colors) to front (hot colors) for proper layering
        // Sort by color temperature - purples first, then magentas, then oranges, then yellow
        let sortedBlobs = blobs.enumerated().sorted { a, b in
            let tempA = colorTemperature(blobs[a.offset].color)
            let tempB = colorTemperature(blobs[b.offset].color)
            return tempA < tempB
        }.map { $0.element }

        for blob in sortedBlobs {
            let t = time * blob.speed + blob.phase
            let orbitT = time * blob.orbitSpeed + blob.phase

            // Organic motion - each blob orbits its base position with added undulation
            let orbitX = cos(orbitT) * blob.orbitRadius * scale
            let orbitY = sin(orbitT) * blob.orbitRadius * scale * 0.7 // Flattened for perspective

            // Additional organic undulation
            let undulationX = sin(t * 1.3) * 2.0 * scale + cos(t * 0.7) * 1.5 * scale
            let undulationY = cos(t * 1.1) * 2.5 * scale * 0.7 + sin(t * 0.9) * 1.2 * scale

            let position = CGPoint(
                x: center.x + (blob.baseX + orbitX + undulationX) * scale,
                y: center.y + (blob.baseY + orbitY + undulationY) * scale
            )

            // Radius pulse for breathing effect
            let radiusPulse = 1.0 + 0.06 * sin(t * 2.2) + 0.03 * cos(t * 3.5)
            let radius = blob.baseRadius * scale * radiusPulse

            // Draw soft-edged blob for metaball fusion effect
            // Use many concentric circles with decreasing opacity for soft edge
            let steps = 12
            for i in stride(from: steps, through: 0, by: -1) {
                let progress = CGFloat(i) / CGFloat(steps)
                let r = radius * (0.85 + 0.5 * progress) // Extend beyond radius for soft falloff
                let opacity = blob.intensity * (1.0 - progress * 0.92) * 0.35

                let rect = CGRect(
                    x: position.x - r,
                    y: position.y - r,
                    width: r * 2,
                    height: r * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(blob.color.opacity(Double(opacity))))
            }

            // Inner bright core for each blob
            let coreRect = CGRect(
                x: position.x - radius * 0.5,
                y: position.y - radius * 0.5,
                width: radius,
                height: radius
            )
            context.fill(Path(ellipseIn: coreRect), with: .color(blob.color.opacity(Double(blob.intensity * 0.7))))
        }

    }

    private func colorTemperature(_ color: Color) -> CGFloat {
        // Approximate temperature based on color characteristics
        // Yellow/orange = hot (high value), purple/blue = cool (low value)
        // Since we can't easily extract RGB from SwiftUI Color in a canvas context,
        // we'll use brightness as a proxy for temperature
        return 0.5 // Neutral default - rely on order in array instead
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
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled ? NeoCodeTheme.warning : NeoCodeTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
    @Binding var selectionRequest: ComposerTextSelectionRequest?
    let projectPath: String?
    let onPrimaryAction: () -> Void
    let onConfirmAuxiliarySelection: () -> Bool
    let onMoveAuxiliarySelection: (Int) -> Bool
    let onCancelAuxiliaryUI: () -> Bool
    let allowsEmptyPrimaryAction: Bool
    let onImportAttachments: ([ComposerAttachmentImportItem]) -> Void

    private let minimumHeight: CGFloat = ComposerLayout.minimumTextViewHeight
    private let maximumHeight: CGFloat = 140

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ComposerNSTextView()
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
        textView.onImportAttachments = onImportAttachments
        textView.onConfirmAuxiliarySelection = onConfirmAuxiliarySelection
        textView.onMoveAuxiliarySelection = onMoveAuxiliarySelection
        textView.onCancelAuxiliaryUI = onCancelAuxiliaryUI
        textView.projectPath = projectPath

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }
        if textView.string != text {
            textView.string = text

            if text.isEmpty {
                textView.scheduleFileMentionHighlightUpdate()
                context.coordinator.updateMeasuredHeight(minimumHeight)
                return
            }
        }
        textView.onImportAttachments = onImportAttachments
        textView.onConfirmAuxiliarySelection = onConfirmAuxiliarySelection
        textView.onMoveAuxiliarySelection = onMoveAuxiliarySelection
        textView.onCancelAuxiliaryUI = onCancelAuxiliaryUI
        textView.projectPath = projectPath

        if let selectionRequest, context.coordinator.lastSelectionRequestID != selectionRequest.id {
            context.coordinator.lastSelectionRequestID = selectionRequest.id
            textView.string = selectionRequest.text
            textView.setSelectedRange(NSRange(location: selectionRequest.cursorLocation, length: 0))
            textView.window?.makeFirstResponder(textView)

            DispatchQueue.main.async {
                self.selectionRequest = nil
            }
        }

        textView.scheduleFileMentionHighlightUpdate()

        context.coordinator.recalculateHeight(for: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView
        var lastSelectionRequestID: UUID?

        init(_ parent: GrowingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight(for: textView)

            if let composerTextView = textView as? ComposerNSTextView {
                composerTextView.scheduleFileMentionHighlightUpdate()
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                return parent.onMoveAuxiliarySelection(-1)
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                return parent.onMoveAuxiliarySelection(1)
            }

            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return parent.onConfirmAuxiliarySelection()
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                return parent.onCancelAuxiliaryUI()
            }

            let insertsNewline = commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertLineBreak(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))

            guard insertsNewline else { return false }

            let shiftPressed = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            if shiftPressed {
                return false
            }

            if parent.onConfirmAuxiliarySelection() {
                return true
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

private final class ComposerNSTextView: NSTextView {
    var onImportAttachments: (([ComposerAttachmentImportItem]) -> Void)?
    var onConfirmAuxiliarySelection: (() -> Bool)?
    var onMoveAuxiliarySelection: ((Int) -> Bool)?
    var onCancelAuxiliaryUI: (() -> Bool)?
    var projectPath: String?

    private var mentionHighlightTask: Task<Void, Never>?
    private var promotedFileMentionSourceTexts: [ComposerPromptFileReference.SourceText] = []
    private lazy var mentionHighlightAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor(NeoCodeTheme.accent),
        .backgroundColor: NSColor(NeoCodeTheme.accentDim).withAlphaComponent(0.42),
        .underlineStyle: NSUnderlineStyle.single.rawValue,
        .underlineColor: NSColor(NeoCodeTheme.accent).withAlphaComponent(0.85)
    ]

    deinit {
        mentionHighlightTask?.cancel()
    }

    override func paste(_ sender: Any?) {
        let items = composerAttachmentItems(from: .general)
        if !items.isEmpty {
            onImportAttachments?(items)
            return
        }

        super.paste(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        if deletePromotedFileMentionIfNeeded() {
            return
        }

        super.deleteBackward(sender)
    }

    func scheduleFileMentionHighlightUpdate() {
        mentionHighlightTask?.cancel()

        let textSnapshot = string
        let projectPathSnapshot = projectPath
        applyFileMentionHighlights([])

        guard let projectPathSnapshot,
              !textSnapshot.isEmpty
        else {
            return
        }

        mentionHighlightTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }

            let references = await ProjectFileSearchService.shared.resolveFileReferences(
                in: projectPathSnapshot,
                text: textSnapshot
            )
            let sourceTexts = references.map(\.sourceText)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      self.string == textSnapshot,
                      self.projectPath == projectPathSnapshot
                else {
                    return
                }

                self.applyFileMentionHighlights(sourceTexts)
            }
        }
    }

    private func applyFileMentionHighlights(_ sourceTexts: [ComposerPromptFileReference.SourceText]) {
        guard let layoutManager else { return }

        promotedFileMentionSourceTexts = sourceTexts

        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: fullRange)

        for sourceText in sourceTexts {
            let range = NSRange(location: sourceText.start, length: sourceText.end - sourceText.start)
            guard range.location >= 0, NSMaxRange(range) <= fullRange.length else { continue }
            layoutManager.addTemporaryAttributes(mentionHighlightAttributes, forCharacterRange: range)
        }
    }

    private func deletePromotedFileMentionIfNeeded() -> Bool {
        guard selectedRange.length == 0,
              let deletionRange = ComposerPromptFileReferenceDeletion.backwardDeleteRange(
                in: string,
                sourceTexts: promotedFileMentionSourceTexts,
                cursorLocation: selectedRange.location
              )
        else {
            return false
        }

        guard shouldChangeText(in: deletionRange, replacementString: "") else {
            return true
        }

        textStorage?.replaceCharacters(in: deletionRange, with: "")
        didChangeText()
        setSelectedRange(NSRange(location: deletionRange.location, length: 0))
        scheduleFileMentionHighlightUpdate()
        return true
    }

    private func composerAttachmentItems(from pasteboard: NSPasteboard) -> [ComposerAttachmentImportItem] {
        let fileURLs = composerFileURLs(from: pasteboard)
        let orderedFileURLs = fileURLs.sorted { lhs, rhs in
            isImageFileURL(lhs) && !isImageFileURL(rhs)
        }

        if !orderedFileURLs.isEmpty {
            return orderedFileURLs.map(ComposerAttachmentImportItem.fileURL)
        }

        if let imageData = pasteboard.data(forType: .png) {
            return [.imageData(imageData, filename: "Pasted Image.png", mimeType: "image/png")]
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let tiffRepresentation = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffRepresentation),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return [.imageData(pngData, filename: "Pasted Image.png", mimeType: "image/png")]
        }

        return []
    }

    private func composerFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    private func isImageFileURL(_ url: URL) -> Bool {
        let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let contentType = (try? resolvedURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: resolvedURL.pathExtension)
        return contentType?.preferredMIMEType?.lowercased().hasPrefix("image/") == true
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

struct ComposerDropdownOption: Identifiable, Hashable {
    let id: String
    let title: String
}

struct ComposerAttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    var body: some View {
        Group {
            if attachment.isImage {
                ComposerImageAttachmentChip(attachment: attachment, onRemove: onRemove)
            } else {
                ComposerFileAttachmentChip(attachment: attachment, onRemove: onRemove)
            }
        }
    }
}

private struct ComposerFileAttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "paperclip")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NeoCodeTheme.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .lineLimit(1)

                Text(attachment.mimeType)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NeoCodeTheme.textMuted)
                    .lineLimit(1)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NeoCodeTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(NeoCodeTheme.panelSoft)
                .overlay(Capsule().stroke(NeoCodeTheme.line, lineWidth: 1))
        )
    }
}

private struct ComposerImageAttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void
    @State private var isHovering = false

    private let previewWidth: CGFloat = 80
    private let previewHeight: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Group {
                    if let image = composerAttachmentImage(for: attachment) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(NeoCodeTheme.panelSoft)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(NeoCodeTheme.textMuted)
                            }
                    }
                }
                .frame(width: previewWidth, height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if isHovering {
                    Button(action: onRemove) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.88))
                            .overlay {
                                VStack(spacing: 6) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 18, weight: .semibold))
                                    Text("Remove")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(Color.white)
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(width: previewWidth, height: previewHeight)
                    .help("Remove attachment")
                    .accessibilityLabel("Remove attachment")
                    .transition(.opacity)
                }
            }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.14), value: isHovering)

            Text(attachment.name)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .lineLimit(1)
                .frame(width: previewWidth, alignment: .leading)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(NeoCodeTheme.panelSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }
}

private func composerAttachmentImage(for attachment: ComposerAttachment) -> NSImage? {
    ComposerAttachmentImageCache.image(for: attachment) {
        switch attachment.content {
        case .file(let path):
            return NSImage(contentsOfFile: path)
        case .dataURL(let dataURL):
            guard let data = data(fromDataURL: dataURL) else { return nil }
            return NSImage(data: data)
        }
    }
}

private func data(fromDataURL dataURL: String) -> Data? {
    guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
    let encoded = String(dataURL[dataURL.index(after: commaIndex)...])
    return Data(base64Encoded: encoded)
}

private enum ComposerAttachmentImageCache {
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        return cache
    }()

    private static let failedLookupCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 128
        return cache
    }()

    static func image(for attachment: ComposerAttachment, loader: () -> NSImage?) -> NSImage? {
        let key = cacheKey(for: attachment)

        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        if failedLookupCache.object(forKey: key) != nil {
            return nil
        }

        guard let image = loader() else {
            failedLookupCache.setObject(NSNumber(value: true), forKey: key)
            return nil
        }

        imageCache.setObject(image, forKey: key)
        return image
    }

    private static func cacheKey(for attachment: ComposerAttachment) -> NSString {
        var hasher = Hasher()
        hasher.combine(attachment.name)
        hasher.combine(attachment.mimeType)
        hasher.combine(attachment.deduplicationKey)
        return NSString(string: String(hasher.finalize()))
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
            MetaballOrb(size: 88)

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
