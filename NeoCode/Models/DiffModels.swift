import Foundation

struct DiffBundle: Hashable, Codable {
    enum SourceFormat: String, Codable, Hashable {
        case applyPatch
        case unified
        case unknown
    }

    let sourceFormat: SourceFormat
    let files: [DiffFile]
}

struct DiffFile: Identifiable, Hashable, Codable {
    enum ChangeKind: String, Codable, Hashable {
        case added
        case deleted
        case modified
        case renamed
        case copied
        case unknown
    }

    let id: String
    let oldPath: String?
    let newPath: String?
    let change: ChangeKind
    let hunks: [DiffHunk]
    let isBinary: Bool

    var displayPath: String {
        newPath ?? oldPath ?? "Untitled"
    }
}

struct DiffHunk: Hashable, Codable {
    let header: String
    let oldRange: DiffLineRange?
    let newRange: DiffLineRange?
    let lines: [DiffLine]
}

struct DiffLineRange: Hashable, Codable {
    let start: Int
    let count: Int
}

struct DiffLine: Hashable, Codable {
    enum Kind: String, Codable, Hashable {
        case context
        case added
        case removed
        case note
    }

    let kind: Kind
    let text: String
}
