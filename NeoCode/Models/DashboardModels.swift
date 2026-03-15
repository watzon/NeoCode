import Foundation

enum AppContentSelection: Hashable {
    case dashboard
    case session(String)
}

struct DashboardProjectDescriptor: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let path: String

    nonisolated init(id: UUID, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    nonisolated init(project: ProjectSummary) {
        self.init(id: project.id, name: project.name, path: project.path)
    }
}

struct DashboardRemoteSessionDescriptor: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date

    nonisolated init(id: String, title: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    nonisolated init(session: OpenCodeSession, fallbackTitle: String = SessionSummary.defaultTitle) {
        let resolvedTitle = session.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (resolvedTitle?.isEmpty == false) ? resolvedTitle! : fallbackTitle
        self.init(
            id: session.id,
            title: title,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt
        )
    }
}

struct DashboardTokenTotals: Codable, Hashable, Sendable {
    var input: Int
    var output: Int
    var reasoning: Int
    var cacheRead: Int
    var cacheWrite: Int

    nonisolated init(input: Int = 0, output: Int = 0, reasoning: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.reasoning = reasoning
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    nonisolated static let zero = DashboardTokenTotals()

    nonisolated var total: Int {
        input + output + reasoning + cacheRead + cacheWrite
    }

    nonisolated mutating func formUnion(with other: DashboardTokenTotals) {
        input += other.input
        output += other.output
        reasoning += other.reasoning
        cacheRead += other.cacheRead
        cacheWrite += other.cacheWrite
    }

    nonisolated mutating func formUnion(with usage: OpenCodeTokenUsage?) {
        guard let usage else { return }
        input += usage.input
        output += usage.output
        reasoning += usage.reasoning
        cacheRead += usage.cache?.read ?? 0
        cacheWrite += usage.cache?.write ?? 0
    }
}

struct DashboardModelUsageSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var providerID: String
    var modelID: String
    var messageCount: Int
    var sessionCount: Int
    var totalCost: Double
    var tokens: DashboardTokenTotals
    var lastUsedAt: Date?

    nonisolated init(
        id: String,
        providerID: String,
        modelID: String,
        messageCount: Int = 0,
        sessionCount: Int = 0,
        totalCost: Double = 0,
        tokens: DashboardTokenTotals = .zero,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.providerID = providerID
        self.modelID = modelID
        self.messageCount = messageCount
        self.sessionCount = sessionCount
        self.totalCost = totalCost
        self.tokens = tokens
        self.lastUsedAt = lastUsedAt
    }

    nonisolated var displayName: String {
        "\(providerID)/\(modelID)"
    }
}

struct DashboardToolUsageSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var callCount: Int
    var sessionCount: Int
    var lastUsedAt: Date?

    nonisolated init(id: String, name: String, callCount: Int = 0, sessionCount: Int = 0, lastUsedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.callCount = callCount
        self.sessionCount = sessionCount
        self.lastUsedAt = lastUsedAt
    }
}

struct DashboardSessionStats: Codable, Hashable, Sendable {
    var totalMessages: Int
    var userMessages: Int
    var assistantMessages: Int
    var toolCalls: Int
    var totalCost: Double
    var tokens: DashboardTokenTotals
    var models: [DashboardModelUsageSummary]
    var tools: [DashboardToolUsageSummary]
    var firstActivityAt: Date?
    var lastActivityAt: Date?

    nonisolated init(
        totalMessages: Int = 0,
        userMessages: Int = 0,
        assistantMessages: Int = 0,
        toolCalls: Int = 0,
        totalCost: Double = 0,
        tokens: DashboardTokenTotals = .zero,
        models: [DashboardModelUsageSummary] = [],
        tools: [DashboardToolUsageSummary] = [],
        firstActivityAt: Date? = nil,
        lastActivityAt: Date? = nil
    ) {
        self.totalMessages = totalMessages
        self.userMessages = userMessages
        self.assistantMessages = assistantMessages
        self.toolCalls = toolCalls
        self.totalCost = totalCost
        self.tokens = tokens
        self.models = models
        self.tools = tools
        self.firstActivityAt = firstActivityAt
        self.lastActivityAt = lastActivityAt
    }
}

struct DashboardProjectCatalog: Codable, Hashable, Sendable {
    var descriptor: DashboardProjectDescriptor
    var knownSessionCount: Int
    var lastSessionScanAt: Date?

    nonisolated init(descriptor: DashboardProjectDescriptor, knownSessionCount: Int = 0, lastSessionScanAt: Date? = nil) {
        self.descriptor = descriptor
        self.knownSessionCount = knownSessionCount
        self.lastSessionScanAt = lastSessionScanAt
    }
}

struct DashboardSessionCacheEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var projectID: UUID
    var projectName: String
    var projectPath: String
    var sessionID: String
    var sessionTitle: String
    var createdAt: Date
    var updatedAt: Date
    var stats: DashboardSessionStats

    nonisolated init(
        projectID: UUID,
        projectName: String,
        projectPath: String,
        sessionID: String,
        sessionTitle: String,
        createdAt: Date,
        updatedAt: Date,
        stats: DashboardSessionStats
    ) {
        self.id = Self.cacheKey(projectPath: projectPath, sessionID: sessionID)
        self.projectID = projectID
        self.projectName = projectName
        self.projectPath = projectPath
        self.sessionID = sessionID
        self.sessionTitle = sessionTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.stats = stats
    }

    nonisolated static func cacheKey(projectPath: String, sessionID: String) -> String {
        "\(projectPath)::\(sessionID)"
    }
}

struct DashboardProjectUsageSummary: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var path: String
    var knownSessionCount: Int
    var indexedSessionCount: Int
    var totalMessages: Int
    var userMessages: Int
    var assistantMessages: Int
    var toolCalls: Int
    var totalCost: Double
    var tokens: DashboardTokenTotals
    var lastActivityAt: Date?
}

struct DashboardSnapshot: Codable, Hashable, Sendable {
    var generatedAt: Date
    var totalProjects: Int
    var knownSessionCount: Int
    var indexedSessionCount: Int
    var totalMessages: Int
    var userMessages: Int
    var assistantMessages: Int
    var toolCalls: Int
    var totalCost: Double
    var tokens: DashboardTokenTotals
    var topModels: [DashboardModelUsageSummary]
    var topTools: [DashboardToolUsageSummary]
    var projects: [DashboardProjectUsageSummary]
    var latestActivityAt: Date?
    var oldestActivityAt: Date?

    nonisolated var pendingSessionCount: Int {
        max(0, knownSessionCount - indexedSessionCount)
    }

    nonisolated var cacheCoverage: Double {
        guard knownSessionCount > 0 else { return 1 }
        return Double(indexedSessionCount) / Double(knownSessionCount)
    }
}

struct DashboardSessionIngress: Sendable {
    let project: DashboardProjectDescriptor
    let session: DashboardRemoteSessionDescriptor
    let messages: [OpenCodeMessageEnvelope]
}

struct DashboardRefreshPlan: Sendable {
    let changedSessions: [DashboardRemoteSessionDescriptor]
    let snapshot: DashboardSnapshot
}

struct DashboardRefreshStatus: Hashable {
    enum Phase: Hashable {
        case idle
        case priming
        case refreshing
        case failed
    }

    var phase: Phase
    var title: String
    var detail: String
    var processedSessions: Int
    var totalSessions: Int
    var currentProjectName: String?
    var currentSessionTitle: String?
    var lastUpdatedAt: Date?

    nonisolated static let idle = DashboardRefreshStatus(
        phase: .idle,
        title: "",
        detail: "",
        processedSessions: 0,
        totalSessions: 0,
        currentProjectName: nil,
        currentSessionTitle: nil,
        lastUpdatedAt: nil
    )

    nonisolated var isVisible: Bool {
        phase != .idle
    }

    nonisolated var progress: Double? {
        guard totalSessions > 0 else { return nil }
        return min(max(Double(processedSessions) / Double(totalSessions), 0), 1)
    }
}

struct DashboardStatsCache: Codable, Sendable {
    var catalogs: [DashboardProjectCatalog]
    var sessions: [DashboardSessionCacheEntry]
}
