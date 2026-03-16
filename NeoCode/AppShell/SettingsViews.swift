import SwiftUI

struct SettingsSidebarView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WindowDragRegion()
                .frame(height: 52)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(NeoCodeTheme.textPrimary)

                        Text("Tune NeoCode without leaving the main workspace.")
                            .font(.neoBody)
                            .foregroundStyle(NeoCodeTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Button(action: store.closeSettings) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NeoCodeTheme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(NeoCodeTheme.panelSoft)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Done")
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(AppSettingsSection.allCases) { section in
                        SettingsSidebarButton(
                            section: section,
                            isSelected: store.selectedSettingsSection == section,
                            action: { store.selectSettingsSection(section) }
                        )
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Release Prep")
                        .font(.neoMeta)
                        .foregroundStyle(NeoCodeTheme.textMuted)

                    Text("General and Appearance are wired first so more sections can slot in without reworking the shell.")
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(NeoCodeTheme.panelSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(NeoCodeTheme.line, lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

struct SettingsScreen: View {
    let section: AppSettingsSection

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeaderView(section: section)
                .zIndex(50)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch section {
                    case .general:
                        GeneralSettingsView()
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

private struct SettingsHeaderView: View {
    let section: AppSettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(NeoCodeTheme.textPrimary)

            Text(section.subtitle)
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
    var body: some View {
        SettingsCard(
            title: "General foundation",
            detail: "The shell is ready for app defaults, runtime behavior, and notification preferences next."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("This section is intentionally lightweight for the first release pass.")
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text("Appearance is fully mocked out first, while General keeps the navigation and persistence structure in place for the next follow-up.")
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AppearanceSettingsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard(
                title: "Theme",
                detail: "Pick a presentation mode, then tune the light and dark palettes independently."
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Theme", selection: appearanceBinding(\.themeMode)) {
                        ForEach(NeoCodeThemeMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbolName)
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
                    title: "Light theme",
                    subtitle: "Warm daylight palette for your brighter workspace.",
                    profile: profileBinding(.light)
                )

                AppearanceThemeEditorCard(
                    title: "Dark theme",
                    subtitle: "Low-glare palette for the main NeoCode shell.",
                    profile: profileBinding(.dark)
                )
            }

            SettingsCard(
                title: "Interface",
                detail: "These settings are persisted now and can be hooked into more detailed behavior next."
            ) {
                VStack(spacing: 0) {
                    SettingsControlRow(
                        title: "Use pointer cursors",
                        detail: "Prefer arrow-to-hand pointer transitions over the default app cursor.",
                        accessory: {
                            Toggle("Use pointer cursors", isOn: appearanceBinding(\.usesPointerCursor))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: "UI font",
                        detail: "The display name is saved now so a font picker can be attached later.",
                        accessory: {
                            SettingsTag(text: store.appSettings.appearance.uiFontName)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: "UI font size",
                        detail: "Changes the base size used across labels, headers, and controls.",
                        accessory: {
                            Stepper(value: appearanceBinding(\.uiFontSize), in: NeoCodeAppearanceSettings.minimumUIFontSize...NeoCodeAppearanceSettings.maximumUIFontSize, step: 1) {
                                SettingsStepperValue(value: store.appSettings.appearance.uiFontSize)
                            }
                            .labelsHidden()
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: "Code font",
                        detail: "Stored for the next pass when code-specific font selection becomes configurable.",
                        accessory: {
                            SettingsTag(text: store.appSettings.appearance.codeFontName)
                        }
                    )

                    SettingsDivider()

                    SettingsControlRow(
                        title: "Code font size",
                        detail: "Changes transcript, diff, and code-preview sizing throughout the app.",
                        accessory: {
                            Stepper(value: appearanceBinding(\.codeFontSize), in: NeoCodeAppearanceSettings.minimumCodeFontSize...NeoCodeAppearanceSettings.maximumCodeFontSize, step: 1) {
                                SettingsStepperValue(value: store.appSettings.appearance.codeFontSize)
                            }
                            .labelsHidden()
                        }
                    )
                }
            }
        }
        .tint(NeoCodeTheme.accent)
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
}

private enum ThemeProfileKind {
    case light
    case dark
}

private struct AppearanceThemePreview: View {
    let lightTheme: NeoCodeThemeProfile
    let darkTheme: NeoCodeThemeProfile

    var body: some View {
        HStack(spacing: 0) {
            AppearancePreviewPane(title: "Light", profile: lightTheme, isDark: false)
            Divider()
                .overlay(NeoCodeTheme.line)
            AppearancePreviewPane(title: "Dark", profile: darkTheme, isDark: true)
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

    var body: some View {
        let background = Color(neoHex: profile.backgroundHex) ?? (isDark ? Color.black : Color.white)
        let foreground = Color(neoHex: profile.foregroundHex) ?? (isDark ? Color.white : Color.black)
        let accent = Color(neoHex: profile.accentHex) ?? NeoCodeTheme.accent

        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.neoMeta)
                .foregroundStyle(foreground.opacity(0.72))

            VStack(alignment: .leading, spacing: 6) {
                Text("const theme = {")
                Text("  accent: \"\(profile.accentHex.uppercased())\",")
                    .foregroundStyle(accent)
                Text("  background: \"\(profile.backgroundHex.uppercased())\",")
                Text("  contrast: \(Int(profile.contrast))")
                    .foregroundStyle(foreground.opacity(0.8))
                Text("}")
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
    let title: String
    let subtitle: String
    @Binding var profile: NeoCodeThemeProfile

    var body: some View {
        SettingsCard(title: title, detail: subtitle) {
            VStack(spacing: 0) {
                SettingsControlRow(
                    title: "Accent",
                    detail: "Primary tint used for controls, highlights, and actions.",
                    accessory: {
                        HexColorField(text: $profile.accentHex)
                    }
                )

                SettingsDivider()

                SettingsControlRow(
                    title: "Background",
                    detail: "Base surface color used to build canvas, panels, and cards.",
                    accessory: {
                        HexColorField(text: $profile.backgroundHex)
                    }
                )

                SettingsDivider()

                SettingsControlRow(
                    title: "Foreground",
                    detail: "Primary text tone for readable content across the shell.",
                    accessory: {
                        HexColorField(text: $profile.foregroundHex)
                    }
                )

                SettingsDivider()

                SettingsControlRow(
                    title: "Contrast",
                    detail: "Adjusts separation between surfaces, borders, and low-emphasis text.",
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
            }
        }
    }
}

private struct SettingsSidebarButton: View {
    let section: AppSettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? NeoCodeTheme.accent : NeoCodeTheme.textSecondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.neoAction)
                        .foregroundStyle(isSelected ? NeoCodeTheme.textPrimary : NeoCodeTheme.textSecondary)

                    Text(section.subtitle)
                        .font(.neoMeta)
                        .foregroundStyle(NeoCodeTheme.textMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? NeoCodeTheme.panelSoft : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(NeoCodeTheme.textPrimary)

                Text(detail)
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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

private struct SettingsControlRow<Accessory: View>: View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(NeoCodeTheme.line)
            .frame(height: 1)
            .padding(.vertical, 16)
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
