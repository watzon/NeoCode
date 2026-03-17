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

    func displayedSessions(showAll: Bool = false) -> [SessionSummary] {
        guard !showAll else { return sessions }
        return Array(sessions.prefix(Self.displayedSessionLimit))
    }

    var hiddenSessionCount: Int {
        max(0, sessions.count - Self.displayedSessionLimit)
    }

    var hasHiddenSessions: Bool {
        hiddenSessionCount > 0
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
    var summary: OpenCodeSessionSummary?
    var revert: OpenCodeSessionRevert?
    var stats: SessionStatsSnapshot?
    var transcript: [ChatMessage]
    var isEphemeral: Bool

    init(
        id: String,
        parentID: String? = nil,
        title: String,
        lastUpdatedAt: Date,
        status: SessionStatus = .idle,
        summary: OpenCodeSessionSummary? = nil,
        revert: OpenCodeSessionRevert? = nil,
        stats: SessionStatsSnapshot? = nil,
        transcript: [ChatMessage] = [],
        isEphemeral: Bool = false
    ) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.lastUpdatedAt = lastUpdatedAt
        self.status = status
        self.summary = summary
        self.revert = revert
        self.stats = stats
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
            summary: session.summary,
            revert: session.revert,
            stats: nil,
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
        let normalized = trimmed.lowercased()
        let placeholder = defaultTitle.lowercased()
        return normalized == placeholder || normalized.hasPrefix("\(placeholder) - ")
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

struct RevertPreviewFileChange: Identifiable, Hashable {
    enum Status: String, Hashable {
        case added
        case deleted
        case modified
    }

    let path: String
    let additions: Int
    let deletions: Int
    let status: Status

    var id: String { path }
}

struct SessionRevertPreview: Identifiable, Hashable {
    let targetPartID: String
    let upstreamMessageID: String
    let restoredText: String
    let restoredAttachments: [ComposerAttachment]
    let affectedPromptCount: Int
    let changedFiles: [RevertPreviewFileChange]

    var id: String { targetPartID }
}

struct ChatAttachment: Codable, Hashable {
    let filename: String?
    let mimeType: String
    let url: String
    let sourcePath: String?

    nonisolated init(filename: String?, mimeType: String, url: String, sourcePath: String? = nil) {
        self.filename = filename
        self.mimeType = mimeType
        self.url = url
        self.sourcePath = sourcePath
    }

    nonisolated init(attachment: ComposerAttachment) {
        self.init(
            filename: attachment.name,
            mimeType: attachment.mimeType,
            url: attachment.requestURL,
            sourcePath: attachment.filePath
        )
    }

    nonisolated var isImage: Bool {
        mimeType.lowercased().hasPrefix("image/")
    }

    nonisolated var displayTitle: String {
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

    nonisolated var displaySubtitle: String? {
        if let sourcePath, !sourcePath.isEmpty {
            return sourcePath
        }
        return mimeType.isEmpty ? nil : mimeType
    }

    nonisolated var optimisticKey: String {
        url
    }

    var composerAttachment: ComposerAttachment? {
        if let sourcePath, !sourcePath.isEmpty {
            return ComposerAttachment(name: displayTitle, mimeType: mimeType, content: .file(path: sourcePath))
        }

        if url.hasPrefix("data:") {
            return ComposerAttachment(name: displayTitle, mimeType: mimeType, content: .dataURL(url))
        }

        if let parsedURL = URL(string: url), parsedURL.isFileURL {
            return ComposerAttachment(name: displayTitle, mimeType: mimeType, content: .file(path: parsedURL.path))
        }

        return nil
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

        nonisolated init(
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
        case compactionMarker

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
            case compactionMarker
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
            case .compactionMarker:
                self = .compactionMarker
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
            case .compactionMarker:
                try container.encode(PayloadType.compactionMarker, forKey: .type)
            }
        }

        var toolCall: ToolCall? {
            guard case .toolCall(let toolCall) = self else { return nil }
            return toolCall
        }

        var isCompactionMarker: Bool {
            if case .compactionMarker = self { return true }
            return false
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

    nonisolated var turnGroupID: String {
        messageID ?? id
    }

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
            let containsAttachment = message.parts.contains { $0.attachment != nil }
            let promotedFileReferences = message.info.chatRole == .user
                ? message.parts.compactMap(\.promotedSourceText)
                : []

            let transcript = message.parts.compactMap { part -> ChatMessage? in
                guard part.shouldDisplay else { return nil }
                guard !(message.info.chatRole == .user && containsAttachment && part.isSyntheticAttachmentReadSummary) else {
                    return nil
                }
                guard !(message.info.chatRole == .user && (containsAttachment || !promotedFileReferences.isEmpty) && part.isSyntheticUserFileContentDump) else {
                    return nil
                }
                guard !(message.info.chatRole == .user && part.isPromotedFileReference) else {
                    return nil
                }

                return ChatMessage(
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

            guard transcript.isEmpty,
                  message.info.chatRole == .user,
                  !promotedFileReferences.isEmpty
            else {
                return transcript
            }

            return [
                ChatMessage(
                    id: "\(message.info.id)-promoted-file-reference",
                    messageID: message.info.id,
                    role: .user,
                    text: promotedFileReferences.joined(separator: " "),
                    timestamp: timestamp,
                    emphasis: .normal
                )
            ]
        }
    }
}

struct SessionStatsSnapshot: Codable, Hashable, Sendable {
    let sessionID: String
    let providerID: String?
    let modelID: String?
    let modelTitle: String?
    let contextWindow: Int?
    let totalContextTokens: Int
    let inputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let totalCost: Double
    let lastActivityAt: Date?

    var remainingContextTokens: Int? {
        guard let contextWindow else { return nil }
        return max(contextWindow - totalContextTokens, 0)
    }

    var usedContextFraction: Double? {
        guard let contextWindow, contextWindow > 0 else { return nil }
        return min(max(Double(totalContextTokens) / Double(contextWindow), 0), 1)
    }

    var remainingContextFraction: Double? {
        guard let usedContextFraction else { return nil }
        return max(1 - usedContextFraction, 0)
    }

    var percentUsed: Int? {
        guard let usedContextFraction else { return nil }
        return Int((usedContextFraction * 100).rounded())
    }

    var percentRemaining: Int? {
        guard let remainingContextFraction else { return nil }
        return Int((remainingContextFraction * 100).rounded())
    }

    var modelDisplayName: String {
        modelTitle ?? modelID ?? "Unknown model"
    }

    static func make(
        sessionID: String,
        messageInfos: [OpenCodeMessageInfo],
        models: [ComposerModelOption]
    ) -> SessionStatsSnapshot? {
        let assistantInfos = messageInfos
            .filter { $0.role == "assistant" }
            .sorted {
                ($0.updatedAt ?? $0.createdAt ?? .distantPast) < ($1.updatedAt ?? $1.createdAt ?? .distantPast)
            }

        guard !assistantInfos.isEmpty else { return nil }

        let usageInfo = assistantInfos.last { info in
            guard let tokens = info.tokens else { return false }
            let total = tokens.total ?? tokens.input + tokens.output + tokens.reasoning + (tokens.cache?.read ?? 0) + (tokens.cache?.write ?? 0)
            return total > 0
        }

        let referenceInfo = usageInfo ?? assistantInfos.last
        guard let referenceInfo else { return nil }

        let tokens = referenceInfo.tokens
        let inputTokens = tokens?.input ?? 0
        let outputTokens = tokens?.output ?? 0
        let reasoningTokens = tokens?.reasoning ?? 0
        let cacheReadTokens = tokens?.cache?.read ?? 0
        let cacheWriteTokens = tokens?.cache?.write ?? 0
        let totalContextTokens = tokens?.total ?? (inputTokens + outputTokens + reasoningTokens + cacheReadTokens + cacheWriteTokens)

        let matchedModel = models.first {
            $0.providerID == referenceInfo.providerID && $0.modelID == referenceInfo.modelID
        }

        return SessionStatsSnapshot(
            sessionID: sessionID,
            providerID: referenceInfo.providerID,
            modelID: referenceInfo.modelID,
            modelTitle: matchedModel?.title,
            contextWindow: matchedModel?.contextWindow,
            totalContextTokens: totalContextTokens,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            reasoningTokens: reasoningTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            totalCost: assistantInfos.reduce(0) { $0 + ($1.cost ?? 0) },
            lastActivityAt: messageInfos.compactMap { $0.updatedAt ?? $0.createdAt }.max()
        )
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
