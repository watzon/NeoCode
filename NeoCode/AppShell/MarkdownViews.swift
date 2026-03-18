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
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let attributed):
                    Text(attributed)
                        .textSelection(.enabled)
                case .table(let table):
                    MarkdownTableView(table: table, baseFont: baseFont, textColor: textColor)
                }
            }
        }
    }

    private var elements: [MarkdownElement] {
        MarkdownRenderCache.elements(for: markdown)
    }

    private var segments: [MarkdownSegment] {
        var results: [MarkdownSegment] = []
        var currentText = AttributedString()

        func flushText() {
            guard !currentText.characters.isEmpty else { return }
            results.append(.text(currentText))
            currentText = AttributedString()
        }

        for (index, element) in elements.enumerated() {
            switch element {
            case .table(let table):
                flushText()
                if index == 0, let leadingLabel {
                    results.append(.text(leadingLabelAttributedString(leadingLabel, trailingNewlines: 2)))
                }
                results.append(.table(table))
            case .heading(let level, let text):
                if !currentText.characters.isEmpty {
                    currentText.append(AttributedString("\n\n"))
                } else if index == 0, let leadingLabel {
                    currentText.append(leadingLabelAttributedString(leadingLabel))
                }
                currentText.append(styledInlineAttributedString(text: text, baseFont: headingFont(level), textColor: textColor))
            case .paragraph(let text):
                if !currentText.characters.isEmpty {
                    currentText.append(AttributedString("\n\n"))
                } else if index == 0, let leadingLabel {
                    currentText.append(leadingLabelAttributedString(leadingLabel))
                }
                currentText.append(styledInlineAttributedString(text: text, baseFont: baseFont, textColor: textColor))
            case .list(let items):
                if !currentText.characters.isEmpty {
                    currentText.append(AttributedString("\n\n"))
                } else if index == 0, let leadingLabel {
                    currentText.append(leadingLabelAttributedString(leadingLabel))
                }

                for (itemIndex, item) in items.enumerated() {
                    if itemIndex > 0 {
                        currentText.append(AttributedString("\n"))
                    }
                    currentText.append(attributedString(for: item))
                }
            }
        }

        flushText()
        return results
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

    private func leadingLabelAttributedString(_ leadingLabel: MarkdownLeadingLabel, trailingNewlines: Int = 0) -> AttributedString {
        var attributed = AttributedString(leadingLabel.text)
        attributed.font = .system(size: 13, weight: .bold, design: .default)
        attributed.foregroundColor = leadingLabel.color

        if trailingNewlines > 0 {
            attributed.append(AttributedString(String(repeating: "\n", count: trailingNewlines)))
        }

        return attributed
    }

    private func attributedString(for item: MarkdownListItem) -> AttributedString {
        var attributed = AttributedString(String(repeating: " ", count: item.level * 4))

        var marker = AttributedString("\(markerLabel(for: item.marker)) ")
        marker.font = Font.neoMono
        marker.foregroundColor = markerColor(for: item.marker)
        attributed.append(marker)
        attributed.append(styledInlineAttributedString(text: item.text, baseFont: baseFont, textColor: textColor))
        return attributed
    }

    private func styledInlineAttributedString(text: String, baseFont: Font, textColor: Color) -> AttributedString {
        var attributed = MarkdownRenderCache.inlineAttributedString(for: text) ?? AttributedString(text)
        attributed.font = baseFont
        attributed.foregroundColor = textColor

        for run in attributed.runs {
            if run.inlinePresentationIntent == .code {
                attributed[run.range].foregroundColor = NeoCodeTheme.accent
                attributed[run.range].font = Font.neoMono
            }
        }

        return attributed
    }
}

enum MarkdownSegment {
    case text(AttributedString)
    case table(MarkdownTable)
}

enum MarkdownElement {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([MarkdownListItem])
    case table(MarkdownTable)

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

struct MarkdownTable {
    let headers: [String]
    let rows: [[String]]
    let alignments: [Alignment]
    
    enum Alignment {
        case left
        case center
        case right
    }
}

struct MarkdownTableView: View {
    let table: MarkdownTable
    let baseFont: Font
    let textColor: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                        cell(
                            text: header,
                            font: .system(size: 13, weight: .semibold, design: .default),
                            background: NeoCodeTheme.panelRaised.opacity(0.7),
                            alignment: table.alignments[safe: index] ?? .left
                        )
                        .gridColumnAlignment(columnAlignment(for: table.alignments[safe: index] ?? .left))
                    }
                }

                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { index, value in
                            cell(
                                text: value,
                                font: baseFont,
                                background: rowIndex.isMultiple(of: 2) ? NeoCodeTheme.panel : NeoCodeTheme.panelSoft,
                                alignment: table.alignments[safe: index] ?? .left
                            )
                        }
                    }
                }
            }
            .background(NeoCodeTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(NeoCodeTheme.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func cell(text: String, font: Font, background: Color, alignment: MarkdownTable.Alignment) -> some View {
        InlineMarkdownText(text: text, baseFont: font)
            .foregroundStyle(textColor)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 96, maxWidth: .infinity, alignment: frameAlignment(for: alignment))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(NeoCodeTheme.line)
                    .frame(height: 1)
            }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(NeoCodeTheme.line)
                    .frame(width: 1)
            }
    }

    private func frameAlignment(for tableAlignment: MarkdownTable.Alignment) -> Alignment {
        switch tableAlignment {
        case .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        }
    }

    private func columnAlignment(for tableAlignment: MarkdownTable.Alignment) -> HorizontalAlignment {
        switch tableAlignment {
        case .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
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
        var lineIndex = 0

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

        while lineIndex < lines.count {
            let rawLine = lines[lineIndex]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                flushList()
                lineIndex += 1
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                flushList()
                results.append(heading)
                lineIndex += 1
                continue
            }

            if let item = parseListItem(rawLine) {
                flushParagraph()
                listItems.append(item)
                lineIndex += 1
                continue
            }

            // Check for table
            if let (table, consumedLines) = parseTable(from: lines, startingAt: lineIndex) {
                flushParagraph()
                flushList()
                results.append(.table(table))
                lineIndex += consumedLines
                continue
            }

            flushList()
            paragraph.append(line)
            lineIndex += 1
        }

        flushParagraph()
        flushList()
        return results
    }

    private static func parseTable(from lines: [String], startingAt startIndex: Int) -> (MarkdownTable, Int)? {
        guard startIndex < lines.count else { return nil }

        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)

        // Check if line looks like a table row (starts and ends with |)
        guard headerLine.hasPrefix("|") && headerLine.hasSuffix("|") else { return nil }

        // Check if there's a next line for the separator
        guard startIndex + 1 < lines.count else { return nil }

        let separatorLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)

        // Check if separator line is valid (contains only |, -, :, and spaces)
        guard separatorLine.range(of: "^\\|[-:\\s|]+\\|$", options: .regularExpression) != nil ||
              (separatorLine.hasPrefix("|") && separatorLine.hasSuffix("|")) else { return nil }

        // Verify separator contains dashes
        guard separatorLine.contains("-") else { return nil }

        // Parse headers
        let headers = parseTableCells(headerLine)

        // Parse alignments from separator
        let alignments = parseTableAlignments(separatorLine, columnCount: headers.count)

        // Parse data rows
        var rows: [[String]] = []
        var currentIndex = startIndex + 2

        while currentIndex < lines.count {
            let line = lines[currentIndex].trimmingCharacters(in: .whitespaces)

            // Check if this is a table row
            guard line.hasPrefix("|") && line.hasSuffix("|") else { break }

            // Check if this looks like another header/separator (stop parsing)
            if line.range(of: "^\\|[-:\\s|]+\\|$", options: .regularExpression) != nil && line.contains("-") {
                break
            }

            let cells = parseTableCells(line)
            // Pad cells to match header count
            var paddedCells = cells
            while paddedCells.count < headers.count {
                paddedCells.append("")
            }
            rows.append(Array(paddedCells.prefix(headers.count)))

            currentIndex += 1
        }

        guard !rows.isEmpty else { return nil }

        let table = MarkdownTable(headers: headers, rows: rows, alignments: alignments)
        return (table, currentIndex - startIndex)
    }

    private static func parseTableCells(_ line: String) -> [String] {
        // Remove leading and trailing |
        let trimmed = line.dropFirst().dropLast()

        // Split by |
        let cells = trimmed.split(separator: "|", omittingEmptySubsequences: false)

        return cells.map { cell in
            String(cell).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func parseTableAlignments(_ separatorLine: String, columnCount: Int) -> [MarkdownTable.Alignment] {
        // Remove leading and trailing |
        let trimmed = separatorLine.dropFirst().dropLast()

        // Split by |
        let parts = trimmed.split(separator: "|", omittingEmptySubsequences: false)

        return parts.prefix(columnCount).map { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            let hasLeftColon = trimmed.hasPrefix(":")
            let hasRightColon = trimmed.hasSuffix(":")

            if hasLeftColon && hasRightColon {
                return .center
            } else if hasRightColon {
                return .right
            } else {
                return .left
            }
        }
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
