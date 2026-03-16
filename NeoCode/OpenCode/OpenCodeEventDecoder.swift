import Foundation

enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    nonisolated var prettyPrinted: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        case .bool(let value): return String(value)
        case .null: return "null"
        case .array(let values):
            let payload = values.map { $0.foundationValue }
            return Self.stringify(payload)
        case .object(let values):
            let payload = values.mapValues { $0.foundationValue }
            return Self.stringify(payload)
        }
    }

    nonisolated var displayString: String? {
        guard isMeaningfulDisplayValue else { return nil }
        return prettyPrinted
    }

    private nonisolated var isMeaningfulDisplayValue: Bool {
        switch self {
        case .null:
            return false
        case .string(let value):
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let values):
            return !values.isEmpty
        case .object(let values):
            return !values.isEmpty
        case .number, .bool:
            return true
        }
    }

    private nonisolated var foundationValue: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .null: NSNull()
        case .array(let values): values.map(\.foundationValue)
        case .object(let values): values.mapValues(\.foundationValue)
        }
    }

    private static nonisolated func stringify(_ payload: Any) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8)
        else {
            return String(describing: payload)
        }
        return string
    }
}

enum OpenCodeEventDecoder {
    private struct RawEvent: Decodable {
        let type: String
        let properties: DataBackedProperties
    }

    private struct DataBackedProperties: Decodable {
        let rawData: Data

        init(from decoder: Decoder) throws {
            let value = try JSONValue(from: decoder)
            rawData = try JSONEncoder().encode(value)
        }
    }

    private struct SessionPayload: Decodable { let info: OpenCodeSession }
    private struct SessionStatusPayload: Decodable {
        let sessionID: String
        let status: OpenCodeSessionActivity
    }
    private struct PermissionPayload: Decodable { let properties: OpenCodePermissionRequest }
    private struct QuestionPayload: Decodable { let properties: OpenCodeQuestionRequest }
    private struct MessagePayload: Decodable { let info: OpenCodeMessageInfo }
    private struct PartPayload: Decodable { let part: OpenCodePart }
    private struct PartDeltaPayload: Decodable {
        let sessionID: String
        let messageID: String
        let partID: String
        let field: String
        let delta: String
    }
    private struct SessionDeletedPayload: Decodable {
        let id: String?
        let sessionID: String?
    }

    static func decode(frame: OpenCodeSSEFrame, decoder: JSONDecoder = .opencode) throws -> OpenCodeEvent {
        if frame.event == "server.connected" {
            return .connected
        }

        let data = Data(frame.data.utf8)
        let raw = try decoder.decode(RawEvent.self, from: data)
        switch raw.type {
        case "server.connected":
            return .connected
        case "session.created":
            return .sessionCreated(try decoder.decode(SessionPayload.self, from: raw.properties.rawData).info)
        case "session.updated":
            return .sessionUpdated(try decoder.decode(SessionPayload.self, from: raw.properties.rawData).info)
        case "session.deleted":
            let payload = try decoder.decode(SessionDeletedPayload.self, from: raw.properties.rawData)
            return .sessionDeleted(payload.id ?? payload.sessionID ?? "")
        case "session.status":
            let payload = try decoder.decode(SessionStatusPayload.self, from: raw.properties.rawData)
            return .sessionStatusChanged(sessionID: payload.sessionID, status: payload.status)
        case "permission.asked":
            return .permissionAsked(try decoder.decode(OpenCodePermissionRequest.self, from: raw.properties.rawData))
        case "permission.replied":
            return .permissionReplied(try decoder.decode(OpenCodePermissionReplyEvent.self, from: raw.properties.rawData))
        case "question.asked":
            return .questionAsked(try decoder.decode(OpenCodeQuestionRequest.self, from: raw.properties.rawData))
        case "question.replied":
            return .questionReplied(try decoder.decode(OpenCodeQuestionReplyEvent.self, from: raw.properties.rawData))
        case "question.rejected":
            return .questionRejected(try decoder.decode(OpenCodeQuestionRejectEvent.self, from: raw.properties.rawData))
        case "message.updated":
            return .messageUpdated(try decoder.decode(MessagePayload.self, from: raw.properties.rawData).info)
        case "message.part.updated":
            return .messagePartUpdated(try decoder.decode(PartPayload.self, from: raw.properties.rawData).part)
        case "message.part.delta":
            let payload = try decoder.decode(PartDeltaPayload.self, from: raw.properties.rawData)
            return .messagePartDelta(
                OpenCodePartDelta(
                    sessionID: payload.sessionID,
                    messageID: payload.messageID,
                    partID: payload.partID,
                    field: payload.field,
                    delta: payload.delta
                )
            )
        default:
            return .ignored(raw.type)
        }
    }
}

enum OpenCodeClientError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenCode returned an invalid response."
        case .httpStatus(let statusCode):
            return "OpenCode request failed with status \(statusCode)."
        }
    }
}
