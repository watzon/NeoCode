import Foundation

struct SessionDebugEvent: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: String
    let message: String

    init(id: UUID = UUID(), timestamp: Date = .now, category: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
    }
}

struct SessionInProgressDiagnostic: Identifiable, Equatable, Hashable, Sendable {
    enum Category: String, Equatable, Hashable, Sendable {
        case assistantOutput = "Assistant output"
        case toolCall = "Tool call"
        case backgroundTool = "Background tool"
    }

    enum BlockingReason: String, Equatable, Hashable, Sendable {
        case messageIncomplete = "message incomplete"
        case partIncomplete = "part incomplete"
        case detachedBackgroundTool = "detached background tool"
        case foregroundToolRunning = "foreground tool still running"
        case unexpectedUserProgress = "user message still marked active"
        case orphanedAfterRefresh = "orphaned after refresh"
        case unknown = "unknown"
    }

    let id: String
    let messageID: String?
    let title: String
    let detail: String?
    let category: Category
    let isBlocking: Bool
    let role: String
    let blockingReason: BlockingReason
    let parentMessageCompletedAt: Date?
    let itemTimestamp: Date
}

struct SessionDebugSnapshot: Equatable, Sendable {
    let projectName: String
    let projectPath: String
    let sessionID: String
    let sessionTitle: String
    let sessionStatus: SessionStatus
    let liveActivity: OpenCodeSessionActivity?
    let isActivelyResponding: Bool
    let hasLocalActivity: Bool
    let inProgressMessageCount: Int
    let blockingInProgressMessageCount: Int
    let nonBlockingInProgressMessageCount: Int
    let bufferedDeltaCount: Int
    let pendingPermissionCount: Int
    let pendingQuestionCount: Int
    let queuedMessageCount: Int
    let transcriptMessageCount: Int
    let transcriptRevision: Int
    let lastUpdatedAt: Date
    let lastLiveEventAt: Date?
    let lastLiveEventLabel: String?
    let lastTranscriptRefreshAt: Date?
    let lastCompletedMessageAt: Date?
    let possibleStuckReason: String?
    let inProgressDiagnostics: [SessionInProgressDiagnostic]
    let recentEvents: [SessionDebugEvent]

    var copySummary: String {
        let liveActivityLabel: String
        if let liveActivity {
            switch liveActivity {
            case .idle:
                liveActivityLabel = "idle"
            case .busy:
                liveActivityLabel = "busy"
            case .retry(let attempt, let message, let next):
                liveActivityLabel = "retry(attempt=\(attempt), next=\(next), message=\(message))"
            }
        } else {
            liveActivityLabel = "none"
        }

        let header = [
            "Project: \(projectName)",
            "Path: \(projectPath)",
            "Session: \(sessionTitle) (\(sessionID))",
            "Status: \(sessionStatus.rawValue)",
            "Live activity: \(liveActivityLabel)",
            "Actively responding: \(isActivelyResponding)",
            "Local activity: \(hasLocalActivity)",
            "In-progress messages: \(inProgressMessageCount)",
            "Blocking in-progress messages: \(blockingInProgressMessageCount)",
            "Non-blocking in-progress messages: \(nonBlockingInProgressMessageCount)",
            "Buffered deltas: \(bufferedDeltaCount)",
            "Pending permissions: \(pendingPermissionCount)",
            "Pending questions: \(pendingQuestionCount)",
            "Queued messages: \(queuedMessageCount)",
            "Transcript messages: \(transcriptMessageCount)",
            "Transcript revision: \(transcriptRevision)",
            "Last updated: \(lastUpdatedAt.formatted(date: .abbreviated, time: .standard))",
            "Last live event: \(formattedDate(lastLiveEventAt, fallback: lastLiveEventLabel.map { "\($0)" } ?? "none"))",
            "Last transcript refresh: \(formattedDate(lastTranscriptRefreshAt))",
            "Last completed message: \(formattedDate(lastCompletedMessageAt))",
            "Possible stuck reason: \(possibleStuckReason ?? "none")",
        ]

        let progressLines = inProgressDiagnostics.map { diagnostic in
            let blockingLabel = diagnostic.isBlocking ? "blocking" : "non-blocking"
            let detailSuffix: String
            if let detail = diagnostic.detail, !detail.isEmpty {
                detailSuffix = " - \(detail)"
            } else {
                detailSuffix = ""
            }

            return "[\(diagnostic.category.rawValue)] [\(blockingLabel)] [reason=\(diagnostic.blockingReason.rawValue)] [role=\(diagnostic.role)] \(diagnostic.title)\(detailSuffix)"
        }

        let eventLines = recentEvents.map {
            "[\($0.timestamp.formatted(date: .omitted, time: .standard))] [\($0.category)] \($0.message)"
        }

        var sections = header
        if !progressLines.isEmpty {
            sections += ["", "In-progress diagnostics:"] + progressLines
        }

        if eventLines.isEmpty {
            return sections.joined(separator: "\n")
        }

        return (sections + ["", "Recent events:"] + eventLines).joined(separator: "\n")
    }

    private func formattedDate(_ date: Date?, fallback: String = "none") -> String {
        guard let date else { return fallback }
        return date.formatted(date: .abbreviated, time: .standard)
    }
}

struct AppLogEntry: Identifiable, Equatable, Hashable, Sendable {
    let date: Date
    let level: String
    let category: String
    let message: String

    var id: String {
        "\(date.timeIntervalSinceReferenceDate)|\(level)|\(category)|\(message)"
    }

    var formattedLine: String {
        "[\(Self.timestampFormatter.string(from: date))] [\(level)] [\(category)] \(message)"
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
