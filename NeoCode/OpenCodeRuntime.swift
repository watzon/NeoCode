import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class OpenCodeRuntime {
    private let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "Runtime")
    private static let resolutionLogger = Logger(subsystem: "tech.watzon.NeoCode", category: "RuntimeResolution")
    private static let maxStartupOutputBufferCharacters = 64_000
    private static let maxLastOutputCharacters = 8_000
    private static var didSweepPersistedProcesses = false

    enum State: Equatable {
        case idle
        case starting(projectPath: String)
        case stopping(projectPath: String)
        case running(Connection)
        case failed(projectPath: String, message: String)
    }

    struct Connection: Equatable {
        let projectPath: String
        let baseURL: URL
        let username: String
        let password: String
        let version: String
    }

    private enum StartupPhase: String {
        case idle
        case resolvingConfiguration
        case launchingProcess
        case waitingForListeningAddress
        case waitingForHealthCheck
    }

    private final class RuntimeEntry {
        var process: Process?
        var outputPipe: Pipe?
        var requestedStop = false
        var outputBuffer = ""
        var lastOutput = ""
        var startTask: Task<Connection, Error>?
        var startupPhase: StartupPhase = .idle
        var launchID = UUID()
    }

    private let healthClient = OpenCodeRuntimeHealthClient()
    private let processStore = PersistedRuntimeProcessStore()
    private var entries: [String: RuntimeEntry] = [:]
    private var statesByProjectPath: [String: State] = [:]
    private var connectionsByProjectPath: [String: Connection] = [:]
    var preferredExecutablePath: String?

    init() {
        sweepPersistedProcessesIfNeeded()
    }

    func ensureRunning(for projectPath: String?) async {
        guard let projectPath else { return }

        markUsed(for: projectPath)

        if case .running(let connection) = state(for: projectPath),
           connection.projectPath == projectPath,
           entries[projectPath]?.process?.isRunning == true {
            logger.debug("Runtime already running for project: \(projectPath, privacy: .public)")
            return
        }

        let entry = entry(for: projectPath)
        if let startTask = entry.startTask {
            _ = try? await startTask.value
            return
        }

        logger.info("Ensuring runtime is running for project: \(projectPath, privacy: .public)")
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.start(for: projectPath, entry: entry)
        }
        entry.startTask = task

        _ = try? await task.value
    }

    func stop() {
        for projectPath in Array(entries.keys) {
            stop(projectPath: projectPath)
        }
    }

    func stop(projectPath: String?) {
        guard let projectPath,
              let entry = entries[projectPath]
        else { return }

        logger.debug("Stopping runtime for project: \(projectPath, privacy: .public)")
        stop(entry: entry, projectPath: projectPath)
    }

    func markUsed(for projectPath: String?) {
        guard let projectPath else { return }
        _ = entry(for: projectPath)
    }

    func state(for projectPath: String?) -> State {
        guard let projectPath else { return .idle }
        return statesByProjectPath[projectPath] ?? .idle
    }

    func connection(for projectPath: String?) -> Connection? {
        guard let projectPath else { return nil }
        return connectionsByProjectPath[projectPath]
    }

    func statusLabel(for projectPath: String?) -> String {
        switch state(for: projectPath) {
        case .idle:
            return "Runtime idle"
        case .starting:
            return "Starting runtime"
        case .stopping:
            return "Stopping runtime"
        case .running(let connection):
            return "OpenCode \(connection.version)"
        case .failed:
            return "Runtime failed"
        }
    }

    func detailLabel(for projectPath: String?) -> String {
        switch state(for: projectPath) {
        case .idle:
            return "Select a project"
        case .starting(let projectPath):
            return URL(fileURLWithPath: projectPath).lastPathComponent
        case .stopping(let projectPath):
            return URL(fileURLWithPath: projectPath).lastPathComponent
        case .running(let connection):
            return URL(fileURLWithPath: connection.projectPath).lastPathComponent
        case .failed(_, let message):
            return message
        }
    }

    func failureMessage(for projectPath: String?) -> String? {
        guard case .failed(_, let message) = state(for: projectPath) else {
            return nil
        }

        return message
    }

    private func entry(for projectPath: String) -> RuntimeEntry {
        if let entry = entries[projectPath] {
            return entry
        }

        let entry = RuntimeEntry()
        entries[projectPath] = entry
        return entry
    }

    private func start(for projectPath: String, entry: RuntimeEntry) async throws -> Connection {
        let launchID = UUID()
        entry.launchID = launchID
        defer {
            if entry.launchID == launchID {
                entry.startTask = nil
            }
        }

        guard terminateProcess(entry: entry, projectPath: projectPath, clearStartTask: false) else {
            throw OpenCodeRuntimeError.processTerminationTimedOut
        }
        entry.requestedStop = false
        entry.startupPhase = .resolvingConfiguration
        setState(.starting(projectPath: projectPath), for: projectPath)
        logger.info("Starting OpenCode runtime for project: \(projectPath, privacy: .public)")

        do {
            let configuration = try OpenCodeRuntimeConfiguration(projectPath: projectPath)
            entry.startupPhase = .launchingProcess
            let process = try makeProcess(for: configuration, entry: entry, projectPath: projectPath)
            entry.process = process

            process.terminationHandler = { [runtime = self] process in
                Task { @MainActor in
                    runtime.handleTermination(of: process, projectPath: projectPath, entry: entry, launchID: launchID)
                }
            }

            try process.run()
            ManagedProcessRegistry.shared.register(process)
            processStore.record(projectPath: projectPath, pid: process.processIdentifier)

            entry.startupPhase = .waitingForListeningAddress
            let baseURL = try await waitForBoundURL(entry: entry, timeout: 15)
            entry.startupPhase = .waitingForHealthCheck
            let health = try await healthClient.waitUntilHealthy(
                baseURL: baseURL,
                username: configuration.username,
                password: configuration.password,
                timeout: 12
            )
            logger.info("Runtime healthy on \(baseURL.absoluteString, privacy: .public)")

            let connection = Connection(
                projectPath: projectPath,
                baseURL: baseURL,
                username: configuration.username,
                password: configuration.password,
                version: health.version
            )
            entry.outputBuffer = ""
            entry.startupPhase = .idle
            connectionsByProjectPath[projectPath] = connection
            setState(.running(connection), for: projectPath)
            return connection
        } catch is CancellationError {
            logger.info(
                "Runtime startup cancelled project=\(projectPath, privacy: .public) phase=\(entry.startupPhase.rawValue, privacy: .public) requestedStop=\(entry.requestedStop, privacy: .public) processRunning=\(entry.process?.isRunning == true, privacy: .public) lastOutput=\(Self.startupLogOutput(entry.lastOutput), privacy: .public)"
            )
            _ = terminateProcess(entry: entry, projectPath: projectPath, clearStartTask: false, expectedLaunchID: launchID)
            throw CancellationError()
        } catch {
            logger.error(
                "Runtime failed to start project=\(projectPath, privacy: .public) phase=\(entry.startupPhase.rawValue, privacy: .public) requestedStop=\(entry.requestedStop, privacy: .public) processRunning=\(entry.process?.isRunning == true, privacy: .public) error=\(error.localizedDescription, privacy: .public) lastOutput=\(Self.startupLogOutput(entry.lastOutput), privacy: .public)"
            )
            _ = terminateProcess(entry: entry, projectPath: projectPath, clearStartTask: false, expectedLaunchID: launchID)
            setState(.failed(projectPath: projectPath, message: error.localizedDescription), for: projectPath)
            throw error
        }
    }

    private func stop(entry: RuntimeEntry, projectPath: String) {
        _ = terminateProcess(entry: entry, projectPath: projectPath, clearStartTask: true)
    }

    @discardableResult
    private func terminateProcess(
        entry: RuntimeEntry,
        projectPath: String,
        clearStartTask: Bool,
        expectedLaunchID: UUID? = nil
    ) -> Bool {
        guard expectedLaunchID == nil || entry.launchID == expectedLaunchID else {
            return true
        }

        if clearStartTask {
            entry.startTask?.cancel()
            if expectedLaunchID == nil || entry.launchID == expectedLaunchID {
                entry.startTask = nil
            }
        }

        entry.outputPipe?.fileHandleForReading.readabilityHandler = nil
        entry.requestedStop = true
        connectionsByProjectPath.removeValue(forKey: projectPath)

        if let process = entry.process {
            setState(.stopping(projectPath: projectPath), for: projectPath)
            let result = ManagedProcessRegistry.shared.terminateTrackedProcess(process)
            guard result.didTerminate || !ManagedProcessRegistry.isProcessAlive(result.rootPID) else {
                let message = "OpenCode runtime did not exit cleanly."
                logger.error(
                    "Runtime failed to terminate project=\(projectPath, privacy: .public) pid=\(result.rootPID, privacy: .public)"
                )
                setState(.failed(projectPath: projectPath, message: message), for: projectPath)
                return false
            }

            resetEntryAfterExit(entry: entry, projectPath: projectPath, process: process, launchID: entry.launchID)
            entry.requestedStop = false
            setState(.idle, for: projectPath)
            return true
        }

        resetEntryAfterExit(entry: entry, projectPath: projectPath, process: nil, launchID: entry.launchID)
        entry.requestedStop = false
        setState(.idle, for: projectPath)
        return true
    }

    private func setState(_ state: State, for projectPath: String) {
        statesByProjectPath[projectPath] = state
        if case .running(let connection) = state {
            connectionsByProjectPath[projectPath] = connection
        } else {
            connectionsByProjectPath.removeValue(forKey: projectPath)
        }
    }

    private func makeProcess(for configuration: OpenCodeRuntimeConfiguration, entry: RuntimeEntry, projectPath: String) throws -> Process {
        let process = Process()
        var environment = ProcessInfo.processInfo.environment
        environment["OPENCODE_SERVER_USERNAME"] = configuration.username
        environment["OPENCODE_SERVER_PASSWORD"] = configuration.password
        environment["PATH"] = Self.enhancedPATH(from: environment["PATH"])

        let opencodeExecutableURL = try Self.resolveOpenCodeExecutableURL(
            preferredPath: preferredExecutablePath,
            environment: environment
        )

        process.executableURL = opencodeExecutableURL
        process.arguments = [
            "serve",
            "--hostname", configuration.host,
            "--port", "0",
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: configuration.projectPath)
        process.environment = environment

        let outputPipe = Pipe()
        entry.outputPipe = outputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [runtime = self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let string = String(data: data, encoding: .utf8)
            else { return }

            Task { @MainActor in
                runtime.consumeProcessOutput(string, for: projectPath, entry: entry)
            }
        }

        return process
    }

    private func handleTermination(of process: Process, projectPath: String, entry: RuntimeEntry, launchID: UUID) {
        defer {
            ManagedProcessRegistry.shared.unregister(process)
            processStore.remove(projectPath: projectPath, pid: process.processIdentifier)
        }

        guard entry.launchID == launchID, entry.process === process else { return }

        let wasRequestedStop = entry.requestedStop
        let lastOutput = entry.lastOutput
        resetEntryAfterExit(entry: entry, projectPath: projectPath, process: process, launchID: launchID)

        if wasRequestedStop {
            entry.requestedStop = false
            setState(.idle, for: projectPath)
            return
        }

        let message: String
        if process.terminationReason == .uncaughtSignal {
            message = "Process exited with signal \(process.terminationStatus)"
        } else {
            message = "Process exited with status \(process.terminationStatus)"
        }

        let detail = lastOutput.isEmpty ? message : lastOutput
        setState(.failed(projectPath: projectPath, message: detail), for: projectPath)
        logger.error("Runtime terminated unexpectedly for project \(projectPath, privacy: .public): \(detail, privacy: .public)")
    }

    private func resetEntryAfterExit(entry: RuntimeEntry, projectPath: String, process: Process?, launchID: UUID) {
        guard entry.launchID == launchID else { return }

        if let process {
            process.terminationHandler = nil
            processStore.remove(projectPath: projectPath, pid: process.processIdentifier)
        }

        entry.process = nil
        entry.outputPipe?.fileHandleForReading.readabilityHandler = nil
        entry.outputPipe = nil
        entry.outputBuffer = ""
        entry.lastOutput = ""
        entry.startupPhase = .idle
        connectionsByProjectPath.removeValue(forKey: projectPath)
    }

    private func waitForBoundURL(entry: RuntimeEntry, timeout: TimeInterval) async throws -> URL {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let url = Self.detectedServerURL(in: entry.outputBuffer) {
                return url
            }

            if let process = entry.process, !process.isRunning {
                throw OpenCodeRuntimeError.processExitedBeforeStartup(
                    entry.lastOutput.isEmpty ? "Process exited before startup completed." : entry.lastOutput
                )
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        throw OpenCodeRuntimeError.startupOutputTimedOut
    }

    private func consumeProcessOutput(_ chunk: String, for projectPath: String, entry: RuntimeEntry) {
        entry.lastOutput = Self.recentOutputSnippet(from: chunk, limit: Self.maxLastOutputCharacters)

        if case .starting = state(for: projectPath) {
            entry.outputBuffer = Self.cappedOutputBuffer(
                entry.outputBuffer,
                appending: chunk,
                limit: Self.maxStartupOutputBufferCharacters
            )
        }

        logger.debug("Runtime output for project \(projectPath, privacy: .public): \(chunk, privacy: .private(mask: .hash))")
    }

    nonisolated static func cappedOutputBuffer(_ existing: String, appending chunk: String, limit: Int) -> String {
        guard limit > 0 else { return "" }

        if chunk.count >= limit {
            return String(chunk.suffix(limit))
        }

        let overflow = max(0, existing.count + chunk.count - limit)
        if overflow == 0 {
            return existing + chunk
        }

        return String(existing.dropFirst(overflow)) + chunk
    }

    nonisolated static func recentOutputSnippet(from chunk: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.suffix(limit))
    }

    nonisolated static func startupLogOutput(_ output: String, limit: Int = 240) -> String {
        let normalized = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")

        guard !normalized.isEmpty else { return "<none>" }
        guard normalized.count > limit else { return normalized }
        return String(normalized.suffix(limit))
    }

    nonisolated static func detectedServerURL(in text: String) -> URL? {
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            if let url = detectedServerURL(in: line, requireSignalWords: true) {
                return url
            }
        }

        for line in lines {
            if let url = detectedServerURL(in: line, requireSignalWords: false) {
                return url
            }
        }

        return nil
    }

    private nonisolated static func detectedServerURL(in line: String, requireSignalWords: Bool) -> URL? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        if requireSignalWords,
           !["listen", "server", "ready", "started", "bound", "http"].contains(where: lowercased.contains) {
            return nil
        }

        if let candidate = firstMatch(in: trimmed, pattern: #"https?://[^\s"'<>]+"#),
           let url = normalizedServerURL(from: candidate) {
            return url
        }

        if let candidate = firstMatch(in: trimmed, pattern: #"(?:127\.0\.0\.1|0\.0\.0\.0|localhost|\[::1\]|::1):\d+"#),
           let url = normalizedServerURL(from: candidate) {
            return url
        }

        return nil
    }

    private nonisolated static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }

        return String(text[matchRange])
    }

    private nonisolated static func normalizedServerURL(from candidate: String) -> URL? {
        var cleaned = candidate.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'`.,;:!?)]}"))
        guard !cleaned.isEmpty else { return nil }

        if !cleaned.contains("://") {
            cleaned = "http://\(cleaned)"
        }

        guard var components = URLComponents(string: cleaned),
              let host = components.host,
              let scheme = components.scheme,
              !host.isEmpty,
              !scheme.isEmpty else {
            return nil
        }

        switch host {
        case "0.0.0.0", "::", "::1":
            components.host = "127.0.0.1"
        default:
            break
        }

        components.scheme = scheme.lowercased()
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func sweepPersistedProcessesIfNeeded() {
        guard Self.shouldSweepPersistedProcessesOnLaunch, !Self.didSweepPersistedProcesses else { return }
        Self.didSweepPersistedProcesses = true

        let result = processStore.sweepTrackedProcesses()
        guard result.totalCount > 0 else { return }

        logger.info(
            "Swept persisted runtimes total=\(result.totalCount, privacy: .public) terminated=\(result.terminatedCount, privacy: .public) surviving=\(result.survivingCount, privacy: .public)"
        )
    }

    private static var shouldSweepPersistedProcessesOnLaunch: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    private static func resolveOpenCodeExecutableURL(
        preferredPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let preferredPath = normalizedExecutablePath(preferredPath) {
            return try resolveExecutableURL(at: preferredPath)
        }

        return try resolveExecutableURL(named: "opencode", environment: environment)
    }

    static func resolveExecutableURL(named executableName: String, environment: [String: String]) throws -> URL {
        let fileManager = FileManager.default
        let homeDirectory = NSHomeDirectory()
        let homeEnv = environment["HOME"] ?? "<missing>"
        let pathEnv = environment["PATH"] ?? "<missing>"
        let searchPATH = enhancedPATH(from: environment["PATH"])

        resolutionLogger.info("Resolving \(executableName, privacy: .public) executable")
        resolutionLogger.debug("NSHomeDirectory: \(homeDirectory, privacy: .public)")
        resolutionLogger.debug("FileManager.homeDirectoryForCurrentUser: \(fileManager.homeDirectoryForCurrentUser.path, privacy: .public)")
        resolutionLogger.debug("HOME env: \(homeEnv, privacy: .public)")
        resolutionLogger.debug("PATH env: \(pathEnv, privacy: .public)")
        resolutionLogger.debug("Search PATH: \(searchPATH, privacy: .public)")

        for directory in searchPATH.split(separator: ":") {
            let candidateURL = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(executableName)
            let candidatePath = candidateURL.path
            let resolvedPath = candidateURL.resolvingSymlinksInPath().path
            let exists = fileManager.fileExists(atPath: candidatePath)
            let executable = fileManager.isExecutableFile(atPath: candidatePath)
            let resolvedExists = fileManager.fileExists(atPath: resolvedPath)
            let resolvedExecutable = fileManager.isExecutableFile(atPath: resolvedPath)

            resolutionLogger.debug("PATH candidate: \(candidatePath, privacy: .public) exists=\(exists) executable=\(executable) resolved=\(resolvedPath, privacy: .public) resolvedExists=\(resolvedExists) resolvedExecutable=\(resolvedExecutable)")

            if executable || resolvedExecutable {
                return candidateURL
            }
        }

        let details = "HOME=\(homeEnv) PATH=\(pathEnv) SEARCH_PATH=\(searchPATH)"
        throw OpenCodeRuntimeError.executableNotFound(details)
    }

    static func resolveExecutableURL(at path: String) throws -> URL {
        let fileManager = FileManager.default
        let candidateURL = URL(fileURLWithPath: path)
        let candidatePath = candidateURL.path
        let resolvedPath = candidateURL.resolvingSymlinksInPath().path
        let executable = fileManager.isExecutableFile(atPath: candidatePath)
        let resolvedExecutable = fileManager.isExecutableFile(atPath: resolvedPath)

        resolutionLogger.info("Resolving explicit opencode executable path")
        resolutionLogger.debug("Explicit candidate: \(candidatePath, privacy: .public) executable=\(executable) resolved=\(resolvedPath, privacy: .public) resolvedExecutable=\(resolvedExecutable)")

        guard executable || resolvedExecutable else {
            throw OpenCodeRuntimeError.executableNotFound("Configured path is not executable: \(candidatePath)")
        }

        return candidateURL
    }

    static func normalizedExecutablePath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    static func enhancedPATH(from existingPATH: String?) -> String {
        var entries = [
            NSHomeDirectory() + "/.bun/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]

        if let existingPATH {
            entries.append(contentsOf: existingPATH.split(separator: ":").map(String.init))
        }

        return Array(NSOrderedSet(array: entries)).compactMap { $0 as? String }.joined(separator: ":")
    }
}

private struct OpenCodeRuntimeConfiguration {
    let projectPath: String
    let host: String
    let username: String
    let password: String

    init(projectPath: String) throws {
        self.projectPath = projectPath
        self.host = "127.0.0.1"
        self.username = "opencode"
        self.password = Self.randomPassword()
    }

    private static func randomPassword(length: Int = 24) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}

enum OpenCodeRuntimeError: LocalizedError {
    case executableNotFound(String)
    case invalidServerResponse
    case healthCheckTimedOut
    case startupOutputTimedOut
    case processExitedBeforeStartup(String)
    case processTerminationTimedOut

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let details):
            return "Could not find the OpenCode CLI. \(details)"
        case .invalidServerResponse:
            return "OpenCode returned an invalid response while starting."
        case .healthCheckTimedOut:
            return "OpenCode did not become healthy before the startup timeout."
        case .startupOutputTimedOut:
            return "OpenCode did not report a listening address before the startup timeout."
        case .processExitedBeforeStartup(let message):
            return message
        case .processTerminationTimedOut:
            return "The previous OpenCode runtime did not exit cleanly, so NeoCode refused to start a duplicate background process."
        }
    }
}
