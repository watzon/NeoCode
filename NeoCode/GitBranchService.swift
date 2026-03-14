import Foundation

struct GitBranchService {
    func listBranches(in projectPath: String) async throws -> [String] {
        let output = try runGit(["branch", "--format=%(refname:short)"], in: projectPath)
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func currentBranch(in projectPath: String) async throws -> String {
        try runGit(["branch", "--show-current"], in: projectPath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGit(_ arguments: [String], in projectPath: String) throws -> String {
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
