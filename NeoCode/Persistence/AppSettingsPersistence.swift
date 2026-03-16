import Foundation

struct PersistedAppSettingsStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "tech.watzon.NeoCode.appSettings"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func loadSettings() -> NeoCodeAppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(NeoCodeAppSettings.self, from: data)
        else {
            return .init()
        }

        return settings
    }

    func saveSettings(_ settings: NeoCodeAppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
