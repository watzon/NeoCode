import SwiftUI

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

struct SettingsFontPicker: View {
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

struct SettingsStepperControl: View {
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

struct HexColorField: View {
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

struct SettingsStepperValue: View {
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

struct SettingsCardActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.neoAction)
            .foregroundStyle(NeoCodeTheme.textSecondary)
    }
}

struct ThemePresetPicker: View {
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

struct ThemePresetBadgeView: View {
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

struct FixedWidthDropdownTriggerLabel<Leading: View>: View {
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
