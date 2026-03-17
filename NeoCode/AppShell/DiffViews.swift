import SwiftUI

struct ToolCallItemCardView: View {
    let item: ToolCallPresentation.Item
    let toolStatus: ChatMessage.ToolCallStatus
    let contentWidth: CGFloat

    private let diffContentHorizontalInset: CGFloat = 21

    @State private var isExpanded: Bool

    init(item: ToolCallPresentation.Item, toolStatus: ChatMessage.ToolCallStatus, contentWidth: CGFloat) {
        self.item = item
        self.toolStatus = toolStatus
        self.contentWidth = contentWidth
        _isExpanded = State(initialValue: item.defaultExpanded || toolStatus == .pending || toolStatus == .running)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if isExpanded {
                switch item.content {
                case .text(let text):
                    if !text.isEmpty {
                        Text(text)
                            .font(.neoMonoSmall)
                            .foregroundStyle(NeoCodeTheme.textSecondary)
                            .textSelection(.enabled)
                            .padding(.leading, diffContentHorizontalInset)
                            .frame(maxWidth: maxCardWidth, alignment: .leading)
                    }
                case .diff(let file, let style):
                    Group {
                        switch style {
                        case .split:
                            DiffFileView(file: file)
                        case .changesOnly:
                            DiffChangeListView(file: file)
                        }
                    }
                    .padding(.leading, diffContentHorizontalInset)
                }
            }
        }
        .frame(maxWidth: maxCardWidth, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(cardBackground)
        .onChange(of: toolStatus) { _, status in
            withAnimation(.easeOut(duration: 0.16)) {
                isExpanded = item.defaultExpanded || status == .pending || status == .running
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NeoCodeTheme.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textSecondary)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.textMuted)
                }
            }

            Spacer(minLength: 8)

            Text(toolStatus.label)
                .font(.neoMonoSmall)
                .foregroundStyle(statusColor)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.16)) {
                isExpanded.toggle()
            }
        }
    }

    private var statusColor: Color {
        switch toolStatus {
        case .pending, .running:
            return NeoCodeTheme.accent
        case .completed:
            return NeoCodeTheme.success
        case .error:
            return NeoCodeTheme.warning
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(NeoCodeTheme.panelSoft)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(NeoCodeTheme.line, lineWidth: 1)
            )
    }

    private var maxCardWidth: CGFloat {
        if contentWidth.isFinite, contentWidth > 0 {
            return contentWidth
        }

        return .infinity
    }

}

private struct DiffFileView: View {
    let file: DiffFile
    private let rows: [DiffDisplayRow]
    private let lineNumberColumnWidth: CGFloat

    init(file: DiffFile) {
        self.file = file
        let computedRows = DiffDisplayRowBuilder.makeRows(for: file)
        rows = computedRows
        lineNumberColumnWidth = DiffDisplayMetrics.lineNumberColumnWidth(for: computedRows)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                DiffRowView(row: row, lineNumberColumnWidth: lineNumberColumnWidth)
            }
        }
        .background(NeoCodeTheme.diffContextBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiffChangeListView: View {
    let file: DiffFile
    private let rows: [DiffChangeRow]

    init(file: DiffFile) {
        self.file = file
        rows = DiffChangeRowBuilder.makeRows(for: file)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                DiffChangeRowView(row: row)
            }
        }
        .background(NeoCodeTheme.diffContextBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiffRowView: View {
    let row: DiffDisplayRow
    let lineNumberColumnWidth: CGFloat

    var body: some View {
        switch row.content {
        case .note(let text):
            Text(text)
                .font(.neoMonoSmall)
                .foregroundStyle(ToolCallDiffPalette.hunkText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ToolCallDiffPalette.hunkBackground)
        case .split(let left, let right):
            HStack(alignment: .top, spacing: 0) {
                DiffCellView(cell: left, lineNumberColumnWidth: lineNumberColumnWidth)
                Rectangle()
                    .fill(NeoCodeTheme.lineSoft)
                    .frame(width: 1)
                DiffCellView(cell: right, lineNumberColumnWidth: lineNumberColumnWidth)
            }
        }
    }
}

private struct DiffCellView: View {
    let cell: DiffDisplayCell?
    let lineNumberColumnWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(lineNumberText)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.diffLineNumber)
                .frame(width: lineNumberColumnWidth, alignment: .trailing)

            Text(verbatim: displayText)
                .font(.neoMonoSmall)
                .foregroundStyle(textColor)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
    }

    private var lineNumberText: String {
        guard let number = cell?.lineNumber else { return "" }
        return String(number)
    }

    private var displayText: String {
        guard let text = cell?.text else { return "" }
        return text.isEmpty ? " " : text
    }

    private var backgroundColor: Color {
        guard let cell else { return .clear }

        switch cell.kind {
        case .context:
            return .clear
        case .added:
            return ToolCallDiffPalette.addedBackground
        case .removed:
            return ToolCallDiffPalette.removedBackground
        }
    }

    private var textColor: Color {
        guard let cell else {
            return NeoCodeTheme.diffContextText
        }

        switch cell.kind {
        case .context:
            return NeoCodeTheme.diffContextText
        case .added:
            return ToolCallDiffPalette.addedText
        case .removed:
            return ToolCallDiffPalette.removedText
        }
    }
}

private enum DiffDisplayMetrics {
    static func lineNumberColumnWidth(for rows: [DiffDisplayRow]) -> CGFloat {
        let largestLineNumber = rows.reduce(0) { partialResult, row in
            switch row.content {
            case .note:
                return partialResult
            case .split(let left, let right):
                return max(partialResult, left?.lineNumber ?? 0, right?.lineNumber ?? 0)
            }
        }

        let digits = max(2, String(largestLineNumber).count)
        return CGFloat(digits * 8 + 6)
    }
}

private struct DiffChangeRow: Identifiable {
    enum Content {
        case line(prefix: String, text: String, kind: DiffDisplayCell.Kind)
        case note(String)
    }

    let id: String
    let content: Content
}

private struct DiffChangeRowView: View {
    let row: DiffChangeRow

    var body: some View {
        switch row.content {
        case .note(let text):
            Text(text)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.diffContextText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .line(let prefix, let text, let kind):
            HStack(alignment: .top, spacing: 8) {
                Text(prefix)
                    .font(.neoMonoSmall)
                    .foregroundStyle(textColor(for: kind))

                Text(verbatim: text.isEmpty ? " " : text)
                    .font(.neoMonoSmall)
                    .foregroundStyle(textColor(for: kind))
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor(for: kind))
        }
    }

    private func backgroundColor(for kind: DiffDisplayCell.Kind) -> Color {
        switch kind {
        case .context:
            return .clear
        case .added:
            return ToolCallDiffPalette.addedBackground
        case .removed:
            return ToolCallDiffPalette.removedBackground
        }
    }

    private func textColor(for kind: DiffDisplayCell.Kind) -> Color {
        switch kind {
        case .context:
            return NeoCodeTheme.diffContextText
        case .added:
            return ToolCallDiffPalette.addedText
        case .removed:
            return ToolCallDiffPalette.removedText
        }
    }
}

private enum ToolCallDiffPalette {
    static let addedBackground = Color(.sRGB, red: 0.18, green: 0.63, blue: 0.33, opacity: 0.22)
    static let addedText = Color(.sRGB, red: 0.35, green: 0.85, blue: 0.49, opacity: 0.96)
    static let hunkBackground = Color(.sRGB, red: 0.45, green: 0.49, blue: 0.55, opacity: 0.24)
    static let hunkText = Color(.sRGB, red: 0.92, green: 0.94, blue: 0.97, opacity: 0.96)
    static let removedBackground = Color(.sRGB, red: 0.81, green: 0.25, blue: 0.25, opacity: 0.20)
    static let removedText = Color(.sRGB, red: 0.96, green: 0.46, blue: 0.46, opacity: 0.96)
}

private struct DiffDisplayRow: Identifiable {
    enum Content {
        case split(left: DiffDisplayCell?, right: DiffDisplayCell?)
        case note(String)
    }

    let id: String
    let content: Content
}

private struct DiffDisplayCell {
    enum Kind {
        case context
        case added
        case removed
    }

    let lineNumber: Int?
    let text: String
    let kind: Kind
}

private enum DiffDisplayRowBuilder {
    static func makeRows(for file: DiffFile) -> [DiffDisplayRow] {
        guard !file.hunks.isEmpty else {
            return [DiffDisplayRow(id: "\(file.id):empty", content: .note(emptyStateText(for: file.change)))]
        }

        var rows: [DiffDisplayRow] = []

        for (hunkIndex, hunk) in file.hunks.enumerated() {
            if !hunk.header.isEmpty {
                rows.append(DiffDisplayRow(id: "\(file.id):header:\(hunkIndex)", content: .note(hunk.header)))
            }

            rows.append(contentsOf: makeRows(for: hunk, fileID: file.id, hunkIndex: hunkIndex))
        }

        return rows
    }

    private static func makeRows(for hunk: DiffHunk, fileID: String, hunkIndex: Int) -> [DiffDisplayRow] {
        var rows: [DiffDisplayRow] = []
        var oldLine = hunk.oldRange?.start
        var newLine = hunk.newRange?.start
        var pendingRemoved: [DiffDisplayCell] = []
        var pendingAdded: [DiffDisplayCell] = []

        func flushPending() {
            let pairCount = max(pendingRemoved.count, pendingAdded.count)
            guard pairCount > 0 else { return }

            for index in 0..<pairCount {
                let left = index < pendingRemoved.count ? pendingRemoved[index] : nil
                let right = index < pendingAdded.count ? pendingAdded[index] : nil
                rows.append(
                    DiffDisplayRow(
                        id: "\(fileID):\(hunkIndex):pair:\(rows.count)",
                        content: .split(left: left, right: right)
                    )
                )
            }

            pendingRemoved.removeAll(keepingCapacity: true)
            pendingAdded.removeAll(keepingCapacity: true)
        }

        for line in hunk.lines {
            switch line.kind {
            case .context:
                flushPending()
                rows.append(
                    DiffDisplayRow(
                        id: "\(fileID):\(hunkIndex):context:\(rows.count)",
                        content: .split(
                            left: DiffDisplayCell(lineNumber: oldLine, text: line.text, kind: .context),
                            right: DiffDisplayCell(lineNumber: newLine, text: line.text, kind: .context)
                        )
                    )
                )
                oldLine = oldLine.map { $0 + 1 }
                newLine = newLine.map { $0 + 1 }
            case .removed:
                pendingRemoved.append(DiffDisplayCell(lineNumber: oldLine, text: line.text, kind: .removed))
                oldLine = oldLine.map { $0 + 1 }
            case .added:
                pendingAdded.append(DiffDisplayCell(lineNumber: newLine, text: line.text, kind: .added))
                newLine = newLine.map { $0 + 1 }
            case .note:
                flushPending()
                rows.append(DiffDisplayRow(id: "\(fileID):\(hunkIndex):note:\(rows.count)", content: .note(line.text)))
            }
        }

        flushPending()
        return rows
    }

    private static func emptyStateText(for change: DiffFile.ChangeKind) -> String {
        diffEmptyStateText(for: change)
    }
}

private enum DiffChangeRowBuilder {
    static func makeRows(for file: DiffFile) -> [DiffChangeRow] {
        let rows = file.hunks.enumerated().flatMap { hunkIndex, hunk in
            hunk.lines.enumerated().compactMap { lineIndex, line in
                switch line.kind {
                case .added:
                    return DiffChangeRow(
                        id: "\(file.id):change:\(hunkIndex):\(lineIndex)",
                        content: .line(prefix: "+", text: line.text, kind: .added)
                    )
                case .removed:
                    return DiffChangeRow(
                        id: "\(file.id):change:\(hunkIndex):\(lineIndex)",
                        content: .line(prefix: "-", text: line.text, kind: .removed)
                    )
                case .context, .note:
                    return nil
                }
            }
        }

        if rows.isEmpty {
            return [DiffChangeRow(id: "\(file.id):empty", content: .note(diffEmptyStateText(for: file.change)))]
        }

        return rows
    }
}

private func diffEmptyStateText(for change: DiffFile.ChangeKind) -> String {
    switch change {
    case .added:
        return "New file created."
    case .deleted:
        return "File removed."
    case .renamed:
        return "File renamed with no inline hunk details."
    case .copied:
        return "File copied with no inline hunk details."
    case .modified, .unknown:
        return "No added or removed lines."
    }
}
