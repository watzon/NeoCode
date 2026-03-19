import Foundation
import SwiftUI
import Testing
@testable import NeoCode

@MainActor
@Suite(.serialized)
struct TranscriptRenderingTests {
        @Test func transcriptDropsSyntheticReadSummaryForUserAttachmentMessages() throws {
            let timestamp = Date(timeIntervalSince1970: 1_710_616_186)
            let envelopes = [
                OpenCodeMessageEnvelope(
                    info: OpenCodeMessageInfo(
                        id: "msg_user_attachment",
                        sessionID: "ses_1",
                        role: "user",
                        summary: nil,
                        agent: nil,
                        providerID: nil,
                        modelID: nil,
                        cost: nil,
                        tokens: nil,
                        time: OpenCodeTimeContainer(created: timestamp, updated: timestamp, completed: nil)
                    ),
                    parts: [
                        OpenCodePart(
                            id: "part_attachment",
                            sessionID: "ses_1",
                            messageID: "msg_user_attachment",
                            type: .file,
                            text: nil,
                            tool: nil,
                            mime: "image/png",
                            filename: "CleanShot.png",
                            url: "data:image/png;base64,AAAA",
                            source: nil,
                            state: nil,
                            time: OpenCodeTimeContainer(created: timestamp, updated: timestamp, completed: nil)
                        ),
                        OpenCodePart(
                            id: "part_prompt",
                            sessionID: "ses_1",
                            messageID: "msg_user_attachment",
                            type: .text,
                            text: "Ok one more test",
                            tool: nil,
                            mime: nil,
                            filename: nil,
                            url: nil,
                            source: nil,
                            state: nil,
                            time: OpenCodeTimeContainer(created: timestamp, updated: timestamp, completed: nil)
                        ),
                        OpenCodePart(
                            id: "part_read_summary",
                            sessionID: "ses_1",
                            messageID: "msg_user_attachment",
                            type: .text,
                            text: "Called the Read tool with the following input: {\"filePath\":\"/tmp/CleanShot.png\"}",
                            tool: nil,
                            mime: nil,
                            filename: nil,
                            url: nil,
                            source: nil,
                            state: nil,
                            time: OpenCodeTimeContainer(created: timestamp, updated: timestamp, completed: nil)
                        ),
                    ]
                )
            ]
    
            let transcript = ChatMessage.makeTranscript(from: envelopes)
    
            #expect(transcript.count == 2)
            #expect(transcript.contains(where: { $0.text == "Ok one more test" }))
            #expect(transcript.contains(where: { $0.attachment?.displayTitle == "CleanShot.png" }))
            #expect(transcript.contains(where: { $0.text.contains("Called the Read tool") }) == false)
        }

        @Test func parsesTodosFromTodoWriteToolInput() {
            let timestamp = Date(timeIntervalSince1970: 1_710_616_200)
            let part = OpenCodePart(
                id: "part_todo_write",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .tool,
                text: nil,
                tool: "todowrite",
                mime: nil,
                filename: nil,
                url: nil,
                source: nil,
                state: OpenCodeToolState(
                    status: .completed,
                    input: .object([
                        "todos": .array([
                            .object([
                                "content": .string("Wire the todo UI into the composer dock"),
                                "status": .string("in_progress"),
                                "priority": .string("high")
                            ]),
                            .object([
                                "content": .string("Review hover behavior"),
                                "status": .string("pending"),
                                "priority": .string("medium")
                            ]),
                            .object([
                                "content": .string("Ship it"),
                                "status": .string("completed"),
                                "priority": .string("low")
                            ])
                        ])
                    ]),
                    output: nil,
                    error: nil
                ),
                time: OpenCodeTimeContainer(created: timestamp, updated: timestamp, completed: timestamp)
            )
    
            let snapshot = SessionTodoParser.snapshot(from: part)
    
            #expect(snapshot?.items.count == 3)
            #expect(snapshot?.items.map(\.content) == [
                "Wire the todo UI into the composer dock",
                "Review hover behavior",
                "Ship it"
            ])
            #expect(snapshot?.items.first?.priority == .high)
            #expect(snapshot?.remainingCount == 2)
        }

        @Test func parsesActiveTodosFromNamespacedTodoToolName() {
            let timestamp = Date(timeIntervalSince1970: 1_710_616_210)
            let part = OpenCodePart(
                id: "part_namespaced_todo_write",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .tool,
                text: nil,
                tool: "functions.todowrite",
                mime: nil,
                filename: nil,
                url: nil,
                source: nil,
                state: OpenCodeToolState(
                    status: .completed,
                    input: .object([
                        "todos": .array([
                            .object([
                                "content": .string("Namespaced todo tool should still render"),
                                "status": .string("pending"),
                                "priority": .string("high")
                            ])
                        ])
                    ]),
                    output: nil,
                    error: nil
                ),
                time: OpenCodeTimeContainer(created: timestamp, updated: timestamp, completed: timestamp)
            )
    
            let snapshot = SessionTodoParser.snapshot(from: part)
    
            #expect(snapshot?.items.map(\.content) == ["Namespaced todo tool should still render"])
            #expect(part.shouldDisplay == false)
        }

        @Test func latestTodoSnapshotPreservesCompletedItems() {
            let timestamp = Date(timeIntervalSince1970: 1_710_616_240)
            let envelopes = [
                OpenCodeMessageEnvelope(
                    info: OpenCodeMessageInfo(
                        id: "msg_todos",
                        sessionID: "ses_1",
                        role: "assistant",
                        summary: nil,
                        agent: nil,
                        providerID: nil,
                        modelID: nil,
                        cost: nil,
                        tokens: nil,
                        time: OpenCodeTimeContainer(created: timestamp, updated: timestamp, completed: timestamp)
                    ),
                    parts: [
                        OpenCodePart(
                            id: "part_todo_read",
                            sessionID: "ses_1",
                            messageID: "msg_todos",
                            type: .tool,
                            text: nil,
                            tool: "todo_read",
                            mime: nil,
                            filename: nil,
                            url: nil,
                            source: nil,
                            state: OpenCodeToolState(
                                status: .completed,
                                input: nil,
                                output: .object([
                                    "todos": .array([
                                        .object([
                                            "content": .string("Already done"),
                                            "status": .string("completed"),
                                            "priority": .string("low")
                                        ])
                                    ])
                                ]),
                                error: nil
                            ),
                            time: OpenCodeTimeContainer(created: timestamp, updated: timestamp, completed: timestamp)
                        )
                    ]
                )
            ]
    
            let snapshot = SessionTodoParser.latestSnapshot(from: envelopes)
    
            #expect(snapshot?.items.map(\.content) == ["Already done"])
            #expect(snapshot?.remainingCount == 0)
        }

        @Test func transcriptUsesInlineMentionTextForUserFileReferences() throws {
            let envelopes: [OpenCodeMessageEnvelope] = try decode(
                """
                [
                  {
                    "info": {
                      "id": "msg_user_file_reference",
                      "sessionID": "ses_summary",
                      "role": "user",
                      "time": {
                        "created": 1741860000
                      }
                    },
                    "parts": [
                      {
                        "id": "part_text",
                        "sessionID": "ses_summary",
                        "messageID": "msg_user_file_reference",
                        "type": "text",
                        "text": "Review @Docs/Guide.md",
                        "time": {
                          "created": 1741860000
                        }
                      },
                      {
                        "id": "part_file",
                        "sessionID": "ses_summary",
                        "messageID": "msg_user_file_reference",
                        "type": "file",
                        "text": "# Guide\\nThis should not render as a separate transcript message.",
                        "source": {
                          "path": "Docs/Guide.md",
                          "text": {
                            "value": "@Docs/Guide.md",
                            "start": 7,
                            "end": 21
                          }
                        },
                        "time": {
                          "created": 1741860000
                        }
                      }
                    ]
                  }
                ]
                """
            )
    
            let transcript = ChatMessage.makeTranscript(from: envelopes)
            #expect(transcript.count == 1)
            #expect(transcript.first?.text == "Review @Docs/Guide.md")
        }

        @Test func transcriptFallsBackToMentionTokenWhenUserFileReferenceHasNoTextPart() throws {
            let envelopes: [OpenCodeMessageEnvelope] = try decode(
                """
                [
                  {
                    "info": {
                      "id": "msg_user_file_reference_only",
                      "sessionID": "ses_summary",
                      "role": "user",
                      "time": {
                        "created": 1741860000
                      }
                    },
                    "parts": [
                      {
                        "id": "part_file",
                        "sessionID": "ses_summary",
                        "messageID": "msg_user_file_reference_only",
                        "type": "file",
                        "text": "# Guide\\nThis should not render as a separate transcript message.",
                        "source": {
                          "path": "Docs/Guide.md",
                          "text": {
                            "value": "@Docs/Guide.md",
                            "start": 0,
                            "end": 14
                          }
                        },
                        "time": {
                          "created": 1741860000
                        }
                      }
                    ]
                  }
                ]
                """
            )
    
            let transcript = ChatMessage.makeTranscript(from: envelopes)
            #expect(transcript.count == 1)
            #expect(transcript.first?.text == "@Docs/Guide.md")
        }

        @Test func buildsTranscriptWithCompactionMarker() throws {
            let envelopes: [OpenCodeMessageEnvelope] = try decode(
                """
                [
                  {
                    "info": {
                      "id": "msg_compact_request",
                      "sessionID": "ses_usage",
                      "role": "user",
                      "agent": "builder",
                      "time": {
                        "created": "2026-03-13T10:07:00Z"
                      }
                    },
                    "parts": [
                      {
                        "id": "part_compaction",
                        "sessionID": "ses_usage",
                        "messageID": "msg_compact_request",
                        "type": "compaction",
                        "time": {
                          "created": "2026-03-13T10:07:00Z"
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
                      "agent": "compaction",
                      "providerID": "openai",
                      "modelID": "gpt-5.4",
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
            #expect(transcript.count == 2)
            #expect(transcript[0].role == .system)
            #expect(transcript[0].kind.isCompactionMarker)
            #expect(transcript[1].role == .assistant)
            #expect(transcript[1].text.contains("Continue the feature work"))
        }

        @MainActor
        @Test func reconcileLoadedTranscriptDropsStaleInProgressSuffixWhenNotPreserving() {
            let existing = [
                ChatMessage(
                    id: "msg_done",
                    messageID: "server_1",
                    role: .assistant,
                    text: "Done",
                    timestamp: .distantPast,
                    emphasis: .normal,
                    isInProgress: false
                ),
                ChatMessage(
                    id: "msg_stale",
                    messageID: "local_1",
                    role: .assistant,
                    text: "Working",
                    timestamp: .now,
                    emphasis: .normal,
                    isInProgress: true
                ),
            ]
            let incoming = [
                ChatMessage(
                    id: "msg_done",
                    messageID: "server_1",
                    role: .assistant,
                    text: "Done",
                    timestamp: .now,
                    emphasis: .normal,
                    isInProgress: false
                ),
            ]
    
            let reconciled = AppStore.reconcileLoadedTranscript(
                existing: existing,
                incoming: incoming,
                preserveInProgressSuffix: false
            )
    
            #expect(reconciled.count == 1)
            #expect(reconciled.last?.id == "msg_done")
            #expect(reconciled.contains(where: { $0.id == "msg_stale" }) == false)
        }

        @MainActor
        @Test func reconcileLoadedTranscriptPrefersCompletedLocalMessagesOverStaleRemoteMessages() {
            let now = Date(timeIntervalSince1970: 1_710_616_186)
            let existing = [
                ChatMessage(
                    id: "part_1",
                    messageID: "msg_1",
                    role: .assistant,
                    text: "Finished output",
                    timestamp: now.addingTimeInterval(1),
                    emphasis: .normal,
                    isInProgress: false
                )
            ]
            let incoming = [
                ChatMessage(
                    id: "part_1",
                    messageID: "msg_1",
                    role: .assistant,
                    text: "Working",
                    timestamp: now,
                    emphasis: .normal,
                    isInProgress: true
                )
            ]
    
            let reconciled = AppStore.reconcileLoadedTranscript(existing: existing, incoming: incoming)
    
            #expect(reconciled.count == 1)
            #expect(reconciled[0].text == "Finished output")
            #expect(reconciled[0].isInProgress == false)
        }

        @MainActor
        @Test func reconcileLoadedTranscriptPreservesTrailingInProgressMessagesMissingFromIncoming() {
            let now = Date(timeIntervalSince1970: 1_710_616_186)
            let existing = [
                ChatMessage(
                    id: "user_1",
                    messageID: "msg_user",
                    role: .user,
                    text: "Explain the bug",
                    timestamp: now,
                    emphasis: .normal
                ),
                ChatMessage(
                    id: "reasoning_1",
                    messageID: "msg_assistant",
                    role: .assistant,
                    text: "Investigating",
                    timestamp: now.addingTimeInterval(1),
                    emphasis: .strong,
                    isInProgress: false
                ),
                ChatMessage(
                    id: "text_1",
                    messageID: "msg_assistant",
                    role: .assistant,
                    text: "Working through the stop flow",
                    timestamp: now.addingTimeInterval(2),
                    emphasis: .normal,
                    isInProgress: true
                ),
            ]
            let incoming = [
                ChatMessage(
                    id: "user_1",
                    messageID: "msg_user",
                    role: .user,
                    text: "Explain the bug",
                    timestamp: now,
                    emphasis: .normal
                )
            ]
    
            let reconciled = AppStore.reconcileLoadedTranscript(existing: existing, incoming: incoming)
    
            #expect(reconciled.map(\.id) == ["user_1", "reasoning_1", "text_1"])
            #expect(reconciled.last?.text == "Working through the stop flow")
            #expect(reconciled.last?.isInProgress == true)
        }

        @MainActor
        @Test func reconcileLoadedTranscriptDropsTrailingCompletedMessagesMissingFromIncoming() {
            let now = Date(timeIntervalSince1970: 1_710_616_186)
            let existing = [
                ChatMessage(
                    id: "user_1",
                    messageID: "msg_user",
                    role: .user,
                    text: "Explain the bug",
                    timestamp: now,
                    emphasis: .normal
                ),
                ChatMessage(
                    id: "text_1",
                    messageID: "msg_assistant",
                    role: .assistant,
                    text: "This should not linger",
                    timestamp: now.addingTimeInterval(1),
                    emphasis: .normal,
                    isInProgress: false
                ),
            ]
            let incoming = [
                ChatMessage(
                    id: "user_1",
                    messageID: "msg_user",
                    role: .user,
                    text: "Explain the bug",
                    timestamp: now,
                    emphasis: .normal
                )
            ]
    
            let reconciled = AppStore.reconcileLoadedTranscript(existing: existing, incoming: incoming)
    
            #expect(reconciled.map(\.id) == ["user_1"])
        }

        @MainActor
        @Test func selectingCachedSessionKeepsTranscriptVisible() {
            let now = Date()
            let store = AppStore(projects: [
                ProjectSummary(
                    name: "NeoCode",
                    path: "/tmp/NeoCode",
                    sessions: [
                        SessionSummary(
                            id: "ses_1",
                            title: "Cached",
                            lastUpdatedAt: now,
                            transcript: [
                                ChatMessage(
                                    id: "msg_1",
                                    role: .assistant,
                                    text: "Already loaded",
                                    timestamp: now,
                                    emphasis: .normal,
                                    isInProgress: false
                                ),
                            ]
                        ),
                    ]
                ),
            ])
    
            store.selectSession("ses_1")
    
            #expect(store.loadingTranscriptSessionID == nil)
            #expect(store.selectedTranscript.count == 1)
        }

        @Test func growingTextViewAllowsAttachmentOnlyPrimaryAction() {
            #expect(
                GrowingTextView.canTriggerPrimaryAction(
                    text: "   ",
                    allowsEmptyPrimaryAction: false,
                    hasAttachments: true
                ) == true
            )
            #expect(
                GrowingTextView.canTriggerPrimaryAction(
                    text: "   ",
                    allowsEmptyPrimaryAction: false,
                    hasAttachments: false
                ) == false
            )
        }

        @MainActor
        @Test func markdownFenceParserPreservesMermaidLanguage() {
            let source = "Before\n\n```mermaid\ngraph TD\n    A[Start] --> B[Done]\n```\n\nAfter"
            let blocks = MarkdownFenceParser.parseBlocks(from: source)
    
            #expect(blocks.count == 3)
            #expect(blocks[0] == .prose("Before\n\n"))
            #expect(
                blocks[1] == .code(
                    language: "mermaid",
                    source: "graph TD\n    A[Start] --> B[Done]"
                )
            )
            #expect(blocks[2] == .prose("\n\nAfter"))
        }

        @MainActor
        @Test func markdownFenceParserKeepsUnlabeledCodeBlocks() {
            let blocks = MarkdownFenceParser.parseBlocks(from: """
            ```
            let value = 1
            ```
            """)
    
            #expect(blocks == [.code(language: nil, source: "let value = 1")])
        }

        @MainActor
        @Test func markdownRenderBudgetSkipsOversizedMermaidDiagrams() {
            let validDiagram = "graph TD\nA[Start] --> B[Done]"
            let oversizedDiagram = String(repeating: "node\n", count: MarkdownRenderBudget.maxMermaidLines + 1)
    
            #expect(MarkdownRenderBudget.shouldRenderMermaid(source: validDiagram))
            #expect(MarkdownRenderBudget.shouldRenderMermaid(source: oversizedDiagram) == false)
            #expect(
                MarkdownRenderBudget.shouldRenderMermaid(
                    source: String(repeating: "a", count: MarkdownRenderBudget.maxMermaidCharacters + 1)
                ) == false
            )
        }

        @Test func transcriptScrollPinningUnpinsImmediatelyWhenUserScrollsUp() {
            let previousOffsetY: CGFloat = 600
            let metrics = TranscriptScrollMetrics(
                contentOffsetY: 560,
                contentHeight: 2_000,
                visibleMaxY: 1_400
            )
    
            let isPinned = TranscriptScrollPinning.nextPinnedState(
                for: metrics,
                previousOffsetY: previousOffsetY,
                isMaintainingPinnedPosition: false,
                autoScrollThreshold: 72
            )
    
            #expect(isPinned == false)
        }

        @Test func transcriptScrollPinningRepinsWhenViewportReturnsNearBottom() {
            let metrics = TranscriptScrollMetrics(
                contentOffsetY: 1_120,
                contentHeight: 1_600,
                visibleMaxY: 1_548
            )
    
            let isPinned = TranscriptScrollPinning.nextPinnedState(
                for: metrics,
                previousOffsetY: 1_120,
                isMaintainingPinnedPosition: false,
                autoScrollThreshold: 72
            )
    
            #expect(isPinned)
        }

        @Test func transcriptScrollPinningStaysPinnedDuringProgrammaticScroll() {
            let metrics = TranscriptScrollMetrics(
                contentOffsetY: 320,
                contentHeight: 1_600,
                visibleMaxY: 1_200
            )
    
            let isPinned = TranscriptScrollPinning.nextPinnedState(
                for: metrics,
                previousOffsetY: 380,
                isMaintainingPinnedPosition: true,
                autoScrollThreshold: 72
            )
    
            #expect(isPinned)
        }
}
