import Foundation

struct GitBranchService: Sendable {
    nonisolated func listBranches(in projectPath: String) async throws -> [String] {
        try await Task.detached(priority: .utility) {
            let output = try Self.runGit(["branch", "--format=%(refname:short)"], in: projectPath)
            return output
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }.value
    }

    nonisolated func currentBranch(in projectPath: String) async throws -> String {
        try await Task.detached(priority: .utility) {
            try Self.currentBranchSync(in: projectPath)
        }.value
    }

    nonisolated func initializeRepository(in projectPath: String) async throws {
        try await Task.detached(priority: .utility) {
            do {
                _ = try Self.runGit(["init", "-b", "main"], in: projectPath)
            } catch {
                _ = try Self.runGit(["init"], in: projectPath)
                _ = try? Self.runGit(["symbolic-ref", "HEAD", "refs/heads/main"], in: projectPath)
            }
        }.value
    }

    nonisolated func switchBranch(named branch: String, in projectPath: String) async throws {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try await Task.detached(priority: .utility) {
            do {
                _ = try Self.runGit(["switch", trimmed], in: projectPath)
            } catch {
                _ = try Self.runGit(["checkout", trimmed], in: projectPath)
            }
        }.value
    }

    nonisolated func createBranch(named branch: String, in projectPath: String) async throws {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try await Task.detached(priority: .utility) {
            do {
                _ = try Self.runGit(["switch", "-c", trimmed], in: projectPath)
            } catch {
                _ = try Self.runGit(["checkout", "-b", trimmed], in: projectPath)
            }
        }.value
    }

    private nonisolated static func currentBranchSync(in projectPath: String) throws -> String {
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
            throw NSError(domain: "GitBranchService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: string.trimmingCharacters(in: .whitespacesAndNewlines)])
        }

        return string
    }
}
