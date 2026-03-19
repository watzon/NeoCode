import AppKit

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
    var selectedLightPresetID: String?
    var selectedDarkPresetID: String?

    init(
        themeMode: NeoCodeThemeMode = .system,
        lightTheme: NeoCodeThemeProfile = .lightDefault,
        darkTheme: NeoCodeThemeProfile = .darkDefault,
        usesPointerCursor: Bool = false,
        uiFontSize: Double = 13,
        codeFontSize: Double = 12,
        selectedLightPresetID: String? = nil,
        selectedDarkPresetID: String? = nil
    ) {
        self.themeMode = themeMode
        self.lightTheme = lightTheme
        self.darkTheme = darkTheme
        self.usesPointerCursor = usesPointerCursor
        self.uiFontSize = uiFontSize
        self.codeFontSize = codeFontSize
        self.selectedLightPresetID = selectedLightPresetID
        self.selectedDarkPresetID = selectedDarkPresetID
        syncPresetSelection()
    }

    enum CodingKeys: String, CodingKey {
        case themeMode
        case lightTheme
        case darkTheme
        case usesPointerCursor
        case uiFontSize
        case codeFontSize
        case selectedLightPresetID
        case selectedDarkPresetID
        case uiFontName
        case codeFontName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeMode = try container.decodeIfPresent(NeoCodeThemeMode.self, forKey: .themeMode) ?? .system
        lightTheme = try container.decodeIfPresent(NeoCodeThemeProfile.self, forKey: .lightTheme) ?? .lightDefault
        darkTheme = try container.decodeIfPresent(NeoCodeThemeProfile.self, forKey: .darkTheme) ?? .darkDefault
        usesPointerCursor = try container.decodeIfPresent(Bool.self, forKey: .usesPointerCursor) ?? false
        uiFontSize = try container.decodeIfPresent(Double.self, forKey: .uiFontSize) ?? 13
        codeFontSize = try container.decodeIfPresent(Double.self, forKey: .codeFontSize) ?? 12
        selectedLightPresetID = try container.decodeIfPresent(String.self, forKey: .selectedLightPresetID)
        selectedDarkPresetID = try container.decodeIfPresent(String.self, forKey: .selectedDarkPresetID)

        if container.contains(.uiFontName) || container.contains(.codeFontName) {
            let legacyUIFontName = try container.decodeIfPresent(String.self, forKey: .uiFontName) ?? NeoCodeFontCatalog.defaultUIFontName
            let legacyCodeFontName = try container.decodeIfPresent(String.self, forKey: .codeFontName) ?? NeoCodeFontCatalog.defaultCodeFontName
            lightTheme.applyLegacyFontNames(uiFontName: legacyUIFontName, codeFontName: legacyCodeFontName)
            darkTheme.applyLegacyFontNames(uiFontName: legacyUIFontName, codeFontName: legacyCodeFontName)
        }

        syncPresetSelection()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(themeMode, forKey: .themeMode)
        try container.encode(lightTheme, forKey: .lightTheme)
        try container.encode(darkTheme, forKey: .darkTheme)
        try container.encode(usesPointerCursor, forKey: .usesPointerCursor)
        try container.encode(uiFontSize, forKey: .uiFontSize)
        try container.encode(codeFontSize, forKey: .codeFontSize)
        try container.encodeIfPresent(selectedLightPresetID, forKey: .selectedLightPresetID)
        try container.encodeIfPresent(selectedDarkPresetID, forKey: .selectedDarkPresetID)
    }

    mutating func syncPresetSelection() {
        selectedLightPresetID = Self.matchingPresetID(for: lightTheme, kind: .light) ?? selectedLightPresetID
        if Self.matchingPresetID(for: lightTheme, kind: .light) == nil {
            selectedLightPresetID = nil
        }

        selectedDarkPresetID = Self.matchingPresetID(for: darkTheme, kind: .dark) ?? selectedDarkPresetID
        if Self.matchingPresetID(for: darkTheme, kind: .dark) == nil {
            selectedDarkPresetID = nil
        }
    }

    mutating func applyPreset(_ preset: NeoCodeThemePreset, kind: ThemeProfileKind) {
        guard let theme = preset.theme(for: kind) else {
            return
        }

        switch kind {
        case .light:
            lightTheme = theme
            selectedLightPresetID = preset.id
        case .dark:
            darkTheme = theme
            selectedDarkPresetID = preset.id
        }
    }

    func selectedPresetID(for kind: ThemeProfileKind) -> String? {
        switch kind {
        case .light:
            return selectedLightPresetID
        case .dark:
            return selectedDarkPresetID
        }
    }

    static func matchingPresetID(for profile: NeoCodeThemeProfile, kind: ThemeProfileKind) -> String? {
        NeoCodeThemePresetCatalog.presets.first { preset in
            preset.theme(for: kind)?.matches(profile) == true
        }?.id
    }
}

struct NeoCodeThemeProfile: Codable, Hashable {
    static let defaultLightDiffAddedHex = "#2B7A4C"
    static let defaultDarkDiffAddedHex = "#54B47C"
    static let defaultLightDiffRemovedHex = "#9F5B16"
    static let defaultDarkDiffRemovedHex = "#D68642"
    static let defaultDiffAddedHex = defaultLightDiffAddedHex
    static let defaultDiffRemovedHex = defaultLightDiffRemovedHex

    var accentHex: String
    var backgroundHex: String
    var foregroundHex: String
    var contrast: Double
    var isSidebarTranslucent: Bool
    var diffAddedHex: String
    var diffRemovedHex: String
    var skillHex: String
    var uiFontName: String
    var codeFontName: String

    init(
        accentHex: String,
        backgroundHex: String,
        foregroundHex: String,
        contrast: Double,
        isSidebarTranslucent: Bool,
        diffAddedHex: String = defaultDiffAddedHex,
        diffRemovedHex: String = defaultDiffRemovedHex,
        skillHex: String? = nil,
        uiFontName: String = NeoCodeFontCatalog.defaultUIFontName,
        codeFontName: String = NeoCodeFontCatalog.defaultCodeFontName
    ) {
        self.accentHex = accentHex
        self.backgroundHex = backgroundHex
        self.foregroundHex = foregroundHex
        self.contrast = contrast
        self.isSidebarTranslucent = isSidebarTranslucent
        self.diffAddedHex = diffAddedHex
        self.diffRemovedHex = diffRemovedHex
        self.skillHex = skillHex ?? accentHex
        self.uiFontName = Self.normalizedFontName(uiFontName, fallback: NeoCodeFontCatalog.defaultUIFontName)
        self.codeFontName = Self.normalizedFontName(codeFontName, fallback: NeoCodeFontCatalog.defaultCodeFontName)
    }

    enum CodingKeys: String, CodingKey {
        case accentHex
        case backgroundHex
        case foregroundHex
        case contrast
        case isSidebarTranslucent
        case diffAddedHex
        case diffRemovedHex
        case skillHex
        case uiFontName
        case codeFontName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex) ?? Self.darkDefault.accentHex
        backgroundHex = try container.decodeIfPresent(String.self, forKey: .backgroundHex) ?? Self.darkDefault.backgroundHex
        foregroundHex = try container.decodeIfPresent(String.self, forKey: .foregroundHex) ?? Self.darkDefault.foregroundHex
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? Self.darkDefault.contrast
        isSidebarTranslucent = try container.decodeIfPresent(Bool.self, forKey: .isSidebarTranslucent) ?? false

        let isDark = Self.isDarkBackgroundHex(backgroundHex)
        diffAddedHex = try container.decodeIfPresent(String.self, forKey: .diffAddedHex)
            ?? (isDark ? Self.defaultDarkDiffAddedHex : Self.defaultLightDiffAddedHex)
        diffRemovedHex = try container.decodeIfPresent(String.self, forKey: .diffRemovedHex)
            ?? (isDark ? Self.defaultDarkDiffRemovedHex : Self.defaultLightDiffRemovedHex)
        skillHex = try container.decodeIfPresent(String.self, forKey: .skillHex) ?? accentHex
        uiFontName = Self.normalizedFontName(
            try container.decodeIfPresent(String.self, forKey: .uiFontName),
            fallback: NeoCodeFontCatalog.defaultUIFontName
        )
        codeFontName = Self.normalizedFontName(
            try container.decodeIfPresent(String.self, forKey: .codeFontName),
            fallback: NeoCodeFontCatalog.defaultCodeFontName
        )
    }

    static let lightDefault = NeoCodeThemeProfile(
        accentHex: "#C48A37",
        backgroundHex: "#F7F3E9",
        foregroundHex: "#241D12",
        contrast: 44,
        isSidebarTranslucent: false,
        diffAddedHex: defaultLightDiffAddedHex,
        diffRemovedHex: defaultLightDiffRemovedHex
    )

    static let darkDefault = NeoCodeThemeProfile(
        accentHex: "#DDA756",
        backgroundHex: "#121315",
        foregroundHex: "#F1EBDD",
        contrast: 62,
        isSidebarTranslucent: true,
        diffAddedHex: defaultDarkDiffAddedHex,
        diffRemovedHex: defaultDarkDiffRemovedHex
    )

    mutating func applyLegacyFontNames(uiFontName: String, codeFontName: String) {
        self.uiFontName = Self.normalizedFontName(uiFontName, fallback: NeoCodeFontCatalog.defaultUIFontName)
        self.codeFontName = Self.normalizedFontName(codeFontName, fallback: NeoCodeFontCatalog.defaultCodeFontName)
    }

    static func normalizedFontName(_ fontName: String?, fallback: String) -> String {
        guard let trimmed = fontName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return fallback
        }

        return trimmed
    }

    static func isDarkBackgroundHex(_ hex: String) -> Bool {
        guard let color = NSColor(neoHex: hex)?.usingColorSpace(.deviceRGB) else {
            return false
        }

        let luminance = 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
        return luminance < 0.5
    }
}

enum ThemeProfileKind: String, Codable, Hashable, Identifiable {
    case light
    case dark

    var id: String { rawValue }
}

struct NeoCodeThemePreset: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let badgeText: String
    let badgeBackgroundHex: String
    let badgeForegroundHex: String
    let lightTheme: NeoCodeThemeProfile?
    let darkTheme: NeoCodeThemeProfile?

    func theme(for kind: ThemeProfileKind) -> NeoCodeThemeProfile? {
        switch kind {
        case .light:
            return lightTheme
        case .dark:
            return darkTheme
        }
    }
}

struct NeoCodeThemeProfileTransfer: Codable, Hashable {
    var version: Int
    var name: String?
    var accentHex: String
    var backgroundHex: String
    var foregroundHex: String
    var contrast: Double
    var isSidebarTranslucent: Bool
    var diffAddedHex: String
    var diffRemovedHex: String
    var skillHex: String
    var uiFontName: String
    var codeFontName: String

    init(
        version: Int = 2,
        name: String? = nil,
        accentHex: String,
        backgroundHex: String,
        foregroundHex: String,
        contrast: Double,
        isSidebarTranslucent: Bool = false,
        diffAddedHex: String = NeoCodeThemeProfile.defaultDiffAddedHex,
        diffRemovedHex: String = NeoCodeThemeProfile.defaultDiffRemovedHex,
        skillHex: String? = nil,
        uiFontName: String = NeoCodeFontCatalog.defaultUIFontName,
        codeFontName: String = NeoCodeFontCatalog.defaultCodeFontName
    ) {
        self.version = version
        self.name = name
        self.accentHex = accentHex
        self.backgroundHex = backgroundHex
        self.foregroundHex = foregroundHex
        self.contrast = contrast
        self.isSidebarTranslucent = isSidebarTranslucent
        self.diffAddedHex = diffAddedHex
        self.diffRemovedHex = diffRemovedHex
        self.skillHex = skillHex ?? accentHex
        self.uiFontName = NeoCodeThemeProfile.normalizedFontName(uiFontName, fallback: NeoCodeFontCatalog.defaultUIFontName)
        self.codeFontName = NeoCodeThemeProfile.normalizedFontName(codeFontName, fallback: NeoCodeFontCatalog.defaultCodeFontName)
    }

    enum CodingKeys: String, CodingKey {
        case version
        case name
        case accentHex
        case backgroundHex
        case foregroundHex
        case contrast
        case isSidebarTranslucent
        case diffAddedHex
        case diffRemovedHex
        case skillHex
        case uiFontName
        case codeFontName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        name = try container.decodeIfPresent(String.self, forKey: .name)
        accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex) ?? NeoCodeThemeProfile.darkDefault.accentHex
        backgroundHex = try container.decodeIfPresent(String.self, forKey: .backgroundHex) ?? NeoCodeThemeProfile.darkDefault.backgroundHex
        foregroundHex = try container.decodeIfPresent(String.self, forKey: .foregroundHex) ?? NeoCodeThemeProfile.darkDefault.foregroundHex
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? NeoCodeThemeProfile.darkDefault.contrast
        isSidebarTranslucent = try container.decodeIfPresent(Bool.self, forKey: .isSidebarTranslucent) ?? false

        let isDark = NeoCodeThemeProfile.isDarkBackgroundHex(backgroundHex)
        diffAddedHex = try container.decodeIfPresent(String.self, forKey: .diffAddedHex)
            ?? (isDark ? NeoCodeThemeProfile.defaultDarkDiffAddedHex : NeoCodeThemeProfile.defaultLightDiffAddedHex)
        diffRemovedHex = try container.decodeIfPresent(String.self, forKey: .diffRemovedHex)
            ?? (isDark ? NeoCodeThemeProfile.defaultDarkDiffRemovedHex : NeoCodeThemeProfile.defaultLightDiffRemovedHex)
        skillHex = try container.decodeIfPresent(String.self, forKey: .skillHex) ?? accentHex
        uiFontName = NeoCodeThemeProfile.normalizedFontName(
            try container.decodeIfPresent(String.self, forKey: .uiFontName),
            fallback: NeoCodeFontCatalog.defaultUIFontName
        )
        codeFontName = NeoCodeThemeProfile.normalizedFontName(
            try container.decodeIfPresent(String.self, forKey: .codeFontName),
            fallback: NeoCodeFontCatalog.defaultCodeFontName
        )
    }

    init(profile: NeoCodeThemeProfile, name: String? = nil) {
        self.init(
            name: name,
            accentHex: profile.accentHex,
            backgroundHex: profile.backgroundHex,
            foregroundHex: profile.foregroundHex,
            contrast: profile.contrast,
            isSidebarTranslucent: profile.isSidebarTranslucent,
            diffAddedHex: profile.diffAddedHex,
            diffRemovedHex: profile.diffRemovedHex,
            skillHex: profile.skillHex,
            uiFontName: profile.uiFontName,
            codeFontName: profile.codeFontName
        )
    }

    var profile: NeoCodeThemeProfile {
        NeoCodeThemeProfile(
            accentHex: accentHex,
            backgroundHex: backgroundHex,
            foregroundHex: foregroundHex,
            contrast: contrast,
            isSidebarTranslucent: isSidebarTranslucent,
            diffAddedHex: diffAddedHex,
            diffRemovedHex: diffRemovedHex,
            skillHex: skillHex,
            uiFontName: uiFontName,
            codeFontName: codeFontName
        )
    }
}

private extension NeoCodeThemeProfile {
    func matches(_ other: NeoCodeThemeProfile) -> Bool {
        accentHex.caseInsensitiveCompare(other.accentHex) == .orderedSame &&
        backgroundHex.caseInsensitiveCompare(other.backgroundHex) == .orderedSame &&
        foregroundHex.caseInsensitiveCompare(other.foregroundHex) == .orderedSame &&
        diffAddedHex.caseInsensitiveCompare(other.diffAddedHex) == .orderedSame &&
        diffRemovedHex.caseInsensitiveCompare(other.diffRemovedHex) == .orderedSame &&
        skillHex.caseInsensitiveCompare(other.skillHex) == .orderedSame &&
        uiFontName.caseInsensitiveCompare(other.uiFontName) == .orderedSame &&
        codeFontName.caseInsensitiveCompare(other.codeFontName) == .orderedSame &&
        isSidebarTranslucent == other.isSidebarTranslucent &&
        Int(contrast.rounded()) == Int(other.contrast.rounded())
    }
}
