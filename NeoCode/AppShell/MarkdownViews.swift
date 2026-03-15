import Foundation
import SwiftUI

struct AssistantOutputView: View {
    let message: ChatMessage

    var body: some View {
        MarkdownMessageView(markdown: message.text, baseFont: .neoBody)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ThinkingRowView: View {
    let message: ChatMessage
    let showsLabel: Bool

    init(message: ChatMessage, showsLabel: Bool = true) {
        self.message = message
        self.showsLabel = showsLabel
    }

    var body: some View {
        MarkdownMessageView(
            markdown: message.text,
            baseFont: .neoBody,
            textColor: NeoCodeTheme.textMuted,
            leadingLabel: showsLabel ? MarkdownLeadingLabel(text: "Thinking: ", color: NeoCodeTheme.accent.opacity(0.72)) : nil
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MarkdownLeadingLabel {
    let text: String
    let color: Color
}

struct MarkdownMessageView: View {
    let markdown: String
    let baseFont: Font
    let textColor: Color
    let leadingLabel: MarkdownLeadingLabel?

    init(markdown: String, baseFont: Font, textColor: Color = NeoCodeTheme.textPrimary, leadingLabel: MarkdownLeadingLabel? = nil) {
        self.markdown = markdown
        self.baseFont = baseFont
        self.textColor = textColor
        self.leadingLabel = leadingLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .prose(let text):
                    ProseMarkdownView(
                        markdown: text,
                        baseFont: baseFont,
                        textColor: textColor,
                        leadingLabel: index == 0 ? leadingLabel : nil
                    )
                case .code(let code):
                    VStack(alignment: .leading, spacing: 8) {
                        if index == 0, let leadingLabel {
                            Text(leadingLabel.text)
                                .font(.system(size: 13, weight: .bold, design: .default))
                                .foregroundStyle(leadingLabel.color)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(code)
                                .font(.neoMono)
                                .foregroundStyle(textColor)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(NeoCodeTheme.panelRaised)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(NeoCodeTheme.line, lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    private var blocks: [MarkdownBlock] {
        MarkdownRenderCache.blocks(for: markdown)
    }
}

enum MarkdownBlock {
    case prose(String)
    case code(String)
}

struct ProseMarkdownView: View {
    let markdown: String
    let baseFont: Font
    let textColor: Color
    let leadingLabel: MarkdownLeadingLabel?

    init(markdown: String, baseFont: Font, textColor: Color = NeoCodeTheme.textPrimary, leadingLabel: MarkdownLeadingLabel? = nil) {
        self.markdown = markdown
        self.baseFont = baseFont
        self.textColor = textColor
        self.leadingLabel = leadingLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(elements.enumerated()), id: \.offset) { index, element in
                if index == 0, let leadingLabel, !element.supportsInlineLeadingLabel {
                    Text(leadingLabel.text)
                        .font(.system(size: 13, weight: .bold, design: .default))
                        .foregroundStyle(leadingLabel.color)
                }

                switch element {
                case .heading(let level, let text):
                    InlineMarkdownText(text: text, baseFont: headingFont(level))
                        .foregroundStyle(textColor)
                case .paragraph(let text):
                    if index == 0, let leadingLabel {
                        LabeledInlineMarkdownText(
                            label: leadingLabel.text,
                            labelColor: leadingLabel.color,
                            text: text,
                            baseFont: baseFont,
                            textColor: textColor
                        )
                    } else {
                        InlineMarkdownText(text: text, baseFont: baseFont)
                            .foregroundStyle(textColor)
                    }
                case .list(let items):
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text(markerLabel(for: item.marker))
                                    .font(.neoMono)
                                    .foregroundStyle(markerColor(for: item.marker))
                                    .frame(width: markerWidth(for: item.marker), alignment: .leading)

                                InlineMarkdownText(text: item.text, baseFont: baseFont)
                                    .foregroundStyle(textColor)
                            }
                            .padding(.leading, CGFloat(item.level) * 18)
                        }
                    }
                }
            }
        }
    }

    private var elements: [MarkdownElement] {
        MarkdownRenderCache.elements(for: markdown)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 16, weight: .semibold, design: .default)
        case 2: return .system(size: 15, weight: .semibold, design: .default)
        default: return .system(size: 14, weight: .semibold, design: .default)
        }
    }

    private func markerLabel(for marker: MarkdownListItem.Marker) -> String {
        switch marker {
        case .bullet:
            return "-"
        case .ordered(let number):
            return "\(number)."
        case .check(let checked):
            return checked ? "[x]" : "[ ]"
        }
    }

    private func markerColor(for marker: MarkdownListItem.Marker) -> Color {
        switch marker {
        case .check(let checked):
            return checked ? NeoCodeTheme.success : NeoCodeTheme.textMuted
        case .bullet, .ordered:
            return NeoCodeTheme.textMuted
        }
    }

    private func markerWidth(for marker: MarkdownListItem.Marker) -> CGFloat {
        switch marker {
        case .ordered(let number):
            return number >= 10 ? 26 : 20
        case .bullet:
            return 12
        case .check:
            return 24
        }
    }
}

enum MarkdownElement {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([MarkdownListItem])

    var supportsInlineLeadingLabel: Bool {
        switch self {
        case .paragraph:
            return true
        case .heading, .list:
            return false
        }
    }
}

struct MarkdownListItem {
    enum Marker {
        case bullet
        case ordered(Int)
        case check(Bool)
    }

    let level: Int
    let marker: Marker
    let text: String
}

struct InlineMarkdownText: View {
    let text: String
    let baseFont: Font

    var body: some View {
        Group {
            if let attributed = styledAttributedString {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(baseFont)
        .textSelection(.enabled)
    }

    private var styledAttributedString: AttributedString? {
        MarkdownRenderCache.inlineAttributedString(for: text)
    }
}

struct LabeledInlineMarkdownText: View {
    let label: String
    let labelColor: Color
    let text: String
    let baseFont: Font
    let textColor: Color

    var body: some View {
        Text("\(labelText)\(bodyText)")
            .textSelection(.enabled)
    }

    private var labelText: Text {
        Text(label)
            .font(.system(size: 13, weight: .bold, design: .default))
            .foregroundColor(labelColor)
    }

    private var bodyText: Text {
        if let attributed = styledAttributedString {
            return Text(attributed)
                .font(baseFont)
                .foregroundColor(textColor)
        }

        return Text(text)
            .font(baseFont)
            .foregroundColor(textColor)
    }

    private var styledAttributedString: AttributedString? {
        MarkdownRenderCache.inlineAttributedString(for: text)
    }
}

private final class CachedMarkdownBlocks: NSObject {
    let value: [MarkdownBlock]

    init(_ value: [MarkdownBlock]) {
        self.value = value
    }
}

private final class CachedMarkdownElements: NSObject {
    let value: [MarkdownElement]

    init(_ value: [MarkdownElement]) {
        self.value = value
    }
}

private final class CachedInlineMarkdown: NSObject {
    let value: AttributedString?

    init(_ value: AttributedString?) {
        self.value = value
    }
}

private enum MarkdownRenderCache {
    private static let blockCache: NSCache<NSString, CachedMarkdownBlocks> = {
        let cache = NSCache<NSString, CachedMarkdownBlocks>()
        cache.countLimit = 256
        return cache
    }()

    private static let elementCache: NSCache<NSString, CachedMarkdownElements> = {
        let cache = NSCache<NSString, CachedMarkdownElements>()
        cache.countLimit = 512
        return cache
    }()

    private static let inlineAttributedCache: NSCache<NSString, CachedInlineMarkdown> = {
        let cache = NSCache<NSString, CachedInlineMarkdown>()
        cache.countLimit = 1024
        return cache
    }()

    static func blocks(for markdown: String) -> [MarkdownBlock] {
        let key = markdown as NSString
        if let cached = blockCache.object(forKey: key) {
            return cached.value
        }

        let parsed = parseBlocks(from: markdown)
        blockCache.setObject(CachedMarkdownBlocks(parsed), forKey: key)
        return parsed
    }

    static func elements(for markdown: String) -> [MarkdownElement] {
        let key = markdown as NSString
        if let cached = elementCache.object(forKey: key) {
            return cached.value
        }

        let parsed = parseElements(from: markdown)
        elementCache.setObject(CachedMarkdownElements(parsed), forKey: key)
        return parsed
    }

    static func inlineAttributedString(for text: String) -> AttributedString? {
        let key = text as NSString
        if let cached = inlineAttributedCache.object(forKey: key) {
            return cached.value
        }

        let parsed = parseInlineMarkdown(from: text)
        inlineAttributedCache.setObject(CachedInlineMarkdown(parsed), forKey: key)
        return parsed
    }

    private static func parseBlocks(from markdown: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        let pieces = markdown.components(separatedBy: "```")

        for (index, piece) in pieces.enumerated() {
            guard !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if index.isMultiple(of: 2) {
                result.append(.prose(piece))
            } else {
                let code = piece.replacingOccurrences(of: "^\\w+\n", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .newlines)
                result.append(.code(code))
            }
        }

        return result
    }

    private static func parseElements(from markdown: String) -> [MarkdownElement] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: .newlines)
        var results: [MarkdownElement] = []
        var paragraph: [String] = []
        var listItems: [MarkdownListItem] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            results.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll(keepingCapacity: true)
        }

        func flushList() {
            guard !listItems.isEmpty else { return }
            results.append(.list(listItems))
            listItems.removeAll(keepingCapacity: true)
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                flushList()
                results.append(heading)
                continue
            }

            if let item = parseListItem(rawLine) {
                flushParagraph()
                listItems.append(item)
                continue
            }

            flushList()
            paragraph.append(line)
        }

        flushParagraph()
        flushList()
        return results
    }

    private static func parseInlineMarkdown(from text: String) -> AttributedString? {
        guard var attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return nil
        }

        for run in attributed.runs {
            if run.inlinePresentationIntent == .code {
                attributed[run.range].foregroundColor = NeoCodeTheme.accent
                attributed[run.range].font = .neoMono
            }
        }

        return attributed
    }

    private static func parseHeading(_ line: String) -> MarkdownElement? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, line.dropFirst(hashes.count).first == " " else { return nil }
        let text = String(line.dropFirst(hashes.count + 1))
        return .heading(level: min(hashes.count, 3), text: text)
    }

    private static func parseListItem(_ rawLine: String) -> MarkdownListItem? {
        let leadingSpaces = rawLine.prefix { $0 == " " }.count
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        let level = leadingSpaces / 2

        if trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") {
            let chars = Array(trimmed)
            guard chars.count > 5 else { return nil }
            let checked = chars[3] == "x" || chars[3] == "X"
            let text = String(chars.dropFirst(6))
            return MarkdownListItem(level: level, marker: .check(checked), text: text)
        }

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return MarkdownListItem(level: level, marker: .bullet, text: String(trimmed.dropFirst(2)))
        }

        if let range = trimmed.range(of: "^\\d+\\.\\s", options: .regularExpression) {
            let prefix = String(trimmed[range])
            let number = Int(
                prefix
                    .replacingOccurrences(of: ".", with: "")
                    .trimmingCharacters(in: CharacterSet.whitespaces)
            ) ?? 1
            return MarkdownListItem(level: level, marker: .ordered(number), text: String(trimmed[range.upperBound...]))
        }

        return nil
    }
}
