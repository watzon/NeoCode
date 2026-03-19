import Foundation
import Testing
@testable import NeoCode

@MainActor
@Suite(.serialized)
struct SettingsAndThemeTests {
    @Test func appearanceSettingsInferPresetSelectionFromMatchingThemes() throws {
        let codex = try #require(NeoCodeThemePresetCatalog.presets.first(where: { $0.id == "codex" }))
        let lightTheme = try #require(codex.lightTheme)
        let darkTheme = try #require(codex.darkTheme)
        let appearance = NeoCodeAppearanceSettings(
            themeMode: .system,
            lightTheme: lightTheme,
            darkTheme: darkTheme
        )

        #expect(appearance.selectedLightPresetID == "codex")
        #expect(appearance.selectedDarkPresetID == "codex")
    }

    @Test func themeProfileTransferRoundTripsThemeJSON() throws {
        let transfer = NeoCodeThemeProfileTransfer(
            name: "Codex",
            accentHex: "#0285FF",
            backgroundHex: "#FFFFFF",
            foregroundHex: "#0D0D0D",
            contrast: 45,
            diffAddedHex: "#00A240",
            diffRemovedHex: "#E02E2A",
            skillHex: "#751ED9",
            uiFontName: "Inter",
            codeFontName: "JetBrains Mono"
        )

        let data = try JSONEncoder().encode(transfer)
        let decoded = try JSONDecoder().decode(NeoCodeThemeProfileTransfer.self, from: data)

        #expect(decoded == transfer)
        #expect(decoded.profile.accentHex == "#0285FF")
        #expect(decoded.profile.diffAddedHex == "#00A240")
        #expect(decoded.profile.skillHex == "#751ED9")
        #expect(decoded.profile.uiFontName == "Inter")
        #expect(decoded.profile.codeFontName == "JetBrains Mono")
    }

    @Test func appearanceSettingsMigrateLegacyGlobalFontsIntoBothThemes() throws {
        let payload = #"""
        {
          "themeMode": "dark",
          "lightTheme": {
            "accentHex": "#FFFFFF",
            "backgroundHex": "#F5F5F5",
            "foregroundHex": "#111111",
            "contrast": 45,
            "isSidebarTranslucent": false
          },
          "darkTheme": {
            "accentHex": "#000000",
            "backgroundHex": "#111111",
            "foregroundHex": "#F5F5F5",
            "contrast": 60,
            "isSidebarTranslucent": true
          },
          "uiFontName": "Inter",
          "codeFontName": "JetBrains Mono"
        }
        """#

        let appearance = try JSONDecoder().decode(NeoCodeAppearanceSettings.self, from: Data(payload.utf8))

        #expect(appearance.lightTheme.uiFontName == "Inter")
        #expect(appearance.lightTheme.codeFontName == "JetBrains Mono")
        #expect(appearance.darkTheme.uiFontName == "Inter")
        #expect(appearance.darkTheme.codeFontName == "JetBrains Mono")
    }

    @Test func themePresetCatalogIncludesExpectedThemeCounts() {
        #expect(NeoCodeThemePresetCatalog.decodeFailureDescription == nil)
        #expect(NeoCodeThemePresetCatalog.presets.count == 26)
        #expect(NeoCodeThemePresetCatalog.presets(for: .light).count == 13)
        #expect(NeoCodeThemePresetCatalog.presets(for: .dark).count == 25)
    }

    @Test func themeProfileNormalizesBlankFontNamesToDefaults() {
        let profile = NeoCodeThemeProfile(
            accentHex: "#123456",
            backgroundHex: "#FFFFFF",
            foregroundHex: "#000000",
            contrast: 44,
            isSidebarTranslucent: false,
            uiFontName: "   ",
            codeFontName: ""
        )

        #expect(profile.uiFontName == NeoCodeFontCatalog.defaultUIFontName)
        #expect(profile.codeFontName == NeoCodeFontCatalog.defaultCodeFontName)
    }

    @Test func generalSettingsPreserveWorkspaceAndNotificationChoices() throws {
        let settings = NeoCodeGeneralSettings(
            appLanguage: .french,
            startupBehavior: .lastWorkspace,
            sendKeyBehavior: .commandReturn,
            opencodeExecutablePath: "/opt/homebrew/bin/opencode",
            restoresPromptDrafts: false,
            remembersYoloModePerThread: false,
            defaultWorkspaceToolID: "dev.zed.Zed",
            preventsSystemSleepWhileRunning: true,
            notifiesWhenResponseCompletes: true,
            notifiesWhenInputIsRequired: true
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(NeoCodeGeneralSettings.self, from: data)

        #expect(decoded == settings)
    }
}
