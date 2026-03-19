import Foundation

struct PersistedRuntimeProcessRecord: Codable, Equatable {
    let projectPath: String
    let pid: pid_t
    let recordedAt: Date
}

struct PersistedRuntimeProcessSweepResult {
    let totalCount: Int
    let terminatedCount: Int
    let survivingCount: Int
}

struct PersistedRuntimeProcessStore {
    private static let cacheDirectoryName = "tech.watzon.NeoCode"
    private static let cacheFileName = "runtime-processes.json"

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let explicitCacheURL: URL?

    init(cacheURL: URL? = nil) {
        self.explicitCacheURL = cacheURL
    }

    func record(projectPath: String, pid: pid_t) {
        guard pid > 0 else { return }

        var records = loadRecords()
        records.removeAll { $0.projectPath == projectPath || $0.pid == pid }
        records.append(PersistedRuntimeProcessRecord(projectPath: projectPath, pid: pid, recordedAt: Date()))
        saveRecords(records)
    }

    func remove(projectPath: String, pid: pid_t? = nil) {
        let filtered = loadRecords().filter { record in
            if record.projectPath != projectPath {
                return true
            }

            if let pid {
                return record.pid != pid
            }

            return false
        }

        saveRecords(filtered)
    }

    func sweepTrackedProcesses() -> PersistedRuntimeProcessSweepResult {
        let records = loadRecords()
        guard !records.isEmpty else {
            return PersistedRuntimeProcessSweepResult(totalCount: 0, terminatedCount: 0, survivingCount: 0)
        }

        var survivors: [PersistedRuntimeProcessRecord] = []
        var terminatedCount = 0

        for record in records {
            if !ManagedProcessRegistry.isProcessAlive(record.pid) {
                terminatedCount += 1
                continue
            }

            if ManagedProcessRegistry.terminateProcessIdentifier(record.pid) {
                terminatedCount += 1
            } else {
                survivors.append(record)
            }
        }

        saveRecords(survivors)
        return PersistedRuntimeProcessSweepResult(
            totalCount: records.count,
            terminatedCount: terminatedCount,
            survivingCount: survivors.count
        )
    }

    private func loadRecords() -> [PersistedRuntimeProcessRecord] {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let records = try? decoder.decode([PersistedRuntimeProcessRecord].self, from: data)
        else {
            return []
        }

        return records
    }

    private func saveRecords(_ records: [PersistedRuntimeProcessRecord]) {
        guard let url = cacheURL else { return }

        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(records)
            try data.write(to: url, options: .atomic)
        } catch {
        }
    }

    private var cacheURL: URL? {
        if let explicitCacheURL {
            return explicitCacheURL
        }

        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.cacheFileName, isDirectory: false)
    }
}
