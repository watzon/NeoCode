import AppKit
import SwiftUI

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
