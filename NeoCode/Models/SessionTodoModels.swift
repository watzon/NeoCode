import Foundation

struct SessionTodoItem: Identifiable, Equatable, Hashable, Sendable {
    enum Status: String, Equatable, Hashable, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
        case cancelled

        nonisolated init?(rawValue: String) {
            switch rawValue.lowercased() {
            case "pending":
                self = .pending
            case "in_progress", "inprogress":
                self = .inProgress
            case "completed", "complete":
                self = .completed
            case "cancelled", "canceled":
                self = .cancelled
            default:
                return nil
            }
        }

        var isActive: Bool {
            switch self {
            case .pending, .inProgress:
                return true
            case .completed, .cancelled:
                return false
            }
        }
    }

    enum Priority: String, Equatable, Hashable, Sendable {
        case high
        case medium
        case low

        nonisolated init?(rawValue: String) {
            switch rawValue.lowercased() {
            case "high":
                self = .high
            case "medium":
                self = .medium
            case "low":
                self = .low
            default:
                return nil
            }
        }
    }

    let id: String
    let content: String
    let status: Status
    let priority: Priority?
}

struct SessionTodoSnapshot: Equatable, Sendable {
    let items: [SessionTodoItem]
    let updatedAt: Date?

    var isEmpty: Bool {
        items.isEmpty
    }

    var remainingCount: Int {
        items.filter { $0.status.isActive }.count
    }
}

enum SessionTodoParser {
    static func latestSnapshot(from messages: [OpenCodeMessageEnvelope]) -> SessionTodoSnapshot? {
        var latest: SessionTodoSnapshot?

        for message in messages {
            for part in message.parts {
                if let snapshot = snapshot(from: part) {
                    latest = snapshot
                }
            }
        }

        return latest
    }

    static func snapshot(from part: OpenCodePart) -> SessionTodoSnapshot? {
        guard let toolName = part.tool?.normalizedTodoToolName else { return nil }

        let payload: JSONValue?
        switch toolName {
        case "todowrite":
            payload = part.state?.input
        case "todoread":
            payload = part.state?.output ?? part.state?.input
        default:
            payload = nil
        }

        guard let payload,
              let items = items(from: payload)
        else {
            return nil
        }

        return SessionTodoSnapshot(items: items, updatedAt: part.updatedAt)
    }

    private static func items(from value: JSONValue) -> [SessionTodoItem]? {
        let todos = todoObjects(from: value)
        guard !todos.isEmpty else { return nil }

        let items = todos.enumerated().compactMap { index, todo in
            item(from: todo, index: index)
        }

        guard !items.isEmpty else { return nil }
        return items
    }

    private static func todoObjects(from value: JSONValue) -> [JSONValue] {
        switch value {
        case .array(let values):
            return values
        case .object(let values):
            if case .array(let todos) = values["todos"] {
                return todos
            }

            if case .array(let items) = values["items"] {
                return items
            }

            return []
        case .string, .number, .bool, .null:
            return []
        }
    }

    private static func item(from value: JSONValue, index: Int) -> SessionTodoItem? {
        guard let object = value.objectValue,
              let content = object["content"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty,
              let rawStatus = object["status"]?.stringValue,
              let status = SessionTodoItem.Status(rawValue: rawStatus)
        else {
            return nil
        }

        let priority = object["priority"]?.stringValue.flatMap(SessionTodoItem.Priority.init(rawValue:))
        return SessionTodoItem(id: "\(index)-\(content)", content: content, status: status, priority: priority)
    }
}

private extension String {
    var normalizedTodoToolName: String {
        let leaf = split(whereSeparator: { $0 == "." || $0 == "/" || $0 == ":" }).last.map(String.init) ?? self
        return leaf.lowercased().replacingOccurrences(of: "_", with: "")
    }
}

private extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}
