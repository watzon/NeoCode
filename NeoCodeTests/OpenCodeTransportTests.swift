import Foundation
import Testing
@testable import NeoCode

@MainActor
@Suite(.serialized)
struct OpenCodeTransportTests {
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
    
                return (response, Data("{\"ok\":true}".utf8))
            }
    
            let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
            let client = NeoCodeClient(
                connection: OpenCodeRuntime.Connection(
                    projectPath: "/tmp/NeoCode",
                    baseURL: baseURL,
                    username: "user",
                    password: "pass",
                    version: "1.0.0",
                    workspaceID: "ws_1"
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
                fileReferences: [],
                options: nil
            )
    
            let request = try #require(capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/sessions/ses_1/prompt")
    
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
        @Test func openCodeClientDecodesRevertSessionResponse() async throws {
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
                      "id": "ses_1",
                      "title": "Existing",
                      "parentId": null,
                      "createdAt": "2026-03-13T10:00:00Z",
                      "updatedAt": "2026-03-13T10:05:00Z",
                      "summary": {
                        "additions": 4,
                        "deletions": 1,
                        "files": 1,
                        "diffs": [
                          {
                            "file": "Sources/App.swift",
                            "before": "",
                            "after": "",
                            "additions": 4,
                            "deletions": 1,
                            "status": "modified"
                          }
                        ]
                      },
                      "revert": {
                        "messageId": "msg_user_1"
                      }
                    }
                    """.utf8
                )
                return (response, body)
            }
    
            let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
            let client = NeoCodeClient(
                connection: OpenCodeRuntime.Connection(
                    projectPath: "/tmp/NeoCode",
                    baseURL: baseURL,
                    username: "user",
                    password: "pass",
                    version: "1.0.0",
                    workspaceID: "ws_1"
                ),
                session: session
            )
    
            let reverted = try await client.revertSession(sessionID: "ses_1", messageID: "msg_user_1", partID: nil)
    
            let request = try #require(capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/sessions/ses_1/revert")
            let bodyData = try requestBodyData(from: request)
            let body = try #require(bodyData)
            let payload = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["messageID"] as? String == "msg_user_1")
            #expect(reverted.id == "ses_1")
            #expect(reverted.revert?.messageID == "msg_user_1")
            #expect(reverted.summary?.files == 1)
        }

        @MainActor
        @Test func openCodeClientDecodesUnrevertSessionResponse() async throws {
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
                      "id": "ses_1",
                      "title": "Existing",
                      "parentId": null,
                      "createdAt": "2026-03-13T10:00:00Z",
                      "updatedAt": "2026-03-13T10:05:00Z"
                    }
                    """.utf8
                )
                return (response, body)
            }
    
            let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
            let client = NeoCodeClient(
                connection: OpenCodeRuntime.Connection(
                    projectPath: "/tmp/NeoCode",
                    baseURL: baseURL,
                    username: "user",
                    password: "pass",
                    version: "1.0.0",
                    workspaceID: "ws_1"
                ),
                session: session
            )
    
            let restored = try await client.unrevertSession(sessionID: "ses_1")
    
            let request = try #require(capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/sessions/ses_1/unrevert")
            #expect(restored.id == "ses_1")
        }

        @MainActor
        @Test func openCodeClientPostsSlashCommandRequests() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MockURLProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { MockURLProtocol.requestHandler = nil }

            MockURLProtocol.requestHandler = { request in
                guard let url = request.url,
                      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
                else {
                    throw URLError(.badServerResponse)
                }
    
                return (response, Data("{\"ok\":true}".utf8))
            }
    
            let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
            let client = NeoCodeClient(
                connection: OpenCodeRuntime.Connection(
                    projectPath: "/tmp/NeoCode",
                    baseURL: baseURL,
                    username: "user",
                    password: "pass",
                    version: "1.0.0",
                    workspaceID: "ws_1"
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
                fileReferences: [],
                options: OpenCodePromptOptions(
                    model: ComposerModelOption(
                        id: "openai/gpt-5.4",
                        providerID: "openai",
                        modelID: "gpt-5.4",
                        title: "GPT-5.4",
                        contextWindow: nil,
                        variants: ["high"]
                    ),
                    agentName: "builder",
                    variant: "high"
                )
            )

        }

        @MainActor
        @Test func openCodeClientPostsMentionFileReferences() async throws {
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
    
                return (response, Data("{\"ok\":true}".utf8))
            }
    
            let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
            let client = NeoCodeClient(
                connection: OpenCodeRuntime.Connection(
                    projectPath: "/tmp/NeoCode",
                    baseURL: baseURL,
                    username: "user",
                    password: "pass",
                    version: "1.0.0",
                    workspaceID: "ws_1"
                ),
                session: session
            )
    
            try await client.sendPromptAsync(
                sessionID: "ses_1",
                text: "Review @Docs/Guide.md",
                attachments: [],
                fileReferences: [
                    ComposerPromptFileReference(
                        relativePath: "Docs/Guide.md",
                        absolutePath: "/tmp/NeoCode/Docs/Guide.md",
                        sourceText: .init(value: "@Docs/Guide.md", start: 7, end: 21)
                    ),
                ],
                options: nil
            )
    
            let request = try #require(capturedRequest)
            let bodyData = try requestBodyData(from: request)
            let payloadData = try #require(bodyData)
            let payload = try #require(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
            let parts = try #require(payload["parts"] as? [[String: Any]])
            #expect(parts.count == 2)
            #expect(parts[1]["type"] as? String == "file")
            #expect(parts[1]["filename"] as? String == "Docs/Guide.md")
            #expect(parts[1]["url"] as? String == "file:///tmp/NeoCode/Docs/Guide.md")
    
            let source = try #require(parts[1]["source"] as? [String: Any])
            let textSource = try #require(source["text"] as? [String: Any])
            #expect(source["type"] as? String == "file")
            #expect(source["path"] as? String == "/tmp/NeoCode/Docs/Guide.md")
            #expect(textSource["value"] as? String == "@Docs/Guide.md")
            #expect(textSource["start"] as? Int == 7)
            #expect(textSource["end"] as? Int == 21)
        }

        @MainActor
        @Test func openCodeClientPostsAbortForSession() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MockURLProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { MockURLProtocol.requestHandler = nil }
    
            MockURLProtocol.requestHandler = { request in
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/v1/sessions/ses_1/abort")
                #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
    
                guard let url = request.url,
                      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
                else {
                    throw URLError(.badServerResponse)
                }
    
                return (response, Data("{\"ok\":true}".utf8))
            }
    
            let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
            let client = NeoCodeClient(
                connection: OpenCodeRuntime.Connection(
                    projectPath: "/tmp/NeoCode",
                    baseURL: baseURL,
                    username: "user",
                    password: "pass",
                    version: "1.0.0",
                    workspaceID: "ws_1"
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
                #expect(request.url?.path == "/v1/workspaces/ws_1/session-status")
    
                guard let url = request.url,
                      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
                else {
                    throw URLError(.badServerResponse)
                }
    
                let payload = Data("{\"ses_1\":{\"type\":\"busy\"}}".utf8)
                return (response, payload)
            }
    
            let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
            let client = NeoCodeClient(
                connection: OpenCodeRuntime.Connection(
                    projectPath: "/tmp/NeoCode",
                    baseURL: baseURL,
                    username: "user",
                    password: "pass",
                    version: "1.0.0",
                    workspaceID: "ws_1"
                ),
                session: session
            )
    
            let statuses = try await client.listSessionStatuses()
            #expect(statuses["ses_1"] == .busy)
        }

        @MainActor
        @Test func openCodeClientPostsSessionSummarizeRequest() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MockURLProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { MockURLProtocol.requestHandler = nil }

            MockURLProtocol.requestHandler = { request in
                guard let url = request.url,
                      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
                else {
                    throw URLError(.badServerResponse)
                }
    
                return (response, Data("{\"ok\":true}".utf8))
            }
    
            let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
            let client = NeoCodeClient(
                connection: OpenCodeRuntime.Connection(
                    projectPath: "/tmp/NeoCode",
                    baseURL: baseURL,
                    username: "user",
                    password: "pass",
                    version: "1.0.0",
                    workspaceID: "ws_1"
                ),
                session: session
            )

            try await client.summarizeSession(sessionID: "ses_1", providerID: "openai", modelID: "gpt-5.4", auto: false)
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
    
                return (response, Data("{\"ok\":true}".utf8))
            }
    
            let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
            let client = NeoCodeClient(
                connection: OpenCodeRuntime.Connection(
                    projectPath: "/tmp/NeoCode",
                    baseURL: baseURL,
                    username: "user",
                    password: "pass",
                    version: "1.0.0",
                    workspaceID: "ws_1"
                ),
                session: session
            )
    
            try await client.replyToPermission(requestID: "perm_1", reply: .always, message: nil)
    
            let request = try #require(capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/permissions/perm_1/reply")
    
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
    
                return (response, Data("{\"ok\":true}".utf8))
            }
    
            let baseURL = try #require(URL(string: "http://127.0.0.1:4000"))
            let client = NeoCodeClient(
                connection: OpenCodeRuntime.Connection(
                    projectPath: "/tmp/NeoCode",
                    baseURL: baseURL,
                    username: "user",
                    password: "pass",
                    version: "1.0.0",
                    workspaceID: "ws_1"
                ),
                session: session
            )
    
            try await client.replyToQuestion(requestID: "que_1", answers: [["Yes"], ["Type your own answer"]])
    
            let request = try #require(capturedRequest)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/questions/que_1/reply")
    
            let bodyData = try requestBodyData(from: request)
            let body = try #require(bodyData)
            let payload = try JSONDecoder().decode(QuestionReplyPayload.self, from: body)
            #expect(payload.answers == [["Yes"], ["Type your own answer"]])
        }
}
