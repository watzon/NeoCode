import Foundation

struct GitBranchService: Sendable {
    nonisolated func listBranches(in projectPath: String) async throws -> [String] {
        let output = try await Self.runGit(["branch", "--format=%(refname:short)"], in: projectPath)
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated func currentBranch(in projectPath: String) async throws -> String {
        try await Self.currentBranch(in: projectPath)
    }

    nonisolated func initializeRepository(in projectPath: String) async throws {
        do {
            _ = try await Self.runGit(["init", "-b", "main"], in: projectPath)
        } catch {
            _ = try await Self.runGit(["init"], in: projectPath)
            _ = try? await Self.runGit(["symbolic-ref", "HEAD", "refs/heads/main"], in: projectPath)
        }
    }

    nonisolated func switchBranch(named branch: String, in projectPath: String) async throws {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            _ = try await Self.runGit(["switch", trimmed], in: projectPath)
        } catch {
            _ = try await Self.runGit(["checkout", trimmed], in: projectPath)
        }
    }

    nonisolated func createBranch(named branch: String, in projectPath: String) async throws {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            _ = try await Self.runGit(["switch", "-c", trimmed], in: projectPath)
        } catch {
            _ = try await Self.runGit(["checkout", "-b", trimmed], in: projectPath)
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
            throw NSError(domain: "GitBranchService", code: Int(result.terminationStatus), userInfo: [NSLocalizedDescriptionKey: string.trimmingCharacters(in: .whitespacesAndNewlines)])
        }

        return string
    }
}
