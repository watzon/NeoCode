import AppKit
import SwiftUI

enum NeoCodeTheme {
    private static var appearanceSettings = NeoCodeAppearanceSettings()

    static let window = Color.clear

    static func configure(with appearance: NeoCodeAppearanceSettings) {
        appearanceSettings = appearance
        NSApp.appearance = appearance.themeMode.appKitAppearanceName.flatMap(NSAppearance.init(named:))
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
    static var panelColor: NSColor { dynamicNSColor(\.panel) }
    static var panelRaisedColor: NSColor { dynamicNSColor(\.panelRaised) }
    static var lineColor: NSColor { dynamicNSColor(\.line) }
    static var lineStrongColor: NSColor { dynamicNSColor(\.lineStrong) }
    static var textPrimaryColor: NSColor { dynamicNSColor(\.textPrimary) }
    static var textMutedColor: NSColor { dynamicNSColor(\.textMuted) }
    static var accentColor: NSColor { dynamicNSColor(\.accent) }

    static var uiBaseFontSize: CGFloat {
        CGFloat(appearanceSettings.uiFontSize)
    }

    static var codeBaseFontSize: CGFloat {
        CGFloat(appearanceSettings.codeFontSize)
    }

    static var currentUIFontName: String {
        activeThemeProfile.uiFontName
    }

    static var currentCodeFontName: String {
        activeThemeProfile.codeFontName
    }

    static func uiAppKitFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let customFont = resolvedFont(
            storedName: currentUIFontName,
            size: size,
            weight: weight,
            fallback: NSFont.systemFont(ofSize: size, weight: weight),
            preferFixedPitch: false
        ) {
            return customFont
        }

        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func codeAppKitFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let customFont = resolvedFont(
            storedName: currentCodeFontName,
            size: size,
            weight: weight,
            fallback: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
            preferFixedPitch: true
        ) {
            return customFont
        }

        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    private static func resolvedFont(
        storedName: String,
        size: CGFloat,
        weight: NSFont.Weight,
        fallback: NSFont,
        preferFixedPitch: Bool
    ) -> NSFont? {
        if NeoCodeFontCatalog.usesSystemMonospaceStack(storedName) {
            return adjustedFont(
                NSFont.monospacedSystemFont(ofSize: size, weight: weight),
                size: size,
                weight: weight,
                fallback: fallback,
                preferFixedPitch: preferFixedPitch
            )
        }

        guard let postScriptName = NeoCodeFontCatalog.postScriptName(for: storedName, preferFixedPitch: preferFixedPitch),
              let baseFont = NSFont(name: postScriptName, size: size)
        else {
            return nil
        }

        return adjustedFont(baseFont, size: size, weight: weight, fallback: fallback, preferFixedPitch: preferFixedPitch)
    }

    private static func adjustedFont(
        _ font: NSFont,
        size: CGFloat,
        weight: NSFont.Weight,
        fallback: NSFont,
        preferFixedPitch: Bool
    ) -> NSFont {
        var resolvedFont = font.withSize(size)
        let fontManager = NSFontManager.shared

        if weight.rawValue >= NSFont.Weight.semibold.rawValue {
            let boldCandidate = fontManager.convert(resolvedFont, toHaveTrait: .boldFontMask)
            if boldCandidate.fontName != resolvedFont.fontName || boldCandidate.familyName == resolvedFont.familyName {
                resolvedFont = boldCandidate.withSize(size)
            }
        }

        if preferFixedPitch,
           !resolvedFont.isFixedPitch,
           fallback.isFixedPitch {
            return fallback
        }

        return resolvedFont
    }

    fileprivate static func customFont(_ font: NSFont) -> Font {
        .custom(font.fontName, size: font.pointSize)
    }

    private static var activeThemeProfile: NeoCodeThemeProfile {
        isDark(currentAppearance) ? appearanceSettings.darkTheme : appearanceSettings.lightTheme
    }

    private static func dynamicColor(_ keyPath: KeyPath<ResolvedPalette, NSColor>) -> Color {
        Color(nsColor: dynamicNSColor(keyPath))
    }

    private static func dynamicNSColor(_ keyPath: KeyPath<ResolvedPalette, NSColor>) -> NSColor {
        NSColor(name: nil) { appearance in
            resolvedPalette(for: isDark(appearance))[keyPath: keyPath]
        }
    }

    private static func resolvedPalette(for isDark: Bool) -> ResolvedPalette {
        ResolvedPalette(
            profile: isDark ? appearanceSettings.darkTheme : appearanceSettings.lightTheme,
            isDark: isDark
        )
    }

    private static var currentAppearance: NSAppearance {
        if let appearance = NSApp?.effectiveAppearance {
            return appearance
        }

        return NSAppearance(named: .aqua)!
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension Font {
    static var neoTitle: Font {
        let size = NeoCodeTheme.uiBaseFontSize + 1
        if NeoCodeTheme.currentUIFontName == NeoCodeFontCatalog.defaultUIFontName {
            return .system(size: size, weight: .semibold, design: .rounded)
        }
        return NeoCodeTheme.customFont(NeoCodeTheme.uiAppKitFont(size: size, weight: .semibold))
    }

    static var neoBody: Font {
        let size = NeoCodeTheme.uiBaseFontSize
        if NeoCodeTheme.currentUIFontName == NeoCodeFontCatalog.defaultUIFontName {
            return .system(size: size, weight: .regular, design: .default)
        }
        return NeoCodeTheme.customFont(NeoCodeTheme.uiAppKitFont(size: size, weight: .regular))
    }

    static var neoMeta: Font {
        let size = max(10, NeoCodeTheme.uiBaseFontSize - 2)
        if NeoCodeTheme.currentUIFontName == NeoCodeFontCatalog.defaultUIFontName {
            return .system(size: size, weight: .medium, design: .default)
        }
        return NeoCodeTheme.customFont(NeoCodeTheme.uiAppKitFont(size: size, weight: .medium))
    }

    static var neoAction: Font {
        let size = NeoCodeTheme.uiBaseFontSize
        if NeoCodeTheme.currentUIFontName == NeoCodeFontCatalog.defaultUIFontName {
            return .system(size: size, weight: .medium, design: .default)
        }
        return NeoCodeTheme.customFont(NeoCodeTheme.uiAppKitFont(size: size, weight: .medium))
    }

    static var neoMono: Font {
        let size = NeoCodeTheme.codeBaseFontSize
        if NeoCodeTheme.currentCodeFontName == NeoCodeFontCatalog.defaultCodeFontName {
            return .system(size: size, weight: .regular, design: .monospaced)
        }
        return NeoCodeTheme.customFont(NeoCodeTheme.codeAppKitFont(size: size, weight: .regular))
    }

    static var neoMonoSmall: Font {
        let size = max(10, NeoCodeTheme.codeBaseFontSize - 1)
        if NeoCodeTheme.currentCodeFontName == NeoCodeFontCatalog.defaultCodeFontName {
            return .system(size: size, weight: .regular, design: .monospaced)
        }
        return NeoCodeTheme.customFont(NeoCodeTheme.codeAppKitFont(size: size, weight: .regular))
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
        let diffAdded = NSColor(neoHex: profile.diffAddedHex)
            ?? (isDark ? NSColor(neoHex: NeoCodeThemeProfile.defaultDarkDiffAddedHex) : NSColor(neoHex: NeoCodeThemeProfile.defaultLightDiffAddedHex))
            ?? .systemGreen
        let diffRemoved = NSColor(neoHex: profile.diffRemovedHex)
            ?? (isDark ? NSColor(neoHex: NeoCodeThemeProfile.defaultDarkDiffRemovedHex) : NSColor(neoHex: NeoCodeThemeProfile.defaultLightDiffRemovedHex))
            ?? .systemOrange
        let skill = NSColor(neoHex: profile.skillHex) ?? accent

        let contrast = min(max(profile.contrast, 20), 80) / 100
        let warning = isDark
            ? NSColor(neoHex: "#D68642") ?? .systemOrange
            : NSColor(neoHex: "#9F5B16") ?? .systemOrange
        let success = isDark
            ? NSColor(neoHex: "#54B47C") ?? .systemGreen
            : NSColor(neoHex: "#2B7A4C") ?? .systemGreen

        if isDark {
            canvas = background.darker(by: 0.12 + contrast * 0.08)
            panel = background.lighter(by: 0.01)
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
            diffAddedBackground = diffAdded.mixed(with: background, ratio: 0.80)
            diffAddedText = diffAdded.lighter(by: 0.18)
            diffRemovedBackground = diffRemoved.mixed(with: background, ratio: 0.82)
            diffRemovedText = diffRemoved.lighter(by: 0.16)
            diffHunkBackground = skill.mixed(with: background, ratio: 0.88)
            diffHunkText = skill.lighter(by: 0.10)
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
            diffAddedBackground = diffAdded.mixed(with: background, ratio: 0.86)
            diffAddedText = diffAdded.darker(by: 0.06)
            diffRemovedBackground = diffRemoved.mixed(with: background, ratio: 0.90)
            diffRemovedText = diffRemoved.darker(by: 0.02)
            diffHunkBackground = skill.mixed(with: background, ratio: 0.90)
            diffHunkText = skill.darker(by: 0.08)
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
    nonisolated convenience init?(neoHex: String) {
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

    nonisolated func mixed(with other: NSColor, ratio: CGFloat) -> NSColor {
        let clamped = min(max(ratio, 0), 1)
        let source = usingColorSpace(.deviceRGB) ?? self
        let destination = other.usingColorSpace(.deviceRGB) ?? other

        let red = source.redComponent * clamped + destination.redComponent * (1 - clamped)
        let green = source.greenComponent * clamped + destination.greenComponent * (1 - clamped)
        let blue = source.blueComponent * clamped + destination.blueComponent * (1 - clamped)
        let alpha = source.alphaComponent * clamped + destination.alphaComponent * (1 - clamped)

        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    nonisolated func lighter(by amount: Double) -> NSColor {
        mixed(with: .white, ratio: 1 - CGFloat(amount))
    }

    nonisolated func darker(by amount: Double) -> NSColor {
        mixed(with: .black, ratio: 1 - CGFloat(amount))
    }
}
