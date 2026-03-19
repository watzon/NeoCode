import Foundation
@testable import NeoCode

func decode<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder.opencode.decode(T.self, from: Data(json.utf8))
}

func date(_ iso8601: String) -> Date {
    (try? JSONDecoder.opencode.decode(Date.self, from: Data("\"\(iso8601)\"".utf8))) ?? .distantPast
}

func isoDateString(from date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

func dashboardMessages(sessionID: String, totalTokens: Int, updatedAt: String) throws -> [OpenCodeMessageEnvelope] {
    try decode(
        """
        [
          {
            "info": {
              "id": "msg_\(sessionID)",
              "sessionID": "\(sessionID)",
              "role": "assistant",
              "providerID": "openai",
              "modelID": "gpt-5.4",
              "cost": 0.0,
              "tokens": {
                "total": \(totalTokens),
                "input": \(totalTokens),
                "output": 0,
                "reasoning": 0,
                "cache": {
                  "read": 0,
                  "write": 0
                }
              },
              "time": {
                "created": "\(updatedAt)",
                "updated": "\(updatedAt)",
                "completed": "\(updatedAt)"
              }
            },
            "parts": []
          }
        ]
        """
    )
}

func requestBodyData(from request: URLRequest) throws -> Data? {
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

func createTemporaryGitRepository() throws -> URL {
    let repositoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
    try runGit(["init"], in: repositoryURL)
    try runGit(["config", "user.name", "NeoCode Tests"], in: repositoryURL)
    try runGit(["config", "user.email", "tests@neocode.invalid"], in: repositoryURL)
    return repositoryURL
}

func write(_ contents: String, to url: URL) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

@discardableResult
func runGit(_ arguments: [String], in repositoryURL: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = repositoryURL

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe

    try process.run()
    process.waitUntilExit()

    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "NeoCodeTests",
            code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: output.trimmingCharacters(in: .whitespacesAndNewlines)]
        )
    }

    return output
}

func waitForProcessIdentifier(from runner: SubprocessRunner) async throws -> pid_t {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if let pid = runner.processIdentifier, pid > 0 {
            return pid
        }

        try await Task.sleep(for: .milliseconds(50))
    }

    throw NSError(domain: "NeoCodeTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for root process identifier"])
}

func waitForChildProcessIdentifier(at url: URL) async throws -> pid_t {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if let contents = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = pid_t(contents), pid > 0 {
            return pid
        }

        try await Task.sleep(for: .milliseconds(50))
    }

    throw NSError(domain: "NeoCodeTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for child process identifier"])
}

func waitForProcessExit(_ pid: pid_t) async throws {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if !ManagedProcessRegistry.isProcessAlive(pid) {
            return
        }

        try await Task.sleep(for: .milliseconds(50))
    }

    throw NSError(domain: "NeoCodeTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for process \(pid) to exit"])
}

func waitForProcessToStop(_ process: Process) async throws {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if !process.isRunning {
            return
        }

        try await Task.sleep(for: .milliseconds(50))
    }

    throw NSError(domain: "NeoCodeTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for process \(process.processIdentifier) to stop"])
}

struct QuestionReplyPayload: Decodable {
    let answers: [[String]]
}

struct PermissionReplyPayload: Decodable {
    let reply: OpenCodePermissionReply
    let message: String?
}

final class MockURLProtocol: URLProtocol {
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

final class MockOpenCodeService: OpenCodeServicing {
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

    struct SentSummary {
        let sessionID: String
        let providerID: String
        let modelID: String
        let auto: Bool
    }

    var revertedSessionID: String?
    var revertedMessageID: String?
    var unrevertedSessionIDs: [String] = []
    var sentPrompts: [SentPrompt] = []
    var sentCommands: [SentCommand] = []
    var sentSummaries: [SentSummary] = []
    var repliedPermissionIDs: [String] = []
    var repliedQuestionIDs: [String] = []
    var rejectedQuestionIDs: [String] = []
    var abortedSessionIDs: [String] = []
    var sendPromptError: Error?
    var createSessionError: Error?
    var createdSession: OpenCodeSession?
    var createdSessionTitles: [String?] = []

    init(sendPromptError: Error? = nil, createSessionError: Error? = nil, createdSession: OpenCodeSession? = nil) {
        self.sendPromptError = sendPromptError
        self.createSessionError = createSessionError
        self.createdSession = createdSession
    }

    func listSessions() async throws -> [OpenCodeSession] { [] }
    func listSessionStatuses() async throws -> [String: OpenCodeSessionActivity] { [:] }
    func listPermissions() async throws -> [OpenCodePermissionRequest] { [] }
    func listQuestions() async throws -> [OpenCodeQuestionRequest] { [] }
    func listCommands() async throws -> [OpenCodeCommand] { [] }
    func createSession(title: String?) async throws -> OpenCodeSession {
        createdSessionTitles.append(title)
        if let createSessionError {
            throw createSessionError
        }
        if let createdSession {
            return createdSession
        }
        fatalError("Unused in test")
    }
    func updateSession(sessionID: String, title: String) async throws -> OpenCodeSession { fatalError("Unused in test") }
    func deleteSession(sessionID: String) async throws -> Bool { true }
    func summarizeSession(sessionID: String, providerID: String, modelID: String, auto: Bool) async throws {
        sentSummaries.append(SentSummary(sessionID: sessionID, providerID: providerID, modelID: modelID, auto: auto))
    }

    func revertSession(sessionID: String, messageID: String, partID: String?) async throws -> OpenCodeSession {
        revertedSessionID = sessionID
        revertedMessageID = messageID
        return OpenCodeSession(
            id: sessionID,
            title: nil,
            parentID: nil,
            revert: OpenCodeSessionRevert(messageID: messageID, partID: partID, snapshot: nil, diff: nil),
            time: nil
        )
    }

    func unrevertSession(sessionID: String) async throws -> OpenCodeSession {
        unrevertedSessionIDs.append(sessionID)
        return OpenCodeSession(id: sessionID, title: nil, parentID: nil, time: nil)
    }

    func abortSession(sessionID: String) async throws {
        abortedSessionIDs.append(sessionID)
    }
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

    func sendPromptAsync(
        sessionID: String,
        text: String,
        attachments: [ComposerAttachment],
        fileReferences: [ComposerPromptFileReference],
        options: OpenCodePromptOptions?
    ) async throws {
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
        fileReferences: [ComposerPromptFileReference],
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

enum TestFailure: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}
