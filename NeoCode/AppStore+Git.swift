import Foundation
import OSLog

extension AppStore {
    func refreshGitStatus(projectPathOverride: String? = nil) async {
        let projectPath = projectPathOverride ?? selectedProject?.path
        let updatesVisibleState = projectPathOverride == nil || selectedProject?.path == projectPathOverride

        while refreshingGitStatusProjectPath != nil {
            guard !Task.isCancelled else { return }
            await Task.yield()
        }

        guard let projectPath else {
            if projectPathOverride == nil {
                resetGitState()
            }
            return
        }

        refreshingGitStatusProjectPath = projectPath
        if updatesVisibleState {
            isRefreshingGitStatus = true
        }
        defer {
            if refreshingGitStatusProjectPath == projectPath {
                refreshingGitStatusProjectPath = nil
            }
            if updatesVisibleState {
                isRefreshingGitStatus = false
            }
        }

        guard let (_, service) = liveGitService(for: projectPath) else {
            logger.debug("Skipping git status refresh because no daemon service is connected for path=\(projectPath, privacy: .public)")
            return
        }

        let status: GitRepositoryStatus
        let branches: [String]
        let currentBranch: String
        do {
            status = try await service.gitStatus()
            let branchInfo = try await service.listGitBranches()
            branches = branchInfo.branches
            currentBranch = branchInfo.current
        } catch {
            logger.warning("Git status refresh failed path=\(projectPath, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return
        }
        guard !Task.isCancelled else { return }

        guard projectPathOverride != nil || selectedProject?.path == projectPath else { return }

        if !status.isRepository {
            cacheGitState(
                GitCachedState(
                    status: .notRepository,
                    commitPreview: nil,
                    branches: [],
                    selectedBranch: "main"
                ),
                for: projectPath
            )
            if updatesVisibleState {
                applyCachedGitState(for: projectPath)
            }
            return
        }

        let fallbackBranch = gitStateByProjectPath[projectPath]?.selectedBranch ?? selectedBranch
        let resolvedCurrentBranch = currentBranch.isEmpty ? fallbackBranch : currentBranch
        guard !Task.isCancelled else { return }

        guard projectPathOverride != nil || selectedProject?.path == projectPath else { return }

        var resolvedBranches = branches
        if !resolvedCurrentBranch.isEmpty, !resolvedBranches.contains(resolvedCurrentBranch) {
            resolvedBranches.insert(resolvedCurrentBranch, at: 0)
        }

        cacheGitState(
            GitCachedState(
                status: status,
                commitPreview: gitStateByProjectPath[projectPath]?.commitPreview,
                branches: resolvedBranches,
                selectedBranch: resolvedCurrentBranch.isEmpty ? "main" : resolvedCurrentBranch
            ),
            for: projectPath
        )

        if updatesVisibleState {
            applyCachedGitState(for: projectPath)
        }

        if status.hasChanges,
           gitStateByProjectPath[projectPath]?.commitPreview == nil,
           !(updatesVisibleState && isLoadingGitCommitPreview) {
            Task { [weak self] in
                await self?.refreshGitCommitPreview(showLoadingIndicator: false, projectPathOverride: projectPath)
            }
        }
    }

    func refreshGitCommitPreview(
        showLoadingIndicator: Bool = true,
        projectPathOverride: String? = nil
    ) async {
        let projectPath = projectPathOverride ?? selectedProject?.path
        let updatesVisibleState = projectPathOverride == nil || selectedProject?.path == projectPathOverride

        while refreshingGitCommitPreviewProjectPath != nil {
            guard !Task.isCancelled else { return }
            await Task.yield()
        }

        guard let projectPath,
              (projectPathOverride != nil || gitStatus.isRepository)
        else {
            if projectPathOverride == nil {
                gitCommitPreview = nil
            }
            return
        }

        refreshingGitCommitPreviewProjectPath = projectPath
        isRefreshingGitCommitPreview = true
        if showLoadingIndicator && updatesVisibleState {
            isLoadingGitCommitPreview = true
        }
        defer {
            if refreshingGitCommitPreviewProjectPath == projectPath {
                refreshingGitCommitPreviewProjectPath = nil
            }
            isRefreshingGitCommitPreview = false
            if updatesVisibleState {
                isLoadingGitCommitPreview = false
            }
        }

        do {
            let preview = try await loadGitCommitPreview(in: projectPath)
            guard !Task.isCancelled else { return }
            guard projectPathOverride != nil || selectedProject?.path == projectPath else { return }
            updateCachedGitCommitPreview(preview, for: projectPath)
            if updatesVisibleState {
                applyCachedGitState(for: projectPath)
            }
        } catch is CancellationError {
            logger.debug("Cancelled git commit preview refresh for path=\(projectPath, privacy: .public)")
            return
        } catch {
            guard !Task.isCancelled else { return }
            guard projectPathOverride != nil || selectedProject?.path == projectPath else { return }
            logger.warning(
                "Git commit preview refresh failed path=\(projectPath, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func initializeGitRepository() async {
        guard let projectPath = selectedProject?.path else { return }

        isPerformingGitOperation = true
        setGitOperationState(.initializingRepository, for: projectPath)
        defer {
            isPerformingGitOperation = false
            clearGitOperationState(for: projectPath)
        }

        do {
            guard let (_, service) = liveGitService(for: projectPath) else { return }
            try await service.initializeGitRepository()
            lastError = nil
            await refreshGitStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func switchBranch(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let projectPath = selectedProject?.path,
              gitStatus.isRepository
        else { return }

        if trimmed == selectedBranch {
            await refreshGitStatus()
            return
        }

        isPerformingGitOperation = true
        setGitOperationState(.switchingBranch, for: projectPath)
        defer {
            isPerformingGitOperation = false
            clearGitOperationState(for: projectPath)
        }

        do {
            guard let (_, service) = liveGitService(for: projectPath) else { return }
            try await service.switchGitBranch(named: trimmed)
            lastError = nil
            await refreshGitStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createBranch(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let projectPath = selectedProject?.path,
              gitStatus.isRepository
        else { return }

        isPerformingGitOperation = true
        setGitOperationState(.creatingBranch, for: projectPath)
        defer {
            isPerformingGitOperation = false
            clearGitOperationState(for: projectPath)
        }

        do {
            guard let (_, service) = liveGitService(for: projectPath) else { return }
            try await service.createGitBranch(named: trimmed)
            lastError = nil
            await refreshGitStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func commitChanges(message: String, includeUnstaged: Bool, pushAfterCommit: Bool) async -> Bool {
        guard let projectPath = selectedProject?.path, gitStatus.isRepository else { return false }

        guard let resolvedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyTrimmed else {
            return false
        }

        isPerformingGitOperation = true
        setGitOperationState(.committing, for: projectPath)
        logger.info("Starting git commit for project: \(projectPath, privacy: .public)")
        defer {
            isPerformingGitOperation = false
            clearGitOperationState(for: projectPath)
        }

        do {
            guard let (_, service) = liveGitService(for: projectPath) else { return false }
            try await service.commitGitChanges(message: resolvedMessage, includeUnstaged: includeUnstaged)
            if pushAfterCommit {
                setGitOperationState(.pushing, for: projectPath)
                try await service.pushGitChanges()
            }
            lastError = nil
            logger.info("Git commit finished for project: \(projectPath, privacy: .public)")
            applyPostCommitState(pushAfterCommit: pushAfterCommit, for: projectPath)
            scheduleGitRefreshAfterOperation(for: projectPath)
            return true
        } catch {
            logger.error("Git commit failed for project: \(projectPath, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            await refreshGitStatus()
            return false
        }
    }

    func scheduleGitRefreshLoop(for projectPath: String?) {
        guard let projectPath else {
            cancelGitRefreshLoop()
            applyCachedGitState(for: nil)
            return
        }

        applyCachedGitState(for: projectPath)
        scheduleGitFallbackRefresh(for: projectPath)
        scheduleGitRefresh(reason: "project-selected", projectPath: projectPath, refreshCommitPreviewIfLoaded: false, delay: .milliseconds(0))
    }

    func cancelGitRefreshLoop() {
        gitRefreshTask?.cancel()
        gitRefreshTask = nil
        gitRefreshDebounceTask?.cancel()
        gitRefreshDebounceTask = nil
    }

    func scheduleGitFallbackRefresh(for projectPath: String) {
        gitRefreshTask?.cancel()
        gitRefreshTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: gitRefreshFallbackInterval)
                guard !Task.isCancelled else { return }
                guard self.selectedProject?.path == projectPath else { return }
                await self.refreshVisibleGitState(for: projectPath, refreshCommitPreviewIfLoaded: false)
            }
        }
    }

    func scheduleGitRefresh(
        reason: String,
        projectPath: String,
        refreshCommitPreviewIfLoaded: Bool,
        delay: Duration
    ) {
        gitRefreshDebounceTask?.cancel()
        gitRefreshDebounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            guard self.selectedProject?.path == projectPath else { return }
            await self.refreshVisibleGitState(for: projectPath, refreshCommitPreviewIfLoaded: refreshCommitPreviewIfLoaded)
        }
    }

    func refreshVisibleGitState(for projectPath: String, refreshCommitPreviewIfLoaded: Bool) async {
        guard selectedProject?.path == projectPath else { return }

        await refreshGitStatus()

        guard refreshCommitPreviewIfLoaded,
              selectedProject?.path == projectPath,
              gitCommitPreview != nil
        else {
            return
        }

        await refreshGitCommitPreview(showLoadingIndicator: false, projectPathOverride: projectPath)
    }

    func loadGitCommitPreview(in projectPath: String) async throws -> GitCommitPreview {
        guard let (_, service) = liveGitService(for: projectPath) else {
            throw GitClientUnavailableError()
        }

        for (_, delay) in gitCommitPreviewRetryDelays.enumerated() {
            do {
                return try await service.gitCommitPreview()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try await Task.sleep(for: delay)
            }
        }

        return try await service.gitCommitPreview()
    }

    func applyCachedGitState(for projectPath: String?) {
        guard let projectPath, let cached = gitStateByProjectPath[projectPath] else {
            resetGitState()
            return
        }

        if gitStatus != cached.status {
            gitStatus = cached.status
        }
        if gitCommitPreview != cached.commitPreview {
            gitCommitPreview = cached.commitPreview
        }
        if availableBranches != cached.branches {
            availableBranches = cached.branches
        }
        if selectedBranch != cached.selectedBranch {
            selectedBranch = cached.selectedBranch
        }
    }

    func cacheGitState(_ state: GitCachedState, for projectPath: String) {
        gitStateByProjectPath[projectPath] = state
    }

    func cacheCurrentGitState(for projectPath: String) {
        cacheGitState(GitCachedState(
            status: gitStatus,
            commitPreview: gitCommitPreview,
            branches: availableBranches,
            selectedBranch: selectedBranch
        ), for: projectPath)
    }

    func updateCachedGitCommitPreview(_ preview: GitCommitPreview?, for projectPath: String) {
        let existingState = gitStateByProjectPath[projectPath]
        let visibleProjectPath = selectedProject?.path
        let fallbackStatus = visibleProjectPath == projectPath ? gitStatus : .notRepository
        let fallbackBranches = visibleProjectPath == projectPath ? availableBranches : []
        let fallbackSelectedBranch = visibleProjectPath == projectPath ? selectedBranch : (preview?.branch ?? "main")

        cacheGitState(
            GitCachedState(
                status: existingState?.status ?? fallbackStatus,
                commitPreview: preview,
                branches: existingState?.branches ?? fallbackBranches,
                selectedBranch: existingState?.selectedBranch ?? fallbackSelectedBranch
            ),
            for: projectPath
        )
    }

    func applyPostCommitState(pushAfterCommit: Bool, for projectPath: String) {
        let aheadCount = pushAfterCommit ? 0 : (gitStatus.hasRemote ? max(1, gitStatus.aheadCount + 1) : 0)
        let hasRemote = gitStatus.hasRemote
        gitStatus = GitRepositoryStatus(isRepository: true, hasChanges: false, aheadCount: aheadCount, hasRemote: hasRemote)
        cacheCurrentGitState(for: projectPath)
    }

    func scheduleGitRefreshAfterOperation(for projectPath: String) {
        Task { [weak self] in
            guard let self else { return }
            await self.refreshGitStatus(projectPathOverride: projectPath)
            await self.refreshGitCommitPreview(showLoadingIndicator: false, projectPathOverride: projectPath)
            guard self.selectedProject?.path == projectPath else { return }
            self.applyCachedGitState(for: projectPath)
        }
    }

    func setGitOperationState(_ state: GitOperationState, for projectPath: String) {
        gitOperationStateByProjectPath[projectPath] = state
    }

    func clearGitOperationState(for projectPath: String) {
        gitOperationStateByProjectPath.removeValue(forKey: projectPath)
    }

    func resetGitState() {
        gitStatus = .notRepository
        gitCommitPreview = nil
        availableBranches = []
        selectedBranch = "main"
    }

    private func liveGitService(for projectPath: String) -> (ProjectSummary.ID, any NeoCodeServicing)? {
        connectedService(forProjectPath: projectPath)
    }
}

struct GitClientUnavailableError: LocalizedError {
    var errorDescription: String? {
        "NeoCode daemon is not connected for this workspace yet."
    }
}
