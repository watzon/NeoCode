import AppKit
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
            return "Startup, composer, autonomy, and notifications."
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
        switch self {
        case .dashboard:
            return "Dashboard"
        case .lastWorkspace:
            return "Last workspace"
        }
    }
}

enum NeoCodeSendKeyBehavior: String, Codable, CaseIterable, Hashable, Identifiable {
    case returnKey
    case commandReturn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .returnKey:
            return "Return"
        case .commandReturn:
            return "Command-Return"
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
    var startupBehavior: NeoCodeStartupBehavior
    var sendKeyBehavior: NeoCodeSendKeyBehavior
    var restoresPromptDrafts: Bool
    var remembersYoloModePerThread: Bool
    var defaultWorkspaceToolID: String?
    var preventsSystemSleepWhileRunning: Bool
    var notifiesWhenResponseCompletes: Bool
    var notifiesWhenInputIsRequired: Bool

    init(
        startupBehavior: NeoCodeStartupBehavior = .dashboard,
        sendKeyBehavior: NeoCodeSendKeyBehavior = .returnKey,
        restoresPromptDrafts: Bool = true,
        remembersYoloModePerThread: Bool = true,
        defaultWorkspaceToolID: String? = nil,
        preventsSystemSleepWhileRunning: Bool = false,
        notifiesWhenResponseCompletes: Bool = false,
        notifiesWhenInputIsRequired: Bool = false
    ) {
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
              storedName != defaultCodeFontName
        else {
            return nil
        }

        if NSFont(name: storedName, size: 13) != nil {
            return storedName
        }

        return preferredMember(forFamily: storedName, preferFixedPitch: preferFixedPitch)?.postScriptName
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
    var uiFontName: String
    var codeFontName: String
    var selectedLightPresetID: String?
    var selectedDarkPresetID: String?

    init(
        themeMode: NeoCodeThemeMode = .system,
        lightTheme: NeoCodeThemeProfile = .lightDefault,
        darkTheme: NeoCodeThemeProfile = .darkDefault,
        usesPointerCursor: Bool = false,
        uiFontSize: Double = 13,
        codeFontSize: Double = 12,
        uiFontName: String = NeoCodeFontCatalog.defaultUIFontName,
        codeFontName: String = NeoCodeFontCatalog.defaultCodeFontName,
        selectedLightPresetID: String? = nil,
        selectedDarkPresetID: String? = nil
    ) {
        self.themeMode = themeMode
        self.lightTheme = lightTheme
        self.darkTheme = darkTheme
        self.usesPointerCursor = usesPointerCursor
        self.uiFontSize = uiFontSize
        self.codeFontSize = codeFontSize
        self.uiFontName = uiFontName
        self.codeFontName = codeFontName
        self.selectedLightPresetID = selectedLightPresetID
        self.selectedDarkPresetID = selectedDarkPresetID
        syncPresetSelection()
    }

    init(
        themeMode: NeoCodeThemeMode,
        lightTheme: NeoCodeThemeProfile,
        darkTheme: NeoCodeThemeProfile,
        usesPointerCursor: Bool,
        uiFontSize: Double,
        codeFontSize: Double,
        uiFontName: String,
        codeFontName: String
    ) {
        self.init(
            themeMode: themeMode,
            lightTheme: lightTheme,
            darkTheme: darkTheme,
            usesPointerCursor: usesPointerCursor,
            uiFontSize: uiFontSize,
            codeFontSize: codeFontSize,
            uiFontName: uiFontName,
            codeFontName: codeFontName,
            selectedLightPresetID: nil,
            selectedDarkPresetID: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case themeMode
        case lightTheme
        case darkTheme
        case usesPointerCursor
        case uiFontSize
        case codeFontSize
        case uiFontName
        case codeFontName
        case selectedLightPresetID
        case selectedDarkPresetID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeMode = try container.decodeIfPresent(NeoCodeThemeMode.self, forKey: .themeMode) ?? .system
        lightTheme = try container.decodeIfPresent(NeoCodeThemeProfile.self, forKey: .lightTheme) ?? .lightDefault
        darkTheme = try container.decodeIfPresent(NeoCodeThemeProfile.self, forKey: .darkTheme) ?? .darkDefault
        usesPointerCursor = try container.decodeIfPresent(Bool.self, forKey: .usesPointerCursor) ?? false
        uiFontSize = try container.decodeIfPresent(Double.self, forKey: .uiFontSize) ?? 13
        codeFontSize = try container.decodeIfPresent(Double.self, forKey: .codeFontSize) ?? 12
        uiFontName = try container.decodeIfPresent(String.self, forKey: .uiFontName) ?? NeoCodeFontCatalog.defaultUIFontName
        codeFontName = try container.decodeIfPresent(String.self, forKey: .codeFontName) ?? NeoCodeFontCatalog.defaultCodeFontName
        selectedLightPresetID = try container.decodeIfPresent(String.self, forKey: .selectedLightPresetID)
        selectedDarkPresetID = try container.decodeIfPresent(String.self, forKey: .selectedDarkPresetID)
        syncPresetSelection()
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
        switch kind {
        case .light:
            lightTheme = preset.lightTheme
            selectedLightPresetID = preset.id
        case .dark:
            darkTheme = preset.darkTheme
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
            switch kind {
            case .light:
                return preset.lightTheme.matches(profile)
            case .dark:
                return preset.darkTheme.matches(profile)
            }
        }?.id
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
    let lightTheme: NeoCodeThemeProfile
    let darkTheme: NeoCodeThemeProfile
}

enum NeoCodeThemePresetCatalog {
    static let presets: [NeoCodeThemePreset] = {
        let data = Data(json.utf8)
        return (try? JSONDecoder().decode([NeoCodeThemePreset].self, from: data)) ?? []
    }()

    private static let json = """
    [
      {
        "id": "absolutely",
        "title": "Absolutely",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#F3E8E2",
        "badgeForegroundHex": "#C96D4D",
        "lightTheme": {
          "accentHex": "#DF7A53",
          "backgroundHex": "#F8F1EA",
          "foregroundHex": "#241915",
          "contrast": 46,
          "isSidebarTranslucent": false
        },
        "darkTheme": {
          "accentHex": "#F09369",
          "backgroundHex": "#161313",
          "foregroundHex": "#F6EEE9",
          "contrast": 64,
          "isSidebarTranslucent": false
        }
      },
      {
        "id": "catppuccin",
        "title": "Catppuccin",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#ECE6FF",
        "badgeForegroundHex": "#7C63E6",
        "lightTheme": {
          "accentHex": "#8C6CFF",
          "backgroundHex": "#F5F1FF",
          "foregroundHex": "#241B39",
          "contrast": 42,
          "isSidebarTranslucent": false
        },
        "darkTheme": {
          "accentHex": "#B69CFF",
          "backgroundHex": "#181626",
          "foregroundHex": "#F3EEFF",
          "contrast": 60,
          "isSidebarTranslucent": false
        }
      },
      {
        "id": "codex",
        "title": "Codex",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#F5F7FF",
        "badgeForegroundHex": "#2A63FF",
        "lightTheme": {
          "accentHex": "#0285FF",
          "backgroundHex": "#FFFFFF",
          "foregroundHex": "#0D0D0D",
          "contrast": 45,
          "isSidebarTranslucent": false
        },
        "darkTheme": {
          "accentHex": "#339CFF",
          "backgroundHex": "#181818",
          "foregroundHex": "#FFFFFF",
          "contrast": 60,
          "isSidebarTranslucent": false
        }
      },
      {
        "id": "everforest",
        "title": "Everforest",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#EFF3D8",
        "badgeForegroundHex": "#708238",
        "lightTheme": {
          "accentHex": "#7A8F42",
          "backgroundHex": "#F4F1E4",
          "foregroundHex": "#283222",
          "contrast": 43,
          "isSidebarTranslucent": false
        },
        "darkTheme": {
          "accentHex": "#9FBC69",
          "backgroundHex": "#202622",
          "foregroundHex": "#E6E8D5",
          "contrast": 61,
          "isSidebarTranslucent": false
        }
      },
      {
        "id": "github",
        "title": "GitHub",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#EDF4FF",
        "badgeForegroundHex": "#2F6FEB",
        "lightTheme": {
          "accentHex": "#2F6FEB",
          "backgroundHex": "#FFFFFF",
          "foregroundHex": "#1F2328",
          "contrast": 43,
          "isSidebarTranslucent": false
        },
        "darkTheme": {
          "accentHex": "#58A6FF",
          "backgroundHex": "#0D1117",
          "foregroundHex": "#E6EDF3",
          "contrast": 66,
          "isSidebarTranslucent": false
        }
      },
      {
        "id": "gruvbox",
        "title": "Gruvbox",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#F4ECD8",
        "badgeForegroundHex": "#B57614",
        "lightTheme": {
          "accentHex": "#B57614",
          "backgroundHex": "#FBF1C7",
          "foregroundHex": "#3C3836",
          "contrast": 47,
          "isSidebarTranslucent": false
        },
        "darkTheme": {
          "accentHex": "#FABD2F",
          "backgroundHex": "#282828",
          "foregroundHex": "#EBDBB2",
          "contrast": 64,
          "isSidebarTranslucent": false
        }
      },
      {
        "id": "linear",
        "title": "Linear",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#EFEFFF",
        "badgeForegroundHex": "#5D6BFF",
        "lightTheme": {
          "accentHex": "#5E6AD2",
          "backgroundHex": "#F7F7FA",
          "foregroundHex": "#101218",
          "contrast": 41,
          "isSidebarTranslucent": false
        },
        "darkTheme": {
          "accentHex": "#8490FF",
          "backgroundHex": "#08090A",
          "foregroundHex": "#F7F8F8",
          "contrast": 63,
          "isSidebarTranslucent": false
        }
      },
      {
        "id": "notion",
        "title": "Notion",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#F4F4F4",
        "badgeForegroundHex": "#111111",
        "lightTheme": {
          "accentHex": "#111111",
          "backgroundHex": "#FFFFFF",
          "foregroundHex": "#191919",
          "contrast": 40,
          "isSidebarTranslucent": false
        },
        "darkTheme": {
          "accentHex": "#F1F1EF",
          "backgroundHex": "#191919",
          "foregroundHex": "#F1F1EF",
          "contrast": 58,
          "isSidebarTranslucent": false
        }
      },
      {
        "id": "one",
        "title": "One",
        "badgeText": "Aa",
        "badgeBackgroundHex": "#EDF3FF",
        "badgeForegroundHex": "#4C8DFF",
        "lightTheme": {
          "accentHex": "#4C8DFF",
          "backgroundHex": "#FAFBFC",
          "foregroundHex": "#22252A",
          "contrast": 42,
          "isSidebarTranslucent": false
        },
        "darkTheme": {
          "accentHex": "#61AFEF",
          "backgroundHex": "#282C34",
          "foregroundHex": "#ABB2BF",
          "contrast": 63,
          "isSidebarTranslucent": false
        }
      }
    ]
    """
}

struct NeoCodeThemeProfileTransfer: Codable, Hashable {
    var version: Int
    var name: String?
    var accentHex: String
    var backgroundHex: String
    var foregroundHex: String
    var contrast: Double

    init(
        version: Int = 1,
        name: String? = nil,
        accentHex: String,
        backgroundHex: String,
        foregroundHex: String,
        contrast: Double
    ) {
        self.version = version
        self.name = name
        self.accentHex = accentHex
        self.backgroundHex = backgroundHex
        self.foregroundHex = foregroundHex
        self.contrast = contrast
    }

    init(profile: NeoCodeThemeProfile, name: String? = nil) {
        self.init(
            name: name,
            accentHex: profile.accentHex,
            backgroundHex: profile.backgroundHex,
            foregroundHex: profile.foregroundHex,
            contrast: profile.contrast
        )
    }

    var profile: NeoCodeThemeProfile {
        NeoCodeThemeProfile(
            accentHex: accentHex,
            backgroundHex: backgroundHex,
            foregroundHex: foregroundHex,
            contrast: contrast,
            isSidebarTranslucent: false
        )
    }
}

private extension NeoCodeThemeProfile {
    func matches(_ other: NeoCodeThemeProfile) -> Bool {
        accentHex.caseInsensitiveCompare(other.accentHex) == .orderedSame &&
        backgroundHex.caseInsensitiveCompare(other.backgroundHex) == .orderedSame &&
        foregroundHex.caseInsensitiveCompare(other.foregroundHex) == .orderedSame &&
        Int(contrast.rounded()) == Int(other.contrast.rounded())
    }
}
