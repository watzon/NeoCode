import Foundation

struct OpenCodeProviderResponse: Decodable, Equatable {
    let providers: [OpenCodeProvider]
    let `default`: [String: String]?
}

struct OpenCodeProvider: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let models: [String: OpenCodeModel]
}

struct OpenCodeModel: Decodable, Equatable {
    let id: String
    let providerID: String
    let name: String
    let variants: [String: JSONValue]?
}

struct OpenCodeAgent: Decodable, Equatable, Identifiable {
    let id = UUID()
    let name: String
    let description: String?
    let hidden: Bool?
    let mode: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case hidden
        case mode
    }
}

struct OpenCodeCommand: Decodable, Equatable, Identifiable, Hashable {
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

    var trimmedDescription: String? {
        description?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyTrimmed
    }
}

struct OpenCodePromptOptions {
    let model: ComposerModelOption?
    let agentName: String?
    let variant: String?
}

struct OpenCodeSession: Decodable, Identifiable, Equatable {
    let id: String
    let title: String?
    let parentID: String?
    let time: OpenCodeTimeContainer?

    var createdAt: Date { time?.created ?? .distantPast }
    var updatedAt: Date { time?.updated ?? time?.created ?? .distantPast }
    var isRootVisible: Bool { parentID == nil }
}

enum OpenCodeSessionActivity: Decodable, Equatable {
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

struct OpenCodeMessageEnvelope: Decodable, Equatable {
    let info: OpenCodeMessageInfo
    let parts: [OpenCodePart]
}

struct OpenCodeMessageInfo: Decodable, Equatable {
    let id: String
    let sessionID: String?
    let role: String
    let agent: String?
    let modelID: String?
    let time: OpenCodeTimeContainer?

    var createdAt: Date? { time?.created }
    var updatedAt: Date? { time?.completed ?? time?.updated ?? time?.created }

    var chatRole: ChatMessage.Role {
        switch role {
        case "user": .user
        case "assistant": .assistant
        case "system": .system
        default: .assistant
        }
    }
}

typealias OpenCodeQuestionAnswer = [String]

enum OpenCodePermissionReply: String, Codable, Equatable, Hashable {
    case once
    case always
    case reject
}

struct OpenCodePermissionRequest: Codable, Equatable, Identifiable {
    struct ToolReference: Codable, Equatable {
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

struct OpenCodePermissionReplyEvent: Codable, Equatable {
    let sessionID: String
    let requestID: String
    let reply: OpenCodePermissionReply
}

struct OpenCodeQuestionOption: Codable, Equatable, Hashable {
    let label: String
    let description: String
}

struct OpenCodeQuestionInfo: Codable, Equatable, Hashable {
    let question: String
    let header: String
    let options: [OpenCodeQuestionOption]
    let multiple: Bool?
    let custom: Bool?

    var allowsMultipleSelections: Bool { multiple == true }
    var allowsCustomAnswer: Bool { custom != false }
}

struct OpenCodeQuestionRequest: Codable, Equatable, Hashable, Identifiable {
    struct ToolReference: Codable, Equatable, Hashable {
        let messageID: String
        let callID: String
    }

    let id: String
    let sessionID: String
    let questions: [OpenCodeQuestionInfo]
    let tool: ToolReference?
}

struct OpenCodeQuestionReplyEvent: Codable, Equatable, Hashable {
    let sessionID: String
    let requestID: String
    let answers: [OpenCodeQuestionAnswer]
}

struct OpenCodeQuestionRejectEvent: Codable, Equatable, Hashable {
    let sessionID: String
    let requestID: String
}

struct OpenCodeFileSourceText: Decodable, Equatable {
    let value: String
    let start: Int?
    let end: Int?
}

struct OpenCodeFileSourceRange: Decodable, Equatable {
    let start: Int?
    let end: Int?
}

struct OpenCodeFileSource: Decodable, Equatable {
    let text: OpenCodeFileSourceText?
    let path: String?
    let range: OpenCodeFileSourceRange?
    let clientName: String?
    let uri: String?
}

struct OpenCodePart: Decodable, Equatable {
    enum Kind: String, Decodable {
        case text
        case reasoning
        case tool
        case file
        case diff
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

    var updatedAt: Date? { time?.completed ?? time?.updated ?? time?.created }
    var toolStatus: OpenCodeToolState.Status? { state?.status }
    var trimmedText: String { (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    var attachment: ChatAttachment? {
        guard type == .file,
              let mime,
              let url
        else {
            return nil
        }

        return ChatAttachment(filename: filename, mimeType: mime, url: url, sourcePath: source?.path)
    }

    var isInProgress: Bool {
        switch type {
        case .tool:
            switch toolStatus {
            case .completed, .error:
                return false
            case .pending, .running, .none:
                return true
            }
        case .text, .reasoning, .file, .diff, .unknown:
            return time?.completed == nil
        }
    }

    var shouldDisplay: Bool {
        switch type {
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

    var renderedText: String {
        switch type {
        case .text, .reasoning:
            return text ?? ""
        case .tool:
            let name = tool ?? "tool"
            switch state?.status {
            case .completed:
                return "\(name) completed\n\(state?.output?.prettyPrinted ?? state?.rawOutput ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
            case .error:
                return "\(name) failed\n\(state?.error ?? "Unknown error")"
            case .running, .pending, .none:
                return "\(name) running\n\(state?.input?.prettyPrinted ?? state?.rawInput ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case .file:
            return attachment?.displayTitle ?? text ?? ""
        case .diff, .unknown:
            return text ?? ""
        }
    }

    var chatRole: ChatMessage.Role { chatRole(defaultRole: .assistant) }

    func chatRole(defaultRole: ChatMessage.Role) -> ChatMessage.Role {
        switch type {
        case .tool:
            return .tool
        case .reasoning:
            return .assistant
        case .text, .file, .diff, .unknown:
            return defaultRole
        }
    }

    var chatEmphasis: ChatMessage.Emphasis {
        switch type {
        case .reasoning:
            return .strong
        case .tool:
            return .subtle
        case .text, .file, .diff, .unknown:
            return .normal
        }
    }

    var chatMessageKind: ChatMessage.Kind {
        if type == .tool {
            let status = ChatMessage.ToolCallStatus(rawValue: toolStatus?.rawValue ?? "running") ?? .running
            return .toolCall(name: tool ?? "tool", status: status, detail: renderedText)
        }
        return .plain
    }
}

struct OpenCodeToolState: Decodable, Equatable {
    enum Status: String, Decodable {
        case pending
        case running
        case completed
        case error
    }

    let status: Status?
    let input: JSONValue?
    let output: JSONValue?
    let error: String?

    var rawInput: String? { input?.prettyPrinted }
    var rawOutput: String? { output?.prettyPrinted }
}

struct OpenCodeTimeContainer: Decodable, Equatable {
    let created: Date?
    let updated: Date?
    let completed: Date?
}

enum OpenCodeEvent: Equatable {
    case connected
    case sessionCreated(OpenCodeSession)
    case sessionUpdated(OpenCodeSession)
    case sessionDeleted(String)
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

    var isCreated: Bool {
        if case .sessionCreated = self { return true }
        return false
    }

    var debugName: String {
        switch self {
        case .connected:
            return "connected"
        case .sessionCreated:
            return "session.created"
        case .sessionUpdated:
            return "session.updated"
        case .sessionDeleted:
            return "session.deleted"
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

struct OpenCodePartDelta: Decodable, Equatable {
    let sessionID: String
    let messageID: String
    let partID: String
    let field: String
    let delta: String
}
