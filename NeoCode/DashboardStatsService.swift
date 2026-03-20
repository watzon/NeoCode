import Foundation

actor DashboardStatsService {
    private let persistence: PersistedDashboardStatsStore

    private var hasLoadedCache = false
    private var catalogsByPath: [String: DashboardProjectCatalog] = [:]
    private var sessionsByKey: [String: DashboardSessionCacheEntry] = [:]

    init(persistence: PersistedDashboardStatsStore = PersistedDashboardStatsStore()) {
        self.persistence = persistence
    }

    func prepare(
        projects: [DashboardProjectDescriptor],
        range: DashboardTimeRange = .allTime,
        projectPath: String? = nil
    ) async -> DashboardSnapshot {
        await loadCacheIfNeeded()

        let activePaths = Set(projects.map(\.path))
        var nextCatalogs: [String: DashboardProjectCatalog] = [:]
        for descriptor in projects {
            var catalog = catalogsByPath[descriptor.path] ?? DashboardProjectCatalog(descriptor: descriptor)
            catalog.descriptor = descriptor
            nextCatalogs[descriptor.path] = catalog
        }

        catalogsByPath = nextCatalogs
        sessionsByKey = sessionsByKey.filter { activePaths.contains($0.value.projectPath) }
        await persist()
        return buildSnapshot(range: range, projectPath: projectPath)
    }

    func currentSnapshot(range: DashboardTimeRange = .allTime, projectPath: String? = nil) async -> DashboardSnapshot {
        await loadCacheIfNeeded()
        return buildSnapshot(range: range, projectPath: projectPath)
    }

    func planRefresh(
        for project: DashboardProjectDescriptor,
        sessions: [DashboardRemoteSessionDescriptor],
        forceSessionIDs: Set<String> = [],
        range: DashboardTimeRange = .allTime,
        projectPath: String? = nil
    ) async -> DashboardRefreshPlan {
        await loadCacheIfNeeded()

        var catalog = catalogsByPath[project.path] ?? DashboardProjectCatalog(descriptor: project)
        catalog.descriptor = project
        let cachedSessionCount = sessionsByKey.values.reduce(into: 0) { count, entry in
            guard entry.projectPath == project.path else { return }
            count += 1
        }
        catalog.knownSessionCount = max(sessions.count, cachedSessionCount)
        catalog.lastSessionScanAt = .now
        catalogsByPath[project.path] = catalog

        let changedSessions = sessions.filter { session in
            if forceSessionIDs.contains(session.id) {
                return true
            }
            let cacheKey = DashboardSessionCacheEntry.cacheKey(projectPath: project.path, sessionID: session.id)
            guard let cachedEntry = sessionsByKey[cacheKey] else { return true }
            return cachedEntry.updatedAt < session.updatedAt
        }

        await persist()
        return DashboardRefreshPlan(
            changedSessions: changedSessions,
            snapshot: buildSnapshot(range: range, projectPath: projectPath)
        )
    }

    func ingest(
        _ ingestions: [DashboardSessionIngress],
        range: DashboardTimeRange = .allTime,
        projectPath: String? = nil
    ) async -> DashboardSnapshot {
        await loadCacheIfNeeded()

        for ingress in ingestions {
            let entry = summarize(messages: ingress.messages, session: ingress.session, project: ingress.project)
            sessionsByKey[entry.id] = entry
        }

        await persist()
        return buildSnapshot(range: range, projectPath: projectPath)
    }

    private func loadCacheIfNeeded() async {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true

        guard let cache = await persistence.loadCache() else { return }
        catalogsByPath = Dictionary(uniqueKeysWithValues: cache.catalogs.map { ($0.descriptor.path, $0) })
        sessionsByKey = Dictionary(uniqueKeysWithValues: cache.sessions.map { ($0.id, $0) })
    }

    private func persist() async {
        let cache = DashboardStatsCache(
            catalogs: catalogsByPath.values.sorted { $0.descriptor.name.localizedCaseInsensitiveCompare($1.descriptor.name) == .orderedAscending },
            sessions: sessionsByKey.values.sorted { lhs, rhs in
                if lhs.projectName != rhs.projectName {
                    return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
                }
                return lhs.updatedAt > rhs.updatedAt
            }
        )
        await persistence.saveCache(cache)
    }

    private func summarize(
        messages: [OpenCodeMessageEnvelope],
        session: DashboardRemoteSessionDescriptor,
        project: DashboardProjectDescriptor
    ) -> DashboardSessionCacheEntry {
        var totalMessages = 0
        var userMessages = 0
        var assistantMessages = 0
        var toolCalls = 0
        var totalCost = 0.0
        var tokens = DashboardTokenTotals.zero
        var firstActivityAt: Date? = session.createdAt
        var lastActivityAt: Date? = session.updatedAt
        var models: [String: DashboardModelUsageSummary] = [:]
        var tools: [String: DashboardToolUsageSummary] = [:]

        for message in messages {
            totalMessages += 1
            let messageTimestamp = message.info.updatedAt ?? message.info.createdAt ?? session.updatedAt
            if let currentFirstActivityAt = firstActivityAt {
                firstActivityAt = min(currentFirstActivityAt, messageTimestamp)
            } else {
                firstActivityAt = messageTimestamp
            }
            if let currentLastActivityAt = lastActivityAt {
                lastActivityAt = max(currentLastActivityAt, messageTimestamp)
            } else {
                lastActivityAt = messageTimestamp
            }

            switch message.info.chatRole {
            case .user:
                userMessages += 1
            case .assistant:
                assistantMessages += 1
            case .tool, .system:
                break
            }

            if message.info.chatRole == .assistant {
                totalCost += message.info.cost ?? 0
                tokens.formUnion(with: message.info.tokens)

                let providerID = message.info.providerID?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let modelID = message.info.modelID?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let providerID,
                   !providerID.isEmpty,
                   let modelID,
                   !modelID.isEmpty {
                    let modelKey = "\(providerID)/\(modelID)"
                    var modelUsage = models[modelKey] ?? DashboardModelUsageSummary(
                        id: modelKey,
                        providerID: providerID,
                        modelID: modelID
                    )
                    modelUsage.messageCount += 1
                    modelUsage.sessionCount = 1
                    modelUsage.totalCost += message.info.cost ?? 0
                    modelUsage.tokens.formUnion(with: message.info.tokens)
                    modelUsage.lastUsedAt = max(modelUsage.lastUsedAt ?? .distantPast, messageTimestamp)
                    models[modelKey] = modelUsage
                }
            }

            for part in message.parts where part.type == .tool {
                let toolName = part.tool?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let toolName, !toolName.isEmpty else { continue }
                toolCalls += 1
                var toolUsage = tools[toolName] ?? DashboardToolUsageSummary(id: toolName, name: toolName)
                toolUsage.callCount += 1
                toolUsage.sessionCount = 1
                toolUsage.lastUsedAt = max(toolUsage.lastUsedAt ?? .distantPast, part.updatedAt ?? messageTimestamp)
                tools[toolName] = toolUsage
            }
        }

        let stats = DashboardSessionStats(
            totalMessages: totalMessages,
            userMessages: userMessages,
            assistantMessages: assistantMessages,
            toolCalls: toolCalls,
            totalCost: totalCost,
            tokens: tokens,
            models: models.values.sorted { $0.messageCount > $1.messageCount },
            tools: tools.values.sorted { $0.callCount > $1.callCount },
            firstActivityAt: firstActivityAt,
            lastActivityAt: lastActivityAt
        )

        return DashboardSessionCacheEntry(
            projectID: project.id,
            projectName: project.name,
            projectPath: project.path,
            sessionID: session.id,
            sessionTitle: session.title,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            stats: stats
        )
    }

    private func buildSnapshot(range: DashboardTimeRange, projectPath: String? = nil) -> DashboardSnapshot {
        let catalogs = catalogsByPath.values
            .filter { catalog in
                guard let projectPath else { return true }
                return catalog.descriptor.path == projectPath
            }
            .sorted { lhs, rhs in
            lhs.descriptor.name.localizedCaseInsensitiveCompare(rhs.descriptor.name) == .orderedAscending
        }
        let activePaths = Set(catalogs.map(\.descriptor.path))
        let entries = sessionsByKey.values.filter { entry in
            guard activePaths.contains(entry.projectPath) else { return false }
            let activityDate = entry.stats.lastActivityAt ?? entry.updatedAt
            return range.includes(activityDate)
        }

        var totalMessages = 0
        var userMessages = 0
        var assistantMessages = 0
        var toolCalls = 0
        var totalCost = 0.0
        var tokens = DashboardTokenTotals.zero
        var latestActivityAt: Date?
        var oldestActivityAt: Date?
        var modelUsageByKey: [String: DashboardModelUsageSummary] = [:]
        var toolUsageByKey: [String: DashboardToolUsageSummary] = [:]
        var projectUsageByPath: [String: DashboardProjectUsageSummary] = [:]

        for catalog in catalogs {
            projectUsageByPath[catalog.descriptor.path] = DashboardProjectUsageSummary(
                id: catalog.descriptor.id,
                name: catalog.descriptor.name,
                path: catalog.descriptor.path,
                knownSessionCount: catalog.knownSessionCount,
                indexedSessionCount: 0,
                totalMessages: 0,
                userMessages: 0,
                assistantMessages: 0,
                toolCalls: 0,
                totalCost: 0,
                tokens: .zero,
                lastActivityAt: nil
            )
        }

        for entry in entries {
            totalMessages += entry.stats.totalMessages
            userMessages += entry.stats.userMessages
            assistantMessages += entry.stats.assistantMessages
            toolCalls += entry.stats.toolCalls
            totalCost += entry.stats.totalCost
            tokens.formUnion(with: entry.stats.tokens)

            if let lastActivity = entry.stats.lastActivityAt {
                latestActivityAt = max(latestActivityAt ?? .distantPast, lastActivity)
            }
            if let firstActivity = entry.stats.firstActivityAt {
                oldestActivityAt = min(oldestActivityAt ?? .distantFuture, firstActivity)
            }

            if var projectUsage = projectUsageByPath[entry.projectPath] {
                projectUsage.indexedSessionCount += 1
                projectUsage.totalMessages += entry.stats.totalMessages
                projectUsage.userMessages += entry.stats.userMessages
                projectUsage.assistantMessages += entry.stats.assistantMessages
                projectUsage.toolCalls += entry.stats.toolCalls
                projectUsage.totalCost += entry.stats.totalCost
                projectUsage.tokens.formUnion(with: entry.stats.tokens)
                projectUsage.lastActivityAt = max(projectUsage.lastActivityAt ?? .distantPast, entry.stats.lastActivityAt ?? entry.updatedAt)
                projectUsageByPath[entry.projectPath] = projectUsage
            }

            for model in entry.stats.models {
                var aggregate = modelUsageByKey[model.id] ?? DashboardModelUsageSummary(
                    id: model.id,
                    providerID: model.providerID,
                    modelID: model.modelID
                )
                aggregate.messageCount += model.messageCount
                aggregate.sessionCount += model.sessionCount
                aggregate.totalCost += model.totalCost
                aggregate.tokens.formUnion(with: model.tokens)
                aggregate.lastUsedAt = max(aggregate.lastUsedAt ?? .distantPast, model.lastUsedAt ?? .distantPast)
                modelUsageByKey[model.id] = aggregate
            }

            for tool in entry.stats.tools {
                var aggregate = toolUsageByKey[tool.id] ?? DashboardToolUsageSummary(id: tool.id, name: tool.name)
                aggregate.callCount += tool.callCount
                aggregate.sessionCount += tool.sessionCount
                aggregate.lastUsedAt = max(aggregate.lastUsedAt ?? .distantPast, tool.lastUsedAt ?? .distantPast)
                toolUsageByKey[tool.id] = aggregate
            }
        }

        let knownSessionCount = catalogs.reduce(0) { $0 + $1.knownSessionCount }
        let indexedSessionCount = entries.count

        let normalizedOldestActivityAt = oldestActivityAt

        return DashboardSnapshot(
            generatedAt: .now,
            totalProjects: catalogs.count,
            knownSessionCount: knownSessionCount,
            indexedSessionCount: indexedSessionCount,
            totalMessages: totalMessages,
            userMessages: userMessages,
            assistantMessages: assistantMessages,
            toolCalls: toolCalls,
            totalCost: totalCost,
            tokens: tokens,
            topModels: modelUsageByKey.values.sorted {
                if $0.messageCount == $1.messageCount {
                    return $0.tokens.total > $1.tokens.total
                }
                return $0.messageCount > $1.messageCount
            },
            topTools: toolUsageByKey.values.sorted {
                if $0.callCount == $1.callCount {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.callCount > $1.callCount
            },
            projects: projectUsageByPath.values.sorted {
                let lhsDate = $0.lastActivityAt ?? .distantPast
                let rhsDate = $1.lastActivityAt ?? .distantPast
                if lhsDate == rhsDate {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return lhsDate > rhsDate
            },
            latestActivityAt: latestActivityAt,
            oldestActivityAt: normalizedOldestActivityAt
        )
    }
}
