import Foundation

struct OpenCodeProviderResponse: Decodable, Equatable, Sendable {
    let providers: [OpenCodeProvider]
    let `default`: [String: String]?
}

struct OpenCodeProvider: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let models: [String: OpenCodeModel]
}

struct OpenCodeModel: Decodable, Equatable, Sendable {
    struct Limits: Decodable, Equatable, Sendable {
        let context: Int
        let input: Int?
        let output: Int
    }

    let id: String
    let providerID: String
    let name: String
    let limit: Limits?
    let variants: [String: JSONValue]?
}

struct OpenCodeAgentModel: Decodable, Equatable, Sendable {
    let providerID: String
    let modelID: String
}

struct OpenCodeAgent: Decodable, Equatable, Identifiable, Sendable {
    let id = UUID()
    let name: String
    let description: String?
    let hidden: Bool?
    let mode: String?
    let model: OpenCodeAgentModel?

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case hidden
        case mode
        case model
    }
}

struct OpenCodeCommand: Decodable, Equatable, Identifiable, Hashable, Sendable {
    let name: String
    let description: String?
    let agent: String?
    let model: String?
    let source: String?
    let template: String?
    let subtask: Bool?
    let hints: [String]

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case agent
        case model
        case source
        case template
        case subtask
        case hints
    }

    init(
        name: String,
        description: String?,
        agent: String?,
        model: String?,
        source: String?,
        template: String?,
        subtask: Bool?,
        hints: [String]
    ) {
        self.name = name
        self.description = description
        self.agent = agent
        self.model = model
        self.source = source
        self.template = template
        self.subtask = subtask
        self.hints = hints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        subtask = try container.decodeIfPresent(Bool.self, forKey: .subtask)
        hints = (try? container.decodeIfPresent([String].self, forKey: .hints)) ?? []

        if let value = try? container.decodeIfPresent(String.self, forKey: .template) {
            template = value
        } else {
            template = nil
        }
    }

    var id: String { name }

    nonisolated var trimmedDescription: String? {
        description?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyTrimmed
    }
}

struct OpenCodePromptOptions: Sendable {
    let model: ComposerModelOption?
    let agentName: String?
    let variant: String?
}

struct OpenCodeFileChangeSummary: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Status: String, Codable, Equatable, Hashable, Sendable {
        case added
        case deleted
        case modified
    }

    let file: String
    let before: String?
    let after: String?
    let additions: Int
    let deletions: Int
    let status: Status?

    var id: String { file }
}

struct OpenCodeMessageSummary: Codable, Equatable, Hashable, Sendable {
    let title: String?
    let body: String?
    let diffs: [OpenCodeFileChangeSummary]?
}

struct OpenCodeSessionSummary: Codable, Equatable, Hashable, Sendable {
    let additions: Int
    let deletions: Int
    let files: Int
    let diffs: [OpenCodeFileChangeSummary]?
}

struct OpenCodeSessionRevert: Codable, Equatable, Hashable, Sendable {
    let messageID: String
    let partID: String?
    let snapshot: String?
    let diff: String?
}

struct OpenCodeSession: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String?
    let parentID: String?
    let summary: OpenCodeSessionSummary?
    let revert: OpenCodeSessionRevert?
    let time: OpenCodeTimeContainer?

    init(
        id: String,
        title: String?,
        parentID: String?,
        summary: OpenCodeSessionSummary? = nil,
        revert: OpenCodeSessionRevert? = nil,
        time: OpenCodeTimeContainer?
    ) {
        self.id = id
        self.title = title
        self.parentID = parentID
        self.summary = summary
        self.revert = revert
        self.time = time
    }

    nonisolated var createdAt: Date { time?.created ?? .distantPast }
    nonisolated var updatedAt: Date { time?.updated ?? time?.created ?? .distantPast }
    nonisolated var isRootVisible: Bool { parentID == nil }
}

enum OpenCodeSessionActivity: Decodable, Equatable, Sendable {
    case idle
    case busy
    case retry(attempt: Int, message: String, next: TimeInterval)

    private enum CodingKeys: String, CodingKey {
        case type
        case attempt
        case message
        case next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "idle":
            self = .idle
        case "busy":
            self = .busy
        case "retry":
            self = .retry(
                attempt: try container.decode(Int.self, forKey: .attempt),
                message: try container.decode(String.self, forKey: .message),
                next: try container.decode(TimeInterval.self, forKey: .next)
            )
        default:
            self = .idle
        }
    }
}

struct OpenCodeTokenCacheUsage: Decodable, Equatable, Sendable {
    let read: Int
    let write: Int
}

struct OpenCodeTokenUsage: Decodable, Equatable, Sendable {
    let total: Int?
    let input: Int
    let output: Int
    let reasoning: Int
    let cache: OpenCodeTokenCacheUsage?
}

struct OpenCodeMessageEnvelope: Decodable, Equatable, Sendable {
    let info: OpenCodeMessageInfo
    let parts: [OpenCodePart]
}

struct OpenCodeMessageInfo: Decodable, Equatable, Sendable {
    let id: String
    let sessionID: String?
    let role: String
    let summary: JSONValue?
    let agent: String?
    let providerID: String?
    let modelID: String?
    let cost: Double?
    let tokens: OpenCodeTokenUsage?
    let time: OpenCodeTimeContainer?

    nonisolated var createdAt: Date? { time?.created }
    nonisolated var updatedAt: Date? { time?.completed ?? time?.updated ?? time?.created }
    nonisolated var isSummaryMessage: Bool {
        guard case .bool(true) = summary else { return false }
        return true
    }

    var summaryInfo: OpenCodeMessageSummary? {
        guard case .object = summary,
              let summary,
              let data = try? JSONEncoder().encode(summary)
        else {
            return nil
        }

        return try? JSONDecoder.opencode.decode(OpenCodeMessageSummary.self, from: data)
    }

    nonisolated var chatRole: ChatMessage.Role {
        switch role {
        case "user": .user
        case "assistant": .assistant
        case "system": .system
        default: .assistant
        }
    }
}

typealias OpenCodeQuestionAnswer = [String]

enum OpenCodePermissionReply: String, Codable, Equatable, Hashable, Sendable {
    case once
    case always
    case reject
}

struct OpenCodePermissionRequest: Codable, Equatable, Identifiable, Sendable {
    struct ToolReference: Codable, Equatable, Sendable {
        let messageID: String
        let callID: String
    }

    let id: String
    let sessionID: String
    let permission: String
    let patterns: [String]
    let metadata: [String: JSONValue]
    let always: [String]
    let tool: ToolReference?
}

struct OpenCodePermissionReplyEvent: Codable, Equatable, Sendable {
    let sessionID: String
    let requestID: String
    let reply: OpenCodePermissionReply
}

struct OpenCodeQuestionOption: Codable, Equatable, Hashable, Sendable {
    let label: String
    let description: String
}

struct OpenCodeQuestionInfo: Codable, Equatable, Hashable, Sendable {
    let question: String
    let header: String
    let options: [OpenCodeQuestionOption]
    let multiple: Bool?
    let custom: Bool?

    nonisolated var allowsMultipleSelections: Bool { multiple == true }
    nonisolated var allowsCustomAnswer: Bool { custom != false }
}

struct OpenCodeQuestionRequest: Codable, Equatable, Hashable, Identifiable, Sendable {
    struct ToolReference: Codable, Equatable, Hashable, Sendable {
        let messageID: String
        let callID: String
    }

    let id: String
    let sessionID: String
    let questions: [OpenCodeQuestionInfo]
    let tool: ToolReference?
}

struct OpenCodeQuestionReplyEvent: Codable, Equatable, Hashable, Sendable {
    let sessionID: String
    let requestID: String
    let answers: [OpenCodeQuestionAnswer]
}

struct OpenCodeQuestionRejectEvent: Codable, Equatable, Hashable, Sendable {
    let sessionID: String
    let requestID: String
}

struct OpenCodeFileSourceText: Decodable, Equatable, Sendable {
    let value: String
    let start: Int?
    let end: Int?
}

struct OpenCodeFileSourceRange: Decodable, Equatable, Sendable {
    let start: Int?
    let end: Int?
}

struct OpenCodeFileSource: Decodable, Equatable, Sendable {
    let text: OpenCodeFileSourceText?
    let path: String?
    let range: OpenCodeFileSourceRange?
    let clientName: String?
    let uri: String?
}

struct OpenCodePart: Decodable, Equatable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case text
        case reasoning
        case tool
        case file
        case diff
        case compaction
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self = Kind(rawValue: try container.decode(String.self)) ?? .unknown
        }
    }

    let id: String
    let sessionID: String?
    let messageID: String?
    let type: Kind
    let text: String?
    let tool: String?
    let mime: String?
    let filename: String?
    let url: String?
    let source: OpenCodeFileSource?
    let state: OpenCodeToolState?
    let time: OpenCodeTimeContainer?

    nonisolated var updatedAt: Date? { time?.completed ?? time?.updated ?? time?.created }
    nonisolated var toolStatus: OpenCodeToolState.Status? { state?.status }
    nonisolated var trimmedText: String { (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    nonisolated var isSyntheticAttachmentReadSummary: Bool {
        type == .text && trimmedText.hasPrefix("Called the Read tool with the following input:")
    }

    nonisolated var isSyntheticUserFileContentDump: Bool {
        guard type == .text else { return false }
        return trimmedText.hasPrefix("<path>")
            && trimmedText.contains("</path>")
            && trimmedText.contains("<type>")
            && trimmedText.contains("</type>")
            && trimmedText.contains("<content>")
    }

    nonisolated var promotedSourceText: String? {
        guard type == .file,
              let value = source?.text?.value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }

        return value
    }

    nonisolated var isPromotedFileReference: Bool {
        promotedSourceText != nil
    }

    nonisolated var attachment: ChatAttachment? {
        guard type == .file,
              let mime,
              let url
        else {
            return nil
        }

        return ChatAttachment(filename: filename, mimeType: mime, url: url, sourcePath: source?.path)
    }

    nonisolated var isInProgress: Bool {
        switch type {
        case .tool:
            switch toolStatus {
            case .completed, .error:
                return false
            case .pending, .running, .none:
                return true
            }
        case .text, .reasoning, .file, .diff, .compaction, .unknown:
            return time?.completed == nil
        }
    }

    nonisolated var shouldDisplay: Bool {
        switch type {
        case .compaction:
            return true
        case .file:
            return attachment != nil || !trimmedText.isEmpty
        case .text, .reasoning, .diff, .unknown:
            return !trimmedText.isEmpty
        case .tool:
            if ["todoread", "todowrite"].contains(tool?.lowercased() ?? "") {
                return false
            }
            if tool?.lowercased() == "question",
               toolStatus == nil || toolStatus == .pending || toolStatus == .running {
                return false
            }
            return !(renderedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    nonisolated var renderedText: String {
        switch type {
        case .text, .reasoning:
            return text ?? ""
        case .compaction:
            return "Session compacted"
        case .tool:
            let name = tool ?? "tool"
            switch state?.status {
            case .completed:
                return "\(name) completed\n\(state?.output?.displayString ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
            case .error:
                return "\(name) failed\n\(state?.error ?? "Unknown error")"
            case .running, .pending, .none:
                return "\(name) running\n\(state?.input?.displayString ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case .file:
            return attachment?.displayTitle ?? text ?? ""
        case .diff, .unknown:
            return text ?? ""
        }
    }

    nonisolated var chatRole: ChatMessage.Role { chatRole(defaultRole: .assistant) }

    nonisolated func chatRole(defaultRole: ChatMessage.Role) -> ChatMessage.Role {
        switch type {
        case .compaction:
            return .system
        case .tool:
            return .tool
        case .reasoning:
            return .assistant
        case .text, .file, .diff, .unknown:
            return defaultRole
        }
    }

    nonisolated var chatEmphasis: ChatMessage.Emphasis {
        switch type {
        case .compaction:
            return .subtle
        case .reasoning:
            return .strong
        case .tool:
            return .subtle
        case .text, .file, .diff, .unknown:
            return .normal
        }
    }

    nonisolated var chatMessageKind: ChatMessage.Kind {
        if type == .compaction {
            return .compactionMarker
        }
        if type == .tool {
            let status = ChatMessage.ToolCallStatus(rawValue: toolStatus?.rawValue ?? "running") ?? .running
            return .toolCall(
                ChatMessage.ToolCall(
                    name: tool ?? "tool",
                    status: status,
                    detail: renderedText,
                    input: state?.input,
                    output: state?.output,
                    error: state?.error
                )
            )
        }
        return .plain
    }
}

struct OpenCodeToolState: Decodable, Equatable, Sendable {
    enum Status: String, Decodable, Sendable {
        case pending
        case running
        case completed
        case error
    }

    let status: Status?
    let input: JSONValue?
    let output: JSONValue?
    let error: String?

    nonisolated var rawInput: String? { input?.displayString }
    nonisolated var rawOutput: String? { output?.displayString }
}

struct OpenCodeTimeContainer: Decodable, Equatable, Sendable {
    let created: Date?
    let updated: Date?
    let completed: Date?
}

enum OpenCodeEvent: Equatable, Sendable {
    case connected
    case sessionCreated(OpenCodeSession)
    case sessionUpdated(OpenCodeSession)
    case sessionDeleted(String)
    case sessionCompacted(String)
    case sessionStatusChanged(sessionID: String, status: OpenCodeSessionActivity)
    case permissionAsked(OpenCodePermissionRequest)
    case permissionReplied(OpenCodePermissionReplyEvent)
    case questionAsked(OpenCodeQuestionRequest)
    case questionReplied(OpenCodeQuestionReplyEvent)
    case questionRejected(OpenCodeQuestionRejectEvent)
    case messageUpdated(OpenCodeMessageInfo)
    case messagePartUpdated(OpenCodePart)
    case messagePartDelta(OpenCodePartDelta)
    case ignored(String)

    nonisolated var isCreated: Bool {
        if case .sessionCreated = self { return true }
        return false
    }

    nonisolated var debugName: String {
        switch self {
        case .connected:
            return "connected"
        case .sessionCreated:
            return "session.created"
        case .sessionUpdated:
            return "session.updated"
        case .sessionDeleted:
            return "session.deleted"
        case .sessionCompacted:
            return "session.compacted"
        case .sessionStatusChanged:
            return "session.status"
        case .permissionAsked:
            return "permission.asked"
        case .permissionReplied:
            return "permission.replied"
        case .questionAsked:
            return "question.asked"
        case .questionReplied:
            return "question.replied"
        case .questionRejected:
            return "question.rejected"
        case .messageUpdated:
            return "message.updated"
        case .messagePartUpdated:
            return "message.part.updated"
        case .messagePartDelta:
            return "message.part.delta"
        case .ignored(let type):
            return "ignored:\(type)"
        }
    }
}

struct OpenCodePartDelta: Decodable, Equatable, Sendable {
    let sessionID: String
    let messageID: String
    let partID: String
    let field: String
    let delta: String
}
