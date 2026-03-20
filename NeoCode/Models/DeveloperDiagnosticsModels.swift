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
    let bufferedDeltaCount: Int
    let pendingPermissionCount: Int
    let pendingQuestionCount: Int
    let queuedMessageCount: Int
    let transcriptMessageCount: Int
    let transcriptRevision: Int
    let lastUpdatedAt: Date
    let possibleStuckReason: String?
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
            "Buffered deltas: \(bufferedDeltaCount)",
            "Pending permissions: \(pendingPermissionCount)",
            "Pending questions: \(pendingQuestionCount)",
            "Queued messages: \(queuedMessageCount)",
            "Transcript messages: \(transcriptMessageCount)",
            "Transcript revision: \(transcriptRevision)",
            "Last updated: \(lastUpdatedAt.formatted(date: .abbreviated, time: .standard))",
            "Possible stuck reason: \(possibleStuckReason ?? "none")",
        ]

        let eventLines = recentEvents.map {
            "[\($0.timestamp.formatted(date: .omitted, time: .standard))] [\($0.category)] \($0.message)"
        }

        if eventLines.isEmpty {
            return header.joined(separator: "\n")
        }

        return (header + ["", "Recent events:"] + eventLines).joined(separator: "\n")
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
