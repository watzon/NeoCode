import Foundation

struct GitRepositoryStatus: Equatable {
    enum PrimaryAction: Equatable {
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
        hasChanges ? .commit : .push
    }
}

struct GitRepositoryService {
    func status(in projectPath: String) async -> GitRepositoryStatus {
        do {
            let repositoryFlag = try runGit(["rev-parse", "--is-inside-work-tree"], in: projectPath)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard repositoryFlag == "true" else { return .notRepository }

            let output = try runGit(["status", "--porcelain=v1", "--branch"], in: projectPath)
            return parseStatus(output)
        } catch {
            return .notRepository
        }
    }

    private func parseStatus(_ output: String) -> GitRepositoryStatus {
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

    private func parseAheadCount(from branchLine: String) -> Int {
        guard let range = branchLine.range(of: "ahead ") else { return 0 }
        let suffix = branchLine[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits) ?? 0
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
            throw NSError(domain: "GitRepositoryService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: string.trimmingCharacters(in: .whitespacesAndNewlines)])
        }

        return string
    }
}
