import AppKit
import SwiftUI

enum NeoCodeTheme {
    private static var appearanceSettings = NeoCodeAppearanceSettings()

    static let window = Color.clear

    static func configure(with appearance: NeoCodeAppearanceSettings) {
        appearanceSettings = appearance
    }

    static var canvas: Color { dynamicColor(\.canvas) }
    static var panel: Color { dynamicColor(\.panel) }
    static var panelRaised: Color { dynamicColor(\.panelRaised) }
    static var panelSoft: Color { dynamicColor(\.panelSoft) }
    static var line: Color { dynamicColor(\.line) }
    static var lineStrong: Color { dynamicColor(\.lineStrong) }
    static var lineSoft: Color { dynamicColor(\.lineSoft) }
    static var textPrimary: Color { dynamicColor(\.textPrimary) }
    static var textSecondary: Color { dynamicColor(\.textSecondary) }
    static var textMuted: Color { dynamicColor(\.textMuted) }
    static var accent: Color { dynamicColor(\.accent) }
    static var accentDim: Color { dynamicColor(\.accentDim) }
    static var success: Color { dynamicColor(\.success) }
    static var warning: Color { dynamicColor(\.warning) }
    static var diffContextBackground: Color { dynamicColor(\.diffContextBackground) }
    static var diffContextText: Color { dynamicColor(\.diffContextText) }
    static var diffLineNumber: Color { dynamicColor(\.diffLineNumber) }
    static var diffAddedBackground: Color { dynamicColor(\.diffAddedBackground) }
    static var diffAddedText: Color { dynamicColor(\.diffAddedText) }
    static var diffRemovedBackground: Color { dynamicColor(\.diffRemovedBackground) }
    static var diffRemovedText: Color { dynamicColor(\.diffRemovedText) }
    static var diffHunkBackground: Color { dynamicColor(\.diffHunkBackground) }
    static var diffHunkText: Color { dynamicColor(\.diffHunkText) }

    static func preferredColorScheme(from appearance: NeoCodeAppearanceSettings) -> ColorScheme? {
        appearance.themeMode.preferredColorScheme
    }

    static var uiBaseFontSize: CGFloat {
        CGFloat(appearanceSettings.uiFontSize)
    }

    static var codeBaseFontSize: CGFloat {
        CGFloat(appearanceSettings.codeFontSize)
    }

    private static func dynamicColor(_ keyPath: KeyPath<ResolvedPalette, NSColor>) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            resolvedPalette(for: isDark(appearance))[keyPath: keyPath]
        })
    }

    private static func resolvedPalette(for isDark: Bool) -> ResolvedPalette {
        ResolvedPalette(
            profile: isDark ? appearanceSettings.darkTheme : appearanceSettings.lightTheme,
            isDark: isDark
        )
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension Font {
    static var neoTitle: Font {
        .system(size: NeoCodeTheme.uiBaseFontSize + 1, weight: .semibold, design: .rounded)
    }

    static var neoBody: Font {
        .system(size: NeoCodeTheme.uiBaseFontSize, weight: .regular, design: .default)
    }

    static var neoMeta: Font {
        .system(size: max(10, NeoCodeTheme.uiBaseFontSize - 2), weight: .medium, design: .default)
    }

    static var neoAction: Font {
        .system(size: NeoCodeTheme.uiBaseFontSize, weight: .medium, design: .default)
    }

    static var neoMono: Font {
        .system(size: NeoCodeTheme.codeBaseFontSize, weight: .regular, design: .monospaced)
    }

    static var neoMonoSmall: Font {
        .system(size: max(10, NeoCodeTheme.codeBaseFontSize - 1), weight: .regular, design: .monospaced)
    }
}

private struct ResolvedPalette {
    let canvas: NSColor
    let panel: NSColor
    let panelRaised: NSColor
    let panelSoft: NSColor
    let line: NSColor
    let lineStrong: NSColor
    let lineSoft: NSColor
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textMuted: NSColor
    let accent: NSColor
    let accentDim: NSColor
    let success: NSColor
    let warning: NSColor
    let diffContextBackground: NSColor
    let diffContextText: NSColor
    let diffLineNumber: NSColor
    let diffAddedBackground: NSColor
    let diffAddedText: NSColor
    let diffRemovedBackground: NSColor
    let diffRemovedText: NSColor
    let diffHunkBackground: NSColor
    let diffHunkText: NSColor
    init(profile: NeoCodeThemeProfile, isDark: Bool) {
        let background = NSColor(neoHex: profile.backgroundHex)
            ?? (isDark ? NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1) : NSColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1))
        let foreground = NSColor(neoHex: profile.foregroundHex)
            ?? (isDark ? NSColor(red: 0.94, green: 0.93, blue: 0.89, alpha: 1) : NSColor(red: 0.16, green: 0.12, blue: 0.08, alpha: 1))
        let accent = NSColor(neoHex: profile.accentHex)
            ?? NSColor(red: 0.87, green: 0.66, blue: 0.34, alpha: 1)

        let contrast = min(max(profile.contrast, 20), 80) / 100
        let warning = isDark
            ? NSColor(neoHex: "#D68642") ?? .systemOrange
            : NSColor(neoHex: "#9F5B16") ?? .systemOrange
        let success = isDark
            ? NSColor(neoHex: "#54B47C") ?? .systemGreen
            : NSColor(neoHex: "#2B7A4C") ?? .systemGreen

        if isDark {
            canvas = background.darker(by: 0.12 + contrast * 0.08)
            panel = background.lighter(by: 0.04 + contrast * 0.02)
            panelRaised = background.lighter(by: 0.08 + contrast * 0.03)
            panelSoft = foreground.withAlphaComponent(0.035 + contrast * 0.03)
            line = foreground.withAlphaComponent(0.08 + contrast * 0.06)
            lineStrong = foreground.withAlphaComponent(0.14 + contrast * 0.08)
            lineSoft = foreground.withAlphaComponent(0.04 + contrast * 0.03)
            textPrimary = foreground
            textSecondary = foreground.withAlphaComponent(0.66)
            textMuted = foreground.withAlphaComponent(0.42)
            accentDim = accent.mixed(with: background, ratio: 0.62)
            diffContextBackground = panelRaised
            diffContextText = foreground.withAlphaComponent(0.84)
            diffLineNumber = foreground.withAlphaComponent(0.36)
            diffAddedBackground = accent.mixed(with: background, ratio: 0.80)
            diffAddedText = accent.lighter(by: 0.18)
            diffRemovedBackground = warning.mixed(with: background, ratio: 0.82)
            diffRemovedText = warning.lighter(by: 0.16)
            diffHunkBackground = accent.mixed(with: background, ratio: 0.88)
            diffHunkText = accent.lighter(by: 0.10)
        } else {
            canvas = background.darker(by: 0.04 + contrast * 0.02)
            panel = background.lighter(by: 0.01)
            panelRaised = background.darker(by: 0.015 + contrast * 0.01)
            panelSoft = foreground.withAlphaComponent(0.035 + contrast * 0.03)
            line = foreground.withAlphaComponent(0.09 + contrast * 0.06)
            lineStrong = foreground.withAlphaComponent(0.15 + contrast * 0.08)
            lineSoft = foreground.withAlphaComponent(0.05 + contrast * 0.03)
            textPrimary = foreground
            textSecondary = foreground.withAlphaComponent(0.68)
            textMuted = foreground.withAlphaComponent(0.46)
            accentDim = accent.mixed(with: background, ratio: 0.72)
            diffContextBackground = panelRaised
            diffContextText = foreground.withAlphaComponent(0.84)
            diffLineNumber = foreground.withAlphaComponent(0.32)
            diffAddedBackground = success.mixed(with: background, ratio: 0.86)
            diffAddedText = success.darker(by: 0.06)
            diffRemovedBackground = warning.mixed(with: background, ratio: 0.90)
            diffRemovedText = warning.darker(by: 0.02)
            diffHunkBackground = accent.mixed(with: background, ratio: 0.90)
            diffHunkText = accent.darker(by: 0.08)
        }

        self.accent = accent
        self.success = success
        self.warning = warning
    }
}

extension Color {
    init?(neoHex: String) {
        guard let color = NSColor(neoHex: neoHex) else { return nil }
        self.init(nsColor: color)
    }
}

extension NSColor {
    convenience init?(neoHex: String) {
        let trimmed = neoHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard sanitized.count == 6,
              let value = Int(sanitized, radix: 16)
        else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }

    func mixed(with other: NSColor, ratio: CGFloat) -> NSColor {
        let clamped = min(max(ratio, 0), 1)
        let source = usingColorSpace(.deviceRGB) ?? self
        let destination = other.usingColorSpace(.deviceRGB) ?? other

        let red = source.redComponent * clamped + destination.redComponent * (1 - clamped)
        let green = source.greenComponent * clamped + destination.greenComponent * (1 - clamped)
        let blue = source.blueComponent * clamped + destination.blueComponent * (1 - clamped)
        let alpha = source.alphaComponent * clamped + destination.alphaComponent * (1 - clamped)

        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    func lighter(by amount: Double) -> NSColor {
        mixed(with: .white, ratio: 1 - CGFloat(amount))
    }

    func darker(by amount: Double) -> NSColor {
        mixed(with: .black, ratio: 1 - CGFloat(amount))
    }
}
