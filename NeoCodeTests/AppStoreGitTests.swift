import Foundation
import Testing
@testable import NeoCode

@MainActor
@Suite(.serialized)
struct AppStoreGitTests {
        @MainActor
        @Test func gitRepositoryStatusChoosesPrimaryActionFromChangesAndAheadCount() {
            let changed = GitRepositoryStatus(isRepository: true, hasChanges: true, aheadCount: 0, hasRemote: true)
            let ahead = GitRepositoryStatus(isRepository: true, hasChanges: false, aheadCount: 2, hasRemote: true)
            let clean = GitRepositoryStatus(isRepository: true, hasChanges: false, aheadCount: 0, hasRemote: true)
    
            #expect(changed.primaryAction == .commit)
            #expect(changed.isPrimaryActionEnabled == true)
            #expect(ahead.primaryAction == .push)
            #expect(ahead.isPrimaryActionEnabled == true)
            #expect(clean.primaryAction == .commit)
            #expect(clean.isPrimaryActionEnabled == false)
        }

        @MainActor
        @Test func gitRepositoryMetadataWatchURLsIncludeIndex() async throws {
            let repoURL = try createTemporaryGitRepository()
            defer { try? FileManager.default.removeItem(at: repoURL) }
    
            let watchURLs = await GitRepositoryService().metadataWatchURLs(in: repoURL.path)
            let watchedNames = Set(watchURLs.map(\.lastPathComponent))
    
            #expect(watchedNames.contains("index"))
            #expect(watchedNames.contains("HEAD"))
        }

        @MainActor
        @Test func gitCommitPreviewUsesCombinedPendingStatsForPartiallyStagedLines() async throws {
            let repoURL = try createTemporaryGitRepository()
            defer { try? FileManager.default.removeItem(at: repoURL) }
    
            try write("one\n", to: repoURL.appendingPathComponent("example.txt"))
            try runGit(["add", "example.txt"], in: repoURL)
            try runGit(["commit", "-m", "Initial commit"], in: repoURL)
    
            try write("one staged\n", to: repoURL.appendingPathComponent("example.txt"))
            try runGit(["add", "example.txt"], in: repoURL)
            try write("one final\n", to: repoURL.appendingPathComponent("example.txt"))
    
            let preview = try await GitRepositoryService().commitPreview(in: repoURL.path)
    
            #expect(preview.stagedAdditions == 1)
            #expect(preview.stagedDeletions == 1)
            #expect(preview.unstagedAdditions == 1)
            #expect(preview.unstagedDeletions == 1)
            #expect(preview.additions(includeUnstaged: true) == 1)
            #expect(preview.deletions(includeUnstaged: true) == 1)
            #expect(preview.changedFiles.count == 1)
            #expect(preview.changedFiles[0].isStaged == true)
            #expect(preview.changedFiles[0].isUnstaged == true)
        }

        @MainActor
        @Test func gitCommitPreviewCountsUntrackedFilesWhenIncludingUnstagedChanges() async throws {
            let repoURL = try createTemporaryGitRepository()
            defer { try? FileManager.default.removeItem(at: repoURL) }
    
            try write("tracked\n", to: repoURL.appendingPathComponent("tracked.txt"))
            try runGit(["add", "tracked.txt"], in: repoURL)
            try runGit(["commit", "-m", "Initial commit"], in: repoURL)
    
            try write("alpha\nbeta\n", to: repoURL.appendingPathComponent("new-file.txt"))
    
            let preview = try await GitRepositoryService().commitPreview(in: repoURL.path)
    
            #expect(preview.changedFiles.count == 1)
            #expect(preview.changedFiles[0].isUntracked == true)
            #expect(preview.additions(includeUnstaged: false) == 0)
            #expect(preview.deletions(includeUnstaged: false) == 0)
            #expect(preview.additions(includeUnstaged: true) == 2)
            #expect(preview.deletions(includeUnstaged: true) == 0)
        }

        @MainActor
        @Test func gitCommitPreviewWorksBeforeGitCreatesAnIndexFile() async throws {
            let repoURL = try createTemporaryGitRepository()
            defer { try? FileManager.default.removeItem(at: repoURL) }
    
            let gitDirectoryPath = try runGit(["rev-parse", "--absolute-git-dir"], in: repoURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let indexURL = URL(fileURLWithPath: gitDirectoryPath, isDirectory: true)
                .appendingPathComponent("index", isDirectory: false)
    
            #expect(FileManager.default.fileExists(atPath: indexURL.path) == false)
    
            try write("alpha\nbeta\n", to: repoURL.appendingPathComponent("new-file.txt"))
    
            let preview = try await GitRepositoryService().commitPreview(in: repoURL.path)
    
            #expect(preview.changedFiles.count == 1)
            #expect(preview.changedFiles[0].isUntracked == true)
            #expect(preview.additions(includeUnstaged: true) == 2)
            #expect(preview.deletions(includeUnstaged: true) == 0)
        }

        @MainActor
        @Test func appStoreRefreshGitCommitPreviewKeepsExistingErrorStateOnSuccess() async throws {
            let repoURL = try createTemporaryGitRepository()
            defer { try? FileManager.default.removeItem(at: repoURL) }
    
            try write("tracked\n", to: repoURL.appendingPathComponent("tracked.txt"))
            try runGit(["add", "tracked.txt"], in: repoURL)
            try runGit(["commit", "-m", "Initial commit"], in: repoURL)
    
            let store = AppStore(projects: [ProjectSummary(name: "NeoCode", path: repoURL.path)])
            store.selectedProjectID = try #require(store.projects.first?.id)
    
            await store.refreshGitStatus()
            store.lastError = "keep me"
    
            await store.refreshGitCommitPreview(showLoadingIndicator: false)
    
            #expect(store.lastError == "keep me")
            #expect(store.gitCommitPreview != nil)
        }

        @MainActor
        @Test func appStoreRefreshGitCommitPreviewRetriesSilentlyAndPreservesStalePreviewOnFailure() async throws {
            let missingPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .path
            let store = AppStore(projects: [ProjectSummary(name: "NeoCode", path: missingPath)])
            store.selectedProjectID = try #require(store.projects.first?.id)
            store.gitStatus = GitRepositoryStatus(isRepository: true, hasChanges: true, aheadCount: 0, hasRemote: true)
    
            let existingPreview = GitCommitPreview(
                branch: "main",
                changedFiles: [GitFileChange(path: "example.txt", stagedStatus: "M", unstagedStatus: " ")],
                stagedAdditions: 1,
                stagedDeletions: 0,
                unstagedAdditions: 0,
                unstagedDeletions: 0,
                totalAdditions: 1,
                totalDeletions: 0
            )
            store.gitCommitPreview = existingPreview
            store.lastError = "keep me"
    
            await store.refreshGitCommitPreview(showLoadingIndicator: false)
    
            #expect(store.lastError == "keep me")
            #expect(store.gitCommitPreview == existingPreview)
            #expect(store.isLoadingGitCommitPreview == false)
        }

        @MainActor
        @Test func appStoreRefreshesGitAfterCompletedFileModifyingToolCall() async throws {
            let repoURL = try createTemporaryGitRepository()
            defer { try? FileManager.default.removeItem(at: repoURL) }
    
            try write("tracked\n", to: repoURL.appendingPathComponent("tracked.txt"))
            try runGit(["add", "tracked.txt"], in: repoURL)
            try runGit(["commit", "-m", "Initial commit"], in: repoURL)
    
            let session = SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast)
            let store = AppStore(projects: [ProjectSummary(name: "NeoCode", path: repoURL.path, sessions: [session])])
            store.selectSession("ses_1")
            await store.refreshGitStatus()
            #expect(store.gitStatus.hasChanges == false)
    
            try write("tracked updated\n", to: repoURL.appendingPathComponent("tracked.txt"))
    
            store.apply(event: .messagePartUpdated(
                OpenCodePart(
                    id: "part_tool",
                    sessionID: "ses_1",
                    messageID: "msg_1",
                    type: .tool,
                    text: nil,
                    tool: "apply_patch",
                    mime: nil,
                    filename: nil,
                    url: nil,
                    source: nil,
                    state: OpenCodeToolState(status: .completed, input: nil, output: nil, error: nil),
                    time: nil
                )
            ))
    
            try await Task.sleep(for: .milliseconds(400))
    
            #expect(store.gitStatus.hasChanges == true)
        }

        @MainActor
        @Test func appStoreRefreshesGitAfterCompletedBashGitToolCall() async throws {
            let repoURL = try createTemporaryGitRepository()
            defer { try? FileManager.default.removeItem(at: repoURL) }
    
            try write("tracked\n", to: repoURL.appendingPathComponent("tracked.txt"))
            try runGit(["add", "tracked.txt"], in: repoURL)
            try runGit(["commit", "-m", "Initial commit"], in: repoURL)
            try write("tracked updated\n", to: repoURL.appendingPathComponent("tracked.txt"))
    
            let session = SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast)
            let store = AppStore(projects: [ProjectSummary(name: "NeoCode", path: repoURL.path, sessions: [session])])
            store.selectSession("ses_1")
            await store.refreshGitStatus()
            #expect(store.gitStatus.hasChanges == true)
    
            try runGit(["add", "tracked.txt"], in: repoURL)
            try runGit(["commit", "-m", "Update tracked"], in: repoURL)
    
            store.apply(event: .messagePartUpdated(
                OpenCodePart(
                    id: "part_bash",
                    sessionID: "ses_1",
                    messageID: "msg_1",
                    type: .tool,
                    text: nil,
                    tool: "bash",
                    mime: nil,
                    filename: nil,
                    url: nil,
                    source: nil,
                    state: OpenCodeToolState(
                        status: .completed,
                        input: .object(["command": .string("git commit -m \"Update tracked\"")]),
                        output: nil,
                        error: nil
                    ),
                    time: nil
                )
            ))
    
            try await Task.sleep(for: .milliseconds(400))
    
            #expect(store.gitStatus.hasChanges == false)
        }

        @MainActor
        @Test func appStoreRefreshGitCommitPreviewForBackgroundProjectDoesNotOverwriteVisibleProject() async throws {
            let firstRepoURL = try createTemporaryGitRepository()
            let secondRepoURL = try createTemporaryGitRepository()
            defer {
                try? FileManager.default.removeItem(at: firstRepoURL)
                try? FileManager.default.removeItem(at: secondRepoURL)
            }
    
            try write("first\n", to: firstRepoURL.appendingPathComponent("first.txt"))
            try runGit(["add", "first.txt"], in: firstRepoURL)
            try runGit(["commit", "-m", "Initial first commit"], in: firstRepoURL)
            try write("first changed\n", to: firstRepoURL.appendingPathComponent("first.txt"))
    
            try write("second\n", to: secondRepoURL.appendingPathComponent("second.txt"))
            try runGit(["add", "second.txt"], in: secondRepoURL)
            try runGit(["commit", "-m", "Initial second commit"], in: secondRepoURL)
            try write("second changed\n", to: secondRepoURL.appendingPathComponent("second.txt"))
    
            let store = AppStore(projects: [
                ProjectSummary(name: "First", path: firstRepoURL.path),
                ProjectSummary(name: "Second", path: secondRepoURL.path),
            ])
            store.selectedProjectID = try #require(store.projects.first?.id)
    
            await store.refreshGitStatus()
            await store.refreshGitCommitPreview(showLoadingIndicator: false)
    
            let visiblePreview = try #require(store.gitCommitPreview)
            #expect(visiblePreview.changedFiles.contains(where: { $0.path == "first.txt" }))
    
            await store.refreshGitCommitPreview(
                showLoadingIndicator: false,
                projectPathOverride: secondRepoURL.path
            )
    
            let finalPreview = try #require(store.gitCommitPreview)
            #expect(finalPreview == visiblePreview)
            #expect(finalPreview.changedFiles.contains(where: { $0.path == "first.txt" }))
            #expect(finalPreview.changedFiles.contains(where: { $0.path == "second.txt" }) == false)
        }
}
