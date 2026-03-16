import SwiftUI

enum AppSettingsSection: String, Codable, CaseIterable, Hashable, Identifiable {
    case general
    case appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .appearance:
            return "Appearance"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Defaults, behavior, and future app controls."
        case .appearance:
            return "Theme, fonts, and interface styling."
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .appearance:
            return "paintbrush"
        }
    }
}

enum NeoCodeThemeMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .system:
            return "desktopcomputer"
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct NeoCodeAppSettings: Codable, Hashable {
    var general: NeoCodeGeneralSettings
    var appearance: NeoCodeAppearanceSettings

    init(
        general: NeoCodeGeneralSettings = .init(),
        appearance: NeoCodeAppearanceSettings = .init()
    ) {
        self.general = general
        self.appearance = appearance
    }
}

struct NeoCodeGeneralSettings: Codable, Hashable {
    var launchToDashboard: Bool

    init(launchToDashboard: Bool = true) {
        self.launchToDashboard = launchToDashboard
    }
}

struct NeoCodeAppearanceSettings: Codable, Hashable {
    static let minimumUIFontSize = 12.0
    static let maximumUIFontSize = 18.0
    static let minimumCodeFontSize = 11.0
    static let maximumCodeFontSize = 18.0

    var themeMode: NeoCodeThemeMode
    var lightTheme: NeoCodeThemeProfile
    var darkTheme: NeoCodeThemeProfile
    var usesPointerCursor: Bool
    var uiFontSize: Double
    var codeFontSize: Double
    var uiFontName: String
    var codeFontName: String

    init(
        themeMode: NeoCodeThemeMode = .system,
        lightTheme: NeoCodeThemeProfile = .lightDefault,
        darkTheme: NeoCodeThemeProfile = .darkDefault,
        usesPointerCursor: Bool = false,
        uiFontSize: Double = 13,
        codeFontSize: Double = 12,
        uiFontName: String = "SF Pro",
        codeFontName: String = "SF Mono"
    ) {
        self.themeMode = themeMode
        self.lightTheme = lightTheme
        self.darkTheme = darkTheme
        self.usesPointerCursor = usesPointerCursor
        self.uiFontSize = uiFontSize
        self.codeFontSize = codeFontSize
        self.uiFontName = uiFontName
        self.codeFontName = codeFontName
    }
}

struct NeoCodeThemeProfile: Codable, Hashable {
    var accentHex: String
    var backgroundHex: String
    var foregroundHex: String
    var contrast: Double
    var isSidebarTranslucent: Bool

    init(
        accentHex: String,
        backgroundHex: String,
        foregroundHex: String,
        contrast: Double,
        isSidebarTranslucent: Bool
    ) {
        self.accentHex = accentHex
        self.backgroundHex = backgroundHex
        self.foregroundHex = foregroundHex
        self.contrast = contrast
        self.isSidebarTranslucent = isSidebarTranslucent
    }

    static let lightDefault = NeoCodeThemeProfile(
        accentHex: "#C48A37",
        backgroundHex: "#F7F3E9",
        foregroundHex: "#241D12",
        contrast: 44,
        isSidebarTranslucent: false
    )

    static let darkDefault = NeoCodeThemeProfile(
        accentHex: "#DDA756",
        backgroundHex: "#121315",
        foregroundHex: "#F1EBDD",
        contrast: 62,
        isSidebarTranslucent: true
    )
}
