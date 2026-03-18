import AppKit
import SwiftUI

enum AppSettingsSection: String, Codable, CaseIterable, Hashable, Identifiable {
    case general
    case appearance
    case updates

    var id: String { rawValue }

    var title: String {
        title(locale: .autoupdatingCurrent)
    }

    func title(locale: Locale) -> String {
        switch self {
        case .general:
            return localized("General", locale: locale)
        case .appearance:
            return localized("Appearance", locale: locale)
        case .updates:
            return localized("Updates", locale: locale)
        }
    }

    var subtitle: String {
        subtitle(locale: .autoupdatingCurrent)
    }

    func subtitle(locale: Locale) -> String {
        switch self {
        case .general:
            return localized("Startup, composer, autonomy, and notifications.", locale: locale)
        case .appearance:
            return localized("Theme, fonts, and interface styling.", locale: locale)
        case .updates:
            return localized("Sparkle delivery, release status, and update controls.", locale: locale)
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "slider.horizontal.3"
        case .appearance:
            return "paintbrush"
        case .updates:
            return "arrow.triangle.2.circlepath"
        }
    }
}

enum NeoCodeThemeMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        title(locale: .autoupdatingCurrent)
    }

    func title(locale: Locale) -> String {
        switch self {
        case .system:
            return localized("System", locale: locale)
        case .light:
            return localized("Light", locale: locale)
        case .dark:
            return localized("Dark", locale: locale)
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

    var appKitAppearanceName: NSAppearance.Name? {
        switch self {
        case .system:
            return nil
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        }
    }
}

enum NeoCodeStartupBehavior: String, Codable, CaseIterable, Hashable, Identifiable {
    case dashboard
    case lastWorkspace

    var id: String { rawValue }

    var title: String {
        title(locale: .autoupdatingCurrent)
    }

    func title(locale: Locale) -> String {
        switch self {
        case .dashboard:
            return localized("Dashboard", locale: locale)
        case .lastWorkspace:
            return localized("Last workspace", locale: locale)
        }
    }
}

enum NeoCodeSendKeyBehavior: String, Codable, CaseIterable, Hashable, Identifiable {
    case returnKey
    case commandReturn

    var id: String { rawValue }

    var title: String {
        title(locale: .autoupdatingCurrent)
    }

    func title(locale: Locale) -> String {
        switch self {
        case .returnKey:
            return localized("Return", locale: locale)
        case .commandReturn:
            return localized("Command-Return", locale: locale)
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
    var appLanguage: NeoCodeAppLanguage
    var startupBehavior: NeoCodeStartupBehavior
    var sendKeyBehavior: NeoCodeSendKeyBehavior
    var restoresPromptDrafts: Bool
    var remembersYoloModePerThread: Bool
    var defaultWorkspaceToolID: String?
    var preventsSystemSleepWhileRunning: Bool
    var notifiesWhenResponseCompletes: Bool
    var notifiesWhenInputIsRequired: Bool

    init(
        appLanguage: NeoCodeAppLanguage = .system,
        startupBehavior: NeoCodeStartupBehavior = .dashboard,
        sendKeyBehavior: NeoCodeSendKeyBehavior = .returnKey,
        restoresPromptDrafts: Bool = true,
        remembersYoloModePerThread: Bool = true,
        defaultWorkspaceToolID: String? = nil,
        preventsSystemSleepWhileRunning: Bool = false,
        notifiesWhenResponseCompletes: Bool = false,
        notifiesWhenInputIsRequired: Bool = false
    ) {
        self.appLanguage = appLanguage
        self.startupBehavior = startupBehavior
        self.sendKeyBehavior = sendKeyBehavior
        self.restoresPromptDrafts = restoresPromptDrafts
        self.remembersYoloModePerThread = remembersYoloModePerThread
        self.defaultWorkspaceToolID = defaultWorkspaceToolID
        self.preventsSystemSleepWhileRunning = preventsSystemSleepWhileRunning
        self.notifiesWhenResponseCompletes = notifiesWhenResponseCompletes
        self.notifiesWhenInputIsRequired = notifiesWhenInputIsRequired
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyLaunchToDashboard = try container.decodeIfPresent(Bool.self, forKey: .launchToDashboard)

        appLanguage = try container.decodeIfPresent(NeoCodeAppLanguage.self, forKey: .appLanguage) ?? .system
        startupBehavior = try container.decodeIfPresent(NeoCodeStartupBehavior.self, forKey: .startupBehavior)
            ?? ((legacyLaunchToDashboard ?? true) ? .dashboard : .lastWorkspace)
        sendKeyBehavior = try container.decodeIfPresent(NeoCodeSendKeyBehavior.self, forKey: .sendKeyBehavior) ?? .returnKey
        restoresPromptDrafts = try container.decodeIfPresent(Bool.self, forKey: .restoresPromptDrafts) ?? true
        remembersYoloModePerThread = try container.decodeIfPresent(Bool.self, forKey: .remembersYoloModePerThread) ?? true
        defaultWorkspaceToolID = try container.decodeIfPresent(String.self, forKey: .defaultWorkspaceToolID)
        preventsSystemSleepWhileRunning = try container.decodeIfPresent(Bool.self, forKey: .preventsSystemSleepWhileRunning) ?? false
        notifiesWhenResponseCompletes = try container.decodeIfPresent(Bool.self, forKey: .notifiesWhenResponseCompletes) ?? false
        notifiesWhenInputIsRequired = try container.decodeIfPresent(Bool.self, forKey: .notifiesWhenInputIsRequired) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appLanguage, forKey: .appLanguage)
        try container.encode(startupBehavior, forKey: .startupBehavior)
        try container.encode(sendKeyBehavior, forKey: .sendKeyBehavior)
        try container.encode(restoresPromptDrafts, forKey: .restoresPromptDrafts)
        try container.encode(remembersYoloModePerThread, forKey: .remembersYoloModePerThread)
        try container.encodeIfPresent(defaultWorkspaceToolID, forKey: .defaultWorkspaceToolID)
        try container.encode(preventsSystemSleepWhileRunning, forKey: .preventsSystemSleepWhileRunning)
        try container.encode(notifiesWhenResponseCompletes, forKey: .notifiesWhenResponseCompletes)
        try container.encode(notifiesWhenInputIsRequired, forKey: .notifiesWhenInputIsRequired)
    }

    private enum CodingKeys: String, CodingKey {
        case appLanguage
        case startupBehavior
        case sendKeyBehavior
        case restoresPromptDrafts
        case remembersYoloModePerThread
        case defaultWorkspaceToolID
        case preventsSystemSleepWhileRunning
        case notifiesWhenResponseCompletes
        case notifiesWhenInputIsRequired
        case launchToDashboard
    }
}

struct NeoCodeFontOption: Identifiable, Hashable {
    let id: String
    let title: String
}

enum NeoCodeFontCatalog {
    static let defaultUIFontName = "SF Pro"
    static let defaultCodeFontName = "SF Mono"

    static let uiOptions: [NeoCodeFontOption] = buildUIOptions()
    static let codeOptions: [NeoCodeFontOption] = buildCodeOptions()

    static func postScriptName(for storedName: String, preferFixedPitch: Bool) -> String? {
        guard !storedName.isEmpty,
              storedName != defaultUIFontName,
              storedName != defaultCodeFontName,
              !usesSystemMonospaceStack(storedName)
        else {
            return nil
        }

        if NSFont(name: storedName, size: 13) != nil {
            return storedName
        }

        return preferredMember(forFamily: storedName, preferFixedPitch: preferFixedPitch)?.postScriptName
    }

    static func displayName(for storedName: String, preferFixedPitch: Bool) -> String {
        let fallback = preferFixedPitch ? defaultCodeFontName : defaultUIFontName
        let trimmed = storedName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return fallback
        }

        if usesSystemMonospaceStack(trimmed) {
            return "System Monospace"
        }

        return trimmed
    }

    static func uiOptions(includingSelected storedName: String) -> [NeoCodeFontOption] {
        options(includingSelected: storedName, in: uiOptions, preferFixedPitch: false)
    }

    static func codeOptions(includingSelected storedName: String) -> [NeoCodeFontOption] {
        options(includingSelected: storedName, in: codeOptions, preferFixedPitch: true)
    }

    static func usesSystemMonospaceStack(_ storedName: String) -> Bool {
        storedName.localizedCaseInsensitiveContains("ui-monospace")
    }

    private static func buildUIOptions() -> [NeoCodeFontOption] {
        [NeoCodeFontOption(id: defaultUIFontName, title: defaultUIFontName)]
            + availableFamilyNames().map { NeoCodeFontOption(id: $0, title: $0) }
    }

    private static func buildCodeOptions() -> [NeoCodeFontOption] {
        [NeoCodeFontOption(id: defaultCodeFontName, title: defaultCodeFontName)]
            + availableFamilyNames().filter { family in
                guard let member = preferredMember(forFamily: family, preferFixedPitch: true),
                      let font = NSFont(name: member.postScriptName, size: 13)
                else {
                    return false
                }

                return font.isFixedPitch
            }
            .map { NeoCodeFontOption(id: $0, title: $0) }
    }

    private static func availableFamilyNames() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .filter { $0 != defaultUIFontName && $0 != defaultCodeFontName }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func preferredMember(forFamily family: String, preferFixedPitch: Bool) -> FontMember? {
        let members = fontMembers(forFamily: family)
        let filteredMembers: [FontMember]
        if preferFixedPitch {
            filteredMembers = members.filter { member in
                guard let font = NSFont(name: member.postScriptName, size: 13) else { return false }
                return font.isFixedPitch
            }
        } else {
            filteredMembers = members
        }

        let candidates = filteredMembers.isEmpty ? members : filteredMembers
        return candidates.first(where: \.isRegularLike) ?? candidates.first
    }

    private static func fontMembers(forFamily family: String) -> [FontMember] {
        guard let rawMembers = NSFontManager.shared.availableMembers(ofFontFamily: family) else {
            return []
        }

        return rawMembers.compactMap { member in
            guard member.count >= 2,
                  let postScriptName = member[0] as? String,
                  let displayName = member[1] as? String
            else {
                return nil
            }

            return FontMember(postScriptName: postScriptName, displayName: displayName)
        }
    }

    private static func options(
        includingSelected storedName: String,
        in baseOptions: [NeoCodeFontOption],
        preferFixedPitch: Bool
    ) -> [NeoCodeFontOption] {
        guard !storedName.isEmpty,
              !baseOptions.contains(where: { $0.id == storedName })
        else {
            return baseOptions
        }

        return [NeoCodeFontOption(id: storedName, title: displayName(for: storedName, preferFixedPitch: preferFixedPitch))] + baseOptions
    }

    private struct FontMember {
        let postScriptName: String
        let displayName: String

        var isRegularLike: Bool {
            let lowered = displayName.lowercased()
            return !lowered.contains("bold")
                && !lowered.contains("italic")
                && !lowered.contains("oblique")
                && !lowered.contains("black")
                && !lowered.contains("heavy")
        }
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

enum NeoCodeThemePresetCatalog {
    private static let decodedPresets: ([NeoCodeThemePreset], String?) = {
        let data = Data(json.utf8)

        do {
            return (try JSONDecoder().decode([NeoCodeThemePreset].self, from: data), nil)
        } catch {
            return ([], String(describing: error))
        }
    }()

    static let presets: [NeoCodeThemePreset] = decodedPresets.0
    static let decodeFailureDescription: String? = decodedPresets.1

    static func presets(for kind: ThemeProfileKind) -> [NeoCodeThemePreset] {
        presets.filter { $0.theme(for: kind) != nil }
    }

    private static let json = #"""
    [
      {
        "id": "absolutely",
        "title": "Absolutely",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#f9f9f7",
        "badgeForegroundHex": "#cc7d5e",
        "lightTheme": {
          "accentHex": "#cc7d5e",
          "backgroundHex": "#f9f9f7",
          "foregroundHex": "#2d2d2b",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#00c853",
          "diffRemovedHex": "#ff5f38",
          "skillHex": "#cc7d5e",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#cc7d5e",
          "backgroundHex": "#2d2d2b",
          "foregroundHex": "#f9f9f7",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#00c853",
          "diffRemovedHex": "#ff5f38",
          "skillHex": "#cc7d5e",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "ayu",
        "title": "Ayu",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#0b0e14",
        "badgeForegroundHex": "#e6b450",
        "darkTheme": {
          "accentHex": "#e6b450",
          "backgroundHex": "#0b0e14",
          "foregroundHex": "#bfbdb6",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#7fd962",
          "diffRemovedHex": "#ea6c73",
          "skillHex": "#cda1fa",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "catppuccin",
        "title": "Catppuccin",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#eff1f5",
        "badgeForegroundHex": "#8839ef",
        "lightTheme": {
          "accentHex": "#8839ef",
          "backgroundHex": "#eff1f5",
          "foregroundHex": "#4c4f69",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#40a02b",
          "diffRemovedHex": "#d20f39",
          "skillHex": "#8839ef",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#cba6f7",
          "backgroundHex": "#1e1e2e",
          "foregroundHex": "#cdd6f4",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#a6e3a1",
          "diffRemovedHex": "#f38ba8",
          "skillHex": "#cba6f7",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "codex",
        "title": "Codex",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#ffffff",
        "badgeForegroundHex": "#0169cc",
        "lightTheme": {
          "accentHex": "#0169cc",
          "backgroundHex": "#ffffff",
          "foregroundHex": "#0d0d0d",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#00a240",
          "diffRemovedHex": "#e02e2a",
          "skillHex": "#751ed9",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#0169cc",
          "backgroundHex": "#111111",
          "foregroundHex": "#fcfcfc",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#00a240",
          "diffRemovedHex": "#e02e2a",
          "skillHex": "#b06dff",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "dracula",
        "title": "Dracula",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#282a36",
        "badgeForegroundHex": "#ff79c6",
        "darkTheme": {
          "accentHex": "#ff79c6",
          "backgroundHex": "#282a36",
          "foregroundHex": "#f8f8f2",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#50fa7b",
          "diffRemovedHex": "#ff5555",
          "skillHex": "#ff79c6",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "everforest",
        "title": "Everforest",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#fdf6e3",
        "badgeForegroundHex": "#93b259",
        "lightTheme": {
          "accentHex": "#93b259",
          "backgroundHex": "#fdf6e3",
          "foregroundHex": "#5c6a72",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#8da101",
          "diffRemovedHex": "#f85552",
          "skillHex": "#df69ba",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#a7c080",
          "backgroundHex": "#2d353b",
          "foregroundHex": "#d3c6aa",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#a7c080",
          "diffRemovedHex": "#e67e80",
          "skillHex": "#d699b6",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "github",
        "title": "GitHub",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#ffffff",
        "badgeForegroundHex": "#0969da",
        "lightTheme": {
          "accentHex": "#0969da",
          "backgroundHex": "#ffffff",
          "foregroundHex": "#1f2328",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#1a7f37",
          "diffRemovedHex": "#cf222e",
          "skillHex": "#8250df",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#1f6feb",
          "backgroundHex": "#0d1117",
          "foregroundHex": "#e6edf3",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#3fb950",
          "diffRemovedHex": "#f85149",
          "skillHex": "#bc8cff",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "gruvbox",
        "title": "Gruvbox",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#fbf1c7",
        "badgeForegroundHex": "#458588",
        "lightTheme": {
          "accentHex": "#458588",
          "backgroundHex": "#fbf1c7",
          "foregroundHex": "#3c3836",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#3c3836",
          "diffRemovedHex": "#cc241d",
          "skillHex": "#b16286",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#458588",
          "backgroundHex": "#282828",
          "foregroundHex": "#ebdbb2",
          "contrast": 60,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#ebdbb2",
          "diffRemovedHex": "#cc241d",
          "skillHex": "#b16286",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "linear",
        "title": "Linear",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#f7f8fa",
        "badgeForegroundHex": "#5e6ad2",
        "lightTheme": {
          "accentHex": "#5e6ad2",
          "backgroundHex": "#f7f8fa",
          "foregroundHex": "#2a3140",
          "contrast": 45,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#00a240",
          "diffRemovedHex": "#ba2623",
          "skillHex": "#8160d8",
          "uiFontName": "Inter",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#5e6ad2",
          "backgroundHex": "#17181d",
          "foregroundHex": "#e6e9ef",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#7ad9c0",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#c2a1ff",
          "uiFontName": "Inter",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "lobster",
        "title": "Lobster",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#111827",
        "badgeForegroundHex": "#ff5c5c",
        "darkTheme": {
          "accentHex": "#ff5c5c",
          "backgroundHex": "#111827",
          "foregroundHex": "#e4e4e7",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#22c55e",
          "diffRemovedHex": "#ff5c5c",
          "skillHex": "#3b82f6",
          "uiFontName": "Satoshi",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "material",
        "title": "Material",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#212121",
        "badgeForegroundHex": "#80cbc4",
        "darkTheme": {
          "accentHex": "#80cbc4",
          "backgroundHex": "#212121",
          "foregroundHex": "#eeffff",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#c3e88d",
          "diffRemovedHex": "#f07178",
          "skillHex": "#c792ea",
          "uiFontName": "Satoshi",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "maple",
        "title": "Maple",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#15120F",
        "badgeForegroundHex": "#E8872B",
        "darkTheme": {
          "accentHex": "#E8872B",
          "backgroundHex": "#15120F",
          "foregroundHex": "#E8E0D6",
          "contrast": 77,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#54B47C",
          "diffRemovedHex": "#D68642",
          "skillHex": "#E8872B",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "matrix",
        "title": "Matrix",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#040805",
        "badgeForegroundHex": "#1eff5a",
        "darkTheme": {
          "accentHex": "#1eff5a",
          "backgroundHex": "#040805",
          "foregroundHex": "#b8ffca",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#1eff5a",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#1eff5a",
          "uiFontName": "ui-monospace, \"SFMono-Regular\", \"SF Mono\", Menlo, Consolas, \"Liberation Mono\", monospace",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "monokai",
        "title": "Monokai",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#272822",
        "badgeForegroundHex": "#99947c",
        "darkTheme": {
          "accentHex": "#99947c",
          "backgroundHex": "#272822",
          "foregroundHex": "#f8f8f2",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#86b42b",
          "diffRemovedHex": "#c4265e",
          "skillHex": "#8c6bc8",
          "uiFontName": "ui-monospace, \"SFMono-Regular\", \"SF Mono\", Menlo, Consolas, \"Liberation Mono\", monospace",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "night-owl",
        "title": "Night Owl",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#011627",
        "badgeForegroundHex": "#44596b",
        "darkTheme": {
          "accentHex": "#44596b",
          "backgroundHex": "#011627",
          "foregroundHex": "#d6deeb",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#c5e478",
          "diffRemovedHex": "#ef5350",
          "skillHex": "#c792ea",
          "uiFontName": "ui-monospace, \"SFMono-Regular\", \"SF Mono\", Menlo, Consolas, \"Liberation Mono\", monospace",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "nord",
        "title": "Nord",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#2e3440",
        "badgeForegroundHex": "#88c0d0",
        "darkTheme": {
          "accentHex": "#88c0d0",
          "backgroundHex": "#2e3440",
          "foregroundHex": "#d8dee9",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#a3be8c",
          "diffRemovedHex": "#bf616a",
          "skillHex": "#b48ead",
          "uiFontName": "ui-monospace, \"SFMono-Regular\", \"SF Mono\", Menlo, Consolas, \"Liberation Mono\", monospace",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "notion",
        "title": "Notion",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#ffffff",
        "badgeForegroundHex": "#3183d8",
        "lightTheme": {
          "accentHex": "#3183d8",
          "backgroundHex": "#ffffff",
          "foregroundHex": "#37352f",
          "contrast": 45,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#008000",
          "diffRemovedHex": "#a31515",
          "skillHex": "#0000ff",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#3183d8",
          "backgroundHex": "#191919",
          "foregroundHex": "#d9d9d8",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#4ec9b0",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#3183d8",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "one",
        "title": "One",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#fafafa",
        "badgeForegroundHex": "#526fff",
        "lightTheme": {
          "accentHex": "#526fff",
          "backgroundHex": "#fafafa",
          "foregroundHex": "#383a42",
          "contrast": 45,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#3bba54",
          "diffRemovedHex": "#e45649",
          "skillHex": "#526fff",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#4d78cc",
          "backgroundHex": "#282c34",
          "foregroundHex": "#abb2bf",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#8cc265",
          "diffRemovedHex": "#e05561",
          "skillHex": "#c162de",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "oscurange",
        "title": "Oscurange",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#0b0b0f",
        "badgeForegroundHex": "#f9b98c",
        "darkTheme": {
          "accentHex": "#f9b98c",
          "backgroundHex": "#0b0b0f",
          "foregroundHex": "#e6e6e6",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#40c977",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#479ffa",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "proof",
        "title": "Proof",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#f5f3ed",
        "badgeForegroundHex": "#3d755d",
        "lightTheme": {
          "accentHex": "#3d755d",
          "backgroundHex": "#f5f3ed",
          "foregroundHex": "#2f312d",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#3d755d",
          "diffRemovedHex": "#ba2623",
          "skillHex": "#5f6ac2",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "rose-pine",
        "title": "Rose Pine",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#faf4ed",
        "badgeForegroundHex": "#d7827e",
        "lightTheme": {
          "accentHex": "#d7827e",
          "backgroundHex": "#faf4ed",
          "foregroundHex": "#575279",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#56949f",
          "diffRemovedHex": "#797593",
          "skillHex": "#907aa9",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#ea9a97",
          "backgroundHex": "#232136",
          "foregroundHex": "#e0def4",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#9ccfd8",
          "diffRemovedHex": "#908caa",
          "skillHex": "#c4a7e7",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "sentry",
        "title": "Sentry",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#2d2935",
        "badgeForegroundHex": "#7055f6",
        "darkTheme": {
          "accentHex": "#7055f6",
          "backgroundHex": "#2d2935",
          "foregroundHex": "#e6dff9",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#8ee6d7",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#7055f6",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "solarized",
        "title": "Solarized",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#fdf6e3",
        "badgeForegroundHex": "#b58900",
        "lightTheme": {
          "accentHex": "#b58900",
          "backgroundHex": "#fdf6e3",
          "foregroundHex": "#657b83",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#859900",
          "diffRemovedHex": "#dc322f",
          "skillHex": "#d33682",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#d30102",
          "backgroundHex": "#002b36",
          "foregroundHex": "#839496",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#859900",
          "diffRemovedHex": "#dc322f",
          "skillHex": "#d33682",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "temple",
        "title": "Temple",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#02120c",
        "badgeForegroundHex": "#e4f222",
        "darkTheme": {
          "accentHex": "#e4f222",
          "backgroundHex": "#02120c",
          "foregroundHex": "#c7e6da",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#40c977",
          "diffRemovedHex": "#fa423e",
          "skillHex": "#e4f222",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "tokyo-night",
        "title": "Tokyo Night",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#1a1b26",
        "badgeForegroundHex": "#3d59a1",
        "darkTheme": {
          "accentHex": "#3d59a1",
          "backgroundHex": "#1a1b26",
          "foregroundHex": "#a9b1d6",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#449dab",
          "diffRemovedHex": "#914c54",
          "skillHex": "#9d7cd8",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      },
      {
        "id": "vscode-plus",
        "title": "VS Code Plus",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#ffffff",
        "badgeForegroundHex": "#007acc",
        "lightTheme": {
          "accentHex": "#007acc",
          "backgroundHex": "#ffffff",
          "foregroundHex": "#000000",
          "contrast": 45,
          "isSidebarTranslucent": true,
          "diffAddedHex": "#008000",
          "diffRemovedHex": "#ee0000",
          "skillHex": "#0000ff",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        },
        "darkTheme": {
          "accentHex": "#007acc",
          "backgroundHex": "#1e1e1e",
          "foregroundHex": "#d4d4d4",
          "contrast": 60,
          "isSidebarTranslucent": false,
          "diffAddedHex": "#369432",
          "diffRemovedHex": "#f44747",
          "skillHex": "#000080",
          "uiFontName": "SF Pro",
          "codeFontName": "SF Mono"
        }
      }
    ]
    """#
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
