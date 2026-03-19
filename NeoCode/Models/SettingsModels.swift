import AppKit
import Foundation

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
    var opencodeExecutablePath: String?
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
        opencodeExecutablePath: String? = nil,
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
        self.opencodeExecutablePath = opencodeExecutablePath
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
        opencodeExecutablePath = try container.decodeIfPresent(String.self, forKey: .opencodeExecutablePath)
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
        try container.encodeIfPresent(opencodeExecutablePath, forKey: .opencodeExecutablePath)
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
        case opencodeExecutablePath
        case restoresPromptDrafts
        case remembersYoloModePerThread
        case defaultWorkspaceToolID
        case preventsSystemSleepWhileRunning
        case notifiesWhenResponseCompletes
        case notifiesWhenInputIsRequired
        case launchToDashboard
    }
}
