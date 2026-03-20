import Foundation

struct OpenCodeSSEFrame: Equatable {
    var event: String?
    var data: String
}

struct OpenCodeSSEParser {
    private var currentEvent: String?
    private var currentData: [String] = []

    nonisolated mutating func ingest(line: String) -> OpenCodeSSEFrame? {
        if line.isEmpty {
            return flush()
        }

        if line.hasPrefix(":") {
            return nil
        }

        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        let value: String

        if parts.count == 2 {
            let rawValue = String(parts[1])
            value = rawValue.hasPrefix(" ") ? String(rawValue.dropFirst()) : rawValue
        } else {
            value = ""
        }

        switch field {
        case "event":
            currentEvent = value
        case "data":
            currentData.append(value)
        default:
            break
        }

        return nil
    }

    nonisolated mutating func flush() -> OpenCodeSSEFrame? {
        guard !currentData.isEmpty || currentEvent != nil else { return nil }
        let frame = OpenCodeSSEFrame(event: currentEvent, data: currentData.joined(separator: "\n"))
        currentEvent = nil
        currentData = []
        return frame
    }
}
