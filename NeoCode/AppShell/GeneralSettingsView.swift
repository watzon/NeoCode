import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime
    @Environment(\.locale) private var locale
    @State private var workspaceToolOptions: [WorkspaceToolSettingsOption] = [.autoDetect]
    @State private var opencodeExecutablePathDraft = ""
    @State private var executablePathValidation: ExecutablePathValidation = .idle
    @State private var executablePathValidationID = 0

    private let workspaceToolService = WorkspaceToolService()
    private static let autoDetectToolID = WorkspaceToolSettingsOption.autoDetectID

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(
                title: localized("Startup & workspace", locale: locale),
                detail: localized("Choose how NeoCode opens and which app should handle projects before a workspace-specific override takes over.", locale: locale)
            ) {
                VStack(spacing: 0) {
                    SettingsControlRow(
                        title: localized("Language", locale: locale),
                        detail: localized("Choose whether NeoCode follows the system language or always uses a specific app language.", locale: locale),
                        accessory: {
                            NeoCodeSelect(
                                title: store.appSettings.general.appLanguage.title(locale: locale),
                                selectedID: store.appSettings.general.appLanguage.id,
                                items: NeoCodeAppLanguage.allCases,
                                emptyMessage: localized("No languages found.", locale: locale),
                                placeholder: localized("Search languages", locale: locale),
                                isSearchable: false,
                                direction: .down,
                                menuWidth: 220,
                                showsSelectionIndicator: false
                            ) { language in
                                Text(language.title(locale: locale))
                                    .font(.neoBody)
                                    .foregroundStyle(NeoCodeTheme.textPrimary)
                                    .lineLimit(1)
                            } searchableText: { language in
                                [language.title(locale: locale), language.id]
                            } onSelect: { language in
                                store.updateGeneral { general in
                                    general.appLanguage = language
                                }
                            }
                            .frame(width: 220, alignment: .trailing)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("On launch", locale: locale),
                        detail: localized("Start on the dashboard or restore the last workspace you were actively using.", locale: locale),
                        accessory: {
                            Picker(localized("On launch", locale: locale), selection: generalBinding(\.startupBehavior)) {
                                ForEach(NeoCodeStartupBehavior.allCases) { behavior in
                                    Text(behavior.title(locale: locale))
                                        .tag(behavior)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("Open project with", locale: locale),
                        detail: localized("Used when a project does not already have its own preferred editor or destination.", locale: locale),
                        accessory: {
                            NeoCodeSelect(
                                title: displayTitle(for: selectedWorkspaceToolOption),
                                selectedID: selectedWorkspaceToolOptionID,
                                items: workspaceToolOptions,
                                emptyMessage: localized("No apps found.", locale: locale),
                                placeholder: localized("Search apps", locale: locale),
                                isSearchable: true,
                                direction: .down,
                                menuWidth: 280,
                                showsSelectionIndicator: false
                            ) { option in
                                WorkspaceToolSettingsOptionLabel(option: option)
                            } searchableText: { option in
                                [displayTitle(for: option), option.id]
                            } onSelect: { option in
                                store.updateGeneral { general in
                                    general.defaultWorkspaceToolID = option.id == Self.autoDetectToolID ? nil : option.id
                                }
                            } triggerLeading: {
                                WorkspaceToolSettingsOptionIcon(option: selectedWorkspaceToolOption)
                            }
                            .frame(width: 220, alignment: .trailing)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("NeoCode server executable", locale: locale),
                        detail: localized("Optionally set the full path to the `neocoded` binary if you want to override NeoCode's managed daemon install. By default NeoCode prefers its app-managed daemon, then falls back to PATH when the versions match.", locale: locale),
                        accessory: {
                            VStack(alignment: .trailing, spacing: 6) {
                                HStack(spacing: 8) {
                                    TextField(
                                        "/Users/you/.local/bin/neocoded",
                                        text: opencodeExecutablePathBinding
                                    )
                                    .neoWritingToolsDisabled()
                                    .textFieldStyle(.plain)
                                    .font(.neoMonoSmall)
                                    .foregroundStyle(NeoCodeTheme.textPrimary)
                                    .frame(width: 240)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(NeoCodeTheme.panelSoft)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .stroke(executablePathValidation.borderColor, lineWidth: 1)
                                            )
                                    )

                                    Button(localized("Browse", locale: locale), action: selectOpenCodeExecutable)
                                        .buttonStyle(.plain)
                                        .font(.neoAction)
                                        .foregroundStyle(NeoCodeTheme.textSecondary)
                                }

                                if let message = executablePathValidation.message(locale: locale) {
                                    Text(message)
                                        .font(.neoMonoSmall)
                                        .foregroundStyle(executablePathValidation.textColor)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 320, alignment: .trailing)
                                }
                            }
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("Managed daemon", locale: locale),
                        detail: runtime.daemonInstallStatus ?? localized("NeoCode automatically downloads the exact matching daemon version when needed. Use this to retry the install manually.", locale: locale),
                        accessory: {
                            Button(localized("Install matching daemon", locale: locale)) {
                                Task {
                                    await runtime.installMatchingDaemon()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.neoAction)
                            .foregroundStyle(NeoCodeTheme.textSecondary)
                        }
                    )
                }
            }

            SettingsCard(
                title: localized("Composer", locale: locale),
                detail: localized("Tune how prompts send and whether NeoCode should keep per-thread drafts waiting for you when you come back.", locale: locale)
            ) {
                VStack(spacing: 0) {
                    SettingsControlRow(
                        title: localized("Send messages with", locale: locale),
                        detail: localized("Choose whether Return sends immediately or only Command-Return sends while Return inserts a newline.", locale: locale),
                        accessory: {
                            Picker(localized("Send messages with", locale: locale), selection: generalBinding(\.sendKeyBehavior)) {
                                ForEach(NeoCodeSendKeyBehavior.allCases) { behavior in
                                    Text(behavior.title(locale: locale))
                                        .tag(behavior)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 240)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("Restore drafts when reopening threads", locale: locale),
                        detail: localized("Keep unfinished prompt text tied to each thread so you can move around the app without losing context.", locale: locale),
                        accessory: {
                            Toggle(localized("Restore drafts when reopening threads", locale: locale), isOn: generalBinding(\.restoresPromptDrafts))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    )
                }
            }

            SettingsCard(
                title: localized("Session autonomy", locale: locale),
                detail: localized("Control whether NeoCode should remember safety-related per-thread behavior between launches.", locale: locale)
            ) {
                SettingsControlRow(
                    title: localized("Remember YOLO mode per thread", locale: locale),
                    detail: localized("Persist YOLO mode for each thread so permission auto-approval comes back the next time you open that workspace.", locale: locale),
                    accessory: {
                        Toggle(localized("Remember YOLO mode per thread", locale: locale), isOn: generalBinding(\.remembersYoloModePerThread))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                )
            }

            SettingsCard(
                title: localized("Power & notifications", locale: locale),
                detail: localized("Keep long-running work alive and optionally notify you when NeoCode finishes or needs your input.", locale: locale)
            ) {
                VStack(spacing: 0) {
                    SettingsControlRow(
                        title: localized("Prevent Mac sleep while responses are running", locale: locale),
                        detail: localized("Ask macOS to keep the system awake while NeoCode is actively processing a response.", locale: locale),
                        accessory: {
                            Toggle(localized("Prevent Mac sleep while responses are running", locale: locale), isOn: generalBinding(\.preventsSystemSleepWhileRunning))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("Notify when a response finishes", locale: locale),
                        detail: localized("Show a macOS notification after a response completes while the app is unfocused.", locale: locale),
                        accessory: {
                            Toggle(localized("Notify when a response finishes", locale: locale), isOn: generalBinding(\.notifiesWhenResponseCompletes))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("Notify when input is required", locale: locale),
                        detail: localized("Show a macOS notification when a permission request or question is waiting for you while NeoCode is unfocused.", locale: locale),
                        accessory: {
                            Toggle(localized("Notify when input is required", locale: locale), isOn: generalBinding(\.notifiesWhenInputIsRequired))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    )
                }
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .task {
            opencodeExecutablePathDraft = store.appSettings.general.opencodeExecutablePath ?? ""
            refreshWorkspaceToolOptions()
        }
    }

    private var selectedWorkspaceToolOptionID: String {
        store.appSettings.general.defaultWorkspaceToolID ?? Self.autoDetectToolID
    }

    private var selectedWorkspaceToolOption: WorkspaceToolSettingsOption {
        workspaceToolOptions.first(where: { $0.id == selectedWorkspaceToolOptionID }) ?? .autoDetect
    }

    private var opencodeExecutablePathBinding: Binding<String> {
        Binding(
            get: { opencodeExecutablePathDraft },
            set: { newValue in
                opencodeExecutablePathDraft = newValue
                validateExecutablePathDraft(newValue)
            }
        )
    }

    private func generalBinding<Value>(_ keyPath: WritableKeyPath<NeoCodeGeneralSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.appSettings.general[keyPath: keyPath] },
            set: { newValue in
                store.updateGeneral { general in
                    general[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func refreshWorkspaceToolOptions() {
        workspaceToolOptions = [.autoDetect] + workspaceToolService.projectOpenTools().map { WorkspaceToolSettingsOption(tool: $0) }
    }

    private func displayTitle(for option: WorkspaceToolSettingsOption) -> String {
        option.id == Self.autoDetectToolID ? localized("Auto detect", locale: locale) : option.title
    }

    private func selectOpenCodeExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.unixExecutable, .data]
        panel.prompt = localized("Choose", locale: locale)
        panel.message = localized("Select the `neocoded` executable NeoCode should launch.", locale: locale)

        if let currentPath = store.appSettings.general.opencodeExecutablePath {
            panel.directoryURL = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
            panel.nameFieldStringValue = URL(fileURLWithPath: currentPath).lastPathComponent
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        opencodeExecutablePathDraft = url.path
        validateExecutablePathDraft(url.path)
    }

    private func validateExecutablePathDraft(_ rawValue: String) {
        let normalized = OpenCodeRuntime.normalizedExecutablePath(rawValue)
        let previousValue = store.appSettings.general.opencodeExecutablePath

        executablePathValidationID += 1
        let validationID = executablePathValidationID

        guard let normalized else {
            store.updateGeneral { general in
                general.opencodeExecutablePath = nil
            }
            executablePathValidation = previousValue == nil ? .idle : .restartRequired
            return
        }

        executablePathValidation = .validating

        Task {
            do {
                try await runtime.validatePreferredExecutablePath(normalized)
                guard validationID == executablePathValidationID else { return }

                store.updateGeneral { general in
                    general.opencodeExecutablePath = normalized
                }
                executablePathValidation = previousValue == normalized ? .idle : .restartRequired
            } catch {
                guard validationID == executablePathValidationID else { return }
                executablePathValidation = .error(error.localizedDescription)
            }
        }
    }
}

private enum ExecutablePathValidation: Equatable {
    case idle
    case validating
    case restartRequired
    case error(String)

    var borderColor: Color {
        switch self {
        case .idle, .validating:
            NeoCodeTheme.line
        case .restartRequired:
            NeoCodeTheme.accent.opacity(0.7)
        case .error:
            NeoCodeTheme.warning.opacity(0.8)
        }
    }

    var textColor: Color {
        switch self {
        case .idle, .validating:
            NeoCodeTheme.textSecondary
        case .restartRequired:
            NeoCodeTheme.accent
        case .error:
            NeoCodeTheme.warning
        }
    }

    func message(locale: Locale) -> String? {
        switch self {
        case .idle:
            nil
        case .validating:
            localized("Validating daemon binary...", locale: locale)
        case .restartRequired:
            localized("Restart NeoCode to apply this daemon path change.", locale: locale)
        case .error(let message):
            message
        }
    }
}

private struct WorkspaceToolSettingsOption: Identifiable, Hashable {
    static let autoDetectID = "__auto__"
    static let autoDetect = WorkspaceToolSettingsOption(
        id: autoDetectID,
        title: "Auto detect",
        tool: nil,
        fallbackSystemImage: "wand.and.stars"
    )

    let id: String
    let title: String
    let tool: WorkspaceTool?
    let fallbackSystemImage: String

    init(tool: WorkspaceTool) {
        id = tool.id
        title = tool.label
        self.tool = tool
        fallbackSystemImage = tool.fallbackSystemImage
    }

    private init(id: String, title: String, tool: WorkspaceTool?, fallbackSystemImage: String) {
        self.id = id
        self.title = title
        self.tool = tool
        self.fallbackSystemImage = fallbackSystemImage
    }
}

private struct WorkspaceToolSettingsOptionLabel: View {
    @Environment(\.locale) private var locale
    let option: WorkspaceToolSettingsOption

    var body: some View {
        HStack(spacing: 10) {
            WorkspaceToolSettingsOptionIcon(option: option)

            Text(option.id == WorkspaceToolSettingsOption.autoDetectID ? localized("Auto detect", locale: locale) : option.title)
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .lineLimit(1)
        }
    }
}

private struct WorkspaceToolSettingsOptionIcon: View {
    let option: WorkspaceToolSettingsOption

    var body: some View {
        Group {
            if let tool = option.tool {
                WorkspaceToolIconView(tool: tool)
            } else {
                Image(systemName: option.fallbackSystemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .frame(width: 16, height: 16)
            }
        }
    }
}
