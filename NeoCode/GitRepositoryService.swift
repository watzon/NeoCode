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

    static let notRepository = GitRepositoryStatus(isRepository: false, hasChanges: false, aheadCount: 0)

    let isRepository: Bool
    let hasChanges: Bool
    let aheadCount: Int

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
    nonisolated func status(in projectPath: String) async -> GitRepositoryStatus {
        await Task.detached(priority: .utility) {
            do {
                let repositoryFlag = try Self.runGit(["rev-parse", "--is-inside-work-tree"], in: projectPath)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard repositoryFlag == "true" else {
                    return GitRepositoryStatus(isRepository: false, hasChanges: false, aheadCount: 0)
                }

                let output = try Self.runGit(["status", "--porcelain=v1", "--branch"], in: projectPath)
                return Self.parseStatus(output)
            } catch {
                return GitRepositoryStatus(isRepository: false, hasChanges: false, aheadCount: 0)
            }
        }.value
    }

    nonisolated func commitPreview(in projectPath: String) async throws -> GitCommitPreview {
        try await Task.detached(priority: .utility) {
            let statusOutput = try Self.runGit(["status", "--porcelain=v1", "--branch"], in: projectPath)
            let currentBranch = try Self.currentBranch(in: projectPath)
            let stagedStats = try Self.runGit(["diff", "--cached", "--numstat"], in: projectPath)
            let unstagedStats = try Self.runGit(["diff", "--numstat"], in: projectPath)

            return GitCommitPreview(
                branch: currentBranch,
                changedFiles: Self.parseChangedFiles(from: statusOutput),
                stagedAdditions: Self.parseNumstat(stagedStats).additions,
                stagedDeletions: Self.parseNumstat(stagedStats).deletions,
                unstagedAdditions: Self.parseNumstat(unstagedStats).additions,
                unstagedDeletions: Self.parseNumstat(unstagedStats).deletions
            )
        }.value
    }

    nonisolated func commit(message: String, includeUnstaged: Bool, in projectPath: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try await Task.detached(priority: .utility) {
            if includeUnstaged {
                _ = try Self.runGit(["add", "-A"], in: projectPath)
            }

            _ = try Self.runGit(["commit", "-m", trimmed], in: projectPath)
        }.value
    }

    nonisolated func push(in projectPath: String) async throws {
        try await Task.detached(priority: .utility) {
            do {
                _ = try Self.runGit(["push"], in: projectPath)
            } catch {
                let remotes = try Self.runGit(["remote"], in: projectPath)
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard remotes.contains("origin") else {
                    throw error
                }

                let branch = try Self.currentBranch(in: projectPath)
                _ = try Self.runGit(["push", "-u", "origin", branch], in: projectPath)
            }
        }.value
    }

    private nonisolated static func parseStatus(_ output: String) -> GitRepositoryStatus {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var aheadCount = 0
        var hasChanges = false

        for line in lines {
            if line.hasPrefix("## ") {
                aheadCount = parseAheadCount(from: line)
                continue
            }

            hasChanges = true
        }

        return GitRepositoryStatus(isRepository: true, hasChanges: hasChanges, aheadCount: aheadCount)
    }

    private nonisolated static func parseAheadCount(from branchLine: String) -> Int {
        guard let range = branchLine.range(of: "ahead ") else { return 0 }
        let suffix = branchLine[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits) ?? 0
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

    private nonisolated static func currentBranch(in projectPath: String) throws -> String {
        let branch = try runGit(["branch", "--show-current"], in: projectPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !branch.isEmpty {
            return branch
        }

        return try runGit(["symbolic-ref", "--short", "HEAD"], in: projectPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func runGit(_ arguments: [String], in projectPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let string = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "GitRepositoryService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: string.trimmingCharacters(in: .whitespacesAndNewlines)])
        }

        return string
    }
}
