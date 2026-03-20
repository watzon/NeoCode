import Foundation
import OSLog

protocol NeoCodeServicing {
    func listSessions() async throws -> [OpenCodeSession]
    func listSessionStatuses() async throws -> [String: OpenCodeSessionActivity]
    func listPermissions() async throws -> [OpenCodePermissionRequest]
    func listQuestions() async throws -> [OpenCodeQuestionRequest]
    func listCommands() async throws -> [OpenCodeCommand]
    func createSession(title: String?) async throws -> OpenCodeSession
    func updateSession(sessionID: String, title: String) async throws -> OpenCodeSession
    func deleteSession(sessionID: String) async throws -> Bool
    func summarizeSession(sessionID: String, providerID: String, modelID: String, auto: Bool) async throws
    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> OpenCodeSession
    func unrevertSession(sessionID: String) async throws -> OpenCodeSession
    func abortSession(sessionID: String) async throws
    func replyToPermission(requestID: String, reply: OpenCodePermissionReply, message: String?) async throws
    func replyToQuestion(requestID: String, answers: [OpenCodeQuestionAnswer]) async throws
    func rejectQuestion(requestID: String) async throws
    func listProviders() async throws -> OpenCodeProviderResponse
    func listAgents() async throws -> [OpenCodeAgent]
    func listMessages(sessionID: String) async throws -> [OpenCodeMessageEnvelope]
    func listDashboardSessionSummaries(sessionIDs: [String]) async throws -> [DashboardRemoteSessionSummary]
    func gitStatus() async throws -> GitRepositoryStatus
    func gitCommitPreview() async throws -> GitCommitPreview
    func initializeGitRepository() async throws
    func switchGitBranch(named name: String) async throws
    func createGitBranch(named name: String) async throws
    func commitGitChanges(message: String, includeUnstaged: Bool) async throws
    func pushGitChanges() async throws
    func listGitBranches() async throws -> (branches: [String], current: String)
    func sendPromptAsync(
        sessionID: String,
        text: String,
        attachments: [ComposerAttachment],
        fileReferences: [ComposerPromptFileReference],
        options: OpenCodePromptOptions?
    ) async throws
    func sendCommand(
        sessionID: String,
        command: String,
        arguments: String,
        attachments: [ComposerAttachment],
        fileReferences: [ComposerPromptFileReference],
        options: OpenCodePromptOptions?
    ) async throws
    func eventStream() throws -> AsyncThrowingStream<OpenCodeEvent, Error>
}


final class NeoCodeClient: NeoCodeServicing {
    private let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "NeoCodeClient")
    private let connection: OpenCodeRuntime.Connection
    private let session: URLSession
    private let decoder: JSONDecoder

    init(connection: OpenCodeRuntime.Connection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
        self.decoder = JSONDecoder.opencode
    }

    func listSessions() async throws -> [OpenCodeSession] {
        try await nativeListSessions()
    }

    func listSessionStatuses() async throws -> [String: OpenCodeSessionActivity] {
        try await request(path: workspacePath("session-status"), method: "GET")
    }

    func listPermissions() async throws -> [OpenCodePermissionRequest] {
        let response: [NativePermissionRequest] = try await request(path: workspacePath("permissions"), method: "GET")
        return response.map(\.openCode)
    }

    func listQuestions() async throws -> [OpenCodeQuestionRequest] {
        let response: [NativeQuestionRequest] = try await request(path: workspacePath("questions"), method: "GET")
        return response.map(\.openCode)
    }

    func listCommands() async throws -> [OpenCodeCommand] {
        try await request(path: workspacePath("commands"), method: "GET")
    }

    func createSession(title: String?) async throws -> OpenCodeSession {
        logger.info("POST /session for project: \(self.connection.projectPath, privacy: .public)")
        let body = CreateSessionBody(title: title)
        let session: NativeSession = try await request(path: workspacePath("sessions"), method: "POST", body: body)
        return session.openCode
    }

    func updateSession(sessionID: String, title: String) async throws -> OpenCodeSession {
        logger.info("PATCH /session/\(sessionID, privacy: .public)")
        let session: NativeSession = try await request(path: "/v1/sessions/\(sessionID)", method: "PATCH", body: UpdateSessionBody(title: title))
        return session.openCode
    }

    func deleteSession(sessionID: String) async throws -> Bool {
        logger.info("DELETE /session/\(sessionID, privacy: .public)")
        let response: NativeBooleanResponse = try await request(path: "/v1/sessions/\(sessionID)", method: "DELETE")
        return response.ok
    }

    func summarizeSession(sessionID: String, providerID: String, modelID: String, auto: Bool = false) async throws {
        logger.info(
            "POST /session/\(sessionID, privacy: .public)/summarize provider=\(providerID, privacy: .public) model=\(modelID, privacy: .public) auto=\(auto, privacy: .public)"
        )
        let _: Bool = try await request(
            path: "/v1/sessions/\(sessionID)/summarize",
            method: "POST",
            body: SummarizeSessionBody(providerID: providerID, modelID: modelID, auto: auto)
        )
    }

    func revertSession(sessionID: String, messageID: String, partID: String? = nil) async throws -> OpenCodeSession {
        logger.info("POST /session/\(sessionID, privacy: .public)/revert messageID=\(messageID, privacy: .public)")
        let session: NativeSession = try await request(
            path: "/v1/sessions/\(sessionID)/revert",
            method: "POST",
            body: RevertSessionBody(messageID: messageID, partID: partID)
        )
        return session.openCode
    }

    func unrevertSession(sessionID: String) async throws -> OpenCodeSession {
        logger.info("POST /session/\(sessionID, privacy: .public)/unrevert")
        let session: NativeSession = try await request(path: "/v1/sessions/\(sessionID)/unrevert", method: "POST", body: Optional<EmptyRequest>.none)
        return session.openCode
    }

    func abortSession(sessionID: String) async throws {
        logger.info("POST /session/\(sessionID, privacy: .public)/abort")
        let _: NativeBooleanResponse = try await request(path: "/v1/sessions/\(sessionID)/abort", method: "POST", body: Optional<EmptyRequest>.none)
    }

    func replyToPermission(requestID: String, reply: OpenCodePermissionReply, message: String?) async throws {
        logger.info("POST /permission/\(requestID, privacy: .public)/reply type=\(reply.rawValue, privacy: .public)")
        let _: NativeBooleanResponse = try await request(
            path: "/v1/permissions/\(requestID)/reply",
            method: "POST",
            body: NativePermissionReplyBody(workspaceId: try workspaceID(), reply: reply, message: message)
        )
    }

    func replyToQuestion(requestID: String, answers: [OpenCodeQuestionAnswer]) async throws {
        logger.info("POST /question/\(requestID, privacy: .public)/reply answers=\(answers.count, privacy: .public)")
        let _: NativeBooleanResponse = try await request(
            path: "/v1/questions/\(requestID)/reply",
            method: "POST",
            body: NativeQuestionReplyBody(workspaceId: try workspaceID(), answers: answers)
        )
    }

    func rejectQuestion(requestID: String) async throws {
        logger.info("POST /question/\(requestID, privacy: .public)/reject")
        let _: NativeBooleanResponse = try await request(path: "/v1/questions/\(requestID)/reject", method: "POST", body: NativeWorkspaceBody(workspaceId: try workspaceID()))
    }

    func listProviders() async throws -> OpenCodeProviderResponse {
        let response: NativeProviderResponse = try await request(path: workspacePath("providers"), method: "GET")
        return response.openCode
    }

    func listAgents() async throws -> [OpenCodeAgent] {
        let response: [NativeAgent] = try await request(path: workspacePath("agents"), method: "GET")
        return response.map(\.openCode)
    }

    func listMessages(sessionID: String) async throws -> [OpenCodeMessageEnvelope] {
        try await request(path: "/v1/sessions/\(sessionID)/messages", method: "GET")
    }

    func listDashboardSessionSummaries(sessionIDs: [String]) async throws -> [DashboardRemoteSessionSummary] {
        guard let workspaceID = connection.workspaceID else {
            throw NeoCodeClientError.invalidResponse
        }

        struct Body: Encodable {
            let sessionIDs: [String]
        }

        return try await request(
            path: "/v1/workspaces/\(workspaceID)/dashboard/sessions",
            method: "POST",
            body: Body(sessionIDs: sessionIDs)
        )
    }

    func gitStatus() async throws -> GitRepositoryStatus {
        let response: NativeGitStatus = try await request(path: workspacePath("git/status"), method: "GET")
        return response.appStatus
    }

    func gitCommitPreview() async throws -> GitCommitPreview {
        let response: NativeGitCommitPreview = try await request(path: workspacePath("git/preview"), method: "GET")
        return response.appPreview
    }

    func initializeGitRepository() async throws {
        let _: NativeBooleanResponse = try await request(path: workspacePath("git/initialize"), method: "POST", body: Optional<EmptyRequest>.none)
    }

    func switchGitBranch(named name: String) async throws {
        let _: NativeBooleanResponse = try await request(path: workspacePath("git/switch"), method: "POST", body: NativeGitBranchBody(branch: name))
    }

    func createGitBranch(named name: String) async throws {
        let _: NativeBooleanResponse = try await request(path: workspacePath("git/create-branch"), method: "POST", body: NativeGitBranchBody(branch: name))
    }

    func commitGitChanges(message: String, includeUnstaged: Bool) async throws {
        let _: NativeBooleanResponse = try await request(path: workspacePath("git/commit"), method: "POST", body: NativeGitCommitBody(message: message, includeUnstaged: includeUnstaged))
    }

    func pushGitChanges() async throws {
        let _: NativeBooleanResponse = try await request(path: workspacePath("git/push"), method: "POST", body: Optional<EmptyRequest>.none)
    }

    func listGitBranches() async throws -> (branches: [String], current: String) {
        let response: NativeGitBranchesResponse = try await request(path: workspacePath("git/branches"), method: "GET")
        return (response.branches, response.current)
    }

    func sendPromptAsync(
        sessionID: String,
        text: String,
        attachments: [ComposerAttachment],
        fileReferences: [ComposerPromptFileReference],
        options: OpenCodePromptOptions?
    ) async throws {
        let modelLabel = options?.model?.id ?? "default"
        let agentLabel = options?.agentName ?? "default"
        let variantLabel = options?.variant ?? "default"
        logger.info(
            "POST /session/\(sessionID, privacy: .public)/prompt_async textLength=\(text.count, privacy: .public) attachments=\(attachments.count, privacy: .public) fileRefs=\(fileReferences.count, privacy: .public) model=\(modelLabel, privacy: .public) agent=\(agentLabel, privacy: .public) variant=\(variantLabel, privacy: .public)"
        )
        let startedAt = Date()
        let body = SendPromptBody(
            parts: [.text(text)]
                + fileReferences.map { .fileReference($0) }
                + attachments.map { .file(mime: $0.mimeType, filename: $0.name, url: $0.requestURL) },
            model: options?.model.map { SendPromptBody.Model(providerID: $0.providerID, modelID: $0.modelID) },
            agent: options?.agentName,
            variant: options?.variant
        )
        let _: NativeBooleanResponse = try await request(path: "/v1/sessions/\(sessionID)/prompt", method: "POST", body: body.native)
        logger.info(
            "Prompt accepted for session \(sessionID, privacy: .public) after \(Date().timeIntervalSince(startedAt), privacy: .public)s"
        )
    }

    func sendCommand(
        sessionID: String,
        command: String,
        arguments: String,
        attachments: [ComposerAttachment],
        fileReferences: [ComposerPromptFileReference],
        options: OpenCodePromptOptions?
    ) async throws {
        let modelLabel = options?.model?.id ?? "default"
        let agentLabel = options?.agentName ?? "default"
        let variantLabel = options?.variant ?? "default"
        logger.info(
            "POST /session/\(sessionID, privacy: .public)/command name=\(command, privacy: .public) argumentLength=\(arguments.count, privacy: .public) attachments=\(attachments.count, privacy: .public) fileRefs=\(fileReferences.count, privacy: .public) model=\(modelLabel, privacy: .public) agent=\(agentLabel, privacy: .public) variant=\(variantLabel, privacy: .public)"
        )
        let startedAt = Date()
        let body = SendCommandBody(
            command: command,
            arguments: arguments,
            agent: options?.agentName,
            model: options?.model.map { "\($0.providerID)/\($0.modelID)" },
            variant: options?.variant,
            parts: {
                let parts = fileReferences.map { SendPromptBody.Part.fileReference($0) }
                    + attachments.map { .file(mime: $0.mimeType, filename: $0.name, url: $0.requestURL) }
                return parts.isEmpty ? nil : parts
            }()
        )
        let _: NativeBooleanResponse = try await request(path: "/v1/sessions/\(sessionID)/command", method: "POST", body: body.native)
        logger.info(
            "Command accepted for session \(sessionID, privacy: .public) after \(Date().timeIntervalSince(startedAt), privacy: .public)s"
        )
    }

    func eventStream() throws -> AsyncThrowingStream<OpenCodeEvent, Error> {
        let request = try makeRequest(path: workspacePath("events"), method: "GET", body: Optional<EmptyRequest>.none, accept: "text/event-stream")
        let session = self.session
        let decoder = self.decoder
        let logger = self.logger

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let requestURL = request.url?.absoluteString ?? "<missing-url>"
                    logger.info("Opening SSE stream: \(requestURL, privacy: .public)")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          200..<300 ~= httpResponse.statusCode
                    else {
                        throw NeoCodeClientError.invalidResponse
                    }

                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "<missing>"
                    logger.info(
                        "SSE connected status=\(httpResponse.statusCode, privacy: .public) contentType=\(contentType, privacy: .public)"
                    )
                    if !contentType.localizedCaseInsensitiveContains("text/event-stream") {
                        logger.warning("Unexpected SSE content type: \(contentType, privacy: .public)")
                    }

                    var parser = OpenCodeSSEParser()
                    var lineBuffer = Data()

                    func emit(_ frame: OpenCodeSSEFrame, final: Bool = false) async {
                        do {
                            let event = try await MainActor.run {
                                try OpenCodeEventDecoder.decode(frame: frame, decoder: decoder)
                            }
                            continuation.yield(event)
                        } catch {
                            let frameEvent = frame.event ?? "message"
                            let payloadPreview = String(frame.data.prefix(500))
                            logger.error(
                                "Failed to decode \(final ? "final " : "")SSE frame event=\(frameEvent, privacy: .public) error=\(error.localizedDescription, privacy: .public) payload=\(payloadPreview, privacy: .public)"
                            )
                        }
                    }

                    func processLine(_ data: Data) async {
                        let line = String(decoding: data, as: UTF8.self)
                        if let frame = parser.ingest(line: line) {
                            await emit(frame)
                        }
                    }

                    for try await byte in bytes {
                        if byte == 0x0A {
                            var line = lineBuffer
                            if line.last == 0x0D {
                                line.removeLast()
                            }
                            await processLine(line)
                            lineBuffer.removeAll(keepingCapacity: true)
                        } else {
                            lineBuffer.append(byte)
                        }
                    }

                    if !lineBuffer.isEmpty {
                        await processLine(lineBuffer)
                    }

                    if let frame = parser.flush() {
                        await emit(frame, final: true)
                    }

                    logger.warning("SSE stream ended")
                    continuation.finish()
                } catch {
                    logger.error("SSE stream failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { termination in
                let _ = termination
                task.cancel()
            }
        }
    }

    private func request<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body? = nil) async throws -> Response {
        let request = try makeRequest(path: path, method: method, body: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NeoCodeClientError.invalidResponse
        }

        if httpResponse.statusCode == 204, Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            logger.error("HTTP \(httpResponse.statusCode) for \(method, privacy: .public) \(path, privacy: .public)")
            throw NeoCodeClientError.httpStatus(httpResponse.statusCode, serverErrorMessage(from: data))
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func request<Response: Decodable>(path: String, method: String) async throws -> Response {
        let request = try makeRequest(path: path, method: method, body: Optional<EmptyRequest>.none)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NeoCodeClientError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            logger.error("HTTP \(httpResponse.statusCode) for \(method, privacy: .public) \(path, privacy: .public)")
            throw NeoCodeClientError.httpStatus(httpResponse.statusCode, serverErrorMessage(from: data))
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest<Body: Encodable>(path: String, method: String, body: Body?, accept: String = "application/json") throws -> URLRequest {
        let url = connection.baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.authorizationHeader(username: connection.username, password: connection.password), forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let workspaceID = connection.workspaceID {
            request.setValue(workspaceID, forHTTPHeaderField: "X-NeoCode-Workspace-ID")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func workspaceID() throws -> String {
        guard let workspaceID = connection.workspaceID else {
            throw NeoCodeClientError.invalidResponse
        }
        return workspaceID
    }

    private func workspacePath(_ suffix: String) throws -> String {
        "/v1/workspaces/\(try workspaceID())/\(suffix)"
    }

    private func serverErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        if let payload = try? JSONDecoder().decode(ServerErrorPayload.self, from: data),
           let message = payload.error?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }

        let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return message?.isEmpty == false ? message : nil
    }

    private func nativeListSessions() async throws -> [OpenCodeSession] {
        let sessions: [NativeSession] = try await request(path: workspacePath("sessions"), method: "GET")
        return sessions.map(\.openCode)
    }

    private static func authorizationHeader(username: String, password: String) -> String {
        let token = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }
}

private struct CreateSessionBody: Encodable {
    let title: String?

    private enum CodingKeys: String, CodingKey {
        case title
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
    }
}

private struct UpdateSessionBody: Encodable {
    let title: String
}

private struct RevertSessionBody: Encodable {
    let messageID: String
    let partID: String?
}

private struct SummarizeSessionBody: Encodable {
    let providerID: String
    let modelID: String
    let auto: Bool
}

private struct SendPromptBody: Encodable {
    struct Model: Encodable {
        let providerID: String
        let modelID: String
    }

    enum Part: Encodable {
        case text(String)
        case file(mime: String, filename: String?, url: String)
        case fileReference(ComposerPromptFileReference)

        private struct SourceText: Encodable {
            let value: String
            let start: Int
            let end: Int
        }

        private struct Source: Encodable {
            let type: String
            let text: SourceText
            let path: String
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case mime
            case filename
            case url
            case source
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .file(let mime, let filename, let url):
                try container.encode("file", forKey: .type)
                try container.encode(mime, forKey: .mime)
                try container.encodeIfPresent(filename, forKey: .filename)
                try container.encode(url, forKey: .url)
            case .fileReference(let fileReference):
                try container.encode("file", forKey: .type)
                try container.encode("text/plain", forKey: .mime)
                try container.encode(fileReference.relativePath, forKey: .filename)
                try container.encode(fileReference.requestURL, forKey: .url)
                try container.encode(
                    Source(
                        type: "file",
                        text: SourceText(
                            value: fileReference.sourceText.value,
                            start: fileReference.sourceText.start,
                            end: fileReference.sourceText.end
                        ),
                        path: fileReference.absolutePath
                    ),
                    forKey: .source
                )
            }
        }
    }

    let parts: [Part]
    let model: Model?
    let agent: String?
    let variant: String?

    var native: NativePromptBody {
        NativePromptBody(
            text: nil,
            parts: parts.map(\.native),
            providerID: model?.providerID,
            modelID: model?.modelID,
            agent: agent,
            variant: variant
        )
    }
}

private struct SendCommandBody: Encodable {
    let command: String
    let arguments: String
    let agent: String?
    let model: String?
    let variant: String?
    let parts: [SendPromptBody.Part]?

    var native: NativeCommandBody {
        NativeCommandBody(
            command: command,
            arguments: arguments,
            parts: parts?.map(\.native) ?? [],
            agent: agent,
            model: model,
            variant: variant
        )
    }
}

private struct NativeWorkspaceBody: Encodable {
    let workspaceId: String
}

private struct NativeGitStatus: Decodable {
    let branch: String
    let aheadCount: Int
    let hasRemote: Bool
    let hasChanges: Bool

    var appStatus: GitRepositoryStatus {
        GitRepositoryStatus(isRepository: true, hasChanges: hasChanges, aheadCount: aheadCount, hasRemote: hasRemote)
    }
}

private struct NativeGitChange: Decodable {
    let path: String
    let status: String
    let isTracked: Bool
    let isStaged: Bool
    let isUnstaged: Bool

    var appChange: GitFileChange {
        GitFileChange(path: path, stagedStatus: stagedCharacter, unstagedStatus: unstagedCharacter)
    }

    private var stagedCharacter: Character {
        guard isStaged else { return " " }
        switch status {
        case "new", "added": return "A"
        case "deleted": return "D"
        case "renamed": return "R"
        case "modified": return "M"
        default: return isTracked ? "M" : "?"
        }
    }

    private var unstagedCharacter: Character {
        if !isTracked { return "?" }
        guard isUnstaged else { return " " }
        switch status {
        case "added": return "A"
        case "deleted": return "D"
        case "renamed": return "R"
        case "modified", "changed": return "M"
        default: return "M"
        }
    }
}

private struct NativeGitCommitPreview: Decodable {
    let branch: String
    let changedFiles: [NativeGitChange]
    let stagedAdditions: Int
    let stagedDeletions: Int
    let unstagedAdditions: Int
    let unstagedDeletions: Int
    let totalAdditions: Int
    let totalDeletions: Int

    var appPreview: GitCommitPreview {
        GitCommitPreview(
            branch: branch,
            changedFiles: changedFiles.map(\.appChange),
            stagedAdditions: stagedAdditions,
            stagedDeletions: stagedDeletions,
            unstagedAdditions: unstagedAdditions,
            unstagedDeletions: unstagedDeletions,
            totalAdditions: totalAdditions,
            totalDeletions: totalDeletions
        )
    }
}

private struct NativeGitBranchBody: Encodable {
    let branch: String
}

private struct NativeGitCommitBody: Encodable {
    let message: String
    let includeUnstaged: Bool
}

private struct NativeGitBranchesResponse: Decodable {
    let branches: [String]
    let current: String
}

private struct NativePermissionReplyBody: Encodable {
    let workspaceId: String
    let reply: OpenCodePermissionReply
    let message: String?
}

private struct NativeQuestionReplyBody: Encodable {
    let workspaceId: String
    let answers: [OpenCodeQuestionAnswer]
}

private struct NativeBooleanResponse: Decodable {
    let ok: Bool
}

private struct ServerErrorPayload: Decodable {
    let error: String?
}

private struct NativeSession: Decodable {
    let id: String
    let title: String
    let parentId: String?
    let summary: OpenCodeSessionSummary?
    let revert: NativeSessionRevert?
    let createdAt: Date
    let updatedAt: Date

    var openCode: OpenCodeSession {
        OpenCodeSession(
            id: id,
            title: title,
            parentID: parentId,
            summary: summary,
            revert: revert?.openCode,
            time: OpenCodeTimeContainer(created: createdAt, updated: updatedAt, completed: nil)
        )
    }
}

private struct NativeSessionRevert: Decodable {
    let messageId: String
    let partId: String?
    let snapshot: String?
    let diff: String?

    var openCode: OpenCodeSessionRevert {
        .init(messageID: messageId, partID: partId, snapshot: snapshot, diff: diff)
    }
}

private struct NativePermissionRequest: Decodable {
    let id: String
    let sessionId: String
    let permission: String
    let patterns: [String]
    let metadata: [String: JSONValue]
    let always: [String]
    let tool: NativeToolReference?

    var openCode: OpenCodePermissionRequest {
        .init(id: id, sessionID: sessionId, permission: permission, patterns: patterns, metadata: metadata, always: always, tool: tool?.permissionTool)
    }
}

private struct NativeQuestionRequest: Decodable {
    let id: String
    let sessionId: String
    let questions: [OpenCodeQuestionInfo]
    let tool: NativeToolReference?

    var openCode: OpenCodeQuestionRequest {
        .init(id: id, sessionID: sessionId, questions: questions, tool: tool?.questionTool)
    }
}

private struct NativeToolReference: Decodable {
    let messageId: String
    let callId: String

    var permissionTool: OpenCodePermissionRequest.ToolReference {
        .init(messageID: messageId, callID: callId)
    }

    var questionTool: OpenCodeQuestionRequest.ToolReference {
        .init(messageID: messageId, callID: callId)
    }
}

private struct NativeProviderResponse: Decodable {
    let providers: [NativeProvider]
    let `default`: [String: String]?

    var openCode: OpenCodeProviderResponse {
        .init(providers: providers.map(\.openCode), default: `default`)
    }
}

private struct NativeProvider: Decodable {
    let id: String
    let name: String
    let models: [String: NativeModel]

    var openCode: OpenCodeProvider {
        .init(id: id, name: name, models: models.mapValues(\.openCode))
    }
}

private struct NativeModel: Decodable {
    let id: String
    let providerId: String
    let name: String
    let limits: OpenCodeModel.Limits?
    let variants: [String: JSONValue]?

    var openCode: OpenCodeModel {
        .init(id: id, providerID: providerId, name: name, limit: limits, variants: variants)
    }
}

private struct NativeAgent: Decodable {
    let name: String
    let description: String?
    let hidden: Bool?
    let mode: String?
    let model: NativeAgentModel?

    var openCode: OpenCodeAgent {
        .init(name: name, description: description, hidden: hidden, mode: mode, model: model?.openCode)
    }
}

private struct NativeAgentModel: Decodable {
    let providerId: String
    let modelId: String

    var openCode: OpenCodeAgentModel {
        .init(providerID: providerId, modelID: modelId)
    }
}

private struct NativeMessage: Decodable {
    let id: String
    let role: String
    let text: String
    let summary: JSONValue?
    let createdAt: Date

    var openCode: OpenCodeMessageEnvelope {
        .init(
            info: OpenCodeMessageInfo(
                id: id,
                sessionID: nil,
                role: role,
                summary: summary,
                agent: nil,
                providerID: nil,
                modelID: nil,
                cost: nil,
                tokens: nil,
                time: OpenCodeTimeContainer(created: createdAt, updated: createdAt, completed: createdAt)
            ),
            parts: [OpenCodePart(id: "\(id):text", sessionID: nil, messageID: id, type: .text, text: text, tool: nil, mime: nil, filename: nil, url: nil, source: nil, state: nil, time: OpenCodeTimeContainer(created: createdAt, updated: createdAt, completed: createdAt))]
        )
    }
}

private struct NativePromptBody: Encodable {
    let text: String?
    let parts: [NativePromptPart]
    let providerID: String?
    let modelID: String?
    let agent: String?
    let variant: String?

    enum CodingKeys: String, CodingKey {
        case text, parts, providerID = "providerId", modelID = "modelId", agent, variant
    }
}

private struct NativeCommandBody: Encodable {
    let command: String
    let arguments: String
    let parts: [NativePromptPart]
    let agent: String?
    let model: String?
    let variant: String?
}

private struct NativePromptPart: Encodable {
    let type: String
    let text: String?
    let mime: String?
    let filename: String?
    let url: String?
    let source: NativePromptSource?
}

private struct NativePromptSource: Encodable {
    let type: String
    let text: NativePromptSourceText
    let path: String
}

private struct NativePromptSourceText: Encodable {
    let value: String
    let start: Int
    let end: Int
}

private extension SendPromptBody.Part {
    var native: NativePromptPart {
        switch self {
        case .text(let text):
            return NativePromptPart(type: "text", text: text, mime: nil, filename: nil, url: nil, source: nil)
        case .file(let mime, let filename, let url):
            return NativePromptPart(type: "file", text: nil, mime: mime, filename: filename, url: url, source: nil)
        case .fileReference(let fileReference):
            return NativePromptPart(
                type: "file",
                text: nil,
                mime: "text/plain",
                filename: fileReference.relativePath,
                url: fileReference.requestURL,
                source: NativePromptSource(
                    type: "file",
                    text: NativePromptSourceText(value: fileReference.sourceText.value, start: fileReference.sourceText.start, end: fileReference.sourceText.end),
                    path: fileReference.absolutePath
                )
            )
        }
    }
}

private struct EmptyRequest: Encodable {}
struct EmptyResponse: Decodable, Equatable {}

extension JSONDecoder {
    nonisolated static var opencode: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let timestamp = try? container.decode(Double.self) {
                let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
                return Date(timeIntervalSince1970: seconds)
            }

            if let timestamp = try? container.decode(Int.self) {
                let value = Double(timestamp)
                let seconds = value > 10_000_000_000 ? value / 1000 : value
                return Date(timeIntervalSince1970: seconds)
            }

            if let string = try? container.decode(String.self) {
                if let isoDate = Self.parseOpenCodeISO8601Date(from: string) {
                    return isoDate
                }

                if let timestamp = Double(string) {
                    let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
                    return Date(timeIntervalSince1970: seconds)
                }
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported OpenCode date value")
        }
        return decoder
    }

    private nonisolated static func parseOpenCodeISO8601Date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
