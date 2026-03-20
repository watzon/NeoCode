import Foundation

@MainActor
protocol AppStoreNotificationServing {
    func requestAuthorizationIfNeeded() async -> Bool
    func postIfApplicationInactive(identifier: String, title: String, body: String) async
}

@MainActor
protocol AppStoreSleepAssertionServing {
    func setActive(_ active: Bool)
}

protocol AppStoreDashboardStatsServing: AnyObject {
    func prepare(
        projects: [DashboardProjectDescriptor],
        range: DashboardTimeRange,
        projectPath: String?
    ) async -> DashboardSnapshot
    func currentSnapshot(range: DashboardTimeRange, projectPath: String?) async -> DashboardSnapshot
    func planRefresh(
        for project: DashboardProjectDescriptor,
        sessions: [DashboardRemoteSessionDescriptor],
        forceSessionIDs: Set<String>,
        range: DashboardTimeRange,
        projectPath: String?
    ) async -> DashboardRefreshPlan
    func ingest(
        _ ingestions: [DashboardSessionIngress],
        range: DashboardTimeRange,
        projectPath: String?
    ) async -> DashboardSnapshot
    func ingestSummaries(
        _ ingestions: [DashboardSessionSummaryIngress],
        range: DashboardTimeRange,
        projectPath: String?
    ) async -> DashboardSnapshot
}

protocol AppStoreWorkspaceToolServing {
    func projectOpenTools() -> [WorkspaceTool]
    func defaultProjectOpenTool(from tools: [WorkspaceTool]) -> WorkspaceTool?
    func openProject(at projectPath: String, with tool: WorkspaceTool)
}

struct AppStorePersistence {
    let projects: PersistedProjectsStore
    let appSettings: PersistedAppSettingsStore
    let workspaceSelection: PersistedWorkspaceSelectionStore
    let promptDrafts: PersistedPromptDraftsStore
    let yoloPreferences: PersistedYoloPreferencesStore
    let favoriteModels: PersistedFavoriteModelsStore

    init(
        projects: PersistedProjectsStore = PersistedProjectsStore(),
        appSettings: PersistedAppSettingsStore = PersistedAppSettingsStore(),
        workspaceSelection: PersistedWorkspaceSelectionStore = PersistedWorkspaceSelectionStore(),
        promptDrafts: PersistedPromptDraftsStore = PersistedPromptDraftsStore(),
        yoloPreferences: PersistedYoloPreferencesStore = PersistedYoloPreferencesStore(),
        favoriteModels: PersistedFavoriteModelsStore = PersistedFavoriteModelsStore()
    ) {
        self.projects = projects
        self.appSettings = appSettings
        self.workspaceSelection = workspaceSelection
        self.promptDrafts = promptDrafts
        self.yoloPreferences = yoloPreferences
        self.favoriteModels = favoriteModels
    }
}

@MainActor
struct AppStoreServices {
    let notifications: any AppStoreNotificationServing
    let sleepAssertions: any AppStoreSleepAssertionServing
    let dashboardStats: any AppStoreDashboardStatsServing
    let workspaceTools: any AppStoreWorkspaceToolServing

    init() {
        self.notifications = NeoCodeNotificationService()
        self.sleepAssertions = NeoCodeSleepAssertionService()
        self.dashboardStats = DashboardStatsService()
        self.workspaceTools = WorkspaceToolService()
    }

    init(
        notifications: any AppStoreNotificationServing,
        sleepAssertions: any AppStoreSleepAssertionServing,
        dashboardStats: any AppStoreDashboardStatsServing,
        workspaceTools: any AppStoreWorkspaceToolServing
    ) {
        self.notifications = notifications
        self.sleepAssertions = sleepAssertions
        self.dashboardStats = dashboardStats
        self.workspaceTools = workspaceTools
    }
}

extension NeoCodeNotificationService: AppStoreNotificationServing {}
extension NeoCodeSleepAssertionService: AppStoreSleepAssertionServing {}
extension DashboardStatsService: AppStoreDashboardStatsServing {}
extension WorkspaceToolService: AppStoreWorkspaceToolServing {}
