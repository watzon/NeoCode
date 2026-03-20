import Foundation
import Testing
@testable import NeoCode

@MainActor
@Suite(.serialized)
struct AppStoreComposerTests {
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
    
            #expect(store.selectedTranscript.count == 1)
            #expect(store.selectedTranscript.first?.text == "Thinking: streaming")
            #expect(store.selectedSession?.status == .running)
        }

        @MainActor
        @Test func appStoreMarksStreamingPlaceholderCompleteWhenMessageCompletesWithoutFinalPartUpdate() {
            let now = Date(timeIntervalSince1970: 1_710_616_186)
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
                                    id: "part_1",
                                    messageID: "msg_1",
                                    role: .assistant,
                                    text: "Partial response",
                                    timestamp: now,
                                    emphasis: .normal,
                                    isInProgress: true
                                )
                            ]
                        ),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
            store.apply(event: .messageUpdated(OpenCodeMessageInfo(
                id: "msg_1",
                sessionID: "ses_1",
                role: "assistant",
                summary: nil,
                agent: nil,
                providerID: nil,
                modelID: nil,
                cost: nil,
                tokens: nil,
                time: OpenCodeTimeContainer(created: now, updated: now, completed: now.addingTimeInterval(2))
            )))
    
            #expect(store.selectedTranscript.count == 1)
            #expect(store.selectedTranscript[0].isInProgress == false)
            #expect(store.selectedTranscript[0].timestamp == now.addingTimeInterval(2))
            #expect(store.selectedSession?.status == .idle)
        }

        @MainActor
        @Test func appStoreFlushesDeferredPersistenceWhenStreamingSettles() async {
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
                    deltaFlushDebounce: .milliseconds(200)
                )
            )
            store.selectSession("ses_1")
    
            store.apply(event: .messagePartDelta(OpenCodePartDelta(sessionID: "ses_1", messageID: "msg_1", partID: "part_1", field: "text", delta: "Buffered text")))
    
            try? await Task.sleep(for: .milliseconds(120))
            #expect(store.debugBufferedTextDeltaCount == 1)
    
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
    
            #expect(store.selectedTranscript.first?.text == "Buffered text")
            #expect(store.debugBufferedTextDeltaCount == 0)
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
            let service = MockNeoCodeService()
    
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
            #expect(store.selectedTranscript.count == 1)
            #expect(store.selectedTranscript.first?.text == "Updated prompt")
            #expect(store.selectedTranscript.first?.id.hasPrefix("optimistic-user-") == true)
            #expect(store.selectedSession?.status == .running)
        }

        @MainActor
        @Test func appStoreBuildsRevertPreviewFromMessageSummaries() async {
            let projectID = UUID()
            let attachment = ChatAttachment(filename: "diagram.png", mimeType: "image/png", url: "data:image/png;base64,AAAA")
            let transcript = [
                ChatMessage(
                    id: "part_user_attachment_1",
                    messageID: "msg_user_1",
                    role: .user,
                    text: attachment.displayTitle,
                    timestamp: Date(timeIntervalSince1970: 100),
                    emphasis: .normal,
                    attachment: attachment
                ),
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
                    text: "Reply",
                    timestamp: Date(timeIntervalSince1970: 110),
                    emphasis: .normal
                ),
                ChatMessage(
                    id: "part_user_2",
                    messageID: "msg_user_2",
                    role: .user,
                    text: "Follow up",
                    timestamp: Date(timeIntervalSince1970: 120),
                    emphasis: .normal
                ),
            ]
            let store = AppStore(projects: [
                ProjectSummary(
                    id: projectID,
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: Date(timeIntervalSince1970: 120), transcript: transcript),
                    ]
                ),
            ])
    
            store.apply(event: .messageUpdated(OpenCodeMessageInfo(
                id: "msg_user_1",
                sessionID: "ses_1",
                role: "user",
                summary: .object([
                    "diffs": .array([
                        .object([
                            "file": .string("Sources/App.swift"),
                            "before": .string(""),
                            "after": .string(""),
                            "additions": .number(3),
                            "deletions": .number(1),
                            "status": .string("modified")
                        ])
                    ])
                ]),
                agent: nil,
                providerID: nil,
                modelID: nil,
                cost: nil,
                tokens: nil,
                time: OpenCodeTimeContainer(created: Date(timeIntervalSince1970: 100), updated: Date(timeIntervalSince1970: 100), completed: nil)
            )))
            store.apply(event: .messageUpdated(OpenCodeMessageInfo(
                id: "msg_user_2",
                sessionID: "ses_1",
                role: "user",
                summary: .object([
                    "diffs": .array([
                        .object([
                            "file": .string("Sources/App.swift"),
                            "before": .string(""),
                            "after": .string(""),
                            "additions": .number(2),
                            "deletions": .number(0),
                            "status": .string("modified")
                        ]),
                        .object([
                            "file": .string("README.md"),
                            "before": .string(""),
                            "after": .string(""),
                            "additions": .number(1),
                            "deletions": .number(0),
                            "status": .string("added")
                        ])
                    ])
                ]),
                agent: nil,
                providerID: nil,
                modelID: nil,
                cost: nil,
                tokens: nil,
                time: OpenCodeTimeContainer(created: Date(timeIntervalSince1970: 120), updated: Date(timeIntervalSince1970: 120), completed: nil)
            )))
    
            let preview = store.revertPreview(for: "part_user_1", in: "ses_1")
    
            #expect(preview?.restoredText == "Original prompt")
            #expect(preview?.restoredAttachments.count == 1)
            #expect(preview?.affectedPromptCount == 2)
            #expect(preview?.changedFiles.count == 2)
            #expect(preview?.changedFiles.first(where: { $0.path == "Sources/App.swift" })?.additions == 5)
            #expect(preview?.changedFiles.first(where: { $0.path == "Sources/App.swift" })?.deletions == 1)
        }

        @MainActor
        @Test func appStoreRevertsMessageAndRestoresComposerDraft() async {
            let projectID = UUID()
            let attachment = ChatAttachment(filename: "diagram.png", mimeType: "image/png", url: "data:image/png;base64,AAAA")
            let originalTranscript = [
                ChatMessage(
                    id: "part_user_attachment_1",
                    messageID: "msg_user_1",
                    role: .user,
                    text: attachment.displayTitle,
                    timestamp: Date(timeIntervalSince1970: 100),
                    emphasis: .normal,
                    attachment: attachment
                ),
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
                ChatMessage(
                    id: "part_user_2",
                    messageID: "msg_user_2",
                    role: .user,
                    text: "Later prompt",
                    timestamp: Date(timeIntervalSince1970: 120),
                    emphasis: .normal
                ),
            ]
            let store = AppStore(projects: [
                ProjectSummary(
                    id: projectID,
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(id: "ses_1", title: "Existing", lastUpdatedAt: Date(timeIntervalSince1970: 120), transcript: originalTranscript),
                    ]
                ),
            ])
            let service = MockNeoCodeService()
    
            store.selectSession("ses_1")
            store.draft = "Current draft"
            store.attachedFiles = [ComposerAttachment(name: "notes.txt", mimeType: "text/plain", content: .dataURL("data:text/plain;base64,QQ=="))]
    
            let didRevert = await store.revertMessage(
                messageID: "part_user_1",
                in: "ses_1",
                projectID: projectID,
                using: service
            )
    
            #expect(didRevert == true)
            #expect(service.revertedSessionID == "ses_1")
            #expect(service.revertedMessageID == "msg_user_1")
            #expect(store.transcript(for: "ses_1").isEmpty)
            #expect(store.visibleTranscript(for: "ses_1").isEmpty)
            #expect(store.draft == "Original prompt")
            #expect(store.attachedFiles.count == 1)
            #expect(store.queuedMessages(for: "ses_1").count == 1)
            #expect(store.queuedMessages(for: "ses_1").first?.text == "Current draft")
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
            let service = MockNeoCodeService()
    
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
            #expect(store.selectedTranscript.count == 1)
            #expect(store.selectedTranscript.first?.text == "/review current diff")
            #expect(store.selectedTranscript.first?.id.hasPrefix("optimistic-user-") == true)
            #expect(store.selectedSession?.status == .running)
        }

        @MainActor
        @Test func appStoreCompactsSessionThroughSummarizeEndpoint() async {
            let projectID = UUID()
            let model = ComposerModelOption(
                id: "openai/gpt-5.4",
                providerID: "openai",
                modelID: "gpt-5.4",
                title: "GPT-5.4",
                contextWindow: nil,
                variants: []
            )
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
            let service = MockNeoCodeService()
    
            store.availableModels = [model]
            store.selectedModelID = model.id
            store.selectSession("ses_1")
            store.draft = "/compact"
    
            let didCompact = await store.compactSession("ses_1", projectID: projectID, using: service)
    
            #expect(didCompact == true)
            #expect(service.sentSummaries.count == 1)
            #expect(service.sentSummaries[0].sessionID == "ses_1")
            #expect(service.sentSummaries[0].providerID == "openai")
            #expect(service.sentSummaries[0].modelID == "gpt-5.4")
            #expect(service.sentSummaries[0].auto == false)
            #expect(store.draft.isEmpty)
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
            let service = MockNeoCodeService()
    
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
        @Test func appStoreKeepsConsecutiveOptimisticAttachmentSendsInSeparateUserTurns() async {
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
            let service = MockNeoCodeService()
            let firstAttachment = ComposerAttachment(
                name: "first.png",
                mimeType: "image/png",
                content: .dataURL("data:image/png;base64,AAAA")
            )
            let secondAttachment = ComposerAttachment(
                name: "second.png",
                mimeType: "image/png",
                content: .dataURL("data:image/png;base64,BBBB")
            )
    
            store.selectSession("ses_1")
    
            let firstDidSend = await store.sendDraft(
                using: service,
                projectID: projectID,
                sessionID: "ses_1",
                text: "First image",
                attachments: [firstAttachment],
                clearComposerOnSend: false
            )
            let secondDidSend = await store.sendDraft(
                using: service,
                projectID: projectID,
                sessionID: "ses_1",
                text: "Second image",
                attachments: [secondAttachment],
                clearComposerOnSend: false
            )
    
            let userTurns = buildDisplayMessageGroups(from: store.selectedTranscript).compactMap { group -> [ChatMessage]? in
                guard case .userTurn(let messages) = group else { return nil }
                return messages
            }
    
            #expect(firstDidSend == true)
            #expect(secondDidSend == true)
            #expect(service.sentPrompts.count == 2)
            #expect(userTurns.count == 2)
            #expect(userTurns[0].contains(where: { $0.text == "First image" }))
            #expect(userTurns[0].compactMap(\.attachment).map(\.displayTitle) == ["first.png"])
            #expect(userTurns[1].contains(where: { $0.text == "Second image" }))
            #expect(userTurns[1].compactMap(\.attachment).map(\.displayTitle) == ["second.png"])
        }

        @MainActor
        @Test func appStoreIgnoresSyntheticReadSummaryDuringLiveAttachmentUpdates() async {
            let projectID = UUID()
            let now = Date(timeIntervalSince1970: 1_710_616_186)
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
    
            store.selectSession("ses_1")
            store.apply(event: .messageUpdated(OpenCodeMessageInfo(
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
            )))
    
            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "part_read_summary",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .text,
                text: "Called the Read tool with the following input: {\"filePath\":\"/tmp/CleanShot.png\"}",
                tool: nil,
                mime: nil,
                filename: nil,
                url: nil,
                source: nil,
                state: nil,
                time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
            )))
    
            #expect(store.selectedTranscript.isEmpty)
    
            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "part_attachment",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .file,
                text: nil,
                tool: nil,
                mime: "image/png",
                filename: "CleanShot.png",
                url: "data:image/png;base64,AAAA",
                source: nil,
                state: nil,
                time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
            )))
            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "part_prompt",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .text,
                text: "Ok one more test",
                tool: nil,
                mime: nil,
                filename: nil,
                url: nil,
                source: nil,
                state: nil,
                time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
            )))
    
            #expect(store.selectedTranscript.count == 2)
            #expect(store.selectedTranscript.contains(where: { $0.text == "Ok one more test" }))
            #expect(store.selectedTranscript.contains(where: { $0.attachment?.displayTitle == "CleanShot.png" }))
            #expect(store.selectedTranscript.contains(where: { $0.text.contains("Called the Read tool") }) == false)
        }

        @MainActor
        @Test func appStoreIgnoresSerializedFileDumpDuringLiveAttachmentUpdates() async {
            let projectID = UUID()
            let now = Date(timeIntervalSince1970: 1_710_616_186)
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
    
            store.selectSession("ses_1")
            store.apply(event: .messageUpdated(OpenCodeMessageInfo(
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
            )))
    
            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "part_dump",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .text,
                text: "<path>/tmp/AGENTS.md</path>\\n<type>file</type>\\n<content>1: hello</content>",
                tool: nil,
                mime: nil,
                filename: nil,
                url: nil,
                source: nil,
                state: nil,
                time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
            )))
    
            #expect(store.selectedTranscript.isEmpty)
    
            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "part_attachment",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .file,
                text: nil,
                tool: nil,
                mime: "text/plain",
                filename: "AGENTS.md",
                url: "file:///tmp/AGENTS.md",
                source: OpenCodeFileSource(
                    text: OpenCodeFileSourceText(value: "@AGENTS.md", start: 24, end: 34),
                    path: "AGENTS.md",
                    range: nil,
                    clientName: nil,
                    uri: nil
                ),
                state: nil,
                time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
            )))
            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "part_prompt",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .text,
                text: "Ok this is just a test @AGENTS.md\n\nJust give a short response.",
                tool: nil,
                mime: nil,
                filename: nil,
                url: nil,
                source: nil,
                state: nil,
                time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
            )))
    
            #expect(store.selectedTranscript.count == 2)
            #expect(store.selectedTranscript.contains(where: { $0.text.contains("Ok this is just a test @AGENTS.md") }))
            #expect(store.selectedTranscript.contains(where: { $0.attachment?.displayTitle == "AGENTS.md" }))
            #expect(store.selectedTranscript.contains(where: { $0.text.contains("<path>") }) == false)
        }

        @MainActor
        @Test func appStoreReconcilesOptimisticAttachmentWhenServerReturnsDifferentURLForSameFile() async {
            let projectID = UUID()
            let now = Date(timeIntervalSince1970: 1_710_616_186)
            let filePath = "/tmp/CleanShot.png"
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
            let service = MockNeoCodeService()
    
            store.selectSession("ses_1")
    
            let didSend = await store.sendDraft(
                using: service,
                projectID: projectID,
                sessionID: "ses_1",
                text: "Image test",
                attachments: [
                    ComposerAttachment(
                        name: "CleanShot.png",
                        mimeType: "image/png",
                        content: .file(path: filePath)
                    )
                ],
                clearComposerOnSend: false
            )
    
            #expect(didSend == true)
            #expect(store.selectedTranscript.compactMap(\.attachment).count == 1)
    
            store.apply(event: .messageUpdated(OpenCodeMessageInfo(
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
            )))
            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "part_attachment",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .file,
                text: nil,
                tool: nil,
                mime: "image/png",
                filename: "CleanShot.png",
                url: "data:image/png;base64,AAAA",
                source: OpenCodeFileSource(text: nil, path: filePath, range: nil, clientName: nil, uri: nil),
                state: nil,
                time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
            )))
            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "part_prompt",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .text,
                text: "Image test",
                tool: nil,
                mime: nil,
                filename: nil,
                url: nil,
                source: nil,
                state: nil,
                time: OpenCodeTimeContainer(created: now, updated: now, completed: nil)
            )))
    
            let attachments = store.selectedTranscript.compactMap(\.attachment)
            #expect(attachments.count == 1)
            #expect(attachments.first?.sourcePath == filePath)
            #expect(store.selectedTranscript.contains(where: { $0.text == "Image test" }))
        }

        @MainActor
        @Test func appStoreQueuesDraftWhenSessionIsAlreadyRunning() async {
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
    
            let didSend = await store.sendDraft(
                using: service,
                projectID: projectID,
                sessionID: "ses_1",
                allowQueueIfRunning: true
            )
    
            #expect(didSend == true)
            #expect(service.sentPrompts.isEmpty)
            #expect(store.queuedMessages(for: "ses_1").count == 1)
            #expect(store.queuedMessages(for: "ses_1").first?.text == "Queued follow-up")
            #expect(store.queuedMessages(for: "ses_1").first?.deliveryMode == .sendWhenDone)
            #expect(store.draft.isEmpty)
        }

        @MainActor
        @Test func appStoreCanSendQueuedSteerMessageWhileSessionIsRunning() async throws {
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
            store.updateQueuedMessageDeliveryMode(id: queuedID, to: .steer, in: "ses_1")
    
            let didSend = await store.sendQueuedSteerMessageIfPossible(
                id: queuedID,
                in: "ses_1",
                projectID: projectID,
                projectPath: "/tmp/NeoCode",
                using: service
            )
    
            #expect(didSend == true)
            #expect(store.queuedMessages(for: "ses_1").isEmpty)
            #expect(service.sentPrompts.count == 1)
            #expect(service.sentPrompts[0].text == "Queued follow-up")
        }

        @MainActor
        @Test func appStoreSendsQueuedDraftOnceSessionReturnsToIdle() async {
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
    
            store.apply(event: .sessionStatusChanged(sessionID: "ses_1", status: .idle))
            let didSend = await store.sendNextQueuedMessageIfPossible(
                in: "ses_1",
                projectID: projectID,
                projectPath: "/tmp/NeoCode",
                using: service
            )
    
            #expect(didSend == true)
            #expect(store.queuedMessages(for: "ses_1").isEmpty)
            #expect(service.sentPrompts.count == 1)
            #expect(service.sentPrompts[0].text == "Queued follow-up")
            #expect(store.selectedSession?.status == .running)
        }

        @MainActor
        @Test func appStoreSendsQueuedDraftAfterSettlingStaleStreamingState() async {
            let projectID = UUID()
            let now = Date(timeIntervalSince1970: 1_710_616_186)
            let store = AppStore(projects: [
                ProjectSummary(
                    id: projectID,
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Existing",
                            lastUpdatedAt: now,
                            status: .running,
                            transcript: [
                                ChatMessage(
                                    id: "part_1",
                                    messageID: "msg_1",
                                    role: .assistant,
                                    text: "Partial response",
                                    timestamp: now,
                                    emphasis: .normal,
                                    isInProgress: true
                                )
                            ]
                        ),
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

            let didSend = await store.sendNextQueuedMessageIfPossible(
                in: "ses_1",
                projectID: projectID,
                projectPath: "/tmp/NeoCode",
                using: service
            )

            #expect(didSend == true)
            #expect(store.queuedMessages(for: "ses_1").isEmpty)
            #expect(service.sentPrompts.count == 1)
            #expect(service.sentPrompts[0].text == "Queued follow-up")
            #expect(store.selectedTranscript.allSatisfy { !$0.isInProgress })
            #expect(store.selectedSession?.status == .running)
        }

        @MainActor
        @Test func appStoreSendsQueuedDraftAfterSessionFallsIntoError() async {
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
    
            store.apply(event: .messagePartUpdated(OpenCodePart(
                id: "part_patch",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .tool,
                text: nil,
                tool: "apply_patch",
                mime: nil,
                filename: nil,
                url: nil,
                source: nil,
                state: OpenCodeToolState(
                    status: .error,
                    input: .object(["patchText": .string("*** Begin Patch\n*** End Patch")]),
                    output: nil,
                    error: "apply_patch verification failed: no hunks found"
                ),
                time: OpenCodeTimeContainer(created: .now, updated: .now, completed: .now)
            )))
    
            #expect(store.selectedSession?.status == .error)
    
            let didSend = await store.sendNextQueuedMessageIfPossible(
                in: "ses_1",
                projectID: projectID,
                projectPath: "/tmp/NeoCode",
                using: service
            )
    
            #expect(didSend == true)
            #expect(store.queuedMessages(for: "ses_1").isEmpty)
            #expect(service.sentPrompts.count == 1)
            #expect(service.sentPrompts[0].text == "Queued follow-up")
            #expect(store.selectedSession?.status == .running)
        }

        @MainActor
        @Test func appStorePrefersRemoteSlashCommandsOverLocalHandlers() async {
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
            let service = MockNeoCodeService()
    
            store.selectSession("ses_1")
            store.availableCommands = [
                OpenCodeCommand(
                    name: "model",
                    description: "Server-side model command",
                    agent: nil,
                    model: nil,
                    source: "command",
                    template: nil,
                    subtask: nil,
                    hints: []
                ),
            ]
            store.draft = "/model gpt-5"
    
            let didSend = await store.sendDraft(using: service, projectID: projectID, sessionID: "ses_1")
    
            #expect(didSend == true)
            #expect(service.sentCommands.count == 1)
            #expect(service.sentCommands[0].command == "model")
            #expect(service.sentCommands[0].arguments == "gpt-5")
            #expect(store.selectedModelID == "openai/gpt-5.4")
            #expect(store.draft.isEmpty)
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
            let service = MockNeoCodeService(sendPromptError: TestFailure.failed("command failed"))
    
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
            #expect(store.selectedSession?.status == .error)
            #expect(store.selectedTranscript.isEmpty == true)
            #expect(service.sentCommands.isEmpty)
        }

        @Test func appStoreComposerOptionCaptureResultTreatsCancellationSeparately() async {
            let task = Task {
                await AppStore.captureResult {
                    try await Task.sleep(for: .seconds(5))
                    return 1
                }
            }
    
            task.cancel()
    
            let result = await task.value
            switch result {
            case .cancelled:
                break
            default:
                Issue.record("Expected cancelled composer options result")
            }
        }
}
