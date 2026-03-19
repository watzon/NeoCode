import Foundation
import Observation
import OSLog

nonisolated struct AppStorePerformanceOptions: Sendable {
    var projectPersistenceDebounce: Duration = .milliseconds(250)
    var streamingPersistenceDebounce: Duration = .seconds(2)
    var deltaFlushDebounce: Duration = .milliseconds(33)
}

struct AppTerminationWarningContext: Equatable {
    struct Session: Identifiable, Equatable {
        let id: String
        let projectName: String
        let sessionTitle: String
        let reason: String
    }

    let sessions: [Session]

    var count: Int {
        sessions.count
    }
}

@MainActor
@Observable
final class AppStore {
    private let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "AppStore")
    private let projectPersistence = PersistedProjectsStore()
    private let appSettingsPersistence = PersistedAppSettingsStore()
    private let workspaceSelectionPersistence = PersistedWorkspaceSelectionStore()
    private let promptDraftPersistence = PersistedPromptDraftsStore()
    private let yoloPreferencePersistence = PersistedYoloPreferencesStore()
    private let favoriteModelPersistence = PersistedFavoriteModelsStore()
    private let notificationService = NeoCodeNotificationService()
    private let sleepAssertionService = NeoCodeSleepAssertionService()
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

    struct StagedSendUI {
        let userMessageID: String?
        let attachmentMessageIDs: [String]
        let originalText: String
        let originalAttachments: [ComposerAttachment]
    }

    private struct PendingSendState {
        let token: UUID
        let projectID: ProjectSummary.ID
        let originalSessionID: String
        let task: Task<Void, Never>
        var activeSessionID: String?
        var stagedUI: StagedSendUI?
        var didAcceptRemoteSend = false
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
    var selectedProjectID: ProjectSummary.ID? {
        didSet {
            persistWorkspaceSelectionIfNeeded()
        }
    }
    var selectedContent: AppContentSelection {
        didSet {
            if case .settings = selectedContent {
                return
            }

            lastWorkspaceSelection = selectedContent
            persistWorkspaceSelectionIfNeeded()
        }
    }
    var appSettings: NeoCodeAppSettings {
        didSet {
            NeoCodeTheme.configure(with: appSettings.appearance)
            persistAppSettingsIfNeeded()
        }
    }
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
    private var availableAgentObjects: [OpenCodeAgent] = []
    private var ephemeralAgentModels: [String: String] = [:]
    private var preferredFallbackModelID: String?
    private var lastThinkingLevelByModelID: [String: String] = [:]
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
    var isLoadingSessions: Bool {
        loadingSessionCountsByProjectID.values.contains { $0 > 0 }
    }
    var loadingTranscriptSessionID: String?
    private(set) var lifecycleRefreshToken = 0
    private(set) var sessionUIRevision = 0
    var isSending = false
    var queuedMessagesBySessionID: [String: [ComposerQueuedMessage]] = [:]
    var activeTodosBySessionID: [String: SessionTodoSnapshot] = [:]
    var isRespondingToPrompt = false
    var isPromptReady = true
    var promptLoadingText: String?
    var selectedDashboardRange: DashboardTimeRange = .allTime
    var selectedDashboardProjectID: ProjectSummary.ID?
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
    private var cachedModelsByProjectPath: [String: [ComposerModelOption]] = [:]
    private var cachedCommandsByProjectPath: [String: [OpenCodeCommand]] = [:]
    private let runtimeIdleTTL: Duration = .seconds(60)
    private let gitRefreshFallbackInterval: Duration = .seconds(300)
    private let gitCommitPreviewRetryDelays: [Duration] = [.milliseconds(150), .milliseconds(500)]
    private var isRefreshingGitCommitPreview = false
    private var liveServices: [ProjectSummary.ID: any OpenCodeServicing] = [:]
    private var serviceConnectionIdentifiers: [ProjectSummary.ID: String] = [:]
    private var eventTasks: [ProjectSummary.ID: Task<Void, Never>] = [:]
    private var eventSubscriptionTokens: [ProjectSummary.ID: UUID] = [:]
    private var refreshTask: Task<Void, Never>?
    private var gitRefreshTask: Task<Void, Never>?
    private var gitRefreshDebounceTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var subscribedConnectionIdentifiers: [ProjectSummary.ID: String] = [:]
    private var runtimeIdleTasks: [ProjectSummary.ID: Task<Void, Never>] = [:]
    private var gitStateByProjectPath: [String: GitCachedState] = [:]
    private var gitOperationStateByProjectPath: [String: GitOperationState] = [:]
    private var streamingRecoveryTasks: [String: Task<Void, Never>] = [:]
    private var transcriptStateBySessionID: [String: SessionTranscriptState] = [:]
    private var messageRoles: [String: ChatMessage.Role] = [:]
    private var messageInfosBySessionID: [String: [String: OpenCodeMessageInfo]] = [:]
    private var liveSessionStatuses: [String: OpenCodeSessionActivity] = [:]
    private var pendingPermissionsBySession: [String: [OpenCodePermissionRequest]] = [:]
    private var pendingQuestionsBySession: [String: [OpenCodeQuestionRequest]] = [:]
    private var promptDraftsByKey: [String: String] = [:]
    private var loadedPromptKeys = Set<String>()
    private var isHydratingPrompt = false
    private var promptPersistTask: Task<Void, Never>?
    private var yoloSessionKeys: Set<String>
    private var favoriteModelIDs: Set<String> = []
    private var isApplyingSessionComposerState = false
    private var autoRespondedPermissionIDs: [String: Date] = [:]
    private var activeTranscriptLoadKeys = Set<String>()
    private var locallyActiveSessionIDs = Set<String>()
    private var observedRunningSessionIDs = Set<String>()
    private var finishedSessionIDs = Set<String>()
    private var failedSessionIDs = Set<String>()
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
    private var queuedMessageDispatchingSessionIDs = Set<String>()
    private var sessionCreationTasksBySessionID: [String: Task<String?, Never>] = [:]
    private var sessionIDAliases: [String: String] = [:]
    private var pendingSendStatesByOriginalSessionID: [String: PendingSendState] = [:]
    private var lastWorkspaceSelection: AppContentSelection = .dashboard
    private var sessionListSyncActivityByProjectID: [ProjectSummary.ID: Int] = [:]
    private var loadingSessionCountsByProjectID: [ProjectSummary.ID: Int] = [:]

    init() {
        let normalizedProjects = Self.normalizedProjects(PersistedProjectsStore().loadProjects())
        let extractedState = Self.extractTranscriptState(from: normalizedProjects)
        let loadedAppSettings = PersistedAppSettingsStore().loadSettings()
        let restoredWorkspaceSelection = PersistedWorkspaceSelectionStore().loadSelection()
        let initialWorkspaceSelection = Self.initialWorkspaceSelection(
            projects: extractedState.projects,
            startupBehavior: loadedAppSettings.general.startupBehavior,
            restoredSelection: restoredWorkspaceSelection
        )
        self.projects = extractedState.projects
        self.transcriptStateBySessionID = extractedState.transcripts
        self.selectedProjectID = initialWorkspaceSelection.projectID
        self.selectedContent = initialWorkspaceSelection.content
        self.appSettings = loadedAppSettings
        self.loadingTranscriptSessionID = nil
        self.selectedDashboardRange = .allTime
        self.yoloSessionKeys = loadedAppSettings.general.remembersYoloModePerThread
            ? PersistedYoloPreferencesStore().loadYoloSessionKeys()
            : []
        self.favoriteModelIDs = favoriteModelPersistence.loadFavoriteModelIDs()
        self.performanceOptions = AppStorePerformanceOptions()
        self.isPersistenceEnabled = true
        self.lastWorkspaceSelection = initialWorkspaceSelection.content
        NeoCodeTheme.configure(with: loadedAppSettings.appearance)
        seedComposerDefaults()
        refreshSystemSleepAssertion()
    }

    init(
        projects: [ProjectSummary],
        performanceOptions: AppStorePerformanceOptions = AppStorePerformanceOptions(),
        isPersistenceEnabled: Bool = false
    ) {
        let normalizedProjects = Self.normalizedProjects(projects)
        let extractedState = Self.extractTranscriptState(from: normalizedProjects)
        let loadedAppSettings = isPersistenceEnabled ? PersistedAppSettingsStore().loadSettings() : .init()
        let restoredWorkspaceSelection = isPersistenceEnabled ? PersistedWorkspaceSelectionStore().loadSelection() : nil
        let initialWorkspaceSelection = Self.initialWorkspaceSelection(
            projects: extractedState.projects,
            startupBehavior: loadedAppSettings.general.startupBehavior,
            restoredSelection: restoredWorkspaceSelection
        )
        self.projects = extractedState.projects
        self.transcriptStateBySessionID = extractedState.transcripts
        self.selectedProjectID = initialWorkspaceSelection.projectID
        self.selectedContent = initialWorkspaceSelection.content
        self.appSettings = loadedAppSettings
        self.loadingTranscriptSessionID = nil
        self.selectedDashboardRange = .allTime
        self.yoloSessionKeys = isPersistenceEnabled && loadedAppSettings.general.remembersYoloModePerThread
            ? PersistedYoloPreferencesStore().loadYoloSessionKeys()
            : []
        self.favoriteModelIDs = isPersistenceEnabled ? favoriteModelPersistence.loadFavoriteModelIDs() : []
        self.performanceOptions = performanceOptions
        self.isPersistenceEnabled = isPersistenceEnabled
        self.lastWorkspaceSelection = initialWorkspaceSelection.content
        NeoCodeTheme.configure(with: loadedAppSettings.appearance)
        seedComposerDefaults()
        refreshSystemSleepAssertion()
    }

    var selectedSessionID: String? {
        get {
            guard case .session(let sessionID) = selectedContent else { return nil }
            return sessionID
        }
        set {
            if let newValue {
                selectedContent = .session(newValue)
                clearStatusIndicators(for: newValue)
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

    var selectedDashboardProject: ProjectSummary? {
        guard let selectedDashboardProjectID else { return nil }
        return projects.first { $0.id == selectedDashboardProjectID }
    }

    var isSettingsSelected: Bool {
        if case .settings = selectedContent {
            return true
        }
        return false
    }

    var selectedSettingsSection: AppSettingsSection? {
        guard case .settings(let section) = selectedContent else { return nil }
        return section
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
        let _ = sessionUIRevision
        guard let selectedSessionID else { return nil }
        return projects
            .flatMap(\.sessions)
            .first(where: { $0.id == selectedSessionID })
    }

    var selectedTranscript: [ChatMessage] {
        visibleTranscript(for: selectedSessionID)
    }

    var selectedQueuedMessages: [ComposerQueuedMessage] {
        queuedMessages(for: selectedSessionID)
    }

    var selectedTodos: [SessionTodoItem] {
        todos(for: selectedSessionID)
    }

    var selectedRemainingTodoCount: Int {
        remainingTodoCount(for: selectedSessionID)
    }

    func transcript(for sessionID: String?) -> [ChatMessage] {
        guard let sessionID else { return [] }
        return transcriptStateBySessionID[sessionID]?.messages ?? []
    }

    func visibleTranscript(for sessionID: String?) -> [ChatMessage] {
        guard let sessionID else { return [] }
        let transcript = transcript(for: sessionID)
        guard let revertMessageID = session(for: sessionID)?.revert?.messageID else {
            return transcript
        }

        return transcript.filter { ($0.messageID ?? $0.id) < revertMessageID }
    }

    func queuedMessages(for sessionID: String?) -> [ComposerQueuedMessage] {
        guard let sessionID else { return [] }
        return queuedMessagesBySessionID[sessionID] ?? []
    }

    func todos(for sessionID: String?) -> [SessionTodoItem] {
        guard let sessionID else { return [] }
        return activeTodosBySessionID[sessionID]?.items ?? []
    }

    func remainingTodoCount(for sessionID: String?) -> Int {
        guard let sessionID else { return 0 }
        return activeTodosBySessionID[sessionID]?.remainingCount ?? 0
    }

    func transcriptRevisionToken(for sessionID: String?) -> Int {
        guard let sessionID else { return 0 }
        return transcriptStateBySessionID[sessionID]?.revision ?? 0
    }

    func sessionStats(for sessionID: String?) -> SessionStatsSnapshot? {
        guard let sessionID else { return nil }
        return session(for: sessionID)?.stats
    }

    func sessionSummary(for sessionID: String) -> SessionSummary? {
        let _ = sessionUIRevision
        return session(for: sessionID)
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
        let _ = sessionUIRevision
        guard let selectedSessionID else { return nil }
        return effectiveLiveSessionActivity(
            for: selectedSessionID,
            transcript: transcript(for: selectedSessionID)
        )
    }

    var selectedSessionIsActivelyResponding: Bool {
        let _ = sessionUIRevision
        guard let selectedSessionID else { return false }
        return isSessionActivelyResponding(selectedSessionID)
    }

    func project(for sessionID: String) -> ProjectSummary? {
        let sessionID = resolvedSessionID(for: sessionID)
        return projects.first(where: { project in
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

    func preferredWorkspaceToolID(for projectID: ProjectSummary.ID?, availableToolIDs: [String]) -> String? {
        let availableToolIDs = Set(availableToolIDs)

        if let projectID,
           let preferredEditorID = preferredEditorID(for: projectID),
           availableToolIDs.contains(preferredEditorID) {
            return preferredEditorID
        }

        if let defaultWorkspaceToolID = appSettings.general.defaultWorkspaceToolID,
           availableToolIDs.contains(defaultWorkspaceToolID) {
            return defaultWorkspaceToolID
        }

        return nil
    }

    func setProjectCollapsed(_ isCollapsed: Bool, for projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[projectIndex].settings.isCollapsedInSidebar = isCollapsed
        scheduleProjectPersistence()
    }

    func pendingPermission(for sessionID: String) -> OpenCodePermissionRequest? {
        let _ = sessionUIRevision
        return pendingPermissionsBySession[sessionID]?.first
    }

    func pendingQuestion(for sessionID: String) -> OpenCodeQuestionRequest? {
        let _ = sessionUIRevision
        return pendingQuestionsBySession[sessionID]?.first
    }

    func showsFinishedIndicator(for sessionID: String) -> Bool {
        let _ = sessionUIRevision
        return finishedSessionIDs.contains(sessionID)
    }

    func showsFailedIndicator(for sessionID: String) -> Bool {
        let _ = sessionUIRevision
        return failedSessionIDs.contains(sessionID)
    }

    func terminationWarningContext() -> AppTerminationWarningContext? {
        let sessions = projects.flatMap { project in
            project.sessions.compactMap { session -> AppTerminationWarningContext.Session? in
                guard let reason = terminationBlockReason(for: session) else { return nil }

                return AppTerminationWarningContext.Session(
                    id: session.id,
                    projectName: project.name,
                    sessionTitle: session.title,
                    reason: reason
                )
            }
        }

        guard !sessions.isEmpty else { return nil }
        return AppTerminationWarningContext(sessions: sessions)
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

        if isPersistenceEnabled,
           appSettings.general.remembersYoloModePerThread {
            yoloPreferencePersistence.saveYoloSessionKeys(yoloSessionKeys)
        }
    }

    func updateGeneral(_ update: (inout NeoCodeGeneralSettings) -> Void) {
        let previousGeneral = appSettings.general
        var general = previousGeneral
        update(&general)
        guard general != previousGeneral else { return }

        appSettings.general = general
        handleGeneralSettingsChange(from: previousGeneral, to: general)
    }

    func preparePrompt(for sessionID: String?) async {
        guard appSettings.general.restoresPromptDrafts else {
            isPromptReady = true
            promptLoadingText = nil
            isHydratingPrompt = true
            draft = ""
            isHydratingPrompt = false
            return
        }

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
        persistComposerStateForSelectedSession()
        selectedProjectID = destinationProjectID
        restoreComposerOptionsFromCache(for: projectPath(for: destinationProjectID))
        if let selectedSessionID,
           projectID(for: selectedSessionID) != destinationProjectID {
            self.selectedSessionID = nil
            loadingTranscriptSessionID = nil
            primePromptState(for: nil)
        }

        scheduleGitRefreshLoop(for: projectPath(for: destinationProjectID))
    }

    func selectDashboard() {
        persistComposerStateForSelectedSession()
        let shouldRefreshSnapshot = selectedDashboardProjectID != nil
        selectedDashboardProjectID = nil
        selectedSessionID = nil
        loadingTranscriptSessionID = nil
        primePromptState(for: nil)
        scheduleGitRefreshLoop(for: selectedProject?.path)

        guard shouldRefreshSnapshot else { return }
        Task { [weak self] in
            guard let self else { return }
            self.dashboardSnapshot = await self.dashboardStatsService.currentSnapshot(range: self.selectedDashboardRange)
        }
    }

    func selectDashboardProject(_ destinationProjectID: ProjectSummary.ID) {
        guard let destinationProject = projects.first(where: { $0.id == destinationProjectID }) else { return }
        persistComposerStateForSelectedSession()
        selectedDashboardProjectID = destinationProjectID
        selectedContent = .dashboard
        selectedSessionID = nil
        loadingTranscriptSessionID = nil
        primePromptState(for: nil)
        scheduleGitRefreshLoop(for: destinationProject.path)

        Task { [weak self] in
            guard let self else { return }
            self.dashboardSnapshot = await self.dashboardStatsService.currentSnapshot(
                range: self.selectedDashboardRange,
                projectPath: destinationProject.path
            )
        }
    }

    func clearDashboardProjectSelection() {
        guard selectedDashboardProjectID != nil else { return }
        selectedDashboardProjectID = nil

        Task { [weak self] in
            guard let self else { return }
            self.dashboardSnapshot = await self.dashboardStatsService.currentSnapshot(range: self.selectedDashboardRange)
        }
    }

    func selectDashboardRange(_ range: DashboardTimeRange) {
        guard selectedDashboardRange != range else { return }
        selectedDashboardRange = range

        Task { [weak self] in
            guard let self else { return }
            self.dashboardSnapshot = await self.dashboardStatsService.currentSnapshot(
                range: range,
                projectPath: self.selectedDashboardProject?.path
            )
        }
    }

    func openSettings(section: AppSettingsSection = .general) {
        if !isSettingsSelected {
            lastWorkspaceSelection = selectedContent
        }

        selectedContent = .settings(section)
        suspendDashboardRefresh()
    }

    func closeSettings() {
        switch lastWorkspaceSelection {
        case .settings:
            selectedContent = .dashboard
        default:
            selectedContent = lastWorkspaceSelection
        }

        scheduleGitRefreshLoop(for: selectedProject?.path)
    }

    func selectSettingsSection(_ section: AppSettingsSection) {
        if !isSettingsSelected {
            lastWorkspaceSelection = selectedContent
        }
        selectedContent = .settings(section)
    }

    func selectSession(_ sessionID: String) {
        let sessionID = resolvedSessionID(for: sessionID)
        guard selectedSessionID != sessionID else { return }
        persistComposerStateForSelectedSession()
        let destinationProjectID = projectID(for: sessionID)
        selectedSessionID = sessionID
        selectedProjectID = destinationProjectID
        withSessionComposerStatePersistenceSuspended {
            restoreComposerOptionsFromCache(for: destinationProjectID.flatMap { projectPath(for: $0) })
        }
        restoreComposerState(for: sessionID)

        if session(for: sessionID)?.isEphemeral == true {
            loadingTranscriptSessionID = nil
        } else if let destinationProjectID,
                  hasCachedTranscript(for: sessionID, projectID: destinationProjectID) {
            loadingTranscriptSessionID = nil
        } else {
            loadingTranscriptSessionID = sessionID
        }

        primePromptState(for: sessionID)
        scheduleGitRefreshLoop(for: selectedProject?.path)
    }

    func addProject(directoryURL: URL) {
        let resolvedURL = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let projectPath = resolvedURL.path

        if let existingProject = projects.first(where: { $0.path == projectPath }) {
            selectedProjectID = existingProject.id
            selectedSessionID = existingProject.sessions.first?.id
            restoreComposerOptionsFromCache(for: existingProject.path)
            primePromptState(for: selectedSessionID)
            lastError = nil
            return
        }

        let project = ProjectSummary(name: resolvedURL.lastPathComponent, path: projectPath)
        projects.append(project)
        scheduleProjectPersistence()
        selectedProjectID = project.id
        selectedSessionID = nil
        primePromptState(for: nil)
        lastError = nil
        scheduleGitRefreshLoop(for: project.path)
    }

    func moveProject(_ projectID: ProjectSummary.ID, before destinationProjectID: ProjectSummary.ID) {
        guard projectID != destinationProjectID,
              let sourceIndex = projects.firstIndex(where: { $0.id == projectID }),
              let destinationIndex = projects.firstIndex(where: { $0.id == destinationProjectID })
        else {
            return
        }

        let insertionIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        moveProject(from: sourceIndex, to: insertionIndex)
    }

    func moveProjectToEnd(_ projectID: ProjectSummary.ID) {
        guard let sourceIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            return
        }

        moveProject(from: sourceIndex, to: projects.count - 1)
    }

    func toggleProjectCollapsed(_ projectID: ProjectSummary.ID) {
        setProjectCollapsed(!isProjectCollapsed(projectID), for: projectID)
    }

    func isProjectCollapsed(_ projectID: ProjectSummary.ID) -> Bool {
        projects.first(where: { $0.id == projectID })?.settings.isCollapsedInSidebar ?? false
    }

    func isSessionListSyncing(for projectID: ProjectSummary.ID) -> Bool {
        (sessionListSyncActivityByProjectID[projectID] ?? 0) > 0
            || (loadingSessionCountsByProjectID[projectID] ?? 0) > 0
    }

    private func moveProject(from sourceIndex: Int, to destinationIndex: Int) {
        guard projects.indices.contains(sourceIndex) else { return }

        let boundedDestination = max(0, min(destinationIndex, projects.count - 1))
        guard sourceIndex != boundedDestination else { return }

        var reorderedProjects = projects
        let project = reorderedProjects.remove(at: sourceIndex)
        let insertionIndex = max(0, min(boundedDestination, reorderedProjects.count))
        reorderedProjects.insert(project, at: insertionIndex)
        projects = reorderedProjects
        scheduleProjectPersistence()
    }

    func updateAppearance(_ update: (inout NeoCodeAppearanceSettings) -> Void) {
        var appearance = appSettings.appearance
        update(&appearance)
        appearance.syncPresetSelection()
        appSettings.appearance = appearance
    }

    private func handleGeneralSettingsChange(from oldValue: NeoCodeGeneralSettings, to newValue: NeoCodeGeneralSettings) {
        if oldValue.restoresPromptDrafts != newValue.restoresPromptDrafts {
            if newValue.restoresPromptDrafts {
                persistDraftIfNeeded()
            } else {
                promptDraftsByKey = [:]
                loadedPromptKeys = []

                if isPersistenceEnabled {
                    let promptDraftPersistence = promptDraftPersistence
                    Task {
                        await promptDraftPersistence.clearAll()
                    }
                }
            }
        }

        if oldValue.remembersYoloModePerThread != newValue.remembersYoloModePerThread,
           isPersistenceEnabled {
            if newValue.remembersYoloModePerThread {
                yoloPreferencePersistence.saveYoloSessionKeys(yoloSessionKeys)
            } else {
                yoloPreferencePersistence.saveYoloSessionKeys([])
            }
        }

        if (!oldValue.notifiesWhenResponseCompletes && newValue.notifiesWhenResponseCompletes)
            || (!oldValue.notifiesWhenInputIsRequired && newValue.notifiesWhenInputIsRequired) {
            Task { [weak self] in
                await self?.ensureNotificationAuthorization()
            }
        }

        refreshSystemSleepAssertion()
    }

    private func ensureNotificationAuthorization() async {
        guard appSettings.general.notifiesWhenResponseCompletes || appSettings.general.notifiesWhenInputIsRequired else {
            return
        }

        guard await notificationService.requestAuthorizationIfNeeded() else {
            updateGeneral { general in
                general.notifiesWhenResponseCompletes = false
                general.notifiesWhenInputIsRequired = false
            }
            lastError = "NeoCode notifications are disabled in macOS. Enable them in System Settings to use notification alerts."
            return
        }
    }

    private func refreshSystemSleepAssertion() {
        let shouldPreventSleep = appSettings.general.preventsSystemSleepWhileRunning && hasRunningSessions
        sleepAssertionService.setActive(shouldPreventSleep)
    }

    private var hasRunningSessions: Bool {
        projects.contains { project in
            project.sessions.contains { $0.status.isActive }
        }
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
        restoreComposerOptionsFromCache(for: project.path)
        await withSessionListSyncActivityIfNeeded(for: project.id) {
            _ = await connectProject(project.id, using: runtime, includeComposerOptions: true)
        }
        reevaluateRuntimeRetention(using: runtime)
    }

    func syncSelection(using runtime: OpenCodeRuntime) async {
        guard selectedSessionID != nil else {
            loadingTranscriptSessionID = nil
            await connect(to: runtime)
            return
        }

        await syncSelectedSession(using: runtime)
    }

    @discardableResult
    func createSession(using runtime: OpenCodeRuntime) async -> String? {
        guard let projectID = selectedProject?.id else { return nil }
        return await createSession(in: projectID, using: runtime)
    }

    @discardableResult
    func createSession(in projectID: ProjectSummary.ID, using runtime: OpenCodeRuntime) async -> String? {
        selectedProjectID = projectID
        let pendingSessionID = stagePendingSession(in: projectID)
        return await ensureServerSession(for: pendingSessionID, in: projectID, using: runtime)
    }

    @discardableResult
    func createSession(in projectID: ProjectSummary.ID, using service: any OpenCodeServicing) async -> String? {
        selectedProjectID = projectID
        let pendingSessionID = stagePendingSession(in: projectID)
        return await ensureServerSession(for: pendingSessionID, in: projectID, using: service)
    }

    func refreshSessions(in projectID: ProjectSummary.ID, using runtime: OpenCodeRuntime) async {
        guard projects.contains(where: { $0.id == projectID }) else { return }

        selectProject(projectID)

        await withSessionListSyncActivityIfNeeded(for: projectID) {
            guard let service = await liveService(for: projectID, runtime: runtime) else { return }

            await loadSessions(using: service, for: projectID)
            await loadSessionStatuses(using: service, for: projectID)
            await loadPendingPermissions(using: service, for: projectID)
            await loadPendingQuestions(using: service, for: projectID)
        }
        reevaluateRuntimeRetention(using: runtime)
    }

    func startDashboard(using runtime: OpenCodeRuntime) async {
        isDashboardActive = true
        dashboardSnapshot = await dashboardStatsService.prepare(
            projects: projects.map(DashboardProjectDescriptor.init(project:)),
            range: selectedDashboardRange,
            projectPath: selectedDashboardProject?.path
        )

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
                    forceSessionIDs: forcedSessions[project.id] ?? [],
                    range: selectedDashboardRange,
                    projectPath: selectedDashboardProject?.path
                )
                dashboardSnapshot = plan.snapshot
                refreshWork.append(contentsOf: plan.changedSessions.map { (project, descriptor, $0) })
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else {
                    stopDashboardOnlyRuntimes(services, runtime: runtime)
                    return
                }
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
            dashboardSnapshot = await dashboardStatsService.currentSnapshot(
                range: selectedDashboardRange,
                projectPath: selectedDashboardProject?.path
            )
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
                    guard !Task.isCancelled, !(error is CancellationError) else {
                        stopDashboardOnlyRuntimes(services, runtime: runtime)
                        return
                    }
                    logger.error("Failed to fetch dashboard messages for session \(item.session.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            if !ingestions.isEmpty {
                dashboardSnapshot = await dashboardStatsService.ingest(
                    ingestions,
                    range: selectedDashboardRange,
                    projectPath: selectedDashboardProject?.path
                )
                processedSessions += ingestions.count
            }

            await Task.yield()
        }

        dashboardSnapshot = await dashboardStatsService.currentSnapshot(
            range: selectedDashboardRange,
            projectPath: selectedDashboardProject?.path
        )
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
            guard !shouldKeepRuntimeAlive(for: projectID),
                  liveServices[projectID] == nil,
                  eventTasks[projectID] == nil
            else {
                continue
            }

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

        guard let projectID = projectID(for: selectedSessionID),
              let project = projects.first(where: { $0.id == projectID }),
              session(for: selectedSessionID)?.isEphemeral != true
        else {
            if loadingTranscriptSessionID == selectedSessionID {
                loadingTranscriptSessionID = nil
            }
            return
        }

        if !hasCachedTranscript(for: selectedSessionID, projectID: projectID) {
            loadingTranscriptSessionID = selectedSessionID
        }

        let hadLiveService = liveServices[projectID] != nil
        let previousConnectionIdentifier = serviceConnectionIdentifiers[projectID]

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

        let didRefreshDuringConnect = !hadLiveService || previousConnectionIdentifier != connectionIdentifier
        if !didRefreshDuringConnect {
            await loadMessages(for: selectedSessionID, using: service, projectID: projectID, allowCachedFallback: true)
        }
        reevaluateRuntimeRetention(using: runtime)
    }

    func renameSession(_ sessionID: String, to title: String, using runtime: OpenCodeRuntime) async {
        let sessionID = resolvedSessionID(for: sessionID)
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

    @discardableResult
    func compactSession(_ sessionID: String, using runtime: OpenCodeRuntime) async -> Bool {
        let sessionID = resolvedSessionID(for: sessionID)
        guard let projectID = projectID(for: sessionID) else { return false }
        guard let service = await liveService(for: projectID, runtime: runtime) else { return false }

        let didCompact = await compactSession(sessionID, projectID: projectID, using: service)
        reevaluateRuntimeRetention(using: runtime)
        return didCompact
    }

    func deleteSession(_ sessionID: String, using runtime: OpenCodeRuntime) async {
        let sessionID = resolvedSessionID(for: sessionID)
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

    func canCompactSession(_ sessionID: String) -> Bool {
        guard let session = sessionSummary(for: sessionID),
              session.isEphemeral == false,
              session.status != .running,
              resolvedCompactionModel(for: sessionID) != nil
        else {
            return false
        }

        return true
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
        let attachments = attachedFiles
        guard !trimmed.isEmpty || !attachments.isEmpty,
              let projectID = selectedProject?.id
        else { return }

        let localCommand = localSlashCommandInvocation(in: trimmed)
        if let localCompactCommand = localCommand,
           localCompactCommand.command == .compact {
            let handled = await executeLocalSlashCommand(localCompactCommand, in: projectID, using: runtime)
            if handled {
                logger.info(
                    "Handled local slash command project=\(projectID.uuidString, privacy: .public) command=\(localCompactCommand.command.name, privacy: .public)"
                )
            }
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        let remoteCommand = slashCommandInvocation(in: trimmed)
        if remoteCommand == nil,
           let localCommand {
            let handled = await executeLocalSlashCommand(localCommand, in: projectID, using: runtime)
            if handled {
                logger.info(
                    "Handled local slash command project=\(projectID.uuidString, privacy: .public) command=\(localCommand.command.name, privacy: .public)"
                )
            }
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        if let selectedSessionID,
           self.projectID(for: selectedSessionID) == projectID,
           session(for: selectedSessionID)?.status.isActive == true,
           enqueueDraft(in: selectedSessionID) {
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        guard let initialSessionID = selectedSessionID,
              self.projectID(for: initialSessionID) == projectID
        else {
            logger.error("Cannot send draft because no session is selected for project: \(projectID.uuidString, privacy: .public)")
            return
        }

        let queuedOptions = currentQueuedMessageOptions()
        let options = OpenCodePromptOptions(
            model: queuedOptions.model,
            agentName: queuedOptions.agentName,
            variant: queuedOptions.variant
        )
        let stagedUI = stageSendUI(
            text: trimmed,
            attachments: attachments,
            shouldShowOptimisticUserMessage: remoteCommand == nil,
            sessionID: initialSessionID,
            projectID: projectID,
            clearComposerOnSend: true
        )
        registerPendingSendUI(stagedUI, forOriginalSessionID: initialSessionID)

        guard !Task.isCancelled else {
            handleCancelledSend(
                originatingSessionID: initialSessionID,
                fallbackSessionID: initialSessionID,
                projectID: projectID,
                restoreComposerOnFailure: true
            )
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        async let resolvedFileReferences = resolveSendFileReferences(for: trimmed, projectID: projectID)

        guard let service = await liveService(for: projectID, runtime: runtime) else {
            logger.error("Cannot send draft because live service is unavailable for project: \(projectID.uuidString, privacy: .public)")
            revertFailedSend(
                stagedUI,
                sessionID: initialSessionID,
                projectID: projectID,
                restoreComposerOnFailure: true
            )
            isSending = false
            if lastError == nil {
                lastError = runtime.detailLabel(for: projectPath(for: projectID))
            }
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        guard !Task.isCancelled else {
            handleCancelledSend(
                originatingSessionID: initialSessionID,
                fallbackSessionID: initialSessionID,
                projectID: projectID,
                restoreComposerOnFailure: true
            )
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        guard let sessionID = await resolveSessionForSend(projectID: projectID, service: service) else {
            revertFailedSend(
                stagedUI,
                sessionID: initialSessionID,
                projectID: projectID,
                restoreComposerOnFailure: true
            )
            isSending = false
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        registerPendingSendActiveSessionID(sessionID, forOriginalSessionID: initialSessionID)

        guard !Task.isCancelled else {
            handleCancelledSend(
                originatingSessionID: initialSessionID,
                fallbackSessionID: sessionID,
                projectID: projectID,
                restoreComposerOnFailure: true
            )
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        let fileReferences = await resolvedFileReferences

        guard !Task.isCancelled else {
            handleCancelledSend(
                originatingSessionID: initialSessionID,
                fallbackSessionID: sessionID,
                projectID: projectID,
                restoreComposerOnFailure: true
            )
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        let accepted = await sendDraft(
            using: service,
            projectID: projectID,
            sessionID: sessionID,
            originatingSessionID: initialSessionID,
            fileReferences: fileReferences,
            stagedUI: stagedUI,
            text: trimmed,
            attachments: attachments,
            options: options,
            clearComposerOnSend: false,
            restoreComposerOnFailure: true
        )
        if accepted {
            scheduleStreamingRecoveryCheck(for: sessionID, projectID: projectID, using: runtime)
        }

        reevaluateRuntimeRetention(using: runtime)
    }

    func beginSendDraft(using runtime: OpenCodeRuntime) {
        guard let projectID = selectedProject?.id,
              let sessionID = selectedSessionID,
              self.projectID(for: sessionID) == projectID
        else {
            Task { [weak self] in
                await self?.sendDraft(using: runtime)
            }
            return
        }

        let token = UUID()
        var task: Task<Void, Never>!
        task = Task { [weak self] in
            guard let self else { return }
            await self.sendDraft(using: runtime)
            self.finishPendingSendTracking(forOriginalSessionID: sessionID, token: token)
        }

        pendingSendStatesByOriginalSessionID[sessionID] = PendingSendState(
            token: token,
            projectID: projectID,
            originalSessionID: sessionID,
            task: task,
            activeSessionID: sessionID,
            stagedUI: nil
        )
    }

    @discardableResult
    func sendDraft(
        using service: any OpenCodeServicing,
        projectID: ProjectSummary.ID,
        sessionID: String,
        originatingSessionID: String? = nil,
        fileReferences: [ComposerPromptFileReference] = [],
        allowQueueIfRunning: Bool = false,
        stagedUI: StagedSendUI? = nil,
        text: String? = nil,
        attachments: [ComposerAttachment]? = nil,
        options: OpenCodePromptOptions? = nil,
        clearComposerOnSend: Bool = true,
        restoreComposerOnFailure: Bool = true
    ) async -> Bool {
        let trimmed = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = attachments ?? attachedFiles
        guard !trimmed.isEmpty || !attachments.isEmpty else { return false }

        if allowQueueIfRunning,
           session(for: sessionID)?.status.isActive == true {
            return enqueueDraft(in: sessionID)
        }

        let resolvedOptions: OpenCodePromptOptions
        if let options {
            resolvedOptions = options
        } else {
            let queuedOptions = currentQueuedMessageOptions()
            resolvedOptions = OpenCodePromptOptions(
                model: queuedOptions.model,
                agentName: queuedOptions.agentName,
                variant: queuedOptions.variant
            )
        }
        return await sendMessage(
            text: trimmed,
            attachments: attachments,
            fileReferences: fileReferences,
            options: resolvedOptions,
            using: service,
            projectID: projectID,
            sessionID: sessionID,
            originatingSessionID: originatingSessionID,
            clearComposerOnSend: clearComposerOnSend,
            restoreComposerOnFailure: restoreComposerOnFailure,
            stagedUI: stagedUI
        )
    }

    @discardableResult
    private func sendMessage(
        text: String,
        attachments: [ComposerAttachment],
        fileReferences: [ComposerPromptFileReference],
        options: OpenCodePromptOptions,
        using service: any OpenCodeServicing,
        projectID: ProjectSummary.ID,
        sessionID: String,
        originatingSessionID: String? = nil,
        clearComposerOnSend: Bool,
        restoreComposerOnFailure: Bool,
        stagedUI: StagedSendUI? = nil
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return false }

        let slashCommand = slashCommandInvocation(in: trimmed)
        let shouldShowOptimisticUserMessage = slashCommand == nil
        if let slashCommand {
            logger.info(
                "Sending slash command session=\(sessionID, privacy: .public) command=\(slashCommand.command.name, privacy: .public) argumentLength=\(slashCommand.arguments.count, privacy: .public) project=\(projectID.uuidString, privacy: .public)"
            )
        } else {
            logger.info(
                "Sending draft session=\(sessionID, privacy: .public) characters=\(trimmed.count, privacy: .public) project=\(projectID.uuidString, privacy: .public)"
            )
        }

        let stagedUI = stagedUI ?? stageSendUI(
            text: trimmed,
            attachments: attachments,
            shouldShowOptimisticUserMessage: shouldShowOptimisticUserMessage,
            sessionID: sessionID,
            projectID: projectID,
            clearComposerOnSend: clearComposerOnSend
        )

        do {
            if let slashCommand {
                try await service.sendCommand(
                    sessionID: sessionID,
                    command: slashCommand.command.name,
                    arguments: slashCommand.arguments,
                    attachments: attachments,
                    fileReferences: fileReferences,
                    options: options
                )
                logger.info(
                    "Slash command accepted for session \(sessionID, privacy: .public): \(slashCommand.command.name, privacy: .public)"
                )
            } else {
                try await service.sendPromptAsync(
                    sessionID: sessionID,
                    text: trimmed,
                    attachments: attachments,
                    fileReferences: fileReferences,
                    options: options
                )
                logger.info("Draft accepted for session: \(sessionID, privacy: .public)")
            }
        } catch {
            logger.error("Failed to send draft for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            revertFailedSend(
                stagedUI,
                sessionID: sessionID,
                projectID: projectID,
                restoreComposerOnFailure: restoreComposerOnFailure
            )
            lastError = error.localizedDescription
            isSending = false
            return false
        }

        if let originatingSessionID {
            pendingSendStatesByOriginalSessionID[originatingSessionID]?.didAcceptRemoteSend = true
        }
        markSidebarActivity(sessionID: sessionID, projectID: projectID)
        scheduleProjectPersistence()
        isSending = false
        return true
    }

    @discardableResult
    func revertPreview(for messageID: String, in sessionID: String) -> SessionRevertPreview? {
        let currentTranscript = transcript(for: sessionID)
        guard let messageIndex = currentTranscript.firstIndex(where: { $0.id == messageID }),
              currentTranscript[messageIndex].role == .user
        else {
            return nil
        }

        let targetMessage = currentTranscript[messageIndex]
        let upstreamMessageID = targetMessage.messageID ?? targetMessage.id
        let affectedPromptIDs = affectedPromptMessageIDs(from: messageIndex, in: currentTranscript)
        let messageInfos = messageInfosBySessionID[sessionID] ?? [:]
        let changedFiles = aggregatedRevertFileChanges(for: affectedPromptIDs, messageInfos: messageInfos)
        let restoredAttachments = currentTranscript
            .filter { ($0.messageID ?? $0.id) == upstreamMessageID }
            .compactMap(\.attachment)
            .compactMap(\.composerAttachment)

        return SessionRevertPreview(
            targetPartID: targetMessage.id,
            upstreamMessageID: upstreamMessageID,
            restoredText: targetMessage.text,
            restoredAttachments: restoredAttachments,
            affectedPromptCount: affectedPromptIDs.count,
            changedFiles: changedFiles
        )
    }

    @discardableResult
    func revertMessage(messageID: String, in sessionID: String, using runtime: OpenCodeRuntime) async -> Bool {
        guard let projectID = projectID(for: sessionID) else {
            return false
        }

        guard session(for: sessionID)?.status != .running else {
            lastError = "Wait for the current response to finish before reverting history."
            return false
        }

        guard let service = await liveService(for: projectID, runtime: runtime) else {
            logger.error("Cannot revert message because live service is unavailable for project: \(projectID.uuidString, privacy: .public)")
            return false
        }

        return await revertMessage(messageID: messageID, in: sessionID, projectID: projectID, using: service)
    }

    @discardableResult
    func revertMessage(
        messageID: String,
        in sessionID: String,
        projectID: ProjectSummary.ID,
        using service: any OpenCodeServicing
    ) async -> Bool {
        let currentTranscript = transcript(for: sessionID)
        guard let preview = revertPreview(for: messageID, in: sessionID),
              let session = sessionSummary(for: sessionID, projectID: projectID)
        else {
            return false
        }

        let originalDraft = draft
        let originalAttachments = attachedFiles
        let originalQueue = queuedMessagesBySessionID[sessionID]
        let firstAffectedIndex = currentTranscript.firstIndex(where: { ($0.messageID ?? $0.id) == preview.upstreamMessageID }) ?? currentTranscript.endIndex
        let truncatedTranscript = Array(currentTranscript.prefix(upTo: firstAffectedIndex))
        let allowedMessageIDs = Set(truncatedTranscript.compactMap { $0.messageID ?? $0.id })

        do {
            logger.info(
                "Reverting message session=\(sessionID, privacy: .public) message=\(preview.upstreamMessageID, privacy: .public)"
            )
            let revertedSession = try await service.revertSession(
                sessionID: sessionID,
                messageID: preview.upstreamMessageID,
                partID: nil
            )

            replaceTranscript(in: sessionID, projectID: projectID, with: truncatedTranscript)
            pruneMessageMetadata(in: sessionID, keeping: allowedMessageIDs)

            if (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedFiles.isEmpty) {
                _ = enqueueDraft(in: sessionID)
            }

            draft = preview.restoredText
            attachedFiles = preview.restoredAttachments
            upsert(session: SessionSummary(session: revertedSession, fallbackTitle: session.title), in: projectID, preferTopInsertion: false)
            refreshSessionStats(sessionID: sessionID, projectID: projectID)
            lastError = nil
            return true
        } catch {
            draft = originalDraft
            attachedFiles = originalAttachments
            queuedMessagesBySessionID[sessionID] = originalQueue
            logger.error(
                "Failed to revert message for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            lastError = error.localizedDescription
            return false
        }
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
        let originalSidebarActivityAt = session.lastSidebarActivityAt
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
            markSidebarActivity(sessionID: sessionID, projectID: projectID, at: now)
            setSessionStatus(.running, sessionID: sessionID, projectID: projectID)

            try await service.sendPromptAsync(
                sessionID: sessionID,
                text: trimmed,
                attachments: [],
                fileReferences: [],
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
            markSidebarActivity(sessionID: sessionID, projectID: projectID, at: originalSidebarActivityAt ?? originalUpdatedAt)
            if originalSidebarActivityAt == nil,
               let indices = indices(for: sessionID, projectID: projectID) {
                projects[indices.project].sessions[indices.session].lastSidebarActivityAt = nil
            }
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
            cancelStreamingRecoveryCheck(for: sessionID)
            lastError = error.localizedDescription
            isSending = false
            return false
        }
    }

    func stopSelectedSession(using runtime: OpenCodeRuntime) async {
        guard let sessionID = selectedSessionID,
              let projectID = projectID(for: sessionID)
        else { return }

        guard let service = await liveService(for: projectID, runtime: runtime) else {
            logger.error("Cannot stop session because live service is unavailable for project: \(projectID.uuidString, privacy: .public)")
            return
        }

        _ = await stopSession(sessionID: sessionID, projectID: projectID, using: service)
        reevaluateRuntimeRetention(using: runtime)
    }

    @discardableResult
    func stopSession(
        sessionID: String,
        projectID: ProjectSummary.ID,
        using service: any OpenCodeServicing
    ) async -> Bool {
        guard isSessionActivelyResponding(sessionID) else { return false }

        do {
            logger.info("Aborting session: \(sessionID, privacy: .public)")
            cancelStreamingRecoveryCheck(for: sessionID)
            flushBufferedTextDeltas(for: sessionID, projectID: projectID)
            try await service.abortSession(sessionID: sessionID)
            liveSessionStatuses[sessionID] = .idle
            settleSessionActivity(sessionID: sessionID, projectID: projectID)
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
            lastError = nil
            return true
        } catch {
            logger.error("Failed to abort session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            return false
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

    func editQueuedMessage(id: ComposerQueuedMessage.ID, in sessionID: String? = nil) {
        let targetSessionID = sessionID ?? selectedSessionID
        guard let targetSessionID,
              var queue = queuedMessagesBySessionID[targetSessionID],
              let queuedIndex = queue.firstIndex(where: { $0.id == id })
        else {
            return
        }

        let queuedMessage = queue.remove(at: queuedIndex)
        let draftText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftAttachments = attachedFiles
        if !draftText.isEmpty || !draftAttachments.isEmpty {
            queue.insert(
                ComposerQueuedMessage(
                    text: draftText,
                    attachments: draftAttachments,
                    options: currentQueuedMessageOptions()
                ),
                at: queuedIndex
            )
        }

        if queue.isEmpty {
            queuedMessagesBySessionID.removeValue(forKey: targetSessionID)
        } else {
            queuedMessagesBySessionID[targetSessionID] = queue
        }

        draft = queuedMessage.text
        attachedFiles = queuedMessage.attachments
        applyQueuedMessageOptions(queuedMessage.options)
    }

    func updateQueuedMessageDeliveryMode(
        id: ComposerQueuedMessage.ID,
        to deliveryMode: ComposerQueuedMessage.DeliveryMode,
        in sessionID: String? = nil
    ) {
        let targetSessionID = sessionID ?? selectedSessionID
        guard let targetSessionID,
              var queue = queuedMessagesBySessionID[targetSessionID],
              let queuedIndex = queue.firstIndex(where: { $0.id == id })
        else {
            return
        }

        queue[queuedIndex].deliveryMode = deliveryMode
        queuedMessagesBySessionID[targetSessionID] = queue
    }

    func removeQueuedMessage(id: ComposerQueuedMessage.ID, in sessionID: String? = nil) {
        let targetSessionID = sessionID ?? selectedSessionID
        guard let targetSessionID,
              var queue = queuedMessagesBySessionID[targetSessionID]
        else {
            return
        }

        queue.removeAll(where: { $0.id == id })
        if queue.isEmpty {
            queuedMessagesBySessionID.removeValue(forKey: targetSessionID)
        } else {
            queuedMessagesBySessionID[targetSessionID] = queue
        }
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
        scheduleGitFallbackRefresh(for: projectPath)
        scheduleGitRefresh(reason: "project-selected", projectPath: projectPath, refreshCommitPreviewIfLoaded: false, delay: .milliseconds(0))
    }

    private func cancelGitRefreshLoop() {
        gitRefreshTask?.cancel()
        gitRefreshTask = nil
        gitRefreshDebounceTask?.cancel()
        gitRefreshDebounceTask = nil
    }

    func handleApplicationDidBecomeActive() {
        lifecycleRefreshToken &+= 1

        guard let projectPath = selectedProject?.path else { return }
        scheduleGitRefresh(
            reason: "application-active",
            projectPath: projectPath,
            refreshCommitPreviewIfLoaded: gitCommitPreview != nil,
            delay: .milliseconds(100)
        )
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
        while isRefreshingGitCommitPreview {
            guard !Task.isCancelled else { return }
            await Task.yield()
        }

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
            let preview = try await loadGitCommitPreview(in: projectPath)
            guard !Task.isCancelled else { return }
            guard selectedProject?.path == projectPath || projectPathOverride != nil else { return }
            gitCommitPreview = preview
            cacheCurrentGitState(for: projectPath)
        } catch is CancellationError {
            logger.debug("Cancelled git commit preview refresh for path=\(projectPath, privacy: .public)")
            return
        } catch {
            guard !Task.isCancelled else { return }
            guard selectedProject?.path == projectPath || projectPathOverride != nil else { return }
            logger.warning(
                "Git commit preview refresh failed path=\(projectPath, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func loadGitCommitPreview(in projectPath: String) async throws -> GitCommitPreview {
        let repositoryService = GitRepositoryService()

        for (attempt, delay) in gitCommitPreviewRetryDelays.enumerated() {
            do {
                return try await repositoryService.commitPreview(in: projectPath)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.debug(
                    "Retrying git commit preview path=\(projectPath, privacy: .public) attempt=\(attempt + 1, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                try await Task.sleep(for: delay)
            }
        }

        return try await repositoryService.commitPreview(in: projectPath)
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
        case .sessionCompacted(let sessionID):
            if let service = liveServices[projectID] {
                Task { [weak self] in
                    await self?.loadMessages(for: sessionID, using: service, projectID: projectID, allowCachedFallback: true)
                }
            }
        case .sessionStatusChanged(let sessionID, let status):
            let previousStatus = liveSessionStatuses[sessionID]
            liveSessionStatuses[sessionID] = status
            if case .idle = status {
                settleSessionActivity(sessionID: sessionID, projectID: projectID)
            }
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
            notifyIfNeededForCompletedResponse(sessionID: sessionID, previousStatus: previousStatus, status: status)
        case .permissionAsked(let request):
            if let service = liveServices[projectID],
               shouldAutoRespond(to: request) {
                Task { [weak self] in
                    await self?.autoRespondToPermission(request, projectID: projectID, service: service)
                }
            } else {
                upsertPendingPermission(request, in: projectID)
                notifyIfNeededForPermissionRequest(request)
            }
        case .permissionReplied(let event):
            removePendingPermission(requestID: event.requestID, sessionID: event.sessionID, projectID: projectID)
        case .questionAsked(let request):
            upsertPendingQuestion(request, in: projectID)
            notifyIfNeededForQuestionRequest(request)
        case .questionReplied(let event):
            removePendingQuestion(requestID: event.requestID, sessionID: event.sessionID, projectID: projectID)
        case .questionRejected(let event):
            removePendingQuestion(requestID: event.requestID, sessionID: event.sessionID, projectID: projectID)
        case .messageUpdated(let info):
            messageRoles[info.id] = info.chatRole
            if let sessionID = info.sessionID {
                var infos = messageInfosBySessionID[sessionID] ?? [:]
                infos[info.id] = info
                messageInfosBySessionID[sessionID] = infos
                reconcileCompletedMessageIfNeeded(info, sessionID: sessionID, projectID: projectID)
                refreshSessionStats(sessionID: sessionID, projectID: projectID)
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

        if includeComposerOptions,
           shouldReloadComposerOptions(for: project.path) {
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

    private func shouldReloadComposerOptions(for projectPath: String) -> Bool {
        composerOptionsProjectPath != projectPath
            || availableModels.isEmpty
            || availableAgents.isEmpty
            || availableCommands.isEmpty
    }

    private func restoreComposerOptionsFromCache(for projectPath: String?) {
        guard let projectPath else { return }

        availableModels = cachedModelsByProjectPath[projectPath] ?? availableModels
        availableCommands = cachedCommandsByProjectPath[projectPath] ?? []
        reconcileSelectedModel(using: availableModels)
        refreshThinkingLevels()
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
        messageRoles = [:]
        liveSessionStatuses = [:]
        locallyActiveSessionIDs = []
        pendingPermissionsBySession = [:]
        pendingQuestionsBySession = [:]
        activeTodosBySessionID = [:]
        sessionListSyncActivityByProjectID = [:]
        loadingSessionCountsByProjectID = [:]
        isSending = false
        isRespondingToPrompt = false
        isPromptReady = true
        promptLoadingText = nil
        refreshSystemSleepAssertion()
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
        sessionListSyncActivityByProjectID.removeValue(forKey: projectID)
        loadingSessionCountsByProjectID.removeValue(forKey: projectID)

        let sessionIDs = projectSessionIDs(for: projectID)
        for sessionID in sessionIDs {
            cancelStreamingRecoveryCheck(for: sessionID)
            liveSessionStatuses.removeValue(forKey: sessionID)
            clearLocalSessionActivity(sessionID)
            pendingPermissionsBySession.removeValue(forKey: sessionID)
            pendingQuestionsBySession.removeValue(forKey: sessionID)
            activeTodosBySessionID.removeValue(forKey: sessionID)
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
        }

        if composerOptionsProjectPath == projectPath(for: projectID) {
            composerOptionsProjectPath = nil
            if let selectedProjectPath = selectedProject?.path {
                availableCommands = cachedCommandsByProjectPath[selectedProjectPath] ?? []
            }
        }
    }

    private func loadComposerOptions(using service: any OpenCodeServicing, projectPath: String) async {
        async let providersTask = Self.captureResult { try await service.listProviders() }
        async let agentsTask = Self.captureResult { try await service.listAgents() }
        async let commandsTask = Self.captureResult { try await service.listCommands() }

        let providersResult = await providersTask
        let agentsResult = await agentsTask
        let commandsResult = await commandsTask

        guard !Task.isCancelled,
              !providersResult.isCancelled,
              !agentsResult.isCancelled,
              !commandsResult.isCancelled
        else {
            logger.debug("Cancelled composer options load for project: \(projectPath, privacy: .public)")
            return
        }

        switch providersResult {
        case .success(let providersResponse):
            let models = providersResponse.providers
                .flatMap { provider in
                    provider.models.values.map {
                        ComposerModelOption(
                            id: "\(provider.id)/\($0.id)",
                            providerID: provider.id,
                            modelID: $0.id,
                            title: $0.name,
                            contextWindow: $0.limit?.context,
                            variants: ($0.variants?.keys.sorted()) ?? []
                        )
                    }
                }
                .sorted { $0.title < $1.title }

            cachedModelsByProjectPath[projectPath] = models
            availableModels = models
            reconcileSelectedModel(using: models)
            if preferredFallbackModelID == nil,
               let selectedModelID,
               models.contains(where: { $0.id == selectedModelID }) {
                preferredFallbackModelID = selectedModelID
            }
            if let projectID = projects.first(where: { $0.path == projectPath })?.id {
                for sessionID in projectSessionIDs(for: projectID) {
                    refreshSessionStats(sessionID: sessionID, projectID: projectID)
                }
            }
        case .failure(let message):
            logger.error("Failed to load composer models: \(message, privacy: .public)")
            availableModels = cachedModelsByProjectPath[projectPath] ?? []
            reconcileSelectedModel(using: availableModels)
        case .cancelled:
            return
        }

        switch agentsResult {
        case .success(let agents):
            let filteredAgents = agents
                .filter { !($0.hidden ?? false) }
                .filter { ($0.mode ?? "primary") != "subagent" }
            availableAgentObjects = filteredAgents
            availableAgents = filteredAgents
                .map(\.name)
                .sorted { displayAgentName($0) < displayAgentName($1) }
            if !availableAgents.contains(selectedAgent) {
                let firstAgent = availableAgents.first ?? ""
                selectAgent(firstAgent)
            }
        case .failure(let message):
            logger.error("Failed to load composer agents: \(message, privacy: .public)")
            availableAgentObjects = []
            availableAgents = []
            selectedAgent = ""
        case .cancelled:
            return
        }

        switch commandsResult {
        case .success(let commands):
            let sortedCommands = commands.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            cachedCommandsByProjectPath[projectPath] = sortedCommands
            availableCommands = sortedCommands
        case .failure(let message):
            logger.error("Failed to load composer commands: \(message, privacy: .public)")
            availableCommands = cachedCommandsByProjectPath[projectPath] ?? []
        case .cancelled:
            return
        }

        logger.info(
            "Loaded composer options project=\(projectPath, privacy: .public) models=\(self.availableModels.count, privacy: .public) agents=\(self.availableAgents.count, privacy: .public) commands=\(self.availableCommands.count, privacy: .public)"
        )

        refreshThinkingLevels()
        persistComposerStateForSelectedSession()
        composerOptionsProjectPath = projectPath
    }

    enum ComposerOptionsLoadResult<T: Sendable>: Sendable {
        case success(T)
        case failure(String)
        case cancelled

        var isCancelled: Bool {
            if case .cancelled = self {
                return true
            }
            return false
        }
    }

    static func captureResult<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async -> ComposerOptionsLoadResult<T> {
        do {
            return .success(try await operation())
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(error.localizedDescription)
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

        if let selectedModelID,
           let selectedThinkingLevel,
           !selectedThinkingLevel.isEmpty {
            lastThinkingLevelByModelID[selectedModelID] = selectedThinkingLevel
        }

        availableThinkingLevels = variants
        if variants.isEmpty {
            persistComposerStateForSelectedSession()
            return
        }

        if let selectedModelID,
           let rememberedLevel = lastThinkingLevelByModelID[selectedModelID],
           variants.contains(rememberedLevel) {
            selectedThinkingLevel = rememberedLevel
        } else if selectedThinkingLevel == nil || !variants.contains(selectedThinkingLevel ?? "") {
            selectedThinkingLevel = variants.first
        }

        persistComposerStateForSelectedSession()
    }

    var selectedModel: ComposerModelOption? {
        availableModels.first(where: { $0.id == selectedModelID })
    }

    private func currentQueuedMessageOptions() -> ComposerQueuedMessage.OptionsSnapshot {
        ComposerQueuedMessage.OptionsSnapshot(
            model: selectedModel,
            agentName: selectedAgent.isEmpty ? nil : selectedAgent,
            variant: selectedThinkingLevel
        )
    }

    private func applyQueuedMessageOptions(_ options: ComposerQueuedMessage.OptionsSnapshot) {
        selectedModelID = options.model?.id
        refreshThinkingLevels()
        selectedAgent = options.agentName ?? ""
        if let variant = options.variant,
           availableThinkingLevels.contains(variant) {
            selectedThinkingLevel = variant
        } else if availableThinkingLevels.isEmpty {
            selectedThinkingLevel = nil
        }
        persistComposerStateForSelectedSession()
    }

    private var currentSessionComposerState: SessionComposerState {
        SessionComposerState(
            selectedModelID: selectedModelID,
            selectedModelVariant: selectedModelVariant,
            selectedAgent: selectedAgent.isEmpty ? nil : selectedAgent,
            selectedThinkingLevel: selectedThinkingLevel,
            ephemeralAgentModels: ephemeralAgentModels,
            preferredFallbackModelID: preferredFallbackModelID
        )
    }

    private func persistComposerStateForSelectedSession() {
        persistComposerState(for: selectedSessionID)
    }

    private func withSessionComposerStatePersistenceSuspended<T>(_ operation: () -> T) -> T {
        let wasApplyingSessionComposerState = isApplyingSessionComposerState
        isApplyingSessionComposerState = true
        defer { isApplyingSessionComposerState = wasApplyingSessionComposerState }
        return operation()
    }

    private func persistComposerState(for sessionID: String?) {
        guard !isApplyingSessionComposerState,
              let sessionID,
              let projectID = projectID(for: sessionID),
              let indices = indices(for: sessionID, projectID: projectID)
        else {
            return
        }

        let state = currentSessionComposerState
        guard projects[indices.project].sessions[indices.session].composerState != state else { return }
        projects[indices.project].sessions[indices.session].composerState = state
        scheduleProjectPersistence()
    }

    private func restoreComposerState(for sessionID: String) {
        if let state = session(for: sessionID)?.composerState {
            applyComposerState(state)
        } else {
            resetComposerStateToDefaults()
        }

        persistComposerState(for: sessionID)
    }

    private func applyComposerState(_ state: SessionComposerState) {
        isApplyingSessionComposerState = true
        defer { isApplyingSessionComposerState = false }

        selectedModelID = state.selectedModelID
        selectedModelVariant = state.selectedModelVariant
        selectedAgent = state.selectedAgent ?? ""
        selectedThinkingLevel = state.selectedThinkingLevel
        ephemeralAgentModels = state.ephemeralAgentModels
        preferredFallbackModelID = state.preferredFallbackModelID
        reconcileSelectedModel(using: availableModels)
        refreshThinkingLevels()
    }

    private func resetComposerStateToDefaults() {
        isApplyingSessionComposerState = true
        defer { isApplyingSessionComposerState = false }

        selectedModelID = availableModels.first?.id
        selectedModelVariant = nil
        selectedAgent = availableAgents.first ?? ""
        selectedThinkingLevel = nil
        ephemeralAgentModels = [:]
        preferredFallbackModelID = selectedModelID
        refreshThinkingLevels()
    }

    @discardableResult
    private func enqueueDraft(in sessionID: String) -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = attachedFiles
        guard !trimmed.isEmpty || !attachments.isEmpty else { return false }

        var queue = queuedMessagesBySessionID[sessionID] ?? []
        queue.append(
            ComposerQueuedMessage(
                text: trimmed,
                attachments: attachments,
                options: currentQueuedMessageOptions()
            )
        )
        queuedMessagesBySessionID[sessionID] = queue
        draft = ""
        attachedFiles = []
        lastError = nil
        return true
    }

    private func popFirstQueuedMessage(in sessionID: String) -> ComposerQueuedMessage? {
        guard var queue = queuedMessagesBySessionID[sessionID], !queue.isEmpty else { return nil }
        let message = queue.removeFirst()
        if queue.isEmpty {
            queuedMessagesBySessionID.removeValue(forKey: sessionID)
        } else {
            queuedMessagesBySessionID[sessionID] = queue
        }
        return message
    }

    private func prependQueuedMessage(_ message: ComposerQueuedMessage, in sessionID: String) {
        var queue = queuedMessagesBySessionID[sessionID] ?? []
        queue.insert(message, at: 0)
        queuedMessagesBySessionID[sessionID] = queue
    }

    private func insertQueuedMessage(_ message: ComposerQueuedMessage, at index: Int, in sessionID: String) {
        var queue = queuedMessagesBySessionID[sessionID] ?? []
        let safeIndex = min(max(index, 0), queue.count)
        queue.insert(message, at: safeIndex)
        queuedMessagesBySessionID[sessionID] = queue
    }

    private func removeQueuedMessage(id: ComposerQueuedMessage.ID, in sessionID: String) -> (message: ComposerQueuedMessage, index: Int)? {
        guard var queue = queuedMessagesBySessionID[sessionID],
              let index = queue.firstIndex(where: { $0.id == id })
        else {
            return nil
        }

        let message = queue.remove(at: index)
        if queue.isEmpty {
            queuedMessagesBySessionID.removeValue(forKey: sessionID)
        } else {
            queuedMessagesBySessionID[sessionID] = queue
        }
        return (message, index)
    }

    func displayAgentName(_ rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    /// Selects an agent and switches to the appropriate model based on priority:
    /// 1. Last model used with this agent
    /// 2. Agent's configured default model
    /// 3. Preferred global fallback model
    /// 4. First available model
    func selectAgent(_ agentName: String) {
        defer { persistComposerStateForSelectedSession() }

        if !selectedAgent.isEmpty,
           selectedAgent != agentName,
           let selectedModelID,
           availableModels.contains(where: { $0.id == selectedModelID }) {
            ephemeralAgentModels[selectedAgent] = selectedModelID
        }

        selectedAgent = agentName

        guard let agent = availableAgentObjects.first(where: { $0.name == agentName }) else { return }

        // Priority 1: Check ephemeral storage for last model used with this agent
        if let ephemeralModelID = ephemeralAgentModels[agentName],
           availableModels.contains(where: { $0.id == ephemeralModelID }) {
            selectedModelID = ephemeralModelID
            selectedModelVariant = nil
            logger.info("Switched to ephemeral model for agent \(agentName): \(ephemeralModelID)")
            return
        }

        // Priority 2: Use agent's configured default model
        if let agentModel = agent.model {
            let modelOptionID = "\(agentModel.providerID)/\(agentModel.modelID)"
            if availableModels.contains(where: { $0.id == modelOptionID }) {
                selectedModelID = modelOptionID
                selectedModelVariant = nil
                logger.info("Switched to agent \(agentName)'s configured model: \(modelOptionID)")
                return
            } else {
                logger.warning("Agent \(agentName)'s configured model \(modelOptionID) is not available")
            }
        }

        // Priority 3: Use the preferred global fallback model
        if let preferredFallbackModelID,
           availableModels.contains(where: { $0.id == preferredFallbackModelID }) {
            selectedModelID = preferredFallbackModelID
            selectedModelVariant = nil
            logger.debug("Switched to fallback model for agent \(agentName): \(preferredFallbackModelID)")
            return
        }

        // Priority 4: Fall back to first available model
        if let firstModel = availableModels.first {
            selectedModelID = firstModel.id
            selectedModelVariant = nil
            logger.info("Fell back to first available model for agent \(agentName): \(firstModel.id)")
        }
    }

    /// Sets the model for the current agent and stores it for future agent switches.
    func setModelForCurrentAgent(_ modelID: String) {
        selectedModelID = modelID
        selectedModelVariant = nil
        preferredFallbackModelID = modelID

        if !self.selectedAgent.isEmpty {
            self.ephemeralAgentModels[self.selectedAgent] = modelID
            logger.info("Stored ephemeral model for agent \(self.selectedAgent): \(modelID)")
        }

        persistComposerStateForSelectedSession()
    }

    func reconcileSelectedModel(using models: [ComposerModelOption]) {
        if let selectedModelID,
           models.contains(where: { $0.id == selectedModelID }) {
            return
        }

        if !selectedAgent.isEmpty,
           let ephemeralModelID = ephemeralAgentModels[selectedAgent],
           models.contains(where: { $0.id == ephemeralModelID }) {
            selectedModelID = ephemeralModelID
            selectedModelVariant = nil
            return
        }

        if let preferredFallbackModelID,
           models.contains(where: { $0.id == preferredFallbackModelID }) {
            selectedModelID = preferredFallbackModelID
            selectedModelVariant = nil
            return
        }

        selectedModelID = models.first?.id
        if selectedModelID == nil {
            selectedModelVariant = nil
        }
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
            _ = await createSession(in: projectID, using: runtime)
            draft = invocation.arguments
            return true

        case .compact:
            guard let sessionID = selectedSession?.id,
                  self.projectID(for: sessionID) == projectID
            else {
                lastError = "Select a session before compacting it."
                return false
            }
            guard let service = await connectProject(
                projectID,
                using: runtime,
                includeComposerOptions: selectedProjectID == projectID
            ) else {
                return false
            }
            return await compactSession(sessionID, projectID: projectID, using: service)

        case .model:
            guard let query = invocation.arguments.nonEmptyTrimmed else {
                lastError = "Usage: /model <name>"
                return false
            }
            guard let match = bestMatchingModel(for: query) else {
                lastError = "No model matches '\(query)'."
                return false
            }
            setModelForCurrentAgent(match.id)
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
            selectAgent(match)
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
            persistComposerStateForSelectedSession()
            draft = ""
            return true

        case .workspace:
            guard let project = projects.first(where: { $0.id == projectID }) else {
                lastError = "Select a project before opening a workspace."
                return false
            }
            let service = WorkspaceToolService()
            let tools = service.projectOpenTools()
            guard !tools.isEmpty else {
                lastError = "No supported workspace tools were found."
                return false
            }
            let preferredID = preferredEditorID(for: projectID)
            let tool = tools.first(where: { $0.id == preferredID })
                ?? service.defaultProjectOpenTool(from: tools)
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

    @discardableResult
    func compactSession(
        _ sessionID: String,
        projectID: ProjectSummary.ID,
        using service: any OpenCodeServicing
    ) async -> Bool {
        guard let session = sessionSummary(for: sessionID, projectID: projectID) else {
            return false
        }

        guard let model = resolvedCompactionModel(for: sessionID) else {
            lastError = "Connect a provider to summarize this session."
            return false
        }

        guard !session.isEphemeral else {
            lastError = "Send at least one message before compacting this session."
            return false
        }

        guard session.status != .running else {
            lastError = "Wait for the current response to finish before compacting the session."
            return false
        }

        isSending = true
        lastError = nil
        setSessionStatus(.running, sessionID: sessionID, projectID: projectID)

        do {
            try await service.summarizeSession(
                sessionID: sessionID,
                providerID: model.providerID,
                modelID: model.modelID,
                auto: false
            )

            draft = ""
            clearLocalSessionActivity(sessionID)
            liveSessionStatuses[sessionID] = .idle
            await loadMessages(for: sessionID, using: service, projectID: projectID, allowCachedFallback: true)
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
            isSending = false
            return true
        } catch {
            clearLocalSessionActivity(sessionID)
            logger.error(
                "Failed to compact session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            setSessionStatus(.error, sessionID: sessionID, projectID: projectID)
            lastError = error.localizedDescription
            isSending = false
            return false
        }
    }

    private func resolvedCompactionModel(for sessionID: String) -> (providerID: String, modelID: String)? {
        if let selectedModel {
            return (selectedModel.providerID, selectedModel.modelID)
        }

        if let stats = sessionStats(for: sessionID),
           let providerID = stats.providerID,
           let modelID = stats.modelID {
            return (providerID, modelID)
        }

        return nil
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
        let fallback = ComposerModelOption(
            id: "openai/gpt-5.4",
            providerID: "openai",
            modelID: "gpt-5.4",
            title: "GPT-5.4",
            contextWindow: nil,
            variants: ["high", "medium", "low"]
        )
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
        beginSessionLoad(for: projectID)
        defer { endSessionLoad(for: projectID) }

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

    private func withSessionListSyncActivityIfNeeded(
        for projectID: ProjectSummary.ID,
        operation: () async -> Void
    ) async {
        let shouldTrack = shouldTrackSessionListSyncActivity(for: projectID)
        if shouldTrack {
            beginSessionListSyncActivity(for: projectID)
        }

        defer {
            if shouldTrack {
                endSessionListSyncActivity(for: projectID)
            }
        }

        await operation()
    }

    private func shouldTrackSessionListSyncActivity(for projectID: ProjectSummary.ID) -> Bool {
        guard let project = projects.first(where: { $0.id == projectID }) else { return false }
        return project.sessions.isEmpty
    }

    private func beginSessionListSyncActivity(for projectID: ProjectSummary.ID) {
        sessionListSyncActivityByProjectID[projectID, default: 0] += 1
    }

    private func endSessionListSyncActivity(for projectID: ProjectSummary.ID) {
        adjustCounter(&sessionListSyncActivityByProjectID, for: projectID, delta: -1)
    }

    private func beginSessionLoad(for projectID: ProjectSummary.ID) {
        loadingSessionCountsByProjectID[projectID, default: 0] += 1
    }

    private func endSessionLoad(for projectID: ProjectSummary.ID) {
        adjustCounter(&loadingSessionCountsByProjectID, for: projectID, delta: -1)
    }

    private func adjustCounter(
        _ counters: inout [ProjectSummary.ID: Int],
        for projectID: ProjectSummary.ID,
        delta: Int
    ) {
        let nextValue = max((counters[projectID] ?? 0) + delta, 0)
        if nextValue == 0 {
            counters.removeValue(forKey: projectID)
        } else {
            counters[projectID] = nextValue
        }
    }

    private func loadMessages(for sessionID: String, using service: any OpenCodeServicing, projectID: ProjectSummary.ID, allowCachedFallback: Bool = false) async {
        let loadKey = "\(projectID.uuidString)|\(sessionID)"
        guard activeTranscriptLoadKeys.insert(loadKey).inserted else { return }

        let keepsCurrentUI = allowCachedFallback && hasCachedTranscript(for: sessionID, projectID: projectID)
        let shouldTrackVisibleLoadingState = selectedSessionID == sessionID && selectedProjectID == projectID

        if shouldTrackVisibleLoadingState && !keepsCurrentUI {
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
            let shouldPreserveInProgressSuffix = hasBufferedTextDeltas(for: sessionID)
                || liveSessionStatuses[sessionID] == .busy
                || {
                    if case .retry = liveSessionStatuses[sessionID] {
                        return true
                    }
                    return false
                }()
            let transcript = Self.reconcileLoadedTranscript(
                existing: transcript(for: sessionID),
                incoming: ChatMessage.makeTranscript(from: messages),
                preserveInProgressSuffix: shouldPreserveInProgressSuffix
            )
            messageInfosBySessionID[sessionID] = Dictionary(uniqueKeysWithValues: messages.map { ($0.info.id, $0.info) })
            for message in messages {
                messageRoles[message.info.id] = message.info.chatRole
            }
            replaceTranscript(in: sessionID, projectID: projectID, with: transcript)
            replaceActiveTodos(in: sessionID, with: SessionTodoParser.latestSnapshot(from: messages))
            refreshSessionStats(sessionID: sessionID, projectID: projectID)
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
                setSessionStatus(.error, sessionID: sessionID, projectID: projectID)
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
                        if let queueSessionID = self.queueDispatchSessionID(for: event) {
                            await self.sendQueuedMessagesIfPossible(
                                for: queueSessionID,
                                projectID: projectID,
                                using: runtime
                            )
                        }
                        switch event {
                        case .sessionCreated(let session):
                            self.noteDashboardChange(projectID: projectID, sessionID: session.id, using: runtime)
                        case .sessionUpdated(let session):
                            self.noteDashboardChange(projectID: projectID, sessionID: session.id, using: runtime)
                        case .sessionDeleted(let sessionID):
                            self.noteDashboardChange(projectID: projectID, sessionID: sessionID, using: runtime)
                        case .sessionCompacted(let sessionID):
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

            let recoveryDelay: Duration = baselineRevision == nil ? .milliseconds(750) : .seconds(2)
            try? await Task.sleep(for: recoveryDelay)
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
        guard let sessionID = resolvedSessionID(for: part) else { return }
        markSessionLocallyActive(sessionID)
        flushBufferedTextDeltas(for: sessionID, projectID: projectID)
        applyActiveTodos(from: part, sessionID: sessionID)
        let defaultRole = part.messageID.flatMap { messageRoles[$0] } ?? .assistant
        guard !shouldSuppressTranscriptPart(part, defaultRole: defaultRole) else {
            return
        }
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

        if partTriggersGitRefresh(part, projectID: projectID),
           let projectPath = project(for: sessionID)?.path {
            scheduleGitRefresh(
                reason: "tool-call-file-modified",
                projectPath: projectPath,
                refreshCommitPreviewIfLoaded: gitStatus.hasChanges || gitCommitPreview != nil,
                delay: .milliseconds(150)
            )
        }
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
            bumpSessionUIRevision()
            refreshSystemSleepAssertion()
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
            terminationBlockReason(for: session) != nil
        }
    }

    private func terminationBlockReason(for session: SessionSummary) -> String? {
        if session.status.isActive || isSessionLocallyActive(session.id) {
            return "responding"
        }

        if pendingPermission(for: session.id) != nil {
            return "awaiting permission"
        }

        if pendingQuestion(for: session.id) != nil {
            return "awaiting input"
        }

        return nil
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

    private func partTriggersGitRefresh(_ part: OpenCodePart, projectID: ProjectSummary.ID) -> Bool {
        guard selectedProject?.id == projectID,
              part.type == .tool,
              part.toolStatus == .completed,
              let toolName = part.tool?.gitRefreshTriggerToolName
        else {
            return false
        }

        switch toolName {
        case "applypatch", "copy", "delete", "edit", "move", "remove", "write":
            return true
        case "bash":
            guard let command = part.state?.input?.stringValue(forKey: "command")?.lowercased() else {
                return false
            }
            return command == "git" || command.hasPrefix("git ") || command.contains(" git ")
        default:
            return false
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
            merged.lastSidebarActivityAt = max(existing.lastSidebarActivityAt ?? .distantPast, incoming.lastSidebarActivityAt ?? .distantPast)
            if merged.lastSidebarActivityAt == .distantPast {
                merged.lastSidebarActivityAt = nil
            }
            if merged.composerState == nil {
                merged.composerState = existing.composerState
            }
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
            let existing = projects[projectIndex].sessions[sessionIndex]
            var updated = session
            updated.transcript = []
            updated = updated.applyingInferredTitle(from: transcript)
            updated.lastSidebarActivityAt = max(existing.lastSidebarActivityAt ?? .distantPast, updated.lastSidebarActivityAt ?? .distantPast)
            if updated.lastSidebarActivityAt == .distantPast {
                updated.lastSidebarActivityAt = nil
            }
            if updated.stats == nil {
                updated.stats = existing.stats
            }
            if updated.composerState == nil {
                updated.composerState = existing.composerState
            }
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
        cancelPendingSessionCreation(for: sessionID)
        discardBufferedTextDeltas(for: sessionID, projectID: projectID)
        clearLocalSessionActivity(sessionID)
        queuedMessagesBySessionID.removeValue(forKey: sessionID)
        activeTodosBySessionID.removeValue(forKey: sessionID)
        queuedMessageDispatchingSessionIDs.remove(sessionID)
        removeTranscript(for: sessionID)
        projects[projectIndex].sessions.removeAll(where: { $0.id == sessionID })
        cancelStreamingRecoveryCheck(for: sessionID)
        liveSessionStatuses.removeValue(forKey: sessionID)
        observedRunningSessionIDs.remove(sessionID)
        finishedSessionIDs.remove(sessionID)
        pendingPermissionsBySession.removeValue(forKey: sessionID)
        pendingQuestionsBySession.removeValue(forKey: sessionID)
        clearSessionAliases(referencing: sessionID)
        if selectedSessionID == sessionID {
            selectedSessionID = nil
        }
        scheduleProjectPersistence()
    }

    private func applyActiveTodos(from part: OpenCodePart, sessionID: String) {
        guard let snapshot = SessionTodoParser.snapshot(from: part) else { return }
        replaceActiveTodos(in: sessionID, with: snapshot)
    }

    private func replaceActiveTodos(in sessionID: String, with snapshot: SessionTodoSnapshot?) {
        guard let snapshot else {
            activeTodosBySessionID.removeValue(forKey: sessionID)
            return
        }

        if snapshot.isEmpty {
            activeTodosBySessionID.removeValue(forKey: sessionID)
        } else {
            activeTodosBySessionID[sessionID] = snapshot
        }
    }

    private func resolvedSessionID(for part: OpenCodePart) -> String? {
        if let sessionID = part.sessionID {
            return sessionID
        }

        guard let messageID = part.messageID else { return nil }

        for (sessionID, infos) in messageInfosBySessionID where infos[messageID] != nil {
            return sessionID
        }

        return nil
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

    private func removeMessages(ids: [String], sessionID: String, projectID: ProjectSummary.ID) {
        guard !ids.isEmpty,
              let indices = indices(for: sessionID, projectID: projectID)
        else {
            return
        }

        let idsToRemove = Set(ids)
        var transcript = transcript(for: sessionID)
        transcript.removeAll { idsToRemove.contains($0.id) }
        setTranscript(transcript, for: sessionID)
        projects[indices.project].sessions[indices.session].lastUpdatedAt = transcript.last?.timestamp ?? projects[indices.project].sessions[indices.session].lastUpdatedAt
        scheduleProjectPersistence()
    }

    private func setSessionStatus(_ status: SessionStatus, sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        let previousStatus = projects[indices.project].sessions[indices.session].status

        switch status {
        case .running, .retrying:
            markSessionLocallyActive(sessionID)
        case .idle, .awaitingInput, .error:
            clearLocalSessionActivity(sessionID)
        }

        projects[indices.project].sessions[indices.session].status = status
        updateFinishedIndicator(sessionID: sessionID, previousStatus: previousStatus, newStatus: status)
        bumpSessionUIRevision()
        refreshSystemSleepAssertion()
        if !status.isActive {
            cancelStreamingRecoveryCheck(for: sessionID)
            flushPendingProjectPersistence()
            return
        }
        scheduleProjectPersistence(.streaming)
    }

    private func refreshSessionStatus(sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        let transcript = transcript(for: sessionID)
        let previousStatus = projects[indices.project].sessions[indices.session].status
        let resolvedStatus = resolvedSessionStatus(
            sessionID: sessionID,
            transcript: transcript,
            fallback: previousStatus
        )
        projects[indices.project].sessions[indices.session].status = resolvedStatus
        if previousStatus.isActive && !resolvedStatus.isActive {
            markSidebarActivity(sessionID: sessionID, projectID: projectID)
        }
        updateFinishedIndicator(sessionID: sessionID, previousStatus: previousStatus, newStatus: resolvedStatus)
        bumpSessionUIRevision()
        refreshSystemSleepAssertion()
        if !resolvedStatus.isActive {
            cancelStreamingRecoveryCheck(for: sessionID)
            flushPendingProjectPersistence()
            return
        }
        scheduleProjectPersistence(.streaming)
    }

    private func reconcileCompletedMessageIfNeeded(
        _ info: OpenCodeMessageInfo,
        sessionID: String,
        projectID: ProjectSummary.ID
    ) {
        guard info.isCompleted,
              let indices = indices(for: sessionID, projectID: projectID)
        else {
            return
        }

        var transcript = transcript(for: sessionID)
        var didChangeTranscript = false

        for index in transcript.indices where transcript[index].messageID == info.id && transcript[index].isInProgress {
            transcript[index].isInProgress = false
            if let completedAt = info.completedAt,
               transcript[index].timestamp < completedAt {
                transcript[index].timestamp = completedAt
            }
            didChangeTranscript = true
        }

        if didChangeTranscript {
            setTranscript(transcript, for: sessionID)
            projects[indices.project].sessions[indices.session].lastUpdatedAt = info.updatedAt ?? projects[indices.project].sessions[indices.session].lastUpdatedAt
        }

        if !transcript.contains(where: \.isInProgress) && !hasBufferedTextDeltas(for: sessionID) {
            clearLocalSessionActivity(sessionID)
        }

        refreshSessionStatus(sessionID: sessionID, projectID: projectID)
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
            return .awaitingInput
        }

        if pendingQuestion(for: sessionID) != nil {
            return .awaitingInput
        }

        if let activity = effectiveLiveSessionActivity(for: sessionID, transcript: transcript) {
            switch activity {
            case .idle:
                return .idle
            case .busy:
                return .running
            case .retry:
                return .retrying
            }
        }

        return transcriptDerivedStatus(for: transcript, sessionID: sessionID, fallback: fallback)
    }

    private func transcriptDerivedStatus(
        for transcript: [ChatMessage],
        sessionID: String,
        fallback _: SessionStatus = .idle
    ) -> SessionStatus {
        if isSessionLocallyActive(sessionID), transcript.contains(where: \.isInProgress) {
            return .running
        }

        if let toolCall = transcript.last?.kind.toolCall,
           toolCall.status == .error,
           !toolCallRepresentsAbort(toolCall) {
            return .error
        }

        return .idle
    }

    private func toolCallRepresentsAbort(_ toolCall: ChatMessage.ToolCall) -> Bool {
        let messages = [toolCall.error, toolCall.detail]
            .compactMap { $0?.lowercased() }

        return messages.contains { message in
            message.contains("tool execution aborted")
                || message.contains("operation was aborted")
                || message.contains("request aborted")
                || message.contains("stream aborted")
                || message.contains("questionrejectederror")
                || message.contains("question rejected")
        }
    }

    private func effectiveLiveSessionActivity(
        for sessionID: String,
        transcript: [ChatMessage]
    ) -> OpenCodeSessionActivity? {
        guard isSessionLocallyActive(sessionID),
              let activity = liveSessionStatuses[sessionID]
        else {
            return nil
        }

        switch activity {
        case .idle:
            return .idle
        case .busy, .retry:
            guard transcript.contains(where: \.isInProgress)
                    || hasBufferedTextDeltas(for: sessionID)
                    || transcript.last?.role == .user
            else {
                return nil
            }
            return activity
        }
    }

    private func settleSessionActivity(sessionID: String, projectID: ProjectSummary.ID) {
        flushBufferedTextDeltas(for: sessionID, projectID: projectID)
        clearLocalSessionActivity(sessionID)

        guard let indices = indices(for: sessionID, projectID: projectID) else { return }

        var transcript = transcript(for: sessionID)
        guard transcript.contains(where: \.isInProgress) else { return }

        for index in transcript.indices where transcript[index].isInProgress {
            transcript[index].isInProgress = false
        }

        setTranscript(transcript, for: sessionID)
        projects[indices.project].sessions[indices.session].lastUpdatedAt = transcript.last?.timestamp ?? projects[indices.project].sessions[indices.session].lastUpdatedAt
    }

    private func hasBufferedTextDeltas(for sessionID: String) -> Bool {
        bufferedTextDeltas.keys.contains { $0.sessionID == sessionID }
    }

    private func clearStatusIndicators(for sessionID: String?) {
        guard let sessionID else { return }
        finishedSessionIDs.remove(sessionID)
        failedSessionIDs.remove(sessionID)
        bumpSessionUIRevision()
    }

    private func updateFinishedIndicator(sessionID: String, previousStatus: SessionStatus, newStatus: SessionStatus) {
        if newStatus.isActive {
            observedRunningSessionIDs.insert(sessionID)
            finishedSessionIDs.remove(sessionID)
            failedSessionIDs.remove(sessionID)
            return
        }

        if selectedSessionID == sessionID {
            finishedSessionIDs.remove(sessionID)
            failedSessionIDs.remove(sessionID)
        }

        guard observedRunningSessionIDs.contains(sessionID) else { return }

        switch newStatus {
        case .idle:
            if previousStatus.isActive, selectedSessionID != sessionID {
                finishedSessionIDs.insert(sessionID)
            }
            failedSessionIDs.remove(sessionID)
            observedRunningSessionIDs.remove(sessionID)
        case .awaitingInput, .error:
            finishedSessionIDs.remove(sessionID)
            if newStatus == .error, previousStatus.isActive, selectedSessionID != sessionID {
                failedSessionIDs.insert(sessionID)
            } else {
                failedSessionIDs.remove(sessionID)
            }
            observedRunningSessionIDs.remove(sessionID)
        case .running, .retrying:
            break
        }
    }

    private func bumpSessionUIRevision() {
        sessionUIRevision &+= 1
    }

    private func queueDispatchSessionID(for event: OpenCodeEvent) -> String? {
        switch event {
        case .sessionCompacted(let sessionID):
            return sessionID
        case .sessionStatusChanged(let sessionID, _):
            return sessionID
        case .permissionAsked(let request):
            return request.sessionID
        case .permissionReplied(let event):
            return event.sessionID
        case .questionAsked(let request):
            return request.sessionID
        case .questionReplied(let event):
            return event.sessionID
        case .questionRejected(let event):
            return event.sessionID
        case .messageUpdated(let info):
            return info.sessionID
        case .messagePartUpdated(let part):
            return part.sessionID
        case .messagePartDelta(let delta):
            return delta.sessionID
        case .sessionCreated, .sessionUpdated, .sessionDeleted, .connected, .ignored:
            return nil
        }
    }

    @discardableResult
    func sendNextQueuedMessageIfPossible(
        in sessionID: String,
        projectID: ProjectSummary.ID,
        projectPath: String,
        using service: any OpenCodeServicing
    ) async -> Bool {
        guard canDispatchQueuedMessages(for: sessionID),
              pendingPermission(for: sessionID) == nil,
              pendingQuestion(for: sessionID) == nil,
              let queuedMessage = popFirstQueuedMessage(in: sessionID)
        else {
            return false
        }

        let fileReferences = await ProjectFileSearchService.shared.resolveFileReferences(in: projectPath, text: queuedMessage.text)
        let didSend = await sendMessage(
            text: queuedMessage.text,
            attachments: queuedMessage.attachments,
            fileReferences: fileReferences,
            options: OpenCodePromptOptions(
                model: queuedMessage.options.model,
                agentName: queuedMessage.options.agentName,
                variant: queuedMessage.options.variant
            ),
            using: service,
            projectID: projectID,
            sessionID: sessionID,
            clearComposerOnSend: false,
            restoreComposerOnFailure: false
        )

        if !didSend {
            prependQueuedMessage(queuedMessage, in: sessionID)
        }
        return didSend
    }

    private func canDispatchQueuedMessages(for sessionID: String) -> Bool {
        guard let status = session(for: sessionID)?.status else {
            return false
        }

        return !status.isActive
    }

    @discardableResult
    func sendQueuedSteerMessageIfPossible(
        id: ComposerQueuedMessage.ID,
        in sessionID: String,
        projectID: ProjectSummary.ID,
        projectPath: String,
        using service: any OpenCodeServicing
    ) async -> Bool {
        guard pendingPermission(for: sessionID) == nil,
              pendingQuestion(for: sessionID) == nil,
              let queuedEntry = removeQueuedMessage(id: id, in: sessionID)
        else {
            return false
        }

        let queuedMessage = queuedEntry.message
        guard queuedMessage.deliveryMode == .steer else {
            insertQueuedMessage(queuedMessage, at: queuedEntry.index, in: sessionID)
            return false
        }

        let fileReferences = await ProjectFileSearchService.shared.resolveFileReferences(in: projectPath, text: queuedMessage.text)
        let didSend = await sendMessage(
            text: queuedMessage.text,
            attachments: queuedMessage.attachments,
            fileReferences: fileReferences,
            options: OpenCodePromptOptions(
                model: queuedMessage.options.model,
                agentName: queuedMessage.options.agentName,
                variant: queuedMessage.options.variant
            ),
            using: service,
            projectID: projectID,
            sessionID: sessionID,
            clearComposerOnSend: false,
            restoreComposerOnFailure: false
        )

        if !didSend {
            insertQueuedMessage(queuedMessage, at: queuedEntry.index, in: sessionID)
        }
        return didSend
    }

    @discardableResult
    func sendQueuedSteerMessageIfPossible(
        id: ComposerQueuedMessage.ID,
        in sessionID: String,
        using runtime: OpenCodeRuntime
    ) async -> Bool {
        guard let projectID = projectID(for: sessionID),
              let service = await liveService(for: projectID, runtime: runtime),
              let projectPath = projectPath(for: projectID)
        else {
            return false
        }

        let didSend = await sendQueuedSteerMessageIfPossible(
            id: id,
            in: sessionID,
            projectID: projectID,
            projectPath: projectPath,
            using: service
        )
        if didSend {
            scheduleStreamingRecoveryCheck(for: sessionID, projectID: projectID, using: runtime)
        }
        return didSend
    }

    private func sendQueuedMessagesIfPossible(
        for sessionID: String,
        projectID: ProjectSummary.ID,
        using runtime: OpenCodeRuntime
    ) async {
        guard queuedMessageDispatchingSessionIDs.insert(sessionID).inserted else { return }
        defer { queuedMessageDispatchingSessionIDs.remove(sessionID) }

        while true {
            guard let service = await liveService(for: projectID, runtime: runtime),
                  let projectPath = projectPath(for: projectID)
            else {
                return
            }

            let didSend = await sendNextQueuedMessageIfPossible(
                in: sessionID,
                projectID: projectID,
                projectPath: projectPath,
                using: service
            )
            guard didSend else {
                return
            }
            scheduleStreamingRecoveryCheck(for: sessionID, projectID: projectID, using: runtime)
        }
    }

    private func reconcileOptimisticUserMessage(with message: ChatMessage, sessionID: String, projectID: ProjectSummary.ID) {
        guard message.attachment == nil else { return }

        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        var transcript = transcript(for: sessionID)

        guard let optimisticIndex = transcript.lastIndex(where: {
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
        guard let optimisticIndex = transcript.lastIndex(where: {
            guard $0.id.hasPrefix("optimistic-user-attachment-"),
                  let optimisticAttachment = $0.attachment
            else {
                return false
            }

            return optimisticAttachmentsMatch(optimisticAttachment, attachment)
        }) else {
            return
        }

        transcript.remove(at: optimisticIndex)
        setTranscript(transcript, for: sessionID)
        projects[indices.project].sessions[indices.session].lastUpdatedAt = message.timestamp
    }

    private func shouldSuppressTranscriptPart(_ part: OpenCodePart, defaultRole: ChatMessage.Role) -> Bool {
        defaultRole == .user && (part.isSyntheticAttachmentReadSummary || part.isSyntheticUserFileContentDump)
    }

    private func optimisticAttachmentsMatch(_ optimistic: ChatAttachment, _ incoming: ChatAttachment) -> Bool {
        if optimistic.optimisticKey == incoming.optimisticKey {
            return true
        }

        if let optimisticSourcePath = optimistic.sourcePath?.nonEmptyTrimmed,
           let incomingSourcePath = incoming.sourcePath?.nonEmptyTrimmed,
           optimisticSourcePath == incomingSourcePath {
            return true
        }

        if let optimisticSourcePath = optimistic.sourcePath?.nonEmptyTrimmed,
           incoming.url == URL(fileURLWithPath: optimisticSourcePath).absoluteString {
            return true
        }

        if let incomingSourcePath = incoming.sourcePath?.nonEmptyTrimmed,
           optimistic.url == URL(fileURLWithPath: incomingSourcePath).absoluteString {
            return true
        }

        if let optimisticFilename = optimistic.filename?.nonEmptyTrimmed,
           let incomingFilename = incoming.filename?.nonEmptyTrimmed,
           optimisticFilename == incomingFilename,
           optimistic.mimeType == incoming.mimeType {
            return true
        }

        return optimistic.displayTitle == incoming.displayTitle && optimistic.mimeType == incoming.mimeType
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

    private func markSidebarActivity(sessionID: String, projectID: ProjectSummary.ID, at date: Date = .now) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        projects[indices.project].sessions[indices.session].lastSidebarActivityAt = date
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
        bumpSessionUIRevision()
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
        guard isPersistenceEnabled,
              appSettings.general.restoresPromptDrafts
        else {
            return
        }

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

        guard appSettings.general.restoresPromptDrafts else {
            isPromptReady = true
            promptLoadingText = nil
            isHydratingPrompt = true
            draft = ""
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
        guard appSettings.general.restoresPromptDrafts else {
            promptDraftsByKey.removeValue(forKey: promptKey)
            loadedPromptKeys.remove(promptKey)
            if isPersistenceEnabled {
                await promptDraftPersistence.saveDraft("", forKey: promptKey)
            }
            return
        }

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
        guard let project = project(for: sessionID) else { return nil }
        return "\(project.path)::\(sessionID)"
    }

    private func persistWorkspaceSelectionIfNeeded() {
        guard isPersistenceEnabled, !isSettingsSelected else { return }
        workspaceSelectionPersistence.saveSelection(currentWorkspaceSelection)
    }

    private var currentWorkspaceSelection: PersistedWorkspaceSelectionStore.Selection {
        switch selectedContent {
        case .session(let sessionID):
            return PersistedWorkspaceSelectionStore.Selection(
                kind: .session,
                projectID: project(for: sessionID)?.id ?? selectedProjectID,
                sessionID: sessionID
            )
        case .dashboard, .settings:
            return PersistedWorkspaceSelectionStore.Selection(
                kind: .dashboard,
                projectID: selectedProjectID
            )
        }
    }

    private static func initialWorkspaceSelection(
        projects: [ProjectSummary],
        startupBehavior: NeoCodeStartupBehavior,
        restoredSelection: PersistedWorkspaceSelectionStore.Selection?
    ) -> (projectID: ProjectSummary.ID?, content: AppContentSelection) {
        let fallbackProjectID = projects.first?.id

        guard startupBehavior == .lastWorkspace,
              let restoredSelection
        else {
            return (fallbackProjectID, .dashboard)
        }

        let restoredProjectID = restoredSelection.projectID.flatMap { projectID in
            projects.contains(where: { $0.id == projectID }) ? projectID : nil
        }

        switch restoredSelection.kind {
        case .dashboard:
            return (restoredProjectID ?? fallbackProjectID, .dashboard)
        case .session:
            guard let sessionID = restoredSelection.sessionID,
                  let project = projects.first(where: { project in
                      project.sessions.contains(where: { $0.id == sessionID })
                  })
            else {
                return (restoredProjectID ?? fallbackProjectID, .dashboard)
            }

            return (project.id, .session(sessionID))
        }
    }

    private func notifyIfNeededForCompletedResponse(sessionID: String, previousStatus: OpenCodeSessionActivity?, status: OpenCodeSessionActivity) {
        guard appSettings.general.notifiesWhenResponseCompletes,
              previousStatus != .idle,
              status == .idle,
              let session = session(for: sessionID)
        else {
            return
        }

        let title = session.title == SessionSummary.defaultTitle ? "Response finished" : session.title
        let body = "NeoCode finished the latest response."

        Task { [weak self] in
            await self?.notificationService.postIfApplicationInactive(
                identifier: "completion-\(sessionID)",
                title: title,
                body: body
            )
        }
    }

    private func notifyIfNeededForPermissionRequest(_ request: OpenCodePermissionRequest) {
        guard appSettings.general.notifiesWhenInputIsRequired,
              let session = session(for: request.sessionID)
        else {
            return
        }

        let body = session.title == SessionSummary.defaultTitle
            ? "A session needs permission before it can continue."
            : "\(session.title) needs permission before it can continue."

        Task { [weak self] in
            await self?.notificationService.postIfApplicationInactive(
                identifier: "permission-\(request.id)",
                title: "Permission required",
                body: body
            )
        }
    }

    private func notifyIfNeededForQuestionRequest(_ request: OpenCodeQuestionRequest) {
        guard appSettings.general.notifiesWhenInputIsRequired,
              let session = session(for: request.sessionID)
        else {
            return
        }

        let body = session.title == SessionSummary.defaultTitle
            ? "A session is waiting for your answer."
            : "\(session.title) is waiting for your answer."

        Task { [weak self] in
            await self?.notificationService.postIfApplicationInactive(
                identifier: "question-\(request.id)",
                title: "Input required",
                body: body
            )
        }
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
        bumpSessionUIRevision()
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

    private func affectedPromptMessageIDs(from startIndex: Int, in transcript: [ChatMessage]) -> [String] {
        var ids: [String] = []
        var seen = Set<String>()

        for message in transcript[startIndex...] where message.role == .user {
            let id = message.messageID ?? message.id
            if seen.insert(id).inserted {
                ids.append(id)
            }
        }

        return ids
    }

    private func aggregatedRevertFileChanges(
        for messageIDs: [String],
        messageInfos: [String: OpenCodeMessageInfo]
    ) -> [RevertPreviewFileChange] {
        var changesByPath: [String: RevertPreviewFileChange] = [:]

        for messageID in messageIDs {
            let diffs = messageInfos[messageID]?.summaryInfo?.diffs ?? []
            for diff in diffs {
                let nextStatus = RevertPreviewFileChange.Status(rawValue: diff.status?.rawValue ?? "") ?? .modified
                if let existing = changesByPath[diff.file] {
                    changesByPath[diff.file] = RevertPreviewFileChange(
                        path: diff.file,
                        additions: existing.additions + diff.additions,
                        deletions: existing.deletions + diff.deletions,
                        status: mergedRevertStatus(existing.status, nextStatus)
                    )
                } else {
                    changesByPath[diff.file] = RevertPreviewFileChange(
                        path: diff.file,
                        additions: diff.additions,
                        deletions: diff.deletions,
                        status: nextStatus
                    )
                }
            }
        }

        return changesByPath.values.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private func mergedRevertStatus(
        _ existing: RevertPreviewFileChange.Status,
        _ incoming: RevertPreviewFileChange.Status
    ) -> RevertPreviewFileChange.Status {
        if existing == incoming {
            return existing
        }

        if existing == .modified || incoming == .modified {
            return .modified
        }

        return .modified
    }

    private func pruneMessageMetadata(in sessionID: String, keeping allowedMessageIDs: Set<String>) {
        if var infos = messageInfosBySessionID[sessionID] {
            infos = infos.filter { allowedMessageIDs.contains($0.key) }
            messageInfosBySessionID[sessionID] = infos
        }
    }

    private func refreshSessionStats(sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID),
              let infos = messageInfosBySessionID[sessionID]
        else {
            return
        }

        let projectPath = projects[indices.project].path
        let models = cachedModelsByProjectPath[projectPath] ?? availableModels
        let transcript = transcriptStateBySessionID[sessionID]?.messages ?? projects[indices.project].sessions[indices.session].transcript
        projects[indices.project].sessions[indices.session].stats = SessionStatsSnapshot.make(
            sessionID: sessionID,
            messageInfos: Array(infos.values),
            models: models,
            transcript: transcript
        )
    }

    private func indices(for sessionID: String, projectID: ProjectSummary.ID) -> (project: Int, session: Int)? {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let sessionIndex = projects[projectIndex].sessions.firstIndex(where: { $0.id == sessionID })
        else { return nil }
        return (projectIndex, sessionIndex)
    }

    private func projectID(for sessionID: String) -> ProjectSummary.ID? {
        let sessionID = resolvedSessionID(for: sessionID)
        return projects.first(where: { project in
            project.sessions.contains(where: { $0.id == sessionID })
        })?.id
    }

    private func session(for sessionID: String) -> SessionSummary? {
        let sessionID = resolvedSessionID(for: sessionID)
        return projects
            .flatMap(\.sessions)
            .first(where: { $0.id == sessionID })
    }

    private func resolvedSessionID(for sessionID: String) -> String {
        var resolvedID = sessionID
        var visitedIDs = Set<String>()

        while let nextID = sessionIDAliases[resolvedID], visitedIDs.insert(resolvedID).inserted {
            resolvedID = nextID
        }

        return resolvedID
    }

    private func registerSessionAlias(from oldSessionID: String, to newSessionID: String) {
        let newSessionID = resolvedSessionID(for: newSessionID)
        guard oldSessionID != newSessionID else {
            sessionIDAliases.removeValue(forKey: oldSessionID)
            return
        }

        sessionIDAliases[oldSessionID] = newSessionID
    }

    private func clearSessionAliases(referencing sessionID: String) {
        sessionIDAliases = sessionIDAliases.filter { $0.key != sessionID && $0.value != sessionID }
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
        messageInfosBySessionID.removeValue(forKey: sessionID)
    }

    private func moveTranscript(from sourceSessionID: String, to destinationSessionID: String) {
        guard sourceSessionID != destinationSessionID,
              let existingState = transcriptStateBySessionID.removeValue(forKey: sourceSessionID)
        else {
            return
        }

        transcriptStateBySessionID[destinationSessionID] = existingState
        if let infos = messageInfosBySessionID.removeValue(forKey: sourceSessionID) {
            messageInfosBySessionID[destinationSessionID] = infos
        }
    }

    @discardableResult
    private func ensureServerSession(
        for sessionID: String,
        in projectID: ProjectSummary.ID,
        using runtime: OpenCodeRuntime
    ) async -> String? {
        if let task = sessionCreationTasksBySessionID[sessionID] {
            return await task.value
        }

        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            guard let service = await self.liveService(for: projectID, runtime: runtime) else {
                return nil
            }
            return await self.ensureServerSession(for: sessionID, in: projectID, using: service)
        }

        sessionCreationTasksBySessionID[sessionID] = task
        let createdSessionID = await task.value
        sessionCreationTasksBySessionID.removeValue(forKey: sessionID)
        reevaluateRuntimeRetention(using: runtime)
        return createdSessionID
    }

    @discardableResult
    private func ensureServerSession(
        for sessionID: String,
        in projectID: ProjectSummary.ID,
        using service: any OpenCodeServicing
    ) async -> String? {
        guard let session = self.session(for: sessionID) else {
            return nil
        }

        guard session.isEphemeral else {
            return session.id
        }

        do {
            logger.info("Creating server session for pending thread id: \(sessionID, privacy: .public)")
            let created = try await service.createSession(title: self.session(for: sessionID)?.requestedServerTitle)

            if Task.isCancelled {
                _ = try? await service.deleteSession(sessionID: created.id)
                return nil
            }

            guard let latestSession = self.session(for: sessionID) else {
                _ = try? await service.deleteSession(sessionID: created.id)
                return nil
            }

            guard latestSession.isEphemeral else {
                return latestSession.id
            }

            logger.info("Created server session id: \(created.id, privacy: .public) for pending thread \(sessionID, privacy: .public)")
            await promoteEphemeralSession(sessionID, in: projectID, to: created)
            lastError = nil
            return created.id
        } catch is CancellationError {
            return nil
        } catch {
            logger.error("Failed to create server session for pending thread \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            return nil
        }
    }

    private func cancelPendingSessionCreation(for sessionID: String) {
        sessionCreationTasksBySessionID[sessionID]?.cancel()
        sessionCreationTasksBySessionID.removeValue(forKey: sessionID)
    }

    private func registerPendingSendUI(_ stagedUI: StagedSendUI, forOriginalSessionID sessionID: String) {
        guard var state = pendingSendStatesByOriginalSessionID[sessionID] else { return }
        state.stagedUI = stagedUI
        pendingSendStatesByOriginalSessionID[sessionID] = state
    }

    private func registerPendingSendActiveSessionID(_ activeSessionID: String, forOriginalSessionID sessionID: String) {
        guard var state = pendingSendStatesByOriginalSessionID[sessionID] else { return }
        state.activeSessionID = activeSessionID
        pendingSendStatesByOriginalSessionID[sessionID] = state
    }

    private func handleCancelledSend(
        originatingSessionID: String,
        fallbackSessionID: String,
        projectID: ProjectSummary.ID,
        restoreComposerOnFailure: Bool
    ) {
        let state = pendingSendStatesByOriginalSessionID[originatingSessionID]
        let resolvedSessionID = state?.activeSessionID ?? fallbackSessionID

        if let stagedUI = state?.stagedUI,
           state?.didAcceptRemoteSend != true {
            revertFailedSend(
                stagedUI,
                sessionID: resolvedSessionID,
                projectID: projectID,
                restoreComposerOnFailure: restoreComposerOnFailure
            )
        }

        isSending = false
    }

    private func finishPendingSendTracking(forOriginalSessionID sessionID: String, token: UUID) {
        guard let state = pendingSendStatesByOriginalSessionID[sessionID],
              state.token == token
        else {
            return
        }

        pendingSendStatesByOriginalSessionID.removeValue(forKey: sessionID)
    }

    private func stageSendUI(
        text: String,
        attachments: [ComposerAttachment],
        shouldShowOptimisticUserMessage: Bool,
        sessionID: String,
        projectID: ProjectSummary.ID,
        clearComposerOnSend: Bool
    ) -> StagedSendUI {
        isSending = true
        lastError = nil

        let now = Date()
        let optimisticMessageID = "optimistic-user-message-\(UUID().uuidString)"
        var userMessageID: String?
        var attachmentMessageIDs: [String] = []

        if shouldShowOptimisticUserMessage && !text.isEmpty {
            let optimisticID = "optimistic-user-\(UUID().uuidString)"
            userMessageID = optimisticID
            upsertMessage(
                ChatMessage(id: optimisticID, messageID: optimisticMessageID, role: .user, text: text, timestamp: now, emphasis: .normal),
                in: sessionID,
                projectID: projectID
            )
        }

        if shouldShowOptimisticUserMessage {
            for attachment in attachments {
                let messageID = "optimistic-user-attachment-\(UUID().uuidString)"
                attachmentMessageIDs.append(messageID)
                upsertMessage(
                    ChatMessage(
                        id: messageID,
                        messageID: optimisticMessageID,
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

        if clearComposerOnSend {
            draft = ""
            attachedFiles = []
        }

        setSessionStatus(.running, sessionID: sessionID, projectID: projectID)
        return StagedSendUI(
            userMessageID: userMessageID,
            attachmentMessageIDs: attachmentMessageIDs,
            originalText: text,
            originalAttachments: attachments
        )
    }

    private func revertFailedSend(
        _ stagedUI: StagedSendUI,
        sessionID: String,
        projectID: ProjectSummary.ID,
        restoreComposerOnFailure: Bool
    ) {
        if let userMessageID = stagedUI.userMessageID {
            removeMessage(id: userMessageID, sessionID: sessionID, projectID: projectID)
        }
        removeMessages(ids: stagedUI.attachmentMessageIDs, sessionID: sessionID, projectID: projectID)
        if restoreComposerOnFailure {
            draft = stagedUI.originalText
            attachedFiles = stagedUI.originalAttachments
        }
        setSessionStatus(.error, sessionID: sessionID, projectID: projectID)
    }

    private func resolveSendFileReferences(for text: String, projectID: ProjectSummary.ID) async -> [ComposerPromptFileReference] {
        guard text.contains("@"),
              let projectPath = projectPath(for: projectID)
        else {
            return []
        }

        return await ProjectFileSearchService.shared.resolveFileReferences(in: projectPath, text: text)
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

    private func isSessionActivelyResponding(_ sessionID: String) -> Bool {
        if let activity = effectiveLiveSessionActivity(for: sessionID, transcript: transcript(for: sessionID)) {
            switch activity {
            case .busy, .retry:
                return true
            case .idle:
                return false
            }
        }

        if session(for: sessionID)?.status.isActive == true {
            return true
        }

        return isSessionLocallyActive(sessionID) || hasBufferedTextDeltas(for: sessionID)
    }

    @discardableResult
    private func stagePendingSession(in projectID: ProjectSummary.ID) -> String {
        let session = SessionSummary(
            id: "draft-session-\(UUID().uuidString)",
            title: newSessionTitle,
            lastUpdatedAt: .now,
            isEphemeral: true,
            composerState: currentSessionComposerState
        )
        upsert(session: session, in: projectID, preferTopInsertion: true)
        selectedProjectID = projectID
        restoreComposerOptionsFromCache(for: projectPath(for: projectID))
        selectedSessionID = session.id
        loadingTranscriptSessionID = nil
        scheduleGitRefreshLoop(for: projectPath(for: projectID))
        primePromptState(for: session.id)
        lastError = nil
        return session.id
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

        if let task = sessionCreationTasksBySessionID[currentSessionID],
           let createdSessionID = await task.value {
            return createdSessionID
        }

        return await ensureServerSession(for: currentSessionID, in: projectID, using: service)
    }

    func promoteEphemeralSession(_ ephemeralSessionID: String, in projectID: ProjectSummary.ID, to created: OpenCodeSession) async {
        guard let ephemeralSession = session(for: ephemeralSessionID) else { return }

        let ephemeralPromptKey = promptDraftKey(for: ephemeralSessionID)
        let wasYoloEnabled = isYoloModeEnabled(for: ephemeralSessionID)

        replaceSession(
            ephemeralSessionID,
            in: projectID,
            with: SessionSummary(
                session: created,
                fallbackTitle: ephemeralSession.title,
                composerState: ephemeralSession.composerState
            )
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
        if replacement.stats == nil {
            replacement.stats = existing.stats
        }
        if replacement.composerState == nil {
            replacement.composerState = existing.composerState
        }
        replacement.transcript = []
        replacement.lastUpdatedAt = max(existing.lastUpdatedAt, session.lastUpdatedAt)
        replacement.lastSidebarActivityAt = max(existing.lastSidebarActivityAt ?? .distantPast, session.lastSidebarActivityAt ?? .distantPast)
        if replacement.lastSidebarActivityAt == .distantPast {
            replacement.lastSidebarActivityAt = nil
        }
        projects[projectIndex].sessions[sessionIndex] = replacement
        registerSessionAlias(from: sessionID, to: session.id)
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

    static func reconcileLoadedTranscript(
        existing: [ChatMessage],
        incoming: [ChatMessage],
        preserveInProgressSuffix: Bool = true
    ) -> [ChatMessage] {
        guard !existing.isEmpty else { return incoming }
        guard !incoming.isEmpty else {
            return preservedLocalTranscriptSuffix(
                existing: existing,
                incomingIDs: [],
                preserveInProgressSuffix: preserveInProgressSuffix
            ) ?? incoming
        }

        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIDs = Set(incoming.map(\.id))
        var reconciled = incoming.map { incomingMessage in
            guard let existingMessage = existingByID[incomingMessage.id] else {
                return incomingMessage
            }

            return preferredTranscriptMessage(existing: existingMessage, incoming: incomingMessage)
        }

        if let preservedSuffix = preservedLocalTranscriptSuffix(
            existing: existing,
            incomingIDs: incomingIDs,
            preserveInProgressSuffix: preserveInProgressSuffix
        ) {
            reconciled.append(contentsOf: preservedSuffix)
        }

        return reconciled
    }

    private static func preservedLocalTranscriptSuffix(
        existing: [ChatMessage],
        incomingIDs: Set<String>,
        preserveInProgressSuffix: Bool
    ) -> [ChatMessage]? {
        guard preserveInProgressSuffix else { return nil }

        var trailingMessages: [ChatMessage] = []

        for message in existing.reversed() {
            if incomingIDs.contains(message.id) {
                break
            }

            trailingMessages.append(message)
        }

        guard !trailingMessages.isEmpty else { return nil }

        let preserved = trailingMessages.reversed()
        return preserved.contains(where: \.isInProgress) ? Array(preserved) : nil
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
        merged.lastSidebarActivityAt = max(existing.lastSidebarActivityAt ?? .distantPast, incoming.lastSidebarActivityAt ?? .distantPast)
        if merged.lastSidebarActivityAt == .distantPast {
            merged.lastSidebarActivityAt = nil
        }
        merged.isEphemeral = existing.isEphemeral && incoming.isEphemeral
        return merged.applyingInferredTitle(from: merged.transcript)
    }

    private static func sessionStatusPriority(_ status: SessionStatus) -> Int {
        switch status {
        case .idle:
            return 0
        case .error:
            return 1
        case .awaitingInput:
            return 2
        case .running, .retrying:
            return 3
        }
    }

    private static func preferredTranscriptMessage(existing: ChatMessage, incoming: ChatMessage) -> ChatMessage {
        if existing.isInProgress != incoming.isInProgress {
            return existing.isInProgress ? incoming : existing
        }

        if (existing.attachment != nil) != (incoming.attachment != nil) {
            return existing.attachment != nil ? existing : incoming
        }

        if existing.text.count != incoming.text.count {
            return existing.text.count > incoming.text.count ? existing : incoming
        }

        if existing.timestamp != incoming.timestamp {
            return existing.timestamp > incoming.timestamp ? existing : incoming
        }

        return incoming
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

    private func persistAppSettingsIfNeeded() {
        guard isPersistenceEnabled else { return }
        appSettingsPersistence.saveSettings(appSettings)
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

private extension String {
    var gitRefreshTriggerToolName: String {
        let leaf = split(whereSeparator: { $0 == "." || $0 == "/" || $0 == ":" }).last.map(String.init) ?? self
        return leaf
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
    }
}

private extension JSONValue {
    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var object: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    func stringValue(forKey key: String) -> String? {
        object?[key]?.string
    }
}
