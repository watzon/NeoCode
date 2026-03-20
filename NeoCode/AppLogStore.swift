import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppLogStore {
    nonisolated private static let subsystem = "tech.watzon.NeoCode"
    nonisolated private static let appLogPathEnv = "NEOCODE_APP_LOG_PATH"
    nonisolated private static let maxRetainedEntries = 500
    nonisolated private static let pollInterval: Duration = .seconds(1)
    nonisolated private static let startupLookback: TimeInterval = 10

    @ObservationIgnored private let logger = Logger(subsystem: AppLogStore.subsystem, category: "AppLogStore")
    @ObservationIgnored private let fileWriter = AppLogFileWriter()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var knownEntryIDs = Set<String>()
    @ObservationIgnored private var lastCaptureDate = Date().addingTimeInterval(-AppLogStore.startupLookback)
    @ObservationIgnored private var didLogCaptureFailure = false

    var entries: [AppLogEntry] = []
    var captureStatus = "Log capture idle"
    var lastCaptureError: String?

    func start() {
        guard pollTask == nil else { return }
        guard !Self.isRunningTests else {
            captureStatus = "Log capture disabled while tests are running"
            return
        }

        captureStatus = "Capturing app logs"
        let logFileURL = Self.appLogFileURL()

        pollTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.fileWriter.prepare(url: logFileURL)
            } catch {
                self.captureStatus = "App log file unavailable"
                self.lastCaptureError = error.localizedDescription
                return
            }

            while !Task.isCancelled {
                await self.captureAvailableEntries()
                do {
                    try await Task.sleep(for: Self.pollInterval)
                } catch {
                    return
                }
            }
        }
    }

    deinit {
        pollTask?.cancel()
    }

    var appLogFilePath: String {
        Self.appLogFileURL().path
    }

    var daemonLogFilePath: String {
        Self.daemonLogFileURL().path
    }

    func recentEntries(matching query: String?, limit: Int = 120) -> [AppLogEntry] {
        let filtered: [AppLogEntry]
        if let query {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return Array(Array(entries.suffix(limit)).reversed())
            }
            filtered = entries.filter { entry in
                entry.message.localizedCaseInsensitiveContains(trimmed)
                    || entry.category.localizedCaseInsensitiveContains(trimmed)
            }
        } else {
            filtered = entries
        }

        return Array(Array(filtered.suffix(limit)).reversed())
    }

    nonisolated static func appLogFileURL() -> URL {
        if let configured = ProcessInfo.processInfo.environment[appLogPathEnv]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }

        return logsDirectoryURL().appendingPathComponent("neocode-app.log", isDirectory: false)
    }

    nonisolated static func daemonLogFileURL() -> URL {
        if let configured = ProcessInfo.processInfo.environment["NEOCODE_SERVER_LOG_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }

        return logsDirectoryURL().appendingPathComponent("neocoded.log", isDirectory: false)
    }

    private func captureAvailableEntries() async {
        do {
            let fetchedEntries = try await Self.fetchEntries(since: lastCaptureDate)
            if let latestDate = fetchedEntries.last?.date {
                lastCaptureDate = latestDate.addingTimeInterval(0.001)
            }

            let newEntries = fetchedEntries.filter { knownEntryIDs.insert($0.id).inserted }
            guard !newEntries.isEmpty else {
                lastCaptureError = nil
                captureStatus = "Capturing app logs"
                didLogCaptureFailure = false
                return
            }

            entries.append(contentsOf: newEntries)
            if entries.count > Self.maxRetainedEntries {
                let overflow = entries.count - Self.maxRetainedEntries
                let removed = entries.prefix(overflow)
                entries.removeFirst(overflow)
                for entry in removed {
                    knownEntryIDs.remove(entry.id)
                }
            }

            try await fileWriter.append(lines: newEntries.map(\.formattedLine), to: Self.appLogFileURL())
            lastCaptureError = nil
            captureStatus = "Capturing app logs"
            didLogCaptureFailure = false
        } catch {
            lastCaptureError = error.localizedDescription
            captureStatus = "App log capture unavailable"
            guard !didLogCaptureFailure else { return }
            didLogCaptureFailure = true
            logger.error("Failed to capture app logs: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated static func fetchEntries(since date: Date) async throws -> [AppLogEntry] {
        try await Task.detached(priority: .utility) {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: date)
            let predicate = NSPredicate(format: "subsystem == %@", subsystem)
            let rawEntries = try store.getEntries(with: [], at: position, matching: predicate)

            return rawEntries.compactMap { entry in
                guard let logEntry = entry as? OSLogEntryLog,
                      logEntry.subsystem == subsystem
                else {
                    return nil
                }

                let message = logEntry.composedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !message.isEmpty else { return nil }

                return AppLogEntry(
                    date: logEntry.date,
                    level: levelLabel(for: logEntry.level),
                    category: logEntry.category,
                    message: message
                )
            }
            .sorted { $0.date < $1.date }
        }.value
    }

    private nonisolated static func levelLabel(for level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined:
            return "undefined"
        case .debug:
            return "debug"
        case .info:
            return "info"
        case .notice:
            return "notice"
        case .error:
            return "error"
        case .fault:
            return "fault"
        @unknown default:
            return "unknown"
        }
    }

    private nonisolated static func logsDirectoryURL() -> URL {
        let fileManager = FileManager.default
        if let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
            return libraryURL.appendingPathComponent("Logs/NeoCode", isDirectory: true)
        }

        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NeoCode", isDirectory: true)
    }

    private nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private actor AppLogFileWriter {
    func prepare(url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            _ = fileManager.createFile(atPath: url.path, contents: nil)
        }
    }

    func append(lines: [String], to url: URL) throws {
        guard !lines.isEmpty else { return }
        try prepare(url: url)
        let payload = lines.joined(separator: "\n") + "\n"
        guard let data = payload.data(using: .utf8) else { return }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
