import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsSidebarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowDragRegion()
                .frame(height: 52)

            VStack(alignment: .leading, spacing: 18) {
                Button(action: store.closeSettings) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                        Text(localized("Back", locale: locale))
                            .font(.neoAction)
                    }
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(NeoCodeTheme.panelSoft)
                    )
                }
                .buttonStyle(.plain)
                .neoTooltip(localized("Back to workspace", locale: locale))

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(AppSettingsSection.allCases) { section in
                        SidebarActionButton(
                            label: section.title(locale: locale),
                            systemImage: section.systemImage,
                            isSelected: store.selectedSettingsSection == section,
                            action: { store.selectSettingsSection(section) }
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

struct SettingsScreen: View {
    @Environment(AppStore.self) private var store
    let section: AppSettingsSection

    private var shellShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeaderView(section: section)
                .zIndex(50)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch section {
                    case .general:
                        GeneralSettingsView()
                    case .updates:
                        UpdatesSettingsView()
                    case .appearance:
                        AppearanceSettingsView()
                    }
                }
                .frame(maxWidth: 960, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .background {
            shellShape
                .fill(NeoCodeTheme.panel)
                .overlay {
                    shellShape.stroke(NeoCodeTheme.line, lineWidth: 1)
                }
                .id(store.appSettings.appearance)
        }
    }
}

private struct SettingsHeaderView: View {
    @Environment(\.locale) private var locale
    let section: AppSettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title(locale: locale))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(NeoCodeTheme.textPrimary)

            Text(section.subtitle(locale: locale))
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(WindowDragRegion())
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale
    @State private var workspaceToolOptions: [WorkspaceToolSettingsOption] = [.autoDetect]

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
                            .frame(width: 240)
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
            refreshWorkspaceToolOptions()
        }
    }

    private var selectedWorkspaceToolOptionID: String {
        store.appSettings.general.defaultWorkspaceToolID ?? Self.autoDetectToolID
    }

    private var selectedWorkspaceToolOption: WorkspaceToolSettingsOption {
        workspaceToolOptions.first(where: { $0.id == selectedWorkspaceToolOptionID }) ?? .autoDetect
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

private struct AppearanceSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.locale) private var locale
    @State private var importTarget: ThemeProfileKind?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(
                title: localized("Theme", locale: locale),
                detail: localized("Pick a presentation mode, then tune the light and dark palettes independently.", locale: locale)
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    Picker(localized("Theme", locale: locale), selection: appearanceBinding(\.themeMode)) {
                        ForEach(NeoCodeThemeMode.allCases) { mode in
                            Label(mode.title(locale: locale), systemImage: mode.symbolName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    AppearanceThemePreview(
                        lightTheme: store.appSettings.appearance.lightTheme,
                        darkTheme: store.appSettings.appearance.darkTheme
                    )
                }
            }

            VStack(spacing: 16) {
                AppearanceThemeEditorCard(
                    title: localized("Light theme", locale: locale),
                    subtitle: localized("Warm daylight palette for your brighter workspace.", locale: locale),
                    profile: profileBinding(.light),
                    selectedPreset: selectedPreset(for: .light),
                    presets: NeoCodeThemePresetCatalog.presets(for: .light),
                    onImport: { importTarget = .light },
                    onCopy: { copyTheme(kind: .light) },
                    onSelectPreset: { applyPreset($0, kind: .light) }
                )

                AppearanceThemeEditorCard(
                    title: localized("Dark theme", locale: locale),
                    subtitle: localized("Low-glare palette for the main NeoCode shell.", locale: locale),
                    profile: profileBinding(.dark),
                    selectedPreset: selectedPreset(for: .dark),
                    presets: NeoCodeThemePresetCatalog.presets(for: .dark),
                    onImport: { importTarget = .dark },
                    onCopy: { copyTheme(kind: .dark) },
                    onSelectPreset: { applyPreset($0, kind: .dark) }
                )
            }

            SettingsCard(
                title: localized("Interface", locale: locale),
                detail: localized("Adjust cursor behavior and base sizing. Font families now live with each theme profile above.", locale: locale)
            ) {
                VStack(spacing: 0) {
                    SettingsControlRow(
                        title: localized("Use pointer cursors", locale: locale),
                        detail: localized("Prefer arrow-to-hand pointer transitions over the default app cursor.", locale: locale),
                        accessory: {
                            Toggle(localized("Use pointer cursors", locale: locale), isOn: appearanceBinding(\.usesPointerCursor))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("UI font size", locale: locale),
                        detail: localized("Changes the base size used across labels, headers, and controls.", locale: locale),
                        accessory: {
                            SettingsStepperControl(
                                value: appearanceBinding(\.uiFontSize),
                                range: NeoCodeAppearanceSettings.minimumUIFontSize...NeoCodeAppearanceSettings.maximumUIFontSize
                            )
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: localized("Code font size", locale: locale),
                        detail: localized("Changes transcript, diff, and code-preview sizing throughout the app.", locale: locale),
                        accessory: {
                            SettingsStepperControl(
                                value: appearanceBinding(\.codeFontSize),
                                range: NeoCodeAppearanceSettings.minimumCodeFontSize...NeoCodeAppearanceSettings.maximumCodeFontSize
                            )
                        }
                    )
                }
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .tint(NeoCodeTheme.accent)
        .fileImporter(
            isPresented: Binding(
                get: { importTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        importTarget = nil
                    }
                }
            ),
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private func appearanceBinding<Value>(_ keyPath: WritableKeyPath<NeoCodeAppearanceSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.appSettings.appearance[keyPath: keyPath] },
            set: { newValue in
                store.updateAppearance { appearance in
                    appearance[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func profileBinding(_ kind: ThemeProfileKind) -> Binding<NeoCodeThemeProfile> {
        Binding(
            get: {
                switch kind {
                case .light:
                    return store.appSettings.appearance.lightTheme
                case .dark:
                    return store.appSettings.appearance.darkTheme
                }
            },
            set: { newProfile in
                store.updateAppearance { appearance in
                    switch kind {
                    case .light:
                        appearance.lightTheme = newProfile
                    case .dark:
                        appearance.darkTheme = newProfile
                    }
                }
            }
        )
    }

    private func selectedPreset(for kind: ThemeProfileKind) -> NeoCodeThemePreset? {
        guard let presetID = store.appSettings.appearance.selectedPresetID(for: kind) else { return nil }
        return NeoCodeThemePresetCatalog.presets.first(where: { $0.id == presetID && $0.theme(for: kind) != nil })
    }

    private func applyPreset(_ preset: NeoCodeThemePreset, kind: ThemeProfileKind) {
        store.updateAppearance { appearance in
            appearance.applyPreset(preset, kind: kind)
        }
    }

    private func copyTheme(kind: ThemeProfileKind) {
        let profile: NeoCodeThemeProfile
        let name: String?

        switch kind {
        case .light:
            profile = store.appSettings.appearance.lightTheme
            name = selectedPreset(for: .light)?.title
        case .dark:
            profile = store.appSettings.appearance.darkTheme
            name = selectedPreset(for: .dark)?.title
        }

        let payload = NeoCodeThemeProfileTransfer(profile: profile, name: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8)
        else {
            store.lastError = localized("Could not serialize the theme as JSON.", locale: locale)
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        store.lastError = nil
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let kind = importTarget else { return }
        defer { importTarget = nil }

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            do {
                let data = try Data(contentsOf: url)
                let payload = try JSONDecoder().decode(NeoCodeThemeProfileTransfer.self, from: data)
                store.updateAppearance { appearance in
                    switch kind {
                    case .light:
                        appearance.lightTheme = payload.profile
                    case .dark:
                        appearance.darkTheme = payload.profile
                    }
                }
                store.lastError = nil
            } catch {
                store.lastError = localized("Could not import theme JSON.", locale: locale)
            }
        case .failure:
            break
        }
    }
}

private struct AppearanceThemePreview: View {
    @Environment(\.locale) private var locale
    let lightTheme: NeoCodeThemeProfile
    let darkTheme: NeoCodeThemeProfile

    var body: some View {
        HStack(spacing: 0) {
            AppearancePreviewPane(title: localized("Light", locale: locale), profile: lightTheme, isDark: false)
            Divider()
                .overlay(NeoCodeTheme.line)
            AppearancePreviewPane(title: localized("Dark", locale: locale), profile: darkTheme, isDark: true)
        }
        .frame(minHeight: 184)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NeoCodeTheme.line, lineWidth: 1)
        )
    }
}

private struct AppearancePreviewPane: View {
    let title: String
    let profile: NeoCodeThemeProfile
    let isDark: Bool

    private var uiFontTitle: String {
        NeoCodeFontCatalog.displayName(for: profile.uiFontName, preferFixedPitch: false)
    }

    private var codeFontTitle: String {
        NeoCodeFontCatalog.displayName(for: profile.codeFontName, preferFixedPitch: true)
    }

    var body: some View {
        let background = Color(neoHex: profile.backgroundHex) ?? (isDark ? Color.black : Color.white)
        let foreground = Color(neoHex: profile.foregroundHex) ?? (isDark ? Color.white : Color.black)
        let accent = Color(neoHex: profile.accentHex) ?? NeoCodeTheme.accent

        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.neoMeta)
                .foregroundStyle(foreground.opacity(0.72))

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "const theme = {")
                Text(verbatim: "  accent: \"\(profile.accentHex.uppercased())\",")
                    .foregroundStyle(accent)
                Text(verbatim: "  background: \"\(profile.backgroundHex.uppercased())\",")
                Text(verbatim: "  uiFont: \"\(uiFontTitle)\",")
                Text(verbatim: "  codeFont: \"\(codeFontTitle)\",")
                Text(verbatim: "  contrast: \(Int(profile.contrast))")
                    .foregroundStyle(foreground.opacity(0.8))
                Text(verbatim: "}")
            }
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .foregroundStyle(foreground)

            HStack(spacing: 10) {
                Capsule()
                    .fill(accent)
                    .frame(width: 44, height: 8)

                Capsule()
                    .fill(foreground.opacity(0.18))
                    .frame(width: 72, height: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(background)
    }
}

private struct AppearanceThemeEditorCard: View {
    @Environment(\.locale) private var locale
    let title: String
    let subtitle: String
    @Binding var profile: NeoCodeThemeProfile
    let selectedPreset: NeoCodeThemePreset?
    let presets: [NeoCodeThemePreset]
    let onImport: () -> Void
    let onCopy: () -> Void
    let onSelectPreset: (NeoCodeThemePreset) -> Void

    var body: some View {
        SettingsCard(
            title: title,
            detail: subtitle,
            headerAccessory: {
                AnyView(
                    HStack(spacing: 10) {
                        SettingsCardActionButton(title: localized("Import", locale: locale), action: onImport)
                        SettingsCardActionButton(title: localized("Copy theme", locale: locale), action: onCopy)
                        ThemePresetPicker(
                            selectedPreset: selectedPreset,
                            presets: presets,
                            onSelectPreset: onSelectPreset
                        )
                    }
                )
            }
        ) {
            VStack(spacing: 0) {
                SettingsControlRow(
                    title: localized("Accent", locale: locale),
                    detail: localized("Primary tint used for controls, highlights, and actions.", locale: locale),
                    accessory: {
                        HexColorField(text: $profile.accentHex)
                    }
                )

                SettingsDivider()

                SettingsControlRow(
                    title: localized("Background", locale: locale),
                    detail: localized("Base surface color used to build canvas, panels, and cards.", locale: locale),
                    accessory: {
                        HexColorField(text: $profile.backgroundHex)
                    }
                )

                SettingsDivider()

                SettingsControlRow(
                    title: localized("Foreground", locale: locale),
                    detail: localized("Primary text tone for readable content across the shell.", locale: locale),
                    accessory: {
                        HexColorField(text: $profile.foregroundHex)
                    }
                )

                SettingsDivider()

                SettingsControlRow(
                    title: localized("Contrast", locale: locale),
                    detail: localized("Adjusts separation between surfaces, borders, and low-emphasis text.", locale: locale),
                    accessory: {
                        HStack(spacing: 12) {
                            Slider(value: $profile.contrast, in: 20...80, step: 1)
                                .frame(width: 160)
                            Text("\(Int(profile.contrast))")
                                .font(.neoMono)
                                .foregroundStyle(NeoCodeTheme.textSecondary)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                )

                SettingsDivider()

                SettingsControlRow(
                    title: localized("UI font", locale: locale),
                    detail: localized("Used for labels, navigation, settings, and conversation chrome in this theme.", locale: locale),
                    accessory: {
                        SettingsFontPicker(
                            title: NeoCodeFontCatalog.displayName(for: profile.uiFontName, preferFixedPitch: false),
                            selectedID: profile.uiFontName,
                            options: NeoCodeFontCatalog.uiOptions(includingSelected: profile.uiFontName),
                            emptyMessage: localized("No fonts found.", locale: locale),
                            placeholder: localized("Search UI fonts", locale: locale)
                        ) { option in
                            profile.uiFontName = option.id
                        }
                    }
                )

                SettingsDivider()

                SettingsControlRow(
                    title: localized("Code font", locale: locale),
                    detail: localized("Used for transcript code, diffs, file references, and inline code in this theme.", locale: locale),
                    accessory: {
                        SettingsFontPicker(
                            title: NeoCodeFontCatalog.displayName(for: profile.codeFontName, preferFixedPitch: true),
                            selectedID: profile.codeFontName,
                            options: NeoCodeFontCatalog.codeOptions(includingSelected: profile.codeFontName),
                            emptyMessage: localized("No monospaced fonts found.", locale: locale),
                            placeholder: localized("Search code fonts", locale: locale)
                        ) { option in
                            profile.codeFontName = option.id
                        }
                    }
                )
            }
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let detail: String
    let headerAccessory: (() -> AnyView)?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        detail: String,
        headerAccessory: (() -> AnyView)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.headerAccessory = headerAccessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(NeoCodeTheme.textPrimary)

                    Text(detail)
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if let headerAccessory {
                    headerAccessory()
                }
            }

            content()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }
}

struct SettingsControlRow<Accessory: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.neoAction)
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text(detail)
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory()
                .frame(minWidth: 190, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(NeoCodeTheme.line)
            .frame(height: 1)
            .padding(.vertical, 16)
    }
}

private struct SettingsFontPicker: View {
    let title: String
    let selectedID: String
    let options: [NeoCodeFontOption]
    let emptyMessage: String
    let placeholder: String
    let onSelect: (NeoCodeFontOption) -> Void

    var body: some View {
        NeoCodeSelect(
            title: title,
            selectedID: selectedID,
            items: options,
            emptyMessage: emptyMessage,
            placeholder: placeholder,
            isSearchable: true,
            direction: .down,
            menuWidth: 280,
            showsSelectionIndicator: false
        ) { option in
            Text(option.title)
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .lineLimit(1)
        } searchableText: { option in
            [option.title, option.id]
        } onSelect: { option in
            onSelect(option)
        }
        .frame(width: 190, alignment: .trailing)
    }
}

private struct SettingsStepperControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 10) {
            SettingsStepperValue(value: value)

            Stepper("", value: $value, in: range, step: 1)
                .labelsHidden()
                .fixedSize()
        }
    }
}

private struct HexColorField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(neoHex: text) ?? NeoCodeTheme.panelSoft)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(NeoCodeTheme.line, lineWidth: 1))

            TextField("#000000", text: normalizedBinding)
                .neoWritingToolsDisabled()
                .textFieldStyle(.plain)
                .font(.neoMono)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .frame(width: 92)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(NeoCodeTheme.panelSoft)
                .overlay(Capsule().stroke(NeoCodeTheme.line, lineWidth: 1))
        )
    }

    private var normalizedBinding: Binding<String> {
        Binding(
            get: { text.uppercased() },
            set: { newValue in
                let filtered = newValue
                    .uppercased()
                    .filter { $0.isHexDigit || $0 == "#" }
                let trimmed = String(filtered.prefix(7))
                if trimmed.hasPrefix("#") {
                    text = trimmed
                } else if trimmed.isEmpty {
                    text = ""
                } else {
                    text = "#\(String(trimmed.prefix(6)))"
                }
            }
        )
    }
}

private struct SettingsTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.neoMono)
            .foregroundStyle(NeoCodeTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(NeoCodeTheme.panelSoft)
                    .overlay(Capsule().stroke(NeoCodeTheme.line, lineWidth: 1))
            )
    }
}

private struct SettingsStepperValue: View {
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text("\(Int(value))")
                .font(.neoMono)
                .foregroundStyle(NeoCodeTheme.textPrimary)
            Text("px")
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(NeoCodeTheme.panelSoft)
                .overlay(Capsule().stroke(NeoCodeTheme.line, lineWidth: 1))
        )
    }
}

private struct SettingsCardActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.neoAction)
            .foregroundStyle(NeoCodeTheme.textSecondary)
    }
}

private struct ThemePresetPicker: View {
    @Environment(\.locale) private var locale
    let selectedPreset: NeoCodeThemePreset?
    let presets: [NeoCodeThemePreset]
    let onSelectPreset: (NeoCodeThemePreset) -> Void

    @State private var isPresented = false

    private let menuMaxHeight: CGFloat = 320

    private var triggerTitle: String {
        selectedPreset?.title ?? localized("Custom", locale: locale)
    }

    var body: some View {
        Button(action: toggleMenu) {
            FixedWidthDropdownTriggerLabel(title: triggerTitle, isPresented: isPresented, width: 120) {
                ThemePresetBadgeView(preset: selectedPreset)
            }
        }
        .buttonStyle(.plain)
        .background {
            AnchoredFloatingPanelPresenter(isPresented: isPresented, direction: .down, onDismiss: closeMenu) {
                DropdownMenuSurface(width: 220) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(presets) { preset in
                                DropdownMenuRow(isSelected: preset.id == selectedPreset?.id, action: {
                                    onSelectPreset(preset)
                                    closeMenu()
                                }) {
                                    HStack(spacing: 10) {
                                        ThemePresetBadgeView(preset: preset)
                                        Text(preset.title)
                                            .font(.neoAction)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: menuMaxHeight)
                }
            }
        }
    }

    private func toggleMenu() {
        isPresented.toggle()
    }

    private func closeMenu() {
        isPresented = false
    }
}

private struct ThemePresetBadgeView: View {
    let preset: NeoCodeThemePreset?

    var body: some View {
        let background = Color(neoHex: preset?.badgeBackgroundHex ?? "#ECECEC") ?? NeoCodeTheme.panelSoft
        let foreground = Color(neoHex: preset?.badgeForegroundHex ?? "#4A4A4A") ?? NeoCodeTheme.textPrimary

        Text(preset?.badgeText ?? "Aa")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .frame(width: 20, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background)
            )
    }
}

private struct FixedWidthDropdownTriggerLabel<Leading: View>: View {
    let title: String
    let isPresented: Bool
    let width: CGFloat
    @ViewBuilder let leading: () -> Leading

    var body: some View {
        HStack(spacing: 8) {
            leading()

            Text(title)
                .font(.neoAction)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .rotationEffect(.degrees(isPresented ? 180 : 0))
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isPresented ? NeoCodeTheme.panelSoft : NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isPresented ? NeoCodeTheme.lineStrong : NeoCodeTheme.line, lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.16), value: isPresented)
    }
}
