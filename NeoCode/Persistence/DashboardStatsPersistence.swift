import Foundation

actor PersistedDashboardStatsStore {
    private let fileManager = FileManager.default
    private let cacheDirectoryName = "tech.watzon.NeoCode"
    private let cacheFileName = "dashboard-stats-cache.json"
    private let backupFileName = "dashboard-stats-cache.previous.json"

    func loadCache() -> DashboardStatsCache? {
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL)
        else {
            return nil
        }

        return try? JSONDecoder().decode(DashboardStatsCache.self, from: data)
    }

    func saveCache(_ cache: DashboardStatsCache) {
        guard let cacheURL,
              let data = try? JSONEncoder().encode(cache)
        else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let backupURL,
               let existingData = try? Data(contentsOf: cacheURL),
               existingData != data {
                try? existingData.write(to: backupURL, options: Data.WritingOptions.atomic)
            }
            try data.write(to: cacheURL, options: Data.WritingOptions.atomic)
        } catch {
        }
    }

    private var cacheURL: URL? {
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
            .appendingPathComponent(cacheFileName, isDirectory: false)
    }

    private var backupURL: URL? {
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
            .appendingPathComponent(backupFileName, isDirectory: false)
    }
}
