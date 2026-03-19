import Foundation
import Testing
@testable import NeoCode

@MainActor
@Suite(.serialized)
struct OpenCodeDecodingTests {
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

        @Test func rejectedQuestionToolPartsRenderAsCancelled() {
            let timestamp = Date(timeIntervalSince1970: 1_710_616_270)
            let part = OpenCodePart(
                id: "part_question_rejected",
                sessionID: "ses_1",
                messageID: "msg_1",
                type: .tool,
                text: nil,
                tool: "functions.question",
                mime: nil,
                filename: nil,
                url: nil,
                source: nil,
                state: OpenCodeToolState(
                    status: .error,
                    input: nil,
                    output: nil,
                    error: "QuestionRejectedError"
                ),
                time: OpenCodeTimeContainer(created: timestamp, updated: timestamp, completed: timestamp)
            )
    
            #expect(part.renderedText == "question cancelled")
            #expect(part.shouldDisplay == true)
        }

        @Test func decodesSessionCompactedEvent() throws {
            let event = try OpenCodeEventDecoder.decode(
                frame: OpenCodeSSEFrame(
                    event: "session.compacted",
                    data: "{\"type\":\"session.compacted\",\"properties\":{\"sessionID\":\"ses_1\"}}"
                )
            )
    
            switch event {
            case .sessionCompacted(let sessionID):
                #expect(sessionID == "ses_1")
            default:
                Issue.record("Expected session.compacted event")
            }
        }

        @Test func decodesAssistantUsageMetadataFromMessages() throws {
            let envelopes: [OpenCodeMessageEnvelope] = try decode(
                """
                [
                  {
                    "info": {
                      "id": "msg_usage",
                      "sessionID": "ses_usage",
                      "role": "assistant",
                      "agent": "builder",
                      "providerID": "openai",
                      "modelID": "gpt-5.4",
                      "cost": 1.25,
                      "tokens": {
                        "total": 420,
                        "input": 120,
                        "output": 240,
                        "reasoning": 40,
                        "cache": {
                          "read": 12,
                          "write": 8
                        }
                      },
                      "time": {
                        "created": "2026-03-13T10:06:00Z",
                        "updated": "2026-03-13T10:06:10Z",
                        "completed": "2026-03-13T10:06:10Z"
                      }
                    },
                    "parts": []
                  }
                ]
                """
            )
    
            let message = try #require(envelopes.first)
            #expect(message.info.providerID == "openai")
            #expect(message.info.modelID == "gpt-5.4")
            #expect(message.info.cost == 1.25)
            #expect(message.info.tokens?.input == 120)
            #expect(message.info.tokens?.output == 240)
            #expect(message.info.tokens?.reasoning == 40)
            #expect(message.info.tokens?.cache?.read == 12)
            #expect(message.info.tokens?.cache?.write == 8)
        }

        @Test func decodesUserMessageSummaryObjectsWithoutFailing() throws {
            let envelopes: [OpenCodeMessageEnvelope] = try decode(
                """
                [
                  {
                    "info": {
                      "id": "msg_user_summary",
                      "sessionID": "ses_summary",
                      "role": "user",
                      "summary": {
                        "title": "Context snapshot",
                        "body": "What happened so far",
                        "diffs": []
                      },
                      "agent": "builder",
                      "time": {
                        "created": 1741860000
                      }
                    },
                    "parts": [
                      {
                        "id": "part_text",
                        "sessionID": "ses_summary",
                        "messageID": "msg_user_summary",
                        "type": "text",
                        "text": "Please continue from here.",
                        "time": {
                          "created": 1741860000
                        }
                      }
                    ]
                  }
                ]
                """
            )
    
            #expect(envelopes.count == 1)
            #expect(envelopes[0].info.isSummaryMessage == false)
            #expect(envelopes[0].parts.first?.text == "Please continue from here.")
        }

        @Test func transcriptDropsSerializedFileDumpForUserFileReferences() throws {
            let envelopes: [OpenCodeMessageEnvelope] = try decode(
                """
                [
                  {
                    "info": {
                      "id": "msg_user_file_dump",
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
                        "messageID": "msg_user_file_dump",
                        "type": "text",
                        "text": "Ok this is just a test @AGENTS.md\\n\\nJust give a short response.",
                        "time": {
                          "created": 1741860000
                        }
                      },
                      {
                        "id": "part_file",
                        "sessionID": "ses_summary",
                        "messageID": "msg_user_file_dump",
                        "type": "file",
                        "mime": "text/plain",
                        "filename": "AGENTS.md",
                        "url": "file:///tmp/AGENTS.md",
                        "source": {
                          "path": "AGENTS.md",
                          "text": {
                            "value": "@AGENTS.md",
                            "start": 24,
                            "end": 34
                          }
                        },
                        "time": {
                          "created": 1741860000
                        }
                      },
                      {
                        "id": "part_dump",
                        "sessionID": "ses_summary",
                        "messageID": "msg_user_file_dump",
                        "type": "text",
                        "text": "<path>/tmp/AGENTS.md</path>\\n<type>file</type>\\n<content>1: hello</content>",
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
            #expect(transcript.count == 2)
            #expect(transcript.contains(where: { $0.text.contains("Ok this is just a test @AGENTS.md") }))
            #expect(transcript.contains(where: { $0.attachment?.displayTitle == "AGENTS.md" }))
            #expect(transcript.contains(where: { $0.text.contains("<path>") }) == false)
        }

        @Test func computesSessionStatsFromLatestAssistantUsage() throws {
            let envelopes: [OpenCodeMessageEnvelope] = try decode(
                """
                [
                  {
                    "info": {
                      "id": "msg_first",
                      "sessionID": "ses_usage",
                      "role": "assistant",
                      "agent": "builder",
                      "providerID": "openai",
                      "modelID": "gpt-5.4",
                      "cost": 0.4,
                      "tokens": {
                        "total": 600,
                        "input": 200,
                        "output": 300,
                        "reasoning": 50,
                        "cache": {
                          "read": 30,
                          "write": 20
                        }
                      },
                      "time": {
                        "created": "2026-03-13T10:06:00Z",
                        "completed": "2026-03-13T10:06:10Z"
                      }
                    },
                    "parts": []
                  },
                  {
                    "info": {
                      "id": "msg_latest",
                      "sessionID": "ses_usage",
                      "role": "assistant",
                      "agent": "builder",
                      "providerID": "openai",
                      "modelID": "gpt-5.4",
                      "cost": 0.6,
                      "tokens": {
                        "total": 1200,
                        "input": 500,
                        "output": 450,
                        "reasoning": 100,
                        "cache": {
                          "read": 100,
                          "write": 50
                        }
                      },
                      "time": {
                        "created": "2026-03-13T10:08:00Z",
                        "completed": "2026-03-13T10:08:15Z"
                      }
                    },
                    "parts": []
                  }
                ]
                """
            )
    
            let stats = SessionStatsSnapshot.make(
                sessionID: "ses_usage",
                messageInfos: envelopes.map(\.info),
                models: [
                    ComposerModelOption(
                        id: "openai/gpt-5.4",
                        providerID: "openai",
                        modelID: "gpt-5.4",
                        title: "GPT-5.4",
                        contextWindow: 2000,
                        variants: ["high"]
                    )
                ]
            )
    
            let resolved = try #require(stats)
            #expect(resolved.modelDisplayName == "GPT-5.4")
            #expect(resolved.totalContextTokens == 1200)
            #expect(resolved.contextUsedTokens == 1200)
            #expect(resolved.remainingContextTokens == 800)
            #expect(resolved.percentUsed == 60)
            #expect(resolved.totalCost == 1.0)
            #expect(resolved.inputTokens == 500)
            #expect(resolved.outputTokens == 450)
            #expect(resolved.reasoningTokens == 100)
            #expect(resolved.cacheReadTokens == 100)
            #expect(resolved.cacheWriteTokens == 50)
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

        @MainActor
        @Test func generalSettingsDecodeLegacyLaunchFlag() throws {
            let payload = #"{"launchToDashboard":false}"#
            let settings = try JSONDecoder().decode(NeoCodeGeneralSettings.self, from: Data(payload.utf8))
    
            #expect(settings.startupBehavior == .lastWorkspace)
            #expect(settings.sendKeyBehavior == .returnKey)
            #expect(settings.opencodeExecutablePath == nil)
            #expect(settings.restoresPromptDrafts == true)
            #expect(settings.remembersYoloModePerThread == true)
            #expect(settings.appLanguage == .system)
        }

        @MainActor
        @Test func persistedWorkspaceSelectionStoreRoundTripsSelection() {
            let suiteName = "tech.watzon.NeoCodeTests.workspace-selection.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            defer {
                defaults.removePersistentDomain(forName: suiteName)
            }
    
            let store = PersistedWorkspaceSelectionStore(defaults: defaults, key: "workspaceSelection")
            let selection = PersistedWorkspaceSelectionStore.Selection(
                kind: .session,
                projectID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
                sessionID: "ses_123"
            )
    
            store.saveSelection(selection)
    
            #expect(store.loadSelection() == selection)
        }
}
