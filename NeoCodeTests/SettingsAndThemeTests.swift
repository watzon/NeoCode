import AppKit
import Foundation
import Testing
@testable import NeoCode

@MainActor
@Suite(.serialized)
struct SettingsAndThemeTests {
        @MainActor
        @Test func promotingEphemeralSessionClearsWorkspacePromptDraft() async throws {
            let store = AppStore(projects: [ProjectSummary(name: "NeoCode", path: "/tmp/NeoCode")])
            let runtime = OpenCodeRuntime()
            let now = Date()
    
            await store.createSession(using: runtime)
            let projectID = try #require(store.selectedProjectID)
            let ephemeralID = try #require(store.selectedSessionID)
    
            store.draft = "Carry this over"
    
            await store.promoteEphemeralSession(
                ephemeralID,
                in: projectID,
                to: OpenCodeSession(
                    id: "ses_promoted",
                    title: nil,
                    parentID: nil,
                    time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
                )
            )
    
            await store.createSession(using: runtime)
            let nextEphemeralID = try #require(store.selectedSessionID)
    
            await store.preparePrompt(for: nextEphemeralID)
    
            #expect(store.draft == "")
        }

        @Test func themeModeMapsToAppKitAppearance() {
            #expect(NeoCodeThemeMode.system.appKitAppearanceName == nil)
            #expect(NeoCodeThemeMode.light.appKitAppearanceName == .aqua)
            #expect(NeoCodeThemeMode.dark.appKitAppearanceName == .darkAqua)
        }

        @MainActor
        @Test func persistedAppSettingsStoreRoundTripsAppearanceSettings() {
            let suiteName = "tech.watzon.NeoCodeTests.app-settings.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            defer {
                defaults.removePersistentDomain(forName: suiteName)
            }
    
            let persistence = PersistedAppSettingsStore(defaults: defaults, key: "appSettings")
            let settings = NeoCodeAppSettings(
                general: .init(
                    appLanguage: .spanish,
                    startupBehavior: .lastWorkspace,
                    sendKeyBehavior: .commandReturn,
                    opencodeExecutablePath: "/opt/homebrew/bin/opencode",
                    restoresPromptDrafts: false,
                    remembersYoloModePerThread: false,
                    defaultWorkspaceToolID: "dev.zed.Zed",
                    preventsSystemSleepWhileRunning: true,
                    notifiesWhenResponseCompletes: true,
                    notifiesWhenInputIsRequired: true
                ),
                appearance: .init(
                    themeMode: .dark,
                    lightTheme: .lightDefault,
                    darkTheme: .init(
                        accentHex: "#55AAFF",
                        backgroundHex: "#14181F",
                        foregroundHex: "#F4F7FA",
                        contrast: 68,
                        isSidebarTranslucent: false,
                        uiFontName: "Instrument Sans",
                        codeFontName: "JetBrains Mono"
                    ),
                    usesPointerCursor: true,
                    uiFontSize: 15,
                    codeFontSize: 14
                )
            )
    
            persistence.saveSettings(settings)
    
            #expect(persistence.loadSettings() == settings)
        }

        @MainActor
        @Test func localizedHelperResolvesSpanishStrings() {
            #expect(localized("Updates", locale: Locale(identifier: "es")) == "Actualizaciones")
            #expect(localized("Language", locale: Locale(identifier: "es")) == "Idioma")
        }

        @MainActor
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

        @MainActor
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

        @MainActor
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

        @MainActor
        @Test func codexPresetCatalogIncludesAllCodexThemes() {
            #expect(NeoCodeThemePresetCatalog.decodeFailureDescription == nil)
            #expect(NeoCodeThemePresetCatalog.presets.count == 26)
            #expect(NeoCodeThemePresetCatalog.presets(for: .light).count == 13)
            #expect(NeoCodeThemePresetCatalog.presets(for: .dark).count == 25)
        }
}
