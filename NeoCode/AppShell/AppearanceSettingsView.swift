import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppearanceSettingsView: View {
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
                Text(verbatim: "  sidebar: \"\(profile.isSidebarTranslucent ? "translucent" : "solid")\",")
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
                    title: localized("Translucent Sidebar", locale: locale),
                    detail: localized("Keeps the sidebar itself clear and makes the app background subtly translucent for this theme.", locale: locale),
                    accessory: {
                        Toggle(localized("Translucent Sidebar", locale: locale), isOn: $profile.isSidebarTranslucent)
                            .labelsHidden()
                            .toggleStyle(.switch)
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
