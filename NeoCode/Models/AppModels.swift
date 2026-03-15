import Foundation

struct ProjectSummary: Codable, Identifiable, Hashable {
    static let displayedSessionLimit = 8

    let id: UUID
    var name: String
    var path: String
    var status: RuntimeStatus
    var settings: ProjectSettings
    var sessions: [SessionSummary]

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        status: RuntimeStatus = .idle,
        settings: ProjectSettings = .init(),
        sessions: [SessionSummary] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.status = status
        self.settings = settings
        self.sessions = sessions
    }

    var displayedSessions: [SessionSummary] {
        Array(sessions.prefix(Self.displayedSessionLimit))
    }
}

struct ProjectSettings: Codable, Hashable {
    var isCollapsedInSidebar: Bool
    var preferredEditorID: String?

    init(isCollapsedInSidebar: Bool = false, preferredEditorID: String? = nil) {
        self.isCollapsedInSidebar = isCollapsedInSidebar
        self.preferredEditorID = preferredEditorID
    }
}

struct SessionSummary: Codable, Identifiable, Hashable {
    static let defaultTitle = "New session"

    let id: String
    let parentID: String?
    var title: String
    var lastUpdatedAt: Date
    var status: SessionStatus
    var transcript: [ChatMessage]
    var isEphemeral: Bool

    init(
        id: String,
        parentID: String? = nil,
        title: String,
        lastUpdatedAt: Date,
        status: SessionStatus = .idle,
        transcript: [ChatMessage] = [],
        isEphemeral: Bool = false
    ) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.lastUpdatedAt = lastUpdatedAt
        self.status = status
        self.transcript = transcript
        self.isEphemeral = isEphemeral
    }

    init(session: OpenCodeSession, fallbackTitle: String = SessionSummary.defaultTitle) {
        self.init(
            id: session.id,
            parentID: session.parentID,
            title: session.title?.isEmpty == false ? session.title! : fallbackTitle,
            lastUpdatedAt: session.updatedAt,
            status: .idle,
            transcript: [],
            isEphemeral: false
        )
    }

    var hasPlaceholderTitle: Bool {
        Self.isPlaceholderTitle(title)
    }

    var requestedServerTitle: String? {
        hasPlaceholderTitle ? nil : title
    }

    func applyingInferredTitle(from transcript: [ChatMessage]) -> SessionSummary {
        guard hasPlaceholderTitle,
              let inferredTitle = Self.inferredTitle(from: transcript)
        else {
            return self
        }

        var session = self
        session.title = inferredTitle
        return session
    }

    static func isPlaceholderTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == defaultTitle || trimmed.hasPrefix("\(defaultTitle) - ")
    }

    static func inferredTitle(from transcript: [ChatMessage], maximumLength: Int = 72) -> String? {
        guard let message = transcript.first(where: { $0.role == .user }) else {
            return nil
        }

        let firstLine = message.text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? message.text
        let collapsedWhitespace = firstLine
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsedWhitespace.isEmpty else {
            return nil
        }

        guard collapsedWhitespace.count > maximumLength else {
            return collapsedWhitespace
        }

        let cutoff = collapsedWhitespace.index(collapsedWhitespace.startIndex, offsetBy: maximumLength)
        let prefix = collapsedWhitespace[..<cutoff]
        let truncated = prefix[..<(prefix.lastIndex(of: " ") ?? prefix.endIndex)]
        let normalized = truncated.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? String(prefix) : "\(normalized)..."
    }
}

struct ChatAttachment: Codable, Hashable {
    let filename: String?
    let mimeType: String
    let url: String
    let sourcePath: String?

    init(filename: String?, mimeType: String, url: String, sourcePath: String? = nil) {
        self.filename = filename
        self.mimeType = mimeType
        self.url = url
        self.sourcePath = sourcePath
    }

    init(attachment: ComposerAttachment) {
        self.init(
            filename: attachment.name,
            mimeType: attachment.mimeType,
            url: attachment.requestURL,
            sourcePath: attachment.filePath
        )
    }

    var isImage: Bool {
        mimeType.lowercased().hasPrefix("image/")
    }

    var displayTitle: String {
        if let filename, !filename.isEmpty {
            return filename
        }

        if let sourcePath, !sourcePath.isEmpty {
            return URL(fileURLWithPath: sourcePath).lastPathComponent
        }

        if url.hasPrefix("data:") {
            return mimeType
        }

        if let parsedURL = URL(string: url) {
            let lastPathComponent = parsedURL.lastPathComponent
            if !lastPathComponent.isEmpty {
                return lastPathComponent
            }
        }

        return "Attachment"
    }

    var displaySubtitle: String? {
        if let sourcePath, !sourcePath.isEmpty {
            return sourcePath
        }
        return mimeType.isEmpty ? nil : mimeType
    }

    var optimisticKey: String {
        url
    }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable, Hashable {
        case user
        case assistant
        case tool
        case system
    }

    enum Emphasis: String, Codable, Hashable {
        case normal
        case subtle
        case strong
    }

    struct ToolCall: Codable, Hashable {
        let name: String
        let status: ToolCallStatus
        let detail: String?
        let input: JSONValue?
        let output: JSONValue?
        let error: String?

        init(
            name: String,
            status: ToolCallStatus,
            detail: String? = nil,
            input: JSONValue? = nil,
            output: JSONValue? = nil,
            error: String? = nil
        ) {
            self.name = name
            self.status = status
            self.detail = detail
            self.input = input
            self.output = output
            self.error = error
        }
    }

    enum Kind: Codable, Hashable {
        case plain
        case toolCall(ToolCall)

        private enum CodingKeys: String, CodingKey {
            case type
            case name
            case status
            case detail
            case input
            case output
            case error
        }

        private enum PayloadType: String, Codable {
            case plain
            case toolCall
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(PayloadType.self, forKey: .type) {
            case .plain:
                self = .plain
            case .toolCall:
                self = .toolCall(
                    ToolCall(
                        name: try container.decode(String.self, forKey: .name),
                        status: try container.decode(ToolCallStatus.self, forKey: .status),
                        detail: try container.decodeIfPresent(String.self, forKey: .detail),
                        input: try container.decodeIfPresent(JSONValue.self, forKey: .input),
                        output: try container.decodeIfPresent(JSONValue.self, forKey: .output),
                        error: try container.decodeIfPresent(String.self, forKey: .error)
                    )
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .plain:
                try container.encode(PayloadType.plain, forKey: .type)
            case .toolCall(let toolCall):
                try container.encode(PayloadType.toolCall, forKey: .type)
                try container.encode(toolCall.name, forKey: .name)
                try container.encode(toolCall.status, forKey: .status)
                try container.encodeIfPresent(toolCall.detail, forKey: .detail)
                try container.encodeIfPresent(toolCall.input, forKey: .input)
                try container.encodeIfPresent(toolCall.output, forKey: .output)
                try container.encodeIfPresent(toolCall.error, forKey: .error)
            }
        }

        var toolCall: ToolCall? {
            guard case .toolCall(let toolCall) = self else { return nil }
            return toolCall
        }
    }

    enum ToolCallStatus: String, Codable, Hashable {
        case pending
        case running
        case completed
        case error

        var label: String { rawValue }
    }

    let id: String
    var messageID: String?
    var role: Role
    var text: String
    var timestamp: Date
    var emphasis: Emphasis
    var kind: Kind
    var isInProgress: Bool
    var attachment: ChatAttachment?

    init(
        id: String,
        messageID: String? = nil,
        role: Role,
        text: String,
        timestamp: Date,
        emphasis: Emphasis,
        kind: Kind = .plain,
        isInProgress: Bool = false,
        attachment: ChatAttachment? = nil
    ) {
        self.id = id
        self.messageID = messageID
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.emphasis = emphasis
        self.kind = kind
        self.isInProgress = isInProgress
        self.attachment = attachment
    }

    init?(part: OpenCodePart, defaultRole: Role = .assistant) {
        guard part.shouldDisplay else { return nil }
        self.id = part.id
        self.messageID = part.messageID
        self.role = part.chatRole(defaultRole: defaultRole)
        self.text = part.renderedText
        self.timestamp = part.updatedAt ?? Date()
        self.emphasis = part.chatEmphasis
        self.kind = part.chatMessageKind
        self.isInProgress = part.isInProgress
        self.attachment = part.attachment
    }

    static func makeTranscript(from messages: [OpenCodeMessageEnvelope]) -> [ChatMessage] {
        messages.flatMap { message in
            let timestamp = message.info.createdAt ?? message.info.updatedAt ?? Date()
            return message.parts.filter(\.shouldDisplay).map { part in
                ChatMessage(
                    id: part.id,
                    messageID: message.info.id,
                    role: part.chatRole(defaultRole: message.info.chatRole),
                    text: part.renderedText,
                    timestamp: part.updatedAt ?? timestamp,
                    emphasis: part.chatEmphasis,
                    kind: part.chatMessageKind,
                    isInProgress: part.isInProgress,
                    attachment: part.attachment
                )
            }
        }
    }
}

enum RuntimeStatus: String, Codable, Equatable, Hashable {
    case connected
    case indexing
    case idle
}

enum SessionStatus: String, Codable, Equatable, Hashable {
    case idle
    case running
    case attention
}

enum SeedProjects {
    static let defaults: [ProjectSummary] = []
}
