import Foundation

struct ComposerAttachment: Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: String

    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
}

struct ComposerModelOption: Identifiable, Hashable {
    let id: String
    let providerID: String
    let modelID: String
    let title: String
    let variants: [String]
}

extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var thinkingLevelSortKey: Int {
        switch lowercased() {
        case "none": 0
        case "low": 1
        case "medium": 2
        case "high": 3
        case "xhigh", "very_high", "very-high", "max": 4
        default: 100
        }
    }
}
