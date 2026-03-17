import Foundation
import OSLog

protocol OpenCodeServicing {
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


final class OpenCodeClient: OpenCodeServicing {
    private let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "OpenCodeClient")
    private let connection: OpenCodeRuntime.Connection
    private let session: URLSession
    private let decoder: JSONDecoder

    init(connection: OpenCodeRuntime.Connection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
        self.decoder = JSONDecoder.opencode
    }

    func listSessions() async throws -> [OpenCodeSession] {
        try await request(path: "/session", method: "GET")
    }

    func listSessionStatuses() async throws -> [String: OpenCodeSessionActivity] {
        try await request(path: "/session/status", method: "GET")
    }

    func listPermissions() async throws -> [OpenCodePermissionRequest] {
        try await request(path: "/permission", method: "GET")
    }

    func listQuestions() async throws -> [OpenCodeQuestionRequest] {
        try await request(path: "/question", method: "GET")
    }

    func listCommands() async throws -> [OpenCodeCommand] {
        try await request(path: "/command", method: "GET")
    }

    func createSession(title: String?) async throws -> OpenCodeSession {
        logger.info("POST /session for project: \(self.connection.projectPath, privacy: .public)")
        let body = CreateSessionBody(title: title)
        let session: OpenCodeSession = try await request(path: "/session", method: "POST", body: body)
        return session
    }

    func updateSession(sessionID: String, title: String) async throws -> OpenCodeSession {
        logger.info("PATCH /session/\(sessionID, privacy: .public)")
        return try await request(path: "/session/\(sessionID)", method: "PATCH", body: UpdateSessionBody(title: title))
    }

    func deleteSession(sessionID: String) async throws -> Bool {
        logger.info("DELETE /session/\(sessionID, privacy: .public)")
        return try await request(path: "/session/\(sessionID)", method: "DELETE")
    }

    func summarizeSession(sessionID: String, providerID: String, modelID: String, auto: Bool = false) async throws {
        logger.info(
            "POST /session/\(sessionID, privacy: .public)/summarize provider=\(providerID, privacy: .public) model=\(modelID, privacy: .public) auto=\(auto, privacy: .public)"
        )
        let _: Bool = try await request(
            path: "/session/\(sessionID)/summarize",
            method: "POST",
            body: SummarizeSessionBody(providerID: providerID, modelID: modelID, auto: auto)
        )
    }

    func revertSession(sessionID: String, messageID: String, partID: String? = nil) async throws -> OpenCodeSession {
        logger.info("POST /session/\(sessionID, privacy: .public)/revert messageID=\(messageID, privacy: .public)")
        return try await request(
            path: "/session/\(sessionID)/revert",
            method: "POST",
            body: RevertSessionBody(messageID: messageID, partID: partID)
        )
    }

    func unrevertSession(sessionID: String) async throws -> OpenCodeSession {
        logger.info("POST /session/\(sessionID, privacy: .public)/unrevert")
        return try await request(path: "/session/\(sessionID)/unrevert", method: "POST", body: Optional<EmptyRequest>.none)
    }

    func abortSession(sessionID: String) async throws {
        logger.info("POST /session/\(sessionID, privacy: .public)/abort")
        let _: EmptyResponse = try await request(path: "/session/\(sessionID)/abort", method: "POST", body: Optional<EmptyRequest>.none)
    }

    func replyToPermission(requestID: String, reply: OpenCodePermissionReply, message: String?) async throws {
        logger.info("POST /permission/\(requestID, privacy: .public)/reply type=\(reply.rawValue, privacy: .public)")
        let _: Bool = try await request(
            path: "/permission/\(requestID)/reply",
            method: "POST",
            body: PermissionReplyBody(reply: reply, message: message)
        )
    }

    func replyToQuestion(requestID: String, answers: [OpenCodeQuestionAnswer]) async throws {
        logger.info("POST /question/\(requestID, privacy: .public)/reply answers=\(answers.count, privacy: .public)")
        let _: Bool = try await request(
            path: "/question/\(requestID)/reply",
            method: "POST",
            body: QuestionReplyBody(answers: answers)
        )
    }

    func rejectQuestion(requestID: String) async throws {
        logger.info("POST /question/\(requestID, privacy: .public)/reject")
        let _: Bool = try await request(path: "/question/\(requestID)/reject", method: "POST", body: Optional<EmptyRequest>.none)
    }

    func listProviders() async throws -> OpenCodeProviderResponse {
        try await request(path: "/config/providers", method: "GET")
    }

    func listAgents() async throws -> [OpenCodeAgent] {
        try await request(path: "/agent", method: "GET")
    }

    func listMessages(sessionID: String) async throws -> [OpenCodeMessageEnvelope] {
        try await request(path: "/session/\(sessionID)/message", method: "GET")
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
        let _: EmptyResponse = try await request(path: "/session/\(sessionID)/prompt_async", method: "POST", body: body)
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
        let _: SendCommandResponse = try await request(path: "/session/\(sessionID)/command", method: "POST", body: body)
        logger.info(
            "Command accepted for session \(sessionID, privacy: .public) after \(Date().timeIntervalSince(startedAt), privacy: .public)s"
        )
    }

    func eventStream() throws -> AsyncThrowingStream<OpenCodeEvent, Error> {
        let request = try makeRequest(path: "/event", method: "GET", body: Optional<EmptyRequest>.none, accept: "text/event-stream")
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
                        throw OpenCodeClientError.invalidResponse
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

                    func emit(_ frame: OpenCodeSSEFrame, final: Bool = false) {
                        do {
                            let event = try OpenCodeEventDecoder.decode(frame: frame, decoder: decoder)
                            if case .ignored = event {
                            } else {
                                logger.debug(
                                    "\(final ? "Flushing final" : "Received") SSE event=\(event.debugName, privacy: .public)"
                                )
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

                    func processLine(_ data: Data) {
                        let line = String(decoding: data, as: UTF8.self)
                        if let frame = parser.ingest(line: line) {
                            emit(frame)
                        }
                    }

                    for try await byte in bytes {
                        if byte == 0x0A {
                            var line = lineBuffer
                            if line.last == 0x0D {
                                line.removeLast()
                            }
                            processLine(line)
                            lineBuffer.removeAll(keepingCapacity: true)
                        } else {
                            lineBuffer.append(byte)
                        }
                    }

                    if !lineBuffer.isEmpty {
                        processLine(lineBuffer)
                    }

                    if let frame = parser.flush() {
                        emit(frame, final: true)
                    }

                    logger.warning("SSE stream ended")
                    continuation.finish()
                } catch {
                    logger.error("SSE stream failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { termination in
                logger.debug("SSE continuation terminated: \(String(describing: termination), privacy: .public)")
                task.cancel()
            }
        }
    }

    private func request<Response: Decodable, Body: Encodable>(path: String, method: String, body: Body? = nil) async throws -> Response {
        let request = try makeRequest(path: path, method: method, body: body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeClientError.invalidResponse
        }

        if httpResponse.statusCode == 204, Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            logger.error("HTTP \(httpResponse.statusCode) for \(method, privacy: .public) \(path, privacy: .public)")
            throw OpenCodeClientError.httpStatus(httpResponse.statusCode)
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func request<Response: Decodable>(path: String, method: String) async throws -> Response {
        let request = try makeRequest(path: path, method: method, body: Optional<EmptyRequest>.none)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeClientError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            logger.error("HTTP \(httpResponse.statusCode) for \(method, privacy: .public) \(path, privacy: .public)")
            throw OpenCodeClientError.httpStatus(httpResponse.statusCode)
        }

        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest<Body: Encodable>(path: String, method: String, body: Body?, accept: String = "application/json") throws -> URLRequest {
        let url = connection.baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.authorizationHeader(username: connection.username, password: connection.password), forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
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
}

private struct SendCommandBody: Encodable {
    let command: String
    let arguments: String
    let agent: String?
    let model: String?
    let variant: String?
    let parts: [SendPromptBody.Part]?
}

private struct SendCommandResponse: Decodable {
    let info: OpenCodeMessageInfo
    let parts: [OpenCodePart]
}

private struct QuestionReplyBody: Encodable {
    let answers: [OpenCodeQuestionAnswer]
}

private struct PermissionReplyBody: Encodable {
    let reply: OpenCodePermissionReply
    let message: String?
}

private struct EmptyRequest: Encodable {}
struct EmptyResponse: Decodable, Equatable {}

extension JSONDecoder {
    static var opencode: JSONDecoder {
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
                if let isoDate = ISO8601DateFormatter().date(from: string) {
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
}
