import Foundation
import Testing
@testable import NeoCode

@MainActor
@Suite(.serialized)
struct AppStoreSessionTests {
        @Test func projectsContextUsageFromCompactionSummary() throws {
            let envelopes: [OpenCodeMessageEnvelope] = try decode(
                """
                [
                  {
                    "info": {
                      "id": "msg_compact_request",
                      "sessionID": "ses_usage",
                      "role": "user",
                      "time": {
                        "created": "2026-03-13T10:07:00Z",
                        "completed": "2026-03-13T10:07:00Z"
                      }
                    },
                    "parts": [
                      {
                        "id": "part_compact",
                        "sessionID": "ses_usage",
                        "messageID": "msg_compact_request",
                        "type": "compaction",
                        "time": {
                          "created": "2026-03-13T10:07:00Z",
                          "completed": "2026-03-13T10:07:00Z"
                        }
                      }
                    ]
                  },
                  {
                    "info": {
                      "id": "msg_compact_summary",
                      "sessionID": "ses_usage",
                      "role": "assistant",
                      "summary": true,
                      "providerID": "openai",
                      "modelID": "gpt-5.4",
                      "cost": 0.6,
                      "tokens": {
                        "total": 238085,
                        "input": 236945,
                        "output": 1140,
                        "reasoning": 0,
                        "cache": {
                          "read": 0,
                          "write": 0
                        }
                      },
                      "time": {
                        "created": "2026-03-13T10:07:10Z",
                        "completed": "2026-03-13T10:07:12Z"
                      }
                    },
                    "parts": [
                      {
                        "id": "part_summary",
                        "sessionID": "ses_usage",
                        "messageID": "msg_compact_summary",
                        "type": "text",
                        "text": "## Goal\\nContinue the feature work.",
                        "time": {
                          "created": "2026-03-13T10:07:10Z",
                          "completed": "2026-03-13T10:07:12Z"
                        }
                      }
                    ]
                  }
                ]
                """
            )
    
            let transcript = ChatMessage.makeTranscript(from: envelopes)
            let stats = SessionStatsSnapshot.make(
                sessionID: "ses_usage",
                messageInfos: envelopes.map(\.info),
                models: [
                    ComposerModelOption(
                        id: "openai/gpt-5.4",
                        providerID: "openai",
                        modelID: "gpt-5.4",
                        title: "GPT-5.4",
                        contextWindow: 262_144,
                        variants: ["high"]
                    )
                ],
                transcript: transcript
            )
    
            let resolved = try #require(stats)
            #expect(resolved.isProjectedAfterCompaction)
            #expect(resolved.totalContextTokens == 238085)
            #expect(resolved.contextUsedTokens == 1145)
            #expect(resolved.remainingContextTokens == 260999)
            #expect(resolved.percentUsed == 0)
        }

        @Test func dashboardStatsPreserveCachedSessionsWhenSessionListOmitsOlderOnes() async throws {
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let persistence = PersistedDashboardStatsStore(baseDirectoryURL: tempDirectory)
            let service = DashboardStatsService(persistence: persistence)
            let project = DashboardProjectDescriptor(id: UUID(), name: "NeoCode", path: "/tmp/neocode")
    
            _ = await service.prepare(projects: [project])
    
            let olderSession = DashboardRemoteSessionDescriptor(
                id: "ses_old",
                title: "Older session",
                createdAt: date("2026-03-01T10:00:00Z"),
                updatedAt: date("2026-03-01T10:05:00Z")
            )
            let newerSession = DashboardRemoteSessionDescriptor(
                id: "ses_new",
                title: "Newer session",
                createdAt: date("2026-03-08T10:00:00Z"),
                updatedAt: date("2026-03-08T10:05:00Z")
            )
    
            _ = await service.ingest([
                DashboardSessionIngress(project: project, session: olderSession, messages: try dashboardMessages(sessionID: "ses_old", totalTokens: 600_000_000, updatedAt: "2026-03-01T10:05:00Z")),
                DashboardSessionIngress(project: project, session: newerSession, messages: try dashboardMessages(sessionID: "ses_new", totalTokens: 500_000_000, updatedAt: "2026-03-08T10:05:00Z")),
            ])
    
            let snapshotBefore = await service.currentSnapshot()
            #expect(snapshotBefore.tokens.total == 1_100_000_000)
            #expect(snapshotBefore.indexedSessionCount == 2)
    
            let plan = await service.planRefresh(for: project, sessions: [newerSession])
    
            #expect(plan.snapshot.tokens.total == 1_100_000_000)
            #expect(plan.snapshot.indexedSessionCount == 2)
            #expect(plan.snapshot.knownSessionCount == 2)
            #expect(plan.changedSessions.isEmpty)
        }

        @Test func dashboardStatsCanBeFilteredByPresetRanges() async throws {
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let persistence = PersistedDashboardStatsStore(baseDirectoryURL: tempDirectory)
            let service = DashboardStatsService(persistence: persistence)
            let project = DashboardProjectDescriptor(id: UUID(), name: "NeoCode", path: "/tmp/neocode")
    
            _ = await service.prepare(projects: [project])
    
            let recentDate = isoDateString(from: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now)
            let olderDate = isoDateString(from: Calendar.current.date(byAdding: .day, value: -45, to: .now) ?? .now)
    
            _ = await service.ingest([
                DashboardSessionIngress(project: project, session: DashboardRemoteSessionDescriptor(id: "ses_recent", title: "Recent", createdAt: date(recentDate), updatedAt: date(recentDate)), messages: try dashboardMessages(sessionID: "ses_recent", totalTokens: 200, updatedAt: recentDate)),
                DashboardSessionIngress(project: project, session: DashboardRemoteSessionDescriptor(id: "ses_old", title: "Old", createdAt: date(olderDate), updatedAt: date(olderDate)), messages: try dashboardMessages(sessionID: "ses_old", totalTokens: 800, updatedAt: olderDate)),
            ])
    
            let lastThirtyDays = await service.currentSnapshot(range: .thirtyDays)
            let allTime = await service.currentSnapshot(range: .allTime)
    
            #expect(lastThirtyDays.tokens.total == 200)
            #expect(lastThirtyDays.indexedSessionCount == 1)
            #expect(allTime.tokens.total == 1_000)
            #expect(allTime.indexedSessionCount == 2)
        }

        @Test func dashboardStatsCanBeFilteredToSingleProject() async throws {
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let persistence = PersistedDashboardStatsStore(baseDirectoryURL: tempDirectory)
            let service = DashboardStatsService(persistence: persistence)
            let projectA = DashboardProjectDescriptor(id: UUID(), name: "NeoCode", path: "/tmp/neocode")
            let projectB = DashboardProjectDescriptor(id: UUID(), name: "Docs", path: "/tmp/docs")
    
            _ = await service.prepare(projects: [projectA, projectB])
    
            _ = await service.ingest([
                DashboardSessionIngress(project: projectA, session: DashboardRemoteSessionDescriptor(id: "ses_a", title: "NeoCode", createdAt: date("2026-03-10T10:00:00Z"), updatedAt: date("2026-03-10T10:00:00Z")), messages: try dashboardMessages(sessionID: "ses_a", totalTokens: 200, updatedAt: "2026-03-10T10:00:00Z")),
                DashboardSessionIngress(project: projectB, session: DashboardRemoteSessionDescriptor(id: "ses_b", title: "Docs", createdAt: date("2026-03-11T10:00:00Z"), updatedAt: date("2026-03-11T10:00:00Z")), messages: try dashboardMessages(sessionID: "ses_b", totalTokens: 800, updatedAt: "2026-03-11T10:00:00Z")),
            ])
    
            let filtered = await service.currentSnapshot(projectPath: projectA.path)
    
            #expect(filtered.totalProjects == 1)
            #expect(filtered.projects.count == 1)
            #expect(filtered.projects.first?.id == projectA.id)
            #expect(filtered.tokens.total == 200)
            #expect(filtered.indexedSessionCount == 1)
        }

        @Test func groupsCompactionMarkerAndSummaryIntoCompactionSection() {
            let now = Date(timeIntervalSince1970: 1_710_616_186)
            let groups = buildDisplayMessageGroups(from: [
                ChatMessage(id: "part_user", messageID: "msg_user", role: .user, text: "Hello", timestamp: now, emphasis: .normal),
                ChatMessage(id: "part_compact", messageID: "msg_compact", role: .system, text: "Session compacted", timestamp: now, emphasis: .subtle, kind: .compactionMarker),
                ChatMessage(id: "part_summary", messageID: "msg_summary", role: .assistant, text: "## Goal\nContinue the feature work.", timestamp: now, emphasis: .normal, isSummaryMessage: true),
            ])
    
            #expect(groups.count == 2)
            guard case .compaction(let messages) = groups[1] else {
                Issue.record("Expected a compaction display group")
                return
            }
    
            #expect(messages.count == 2)
            #expect(messages[0].kind.isCompactionMarker)
            #expect(messages[1].isSummaryMessage)
        }

        @Test func projectSummarySupportsShowingMoreThanDefaultSidebarLimit() {
            let sessions = (0..<10).map { index in
                SessionSummary(
                    id: "ses_\(index)",
                    title: "Session \(index)",
                    lastUpdatedAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            }
            let project = ProjectSummary(name: "NeoCode", path: "/tmp/NeoCode", sessions: sessions)
    
            #expect(project.sessions.count == 10)
            #expect(project.displayedSessions().count == 8)
            #expect(project.displayedSessions().map(\.id) == Array(sessions.reversed().prefix(8)).map(\.id))
            #expect(project.hasHiddenSessions)
            #expect(project.hiddenSessionCount == 2)
            #expect(project.displayedSessions(showAll: true).map(\.id) == sessions.reversed().map(\.id))
        }

        @Test func projectSummaryOrdersDisplayedSessionsBySidebarActivityDate() {
            let sessions = [
                SessionSummary(
                    id: "ses_old",
                    title: "Old",
                    lastUpdatedAt: Date(timeIntervalSince1970: 300)
                ),
                SessionSummary(
                    id: "ses_finished",
                    title: "Finished",
                    lastUpdatedAt: Date(timeIntervalSince1970: 100),
                    lastSidebarActivityAt: Date(timeIntervalSince1970: 400)
                ),
                SessionSummary(
                    id: "ses_running",
                    title: "Running",
                    lastUpdatedAt: Date(timeIntervalSince1970: 350),
                    lastSidebarActivityAt: Date(timeIntervalSince1970: 200)
                ),
            ]
    
            let project = ProjectSummary(name: "NeoCode", path: "/tmp/NeoCode", sessions: sessions)
    
            #expect(project.displayedSessions(showAll: true).map(\.id) == ["ses_finished", "ses_old", "ses_running"])
        }

        @Test func sessionSummaryOmitsPlaceholderTitlesWhenCreatingRemoteSessions() {
            let draft = SessionSummary(id: "draft", title: "New session", lastUpdatedAt: .distantPast, isEphemeral: true)
            let timestamped = SessionSummary(id: "draft-2", title: "New session - 2026-03-13T10:00:00Z", lastUpdatedAt: .distantPast, isEphemeral: true)
            let capitalizedTimestamped = SessionSummary(id: "draft-4", title: "New Session - 2026-03-13T10:00:00Z", lastUpdatedAt: .distantPast, isEphemeral: true)
            let renamed = SessionSummary(id: "draft-3", title: "Scratchpad", lastUpdatedAt: .distantPast, isEphemeral: true)
    
            #expect(draft.requestedServerTitle == nil)
            #expect(timestamped.requestedServerTitle == nil)
            #expect(capitalizedTimestamped.requestedServerTitle == nil)
            #expect(renamed.requestedServerTitle == "Scratchpad")
        }

        @Test func sessionSummaryInfersTitleFromCapitalizedPlaceholderThreadName() {
            let session = SessionSummary(id: "ses_1", title: "New Session - 2026-03-13T10:00:00Z", lastUpdatedAt: .distantPast)
            let transcript = [
                ChatMessage(
                    id: "msg_1",
                    role: .user,
                    text: "Investigate optimistic sending latency",
                    timestamp: .distantPast,
                    emphasis: .normal
                )
            ]
    
            #expect(session.applyingInferredTitle(from: transcript).title == "Investigate optimistic sending latency")
        }

        @MainActor
        @Test func appStoreUsesExternalBusyStatusWithoutLocalActivity() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
            store.selectSession("ses_1")
    
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .busy))
    
            #expect(store.selectedSession?.status == .running)
            #expect(store.selectedSessionActivity == .busy)
        }

        @MainActor
        @Test func appStoreUsesExternalBusyStatusForSnapshotInProgressTranscript() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Existing",
                            lastUpdatedAt: .distantPast,
                            transcript: [
                                ChatMessage(
                                    id: "part_1",
                                    role: .assistant,
                                    text: "Partial response",
                                    timestamp: .now,
                                    emphasis: .normal,
                                    isInProgress: true
                                ),
                            ]
                        ),
                    ]
                ),
            ])
            store.selectSession("ses_1")
    
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .busy))
    
            #expect(store.selectedSession?.status == .running)
            #expect(store.selectedSessionActivity == .busy)
        }

        @MainActor
        @Test func appStoreClearsStaleBusyStatusWhenFinalToolPartCompletes() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])

            store.selectSession("ses_1")
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .busy))
            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "tool_1",
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
                    status: .running,
                    input: .object(["command": .string("sleep 30 &")]),
                    output: nil,
                    error: nil
                ),
                time: OpenCodeTimeContainer(created: .now, updated: .now, completed: nil)
            )))

            #expect(store.selectedSession?.status == .running)
            #expect(store.selectedSessionActivity == .busy)

            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "tool_1",
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
                    input: .object(["command": .string("sleep 30 &")]),
                    output: .string("started"),
                    error: nil
                ),
                time: OpenCodeTimeContainer(created: .now, updated: .now, completed: .now)
            )))

            #expect(store.selectedSession?.status == .idle)
            #expect(store.selectedSessionActivity == nil)
        }

        @MainActor
        @Test func appStoreClearsBackgroundWorkingBadgeWhenCompletedPartArrives() async throws {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Background", lastUpdatedAt: .distantPast),
                        SessionSummary(id: "ses_2", title: "Foreground", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
            store.selectSession("ses_2")
    
            store.apply(event: .messagePartDelta(OpenCodePartDelta(
                sessionID: "ses_1",
                messageID: "msg_1",
                partID: "part_1",
                field: "text",
                delta: "Working"
            )))
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .busy))
    
            let completed = try OpenCodeEventDecoder.decode(
                frame: OpenCodeSSEFrame(
                    event: "message.part.updated",
                    data: "{\"type\":\"message.part.updated\",\"properties\":{\"part\":{\"id\":\"part_1\",\"sessionID\":\"ses_1\",\"messageID\":\"msg_1\",\"type\":\"text\",\"text\":\"Done\",\"tool\":null,\"state\":null,\"time\":{\"created\":\"2026-03-13T10:10:00Z\",\"updated\":\"2026-03-13T10:10:01Z\",\"completed\":\"2026-03-13T10:10:02Z\"}}}}"
                )
            )
    
            store.apply(event: completed)
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            let background = try #require(store.projects[0].sessions.first(where: { $0.id == "ses_1" }))
            #expect(background.status == .idle)
    
            store.selectSession("ses_1")
            #expect(store.selectedSession?.status == .idle)
            #expect(store.selectedSessionActivity == nil)
        }

        @MainActor
        @Test func appStoreBumpsSessionUIRevisionWhenSessionStatusChanges() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            let initialRevision = store.sessionUIRevision
    
            store.apply(event: .messagePartDelta(OpenCodePartDelta(
                sessionID: "ses_1",
                messageID: "msg_1",
                partID: "part_1",
                field: "text",
                delta: "Working"
            )))
            let runningRevision = store.sessionUIRevision
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(runningRevision > initialRevision)
            #expect(store.sessionUIRevision > runningRevision)
        }

        @MainActor
        @Test func appStoreShowsFinishedIndicatorForBackgroundCompletionUntilVisited() async throws {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Background", lastUpdatedAt: .distantPast),
                        SessionSummary(id: "ses_2", title: "Foreground", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
            store.selectSession("ses_2")
    
            store.apply(event: .messagePartDelta(OpenCodePartDelta(
                sessionID: "ses_1",
                messageID: "msg_1",
                partID: "part_1",
                field: "text",
                delta: "Working"
            )))
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .busy))
    
            let completed = try OpenCodeEventDecoder.decode(
                frame: OpenCodeSSEFrame(
                    event: "message.part.updated",
                    data: "{\"type\":\"message.part.updated\",\"properties\":{\"part\":{\"id\":\"part_1\",\"sessionID\":\"ses_1\",\"messageID\":\"msg_1\",\"type\":\"text\",\"text\":\"Done\",\"tool\":null,\"state\":null,\"time\":{\"created\":\"2026-03-13T10:10:00Z\",\"updated\":\"2026-03-13T10:10:01Z\",\"completed\":\"2026-03-13T10:10:02Z\"}}}}"
                )
            )
    
            store.apply(event: completed)
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(store.projects[0].sessions.first(where: { $0.id == "ses_1" })?.status == .idle)
            #expect(store.showsFinishedIndicator(for: "ses_1") == true)
    
            store.selectSession("ses_1")
    
            #expect(store.showsFinishedIndicator(for: "ses_1") == false)
        }

        @MainActor
        @Test func appStoreDoesNotShowFinishedIndicatorForSelectedSessionCompletion() async throws {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Foreground", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
            store.selectSession("ses_1")
    
            store.apply(event: .messagePartDelta(OpenCodePartDelta(
                sessionID: "ses_1",
                messageID: "msg_1",
                partID: "part_1",
                field: "text",
                delta: "Working"
            )))
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .busy))
    
            let completed = try OpenCodeEventDecoder.decode(
                frame: OpenCodeSSEFrame(
                    event: "message.part.updated",
                    data: "{\"type\":\"message.part.updated\",\"properties\":{\"part\":{\"id\":\"part_1\",\"sessionID\":\"ses_1\",\"messageID\":\"msg_1\",\"type\":\"text\",\"text\":\"Done\",\"tool\":null,\"state\":null,\"time\":{\"created\":\"2026-03-13T10:10:00Z\",\"updated\":\"2026-03-13T10:10:01Z\",\"completed\":\"2026-03-13T10:10:02Z\"}}}}"
                )
            )
    
            store.apply(event: completed)
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(store.selectedSession?.status == .idle)
            #expect(store.showsFinishedIndicator(for: "ses_1") == false)
        }

        @MainActor
        @Test func appStoreMovesCompletedBackgroundSessionToTopOfSidebarOrdering() async throws {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Background",
                            lastUpdatedAt: Date(timeIntervalSince1970: 100),
                            lastSidebarActivityAt: Date(timeIntervalSince1970: 100),
                            status: .running
                        ),
                        SessionSummary(
                            id: "ses_2",
                            title: "Foreground",
                            lastUpdatedAt: Date(timeIntervalSince1970: 200),
                            lastSidebarActivityAt: Date(timeIntervalSince1970: 200)
                        ),
                    ]
                ),
            ])
            store.selectSession("ses_2")
    
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .busy))
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(store.projects[0].displayedSessions(showAll: true).map(\.id) == ["ses_1", "ses_2"])
        }

        @MainActor
        @Test func appStoreShowsFailedIndicatorForBackgroundFailureUntilVisited() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Background", lastUpdatedAt: .distantPast),
                        SessionSummary(id: "ses_2", title: "Foreground", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
            store.selectSession("ses_2")
    
            store.apply(event: .messagePartDelta(OpenCodePartDelta(
                sessionID: "ses_1",
                messageID: "msg_1",
                partID: "part_1",
                field: "text",
                delta: "Working"
            )))
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .busy))
            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "tool_1",
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
                    status: .error,
                    input: nil,
                    output: nil,
                    error: "Permission denied"
                ),
                time: OpenCodeTimeContainer(created: .now, updated: .now, completed: .now)
            )))
    
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(store.projects[0].sessions.first(where: { $0.id == "ses_1" })?.status == .error)
            #expect(store.showsFailedIndicator(for: "ses_1") == true)
    
            store.selectSession("ses_1")
    
            #expect(store.showsFailedIndicator(for: "ses_1") == false)
        }

        @MainActor
        @Test func appStoreDoesNotShowFailedIndicatorForSelectedSessionFailure() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Foreground",
                            lastUpdatedAt: .distantPast,
                            status: .running,
                            transcript: [
                                ChatMessage(
                                    id: "tool_1",
                                    role: .tool,
                                    text: "bash failed",
                                    timestamp: .now,
                                    emphasis: .subtle,
                                    kind: .toolCall(
                                        ChatMessage.ToolCall(
                                            name: "bash",
                                            status: .error,
                                            detail: "Permission denied",
                                            error: "Permission denied"
                                        )
                                    )
                                ),
                            ]
                        ),
                    ]
                ),
            ])
            store.selectSession("ses_1")
    
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(store.selectedSession?.status == .error)
            #expect(store.showsFailedIndicator(for: "ses_1") == false)
        }

        @MainActor
        @Test func appStoreSettlesInProgressTranscriptWhenSessionTurnsIdle() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Existing",
                            lastUpdatedAt: .distantPast,
                            status: .running,
                            transcript: [
                                ChatMessage(
                                    id: "part_1",
                                    messageID: "msg_1",
                                    role: .assistant,
                                    text: "Done",
                                    timestamp: .now,
                                    emphasis: .normal,
                                    isInProgress: true
                                ),
                            ]
                        ),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(store.selectedSession?.status == .idle)
            #expect(store.selectedSessionIsActivelyResponding == false)
            #expect(store.selectedTranscript.first?.isInProgress == false)
        }

        @MainActor
        @Test func appStoreStopSessionClearsActiveStateImmediately() async {
            let projectID = UUID()
            let store = AppStore(projects: [
                ProjectSummary(
                    id: projectID,
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Existing",
                            lastUpdatedAt: .distantPast,
                            status: .running,
                            transcript: [
                                ChatMessage(
                                    id: "part_1",
                                    messageID: "msg_1",
                                    role: .assistant,
                                    text: "Streaming",
                                    timestamp: .now,
                                    emphasis: .normal,
                                    isInProgress: true
                                ),
                            ]
                        ),
                    ]
                ),
            ])
            let service = MockNeoCodeService()
    
            store.selectSession("ses_1")
    
            let didStop = await store.stopSession(sessionID: "ses_1", projectID: projectID, using: service)
    
            #expect(didStop == true)
            #expect(service.abortedSessionIDs == ["ses_1"])
            #expect(store.projects[0].sessions[0].status == .idle)
        }

        @MainActor
        @Test func appStoreActivationIncrementsLifecycleRefreshToken() {
            let store = AppStore(projects: [])
    
            let initialToken = store.lifecycleRefreshToken
            store.handleApplicationDidBecomeActive()
    
            #expect(store.lifecycleRefreshToken == initialToken + 1)
        }

        @MainActor
        @Test func appStoreBatchesTextDeltasBeforeUpdatingTranscript() async {
            let store = AppStore(
                projects: [
                    ProjectSummary(
                        name: "NeoCode",
                        path: "/tmp/NeoCode",
                        sessions: [
                            SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                        ]
                    ),
                ],
                performanceOptions: AppStorePerformanceOptions(
                    projectPersistenceDebounce: .seconds(1),
                    streamingPersistenceDebounce: .seconds(1),
                    deltaFlushDebounce: .milliseconds(40)
                )
            )
            store.selectSession("ses_1")
    
            store.apply(event: .messagePartDelta(OpenCodePartDelta(sessionID: "ses_1", messageID: "msg_1", partID: "part_1", field: "text", delta: "Hello")))
            store.apply(event: .messagePartDelta(OpenCodePartDelta(sessionID: "ses_1", messageID: "msg_1", partID: "part_1", field: "text", delta: " world")))
    
            #expect(store.selectedTranscript.isEmpty == true)
            #expect(store.debugBufferedTextDeltaCount == 1)
    
            try? await Task.sleep(for: .milliseconds(80))
    
            #expect(store.selectedTranscript.count == 1)
            #expect(store.selectedTranscript.first?.text == "Hello world")
            #expect(store.debugBufferedTextDeltaCount == 0)
        }

        @MainActor
        @Test func appStoreCreatesAndDeletesSessionsFromEvents() async {
            let store = AppStore(projects: [ProjectSummary(name: "NeoCode", path: "/tmp/NeoCode")])
    
            store.apply(event: .sessionCreated(OpenCodeSession(id: "ses_new", title: "New Session", parentID: nil, time: OpenCodeTimeContainer(created: Date(), updated: Date(), completed: nil))))
            #expect(store.projects[0].sessions.count == 1)
            #expect(store.projects[0].sessions[0].id == "ses_new")
    
            store.apply(event: .sessionDeleted("ses_new"))
            #expect(store.projects[0].sessions.isEmpty)
        }

        @MainActor
        @Test func appStoreIgnoresStaleSessionUpdatesAfterDeletionEvent() async {
            let now = Date()
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_new", title: "New Session", lastUpdatedAt: now),
                    ]
                ),
            ])

            store.selectSession("ses_new")
            store.apply(event: .sessionDeleted("ses_new"))
            #expect(store.projects[0].sessions.isEmpty)

            store.apply(event: .sessionUpdated(
                OpenCodeSession(
                    id: "ses_new",
                    title: "New Session",
                    parentID: nil,
                    time: OpenCodeTimeContainer(created: now, updated: now.addingTimeInterval(5), completed: nil)
                )
            ))

            #expect(store.projects[0].sessions.isEmpty)
            #expect(store.selectedSessionID == nil)
        }

        @MainActor
        @Test func appStoreTracksPendingPermissionsAndClearsThemAfterReply() async {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            store.apply(
                event: .permissionAsked(
                    OpenCodePermissionRequest(
                        id: "perm_1",
                        sessionID: "ses_1",
                        permission: "bash",
                        patterns: ["git status"],
                        metadata: [
                            "command": .string("git status"),
                            "description": .string("Shows working tree status"),
                        ],
                        always: ["git status"],
                        tool: nil
                    )
                )
            )
    
            #expect(store.pendingPermission(for: "ses_1")?.id == "perm_1")
            #expect(store.selectedSession?.status == .awaitingInput)
    
            store.apply(
                event: .permissionReplied(
                    OpenCodePermissionReplyEvent(sessionID: "ses_1", requestID: "perm_1", reply: .once)
                )
            )
    
            #expect(store.pendingPermission(for: "ses_1") == nil)
            #expect(store.selectedSession?.status == .idle)
        }

        @MainActor
        @Test func appStoreCanToggleYoloModePerSession() async {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode-auto-respond",
                    sessions: [
                        SessionSummary(id: "ses_edit", title: "Existing", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            #expect(store.isYoloModeEnabled(for: "ses_edit") == false)
    
            store.setYoloMode(true, for: "ses_edit")
            #expect(store.isYoloModeEnabled(for: "ses_edit") == true)
    
            store.setYoloMode(false, for: "ses_edit")
            #expect(store.isYoloModeEnabled(for: "ses_edit") == false)
        }

        @MainActor
        @Test func appStoreResolvesYoloModeForInactiveSessionAcrossProjects() async {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "Workspace A",
                    path: "/tmp/Workspace-A",
                    sessions: [
                        SessionSummary(id: "ses_a", title: "Session A", lastUpdatedAt: .distantPast),
                    ]
                ),
                ProjectSummary(
                    name: "Workspace B",
                    path: "/tmp/Workspace-B",
                    sessions: [
                        SessionSummary(id: "ses_b", title: "Session B", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            store.selectSession("ses_a")
            store.setYoloMode(true, for: "ses_a")
    
            store.selectSession("ses_b")
    
            #expect(store.isYoloModeEnabled(for: "ses_a") == true)
            #expect(store.isYoloModeEnabled(for: "ses_b") == false)
        }

        @MainActor
        @Test func appStoreTracksPendingQuestionsAndClearsThemAfterReply() async {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            store.apply(
                event: .questionAsked(
                    OpenCodeQuestionRequest(
                        id: "que_1",
                        sessionID: "ses_1",
                        questions: [
                            OpenCodeQuestionInfo(
                                question: "Did the question prompt render?",
                                header: "Prompt",
                                options: [
                                    OpenCodeQuestionOption(label: "Yes", description: "It rendered"),
                                    OpenCodeQuestionOption(label: "No", description: "It did not render"),
                                ],
                                multiple: false,
                                custom: true
                            ),
                        ],
                        tool: nil
                    )
                )
            )
    
            #expect(store.pendingQuestion(for: "ses_1")?.id == "que_1")
            #expect(store.selectedSession?.status == .awaitingInput)
    
            store.apply(
                event: .questionReplied(
                    OpenCodeQuestionReplyEvent(sessionID: "ses_1", requestID: "que_1", answers: [["Yes"]])
                )
            )
    
            #expect(store.pendingQuestion(for: "ses_1") == nil)
            #expect(store.selectedSession?.status == .idle)
        }

        @MainActor
        @Test func appStoreDeduplicatesCachedSessionsOnInitialization() async {
            let transcript = [
                ChatMessage(
                    id: "msg_1",
                    role: .user,
                    text: "Fix the duplicated thread bug",
                    timestamp: Date(timeIntervalSince1970: 100),
                    emphasis: .normal
                ),
            ]
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "New session",
                            lastUpdatedAt: Date(timeIntervalSince1970: 200),
                            status: .idle,
                            transcript: []
                        ),
                        SessionSummary(
                            id: "ses_1",
                            title: "New session",
                            lastUpdatedAt: Date(timeIntervalSince1970: 150),
                            status: .running,
                            transcript: transcript
                        ),
                    ]
                ),
            ])
    
            #expect(store.projects[0].sessions.count == 1)
            #expect(store.projects[0].sessions[0].id == "ses_1")
            #expect(store.projects[0].sessions[0].transcript.isEmpty == true)
            #expect(store.transcript(for: "ses_1") == transcript)
            #expect(store.projects[0].sessions[0].status == .running)
            #expect(store.projects[0].sessions[0].title == "Fix the duplicated thread bug")
        }

        @MainActor
        @Test func appStorePrefersExplicitTitlesWhenDeduplicatingSessions() async {
            let transcript = [
                ChatMessage(
                    id: "msg_1",
                    role: .user,
                    text: "Placeholder title should not win",
                    timestamp: Date(timeIntervalSince1970: 100),
                    emphasis: .normal
                ),
            ]
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Server session",
                            lastUpdatedAt: Date(timeIntervalSince1970: 220),
                            status: .idle,
                            transcript: []
                        ),
                        SessionSummary(
                            id: "ses_1",
                            title: "New session",
                            lastUpdatedAt: Date(timeIntervalSince1970: 180),
                            status: .running,
                            transcript: transcript
                        ),
                    ]
                ),
            ])
    
            #expect(store.projects[0].sessions.count == 1)
            #expect(store.projects[0].sessions[0].title == "Server session")
            #expect(store.projects[0].sessions[0].transcript.isEmpty == true)
            #expect(store.transcript(for: "ses_1") == transcript)
            #expect(store.projects[0].sessions[0].status == .running)
        }

        @MainActor
        @Test func appStorePreservesExistingSessionTitleWhenServerTitleIsMissing() async {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Real Title", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            store.apply(
                event: .sessionUpdated(
                    OpenCodeSession(
                        id: "ses_1",
                        title: nil,
                        parentID: nil,
                        time: OpenCodeTimeContainer(created: Date(), updated: Date(), completed: nil)
                    )
                )
            )
    
            #expect(store.projects[0].sessions[0].title == "Real Title")
        }

        @MainActor
        @Test func appStorePreservesSessionStatsWhenServerSessionUpdateArrives() async {
            let snapshot = SessionStatsSnapshot(
                sessionID: "ses_1",
                providerID: "openai",
                modelID: "gpt-5.4",
                modelTitle: "GPT-5.4",
                contextWindow: 200_000,
                projectedContextTokens: nil,
                totalContextTokens: 40_000,
                inputTokens: 20_000,
                outputTokens: 15_000,
                reasoningTokens: 3_000,
                cacheReadTokens: 1_500,
                cacheWriteTokens: 500,
                totalCost: 1.25,
                lastActivityAt: .now
            )
    
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast, stats: snapshot),
                    ]
                ),
            ])
    
            store.apply(
                event: .sessionUpdated(
                    OpenCodeSession(
                        id: "ses_1",
                        title: "Existing",
                        parentID: nil,
                        time: OpenCodeTimeContainer(created: Date(), updated: Date(), completed: nil)
                    )
                )
            )
    
            #expect(store.projects[0].sessions[0].stats == snapshot)
        }

        @MainActor
        @Test func appStorePreservesPerModelReasoningAcrossNonReasoningModelSwitches() async {
            let store = AppStore(projects: [])
            store.availableModels = [
                ComposerModelOption(
                    id: "openai/gpt-5.4",
                    providerID: "openai",
                    modelID: "gpt-5.4",
                    title: "GPT-5.4",
                    contextWindow: nil,
                    variants: ["high", "medium", "low"]
                ),
                ComposerModelOption(
                    id: "anthropic/claude-sonnet",
                    providerID: "anthropic",
                    modelID: "claude-sonnet",
                    title: "Claude Sonnet",
                    contextWindow: nil,
                    variants: []
                ),
            ]
    
            store.selectedModelID = "openai/gpt-5.4"
            store.refreshThinkingLevels()
            store.selectedThinkingLevel = "medium"
    
            store.selectedModelID = "anthropic/claude-sonnet"
            store.refreshThinkingLevels()
    
            #expect(store.availableThinkingLevels.isEmpty)
            #expect(store.selectedThinkingLevel == "medium")
    
            store.selectedModelID = "openai/gpt-5.4"
            store.refreshThinkingLevels()
    
            #expect(store.availableThinkingLevels == ["low", "medium", "high"])
            #expect(store.selectedThinkingLevel == "medium")
        }

        @MainActor
        @Test func appStoreInfersPlaceholderTitleFromFirstUserMessage() async {
            let now = Date()
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "New session", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            store.apply(
                event: .messageUpdated(
                    OpenCodeMessageInfo(
                        id: "msg_1",
                        sessionID: "ses_1",
                        role: "user",
                        summary: nil,
                        agent: nil,
                        providerID: nil,
                        modelID: nil,
                        cost: nil,
                        tokens: nil,
                        time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
                    )
                )
            )
            store.apply(
                event: .messagePartUpdated(
                    OpenCodePart(
                        id: "part_1",
                        sessionID: "ses_1",
                        messageID: "msg_1",
                        type: .text,
                        text: "Fix session naming so new chats stop getting stuck on placeholders",
                        tool: nil,
                        mime: nil,
                        filename: nil,
                        url: nil,
                        source: nil,
                        state: nil,
                        time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
                    )
                )
            )
    
            #expect(store.projects[0].sessions[0].title == "Fix session naming so new chats stop getting stuck on placeholders")
        }

        @MainActor
        @Test func appStoreUsesExplicitSessionStatusOverTranscriptHeuristics() async {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Existing",
                            lastUpdatedAt: .distantPast,
                            status: .running,
                            transcript: [
                                ChatMessage(
                                    id: "part_1",
                                    role: .assistant,
                                    text: "Still here",
                                    timestamp: .now,
                                    emphasis: .normal,
                                    isInProgress: true
                                ),
                            ]
                        ),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(store.selectedSession?.status == .idle)
        }

        @MainActor
        @Test func appStoreMapsRetryStatusToRetryingWhenSessionIsActive() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            store.apply(event: .messagePartDelta(OpenCodePartDelta(
                sessionID: "ses_1",
                messageID: "msg_1",
                partID: "part_1",
                field: "text",
                delta: "Working"
            )))
            store.apply(event: .sessionStatusChanged(
                sessionID: "ses_1",
                status: .retry(attempt: 1, message: "Rate limited", next: 2)
            ))
    
            #expect(store.selectedSession?.status == .retrying)
    
            guard case .retry(let attempt, let message, let next)? = store.selectedSessionActivity else {
                Issue.record("Expected selectedSessionActivity to reflect retrying state")
                return
            }
    
            #expect(attempt == 1)
            #expect(message == "Rate limited")
            #expect(next == 2)
        }

        @MainActor
        @Test func appStoreTreatsAbortedToolErrorsAsIdleWhenSessionStops() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Existing",
                            lastUpdatedAt: .distantPast,
                            status: .running,
                            transcript: [
                                ChatMessage(
                                    id: "tool_1",
                                    role: .tool,
                                    text: "bash failed",
                                    timestamp: .now,
                                    emphasis: .subtle,
                                    kind: .toolCall(
                                        ChatMessage.ToolCall(
                                            name: "bash",
                                            status: .error,
                                            detail: "Tool execution aborted",
                                            error: "Tool execution aborted"
                                        )
                                    )
                                ),
                            ]
                        ),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(store.selectedSession?.status == .idle)
        }

        @MainActor
        @Test func appStoreTreatsRejectedQuestionToolErrorsAsIdleWhenSessionStops() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Existing",
                            lastUpdatedAt: .distantPast,
                            status: .running,
                            transcript: [
                                ChatMessage(
                                    id: "tool_1",
                                    role: .tool,
                                    text: "question cancelled",
                                    timestamp: .now,
                                    emphasis: .subtle,
                                    kind: .toolCall(
                                        ChatMessage.ToolCall(
                                            name: "functions.question",
                                            status: .error,
                                            detail: "QuestionRejectedError",
                                            error: "QuestionRejectedError"
                                        )
                                    )
                                ),
                            ]
                        ),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(store.selectedSession?.status == .idle)
        }

        @MainActor
        @Test func appStoreTreatsRejectedPermissionToolErrorsAsIdleWhenSessionStops() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Existing",
                            lastUpdatedAt: .distantPast,
                            status: .running,
                            transcript: [
                                ChatMessage(
                                    id: "tool_1",
                                    role: .tool,
                                    text: "read failed",
                                    timestamp: .now,
                                    emphasis: .subtle,
                                    kind: .toolCall(
                                        ChatMessage.ToolCall(
                                            name: "read",
                                            status: .error,
                                            detail: "The user rejected permission to use this specific tool call.",
                                            error: "The user rejected permission to use this specific tool call."
                                        )
                                    )
                                ),
                            ]
                        ),
                    ]
                ),
            ])

            store.selectSession("ses_1")
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))

            #expect(store.selectedSession?.status == .idle)
        }

        @MainActor
        @Test func appStoreMarksNonAbortedToolErrorsAsFailed() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Existing",
                            lastUpdatedAt: .distantPast,
                            status: .running,
                            transcript: [
                                ChatMessage(
                                    id: "tool_1",
                                    role: .tool,
                                    text: "bash failed",
                                    timestamp: .now,
                                    emphasis: .subtle,
                                    kind: .toolCall(
                                        ChatMessage.ToolCall(
                                            name: "bash",
                                            status: .error,
                                            detail: "Permission denied",
                                            error: "Permission denied"
                                        )
                                    )
                                ),
                            ]
                        ),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(store.selectedSession?.status == .error)
        }

        @MainActor
        @Test func appStoreEagerlyCreatesServerBackedSessionsWhenServiceIsAvailable() async throws {
            let store = AppStore(projects: [ProjectSummary(name: "NeoCode", path: "/tmp/NeoCode")])
            let now = Date()
            let service = MockNeoCodeService(
                createdSession: OpenCodeSession(
                    id: "ses_created",
                    title: nil,
                    parentID: nil,
                    time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
                )
            )
    
            let createdSessionID = await store.createSession(in: store.projects[0].id, using: service)
    
            #expect(createdSessionID == "ses_created")
            let session = try #require(store.selectedSession)
            #expect(session.title == "New session")
            #expect(session.id == "ses_created")
            #expect(session.isEphemeral == false)
            #expect(store.projects[0].sessions.count == 1)
            #expect(service.createdSessionTitles == [nil])
        }

        @MainActor
        @Test func chatMessageFileAttachmentRoundTripsThroughCodable() async throws {
            let message = ChatMessage(
                id: "file_1",
                role: .user,
                text: "diagram.png",
                timestamp: Date(timeIntervalSince1970: 100),
                emphasis: .normal,
                attachment: ChatAttachment(filename: "diagram.png", mimeType: "image/png", url: "data:image/png;base64,AAAA")
            )
    
            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
    
            #expect(decoded == message)
        }

        @MainActor
        @Test func composerAttachmentImportsPastedImagesAsFiles() async throws {
            let imageData = Data([0x89, 0x50, 0x4E, 0x47])
    
            let attachments = await ComposerAttachment.makeAttachments(
                from: [.imageData(imageData, filename: "Pasted Image.png", mimeType: "image/png")]
            )
    
            let attachment = try #require(attachments.first)
            #expect(attachments.count == 1)
            #expect(attachment.mimeType == "image/png")
    
            switch attachment.content {
            case .file(let path):
                let fileURL = URL(fileURLWithPath: path)
                #expect(fileURL.pathExtension == "png")
                let persistedData = try Data(contentsOf: fileURL)
                #expect(persistedData == imageData)
                try? FileManager.default.removeItem(at: fileURL)
            case .dataURL:
                Issue.record("Expected pasted images to be stored as files")
            }
        }

        @MainActor
        @Test func editingQueuedDraftSwapsCurrentComposerContent() async throws {
            let projectID = UUID()
            let store = AppStore(projects: [
                ProjectSummary(
                    id: projectID,
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast, status: .running),
                    ]
                ),
            ])
            let service = MockNeoCodeService()
    
            store.selectSession("ses_1")
            store.draft = "Queued follow-up"
            _ = await store.sendDraft(
                using: service,
                projectID: projectID,
                sessionID: "ses_1",
                allowQueueIfRunning: true
            )
    
            let queuedID = try #require(store.queuedMessages(for: "ses_1").first?.id)
            store.draft = "Work in progress"
    
            store.editQueuedMessage(id: queuedID, in: "ses_1")
    
            #expect(store.draft == "Queued follow-up")
            #expect(store.queuedMessages(for: "ses_1").count == 1)
            #expect(store.queuedMessages(for: "ses_1").first?.text == "Work in progress")
        }

        @MainActor
        @Test func appStoreRestoresTranscriptIfEditedResendFails() async {
            let projectID = UUID()
            let originalTranscript = [
                ChatMessage(
                    id: "part_user_1",
                    messageID: "msg_user_1",
                    role: .user,
                    text: "Original prompt",
                    timestamp: Date(timeIntervalSince1970: 100),
                    emphasis: .normal
                ),
                ChatMessage(
                    id: "part_assistant_1",
                    messageID: "msg_assistant_1",
                    role: .assistant,
                    text: "Original reply",
                    timestamp: Date(timeIntervalSince1970: 110),
                    emphasis: .normal
                ),
            ]
            let store = AppStore(projects: [
                ProjectSummary(
                    id: projectID,
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Existing",
                            lastUpdatedAt: Date(timeIntervalSince1970: 110),
                            transcript: originalTranscript
                        ),
                    ]
                ),
            ])
            let service = MockNeoCodeService(sendPromptError: TestFailure.failed("send failed"))
    
            store.selectSession("ses_1")
            let didSend = await store.resendEditedMessage(
                messageID: "part_user_1",
                newText: "Updated prompt",
                in: "ses_1",
                projectID: projectID,
                using: service
            )
    
            #expect(didSend == false)
            #expect(service.revertedMessageID == "msg_user_1")
            #expect(service.unrevertedSessionIDs == ["ses_1"])
            #expect(store.selectedTranscript == originalTranscript)
            #expect(store.lastError == "send failed")
        }

        @MainActor
        @Test func appStoreKeepsPendingSessionWhenSelectingAnotherSession() async throws {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_existing", title: "Existing", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            await store.createSession(using: OpenCodeRuntime())
            let ephemeralID = try #require(store.selectedSession?.id)
    
            store.selectSession("ses_existing")
    
            #expect(store.selectedSessionID == "ses_existing")
            #expect(store.projects[0].sessions.count == 2)
            #expect(store.projects[0].sessions.contains(where: { $0.id == ephemeralID }) == true)
        }

        @MainActor
        @Test func appStoreRenamesAndDeletesEphemeralSessionLocally() async throws {
            let store = AppStore(projects: [ProjectSummary(name: "NeoCode", path: "/tmp/NeoCode")])
            let runtime = OpenCodeRuntime()
    
            await store.createSession(using: runtime)
            let ephemeralID = try #require(store.selectedSession?.id)
    
            await store.renameSession(ephemeralID, to: "Scratchpad", using: runtime)
            #expect(store.selectedSession?.title == "Scratchpad")
            #expect(store.selectedSession?.isEphemeral == true)
    
            await store.deleteSession(ephemeralID, using: runtime)
            #expect(store.projects[0].sessions.isEmpty)
            #expect(store.selectedSessionID == nil)
        }

        @MainActor
        @Test func promotedSessionAliasesKeepSidebarActionsAddressable() async throws {
            let store = AppStore(projects: [ProjectSummary(name: "NeoCode", path: "/tmp/NeoCode")])
            let runtime = OpenCodeRuntime()
            let now = Date()
    
            await store.createSession(using: runtime)
            let projectID = try #require(store.selectedProjectID)
            let ephemeralID = try #require(store.selectedSessionID)
    
            await store.promoteEphemeralSession(
                ephemeralID,
                in: projectID,
                to: OpenCodeSession(
                    id: "ses_promoted",
                    title: nil,
                    parentID: nil,
                    time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
                )
            )
    
            let resolvedSession = try #require(store.sessionSummary(for: ephemeralID))
            #expect(resolvedSession.id == "ses_promoted")
            #expect(store.project(for: ephemeralID)?.id == projectID)
    
            store.selectSession(ephemeralID)
            #expect(store.selectedSessionID == "ses_promoted")
        }

        @MainActor
        @Test func selectingProjectDoesNotAutoSelectFirstThread() async {
            let firstProject = ProjectSummary(
                id: UUID(),
                name: "NeoCode",
                path: "/tmp/NeoCode",
                sessions: [
                    SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                ]
            )
            let secondProject = ProjectSummary(
                id: UUID(),
                name: "Docs",
                path: "/tmp/Docs",
                sessions: [
                    SessionSummary(id: "ses_2", title: "Imported", lastUpdatedAt: .distantPast),
                ]
            )
            let store = AppStore(projects: [firstProject, secondProject])
    
            store.selectSession("ses_1")
            store.selectProject(secondProject.id)
    
            #expect(store.selectedProjectID == secondProject.id)
            #expect(store.selectedSessionID == nil)
        }

        @MainActor
        @Test func appStoreMovesProjectsBeforeAnotherProject() {
            let firstProject = ProjectSummary(id: UUID(), name: "NeoCode", path: "/tmp/NeoCode")
            let secondProject = ProjectSummary(id: UUID(), name: "Docs", path: "/tmp/Docs")
            let thirdProject = ProjectSummary(id: UUID(), name: "Site", path: "/tmp/Site")
            let store = AppStore(projects: [firstProject, secondProject, thirdProject])
    
            store.selectProject(secondProject.id)
            store.moveProject(thirdProject.id, before: firstProject.id)
    
            #expect(store.projects.map(\.id) == [thirdProject.id, firstProject.id, secondProject.id])
            #expect(store.selectedProjectID == secondProject.id)
        }

        @MainActor
        @Test func appStoreMovesProjectsToEnd() {
            let firstProject = ProjectSummary(id: UUID(), name: "NeoCode", path: "/tmp/NeoCode")
            let secondProject = ProjectSummary(id: UUID(), name: "Docs", path: "/tmp/Docs")
            let thirdProject = ProjectSummary(id: UUID(), name: "Site", path: "/tmp/Site")
            let store = AppStore(projects: [firstProject, secondProject, thirdProject])
    
            store.moveProjectToEnd(firstProject.id)
    
            #expect(store.projects.map(\.id) == [secondProject.id, thirdProject.id, firstProject.id])
            #expect(store.selectedProjectID == firstProject.id)
        }

        @MainActor
        @Test func selectingUncachedSessionShowsColdLoadState() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
    
            #expect(store.loadingTranscriptSessionID == "ses_1")
        }

        @MainActor
        @Test func appStoreStartsOnDashboardWithoutSelectingInitialThread() async {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_existing", title: "Existing", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            #expect(store.isDashboardSelected == true)
            #expect(store.selectedProjectID == store.projects.first?.id)
            #expect(store.selectedSessionID == nil)
        }

        @MainActor
        @Test func appStoreReturnsToPreviousWorkspaceSelectionWhenClosingSettings() {
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            store.openSettings()
    
            #expect(store.isSettingsSelected == true)
            #expect(store.selectedSettingsSection == .general)
            #expect(store.selectedSessionID == nil)
    
            store.selectSettingsSection(.general)
            #expect(store.selectedSettingsSection == .general)
    
            store.closeSettings()
    
            #expect(store.isSettingsSelected == false)
            #expect(store.selectedSessionID == "ses_1")
        }

        @MainActor
        @Test func appStoreReconcilesBackToLastSelectedModelWhenModelListReloads() {
            let store = AppStore(projects: [])
            let preferredModel = ComposerModelOption(
                id: "anthropic/claude-sonnet",
                providerID: "anthropic",
                modelID: "claude-sonnet",
                title: "Claude Sonnet",
                contextWindow: nil,
                variants: []
            )
            let fallbackModel = ComposerModelOption(
                id: "openai/gpt-5.4",
                providerID: "openai",
                modelID: "gpt-5.4",
                title: "GPT-5.4",
                contextWindow: nil,
                variants: ["high", "medium", "low"]
            )
    
            store.availableModels = [preferredModel, fallbackModel]
            store.setModelForCurrentAgent(preferredModel.id)
            store.selectedModelID = "missing/model"
    
            store.reconcileSelectedModel(using: store.availableModels)
    
            #expect(store.selectedModelID == preferredModel.id)
        }

        @MainActor
        @Test func appStoreKeepsSelectedModelScopedToEachSession() {
            let projectID = UUID()
            let fallbackModel = ComposerModelOption(
                id: "openai/gpt-5.4",
                providerID: "openai",
                modelID: "gpt-5.4",
                title: "GPT-5.4",
                contextWindow: nil,
                variants: ["high", "medium", "low"]
            )
            let preferredModel = ComposerModelOption(
                id: "anthropic/claude-sonnet",
                providerID: "anthropic",
                modelID: "claude-sonnet",
                title: "Claude Sonnet",
                contextWindow: nil,
                variants: []
            )
            let store = AppStore(projects: [
                ProjectSummary(
                    id: projectID,
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Session 1", lastUpdatedAt: .distantPast),
                        SessionSummary(id: "ses_2", title: "Session 2", lastUpdatedAt: .distantPast),
                    ]
                ),
            ])
    
            store.availableModels = [fallbackModel, preferredModel]
    
            store.selectSession("ses_1")
            store.setModelForCurrentAgent(preferredModel.id)
            store.refreshThinkingLevels()
    
            store.selectSession("ses_2")
            #expect(store.selectedModelID == fallbackModel.id)
    
            store.selectSession("ses_1")
            #expect(store.selectedModelID == preferredModel.id)
        }

        @MainActor
        @Test func appStoreUsesGeneralWorkspaceToolDefaultWhenProjectOverrideIsMissing() {
            let store = AppStore(projects: [
                ProjectSummary(name: "NeoCode", path: "/tmp/NeoCode")
            ])
    
            store.updateGeneral { general in
                general.defaultWorkspaceToolID = "dev.zed.Zed"
            }
    
            #expect(
                store.preferredWorkspaceToolID(
                    for: store.projects.first?.id,
                    availableToolIDs: ["dev.zed.Zed", "com.apple.finder"]
                ) == "dev.zed.Zed"
            )
        }

        @MainActor
        @Test func chatMessageToolCallRoundTripsThroughCodable() async throws {
            let message = ChatMessage(
                id: "tool_1",
                role: .tool,
                text: "read completed",
                timestamp: Date(timeIntervalSince1970: 100),
                emphasis: .subtle,
                kind: .toolCall(
                    ChatMessage.ToolCall(
                        name: "read",
                        status: .completed,
                        detail: "ok",
                        input: .object(["path": .string("README.md")]),
                        output: .object(["ok": .bool(true)])
                    )
                ),
                isInProgress: false
            )
    
            let data = try JSONEncoder().encode(message)
            let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
    
            #expect(decoded == message)
        }

        @Test func localCompactSlashCommandSupportsSummarizeAlias() {
            #expect(LocalComposerSlashCommand.compact.matches(name: "compact"))
            #expect(LocalComposerSlashCommand.compact.matches(name: "summarize"))
        }
}
