import SwiftUI

struct UpdatesSettingsView: View {
    @Environment(AppUpdateService.self) private var updateService
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(
                title: localized("Sparkle delivery", locale: locale),
                detail: localized("NeoCode checks signed GitHub releases in the background and surfaces new versions in the titlebar instead of interrupting your flow with a modal window.", locale: locale)
            ) {
                VStack(spacing: 0) {
                    SettingsControlRow(
                        title: localized("Current version", locale: locale),
                        detail: localized("The build currently running on this Mac.", locale: locale),
                        accessory: {
                            Text(updateService.installedVersionDescription)
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.textPrimary)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("Automatic checks", locale: locale),
                        detail: localized("Let Sparkle keep an eye on the release feed and raise the blue titlebar control when a newer signed build appears.", locale: locale),
                        accessory: {
                            Toggle(localized("Automatic checks", locale: locale), isOn: automaticChecksBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(!updateService.isAvailableInThisBuild)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: "Status",
                        detail: updateService.statusDetail,
                        accessory: {
                            UpdateStatusChip(phase: updateService.phase)
                        }
                    )

                    if let availableVersionDescription = updateService.availableVersionDescription {
                        SettingsDivider()

                        SettingsControlRow(
                            title: localized("Available version", locale: locale),
                            detail: localized("The newest signed release Sparkle has found for this channel.", locale: locale),
                            accessory: {
                                Text(availableVersionDescription)
                                    .font(.neoMonoSmall)
                                    .foregroundStyle(NeoCodeTheme.textPrimary)
                            }
                        )
                    }

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("Last checked", locale: locale),
                        detail: localized("The most recent time this Mac finished talking to the release feed.", locale: locale),
                        accessory: {
                            Text(lastCheckedDescription)
                                .font(.neoMeta)
                                .foregroundStyle(NeoCodeTheme.textSecondary)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("Check manually", locale: locale),
                        detail: localized("Ask Sparkle to validate the newest available release right now.", locale: locale),
                        accessory: {
                            Button(updateService.manualCheckButtonTitle) {
                                updateService.checkForUpdates()
                            }
                            .buttonStyle(.plain)
                            .disabled(!updateService.canCheckForUpdates)
                            .modifier(SettingsAccessoryButtonStyle(isDisabled: !updateService.canCheckForUpdates))
                        }
                    )

                    if let primaryActionTitle = updateService.primaryActionTitle {
                        SettingsDivider()

                        SettingsControlRow(
                            title: localized("Apply available update", locale: locale),
                            detail: localized("Download the new build now or finish installing the copy Sparkle has already staged.", locale: locale),
                            accessory: {
                                Button(primaryActionTitle) {
                                    updateService.performPrimaryAction()
                                }
                                .buttonStyle(.plain)
                                .disabled(!updateService.canPerformPrimaryAction)
                                .modifier(SettingsAccessoryButtonStyle(isDisabled: !updateService.canPerformPrimaryAction))
                            }
                        )
                    }
                }
            }
        }
    }

    private var automaticChecksBinding: Binding<Bool> {
        Binding(
            get: { updateService.automaticallyChecksForUpdates },
            set: { updateService.automaticallyChecksForUpdates = $0 }
        )
    }

    private var lastCheckedDescription: String {
        guard let lastCheckedAt = updateService.lastCheckedAt else {
            return localized("Never", locale: locale)
        }

        return lastCheckedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

struct WindowTitlebarUpdateButton: View {
    @Environment(AppUpdateService.self) private var updateService
    @State private var isHovering = false
    @State private var isPulsing = false

    private let blue = Color(red: 0.23, green: 0.50, blue: 0.95)
    private let blueHighlight = Color(red: 0.36, green: 0.61, blue: 0.98)

    private static let compactSize: CGFloat = 14
    private static let expandedHeight: CGFloat = 16
    private static let containerWidth: CGFloat = 250

    var body: some View {
        Group {
            if let model {
                let isExpanded = expanded(for: model)

                Button(action: updateService.performPrimaryAction) {
                    HStack(spacing: isExpanded ? 7 : 0) {
                        if showsLeadingIndicator(for: model, isExpanded: isExpanded) {
                            indicator(for: model)
                        }

                        if isExpanded {
                            Text(model.label)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.leading, isExpanded ? 8 : 0)
                    .padding(.trailing, isExpanded ? 12 : 0)
                    .frame(
                        width: isExpanded ? nil : Self.compactSize,
                        height: isExpanded ? Self.expandedHeight : Self.compactSize,
                        alignment: .center
                    )
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [blueHighlight, blue],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.75)
                    )
                    .shadow(color: blue.opacity(isExpanded ? 0.28 : 0.4), radius: isExpanded ? 10 : 7, x: 0, y: 1)
                    .scaleEffect(availablePulseScale(for: model, isExpanded: isExpanded))
                    .animation(.snappy(duration: 0.18, extraBounce: 0), value: isExpanded)
                    .animation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true), value: isPulsing)
                }
                .buttonStyle(.plain)
                .disabled(!model.isInteractive)
                .neoTooltip(model.label)
                .frame(width: Self.containerWidth, height: 20, alignment: .leading)
                .onHover { isHovering in
                    withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                        self.isHovering = isHovering
                    }
                }
                .onAppear {
                    updatePulseState(for: model)
                }
                .onChange(of: model.state) { _, _ in
                    updatePulseState(for: model)
                }
                .onChange(of: isHovering) { _, _ in
                    updatePulseState(for: model)
                }
            } else {
                Color.clear
                    .frame(width: 0, height: 0)
            }
        }
    }

    private var model: TitlebarUpdateModel? {
        switch updateService.phase {
        case .available(let release):
            return .init(
                label: "Update available: \(release.displayVersion)",
                state: .available,
                progress: nil,
                isInteractive: updateService.canPerformPrimaryAction,
                collapsesWhenIdle: true
            )
        case .downloading(let progress):
            return .init(
                label: "Downloading: \(percentageString(for: progress.fractionCompleted))",
                state: .progress,
                progress: progress.fractionCompleted ?? 0,
                isInteractive: false,
                collapsesWhenIdle: false
            )
        case .extracting(let progress):
            return .init(
                label: "Preparing: \(percentageString(for: progress.fractionCompleted))",
                state: .progress,
                progress: progress.fractionCompleted ?? 0,
                isInteractive: false,
                collapsesWhenIdle: false
            )
        case .readyToInstall(let release):
            return .init(
                label: "Install update \(release.displayVersion)",
                state: .ready,
                progress: nil,
                isInteractive: updateService.canPerformPrimaryAction,
                collapsesWhenIdle: false
            )
        case .installing(let release):
            return .init(
                label: "Installing \(release.displayVersion)",
                state: .installing,
                progress: nil,
                isInteractive: false,
                collapsesWhenIdle: false
            )
        default:
            return nil
        }
    }

    private func expanded(for model: TitlebarUpdateModel) -> Bool {
        !model.collapsesWhenIdle || isHovering
    }

    private func availablePulseScale(for model: TitlebarUpdateModel, isExpanded: Bool) -> CGFloat {
        guard model.state == .available, !isExpanded else { return 1 }
        return isPulsing ? 1.06 : 0.97
    }

    private func showsLeadingIndicator(for model: TitlebarUpdateModel, isExpanded: Bool) -> Bool {
        switch model.state {
        case .available:
            return isExpanded
        case .progress, .ready, .installing:
            return true
        }
    }

    private func updatePulseState(for model: TitlebarUpdateModel) {
        isPulsing = model.state == .available && !isHovering
    }

    @ViewBuilder
    private func indicator(for model: TitlebarUpdateModel) -> some View {
        switch model.state {
        case .available:
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        case .progress:
            UpdateProgressRing(progress: model.progress ?? 0)
        case .ready:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        case .installing:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func percentageString(for progress: Double?) -> String {
        let normalized = min(max(progress ?? 0, 0), 1)
        return "\(Int((normalized * 100).rounded()))%"
    }
}

private struct UpdateStatusChip: View {
    let phase: AppUpdateService.Phase

    var body: some View {
        Text(label)
            .font(.neoMeta)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(background)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }

    private var label: String {
        switch phase {
        case .unavailable:
            return "Unavailable"
        case .idle:
            return "Idle"
        case .checking:
            return "Checking"
        case .available:
            return "Available"
        case .downloading:
            return "Downloading"
        case .extracting:
            return "Preparing"
        case .readyToInstall:
            return "Ready"
        case .installing:
            return "Installing"
        case .upToDate:
            return "Current"
        case .error:
            return "Error"
        }
    }

    private var background: Color {
        switch phase {
        case .available:
            return Color(red: 0.15, green: 0.31, blue: 0.56).opacity(0.42)
        case .downloading, .extracting:
            return Color(red: 0.12, green: 0.34, blue: 0.52).opacity(0.38)
        case .readyToInstall, .upToDate:
            return Color.green.opacity(0.16)
        case .installing, .checking:
            return NeoCodeTheme.panelSoft
        case .error, .unavailable:
            return Color.red.opacity(0.14)
        case .idle:
            return NeoCodeTheme.panelSoft
        }
    }

    private var border: Color {
        switch phase {
        case .available, .downloading, .extracting:
            return Color(red: 0.29, green: 0.58, blue: 0.96).opacity(0.48)
        case .readyToInstall, .upToDate:
            return NeoCodeTheme.success.opacity(0.45)
        case .error, .unavailable:
            return Color.red.opacity(0.35)
        case .idle, .installing, .checking:
            return NeoCodeTheme.line.opacity(0.8)
        }
    }

    private var foreground: Color {
        switch phase {
        case .available, .downloading, .extracting:
            return Color(red: 0.72, green: 0.86, blue: 1.0)
        case .readyToInstall, .upToDate:
            return NeoCodeTheme.success
        case .error, .unavailable:
            return Color(red: 1.0, green: 0.73, blue: 0.73)
        case .idle, .installing, .checking:
            return NeoCodeTheme.textSecondary
        }
    }
}

private struct SettingsAccessoryButtonStyle: ViewModifier {
    let isDisabled: Bool

    func body(content: Content) -> some View {
        content
            .font(.neoAction)
            .foregroundStyle(isDisabled ? NeoCodeTheme.textMuted : NeoCodeTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(NeoCodeTheme.panelSoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isDisabled ? NeoCodeTheme.lineSoft : NeoCodeTheme.line, lineWidth: 1)
            )
    }
}

private struct UpdateProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.24), lineWidth: 2)

            Circle()
                .trim(from: 0, to: max(progress, 0.04))
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 11, height: 11)
    }
}

private struct TitlebarUpdateModel {
    enum State {
        case available
        case progress
        case ready
        case installing
    }

    let label: String
    let state: State
    let progress: Double?
    let isInteractive: Bool
    let collapsesWhenIdle: Bool
}
