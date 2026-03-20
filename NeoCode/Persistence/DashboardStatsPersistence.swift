import Foundation

actor PersistedDashboardStatsStore {
    private let fileManager = FileManager.default
    private let cacheDirectoryName = "tech.watzon.NeoCode"
    private let cacheFileName = "dashboard-stats-cache.json"
    private let backupFileName = "dashboard-stats-cache.previous.json"
    private let baseDirectoryURL: URL?

    init(baseDirectoryURL: URL? = nil) {
        self.baseDirectoryURL = baseDirectoryURL
    }

    func loadCache() async -> DashboardStatsCache? {
        guard let cacheURL,
              let data = try? Data(contentsOf: cacheURL)
        else {
            return nil
        }

        return await MainActor.run {
            try? JSONDecoder().decode(DashboardStatsCache.self, from: data)
        }
    }

    func saveCache(_ cache: DashboardStatsCache) async {
        guard let cacheURL else {
            return
        }

        let data = await MainActor.run {
            try? JSONEncoder().encode(cache)
        }
        guard let data else { return }

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
        guard let applicationSupportURL = baseDirectoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
            .appendingPathComponent(cacheFileName, isDirectory: false)
    }

    private var backupURL: URL? {
        guard let applicationSupportURL = baseDirectoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
            .appendingPathComponent(backupFileName, isDirectory: false)
    }
}
