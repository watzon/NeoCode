import Foundation

enum MarkdownRenderBudget {
    static let maxMermaidCharacters = 8_000
    static let maxMermaidLines = 240

    static func shouldRenderMermaid(source: String) -> Bool {
        source.count <= maxMermaidCharacters && lineCount(in: source) <= maxMermaidLines
    }

    static func cacheCost(for text: String) -> Int {
        text.utf16.count
    }

    private static func lineCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.reduce(into: 1) { count, character in
            if character == "\n" {
                count += 1
            }
        }
    }
}
