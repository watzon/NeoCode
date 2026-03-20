import CryptoKit
import Foundation
import OSLog

enum NeoCodeDaemonBinaryError: LocalizedError {
    case unsupportedArchitecture(String)
    case explicitBinaryVersionMismatch(expected: String, actual: String)
    case discoveredBinaryVersionMismatch(expected: String, actual: String)
    case missingChecksum(String)
    case checksumMismatch(expected: String, actual: String)
    case extractedBinaryMissing
    case versionCommandFailed(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture(let architecture):
            return "NeoCode daemon does not support this Mac architecture yet: \(architecture)."
        case .explicitBinaryVersionMismatch(let expected, let actual):
            return "The configured NeoCode daemon is version \(actual), but NeoCode \(expected) requires an exact daemon match."
        case .discoveredBinaryVersionMismatch(let expected, let actual):
            return "Found NeoCode daemon version \(actual), but NeoCode \(expected) requires an exact daemon match."
        case .missingChecksum(let assetName):
            return "Could not verify the downloaded NeoCode daemon because the checksum for \(assetName) was missing."
        case .checksumMismatch(let expected, let actual):
            return "Downloaded NeoCode daemon failed checksum verification. Expected \(expected), got \(actual)."
        case .extractedBinaryMissing:
            return "Downloaded NeoCode daemon archive did not contain the expected binary."
        case .versionCommandFailed(let message):
            return message
        case .installFailed(let message):
            return message
        }
    }
}

enum NeoCodeDaemonArchitecture: String, CaseIterable {
    case arm64
    case amd64

    nonisolated static var current: NeoCodeDaemonArchitecture? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }

        switch machine {
        case "arm64":
            return .arm64
        case "x86_64":
            return .amd64
        default:
            return nil
        }
    }
}

actor NeoCodeDaemonBinaryManager {
    static let shared = NeoCodeDaemonBinaryManager()

    private let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "DaemonBinaryManager")
    private let ownerDirectoryName = "tech.watzon.NeoCode"
    private let githubRepo = "watzon/NeoCode"

    func resolveExecutableURL(preferredPath: String?, expectedVersion: String, environment: [String: String], status: @escaping @MainActor @Sendable (String) -> Void) async throws -> URL {
        if let preferredPath = normalizedExecutablePath(preferredPath) {
            let url = try resolveExecutableURL(at: preferredPath)
            let actualVersion = try await daemonVersion(at: url)
            guard actualVersion == expectedVersion else {
                throw NeoCodeDaemonBinaryError.explicitBinaryVersionMismatch(expected: expectedVersion, actual: actualVersion)
            }
            return url
        }

        guard let architecture = NeoCodeDaemonArchitecture.current else {
            throw NeoCodeDaemonBinaryError.unsupportedArchitecture(hostArchitectureDescription())
        }

        let managedURL = managedBinaryURL(version: expectedVersion, architecture: architecture)
        if FileManager.default.isExecutableFile(atPath: managedURL.path) {
            let actualVersion = try await daemonVersion(at: managedURL)
            if actualVersion == expectedVersion {
                return managedURL
            }
        }

        let searchPATH = enhancedPATH(from: environment["PATH"])
        for directory in searchPATH.split(separator: ":") {
            let candidateURL = URL(fileURLWithPath: String(directory), isDirectory: true).appendingPathComponent("neocoded")
            guard FileManager.default.isExecutableFile(atPath: candidateURL.path) else { continue }
            do {
                let actualVersion = try await daemonVersion(at: candidateURL)
                if actualVersion == expectedVersion {
                    return candidateURL
                }
                logger.info("Ignoring daemon on PATH because version \(actualVersion, privacy: .public) does not match expected \(expectedVersion, privacy: .public)")
            } catch {
                logger.warning("Ignoring daemon on PATH because its version could not be determined: \(error.localizedDescription, privacy: .public)")
            }
        }

        await status("Downloading daemon")
        return try await downloadAndInstall(version: expectedVersion, architecture: architecture, status: status)
    }

    func daemonVersion(at executableURL: URL) async throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--version"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw NeoCodeDaemonBinaryError.versionCommandFailed("Could not launch NeoCode daemon to inspect its version.")
        }

        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0, !output.isEmpty else {
            throw NeoCodeDaemonBinaryError.versionCommandFailed("Could not determine the NeoCode daemon version from \(executableURL.lastPathComponent).")
        }

        return output
    }

    func managedBinaryURL(version: String, architecture: NeoCodeDaemonArchitecture) -> URL {
        managedInstallDirectory.appendingPathComponent("neocoded-v\(version)-darwin-\(architecture.rawValue)")
    }

    private var managedInstallDirectory: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent(ownerDirectoryName, isDirectory: true)
            .appendingPathComponent("Daemon/bin", isDirectory: true)
    }

    private func downloadAndInstall(version: String, architecture: NeoCodeDaemonArchitecture, status: @escaping @MainActor @Sendable (String) -> Void) async throws -> URL {
        let fileManager = FileManager.default
        let release = releaseAsset(version: version, architecture: architecture)
        let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        await status("Downloading daemon")
        let archiveURL = temporaryDirectory.appendingPathComponent(release.assetName)
        try await downloadFile(from: release.assetURL, to: archiveURL)

        await status("Verifying daemon")
        let checksumsData = try await downloadData(from: release.checksumsURL)
        let expectedChecksum = try parseChecksum(named: release.assetName, from: checksumsData)
        let actualChecksum = try sha256Hex(for: archiveURL)
        guard expectedChecksum.caseInsensitiveCompare(actualChecksum) == .orderedSame else {
            throw NeoCodeDaemonBinaryError.checksumMismatch(expected: expectedChecksum, actual: actualChecksum)
        }

        await status("Installing daemon")
        let extractedDirectory = temporaryDirectory.appendingPathComponent("extract", isDirectory: true)
        try fileManager.createDirectory(at: extractedDirectory, withIntermediateDirectories: true)
        try extractArchive(at: archiveURL, into: extractedDirectory)

        guard let extractedBinaryURL = try findBinary(named: "neocoded", in: extractedDirectory) else {
            throw NeoCodeDaemonBinaryError.extractedBinaryMissing
        }

        try fileManager.createDirectory(at: managedInstallDirectory, withIntermediateDirectories: true)
        let destinationURL = managedBinaryURL(version: version, architecture: architecture)
        let stagedURL = managedInstallDirectory.appendingPathComponent(destinationURL.lastPathComponent + ".tmp")
        try? fileManager.removeItem(at: stagedURL)
        try fileManager.copyItem(at: extractedBinaryURL, to: stagedURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedURL.path)
        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: stagedURL, to: destinationURL)
        logger.info("Installed NeoCode daemon version \(version, privacy: .public) for \(architecture.rawValue, privacy: .public) at \(destinationURL.path, privacy: .public)")
        return destinationURL
    }

    func releaseAsset(version: String, architecture: NeoCodeDaemonArchitecture) -> (assetName: String, assetURL: URL, checksumsURL: URL) {
        let tag = "v\(version)"
        let assetName = "neocoded-\(tag)-darwin-\(architecture.rawValue).tar.gz"
        let baseURL = URL(string: "https://github.com/\(githubRepo)/releases/download/\(tag)/")!
        return (
            assetName: assetName,
            assetURL: baseURL.appendingPathComponent(assetName),
            checksumsURL: baseURL.appendingPathComponent("neocoded-\(tag)-checksums.txt")
        )
    }

    private func downloadData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw NeoCodeDaemonBinaryError.installFailed("Could not download the NeoCode daemon metadata from \(url.absoluteString).")
        }
        return data
    }

    private func downloadFile(from sourceURL: URL, to destinationURL: URL) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw NeoCodeDaemonBinaryError.installFailed("Could not download the NeoCode daemon from \(sourceURL.absoluteString).")
        }

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    func parseChecksum(named assetName: String, from data: Data) throws -> String {
        let content = String(decoding: data, as: UTF8.self)
        for line in content.split(whereSeparator: \ .isNewline) {
            let parts = line.split(whereSeparator: \ .isWhitespace).map(String.init)
            guard parts.count >= 2 else { continue }
            let filename = parts.last!.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if filename == assetName {
                return parts[0]
            }
        }
        throw NeoCodeDaemonBinaryError.missingChecksum(assetName)
    }

    private func sha256Hex(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func extractArchive(at archiveURL: URL, into destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path, "-C", destinationURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NeoCodeDaemonBinaryError.installFailed("Could not extract the NeoCode daemon archive.")
        }
    }

    private func findBinary(named name: String, in rootURL: URL) throws -> URL? {
        let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent == name {
                return url
            }
        }
        return nil
    }

    private func hostArchitectureDescription() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }
}

private extension NeoCodeDaemonBinaryManager {
    func normalizedExecutablePath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    func resolveExecutableURL(at path: String) throws -> URL {
        let candidateURL = URL(fileURLWithPath: path)
        let candidatePath = candidateURL.path
        let resolvedPath = candidateURL.resolvingSymlinksInPath().path
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: candidatePath) || fileManager.isExecutableFile(atPath: resolvedPath) else {
            throw NeoCodeDaemonBinaryError.installFailed("Configured daemon path is not executable: \(candidatePath)")
        }
        return candidateURL
    }

    func enhancedPATH(from existingPATH: String?) -> String {
        var entries = [
            NSHomeDirectory() + "/Library/Application Support/tech.watzon.NeoCode/Daemon/bin",
            NSHomeDirectory() + "/.local/bin",
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
