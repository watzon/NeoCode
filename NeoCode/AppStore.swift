import Foundation
import Observation
import OSLog

nonisolated struct AppStorePerformanceOptions: Sendable {
    var projectPersistenceDebounce: Duration = .milliseconds(250)
    var streamingPersistenceDebounce: Duration = .seconds(2)
    var deltaFlushDebounce: Duration = .milliseconds(33)
}

@MainActor
@Observable
final class AppStore {
    private let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "AppStore")
    private let projectPersistence = PersistedProjectsStore()
    private let promptDraftPersistence = PersistedPromptDraftsStore()
    private let yoloPreferencePersistence = PersistedYoloPreferencesStore()
    private let favoriteModelPersistence = PersistedFavoriteModelsStore()
    private let dashboardStatsService = DashboardStatsService()
    private let newSessionTitle = SessionSummary.defaultTitle
    private let autoRespondedPermissionTTL: TimeInterval = 60 * 60
    private let performanceOptions: AppStorePerformanceOptions
    private let isPersistenceEnabled: Bool

    private struct GitCachedState {
        let status: GitRepositoryStatus
        let commitPreview: GitCommitPreview?
        let branches: [String]
        let selectedBranch: String
    }

    private enum ProjectPersistenceMode {
        case standard
        case streaming
    }

    private struct BufferedTextDeltaKey: Hashable {
        let projectID: ProjectSummary.ID
        let sessionID: String
        let partID: String
    }

    private struct BufferedTextDelta {
        let messageID: String
        var text: String
        var updatedAt: Date
    }

    private struct DashboardRuntimeService {
        let service: any OpenCodeServicing
        let shouldStopAfterUse: Bool
    }

    enum GitOperationState: Equatable {
        case initializingRepository
        case switchingBranch
        case creatingBranch
        case committing
        case pushing

        var title: String {
            switch self {
            case .initializingRepository:
                return "Initializing Git"
            case .switchingBranch:
                return "Switching"
            case .creatingBranch:
                return "Creating"
            case .committing:
                return "Committing"
            case .pushing:
                return "Pushing"
            }
        }
    }

    var projects: [ProjectSummary]
    var selectedProjectID: ProjectSummary.ID?
    var selectedContent: AppContentSelection
    var draft = "" {
        didSet {
            persistDraftIfNeeded()
        }
    }
    var attachedFiles: [ComposerAttachment] = []
    var availableModels: [ComposerModelOption] = []
    var selectedModelID: String?
    var selectedModelVariant: String?
    var selectedAgent = ""
    var availableAgents: [String] = []
    var availableCommands: [OpenCodeCommand] = []
    var availableThinkingLevels: [String] = []
    var selectedThinkingLevel: String?
    var selectedBranch = "main"
    var availableBranches: [String] = []
    var gitStatus = GitRepositoryStatus.notRepository
    var gitCommitPreview: GitCommitPreview?
    var isRefreshingGitStatus = false
    var isLoadingGitCommitPreview = false
    var isPerformingGitOperation = false
    var isLoadingSessions = false
    var loadingTranscriptSessionID: String?
    var isSending = false
    var isRespondingToPrompt = false
    var isPromptReady = true
    var promptLoadingText: String?
    var dashboardSnapshot: DashboardSnapshot?
    var dashboardStatus: DashboardRefreshStatus = .idle
    var lastError: String?

    var sortedAvailableModels: [ComposerModelOption] {
        availableModels.sorted { left, right in
            let leftFavorite = favoriteModelIDs.contains(left.id)
            let rightFavorite = favoriteModelIDs.contains(right.id)
            if leftFavorite != rightFavorite {
                return leftFavorite
            }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    func isFavoriteModel(id: String) -> Bool {
        favoriteModelIDs.contains(id)
    }

    func toggleFavoriteModel(id: String) {
        if favoriteModelIDs.contains(id) {
            favoriteModelIDs.remove(id)
        } else {
            favoriteModelIDs.insert(id)
        }
        guard isPersistenceEnabled else { return }
        favoriteModelPersistence.saveFavoriteModelIDs(favoriteModelIDs)
    }

    private var composerOptionsProjectPath: String?
    private let runtimeIdleTTL: Duration = .seconds(60)
    private let gitRefreshFallbackInterval: Duration = .seconds(90)
    private var isRefreshingGitCommitPreview = false
    private var liveServices: [ProjectSummary.ID: any OpenCodeServicing] = [:]
    private var serviceConnectionIdentifiers: [ProjectSummary.ID: String] = [:]
    private var eventTasks: [ProjectSummary.ID: Task<Void, Never>] = [:]
    private var eventSubscriptionTokens: [ProjectSummary.ID: UUID] = [:]
    private var refreshTask: Task<Void, Never>?
    private var gitRefreshTask: Task<Void, Never>?
    private var gitRefreshDebounceTask: Task<Void, Never>?
    private var gitMonitorSetupTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var subscribedConnectionIdentifiers: [ProjectSummary.ID: String] = [:]
    private var runtimeIdleTasks: [ProjectSummary.ID: Task<Void, Never>] = [:]
    private var gitStateByProjectPath: [String: GitCachedState] = [:]
    private var gitOperationStateByProjectPath: [String: GitOperationState] = [:]
    private var gitRepositoryMonitor: GitRepositoryMonitor?
    private var streamingRecoveryTasks: [String: Task<Void, Never>] = [:]
    private var transcriptStateBySessionID: [String: SessionTranscriptState] = [:]
    private var messageRoles: [String: ChatMessage.Role] = [:]
    private var liveSessionStatuses: [String: OpenCodeSessionActivity] = [:]
    private var pendingPermissionsBySession: [String: [OpenCodePermissionRequest]] = [:]
    private var pendingQuestionsBySession: [String: [OpenCodeQuestionRequest]] = [:]
    private var promptDraftsByKey: [String: String] = [:]
    private var loadedPromptKeys = Set<String>()
    private var isHydratingPrompt = false
    private var promptPersistTask: Task<Void, Never>?
    private var yoloSessionKeys: Set<String>
    private var favoriteModelIDs: Set<String> = []
    private var autoRespondedPermissionIDs: [String: Date] = [:]
    private var activeTranscriptLoadKeys = Set<String>()
    private var locallyActiveSessionIDs = Set<String>()
    private var bufferedTextDeltas: [BufferedTextDeltaKey: BufferedTextDelta] = [:]
    private var bufferedTextDeltaOrder: [BufferedTextDeltaKey] = []
    private var bufferedDeltaFlushTask: Task<Void, Never>?
    private var hasPendingProjectPersistence = false
    private var projectPersistenceSaveCount = 0
    private var dashboardPollingTask: Task<Void, Never>?
    private var dashboardRefreshTask: Task<Void, Never>?
    private var dashboardRefreshPending = false
    private var dashboardDirtySessions: [ProjectSummary.ID: Set<String>] = [:]
    private var isDashboardActive = false

    init() {
        let normalizedProjects = Self.normalizedProjects(PersistedProjectsStore().loadProjects())
        let extractedState = Self.extractTranscriptState(from: normalizedProjects)
        self.projects = extractedState.projects
        self.transcriptStateBySessionID = extractedState.transcripts
        self.selectedProjectID = extractedState.projects.first?.id
        self.selectedContent = .dashboard
        self.loadingTranscriptSessionID = nil
        self.yoloSessionKeys = PersistedYoloPreferencesStore().loadYoloSessionKeys()
        self.favoriteModelIDs = favoriteModelPersistence.loadFavoriteModelIDs()
        self.performanceOptions = AppStorePerformanceOptions()
        self.isPersistenceEnabled = true
        seedComposerDefaults()
    }

    init(
        projects: [ProjectSummary],
        performanceOptions: AppStorePerformanceOptions = AppStorePerformanceOptions(),
        isPersistenceEnabled: Bool = false
    ) {
        let normalizedProjects = Self.normalizedProjects(projects)
        let extractedState = Self.extractTranscriptState(from: normalizedProjects)
        self.projects = extractedState.projects
        self.transcriptStateBySessionID = extractedState.transcripts
        self.selectedProjectID = extractedState.projects.first?.id
        self.selectedContent = .dashboard
        self.loadingTranscriptSessionID = nil
        self.yoloSessionKeys = isPersistenceEnabled ? PersistedYoloPreferencesStore().loadYoloSessionKeys() : []
        self.favoriteModelIDs = isPersistenceEnabled ? favoriteModelPersistence.loadFavoriteModelIDs() : []
        self.performanceOptions = performanceOptions
        self.isPersistenceEnabled = isPersistenceEnabled
        seedComposerDefaults()
    }

    var selectedSessionID: String? {
        get {
            guard case .session(let sessionID) = selectedContent else { return nil }
            return sessionID
        }
        set {
            if let newValue {
                selectedContent = .session(newValue)
            } else {
                selectedContent = .dashboard
            }
        }
    }

    var isDashboardSelected: Bool {
        if case .dashboard = selectedContent {
            return true
        }
        return false
    }

    var dashboardProjectSignature: String {
        projects
            .map(\.path)
            .sorted()
            .joined(separator: "|")
    }

    var debugBufferedTextDeltaCount: Int {
        bufferedTextDeltas.count
    }

    var debugProjectPersistenceSaveCount: Int {
        projectPersistenceSaveCount
    }

    var selectedSession: SessionSummary? {
        guard let selectedSessionID else { return nil }
        return projects
            .flatMap(\.sessions)
            .first(where: { $0.id == selectedSessionID })
    }

    var selectedTranscript: [ChatMessage] {
        transcript(for: selectedSessionID)
    }

    func transcript(for sessionID: String?) -> [ChatMessage] {
        guard let sessionID else { return [] }
        return transcriptStateBySessionID[sessionID]?.messages ?? []
    }

    func transcriptRevisionToken(for sessionID: String?) -> Int {
        guard let sessionID else { return 0 }
        return transcriptStateBySessionID[sessionID]?.revision ?? 0
    }

    func sessionSummary(for sessionID: String) -> SessionSummary? {
        session(for: sessionID)
    }

    var selectedProject: ProjectSummary? {
        if let selectedSessionID,
           let project = projects.first(where: { project in
                project.sessions.contains(where: { $0.id == selectedSessionID })
           }) {
            return project
        }

        if let selectedProjectID,
           let project = projects.first(where: { $0.id == selectedProjectID }) {
            return project
        }

        return projects.first
    }

    var currentGitOperationState: GitOperationState? {
        guard let projectPath = selectedProject?.path else { return nil }
        return gitOperationStateByProjectPath[projectPath]
    }

    var selectedSessionActivity: OpenCodeSessionActivity? {
        guard let selectedSessionID,
              isSessionLocallyActive(selectedSessionID)
        else {
            return nil
        }
        return liveSessionStatuses[selectedSessionID]
    }

    func project(for sessionID: String) -> ProjectSummary? {
        projects.first(where: { project in
            project.sessions.contains(where: { $0.id == sessionID })
        })
    }

    func preferredEditorID(for projectID: ProjectSummary.ID) -> String? {
        projects.first(where: { $0.id == projectID })?.settings.preferredEditorID
    }

    func setPreferredEditorID(_ editorID: String?, for projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[projectIndex].settings.preferredEditorID = editorID
        scheduleProjectPersistence()
    }

    func setProjectCollapsed(_ isCollapsed: Bool, for projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[projectIndex].settings.isCollapsedInSidebar = isCollapsed
        scheduleProjectPersistence()
    }

    func pendingPermission(for sessionID: String) -> OpenCodePermissionRequest? {
        pendingPermissionsBySession[sessionID]?.first
    }

    func pendingQuestion(for sessionID: String) -> OpenCodeQuestionRequest? {
        pendingQuestionsBySession[sessionID]?.first
    }

    func isYoloModeEnabled(for sessionID: String) -> Bool {
        guard let key = yoloPreferenceKey(for: sessionID) else { return false }
        return yoloSessionKeys.contains(key)
    }

    func setYoloMode(_ enabled: Bool, for sessionID: String) {
        guard let key = yoloPreferenceKey(for: sessionID) else { return }

        if enabled {
            yoloSessionKeys.insert(key)
        } else {
            yoloSessionKeys.remove(key)
        }

        if isPersistenceEnabled {
            yoloPreferencePersistence.saveYoloSessionKeys(yoloSessionKeys)
        }
    }

    func preparePrompt(for sessionID: String?) async {
        guard isPersistenceEnabled else {
            isPromptReady = true
            promptLoadingText = nil
            isHydratingPrompt = true
            if let sessionID,
               let promptKey = promptDraftKey(for: sessionID) {
                draft = promptDraftsByKey[promptKey] ?? ""
            } else {
                draft = ""
            }
            isHydratingPrompt = false
            return
        }

        guard let sessionID,
              let promptKey = promptDraftKey(for: sessionID)
        else {
            isPromptReady = true
            promptLoadingText = nil
            isHydratingPrompt = true
            draft = ""
            isHydratingPrompt = false
            return
        }

        if loadedPromptKeys.contains(promptKey), let cached = promptDraftsByKey[promptKey] {
            isPromptReady = true
            promptLoadingText = nil
            isHydratingPrompt = true
            draft = cached
            isHydratingPrompt = false
            return
        }

        isPromptReady = false
        promptLoadingText = promptDraftsByKey[promptKey].flatMap { $0.nonEmptyTrimmed }

        let loadedDraft = await promptDraftPersistence.loadDraft(forKey: promptKey)
        guard selectedSessionID == sessionID else {
            promptDraftsByKey[promptKey] = loadedDraft
            loadedPromptKeys.insert(promptKey)
            return
        }

        promptDraftsByKey[promptKey] = loadedDraft
        loadedPromptKeys.insert(promptKey)
        isHydratingPrompt = true
        draft = loadedDraft
        isHydratingPrompt = false
        promptLoadingText = nil
        isPromptReady = true
    }

    func selectProject(_ destinationProjectID: ProjectSummary.ID) {
        guard projects.contains(where: { $0.id == destinationProjectID }) else { return }
        if selectedProjectID != destinationProjectID {
            discardSelectedEphemeralSessionIfNeeded()
        }
        selectedProjectID = destinationProjectID
        if let selectedSessionID,
           projectID(for: selectedSessionID) != destinationProjectID {
            self.selectedSessionID = nil
            primePromptState(for: nil)
        }

        scheduleGitRefreshLoop(for: projectPath(for: destinationProjectID))
        flushPendingProjectPersistence()
    }

    func selectDashboard() {
        discardSelectedEphemeralSessionIfNeeded()
        selectedSessionID = nil
        loadingTranscriptSessionID = nil
        primePromptState(for: nil)
        scheduleGitRefreshLoop(for: selectedProject?.path)
        flushPendingProjectPersistence()
    }

    func selectSession(_ sessionID: String) {
        guard selectedSessionID != sessionID else { return }
        discardSelectedEphemeralSessionIfNeeded(excluding: sessionID)
        selectedSessionID = sessionID
        selectedProjectID = projectID(for: sessionID)
        if selectedSession?.isEphemeral == true {
            loadingTranscriptSessionID = nil
        } else {
            loadingTranscriptSessionID = sessionID
        }
        primePromptState(for: sessionID)
        scheduleGitRefreshLoop(for: selectedProject?.path)
        flushPendingProjectPersistence()
    }

    func addProject(directoryURL: URL) {
        let resolvedURL = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let projectPath = resolvedURL.path

        if let existingProject = projects.first(where: { $0.path == projectPath }) {
            discardSelectedEphemeralSessionIfNeeded()
            selectedProjectID = existingProject.id
            selectedSessionID = existingProject.sessions.first?.id
            primePromptState(for: selectedSessionID)
            lastError = nil
            return
        }

        discardSelectedEphemeralSessionIfNeeded()
        let project = ProjectSummary(name: resolvedURL.lastPathComponent, path: projectPath)
        projects.append(project)
        scheduleProjectPersistence()
        selectedProjectID = project.id
        selectedSessionID = nil
        primePromptState(for: nil)
        lastError = nil
        scheduleGitRefreshLoop(for: project.path)
    }

    func toggleProjectCollapsed(_ projectID: ProjectSummary.ID) {
        setProjectCollapsed(!isProjectCollapsed(projectID), for: projectID)
    }

    func isProjectCollapsed(_ projectID: ProjectSummary.ID) -> Bool {
        projects.first(where: { $0.id == projectID })?.settings.isCollapsedInSidebar ?? false
    }

    func connect(to runtime: OpenCodeRuntime) async {
        guard let project = selectedProject else {
            logger.debug("Disconnecting all live state because no project is selected")
            cancelGitRefreshLoop()
            disconnectLiveState()
            runtime.stop()
            return
        }

        scheduleGitRefreshLoop(for: project.path)
        _ = await connectProject(project.id, using: runtime, includeComposerOptions: true)
        reevaluateRuntimeRetention(using: runtime)
    }

    func createSession(using runtime: OpenCodeRuntime) async {
        guard let projectID = selectedProject?.id else { return }
        createEphemeralSession(in: projectID)
    }

    func createSession(in projectID: ProjectSummary.ID, using runtime: OpenCodeRuntime) async {
        _ = runtime
        selectedProjectID = projectID
        createEphemeralSession(in: projectID)
    }

    func refreshSessions(in projectID: ProjectSummary.ID, using runtime: OpenCodeRuntime) async {
        guard projects.contains(where: { $0.id == projectID }) else { return }

        selectProject(projectID)

        guard let service = await liveService(for: projectID, runtime: runtime) else { return }

        await loadSessions(using: service, for: projectID)
        await loadSessionStatuses(using: service, for: projectID)
        await loadPendingPermissions(using: service, for: projectID)
        await loadPendingQuestions(using: service, for: projectID)
        reevaluateRuntimeRetention(using: runtime)
    }

    func startDashboard(using runtime: OpenCodeRuntime) async {
        isDashboardActive = true
        dashboardSnapshot = await dashboardStatsService.prepare(projects: projects.map(DashboardProjectDescriptor.init(project:)))

        guard !projects.isEmpty else {
            dashboardStatus = .idle
            dashboardPollingTask?.cancel()
            dashboardPollingTask = nil
            dashboardRefreshTask?.cancel()
            dashboardRefreshTask = nil
            dashboardRefreshPending = false
            dashboardDirtySessions = [:]
            return
        }

        if dashboardSnapshot?.indexedSessionCount ?? 0 > 0 {
            dashboardStatus = DashboardRefreshStatus(
                phase: .refreshing,
                title: "Loaded cached usage",
                detail: "Checking your tracked projects for changed sessions in the background.",
                processedSessions: 0,
                totalSessions: 0,
                currentProjectName: nil,
                currentSessionTitle: nil,
                lastUpdatedAt: dashboardSnapshot?.generatedAt
            )
        } else {
            dashboardStatus = DashboardRefreshStatus(
                phase: .priming,
                title: "Building usage cache",
                detail: "Scanning tracked projects, reading session history, and caching per-session summaries.",
                processedSessions: 0,
                totalSessions: 0,
                currentProjectName: nil,
                currentSessionTitle: nil,
                lastUpdatedAt: nil
            )
        }

        requestDashboardRefresh(using: runtime)
        startDashboardPolling(using: runtime)
    }

    func suspendDashboardRefresh() {
        isDashboardActive = false
        dashboardPollingTask?.cancel()
        dashboardPollingTask = nil
        dashboardRefreshTask?.cancel()
        dashboardRefreshTask = nil
        dashboardRefreshPending = false

        if dashboardStatus.isVisible {
            dashboardStatus = .idle
        }
    }

    private func startDashboardPolling(using runtime: OpenCodeRuntime) {
        dashboardPollingTask?.cancel()
        dashboardPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                self.requestDashboardRefresh(using: runtime, delay: .zero)
            }
        }
    }

    private func noteDashboardChange(projectID: ProjectSummary.ID, sessionID: String?, using runtime: OpenCodeRuntime) {
        if let sessionID {
            dashboardDirtySessions[projectID, default: []].insert(sessionID)
        }

        guard isDashboardActive else { return }
        requestDashboardRefresh(using: runtime, delay: .seconds(3))
    }

    private func requestDashboardRefresh(using runtime: OpenCodeRuntime, delay: Duration = .zero) {
        guard isDashboardActive else { return }
        dashboardRefreshPending = true
        guard dashboardRefreshTask == nil else { return }

        dashboardRefreshTask = Task { [weak self] in
            guard let self else { return }

            if delay > .zero {
                try? await Task.sleep(for: delay)
            }

            while !Task.isCancelled, self.dashboardRefreshPending {
                self.dashboardRefreshPending = false
                let forcedSessions = self.dashboardDirtySessions
                self.dashboardDirtySessions = [:]
                await self.performDashboardRefresh(using: runtime, forcedSessions: forcedSessions)
            }

            self.dashboardRefreshTask = nil

            if self.dashboardRefreshPending {
                self.requestDashboardRefresh(using: runtime)
            }
        }
    }

    private func performDashboardRefresh(
        using runtime: OpenCodeRuntime,
        forcedSessions: [ProjectSummary.ID: Set<String>]
    ) async {
        let activeProjects = projects
        guard !activeProjects.isEmpty else {
            dashboardStatus = .idle
            return
        }

        let hasCachedSnapshot = (dashboardSnapshot?.indexedSessionCount ?? 0) > 0
        if hasCachedSnapshot {
            dashboardStatus = DashboardRefreshStatus(
                phase: .refreshing,
                title: "Refreshing usage cache",
                detail: "Checking tracked projects for sessions that changed since the last refresh.",
                processedSessions: 0,
                totalSessions: 0,
                currentProjectName: nil,
                currentSessionTitle: nil,
                lastUpdatedAt: dashboardSnapshot?.generatedAt
            )
        }

        var refreshWork: [(project: ProjectSummary, descriptor: DashboardProjectDescriptor, session: DashboardRemoteSessionDescriptor)] = []
        var services: [ProjectSummary.ID: DashboardRuntimeService] = [:]
        var failedProjects: [String] = []

        for project in activeProjects {
            let descriptor = DashboardProjectDescriptor(project: project)

            guard let runtimeService = await dashboardService(for: project, runtime: runtime) else {
                failedProjects.append(project.name)
                continue
            }

            services[project.id] = runtimeService

            do {
                let sessions = try await runtimeService.service.listSessions()
                    .filter(\.isRootVisible)
                    .sorted { $0.updatedAt > $1.updatedAt }
                let remoteSessions = sessions.map { session in
                    DashboardRemoteSessionDescriptor(
                        session: session,
                        fallbackTitle: sessionSummary(for: session.id, projectID: project.id)?.title ?? SessionSummary.defaultTitle
                    )
                }
                let plan = await dashboardStatsService.planRefresh(
                    for: descriptor,
                    sessions: remoteSessions,
                    forceSessionIDs: forcedSessions[project.id] ?? []
                )
                dashboardSnapshot = plan.snapshot
                refreshWork.append(contentsOf: plan.changedSessions.map { (project, descriptor, $0) })
            } catch {
                logger.error("Failed to scan dashboard sessions for project \(project.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                failedProjects.append(project.name)
            }
        }

        refreshWork.sort { $0.session.updatedAt > $1.session.updatedAt }

        let initialPhase: DashboardRefreshStatus.Phase = hasCachedSnapshot ? .refreshing : .priming
        dashboardStatus = DashboardRefreshStatus(
            phase: initialPhase,
            title: hasCachedSnapshot ? "Refreshing usage cache" : "Building usage cache",
            detail: refreshWork.isEmpty
                ? "Your cached statistics are already current."
                : "Summarizing model, token, and tool usage one session at a time so the dashboard stays responsive.",
            processedSessions: 0,
            totalSessions: refreshWork.count,
            currentProjectName: nil,
            currentSessionTitle: nil,
            lastUpdatedAt: dashboardSnapshot?.generatedAt
        )

        if refreshWork.isEmpty {
            dashboardSnapshot = await dashboardStatsService.currentSnapshot()
            dashboardStatus = failedProjects.isEmpty ? .idle : DashboardRefreshStatus(
                phase: .failed,
                title: "Some projects were skipped",
                detail: "NeoCode kept your cached dashboard, but couldn't refresh \(failedProjects.joined(separator: ", ")).",
                processedSessions: 0,
                totalSessions: 0,
                currentProjectName: nil,
                currentSessionTitle: nil,
                lastUpdatedAt: dashboardSnapshot?.generatedAt
            )
            stopDashboardOnlyRuntimes(services, runtime: runtime)
            return
        }

        let batchSize = hasCachedSnapshot ? 2 : 4
        var processedSessions = 0
        var cursor = 0

        while cursor < refreshWork.count, !Task.isCancelled {
            let nextCursor = min(cursor + batchSize, refreshWork.count)
            let batch = Array(refreshWork[cursor..<nextCursor])
            cursor = nextCursor

            var ingestions: [DashboardSessionIngress] = []
            for item in batch {
                guard let runtimeService = services[item.project.id] else { continue }
                dashboardStatus = DashboardRefreshStatus(
                    phase: initialPhase,
                    title: hasCachedSnapshot ? "Refreshing usage cache" : "Building usage cache",
                    detail: hasCachedSnapshot
                        ? "Updating only the sessions that changed since the cached snapshot was written."
                        : "Reading historical session data and caching it so future launches can load instantly.",
                    processedSessions: processedSessions,
                    totalSessions: refreshWork.count,
                    currentProjectName: item.project.name,
                    currentSessionTitle: item.session.title,
                    lastUpdatedAt: dashboardSnapshot?.generatedAt
                )

                do {
                    let messages = try await runtimeService.service.listMessages(sessionID: item.session.id)
                    ingestions.append(DashboardSessionIngress(project: item.descriptor, session: item.session, messages: messages))
                } catch {
                    logger.error("Failed to fetch dashboard messages for session \(item.session.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            if !ingestions.isEmpty {
                dashboardSnapshot = await dashboardStatsService.ingest(ingestions)
                processedSessions += ingestions.count
            }

            await Task.yield()
        }

        dashboardSnapshot = await dashboardStatsService.currentSnapshot()
        dashboardStatus = failedProjects.isEmpty ? .idle : DashboardRefreshStatus(
            phase: .failed,
            title: "Usage cache updated with gaps",
            detail: "NeoCode refreshed what it could, but skipped \(failedProjects.joined(separator: ", ")).",
            processedSessions: processedSessions,
            totalSessions: refreshWork.count,
            currentProjectName: nil,
            currentSessionTitle: nil,
            lastUpdatedAt: dashboardSnapshot?.generatedAt
        )
        stopDashboardOnlyRuntimes(services, runtime: runtime)
    }

    private func stopDashboardOnlyRuntimes(_ services: [ProjectSummary.ID: DashboardRuntimeService], runtime: OpenCodeRuntime) {
        for (projectID, runtimeService) in services where runtimeService.shouldStopAfterUse {
            runtime.stop(projectPath: projectPath(for: projectID))
        }
    }

    private func dashboardService(for project: ProjectSummary, runtime: OpenCodeRuntime) async -> DashboardRuntimeService? {
        let hadConnection = runtime.connection(for: project.path) != nil
        await runtime.ensureRunning(for: project.path)

        guard let connection = runtime.connection(for: project.path) else {
            logger.error("Dashboard refresh could not start runtime for project: \(project.path, privacy: .public)")
            return nil
        }

        runtime.markUsed(for: project.path)
        let shouldStopAfterUse = !hadConnection && liveServices[project.id] == nil
        return DashboardRuntimeService(service: OpenCodeClient(connection: connection), shouldStopAfterUse: shouldStopAfterUse)
    }

    func syncSelectedSession(using runtime: OpenCodeRuntime) async {
        guard let selectedSessionID else {
            loadingTranscriptSessionID = nil
            return
        }

        loadingTranscriptSessionID = selectedSessionID

        guard let projectID = projectID(for: selectedSessionID),
              let project = projects.first(where: { $0.id == projectID }),
              session(for: selectedSessionID)?.isEphemeral != true
        else {
            if loadingTranscriptSessionID == selectedSessionID {
                loadingTranscriptSessionID = nil
            }
            return
        }

        guard let service = await connectProject(projectID, using: runtime, includeComposerOptions: selectedProjectID == projectID),
              let connection = runtime.connection(for: project.path)
        else {
            if loadingTranscriptSessionID == selectedSessionID {
                loadingTranscriptSessionID = nil
            }
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        let connectionIdentifier = Self.connectionIdentifier(for: connection)
        guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else {
            if loadingTranscriptSessionID == selectedSessionID {
                loadingTranscriptSessionID = nil
            }
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        await loadMessages(for: selectedSessionID, using: service, projectID: projectID, allowCachedFallback: true)
        reevaluateRuntimeRetention(using: runtime)
    }

    func renameSession(_ sessionID: String, to title: String, using runtime: OpenCodeRuntime) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let projectID = projectID(for: sessionID)
        else { return }

        if updateEphemeralSessionTitleIfNeeded(sessionID: sessionID, projectID: projectID, title: trimmed) {
            lastError = nil
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        guard let service = await liveService(for: projectID, runtime: runtime)
        else { return }

        do {
            let updated = try await service.updateSession(sessionID: sessionID, title: trimmed)
            upsert(session: SessionSummary(session: updated, fallbackTitle: trimmed), in: projectID, preferTopInsertion: false)
            lastError = nil
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to rename session: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    func deleteSession(_ sessionID: String, using runtime: OpenCodeRuntime) async {
        guard let projectID = projectID(for: sessionID) else { return }

        if removeEphemeralSessionIfNeeded(sessionID: sessionID, projectID: projectID) {
            lastError = nil
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        guard let service = await liveService(for: projectID, runtime: runtime) else { return }

        do {
            _ = try await service.deleteSession(sessionID: sessionID)
            removeSession(sessionID, in: projectID)
            lastError = nil
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to delete session: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    private func liveService(for projectID: ProjectSummary.ID, runtime: OpenCodeRuntime) async -> (any OpenCodeServicing)? {
        guard let project = projects.first(where: { $0.id == projectID }) else {
            logger.error("Could not resolve project for id: \(projectID.uuidString, privacy: .public)")
            lastError = "Could not find the selected project."
            return nil
        }

        if let service = await connectProject(projectID, using: runtime, includeComposerOptions: selectedProjectID == projectID),
           let connection = runtime.connection(for: project.path) {
            let connectionIdentifier = Self.connectionIdentifier(for: connection)
            if serviceConnectionIdentifiers[projectID] == connectionIdentifier,
               isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) {
                return service
            }
        }

        if let connection = runtime.connection(for: project.path) {
            logger.debug("Creating fallback OpenCode client from runtime connection for project: \(project.path, privacy: .public)")
            let liveClient = OpenCodeClient(connection: connection)
            liveServices[projectID] = liveClient
            serviceConnectionIdentifiers[projectID] = Self.connectionIdentifier(for: connection)
            reevaluateRuntimeRetention(using: runtime)
            return liveClient
        }

        logger.error("Runtime connection unavailable after bootstrap. Detail: \(runtime.detailLabel(for: project.path), privacy: .public)")
        lastError = lastError ?? runtime.detailLabel(for: project.path)
        reevaluateRuntimeRetention(using: runtime)
        return nil
    }

    func sendDraft(using runtime: OpenCodeRuntime) async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachedFiles.isEmpty,
              let projectID = selectedProject?.id
        else { return }

        if let localCommand = localSlashCommandInvocation(in: trimmed) {
            let handled = await executeLocalSlashCommand(localCommand, in: projectID, using: runtime)
            if handled {
                logger.info(
                    "Handled local slash command project=\(projectID.uuidString, privacy: .public) command=\(localCommand.command.name, privacy: .public)"
                )
            }
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        guard let service = await liveService(for: projectID, runtime: runtime) else {
            logger.error("Cannot send draft because live service is unavailable for project: \(projectID.uuidString, privacy: .public)")
            return
        }

        guard let sessionID = await resolveSessionForSend(projectID: projectID, service: service) else { return }

        let accepted = await sendDraft(using: service, projectID: projectID, sessionID: sessionID)
        if accepted {
            scheduleStreamingRecoveryCheck(for: sessionID, projectID: projectID, using: runtime)
        }

        reevaluateRuntimeRetention(using: runtime)
    }

    @discardableResult
    func sendDraft(using service: any OpenCodeServicing, projectID: ProjectSummary.ID, sessionID: String) async -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = attachedFiles
        guard !trimmed.isEmpty || !attachments.isEmpty else { return false }

        let slashCommand = slashCommandInvocation(in: trimmed)
        let shouldShowOptimisticUserMessage = slashCommand == nil

        isSending = true
        lastError = nil
        if let slashCommand {
            logger.info(
                "Sending slash command session=\(sessionID, privacy: .public) command=\(slashCommand.command.name, privacy: .public) argumentLength=\(slashCommand.arguments.count, privacy: .public) project=\(projectID.uuidString, privacy: .public)"
            )
        } else {
            logger.info(
                "Sending draft session=\(sessionID, privacy: .public) characters=\(trimmed.count, privacy: .public) project=\(projectID.uuidString, privacy: .public)"
            )
        }

        let optimisticID = "optimistic-user-\(UUID().uuidString)"
        let now = Date()
        if shouldShowOptimisticUserMessage && !trimmed.isEmpty {
            upsertMessage(
                ChatMessage(id: optimisticID, role: .user, text: trimmed, timestamp: now, emphasis: .normal),
                in: sessionID,
                projectID: projectID
            )
        }
        if shouldShowOptimisticUserMessage {
            for attachment in attachments {
                upsertMessage(
                    ChatMessage(
                        id: "optimistic-user-attachment-\(UUID().uuidString)",
                        role: .user,
                        text: ChatAttachment(attachment: attachment).displayTitle,
                        timestamp: now,
                        emphasis: .normal,
                        attachment: ChatAttachment(attachment: attachment)
                    ),
                    in: sessionID,
                    projectID: projectID
                )
            }
        }
        draft = ""
        attachedFiles = []
        setSessionStatus(.running, sessionID: sessionID, projectID: projectID)

        do {
            if let slashCommand {
                try await service.sendCommand(
                    sessionID: sessionID,
                    command: slashCommand.command.name,
                    arguments: slashCommand.arguments,
                    attachments: attachments,
                    options: OpenCodePromptOptions(
                        model: selectedModel,
                        agentName: selectedAgent.isEmpty ? nil : selectedAgent,
                        variant: selectedThinkingLevel
                    )
                )
                logger.info(
                    "Slash command accepted for session \(sessionID, privacy: .public): \(slashCommand.command.name, privacy: .public)"
                )
            } else {
                try await service.sendPromptAsync(
                    sessionID: sessionID,
                    text: trimmed,
                    attachments: attachments,
                    options: OpenCodePromptOptions(
                        model: selectedModel,
                        agentName: selectedAgent.isEmpty ? nil : selectedAgent,
                        variant: selectedThinkingLevel
                    )
                )
                logger.info("Draft accepted for session: \(sessionID, privacy: .public)")
            }
        } catch {
            logger.error("Failed to send draft for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if shouldShowOptimisticUserMessage && !trimmed.isEmpty {
                removeMessage(id: optimisticID, sessionID: sessionID, projectID: projectID)
            }
            if shouldShowOptimisticUserMessage {
                removeOptimisticAttachmentMessages(in: sessionID, projectID: projectID)
            }
            draft = trimmed
            attachedFiles = attachments
            setSessionStatus(.attention, sessionID: sessionID, projectID: projectID)
            lastError = error.localizedDescription
            isSending = false
            return false
        }

        isSending = false
        return true
    }

    @discardableResult
    func resendEditedMessage(messageID: String, newText: String, in sessionID: String, using runtime: OpenCodeRuntime) async -> Bool {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let projectID = projectID(for: sessionID)
        else {
            return false
        }

        guard session(for: sessionID)?.status != .running else {
            lastError = "Wait for the current response to finish before editing an earlier message."
            return false
        }

        guard let service = await liveService(for: projectID, runtime: runtime) else {
            logger.error("Cannot resend edited message because live service is unavailable for project: \(projectID.uuidString, privacy: .public)")
            return false
        }

        let didResend = await resendEditedMessage(messageID: messageID, newText: trimmed, in: sessionID, projectID: projectID, using: service)
        if didResend {
            scheduleStreamingRecoveryCheck(for: sessionID, projectID: projectID, using: runtime)
        }
        return didResend
    }

    @discardableResult
    func resendEditedMessage(
        messageID: String,
        newText: String,
        in sessionID: String,
        projectID: ProjectSummary.ID,
        using service: any OpenCodeServicing
    ) async -> Bool {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let session = sessionSummary(for: sessionID, projectID: projectID)
        else {
            return false
        }

        let currentTranscript = transcript(for: sessionID)
        guard let messageIndex = currentTranscript.firstIndex(where: { $0.id == messageID }),
              currentTranscript[messageIndex].role == .user
        else {
            return false
        }

        let targetMessage = currentTranscript[messageIndex]
        let upstreamMessageID = targetMessage.messageID ?? targetMessage.id
        let originalTranscript = currentTranscript
        let originalUpdatedAt = session.lastUpdatedAt
        let truncatedTranscript = Array(originalTranscript.prefix(messageIndex))
        let optimisticID = "optimistic-user-\(UUID().uuidString)"
        let now = Date()
        var didRevert = false

        isSending = true
        lastError = nil
        logger.info(
            "Resending edited message session=\(sessionID, privacy: .public) message=\(messageID, privacy: .public) characters=\(trimmed.count, privacy: .public)"
        )

        do {
            _ = try await service.revertSession(sessionID: sessionID, messageID: upstreamMessageID, partID: nil)
            didRevert = true

            replaceTranscript(in: sessionID, projectID: projectID, with: truncatedTranscript)
            upsertMessage(
                ChatMessage(id: optimisticID, role: .user, text: trimmed, timestamp: now, emphasis: .normal),
                in: sessionID,
                projectID: projectID
            )
            touchSession(sessionID: sessionID, projectID: projectID, updatedAt: now)
            setSessionStatus(.running, sessionID: sessionID, projectID: projectID)

            try await service.sendPromptAsync(
                sessionID: sessionID,
                text: trimmed,
                attachments: [],
                options: OpenCodePromptOptions(
                    model: selectedModel,
                    agentName: selectedAgent.isEmpty ? nil : selectedAgent,
                    variant: selectedThinkingLevel
                )
            )
            logger.info("Edited message accepted for session: \(sessionID, privacy: .public)")
            isSending = false
            return true
        } catch {
            logger.error(
                "Failed to resend edited message for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )

            if didRevert {
                do {
                    _ = try await service.unrevertSession(sessionID: sessionID)
                } catch {
                    logger.error(
                        "Failed to restore reverted transcript for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            replaceTranscript(in: sessionID, projectID: projectID, with: originalTranscript)
            touchSession(sessionID: sessionID, projectID: projectID, updatedAt: originalUpdatedAt)
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
            cancelStreamingRecoveryCheck(for: sessionID)
            lastError = error.localizedDescription
            isSending = false
            return false
        }
    }

    func stopSelectedSession(using runtime: OpenCodeRuntime) async {
        guard let sessionID = selectedSessionID,
              let projectID = projectID(for: sessionID),
              session(for: sessionID)?.status == .running
        else { return }

        guard let service = await liveService(for: projectID, runtime: runtime) else {
            logger.error("Cannot stop session because live service is unavailable for project: \(projectID.uuidString, privacy: .public)")
            return
        }

        do {
            logger.info("Aborting session: \(sessionID, privacy: .public)")
            try await service.abortSession(sessionID: sessionID)
            liveSessionStatuses[sessionID] = .idle
            setSessionStatus(.idle, sessionID: sessionID, projectID: projectID)
            cancelStreamingRecoveryCheck(for: sessionID)
            refreshSelectedSessionMessages(projectID: projectID)
            lastError = nil
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to abort session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    func addAttachments(from urls: [URL]) async {
        let attachments = await ComposerAttachment.makeAttachments(from: urls)
        addAttachments(attachments)
    }

    func addAttachments(from items: [ComposerAttachmentImportItem]) async {
        let attachments = await ComposerAttachment.makeAttachments(from: items)
        addAttachments(attachments)
    }

    func addAttachments(_ attachments: [ComposerAttachment]) {
        let existing = Set(attachedFiles.map(\.deduplicationKey))
        let newAttachments = attachments.filter { !existing.contains($0.deduplicationKey) }
        attachedFiles.append(contentsOf: newAttachments)
    }

    func removeAttachment(id: ComposerAttachment.ID) {
        attachedFiles.removeAll(where: { $0.id == id })
    }

    func refreshGitStatus() async {
        guard !isRefreshingGitStatus else { return }
        guard let project = selectedProject else {
            resetGitState()
            return
        }

        let projectPath = project.path
        isRefreshingGitStatus = true
        defer { isRefreshingGitStatus = false }

        let repositoryService = GitRepositoryService()
        let branchService = GitBranchService()
        let status = await repositoryService.status(in: projectPath)
        guard !Task.isCancelled else { return }

        logger.debug(
            "Git refresh result path=\(projectPath, privacy: .public) repo=\(status.isRepository, privacy: .public) changes=\(status.hasChanges, privacy: .public) ahead=\(status.aheadCount, privacy: .public) hasRemote=\(status.hasRemote, privacy: .public)"
        )

        guard selectedProject?.path == projectPath else { return }

        if gitStatus != status {
            gitStatus = status
        }
        if !status.isRepository {
            logger.debug("Git refresh marked project as non-repository: \(projectPath, privacy: .public)")
            if !availableBranches.isEmpty {
                availableBranches = []
            }
            if selectedBranch != "main" {
                selectedBranch = "main"
            }
            if gitCommitPreview != nil {
                gitCommitPreview = nil
            }
            cacheCurrentGitState(for: projectPath)
            return
        }

        async let branchesTask = branchService.listBranches(in: projectPath)
        async let currentBranchTask = branchService.currentBranch(in: projectPath)

        let branches = (try? await branchesTask) ?? []
        let currentBranch = (try? await currentBranchTask) ?? selectedBranch
        guard !Task.isCancelled else { return }

        logger.debug(
            "Git branch refresh path=\(projectPath, privacy: .public) current=\(currentBranch, privacy: .public) branches=\(branches.joined(separator: ","), privacy: .public)"
        )

        guard selectedProject?.path == projectPath else { return }

        if availableBranches != branches {
            availableBranches = branches
        }
        if !currentBranch.isEmpty {
            if selectedBranch != currentBranch {
                selectedBranch = currentBranch
            }
            if !availableBranches.contains(currentBranch) {
                availableBranches.insert(currentBranch, at: 0)
            }
        }

        cacheCurrentGitState(for: projectPath)

        if status.hasChanges,
           gitStateByProjectPath[projectPath]?.commitPreview == nil,
           !isLoadingGitCommitPreview {
            Task { [weak self] in
                await self?.refreshGitCommitPreview(showLoadingIndicator: false, projectPathOverride: projectPath)
            }
        }
    }

    private func scheduleGitRefreshLoop(for projectPath: String?) {
        guard let projectPath else {
            cancelGitRefreshLoop()
            applyCachedGitState(for: nil)
            return
        }

        applyCachedGitState(for: projectPath)
        startGitRepositoryMonitor(for: projectPath)
        scheduleGitFallbackRefresh(for: projectPath)
        scheduleGitRefresh(reason: "project-selected", projectPath: projectPath, refreshCommitPreviewIfLoaded: false, delay: .milliseconds(0))
    }

    private func cancelGitRefreshLoop() {
        gitRefreshTask?.cancel()
        gitRefreshTask = nil
        gitRefreshDebounceTask?.cancel()
        gitRefreshDebounceTask = nil
        gitMonitorSetupTask?.cancel()
        gitMonitorSetupTask = nil
        gitRepositoryMonitor?.stop()
        gitRepositoryMonitor = nil
    }

    func handleApplicationDidBecomeActive() {
        guard let projectPath = selectedProject?.path else { return }
        scheduleGitRefresh(
            reason: "application-active",
            projectPath: projectPath,
            refreshCommitPreviewIfLoaded: gitCommitPreview != nil,
            delay: .milliseconds(100)
        )
    }

    private func startGitRepositoryMonitor(for projectPath: String) {
        gitMonitorSetupTask?.cancel()
        gitRepositoryMonitor?.stop()

        let monitor = GitRepositoryMonitor { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scheduleGitRefresh(
                    reason: "git-metadata-changed",
                    projectPath: projectPath,
                    refreshCommitPreviewIfLoaded: self.gitCommitPreview != nil,
                    delay: .milliseconds(200)
                )
            }
        }
        gitRepositoryMonitor = monitor

        gitMonitorSetupTask = Task { [weak self, weak monitor] in
            guard let self, let monitor else { return }
            let watchURLs = await GitRepositoryService().metadataWatchURLs(in: projectPath)
            guard !Task.isCancelled else { return }
            guard self.selectedProject?.path == projectPath else { return }

            monitor.watch(urls: watchURLs)
            self.logger.debug(
                "Started git metadata monitor path=\(projectPath, privacy: .public) watched=\(watchURLs.count, privacy: .public)"
            )
        }
    }

    private func scheduleGitFallbackRefresh(for projectPath: String) {
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

    private func scheduleGitRefresh(
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

            self.logger.debug(
                "Scheduling git refresh path=\(projectPath, privacy: .public) reason=\(reason, privacy: .public)"
            )
            await self.refreshVisibleGitState(for: projectPath, refreshCommitPreviewIfLoaded: refreshCommitPreviewIfLoaded)
        }
    }

    private func refreshVisibleGitState(for projectPath: String, refreshCommitPreviewIfLoaded: Bool) async {
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

    func refreshGitCommitPreview(
        showLoadingIndicator: Bool = true,
        projectPathOverride: String? = nil
    ) async {
        guard !isRefreshingGitCommitPreview else { return }

        let projectPath = projectPathOverride ?? selectedProject?.path
        guard let projectPath,
              (projectPathOverride != nil || gitStatus.isRepository)
        else {
            gitCommitPreview = nil
            return
        }

        isRefreshingGitCommitPreview = true
        if showLoadingIndicator {
            isLoadingGitCommitPreview = true
        }
        defer {
            isRefreshingGitCommitPreview = false
            isLoadingGitCommitPreview = false
        }

        do {
            let preview = try await GitRepositoryService().commitPreview(in: projectPath)
            guard !Task.isCancelled else { return }
            guard selectedProject?.path == projectPath || projectPathOverride != nil else { return }
            gitCommitPreview = preview
            cacheCurrentGitState(for: projectPath)
            lastError = nil
        } catch is CancellationError {
            logger.debug("Cancelled git commit preview refresh for path=\(projectPath, privacy: .public)")
            return
        } catch {
            guard !Task.isCancelled else { return }
            guard selectedProject?.path == projectPath || projectPathOverride != nil else { return }
            gitCommitPreview = nil
            cacheCurrentGitState(for: projectPath)
            lastError = error.localizedDescription
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
            try await GitBranchService().initializeRepository(in: projectPath)
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
            try await GitBranchService().switchBranch(named: trimmed, in: projectPath)
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
            try await GitBranchService().createBranch(named: trimmed, in: projectPath)
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
            try await GitRepositoryService().commit(message: resolvedMessage, includeUnstaged: includeUnstaged, in: projectPath)
            if pushAfterCommit {
                setGitOperationState(.pushing, for: projectPath)
                try await GitRepositoryService().push(in: projectPath)
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

    @discardableResult
    func pushChanges() async -> Bool {
        guard let projectPath = selectedProject?.path, gitStatus.isRepository else { return false }

        isPerformingGitOperation = true
        setGitOperationState(.pushing, for: projectPath)
        defer {
            isPerformingGitOperation = false
            clearGitOperationState(for: projectPath)
        }

        do {
            try await GitRepositoryService().push(in: projectPath)
            lastError = nil
            await refreshGitStatus()
            return true
        } catch {
            lastError = error.localizedDescription
            await refreshGitStatus()
            return false
        }
    }

    func apply(event: OpenCodeEvent) {
        guard let projectID = selectedProject?.id else { return }
        apply(event: event, projectID: projectID)
    }

    private func apply(event: OpenCodeEvent, projectID: ProjectSummary.ID) {
        switch event {
        case .sessionCreated(let session), .sessionUpdated(let session):
            if session.isRootVisible {
                let fallbackTitle = sessionSummary(for: session.id, projectID: projectID)?.title ?? SessionSummary.defaultTitle
                upsert(session: SessionSummary(session: session, fallbackTitle: fallbackTitle), in: projectID, preferTopInsertion: event.isCreated)
            } else {
                removeSession(session.id, in: projectID)
            }
        case .sessionDeleted(let sessionID):
            removeSession(sessionID, in: projectID)
        case .sessionStatusChanged(let sessionID, let status):
            liveSessionStatuses[sessionID] = status
            if case .idle = status {
                clearLocalSessionActivity(sessionID)
            }
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
        case .permissionAsked(let request):
            if let service = liveServices[projectID],
               shouldAutoRespond(to: request) {
                Task { [weak self] in
                    await self?.autoRespondToPermission(request, projectID: projectID, service: service)
                }
            } else {
                upsertPendingPermission(request, in: projectID)
            }
        case .permissionReplied(let event):
            removePendingPermission(requestID: event.requestID, sessionID: event.sessionID, projectID: projectID)
        case .questionAsked(let request):
            upsertPendingQuestion(request, in: projectID)
        case .questionReplied(let event):
            removePendingQuestion(requestID: event.requestID, sessionID: event.sessionID, projectID: projectID)
        case .questionRejected(let event):
            removePendingQuestion(requestID: event.requestID, sessionID: event.sessionID, projectID: projectID)
        case .messageUpdated(let info):
            messageRoles[info.id] = info.chatRole
            if let sessionID = info.sessionID {
                touchSession(sessionID: sessionID, projectID: projectID, updatedAt: info.updatedAt ?? info.createdAt ?? Date())
            }
        case .messagePartUpdated(let part):
            apply(part: part, projectID: projectID)
        case .messagePartDelta(let delta):
            apply(delta: delta, projectID: projectID)
        case .connected, .ignored:
            break
        }
    }

    @discardableResult
    private func connectProject(
        _ projectID: ProjectSummary.ID,
        using runtime: OpenCodeRuntime,
        includeComposerOptions: Bool,
        allowCachedFallback: Bool = true
    ) async -> (any OpenCodeServicing)? {
        guard let project = projects.first(where: { $0.id == projectID }) else {
            logger.error("Could not resolve project for id: \(projectID.uuidString, privacy: .public)")
            lastError = "Could not find the selected project."
            return nil
        }

        await runtime.ensureRunning(for: project.path)

        guard let connection = runtime.connection(for: project.path) else {
            logger.debug("Disconnecting live state because runtime connection is missing for project: \(project.path, privacy: .public)")
            disconnectLiveState(for: projectID)
            lastError = lastError ?? runtime.detailLabel(for: project.path)
            return nil
        }

        logger.info("Connecting store to runtime for project: \(project.path, privacy: .public)")
        let service = OpenCodeClient(connection: connection)
        let connectionIdentifier = Self.connectionIdentifier(for: connection)
        let connectionChanged = serviceConnectionIdentifiers[projectID] != connectionIdentifier || liveServices[projectID] == nil

        logger.debug(
            "Runtime connection id=\(connectionIdentifier, privacy: .public) changed=\(connectionChanged, privacy: .public) composerOptions=\(includeComposerOptions, privacy: .public) cachedFallback=\(allowCachedFallback, privacy: .public)"
        )

        if connectionChanged {
            logger.info("Detected runtime connection change for project: \(project.path, privacy: .public)")
        }

        if includeComposerOptions && composerOptionsProjectPath != project.path {
            await loadComposerOptions(using: service, projectPath: project.path)
            guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else { return nil }
        }

        if connectionChanged {
            await loadSessions(using: service, for: projectID, allowCachedFallback: allowCachedFallback)
            guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else { return nil }

            await loadSessionStatuses(using: service, for: projectID)
            guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else { return nil }

            await loadPendingPermissions(using: service, for: projectID)
            guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else { return nil }

            await loadPendingQuestions(using: service, for: projectID)
            guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else { return nil }
        }

        liveServices[projectID] = service
        serviceConnectionIdentifiers[projectID] = connectionIdentifier

        if connectionChanged || eventTasks[projectID] == nil || subscribedConnectionIdentifiers[projectID] != connectionIdentifier {
            logger.info(
                "Starting event subscription project=\(project.path, privacy: .public) connection=\(connectionIdentifier, privacy: .public) existingTask=\(self.eventTasks[projectID] != nil, privacy: .public)"
            )
            subscribeToEvents(using: service, projectID: projectID, connectionIdentifier: connectionIdentifier, runtime: runtime)
        } else {
            logger.debug(
                "Reusing existing event subscription project=\(project.path, privacy: .public) connection=\(connectionIdentifier, privacy: .public)"
            )
        }

        runtime.markUsed(for: project.path)
        return service
    }

    func disconnectLiveState() {
        cancelGitRefreshLoop()

        for projectID in Set(liveServices.keys)
            .union(eventTasks.keys)
            .union(runtimeIdleTasks.keys) {
            disconnectLiveState(for: projectID)
        }

        refreshTask?.cancel()
        refreshTask = nil
        composerOptionsProjectPath = nil
        availableCommands = []
        messageRoles = [:]
        liveSessionStatuses = [:]
        locallyActiveSessionIDs = []
        pendingPermissionsBySession = [:]
        pendingQuestionsBySession = [:]
        isLoadingSessions = false
        isSending = false
        isRespondingToPrompt = false
        isPromptReady = true
        promptLoadingText = nil
    }

    private func disconnectLiveState(for projectID: ProjectSummary.ID) {
        logger.info("Disconnecting live state for project id: \(projectID.uuidString, privacy: .public)")
        eventTasks[projectID]?.cancel()
        eventTasks.removeValue(forKey: projectID)
        eventSubscriptionTokens.removeValue(forKey: projectID)
        liveServices.removeValue(forKey: projectID)
        serviceConnectionIdentifiers.removeValue(forKey: projectID)
        subscribedConnectionIdentifiers.removeValue(forKey: projectID)
        runtimeIdleTasks[projectID]?.cancel()
        runtimeIdleTasks.removeValue(forKey: projectID)

        let sessionIDs = projectSessionIDs(for: projectID)
        for sessionID in sessionIDs {
            cancelStreamingRecoveryCheck(for: sessionID)
            liveSessionStatuses.removeValue(forKey: sessionID)
            clearLocalSessionActivity(sessionID)
            pendingPermissionsBySession.removeValue(forKey: sessionID)
            pendingQuestionsBySession.removeValue(forKey: sessionID)
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
        }

        if composerOptionsProjectPath == projectPath(for: projectID) {
            composerOptionsProjectPath = nil
            availableCommands = []
        }
    }

    private func loadComposerOptions(using service: any OpenCodeServicing, projectPath: String) async {
        async let providersTask = service.listProviders()
        async let agentsTask = service.listAgents()
        async let commandsTask = service.listCommands()

        do {
            let providersResponse = try await providersTask
            let agents = try await agentsTask
            let commands = (try? await commandsTask) ?? []

            let models = providersResponse.providers
                .flatMap { provider in
                    provider.models.values.map {
                        ComposerModelOption(
                            id: "\(provider.id)/\($0.id)",
                            providerID: provider.id,
                            modelID: $0.id,
                            title: $0.name,
                            variants: ($0.variants?.keys.sorted()) ?? []
                        )
                    }
                }
                .sorted { $0.title < $1.title }

            availableModels = models
            if selectedModelID == nil || !models.contains(where: { $0.id == selectedModelID }) {
                selectedModelID = models.first?.id
            }

            availableAgents = agents
                .filter { !($0.hidden ?? false) }
                .filter { ($0.mode ?? "primary") != "subagent" }
                .map(\.name)
                .sorted { displayAgentName($0) < displayAgentName($1) }
            if !availableAgents.contains(selectedAgent) {
                selectedAgent = availableAgents.first ?? ""
            }

            availableCommands = commands.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            logger.info(
                "Loaded composer options project=\(projectPath, privacy: .public) models=\(models.count, privacy: .public) agents=\(self.availableAgents.count, privacy: .public) commands=\(self.availableCommands.count, privacy: .public)"
            )

            refreshThinkingLevels()

            composerOptionsProjectPath = projectPath
        } catch {
            logger.error("Failed to load composer options: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadPendingPermissions(using service: any OpenCodeServicing, for projectID: ProjectSummary.ID) async {
        do {
            let requests = try await service.listPermissions()
            var pendingRequests: [OpenCodePermissionRequest] = []
            for request in requests {
                if shouldAutoRespond(to: request) {
                    await autoRespondToPermission(request, projectID: projectID, service: service)
                } else {
                    pendingRequests.append(request)
                }
            }
            replacePendingPermissions(pendingRequests, in: projectID)
        } catch {
            logger.error("Failed to load pending permissions: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadPendingQuestions(using service: any OpenCodeServicing, for projectID: ProjectSummary.ID) async {
        do {
            let requests = try await service.listQuestions()
            replacePendingQuestions(requests, in: projectID)
        } catch {
            logger.error("Failed to load pending questions: \(error.localizedDescription, privacy: .public)")
        }
    }

    func replyToPermission(requestID: String, sessionID: String, reply: OpenCodePermissionReply, message: String? = nil, using runtime: OpenCodeRuntime) async {
        guard !isRespondingToPrompt,
              let projectID = projectID(for: sessionID),
              let service = await liveService(for: projectID, runtime: runtime)
        else { return }

        isRespondingToPrompt = true
        lastError = nil
        defer { isRespondingToPrompt = false }

        do {
            try await service.replyToPermission(requestID: requestID, reply: reply, message: message)
            removePendingPermission(requestID: requestID, sessionID: sessionID, projectID: projectID)
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to reply to permission \(requestID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    func replyToQuestion(requestID: String, sessionID: String, answers: [OpenCodeQuestionAnswer], using runtime: OpenCodeRuntime) async {
        guard !isRespondingToPrompt,
              let projectID = projectID(for: sessionID),
              let service = await liveService(for: projectID, runtime: runtime)
        else { return }

        isRespondingToPrompt = true
        lastError = nil
        defer { isRespondingToPrompt = false }

        do {
            try await service.replyToQuestion(requestID: requestID, answers: answers)
            removePendingQuestion(requestID: requestID, sessionID: sessionID, projectID: projectID)
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to reply to question \(requestID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    func rejectQuestion(requestID: String, sessionID: String, using runtime: OpenCodeRuntime) async {
        guard !isRespondingToPrompt,
              let projectID = projectID(for: sessionID),
              let service = await liveService(for: projectID, runtime: runtime)
        else { return }

        isRespondingToPrompt = true
        lastError = nil
        defer { isRespondingToPrompt = false }

        do {
            try await service.rejectQuestion(requestID: requestID)
            removePendingQuestion(requestID: requestID, sessionID: sessionID, projectID: projectID)
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to reject question \(requestID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    func refreshThinkingLevels() {
        let variants = (selectedModel?.variants ?? []).sorted(using: KeyPathComparator(\.thinkingLevelSortKey))
        availableThinkingLevels = variants
        if variants.isEmpty {
            selectedThinkingLevel = nil
        } else if selectedThinkingLevel == nil || !variants.contains(selectedThinkingLevel ?? "") {
            selectedThinkingLevel = variants.first
        }
    }

    var selectedModel: ComposerModelOption? {
        availableModels.first(where: { $0.id == selectedModelID })
    }

    func displayAgentName(_ rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func slashCommandInvocation(in text: String) -> SlashCommandInvocation? {
        guard text.hasPrefix("/") else { return nil }

        let components = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = components.first else { return nil }

        let name = String(first.dropFirst())
        guard !name.isEmpty,
              let command = availableCommands.first(where: { $0.name == name })
        else {
            return nil
        }

        let arguments = components.count > 1 ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return SlashCommandInvocation(command: command, arguments: arguments)
    }

    private func localSlashCommandInvocation(in text: String) -> LocalSlashCommandInvocation? {
        guard text.hasPrefix("/") else { return nil }

        let components = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = components.first else { return nil }

        let name = String(first.dropFirst()).lowercased()
        guard !name.isEmpty,
              let command = LocalComposerSlashCommand.allCases.first(where: { $0.matches(name: name) })
        else {
            return nil
        }

        let arguments = components.count > 1 ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return LocalSlashCommandInvocation(command: command, arguments: arguments)
    }

    private func executeLocalSlashCommand(
        _ invocation: LocalSlashCommandInvocation,
        in projectID: ProjectSummary.ID,
        using runtime: OpenCodeRuntime
    ) async -> Bool {
        lastError = nil

        switch invocation.command {
        case .new:
            createEphemeralSession(in: projectID)
            draft = invocation.arguments
            return true

        case .model:
            guard let query = invocation.arguments.nonEmptyTrimmed else {
                lastError = "Usage: /model <name>"
                return false
            }
            guard let match = bestMatchingModel(for: query) else {
                lastError = "No model matches '\(query)'."
                return false
            }
            selectedModelID = match.id
            refreshThinkingLevels()
            draft = ""
            return true

        case .agent:
            guard let query = invocation.arguments.nonEmptyTrimmed else {
                lastError = "Usage: /agent <name>"
                return false
            }
            guard let match = bestMatchingAgent(for: query) else {
                lastError = "No agent matches '\(query)'."
                return false
            }
            selectedAgent = match
            draft = ""
            return true

        case .branch:
            guard let query = invocation.arguments.nonEmptyTrimmed else {
                lastError = "Usage: /branch <name>"
                return false
            }
            guard let match = bestMatchingBranch(for: query) else {
                lastError = "No branch matches '\(query)'."
                return false
            }
            await switchBranch(named: match)
            guard lastError == nil else { return false }
            draft = ""
            return true

        case .reasoning:
            guard let query = invocation.arguments.nonEmptyTrimmed else {
                lastError = "Usage: /reasoning <level>"
                return false
            }
            guard let match = bestMatchingThinkingLevel(for: query) else {
                lastError = "No reasoning level matches '\(query)'."
                return false
            }
            selectedThinkingLevel = match
            draft = ""
            return true

        case .workspace:
            guard let project = projects.first(where: { $0.id == projectID }) else {
                lastError = "Select a project before opening a workspace."
                return false
            }
            let service = WorkspaceToolService()
            let tools = service.discoveredTools()
            guard !tools.isEmpty else {
                lastError = "No supported workspace tools were found."
                return false
            }
            let preferredID = preferredEditorID(for: projectID)
            let tool = tools.first(where: { $0.id == preferredID })
                ?? service.defaultToolID(from: tools).flatMap { id in tools.first(where: { $0.id == id }) }
                ?? tools.first
            guard let tool else {
                lastError = "No supported workspace tools were found."
                return false
            }
            setPreferredEditorID(tool.id, for: projectID)
            service.openProject(at: project.path, with: tool)
            draft = ""
            return true

        case .yolo:
            guard let sessionID = selectedSession?.id else {
                lastError = "Select a session before changing YOLO mode."
                return false
            }
            let action = invocation.arguments.lowercased()
            let nextValue: Bool
            switch action {
            case "", "toggle":
                nextValue = !isYoloModeEnabled(for: sessionID)
            case "on", "enable", "enabled", "true":
                nextValue = true
            case "off", "disable", "disabled", "false":
                nextValue = false
            default:
                lastError = "Usage: /yolo [on|off|toggle]"
                return false
            }
            setYoloMode(nextValue, for: sessionID)
            draft = ""
            _ = runtime
            return true
        }
    }

    private func bestMatchingModel(for query: String) -> ComposerModelOption? {
        bestMatch(in: availableModels, query: query) { model in
            [model.title, model.providerID, model.modelID, model.id]
        }
    }

    private func bestMatchingAgent(for query: String) -> String? {
        bestMatch(in: availableAgents, query: query) { agent in
            [agent, displayAgentName(agent)]
        }
    }

    private func bestMatchingBranch(for query: String) -> String? {
        bestMatch(in: availableBranches, query: query) { [$0] }
    }

    private func bestMatchingThinkingLevel(for query: String) -> String? {
        bestMatch(in: availableThinkingLevels, query: query) { [$0] }
    }

    private func bestMatch<T>(in values: [T], query: String, searchableText: (T) -> [String]) -> T? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return nil }

        return values.first(where: { value in
            searchableText(value).contains(where: { $0.lowercased() == normalizedQuery })
        }) ?? values.first(where: { value in
            searchableText(value).contains(where: { $0.lowercased().hasPrefix(normalizedQuery) })
        }) ?? values.first(where: { value in
            searchableText(value).contains(where: { $0.lowercased().contains(normalizedQuery) })
        })
    }

    private func seedComposerDefaults() {
        let fallback = ComposerModelOption(id: "openai/gpt-5.4", providerID: "openai", modelID: "gpt-5.4", title: "GPT-5.4", variants: ["high", "medium", "low"])
        availableModels = [fallback]
        selectedModelID = fallback.id
        availableAgents = ["Builder"]
        availableCommands = []
        selectedAgent = "Builder"
        availableThinkingLevels = fallback.variants
        selectedThinkingLevel = fallback.variants.first
        availableBranches = ["main"]
        selectedBranch = "main"
    }

    private func loadSessions(using service: any OpenCodeServicing, for projectID: ProjectSummary.ID, allowCachedFallback: Bool = false) async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }

        let keepsCurrentUI = allowCachedFallback && (hasCachedSessions(in: projectID) || selectedSession?.isEphemeral == true)

        do {
            let sessions = try await service.listSessions()
                .filter(\.isRootVisible)
                .sorted { $0.updatedAt > $1.updatedAt }
            guard !Task.isCancelled else { return }
            replaceSessions(
                in: projectID,
                with: sessions.map { session in
                    let fallbackTitle = sessionSummary(for: session.id, projectID: projectID)?.title ?? SessionSummary.defaultTitle
                    return SessionSummary(session: session, fallbackTitle: fallbackTitle)
                }
            )

            if let selectedSessionID,
               self.projectID(for: selectedSessionID) == projectID,
               session(for: selectedSessionID)?.isEphemeral != true {
                await loadMessages(for: selectedSessionID, using: service, projectID: projectID, allowCachedFallback: allowCachedFallback)
            }

            if !keepsCurrentUI {
                lastError = nil
            }
        } catch is CancellationError {
            logger.debug("Cancelled session load for project=\(projectID.uuidString, privacy: .public)")
        } catch {
            logger.error("Failed to load sessions: \(error.localizedDescription, privacy: .public)")
            if !keepsCurrentUI {
                lastError = error.localizedDescription
            }
        }
    }

    private func loadSessionStatuses(using service: any OpenCodeServicing, for projectID: ProjectSummary.ID) async {
        do {
            let remoteStatuses = try await service.listSessionStatuses()
            applyLiveSessionStatuses(remoteStatuses, projectID: projectID)
        } catch {
            logger.error("Failed to load session statuses: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadMessages(for sessionID: String, using service: any OpenCodeServicing, projectID: ProjectSummary.ID, allowCachedFallback: Bool = false) async {
        let loadKey = "\(projectID.uuidString)|\(sessionID)"
        guard activeTranscriptLoadKeys.insert(loadKey).inserted else { return }

        let keepsCurrentUI = allowCachedFallback && hasCachedTranscript(for: sessionID, projectID: projectID)
        let shouldTrackVisibleLoadingState = selectedSessionID == sessionID && selectedProjectID == projectID

        if shouldTrackVisibleLoadingState {
            loadingTranscriptSessionID = sessionID
        }

        defer {
            activeTranscriptLoadKeys.remove(loadKey)

            if loadingTranscriptSessionID == sessionID {
                loadingTranscriptSessionID = nil
            }
        }

        do {
            let messages = try await service.listMessages(sessionID: sessionID)
            guard !Task.isCancelled else { return }
            let transcript = ChatMessage.makeTranscript(from: messages)
            for message in messages {
                messageRoles[message.info.id] = message.info.chatRole
            }
            replaceTranscript(in: sessionID, projectID: projectID, with: transcript)
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
            if !keepsCurrentUI {
                lastError = nil
            }
        } catch is CancellationError {
            logger.debug("Cancelled message load for session \(sessionID, privacy: .public)")
        } catch {
            logger.error("Failed to load messages for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if !keepsCurrentUI {
                lastError = error.localizedDescription
                setSessionStatus(.attention, sessionID: sessionID, projectID: projectID)
            }
        }
    }

    private func subscribeToEvents(
        using service: any OpenCodeServicing,
        projectID: ProjectSummary.ID,
        connectionIdentifier: String,
        runtime: OpenCodeRuntime
    ) {
        logger.info(
            "Subscribing to live event stream for project id: \(projectID.uuidString, privacy: .public) connection=\(connectionIdentifier, privacy: .public)"
        )
        eventTasks[projectID]?.cancel()
        let subscriptionToken = UUID()
        logger.debug("Created event subscription token=\(subscriptionToken.uuidString, privacy: .public)")
        eventSubscriptionTokens[projectID] = subscriptionToken
        subscribedConnectionIdentifiers[projectID] = connectionIdentifier

        guard let projectPath = projectPath(for: projectID) else { return }

        eventTasks[projectID] = Task { [weak self] in
            guard let self else { return }
            defer { clearEventSubscriptionIfCurrent(for: projectID, token: subscriptionToken) }
            var reconnectAttempt = 0
            var streamService = service

            while !Task.isCancelled {
                guard self.hasActiveSubscription(projectID: projectID, connectionIdentifier: connectionIdentifier, token: subscriptionToken) else {
                    return
                }

                do {
                    logger.info(
                        "Opening live event stream attempt=\(reconnectAttempt + 1, privacy: .public) project=\(projectID.uuidString, privacy: .public)"
                    )
                    let stream = try streamService.eventStream()
                    for try await event in stream {
                        if Task.isCancelled || !self.hasActiveSubscription(projectID: projectID, connectionIdentifier: connectionIdentifier, token: subscriptionToken) {
                            return
                        }

                        runtime.markUsed(for: projectPath)

                        if case .connected = event {
                            reconnectAttempt = 0
                            logger.info(
                                "Live event stream connected for project id: \(projectID.uuidString, privacy: .public) token=\(subscriptionToken.uuidString, privacy: .public)"
                            )
                            lastError = nil
                            refreshSelectedSessionMessages(projectID: projectID)
                        } else if case .ignored = event {
                        } else {
                            reconnectAttempt = 0
                            logger.debug("Received live event: \(event.debugName, privacy: .public)")
                        }

                        self.apply(event: event, projectID: projectID)
                        switch event {
                        case .sessionCreated(let session):
                            self.noteDashboardChange(projectID: projectID, sessionID: session.id, using: runtime)
                        case .sessionUpdated(let session):
                            self.noteDashboardChange(projectID: projectID, sessionID: session.id, using: runtime)
                        case .sessionDeleted(let sessionID):
                            self.noteDashboardChange(projectID: projectID, sessionID: sessionID, using: runtime)
                        case .messageUpdated(let info):
                            self.noteDashboardChange(projectID: projectID, sessionID: info.sessionID, using: runtime)
                        case .messagePartUpdated(let part):
                            self.noteDashboardChange(projectID: projectID, sessionID: part.sessionID, using: runtime)
                        case .messagePartDelta(let delta):
                            self.noteDashboardChange(projectID: projectID, sessionID: delta.sessionID, using: runtime)
                        case .connected,
                                .sessionStatusChanged,
                                .permissionAsked,
                                .permissionReplied,
                                .questionAsked,
                                .questionReplied,
                                .questionRejected,
                                .ignored:
                            break
                        }
                        self.reevaluateRuntimeRetention(using: runtime)
                    }

                    if Task.isCancelled || !self.hasActiveSubscription(projectID: projectID, connectionIdentifier: connectionIdentifier, token: subscriptionToken) {
                        return
                    }

                    reconnectAttempt += 1
                    let delay = reconnectDelay(for: reconnectAttempt)
                    logger.warning(
                        "Live event stream ended for project id: \(projectID.uuidString, privacy: .public). Reconnecting in \(delay.components.seconds, privacy: .public)s"
                    )
                    do {
                        try await Task.sleep(for: delay)
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }

                    if let nextService = await self.connectProject(projectID, using: runtime, includeComposerOptions: false) {
                        streamService = nextService
                    }
                } catch is CancellationError {
                    logger.debug(
                        "Live event stream task cancelled project=\(projectID.uuidString, privacy: .public) token=\(subscriptionToken.uuidString, privacy: .public)"
                    )
                    return
                } catch {
                    guard self.hasActiveSubscription(projectID: projectID, connectionIdentifier: connectionIdentifier, token: subscriptionToken) else {
                        return
                    }
                    reconnectAttempt += 1
                    let delay = reconnectDelay(for: reconnectAttempt)
                    logger.error(
                        "Live event stream failed for project id: \(projectID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public). Reconnecting in \(delay.components.seconds, privacy: .public)s"
                    )
                    do {
                        try await Task.sleep(for: delay)
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }

                    if let nextService = await self.connectProject(projectID, using: runtime, includeComposerOptions: false) {
                        streamService = nextService
                    }
                }
            }
        }
    }

    private func refreshSelectedSessionMessages(projectID: ProjectSummary.ID) {
        guard let selectedSessionID,
              session(for: selectedSessionID)?.isEphemeral != true,
              self.projectID(for: selectedSessionID) == projectID,
              let service = liveServices[projectID]
        else { return }

        logger.debug(
            "Scheduling transcript refresh after stream connect session=\(selectedSessionID, privacy: .public) project=\(projectID.uuidString, privacy: .public)"
        )
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            await self.loadMessages(for: selectedSessionID, using: service, projectID: projectID, allowCachedFallback: true)
        }
    }

    private func scheduleStreamingRecoveryCheck(
        for sessionID: String,
        projectID: ProjectSummary.ID,
        using runtime: OpenCodeRuntime,
        attemptsRemaining: Int = 3,
        baselineRevision: Int? = nil
    ) {
        guard attemptsRemaining > 0 else {
            cancelStreamingRecoveryCheck(for: sessionID)
            return
        }

        let initialRevision = baselineRevision ?? transcriptRevision(for: sessionID, projectID: projectID)
        logger.debug(
            "Scheduling streaming recovery check session=\(sessionID, privacy: .public) attemptsRemaining=\(attemptsRemaining, privacy: .public) baselineRevision=\(initialRevision, privacy: .public)"
        )
        streamingRecoveryTasks[sessionID]?.cancel()
        streamingRecoveryTasks[sessionID] = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled,
                  let session = sessionSummary(for: sessionID, projectID: projectID),
                  session.status == .running
            else {
                logger.debug(
                    "Skipping streaming recovery check session=\(sessionID, privacy: .public) because task cancelled or session no longer running"
                )
                cancelStreamingRecoveryCheck(for: sessionID)
                return
            }

            let currentRevision = transcriptRevision(for: sessionID, projectID: projectID)
            guard currentRevision == initialRevision else {
                logger.debug(
                    "Streaming recovery check satisfied by transcript progress session=\(sessionID, privacy: .public) baselineRevision=\(initialRevision, privacy: .public) currentRevision=\(currentRevision, privacy: .public)"
                )
                cancelStreamingRecoveryCheck(for: sessionID)
                return
            }

            logger.warning(
                "No streamed updates detected for running session \(sessionID, privacy: .public); refreshing transcript"
            )

            if let service = await connectProject(projectID, using: runtime, includeComposerOptions: false) {
                await loadMessages(for: sessionID, using: service, projectID: projectID, allowCachedFallback: true)
            }

            scheduleStreamingRecoveryCheck(
                for: sessionID,
                projectID: projectID,
                using: runtime,
                attemptsRemaining: attemptsRemaining - 1,
                baselineRevision: transcriptRevision(for: sessionID, projectID: projectID)
            )
        }
    }

    private func cancelStreamingRecoveryCheck(for sessionID: String) {
        if streamingRecoveryTasks[sessionID] != nil {
            logger.debug("Cancelling streaming recovery check session=\(sessionID, privacy: .public)")
        }
        streamingRecoveryTasks[sessionID]?.cancel()
        streamingRecoveryTasks.removeValue(forKey: sessionID)
    }

    private func apply(part: OpenCodePart, projectID: ProjectSummary.ID) {
        guard let sessionID = part.sessionID else { return }
        markSessionLocallyActive(sessionID)
        flushBufferedTextDeltas(for: sessionID, projectID: projectID)
        let defaultRole = part.messageID.flatMap { messageRoles[$0] } ?? .assistant
        guard let message = ChatMessage(part: part, defaultRole: defaultRole) ?? streamingPlaceholder(for: part, defaultRole: defaultRole) else {
            return
        }

        if message.role == .user {
            reconcileOptimisticUserMessage(with: message, sessionID: sessionID, projectID: projectID)
            reconcileOptimisticAttachmentMessage(with: message, sessionID: sessionID, projectID: projectID)
        }

        upsertMessage(message, in: sessionID, projectID: projectID)
        touchSession(sessionID: sessionID, projectID: projectID, updatedAt: message.timestamp)
        refreshSessionStatus(sessionID: sessionID, projectID: projectID)
    }

    private func apply(delta: OpenCodePartDelta, projectID: ProjectSummary.ID) {
        guard delta.field == "text",
              let indices = indices(for: delta.sessionID, projectID: projectID)
        else {
            return
        }

        markSessionLocallyActive(delta.sessionID)
        let key = BufferedTextDeltaKey(projectID: projectID, sessionID: delta.sessionID, partID: delta.partID)
        if var buffered = bufferedTextDeltas[key] {
            buffered.text += delta.delta
            buffered.updatedAt = .now
            bufferedTextDeltas[key] = buffered
        } else {
            bufferedTextDeltas[key] = BufferedTextDelta(
                messageID: delta.messageID,
                text: delta.delta,
                updatedAt: .now
            )
            bufferedTextDeltaOrder.append(key)
        }

        if projects[indices.project].sessions[indices.session].status == .idle {
            projects[indices.project].sessions[indices.session].status = .running
        }
        scheduleBufferedDeltaFlush()
        scheduleProjectPersistence(.streaming)
    }

    private func reconnectDelay(for attempt: Int) -> Duration {
        let cappedAttempt = min(max(attempt, 1), 6)
        let baseSeconds = min(pow(2, Double(cappedAttempt - 1)) * 0.5, 8)
        let jitterSeconds = Double.random(in: 0 ... 0.25)
        return .milliseconds(Int((baseSeconds + jitterSeconds) * 1000))
    }

    private func isCurrentConnection(_ connectionIdentifier: String, for projectID: ProjectSummary.ID, runtime: OpenCodeRuntime) -> Bool {
        guard let project = projects.first(where: { $0.id == projectID }),
              let connection = runtime.connection(for: project.path)
        else {
            return false
        }

        return Self.connectionIdentifier(for: connection) == connectionIdentifier
    }

    private func hasActiveSubscription(projectID: ProjectSummary.ID, connectionIdentifier: String, token: UUID) -> Bool {
        eventSubscriptionTokens[projectID] == token && subscribedConnectionIdentifiers[projectID] == connectionIdentifier
    }

    private func clearEventSubscriptionIfCurrent(for projectID: ProjectSummary.ID, token: UUID) {
        guard eventSubscriptionTokens[projectID] == token else { return }
        logger.debug(
            "Clearing event subscription project=\(projectID.uuidString, privacy: .public) token=\(token.uuidString, privacy: .public)"
        )
        eventTasks.removeValue(forKey: projectID)
        eventSubscriptionTokens.removeValue(forKey: projectID)
    }

    private func reevaluateRuntimeRetention(using runtime: OpenCodeRuntime) {
        let knownProjectIDs = Set(projects.map(\.id))

        for projectID in runtimeIdleTasks.keys where !knownProjectIDs.contains(projectID) {
            runtimeIdleTasks[projectID]?.cancel()
            runtimeIdleTasks.removeValue(forKey: projectID)
        }

        for project in projects {
            if shouldKeepRuntimeAlive(for: project.id) {
                runtimeIdleTasks[project.id]?.cancel()
                runtimeIdleTasks.removeValue(forKey: project.id)
                continue
            }

            if liveServices[project.id] != nil || eventTasks[project.id] != nil || runtime.state(for: project.path) != .idle {
                scheduleRuntimeIdleShutdown(for: project.id, using: runtime)
            }
        }
    }

    private func scheduleRuntimeIdleShutdown(for projectID: ProjectSummary.ID, using runtime: OpenCodeRuntime) {
        guard runtimeIdleTasks[projectID] == nil else { return }

        runtimeIdleTasks[projectID] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.runtimeIdleTTL)
            if Task.isCancelled { return }

            await MainActor.run {
                self.runtimeIdleTasks[projectID] = nil

                guard !self.shouldKeepRuntimeAlive(for: projectID),
                      let project = self.projects.first(where: { $0.id == projectID })
                else {
                    return
                }

                self.logger.info("Stopping idle runtime for project: \(project.path, privacy: .public)")
                self.disconnectLiveState(for: projectID)
                runtime.stop(projectPath: project.path)
            }
        }
    }

    private func shouldKeepRuntimeAlive(for projectID: ProjectSummary.ID) -> Bool {
        guard let project = projects.first(where: { $0.id == projectID }) else { return false }

        if selectedProjectID == projectID {
            return true
        }

        return project.sessions.contains { session in
            session.status == .running || pendingPermission(for: session.id) != nil || pendingQuestion(for: session.id) != nil
        }
    }

    private func projectSessionIDs(for projectID: ProjectSummary.ID) -> [String] {
        projects.first(where: { $0.id == projectID })?.sessions.map(\.id) ?? []
    }

    private func projectPath(for projectID: ProjectSummary.ID) -> String? {
        projects.first(where: { $0.id == projectID })?.path
    }

    private func applyCachedGitState(for projectPath: String?) {
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

    private func cacheCurrentGitState(for projectPath: String) {
        gitStateByProjectPath[projectPath] = GitCachedState(
            status: gitStatus,
            commitPreview: gitCommitPreview,
            branches: availableBranches,
            selectedBranch: selectedBranch
        )
    }

    private func applyPostCommitState(pushAfterCommit: Bool, for projectPath: String) {
        let aheadCount = pushAfterCommit ? 0 : (gitStatus.hasRemote ? max(1, gitStatus.aheadCount + 1) : 0)
        let hasRemote = gitStatus.hasRemote
        gitStatus = GitRepositoryStatus(isRepository: true, hasChanges: false, aheadCount: aheadCount, hasRemote: hasRemote)
        logger.debug(
            "Applied optimistic post-commit state path=\(projectPath, privacy: .public) changes=false ahead=\(aheadCount, privacy: .public) hasRemote=\(hasRemote, privacy: .public)"
        )
        cacheCurrentGitState(for: projectPath)
    }

    private func scheduleGitRefreshAfterOperation(for projectPath: String) {
        Task { [weak self] in
            guard let self else { return }
            self.logger.debug("Scheduling post-operation git refresh for path=\(projectPath, privacy: .public)")
            await self.refreshGitStatus()
            await self.refreshGitCommitPreview(showLoadingIndicator: false, projectPathOverride: projectPath)
        }
    }

    private func setGitOperationState(_ state: GitOperationState, for projectPath: String) {
        gitOperationStateByProjectPath[projectPath] = state
    }

    private func clearGitOperationState(for projectPath: String) {
        gitOperationStateByProjectPath.removeValue(forKey: projectPath)
    }

    private func resetGitState() {
        gitStatus = .notRepository
        gitCommitPreview = nil
        availableBranches = []
        selectedBranch = "main"
    }

    private static func connectionIdentifier(for connection: OpenCodeRuntime.Connection) -> String {
        "\(connection.projectPath)|\(connection.baseURL.absoluteString)|\(connection.username)"
    }

    private func replaceSessions(in projectID: ProjectSummary.ID, with sessions: [SessionSummary]) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let ephemeralSessions = projects[projectIndex].sessions.filter(\.isEphemeral)
        let cachedSessions = Self.sessionLookup(for: projects[projectIndex].sessions)
        let previousSessionIDs = Set(projects[projectIndex].sessions.map(\.id))

        for session in sessions {
            seedTranscript(session.transcript, for: session.id)
        }

        let mergedSessions = ephemeralSessions + sessions.map { incoming in
            let transcript = transcript(for: incoming.id)
            guard let existing = cachedSessions[incoming.id] else {
                var inserted = incoming.applyingInferredTitle(from: transcript)
                inserted.transcript = []
                inserted.status = resolvedSessionStatus(sessionID: inserted.id, transcript: transcript, fallback: inserted.status)
                return inserted
            }

            var merged = incoming
            merged.transcript = []
            merged.status = existing.status
            merged.lastUpdatedAt = max(existing.lastUpdatedAt, incoming.lastUpdatedAt)
            return merged.applyingInferredTitle(from: transcript)
        }

        let retainedSessionIDs = Set(mergedSessions.map(\.id))
        let removedSessionIDs = previousSessionIDs.subtracting(retainedSessionIDs)
        projects[projectIndex].sessions = mergedSessions
        for sessionID in removedSessionIDs {
            removeTranscript(for: sessionID)
        }
        if selectedProjectID == projectID,
           let selectedSessionID,
           !mergedSessions.contains(where: { $0.id == selectedSessionID }) {
            self.selectedSessionID = nil
        }
        scheduleProjectPersistence()
    }

    private func replaceTranscript(in sessionID: String, projectID: ProjectSummary.ID, with transcript: [ChatMessage]) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        discardBufferedTextDeltas(for: sessionID, projectID: projectID)
        setTranscript(transcript, for: sessionID)
        projects[indices.project].sessions[indices.session].lastUpdatedAt = transcript.last?.timestamp ?? projects[indices.project].sessions[indices.session].lastUpdatedAt
        applyInferredTitleIfNeeded(sessionIndex: indices.session, projectIndex: indices.project)
        scheduleProjectPersistence()
    }

    private func upsert(session: SessionSummary, in projectID: ProjectSummary.ID, preferTopInsertion: Bool) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        seedTranscript(session.transcript, for: session.id)
        let transcript = transcript(for: session.id)
        if let sessionIndex = projects[projectIndex].sessions.firstIndex(where: { $0.id == session.id }) {
            var updated = session
            updated.transcript = []
            updated = updated.applyingInferredTitle(from: transcript)
            projects[projectIndex].sessions[sessionIndex] = updated
            projects[projectIndex].sessions[sessionIndex].status = resolvedSessionStatus(
                sessionID: session.id,
                transcript: transcript,
                fallback: projects[projectIndex].sessions[sessionIndex].status
            )
        } else if preferTopInsertion {
            var inserted = session.applyingInferredTitle(from: transcript)
            inserted.transcript = []
            inserted.status = resolvedSessionStatus(sessionID: session.id, transcript: transcript, fallback: inserted.status)
            projects[projectIndex].sessions.insert(inserted, at: 0)
        } else {
            var inserted = session.applyingInferredTitle(from: transcript)
            inserted.transcript = []
            inserted.status = resolvedSessionStatus(sessionID: session.id, transcript: transcript, fallback: inserted.status)
            projects[projectIndex].sessions.append(inserted)
        }

        scheduleProjectPersistence()
    }

    private func removeSession(_ sessionID: String, in projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        discardBufferedTextDeltas(for: sessionID, projectID: projectID)
        clearLocalSessionActivity(sessionID)
        removeTranscript(for: sessionID)
        projects[projectIndex].sessions.removeAll(where: { $0.id == sessionID })
        cancelStreamingRecoveryCheck(for: sessionID)
        liveSessionStatuses.removeValue(forKey: sessionID)
        pendingPermissionsBySession.removeValue(forKey: sessionID)
        pendingQuestionsBySession.removeValue(forKey: sessionID)
        if selectedSessionID == sessionID {
            selectedSessionID = nil
        }
        scheduleProjectPersistence()
    }

    private func upsertMessage(_ message: ChatMessage, in sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        var transcript = transcript(for: sessionID)
        if let messageIndex = transcript.firstIndex(where: { $0.id == message.id }) {
            transcript[messageIndex] = message
        } else {
            transcript.append(message)
        }
        setTranscript(transcript, for: sessionID)
        projects[indices.project].sessions[indices.session].lastUpdatedAt = message.timestamp
        applyInferredTitleIfNeeded(sessionIndex: indices.session, projectIndex: indices.project)
        scheduleProjectPersistence()
    }

    private func removeMessage(id: String, sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        var transcript = transcript(for: sessionID)
        transcript.removeAll(where: { $0.id == id })
        setTranscript(transcript, for: sessionID)
        projects[indices.project].sessions[indices.session].lastUpdatedAt = transcript.last?.timestamp ?? projects[indices.project].sessions[indices.session].lastUpdatedAt
        scheduleProjectPersistence()
    }

    private func setSessionStatus(_ status: SessionStatus, sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }

        switch status {
        case .running:
            markSessionLocallyActive(sessionID)
        case .idle, .attention:
            clearLocalSessionActivity(sessionID)
        }

        projects[indices.project].sessions[indices.session].status = status
        if status != .running {
            cancelStreamingRecoveryCheck(for: sessionID)
            flushPendingProjectPersistence()
            return
        }
        scheduleProjectPersistence(.streaming)
    }

    private func refreshSessionStatus(sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        let transcript = transcript(for: sessionID)
        projects[indices.project].sessions[indices.session].status = resolvedSessionStatus(
            sessionID: sessionID,
            transcript: transcript,
            fallback: projects[indices.project].sessions[indices.session].status
        )
        if projects[indices.project].sessions[indices.session].status != .running {
            cancelStreamingRecoveryCheck(for: sessionID)
            flushPendingProjectPersistence()
            return
        }
        scheduleProjectPersistence(.streaming)
    }

    private func transcriptRevision(for sessionID: String, projectID: ProjectSummary.ID) -> Int {
        guard indices(for: sessionID, projectID: projectID) != nil else { return 0 }
        return transcriptRevisionToken(for: sessionID)
    }

    private func applyLiveSessionStatuses(_ statuses: [String: OpenCodeSessionActivity], projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }

        for session in projects[projectIndex].sessions {
            liveSessionStatuses[session.id] = statuses[session.id] ?? .idle
        }

        for session in projects[projectIndex].sessions {
            refreshSessionStatus(sessionID: session.id, projectID: projectID)
        }
    }

    private func resolvedSessionStatus(sessionID: String, transcript: [ChatMessage], fallback: SessionStatus = .idle) -> SessionStatus {
        if pendingPermission(for: sessionID) != nil {
            return .attention
        }

        if pendingQuestion(for: sessionID) != nil {
            return .attention
        }

        if let activity = liveSessionStatuses[sessionID] {
            switch activity {
            case .idle:
                return .idle
            case .busy:
                guard isSessionLocallyActive(sessionID) else { break }
                return .running
            case .retry:
                guard isSessionLocallyActive(sessionID) else { break }
                return .attention
            }
        }

        return transcriptDerivedStatus(for: transcript, sessionID: sessionID, fallback: fallback)
    }

    private func transcriptDerivedStatus(
        for transcript: [ChatMessage],
        sessionID: String,
        fallback: SessionStatus = .idle
    ) -> SessionStatus {
        if isSessionLocallyActive(sessionID), transcript.contains(where: \.isInProgress) {
            return .running
        }

        if let toolCall = transcript.last?.kind.toolCall,
           toolCall.status == .error {
            return .attention
        }

        return fallback == .attention ? .attention : .idle
    }

    private func reconcileOptimisticUserMessage(with message: ChatMessage, sessionID: String, projectID: ProjectSummary.ID) {
        guard message.attachment == nil else { return }

        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        var transcript = transcript(for: sessionID)

        guard let optimisticIndex = transcript.firstIndex(where: {
            $0.id.hasPrefix("optimistic-user-") && $0.role == .user && $0.text == message.text
        }) else {
            return
        }

        transcript.remove(at: optimisticIndex)
        setTranscript(transcript, for: sessionID)
        projects[indices.project].sessions[indices.session].lastUpdatedAt = message.timestamp
    }

    private func reconcileOptimisticAttachmentMessage(with message: ChatMessage, sessionID: String, projectID: ProjectSummary.ID) {
        guard let attachment = message.attachment,
              let indices = indices(for: sessionID, projectID: projectID)
        else {
            return
        }

        var transcript = transcript(for: sessionID)
        guard let optimisticIndex = transcript.firstIndex(where: {
            $0.id.hasPrefix("optimistic-user-attachment-") && $0.attachment?.optimisticKey == attachment.optimisticKey
        }) else {
            return
        }

        transcript.remove(at: optimisticIndex)
        setTranscript(transcript, for: sessionID)
        projects[indices.project].sessions[indices.session].lastUpdatedAt = message.timestamp
    }

    private func removeOptimisticAttachmentMessages(in sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        var transcript = transcript(for: sessionID)
        transcript.removeAll(where: {
            $0.id.hasPrefix("optimistic-user-attachment-")
        })
        setTranscript(transcript, for: sessionID)
        projects[indices.project].sessions[indices.session].lastUpdatedAt = transcript.last?.timestamp ?? projects[indices.project].sessions[indices.session].lastUpdatedAt
    }

    private func streamingPlaceholder(for part: OpenCodePart, defaultRole: ChatMessage.Role) -> ChatMessage? {
        guard (part.type == .text || part.type == .reasoning), part.text?.isEmpty ?? true else {
            return nil
        }

        return ChatMessage(
            id: part.id,
            messageID: part.messageID,
            role: part.chatRole(defaultRole: defaultRole),
            text: "",
            timestamp: part.updatedAt ?? Date(),
            emphasis: part.chatEmphasis,
            kind: .plain,
            isInProgress: true
        )
    }

    private func streamingPlaceholder(for delta: OpenCodePartDelta, projectID: ProjectSummary.ID) -> ChatMessage? {
        let defaultRole = messageRoles[delta.messageID] ?? .assistant
        guard defaultRole != .user else { return nil }

        return ChatMessage(
            id: delta.partID,
            messageID: delta.messageID,
            role: defaultRole,
            text: "",
            timestamp: Date(),
            emphasis: .normal,
            kind: .plain,
            isInProgress: true
        )
    }

    private func touchSession(sessionID: String, projectID: ProjectSummary.ID, updatedAt: Date) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        projects[indices.project].sessions[indices.session].lastUpdatedAt = updatedAt
        scheduleProjectPersistence()
    }

    private func replacePendingPermissions(_ requests: [OpenCodePermissionRequest], in projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let sessionIDs = Set(projects[projectIndex].sessions.map(\.id))

        for sessionID in sessionIDs {
            pendingPermissionsBySession.removeValue(forKey: sessionID)
        }

        for request in requests where sessionIDs.contains(request.sessionID) {
            upsertPendingPermission(request, in: projectID)
        }

        for sessionID in sessionIDs {
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
        }
    }

    private func upsertPendingPermission(_ request: OpenCodePermissionRequest, in projectID: ProjectSummary.ID) {
        var requests = pendingPermissionsBySession[request.sessionID] ?? []

        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            requests[index] = request
        } else {
            requests.append(request)
            requests.sort { $0.id < $1.id }
        }

        pendingPermissionsBySession[request.sessionID] = requests
        refreshSessionStatus(sessionID: request.sessionID, projectID: projectID)
    }

    private func removePendingPermission(requestID: String, sessionID: String, projectID: ProjectSummary.ID) {
        guard var requests = pendingPermissionsBySession[sessionID] else { return }
        requests.removeAll(where: { $0.id == requestID })

        if requests.isEmpty {
            pendingPermissionsBySession.removeValue(forKey: sessionID)
        } else {
            pendingPermissionsBySession[sessionID] = requests
        }

        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        let transcript = transcript(for: sessionID)
        projects[indices.project].sessions[indices.session].status = resolvedSessionStatus(
            sessionID: sessionID,
            transcript: transcript,
            fallback: .idle
        )
        scheduleProjectPersistence()
    }

    private func shouldAutoRespond(to request: OpenCodePermissionRequest) -> Bool {
        guard isYoloModeEnabled(for: request.sessionID)
        else {
            return false
        }

        pruneAutoRespondedPermissions()
        return autoRespondedPermissionIDs[request.id] == nil
    }

    private func autoRespondToPermission(_ request: OpenCodePermissionRequest, projectID: ProjectSummary.ID, service: any OpenCodeServicing) async {
        pruneAutoRespondedPermissions()
        guard autoRespondedPermissionIDs[request.id] == nil else { return }

        autoRespondedPermissionIDs[request.id] = Date()

        do {
            try await service.replyToPermission(requestID: request.id, reply: .once, message: nil)
            removePendingPermission(requestID: request.id, sessionID: request.sessionID, projectID: projectID)
        } catch {
            autoRespondedPermissionIDs.removeValue(forKey: request.id)
            logger.error("Failed to auto-respond to permission \(request.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            upsertPendingPermission(request, in: projectID)
        }
    }

    private func pruneAutoRespondedPermissions(now: Date = Date()) {
        autoRespondedPermissionIDs = autoRespondedPermissionIDs.filter { now.timeIntervalSince($0.value) < autoRespondedPermissionTTL }
    }

    private func persistDraftIfNeeded() {
        guard isPersistenceEnabled else { return }

        guard !isHydratingPrompt,
              isPromptReady,
              let sessionID = selectedSessionID,
              let promptKey = promptDraftKey(for: sessionID)
        else {
            return
        }

        promptDraftsByKey[promptKey] = draft
        loadedPromptKeys.insert(promptKey)

        promptPersistTask?.cancel()
        let promptDraftPersistence = promptDraftPersistence
        let value = draft
        promptPersistTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await promptDraftPersistence.saveDraft(value, forKey: promptKey)
        }
    }

    private func primePromptState(for sessionID: String?) {
        attachedFiles = []

        guard let sessionID,
              let promptKey = promptDraftKey(for: sessionID)
        else {
            isPromptReady = true
            promptLoadingText = nil
            isHydratingPrompt = true
            draft = ""
            isHydratingPrompt = false
            return
        }

        if loadedPromptKeys.contains(promptKey) {
            isPromptReady = true
            promptLoadingText = nil
            isHydratingPrompt = true
            draft = promptDraftsByKey[promptKey] ?? ""
            isHydratingPrompt = false
            return
        }

        isPromptReady = false
        promptLoadingText = promptDraftsByKey[promptKey].flatMap { $0.nonEmptyTrimmed }
        isHydratingPrompt = true
        draft = ""
        isHydratingPrompt = false
    }

    private func storePromptDraft(_ value: String, forKey promptKey: String) async {
        promptDraftsByKey[promptKey] = value
        loadedPromptKeys.insert(promptKey)
        guard isPersistenceEnabled else { return }
        await promptDraftPersistence.saveDraft(value, forKey: promptKey)
    }

    private func promptDraftKey(for sessionID: String) -> String? {
        guard let project = selectedProject ?? project(for: sessionID),
              session(for: sessionID) != nil
        else {
            return nil
        }

        if session(for: sessionID)?.isEphemeral == true {
            return "\(project.path)::workspace"
        }

        return "\(project.path)::\(sessionID)"
    }

    private func yoloPreferenceKey(for sessionID: String) -> String? {
        guard let project = selectedProject ?? project(for: sessionID) else { return nil }
        return "\(project.path)::\(sessionID)"
    }

    private func replacePendingQuestions(_ requests: [OpenCodeQuestionRequest], in projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let sessionIDs = Set(projects[projectIndex].sessions.map(\.id))

        for sessionID in sessionIDs {
            pendingQuestionsBySession.removeValue(forKey: sessionID)
        }

        for request in requests where sessionIDs.contains(request.sessionID) {
            upsertPendingQuestion(request, in: projectID)
        }

        for sessionID in sessionIDs {
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
        }
    }

    private func upsertPendingQuestion(_ request: OpenCodeQuestionRequest, in projectID: ProjectSummary.ID) {
        var requests = pendingQuestionsBySession[request.sessionID] ?? []

        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            requests[index] = request
        } else {
            requests.append(request)
            requests.sort { $0.id < $1.id }
        }

        pendingQuestionsBySession[request.sessionID] = requests
        refreshSessionStatus(sessionID: request.sessionID, projectID: projectID)
    }

    private func removePendingQuestion(requestID: String, sessionID: String, projectID: ProjectSummary.ID) {
        guard var requests = pendingQuestionsBySession[sessionID] else { return }
        requests.removeAll(where: { $0.id == requestID })

        if requests.isEmpty {
            pendingQuestionsBySession.removeValue(forKey: sessionID)
        } else {
            pendingQuestionsBySession[sessionID] = requests
        }

        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        let transcript = transcript(for: sessionID)
        projects[indices.project].sessions[indices.session].status = resolvedSessionStatus(
            sessionID: sessionID,
            transcript: transcript,
            fallback: .idle
        )
        scheduleProjectPersistence()
    }

    private func hasCachedSessions(in projectID: ProjectSummary.ID) -> Bool {
        guard let project = projects.first(where: { $0.id == projectID }) else { return false }
        return project.sessions.contains(where: { !$0.isEphemeral })
    }

    private func hasCachedTranscript(for sessionID: String, projectID: ProjectSummary.ID) -> Bool {
        guard indices(for: sessionID, projectID: projectID) != nil else { return false }
        return !transcript(for: sessionID).isEmpty
    }

    private func sessionSummary(for sessionID: String, projectID: ProjectSummary.ID) -> SessionSummary? {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return nil }
        return projects[indices.project].sessions[indices.session]
    }

    private func indices(for sessionID: String, projectID: ProjectSummary.ID) -> (project: Int, session: Int)? {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let sessionIndex = projects[projectIndex].sessions.firstIndex(where: { $0.id == sessionID })
        else { return nil }
        return (projectIndex, sessionIndex)
    }

    private func projectID(for sessionID: String) -> ProjectSummary.ID? {
        projects.first(where: { project in
            project.sessions.contains(where: { $0.id == sessionID })
        })?.id
    }

    private func session(for sessionID: String) -> SessionSummary? {
        projects
            .flatMap(\.sessions)
            .first(where: { $0.id == sessionID })
    }

    private func setTranscript(_ transcript: [ChatMessage], for sessionID: String) {
        var state = transcriptStateBySessionID[sessionID] ?? SessionTranscriptState()
        state.messages = transcript
        state.revision &+= 1
        transcriptStateBySessionID[sessionID] = state
    }

    private func seedTranscript(_ transcript: [ChatMessage], for sessionID: String) {
        guard !transcript.isEmpty else { return }

        if let existingState = transcriptStateBySessionID[sessionID],
           existingState.messages.count >= transcript.count {
            return
        }

        transcriptStateBySessionID[sessionID] = SessionTranscriptState(messages: transcript, revision: 0)
    }

    private func removeTranscript(for sessionID: String) {
        transcriptStateBySessionID.removeValue(forKey: sessionID)
    }

    private func moveTranscript(from sourceSessionID: String, to destinationSessionID: String) {
        guard sourceSessionID != destinationSessionID,
              let existingState = transcriptStateBySessionID.removeValue(forKey: sourceSessionID)
        else {
            return
        }

        transcriptStateBySessionID[destinationSessionID] = existingState
    }

    private func markSessionLocallyActive(_ sessionID: String) {
        locallyActiveSessionIDs.insert(sessionID)
    }

    private func clearLocalSessionActivity(_ sessionID: String) {
        locallyActiveSessionIDs.remove(sessionID)
    }

    private func isSessionLocallyActive(_ sessionID: String) -> Bool {
        locallyActiveSessionIDs.contains(sessionID)
    }

    private func createEphemeralSession(in projectID: ProjectSummary.ID) {
        discardSelectedEphemeralSessionIfNeeded()

        let session = SessionSummary(
            id: "draft-session-\(UUID().uuidString)",
            title: newSessionTitle,
            lastUpdatedAt: .now,
            isEphemeral: true
        )
        upsert(session: session, in: projectID, preferTopInsertion: true)
        selectedProjectID = projectID
        selectedSessionID = session.id
        primePromptState(for: session.id)
        lastError = nil
    }

    private func discardSelectedEphemeralSessionIfNeeded(excluding sessionID: String? = nil) {
        guard let selectedSessionID,
              selectedSessionID != sessionID,
              let projectID = projectID(for: selectedSessionID),
              session(for: selectedSessionID)?.isEphemeral == true
        else {
            return
        }

        removeSession(selectedSessionID, in: projectID)
    }

    private func updateEphemeralSessionTitleIfNeeded(sessionID: String, projectID: ProjectSummary.ID, title: String) -> Bool {
        guard let indices = indices(for: sessionID, projectID: projectID),
              projects[indices.project].sessions[indices.session].isEphemeral
        else {
            return false
        }

        projects[indices.project].sessions[indices.session].title = title
        projects[indices.project].sessions[indices.session].lastUpdatedAt = .now
        scheduleProjectPersistence()
        return true
    }

    private func removeEphemeralSessionIfNeeded(sessionID: String, projectID: ProjectSummary.ID) -> Bool {
        guard session(for: sessionID)?.isEphemeral == true else { return false }
        removeSession(sessionID, in: projectID)
        return true
    }

    private func resolveSessionForSend(projectID: ProjectSummary.ID, service: any OpenCodeServicing) async -> String? {
        guard let currentSessionID = selectedSessionID,
              let session = self.session(for: currentSessionID)
        else {
            return nil
        }

        guard session.isEphemeral else {
            return session.id
        }

        do {
            logger.info("Persisting draft session in project id: \(projectID.uuidString, privacy: .public)")
            let created = try await service.createSession(title: session.requestedServerTitle)
            logger.info("Persisted draft session as id: \(created.id, privacy: .public)")
            await promoteEphemeralSession(session.id, in: projectID, to: created)
            lastError = nil
            return created.id
        } catch {
            logger.error("Failed to persist draft session: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            return nil
        }
    }

    func promoteEphemeralSession(_ ephemeralSessionID: String, in projectID: ProjectSummary.ID, to created: OpenCodeSession) async {
        guard let ephemeralSession = session(for: ephemeralSessionID) else { return }

        let ephemeralPromptKey = promptDraftKey(for: ephemeralSessionID)
        let wasYoloEnabled = isYoloModeEnabled(for: ephemeralSessionID)

        replaceSession(
            ephemeralSessionID,
            in: projectID,
            with: SessionSummary(session: created, fallbackTitle: ephemeralSession.title)
        )
        selectedSessionID = created.id

        if wasYoloEnabled {
            setYoloMode(true, for: created.id)
        }

        if let ephemeralPromptKey {
            promptPersistTask?.cancel()
            promptPersistTask = nil
            await storePromptDraft("", forKey: ephemeralPromptKey)
        }
    }

    private func replaceSession(_ sessionID: String, in projectID: ProjectSummary.ID, with session: SessionSummary) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        discardBufferedTextDeltas(for: sessionID, projectID: projectID)
        seedTranscript(session.transcript, for: session.id)
        let existingTranscript = transcript(for: sessionID)

        projects[projectIndex].sessions.removeAll(where: { $0.id == session.id && $0.id != sessionID })

        guard let sessionIndex = projects[projectIndex].sessions.firstIndex(where: { $0.id == sessionID }) else {
            upsert(session: session, in: projectID, preferTopInsertion: true)
            return
        }

        let existing = projects[projectIndex].sessions[sessionIndex]
        var replacement = session.applyingInferredTitle(from: existingTranscript)
        replacement.status = existing.status
        replacement.transcript = []
        replacement.lastUpdatedAt = max(existing.lastUpdatedAt, session.lastUpdatedAt)
        projects[projectIndex].sessions[sessionIndex] = replacement
        moveTranscript(from: sessionID, to: session.id)
        scheduleProjectPersistence()
    }

    private static func normalizedProjects(_ projects: [ProjectSummary]) -> [ProjectSummary] {
        projects.map { project in
            var normalized = project
            normalized.sessions = deduplicatedSessions(project.sessions)
            return normalized
        }
    }

    private static func extractTranscriptState(from projects: [ProjectSummary]) -> (
        projects: [ProjectSummary],
        transcripts: [String: SessionTranscriptState]
    ) {
        var sanitizedProjects = projects
        var transcripts: [String: SessionTranscriptState] = [:]

        for projectIndex in sanitizedProjects.indices {
            for sessionIndex in sanitizedProjects[projectIndex].sessions.indices {
                let session = sanitizedProjects[projectIndex].sessions[sessionIndex]
                transcripts[session.id] = SessionTranscriptState(messages: session.transcript, revision: 0)
                sanitizedProjects[projectIndex].sessions[sessionIndex].transcript = []
            }
        }

        return (sanitizedProjects, transcripts)
    }

    private static func deduplicatedSessions(_ sessions: [SessionSummary]) -> [SessionSummary] {
        var orderedIDs: [String] = []
        var sessionsByID: [String: SessionSummary] = [:]

        for session in sessions {
            if let existing = sessionsByID[session.id] {
                sessionsByID[session.id] = mergeSession(existing, with: session)
            } else {
                orderedIDs.append(session.id)
                sessionsByID[session.id] = session
            }
        }

        return orderedIDs.compactMap { sessionsByID[$0] }
    }

    private static func sessionLookup(for sessions: [SessionSummary]) -> [String: SessionSummary] {
        var lookup: [String: SessionSummary] = [:]

        for session in deduplicatedSessions(sessions) {
            lookup[session.id] = session
        }

        return lookup
    }

    private static func mergeSession(_ existing: SessionSummary, with incoming: SessionSummary) -> SessionSummary {
        let preferredMetadata = incoming.lastUpdatedAt >= existing.lastUpdatedAt ? incoming : existing
        let fallbackMetadata = preferredMetadata.lastUpdatedAt == existing.lastUpdatedAt ? incoming : existing

        var merged = preferredMetadata

        if merged.hasPlaceholderTitle && !fallbackMetadata.hasPlaceholderTitle {
            merged.title = fallbackMetadata.title
        }

        if merged.transcript.isEmpty || fallbackMetadata.transcript.count > merged.transcript.count {
            merged.transcript = fallbackMetadata.transcript
        }

        if sessionStatusPriority(fallbackMetadata.status) > sessionStatusPriority(merged.status) {
            merged.status = fallbackMetadata.status
        }

        merged.lastUpdatedAt = max(existing.lastUpdatedAt, incoming.lastUpdatedAt)
        merged.isEphemeral = existing.isEphemeral && incoming.isEphemeral
        return merged.applyingInferredTitle(from: merged.transcript)
    }

    private static func sessionStatusPriority(_ status: SessionStatus) -> Int {
        switch status {
        case .idle:
            return 0
        case .running:
            return 1
        case .attention:
            return 2
        }
    }

    private func applyInferredTitleIfNeeded(sessionIndex: Int, projectIndex: Int) {
        let session = projects[projectIndex].sessions[sessionIndex]
        let inferred = session.applyingInferredTitle(from: transcript(for: session.id))
        guard inferred.title != session.title else { return }
        projects[projectIndex].sessions[sessionIndex].title = inferred.title
    }

    func flushPendingProjectPersistence() {
        flushBufferedTextDeltas()
        flushProjectPersistenceNow()
    }

    private func scheduleBufferedDeltaFlush() {
        bufferedDeltaFlushTask?.cancel()
        let delay = performanceOptions.deltaFlushDebounce
        bufferedDeltaFlushTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.flushBufferedTextDeltas()
        }
    }

    private func flushBufferedTextDeltas(for sessionID: String? = nil, projectID: ProjectSummary.ID? = nil) {
        let keysToFlush = bufferedTextDeltaOrder.filter { key in
            bufferedTextDeltas[key] != nil
                && (sessionID == nil || key.sessionID == sessionID)
                && (projectID == nil || key.projectID == projectID)
        }

        guard !keysToFlush.isEmpty else {
            if sessionID == nil && projectID == nil {
                bufferedDeltaFlushTask?.cancel()
                bufferedDeltaFlushTask = nil
            }
            return
        }

        var changedSessions = Set<String>()

        for key in keysToFlush {
            guard let buffered = bufferedTextDeltas.removeValue(forKey: key),
                  indices(for: key.sessionID, projectID: key.projectID) != nil
            else {
                continue
            }

            var transcript = transcript(for: key.sessionID)
            let messageIndex: Int
            if let existingIndex = transcript.firstIndex(where: { $0.id == key.partID }) {
                messageIndex = existingIndex
            } else {
                let placeholder = ChatMessage(
                    id: key.partID,
                    messageID: buffered.messageID,
                    role: messageRoles[buffered.messageID] ?? .assistant,
                    text: "",
                    timestamp: buffered.updatedAt,
                    emphasis: .normal,
                    kind: .plain,
                    isInProgress: true
                )
                transcript.append(placeholder)
                messageIndex = transcript.endIndex - 1
            }

            transcript[messageIndex].text += buffered.text
            transcript[messageIndex].timestamp = buffered.updatedAt
            setTranscript(transcript, for: key.sessionID)
            changedSessions.insert("\(key.projectID.uuidString)|\(key.sessionID)")
        }

        bufferedTextDeltaOrder.removeAll { bufferedTextDeltas[$0] == nil }

        for changedSession in changedSessions {
            let components = changedSession.split(separator: "|", maxSplits: 1).map(String.init)
            guard components.count == 2,
                  let projectID = UUID(uuidString: components[0]),
                  let indices = indices(for: components[1], projectID: projectID)
            else {
                continue
            }

            applyInferredTitleIfNeeded(sessionIndex: indices.session, projectIndex: indices.project)
            let transcript = transcript(for: components[1])
            projects[indices.project].sessions[indices.session].status = resolvedSessionStatus(
                sessionID: components[1],
                transcript: transcript,
                fallback: projects[indices.project].sessions[indices.session].status
            )
        }

        if sessionID == nil && projectID == nil {
            bufferedDeltaFlushTask?.cancel()
            bufferedDeltaFlushTask = nil
        }
    }

    private func discardBufferedTextDeltas(for sessionID: String, projectID: ProjectSummary.ID) {
        bufferedTextDeltas.keys
            .filter { $0.sessionID == sessionID && $0.projectID == projectID }
            .forEach { bufferedTextDeltas.removeValue(forKey: $0) }
        bufferedTextDeltaOrder.removeAll { $0.sessionID == sessionID && $0.projectID == projectID }
    }

    private func flushProjectPersistenceNow() {
        guard isPersistenceEnabled else {
            hasPendingProjectPersistence = false
            persistTask?.cancel()
            persistTask = nil
            return
        }

        persistTask?.cancel()
        persistTask = nil

        guard hasPendingProjectPersistence else { return }

        hasPendingProjectPersistence = false
        let projectSnapshot = projects
        let transcriptStateSnapshot = transcriptStateBySessionID
        projectPersistence.saveProjects(projectSnapshot, transcriptStatesBySessionID: transcriptStateSnapshot)
        projectPersistenceSaveCount += 1
    }

    private func scheduleProjectPersistence(_ mode: ProjectPersistenceMode = .standard) {
        guard isPersistenceEnabled else { return }

        hasPendingProjectPersistence = true

        persistTask?.cancel()
        let delay: Duration
        switch mode {
        case .standard:
            delay = performanceOptions.projectPersistenceDebounce
        case .streaming:
            delay = performanceOptions.streamingPersistenceDebounce
        }

        persistTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.flushPendingProjectPersistence()
        }
    }
}

private struct SlashCommandInvocation {
    let command: OpenCodeCommand
    let arguments: String
}

private struct LocalSlashCommandInvocation {
    let command: LocalComposerSlashCommand
    let arguments: String
}
