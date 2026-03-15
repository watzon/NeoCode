import Foundation
import Testing
@testable import NeoCode

@Suite(.serialized)
struct NeoCodeCoreTests {
    @Test func decodesSessionsAndBuildsTranscript() throws {
        let sessions: [OpenCodeSession] = try decode(
            """
            [
              {
                "id": "ses_1",
                "title": "Runtime Adapter",
                "parentID": null,
                "time": {
                  "created": "2026-03-13T10:00:00Z",
                  "updated": "2026-03-13T10:05:00Z",
                  "completed": null
                }
              }
            ]
            """
        )

        #expect(sessions.count == 1)
        #expect(sessions[0].id == "ses_1")
        #expect(sessions[0].title == "Runtime Adapter")

        let envelopes: [OpenCodeMessageEnvelope] = try decode(
            """
            [
              {
                "info": {
                  "id": "msg_1",
                  "sessionID": "ses_1",
                  "role": "assistant",
                  "agent": "builder",
                  "modelID": "claude-sonnet",
                  "time": {
                    "created": "2026-03-13T10:06:00Z",
                    "updated": "2026-03-13T10:06:01Z",
                    "completed": null
                  }
                },
                "parts": [
                  {
                    "id": "part_1",
                    "sessionID": "ses_1",
                    "messageID": "msg_1",
                    "type": "reasoning",
                    "text": "Thinking: checking the event model.",
                    "tool": null,
                    "state": null,
                    "time": {
                      "created": "2026-03-13T10:06:00Z",
                      "updated": "2026-03-13T10:06:01Z",
                      "completed": null
                    }
                  },
                  {
                    "id": "part_2",
                    "sessionID": "ses_1",
                    "messageID": "msg_1",
                    "type": "tool",
                    "text": null,
                    "tool": "read",
                    "state": {
                      "status": "completed",
                      "input": {"path": "ContentView.swift"},
                      "output": {"ok": true},
                      "error": null
                    },
                    "time": {
                      "created": "2026-03-13T10:06:02Z",
                      "updated": "2026-03-13T10:06:03Z",
                      "completed": "2026-03-13T10:06:03Z"
                    }
                  }
                ]
              }
            ]
            """
        )

        let transcript = ChatMessage.makeTranscript(from: envelopes)
        #expect(transcript.count == 2)
        switch transcript[0].role {
        case .assistant: break
        default: Issue.record("Expected assistant transcript role")
        }
        switch transcript[0].emphasis {
        case .strong: break
        default: Issue.record("Expected strong reasoning emphasis")
        }
        switch transcript[1].role {
        case .tool: break
        default: Issue.record("Expected tool transcript role")
        }
        #expect(transcript[1].text.contains("read completed"))
    }

    @Test func parsesSSEFramesIntoDomainEvents() throws {
        var parser = OpenCodeSSEParser()
        #expect(parser.ingest(line: "event: message.part.updated") == nil)
        #expect(parser.ingest(line: "data: {\"type\":\"message.part.updated\",\"properties\":{\"part\":{\"id\":\"part_1\",\"sessionID\":\"ses_1\",\"messageID\":\"msg_1\",\"type\":\"text\",\"text\":\"Hello\",\"tool\":null,\"state\":null,\"time\":{\"created\":\"2026-03-13T10:00:00Z\",\"updated\":\"2026-03-13T10:00:01Z\",\"completed\":null}}}}") == nil)
        let flushed = parser.ingest(line: "")
        let frame = try #require(flushed)
        let event = try OpenCodeEventDecoder.decode(frame: frame)

        switch event {
        case .messagePartUpdated(let part):
            #expect(part.id == "part_1")
            #expect(part.renderedText == "Hello")
        default:
            Issue.record("Expected message.part.updated event")
        }
    }

    @Test func parsesMultiLineSSEPayloadsBeforeFlushing() throws {
        var parser = OpenCodeSSEParser()

        #expect(parser.ingest(line: "event: message.part.updated") == nil)
        #expect(parser.ingest(line: "data: {\"type\":\"message.part.updated\",\"properties\":{") == nil)
        #expect(parser.ingest(line: "data: \"part\":{\"id\":\"part_1\",\"sessionID\":\"ses_1\",\"messageID\":\"msg_1\",\"type\":\"text\",\"text\":\"Hello\",\"tool\":null,\"state\":null,\"time\":{\"created\":\"2026-03-13T10:00:00Z\",\"updated\":\"2026-03-13T10:00:01Z\",\"completed\":null}}}}") == nil)
        let flushed = parser.ingest(line: "")
        let frame = try #require(flushed)
        let event = try OpenCodeEventDecoder.decode(frame: frame)

        switch event {
        case .messagePartUpdated(let part):
            #expect(part.id == "part_1")
            #expect(part.renderedText == "Hello")
        default:
            Issue.record("Expected message.part.updated event")
        }
    }

    @MainActor
    @Test func decodesSessionStatusEvents() async throws {
        let event = try OpenCodeEventDecoder.decode(
            frame: OpenCodeSSEFrame(
                event: "session.status",
                data: "{\"type\":\"session.status\",\"properties\":{\"sessionID\":\"ses_1\",\"status\":{\"type\":\"busy\"}}}"
            )
        )

        switch event {
        case .sessionStatusChanged(let sessionID, let status):
            #expect(sessionID == "ses_1")
            #expect(status == .busy)
        default:
            Issue.record("Expected session.status event")
        }
    }

    @MainActor
    @Test func decodesPermissionAskedEvents() async throws {
        let event = try OpenCodeEventDecoder.decode(
            frame: OpenCodeSSEFrame(
                event: "permission.asked",
                data: "{\"type\":\"permission.asked\",\"properties\":{\"id\":\"perm_1\",\"sessionID\":\"ses_1\",\"permission\":\"bash\",\"patterns\":[\"git status\"],\"metadata\":{\"command\":\"git status\",\"description\":\"Shows working tree status\"},\"always\":[\"git status\"]}}"
            )
        )

        switch event {
        case .permissionAsked(let request):
            #expect(request.id == "perm_1")
            #expect(request.sessionID == "ses_1")
            #expect(request.permission == "bash")
            #expect(request.patterns == ["git status"])
        default:
            Issue.record("Expected permission.asked event")
        }
    }

    @MainActor
    @Test func decodesQuestionAskedEvents() async throws {
        let event = try OpenCodeEventDecoder.decode(
            frame: OpenCodeSSEFrame(
                event: "question.asked",
                data: "{\"type\":\"question.asked\",\"properties\":{\"id\":\"que_1\",\"sessionID\":\"ses_1\",\"questions\":[{\"question\":\"Did the tool UI show up?\",\"header\":\"Quick Check\",\"options\":[{\"label\":\"Yes\",\"description\":\"It rendered\"},{\"label\":\"No\",\"description\":\"It did not render\"}],\"multiple\":false}]}}"
            )
        )

        switch event {
        case .questionAsked(let request):
            #expect(request.id == "que_1")
            #expect(request.sessionID == "ses_1")
            #expect(request.questions.count == 1)
            #expect(request.questions[0].header == "Quick Check")
            #expect(request.questions[0].options.map(\.label) == ["Yes", "No"])
        default:
            Issue.record("Expected question.asked event")
        }
    }

    @Test func decodesSlashCommands() throws {
        let commands: [OpenCodeCommand] = try decode(
            """
            [
              {
                "name": "review",
                "description": "Review the current working tree",
                "agent": "builder",
                "model": "openai/gpt-5.4",
                "source": "skill",
                "template": "Please review $1",
                "subtask": true,
                "hints": ["$1"]
              }
            ]
            """
        )
        #expect(commands.count == 1)
        #expect(commands[0].id == "review")
        #expect(commands[0].trimmedDescription == "Review the current working tree")
        #expect(commands[0].source == "skill")
        #expect(commands[0].hints == ["$1"])
    }

    @Test func projectSummaryLimitsDisplayedSessionsToEight() {
        let sessions = (0..<10).map { index in
            SessionSummary(
                id: "ses_\(index)",
                title: "Session \(index)",
                lastUpdatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let project = ProjectSummary(name: "NeoCode", path: "/tmp/NeoCode", sessions: sessions)

        #expect(project.sessions.count == 10)
        #expect(project.displayedSessions.count == 8)
        #expect(project.displayedSessions.map(\.id) == Array(sessions.prefix(8)).map(\.id))
    }

    @Test func sessionSummaryOmitsPlaceholderTitlesWhenCreatingRemoteSessions() {
        let draft = SessionSummary(id: "draft", title: "New session", lastUpdatedAt: .distantPast, isEphemeral: true)
        let timestamped = SessionSummary(id: "draft-2", title: "New session - 2026-03-13T10:00:00Z", lastUpdatedAt: .distantPast, isEphemeral: true)
        let renamed = SessionSummary(id: "draft-3", title: "Scratchpad", lastUpdatedAt: .distantPast, isEphemeral: true)

        #expect(draft.requestedServerTitle == nil)
        #expect(timestamped.requestedServerTitle == nil)
        #expect(renamed.requestedServerTitle == "Scratchpad")
    }

    @Test func runtimeCapsStartupOutputBufferToRecentTail() {
        let existing = String(repeating: "a", count: 8)
        let chunk = String(repeating: "b", count: 8)

        let result = OpenCodeRuntime.cappedOutputBuffer(existing, appending: chunk, limit: 10)

        #expect(result.count == 10)
        #expect(result == "aabbbbbbbb")
    }

    @Test func runtimeUsesTrimmedRecentOutputSnippet() {
        let snippet = OpenCodeRuntime.recentOutputSnippet(from: "\n\n  hello world  \n", limit: 5)

        #expect(snippet == "world")
    }

    @MainActor
    @Test func gitRepositoryStatusChoosesPrimaryActionFromChangesAndAheadCount() {
        let changed = GitRepositoryStatus(isRepository: true, hasChanges: true, aheadCount: 0)
        let ahead = GitRepositoryStatus(isRepository: true, hasChanges: false, aheadCount: 2)
        let clean = GitRepositoryStatus(isRepository: true, hasChanges: false, aheadCount: 0)

        #expect(changed.primaryAction == .commit)
        #expect(changed.isPrimaryActionEnabled == true)
        #expect(ahead.primaryAction == .push)
        #expect(ahead.isPrimaryActionEnabled == true)
        #expect(clean.primaryAction == .commit)
        #expect(clean.isPrimaryActionEnabled == false)
    }

}

@Suite(.serialized)
struct NeoCodeMainActorTests {

    @MainActor
    @Test func appStoreAppliesStreamingEventsToSelectedSession() async throws {
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

        let event = try OpenCodeEventDecoder.decode(
            frame: OpenCodeSSEFrame(
                event: "message.part.updated",
                data: "{\"type\":\"message.part.updated\",\"properties\":{\"part\":{\"id\":\"part_live\",\"sessionID\":\"ses_1\",\"messageID\":\"msg_1\",\"type\":\"reasoning\",\"text\":\"Thinking: streaming\",\"tool\":null,\"state\":null,\"time\":{\"created\":\"2026-03-13T10:10:00Z\",\"updated\":\"2026-03-13T10:10:01Z\",\"completed\":null}}}}"
            )
        )

        store.apply(event: event)

        #expect(store.selectedSession?.transcript.count == 1)
        #expect(store.selectedSession?.transcript.first?.text == "Thinking: streaming")
        #expect(store.selectedSession?.status == .running)
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
        #expect(store.selectedSession?.status == .attention)

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
        #expect(store.selectedSession?.status == .attention)

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
        #expect(store.projects[0].sessions[0].transcript == transcript)
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
        #expect(store.projects[0].sessions[0].transcript == transcript)
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
                    agent: nil,
                    modelID: nil,
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
    @Test func appStoreCreatesEphemeralSessionsWithDefaultTitle() async throws {
        let store = AppStore(projects: [ProjectSummary(name: "NeoCode", path: "/tmp/NeoCode")])

        await store.createSession(using: OpenCodeRuntime())

        let session = try #require(store.selectedSession)
        #expect(session.title == "New session")
        #expect(session.isEphemeral == true)
        #expect(store.projects[0].sessions.count == 1)
    }

    @MainActor
    @Test func appStoreClearsVisibleDraftImmediatelyWhenCreatingNewSession() async throws {
        let store = AppStore(projects: [
            ProjectSummary(
                name: "NeoCode",
                path: "/tmp/NeoCode",
                sessions: [
                    SessionSummary(id: "ses_existing", title: "Existing", lastUpdatedAt: .distantPast),
                ]
            ),
        ])

        store.selectSession("ses_existing")
        store.draft = "Previous thread text"

        await store.createSession(using: OpenCodeRuntime())

        #expect(store.selectedSession?.isEphemeral == true)
        #expect(store.draft == "")
    }

    @MainActor
    @Test func appStoreResendsEditedUserMessagesByRevertingAndReplacingLaterTranscript() async {
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
        let service = MockOpenCodeService()

        store.selectSession("ses_1")
        let didSend = await store.resendEditedMessage(
            messageID: "part_user_1",
            newText: "Updated prompt",
            in: "ses_1",
            projectID: projectID,
            using: service
        )

        #expect(didSend == true)
        #expect(service.revertedSessionID == "ses_1")
        #expect(service.revertedMessageID == "msg_user_1")
        #expect(service.unrevertedSessionIDs.isEmpty)
        #expect(service.sentPrompts.count == 1)
        #expect(service.sentPrompts[0].sessionID == "ses_1")
        #expect(service.sentPrompts[0].text == "Updated prompt")
        #expect(service.sentPrompts[0].attachments.isEmpty)
        #expect(store.selectedSession?.transcript.count == 1)
        #expect(store.selectedSession?.transcript.first?.text == "Updated prompt")
        #expect(store.selectedSession?.transcript.first?.id.hasPrefix("optimistic-user-") == true)
        #expect(store.selectedSession?.status == .running)
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
    @Test func openCodeClientPostsPromptAttachments() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { MockURLProtocol.requestHandler = nil }
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request

            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else {
                throw URLError(.badServerResponse)
            }

            return (response, Data("{}".utf8))
        }

        let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
        let client = OpenCodeClient(
            connection: OpenCodeRuntime.Connection(
                projectPath: "/tmp/NeoCode",
                baseURL: baseURL,
                username: "user",
                password: "pass",
                version: "1.0.0"
            ),
            session: session
        )

        try await client.sendPromptAsync(
            sessionID: "ses_1",
            text: "Look at this",
            attachments: [
                ComposerAttachment(
                    name: "diagram.png",
                    mimeType: "image/png",
                    content: .dataURL("data:image/png;base64,AAAA")
                ),
            ],
            options: nil
        )

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/session/ses_1/prompt_async")

        let bodyData = try requestBodyData(from: request)
        let body = try #require(bodyData)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let parts = try #require(payload?["parts"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[1]["type"] as? String == "file")
        #expect(parts[1]["mime"] as? String == "image/png")
        #expect(parts[1]["filename"] as? String == "diagram.png")
        #expect(parts[1]["url"] as? String == "data:image/png;base64,AAAA")
    }

    @MainActor
    @Test func openCodeClientPostsSlashCommandRequests() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { MockURLProtocol.requestHandler = nil }
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request

            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else {
                throw URLError(.badServerResponse)
            }

            let body = Data(
                """
                {
                  "info": {
                    "id": "msg_1",
                    "sessionID": "ses_1",
                    "role": "assistant",
                    "agent": null,
                    "modelID": null,
                    "time": null
                  },
                  "parts": []
                }
                """.utf8
            )
            return (response, body)
        }

        let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
        let client = OpenCodeClient(
            connection: OpenCodeRuntime.Connection(
                projectPath: "/tmp/NeoCode",
                baseURL: baseURL,
                username: "user",
                password: "pass",
                version: "1.0.0"
            ),
            session: session
        )

        try await client.sendCommand(
            sessionID: "ses_1",
            command: "review",
            arguments: "current diff",
            attachments: [
                ComposerAttachment(
                    name: "diagram.png",
                    mimeType: "image/png",
                    content: .dataURL("data:image/png;base64,AAAA")
                ),
            ],
            options: OpenCodePromptOptions(
                model: ComposerModelOption(
                    id: "openai/gpt-5.4",
                    providerID: "openai",
                    modelID: "gpt-5.4",
                    title: "GPT-5.4",
                    variants: ["high"]
                ),
                agentName: "builder",
                variant: "high"
            )
        )

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/session/ses_1/command")

        let bodyData = try #require(try requestBodyData(from: request))
        let payload = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(payload["command"] as? String == "review")
        #expect(payload["arguments"] as? String == "current diff")
        #expect(payload["model"] as? String == "openai/gpt-5.4")
        #expect(payload["agent"] as? String == "builder")
        #expect(payload["variant"] as? String == "high")

        let parts = try #require(payload["parts"] as? [[String: Any]])
        #expect(parts.count == 1)
        #expect(parts[0]["type"] as? String == "file")
        #expect(parts[0]["filename"] as? String == "diagram.png")
    }

    @MainActor
    @Test func appStoreRoutesMatchingSlashDraftThroughCommandEndpoint() async {
        let projectID = UUID()
        let store = AppStore(projects: [
            ProjectSummary(
                id: projectID,
                name: "NeoCode",
                path: "/tmp/NeoCode",
                sessions: [
                    SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                ]
            ),
        ])
        let service = MockOpenCodeService()

        store.selectSession("ses_1")
        store.availableCommands = [
            OpenCodeCommand(
                name: "review",
                description: "Review current changes",
                agent: nil,
                model: nil,
                source: "skill",
                template: nil,
                subtask: true,
                hints: ["$1"]
            ),
        ]
        store.draft = "/review current diff"

        let didSend = await store.sendDraft(using: service, projectID: projectID, sessionID: "ses_1")

        #expect(didSend == true)
        #expect(service.sentPrompts.isEmpty)
        #expect(service.sentCommands.count == 1)
        #expect(service.sentCommands[0].sessionID == "ses_1")
        #expect(service.sentCommands[0].command == "review")
        #expect(service.sentCommands[0].arguments == "current diff")
        #expect(store.draft.isEmpty)
        #expect(store.selectedSession?.transcript.isEmpty == true)
        #expect(store.selectedSession?.status == .running)
    }

    @MainActor
    @Test func appStoreFallsBackToPromptForUnknownSlashDraft() async {
        let projectID = UUID()
        let store = AppStore(projects: [
            ProjectSummary(
                id: projectID,
                name: "NeoCode",
                path: "/tmp/NeoCode",
                sessions: [
                    SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                ]
            ),
        ])
        let service = MockOpenCodeService()

        store.selectSession("ses_1")
        store.availableCommands = []
        store.draft = "/unknown raw text"

        let didSend = await store.sendDraft(using: service, projectID: projectID, sessionID: "ses_1")

        #expect(didSend == true)
        #expect(service.sentCommands.isEmpty)
        #expect(service.sentPrompts.count == 1)
        #expect(service.sentPrompts[0].text == "/unknown raw text")
    }

    @MainActor
    @Test func appStoreRestoresSlashDraftWhenCommandExecutionFails() async {
        let projectID = UUID()
        let store = AppStore(projects: [
            ProjectSummary(
                id: projectID,
                name: "NeoCode",
                path: "/tmp/NeoCode",
                sessions: [
                    SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: .distantPast),
                ]
            ),
        ])
        let service = MockOpenCodeService(sendPromptError: TestFailure.failed("command failed"))

        store.selectSession("ses_1")
        store.availableCommands = [
            OpenCodeCommand(
                name: "review",
                description: nil,
                agent: nil,
                model: nil,
                source: "command",
                template: nil,
                subtask: nil,
                hints: []
            ),
        ]
        store.draft = "/review current diff"

        let didSend = await store.sendDraft(using: service, projectID: projectID, sessionID: "ses_1")

        #expect(didSend == false)
        #expect(store.draft == "/review current diff")
        #expect(store.lastError == "command failed")
        #expect(store.selectedSession?.status == .attention)
        #expect(service.sentCommands.isEmpty)
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
        let service = MockOpenCodeService(sendPromptError: TestFailure.failed("send failed"))

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
        #expect(store.selectedSession?.transcript == originalTranscript)
        #expect(store.lastError == "send failed")
    }

    @MainActor
    @Test func appStoreDiscardsEphemeralSessionWhenSelectingAnotherSession() async throws {
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
        #expect(store.projects[0].sessions.count == 1)
        #expect(store.projects[0].sessions.contains(where: { $0.id == ephemeralID }) == false)
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
    @Test func promotingEphemeralSessionClearsWorkspacePromptDraft() async throws {
        let store = AppStore(projects: [ProjectSummary(name: "NeoCode", path: "/tmp/NeoCode")])
        let runtime = OpenCodeRuntime()
        let now = Date()

        await store.createSession(using: runtime)
        let projectID = try #require(store.selectedProjectID)
        let ephemeralID = try #require(store.selectedSessionID)

        store.draft = "Carry this over"

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

        await store.createSession(using: runtime)
        let nextEphemeralID = try #require(store.selectedSessionID)

        await store.preparePrompt(for: nextEphemeralID)

        #expect(store.draft == "")
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
    @Test func chatMessageToolCallRoundTripsThroughCodable() async throws {
        let message = ChatMessage(
            id: "tool_1",
            role: .tool,
            text: "read completed",
            timestamp: Date(timeIntervalSince1970: 100),
            emphasis: .subtle,
            kind: .toolCall(name: "read", status: .completed, detail: "ok"),
            isInProgress: false
        )

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        #expect(decoded == message)
    }

    @MainActor
    @Test func openCodeClientPostsAbortForSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { MockURLProtocol.requestHandler = nil }

        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/session/ses_1/abort")
            #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)

            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else {
                throw URLError(.badServerResponse)
            }

            return (response, Data("true".utf8))
        }

        let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
        let client = OpenCodeClient(
            connection: OpenCodeRuntime.Connection(
                projectPath: "/tmp/NeoCode",
                baseURL: baseURL,
                username: "user",
                password: "pass",
                version: "1.0.0"
            ),
            session: session
        )

        try await client.abortSession(sessionID: "ses_1")
    }

    @MainActor
    @Test func openCodeClientListsSessionStatuses() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { MockURLProtocol.requestHandler = nil }

        MockURLProtocol.requestHandler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/session/status")

            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else {
                throw URLError(.badServerResponse)
            }

            let payload = Data("{\"ses_1\":{\"type\":\"busy\"}}".utf8)
            return (response, payload)
        }

        let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
        let client = OpenCodeClient(
            connection: OpenCodeRuntime.Connection(
                projectPath: "/tmp/NeoCode",
                baseURL: baseURL,
                username: "user",
                password: "pass",
                version: "1.0.0"
            ),
            session: session
        )

        let statuses = try await client.listSessionStatuses()
        #expect(statuses["ses_1"] == .busy)
    }

    @MainActor
    @Test func openCodeClientRepliesToPermission() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { MockURLProtocol.requestHandler = nil }
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request

            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else {
                throw URLError(.badServerResponse)
            }

            return (response, Data("true".utf8))
        }

        let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
        let client = OpenCodeClient(
            connection: OpenCodeRuntime.Connection(
                projectPath: "/tmp/NeoCode",
                baseURL: baseURL,
                username: "user",
                password: "pass",
                version: "1.0.0"
            ),
            session: session
        )

        try await client.replyToPermission(requestID: "perm_1", reply: .always, message: nil)

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/permission/perm_1/reply")

        let bodyData = try requestBodyData(from: request)
        let body = try #require(bodyData)
        let payload = try JSONDecoder().decode(PermissionReplyPayload.self, from: body)
        #expect(payload.reply == .always)
        #expect(payload.message == nil)
    }

    @MainActor
    @Test func openCodeClientRepliesToQuestion() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { MockURLProtocol.requestHandler = nil }
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request

            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else {
                throw URLError(.badServerResponse)
            }

            return (response, Data("true".utf8))
        }

        let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
        let client = OpenCodeClient(
            connection: OpenCodeRuntime.Connection(
                projectPath: "/tmp/NeoCode",
                baseURL: baseURL,
                username: "user",
                password: "pass",
                version: "1.0.0"
            ),
            session: session
        )

        try await client.replyToQuestion(requestID: "que_1", answers: [["Yes"], ["Type your own answer"]])

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/question/que_1/reply")

        let bodyData = try requestBodyData(from: request)
        let body = try #require(bodyData)
        let payload = try JSONDecoder().decode(QuestionReplyPayload.self, from: body)
        #expect(payload.answers == [["Yes"], ["Type your own answer"]])
    }

}

private func decode<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder.opencode.decode(T.self, from: Data(json.utf8))
}

private func requestBodyData(from request: URLRequest) throws -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)

    while stream.hasBytesAvailable {
        let readCount = stream.read(&buffer, maxLength: buffer.count)
        if readCount < 0 {
            throw stream.streamError ?? URLError(.cannotDecodeRawData)
        }
        if readCount == 0 {
            break
        }
        data.append(buffer, count: readCount)
    }

    return data
}

private struct QuestionReplyPayload: Decodable {
    let answers: [[String]]
}

private struct PermissionReplyPayload: Decodable {
    let reply: OpenCodePermissionReply
    let message: String?
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class MockOpenCodeService: OpenCodeServicing {
    struct SentPrompt {
        let sessionID: String
        let text: String
        let attachments: [ComposerAttachment]
    }

    struct SentCommand {
        let sessionID: String
        let command: String
        let arguments: String
        let attachments: [ComposerAttachment]
    }

    var revertedSessionID: String?
    var revertedMessageID: String?
    var unrevertedSessionIDs: [String] = []
    var sentPrompts: [SentPrompt] = []
    var sentCommands: [SentCommand] = []
    var repliedPermissionIDs: [String] = []
    var repliedQuestionIDs: [String] = []
    var rejectedQuestionIDs: [String] = []
    var sendPromptError: Error?

    init(sendPromptError: Error? = nil) {
        self.sendPromptError = sendPromptError
    }

    func listSessions() async throws -> [OpenCodeSession] { [] }
    func listSessionStatuses() async throws -> [String: OpenCodeSessionActivity] { [:] }
    func listPermissions() async throws -> [OpenCodePermissionRequest] { [] }
    func listQuestions() async throws -> [OpenCodeQuestionRequest] { [] }
    func listCommands() async throws -> [OpenCodeCommand] { [] }
    func createSession(title: String?) async throws -> OpenCodeSession { fatalError("Unused in test") }
    func updateSession(sessionID: String, title: String) async throws -> OpenCodeSession { fatalError("Unused in test") }
    func deleteSession(sessionID: String) async throws -> Bool { true }

    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> Bool {
        revertedSessionID = sessionID
        revertedMessageID = messageID
        return true
    }

    func unrevertSession(sessionID: String) async throws -> Bool {
        unrevertedSessionIDs.append(sessionID)
        return true
    }

    func abortSession(sessionID: String) async throws {}
    func replyToPermission(requestID: String, reply: OpenCodePermissionReply, message: String?) async throws {
        repliedPermissionIDs.append(requestID)
    }
    func replyToQuestion(requestID: String, answers: [OpenCodeQuestionAnswer]) async throws {
        repliedQuestionIDs.append(requestID)
    }
    func rejectQuestion(requestID: String) async throws {
        rejectedQuestionIDs.append(requestID)
    }
    func listProviders() async throws -> OpenCodeProviderResponse { fatalError("Unused in test") }
    func listAgents() async throws -> [OpenCodeAgent] { [] }
    func listMessages(sessionID: String) async throws -> [OpenCodeMessageEnvelope] { [] }

    func sendPromptAsync(sessionID: String, text: String, attachments: [ComposerAttachment], options: OpenCodePromptOptions?) async throws {
        if let sendPromptError {
            throw sendPromptError
        }
        sentPrompts.append(SentPrompt(sessionID: sessionID, text: text, attachments: attachments))
    }

    func sendCommand(
        sessionID: String,
        command: String,
        arguments: String,
        attachments: [ComposerAttachment],
        options: OpenCodePromptOptions?
    ) async throws {
        if let sendPromptError {
            throw sendPromptError
        }
        sentCommands.append(SentCommand(sessionID: sessionID, command: command, arguments: arguments, attachments: attachments))
    }

    func eventStream() throws -> AsyncThrowingStream<OpenCodeEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private enum TestFailure: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}
