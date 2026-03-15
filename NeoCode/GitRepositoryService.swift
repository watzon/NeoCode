import Foundation

struct GitRepositoryStatus: Equatable, Sendable {
    enum PrimaryAction: Equatable, Sendable {
        case commit
        case push

        var title: String {
            switch self {
            case .commit: "Commit"
            case .push: "Push"
            }
        }

        var systemImage: String {
            switch self {
            case .commit: "point.bottomleft.forward.to.point.topright.scurvepath"
            case .push: "arrow.up.circle"
            }
        }
    }

    static let notRepository = GitRepositoryStatus(isRepository: false, hasChanges: false, aheadCount: 0, hasRemote: false)

    let isRepository: Bool
    let hasChanges: Bool
    let aheadCount: Int
    let hasRemote: Bool

    var primaryAction: PrimaryAction {
        hasChanges ? .commit : (aheadCount > 0 ? .push : .commit)
    }

    var isPrimaryActionEnabled: Bool {
        switch primaryAction {
        case .commit:
            return hasChanges
        case .push:
            return aheadCount > 0
        }
    }
}

struct GitFileChange: Equatable, Identifiable, Sendable {
    let path: String
    let stagedStatus: Character
    let unstagedStatus: Character

    nonisolated var id: String { path }

    nonisolated var isUntracked: Bool {
        stagedStatus == "?" && unstagedStatus == "?"
    }

    nonisolated var isStaged: Bool {
        stagedStatus != " " && stagedStatus != "?"
    }

    nonisolated var isUnstaged: Bool {
        unstagedStatus != " " || isUntracked
    }

    nonisolated var statusLabel: String {
        if isUntracked {
            return "New"
        }

        if stagedStatus == "A" || unstagedStatus == "A" {
            return "Added"
        }

        if stagedStatus == "D" || unstagedStatus == "D" {
            return "Deleted"
        }

        if stagedStatus == "R" || unstagedStatus == "R" {
            return "Renamed"
        }

        if stagedStatus == "M" || unstagedStatus == "M" {
            return "Modified"
        }

        return "Changed"
    }
}

struct GitCommitPreview: Equatable, Sendable {
    let branch: String
    let changedFiles: [GitFileChange]
    let stagedAdditions: Int
    let stagedDeletions: Int
    let unstagedAdditions: Int
    let unstagedDeletions: Int

    var fileCount: Int {
        changedFiles.count
    }

    var hasStagedChanges: Bool {
        changedFiles.contains(where: \.isStaged)
    }

    var hasUnstagedChanges: Bool {
        changedFiles.contains(where: \.isUnstaged)
    }

    func additions(includeUnstaged: Bool) -> Int {
        stagedAdditions + (includeUnstaged ? unstagedAdditions : 0)
    }

    func deletions(includeUnstaged: Bool) -> Int {
        stagedDeletions + (includeUnstaged ? unstagedDeletions : 0)
    }
}

struct GitRepositoryService: Sendable {
    nonisolated func metadataWatchURLs(in projectPath: String) async -> [URL] {
        do {
            let repositoryFlag = try await Self.runGit(["rev-parse", "--is-inside-work-tree"], in: projectPath)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard repositoryFlag == "true" else {
                return []
            }

            let gitDirectoryPath = try await Self.runGit(["rev-parse", "--absolute-git-dir"], in: projectPath)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !gitDirectoryPath.isEmpty else {
                return []
            }

            let gitDirectoryURL = URL(fileURLWithPath: gitDirectoryPath, isDirectory: true)
            return [
                gitDirectoryURL.appendingPathComponent("HEAD", isDirectory: false),
                gitDirectoryURL.appendingPathComponent("index", isDirectory: false),
                gitDirectoryURL.appendingPathComponent("refs/heads", isDirectory: true),
                gitDirectoryURL.appendingPathComponent("FETCH_HEAD", isDirectory: false),
                gitDirectoryURL.appendingPathComponent("packed-refs", isDirectory: false),
            ]
        } catch {
            return []
        }
    }

    nonisolated func status(in projectPath: String) async -> GitRepositoryStatus {
        do {
            let repositoryFlag = try await Self.runGit(["rev-parse", "--is-inside-work-tree"], in: projectPath)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard repositoryFlag == "true" else {
                return GitRepositoryStatus(isRepository: false, hasChanges: false, aheadCount: 0, hasRemote: false)
            }

            let output = try await Self.runGit(["status", "--porcelain=v1", "--branch"], in: projectPath)
            async let currentBranch = try? Self.currentBranch(in: projectPath)
            async let remotes = Self.listRemotes(in: projectPath)

            let resolvedCurrentBranch = await currentBranch
            let resolvedRemotes = (try? await remotes) ?? []
            let hasChanges = Self.parseHasChanges(output)
            let aheadCount = (try? await Self.resolveAheadCount(
                in: projectPath,
                currentBranch: resolvedCurrentBranch,
                statusOutput: output,
                remotes: resolvedRemotes
            )) ?? 0

            return GitRepositoryStatus(
                isRepository: true,
                hasChanges: hasChanges,
                aheadCount: aheadCount,
                hasRemote: !resolvedRemotes.isEmpty
            )
        } catch {
            return GitRepositoryStatus(isRepository: false, hasChanges: false, aheadCount: 0, hasRemote: false)
        }
    }

    nonisolated func commitPreview(in projectPath: String) async throws -> GitCommitPreview {
        async let statusOutput = Self.runGit(["status", "--porcelain=v1", "--branch"], in: projectPath)
        async let currentBranch = Self.currentBranch(in: projectPath)
        async let stagedStats = Self.runGit(["diff", "--cached", "--numstat"], in: projectPath)
        async let unstagedStats = Self.runGit(["diff", "--numstat"], in: projectPath)

        let resolvedStatusOutput = try await statusOutput
        let resolvedCurrentBranch = try await currentBranch
        let resolvedStagedStats = try await stagedStats
        let resolvedUnstagedStats = try await unstagedStats

        return GitCommitPreview(
            branch: resolvedCurrentBranch,
            changedFiles: Self.parseChangedFiles(from: resolvedStatusOutput),
            stagedAdditions: Self.parseNumstat(resolvedStagedStats).additions,
            stagedDeletions: Self.parseNumstat(resolvedStagedStats).deletions,
            unstagedAdditions: Self.parseNumstat(resolvedUnstagedStats).additions,
            unstagedDeletions: Self.parseNumstat(resolvedUnstagedStats).deletions
        )
    }

    nonisolated func commit(message: String, includeUnstaged: Bool, in projectPath: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if includeUnstaged {
            _ = try await Self.runGit(["add", "-A"], in: projectPath)
        }

        _ = try await Self.runGit(["commit", "-m", trimmed], in: projectPath)
    }

    nonisolated func push(in projectPath: String) async throws {
        do {
            _ = try await Self.runGit(["push"], in: projectPath)
        } catch {
            let remotes = try await Self.runGit(["remote"], in: projectPath)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard remotes.contains("origin") else {
                throw error
            }

            let branch = try await Self.currentBranch(in: projectPath)
            _ = try await Self.runGit(["push", "-u", "origin", branch], in: projectPath)
        }
    }

    private nonisolated static func parseHasChanges(_ output: String) -> Bool {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines where !line.hasPrefix("## ") {
            return true
        }

        return false
    }

    private nonisolated static func parseAheadCount(from branchLine: String) -> Int {
        guard let range = branchLine.range(of: "ahead ") else { return 0 }
        let suffix = branchLine[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    private nonisolated static func resolveAheadCount(
        in projectPath: String,
        currentBranch: String?,
        statusOutput: String,
        remotes: [String]
    ) async throws -> Int {
        if let branchLine = statusOutput
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("## ") }) {
            let parsedAheadCount = parseAheadCount(from: branchLine)
            if parsedAheadCount > 0 {
                return parsedAheadCount
            }
        }

        if let upstream = try? await runGit(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"], in: projectPath)
            .trimmingCharacters(in: .whitespacesAndNewlines), !upstream.isEmpty {
            return try await revListCount(range: "\(upstream)..HEAD", in: projectPath)
        }

        guard let currentBranch, !currentBranch.isEmpty else { return 0 }
        guard !remotes.isEmpty else { return 0 }

        for remote in remotes {
            if await remoteBranchExists(named: currentBranch, remote: remote, in: projectPath) {
                return try await revListCount(range: "\(remote)/\(currentBranch)..HEAD", in: projectPath)
            }
        }

        return await hasAnyCommits(in: projectPath) ? 1 : 0
    }

    private nonisolated static func revListCount(range: String, in projectPath: String) async throws -> Int {
        let output = try await runGit(["rev-list", "--count", range], in: projectPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(output) ?? 0
    }

    private nonisolated static func listRemotes(in projectPath: String) async throws -> [String] {
        try await runGit(["remote"], in: projectPath)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func remoteBranchExists(named branch: String, remote: String, in projectPath: String) async -> Bool {
        (try? await runGit(["show-ref", "--verify", "--quiet", "refs/remotes/\(remote)/\(branch)"], in: projectPath)) != nil
    }

    private nonisolated static func hasAnyCommits(in projectPath: String) async -> Bool {
        (try? await runGit(["rev-parse", "--verify", "HEAD"], in: projectPath)) != nil
    }

    private nonisolated static func parseChangedFiles(from output: String) -> [GitFileChange] {
        output
            .components(separatedBy: .newlines)
            .compactMap(parseChangedFile)
    }

    private nonisolated static func parseChangedFile(from line: String) -> GitFileChange? {
        guard !line.hasPrefix("## "), line.count >= 4 else { return nil }

        let stagedStatus = line[line.startIndex]
        let unstagedStatus = line[line.index(after: line.startIndex)]
        let pathStart = line.index(line.startIndex, offsetBy: 3)
        var path = String(line[pathStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let renamedPath = path.components(separatedBy: " -> ").last {
            path = renamedPath
        }

        guard !path.isEmpty else { return nil }
        return GitFileChange(path: path, stagedStatus: stagedStatus, unstagedStatus: unstagedStatus)
    }

    private nonisolated static func parseNumstat(_ output: String) -> (additions: Int, deletions: Int) {
        output
            .components(separatedBy: .newlines)
            .reduce(into: (additions: 0, deletions: 0)) { totals, line in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 3 else { return }
                totals.additions += Int(parts[0]) ?? 0
                totals.deletions += Int(parts[1]) ?? 0
            }
    }

    private nonisolated static func currentBranch(in projectPath: String) async throws -> String {
        let branch = try await runGit(["branch", "--show-current"], in: projectPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            return branch
        }

        return try await runGit(["symbolic-ref", "--short", "HEAD"], in: projectPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func runGit(_ arguments: [String], in projectPath: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

        let result = try await SubprocessRunner(process: process).run()
        let string = result.output

        guard result.terminationStatus == 0 else {
            throw NSError(domain: "GitRepositoryService", code: Int(result.terminationStatus), userInfo: [NSLocalizedDescriptionKey: string.trimmingCharacters(in: .whitespacesAndNewlines)])
        }

        return string
    }
}
