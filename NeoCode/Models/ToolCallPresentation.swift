import Foundation

struct ToolCallPresentation: Hashable {
    struct Item: Identifiable, Hashable {
        enum Content: Hashable {
            case text(String)
            case diff(DiffFile)
        }

        let id: String
        let title: String
        let subtitle: String?
        let content: Content
        let defaultExpanded: Bool
    }

    let items: [Item]

    init(toolCall: ChatMessage.ToolCall) {
        items = ToolCallPresentationBuilder.makeItems(for: toolCall)
    }
}

private enum ToolCallPresentationBuilder {
    static func makeItems(for toolCall: ChatMessage.ToolCall) -> [ToolCallPresentation.Item] {
        if let bundle = diffBundle(for: toolCall), !bundle.files.isEmpty {
            return bundle.files.map { file in
                ToolCallPresentation.Item(
                    id: "\(toolCall.name):\(file.id)",
                    title: diffTitle(for: file),
                    subtitle: diffSubtitle(for: file),
                    content: .diff(file),
                    defaultExpanded: false
                )
            }
        }

        return [
            ToolCallPresentation.Item(
                id: "\(toolCall.name):detail",
                title: toolCall.name,
                subtitle: nil,
                content: .text(fallbackText(for: toolCall)),
                defaultExpanded: toolCall.status == .pending || toolCall.status == .running
            )
        ]
    }

    private static func fallbackText(for toolCall: ChatMessage.ToolCall) -> String {
        if let detail = toolCall.detail, !detail.isEmpty {
            return detail
        }
        if toolCall.status == .error, let error = toolCall.error, !error.isEmpty {
            return error
        }
        if let output = toolCall.output?.displayString, !output.isEmpty {
            return output
        }
        if let input = toolCall.input?.displayString, !input.isEmpty {
            return input
        }
        return ""
    }

    private static func diffBundle(for toolCall: ChatMessage.ToolCall) -> DiffBundle? {
        if let bundle = ApplyPatchDiffParser.parse(toolCall: toolCall) {
            return bundle
        }

        for candidate in unifiedDiffCandidates(for: toolCall) {
            if let bundle = UnifiedDiffParser.parse(candidate) {
                return bundle
            }
        }

        return nil
    }

    private static func unifiedDiffCandidates(for toolCall: ChatMessage.ToolCall) -> [String] {
        var candidates: [String] = []
        candidates.append(contentsOf: toolCall.input?.diffStringCandidates ?? [])
        candidates.append(contentsOf: toolCall.output?.diffStringCandidates ?? [])

        if let detail = toolCall.detail, !detail.isEmpty {
            candidates.append(detail)
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return false }
            return true
        }
    }

    private static func diffTitle(for file: DiffFile) -> String {
        switch file.change {
        case .added:
            return "Added \(file.displayPath)"
        case .deleted:
            return "Deleted \(file.displayPath)"
        case .renamed:
            return "Renamed \(file.displayPath)"
        case .copied:
            return "Copied \(file.displayPath)"
        case .modified, .unknown:
            return "Patched \(file.displayPath)"
        }
    }

    private static func diffSubtitle(for file: DiffFile) -> String? {
        guard let oldPath = file.oldPath,
              let newPath = file.newPath,
              oldPath != newPath
        else {
            return nil
        }

        return "from \(oldPath)"
    }
}

private enum ApplyPatchDiffParser {
    static func parse(toolCall: ChatMessage.ToolCall) -> DiffBundle? {
        guard toolCall.name.caseInsensitiveCompare("apply_patch") == .orderedSame,
              let patchText = toolCall.input?.stringValue(forKey: "patchText")
        else {
            return nil
        }

        return parse(patchText: patchText)
    }

    private static func parse(patchText: String) -> DiffBundle? {
        let lines = normalizedLines(from: patchText)
        guard lines.first == "*** Begin Patch" else { return nil }

        var files: [DiffFile] = []
        var index = 1

        while index < lines.count {
            let line = lines[index]
            if line == "*** End Patch" {
                break
            }

            if let path = line.dropPrefix("*** Add File: ") {
                index += 1
                let body = consumeFileBlock(from: lines, index: &index)
                let hunkLines = body.map { bodyLine in
                    DiffLine(kind: .added, text: bodyLine.hasPrefix("+") ? String(bodyLine.dropFirst()) : bodyLine)
                }
                files.append(
                    DiffFile(
                        id: "add:\(path)",
                        oldPath: nil,
                        newPath: path,
                        change: .added,
                        hunks: [
                            DiffHunk(
                                header: "Added file",
                                oldRange: nil,
                                newRange: DiffLineRange(start: 1, count: hunkLines.count),
                                lines: hunkLines
                            )
                        ],
                        isBinary: false
                    )
                )
                continue
            }

            if let path = line.dropPrefix("*** Delete File: ") {
                files.append(
                    DiffFile(
                        id: "delete:\(path)",
                        oldPath: path,
                        newPath: nil,
                        change: .deleted,
                        hunks: [],
                        isBinary: false
                    )
                )
                index += 1
                continue
            }

            if let path = line.dropPrefix("*** Update File: ") {
                index += 1

                var movedTo: String?
                if index < lines.count, let destination = lines[index].dropPrefix("*** Move to: ") {
                    movedTo = destination
                    index += 1
                }

                let body = consumeFileBlock(from: lines, index: &index)
                let resolvedPath = movedTo ?? path
                files.append(
                    DiffFile(
                        id: "update:\(path)->\(movedTo ?? path)",
                        oldPath: path,
                        newPath: movedTo ?? path,
                        change: movedTo == nil ? .modified : .renamed,
                        hunks: inferApplyPatchRanges(in: parseApplyPatchHunks(body), filePath: resolvedPath),
                        isBinary: false
                    )
                )
                continue
            }

            index += 1
        }

        guard !files.isEmpty else { return nil }
        return DiffBundle(sourceFormat: .applyPatch, files: files)
    }

    private static func consumeFileBlock(from lines: [String], index: inout Int) -> [String] {
        let start = index
        while index < lines.count {
            let line = lines[index]
            if line == "*** End Patch"
                || line.hasPrefix("*** Add File: ")
                || line.hasPrefix("*** Delete File: ")
                || line.hasPrefix("*** Update File: ") {
                break
            }
            index += 1
        }

        return Array(lines[start..<index])
    }

    private static func parseApplyPatchHunks(_ lines: [String]) -> [DiffHunk] {
        guard !lines.isEmpty else { return [] }

        var hunks: [DiffHunk] = []
        var currentHeader = "Changes"
        var currentLines: [DiffLine] = []

        func flush() {
            guard !currentLines.isEmpty else { return }
            hunks.append(DiffHunk(header: currentHeader, oldRange: nil, newRange: nil, lines: currentLines))
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            if line.hasPrefix("@@") {
                flush()
                currentHeader = line
                continue
            }

            if line.hasPrefix("+") {
                currentLines.append(DiffLine(kind: .added, text: String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                currentLines.append(DiffLine(kind: .removed, text: String(line.dropFirst())))
            } else if line.hasPrefix(" ") {
                currentLines.append(DiffLine(kind: .context, text: String(line.dropFirst())))
            } else {
                currentLines.append(DiffLine(kind: .note, text: line))
            }
        }

        flush()
        return hunks
    }

    private static func inferApplyPatchRanges(in hunks: [DiffHunk], filePath: String?) -> [DiffHunk] {
        guard let filePath,
              let fileLines = readFileLines(at: filePath),
              !fileLines.isEmpty
        else {
            return hunks
        }

        var inferredHunks: [DiffHunk] = []
        var searchStartIndex = 0
        var cumulativeDelta = 0

        for hunk in hunks {
            let oldCount = hunk.lines.reduce(into: 0) { partialResult, line in
                if line.kind == .context || line.kind == .removed {
                    partialResult += 1
                }
            }
            let newCount = hunk.lines.reduce(into: 0) { partialResult, line in
                if line.kind == .context || line.kind == .added {
                    partialResult += 1
                }
            }
            let newSideLines = hunk.lines.compactMap { line -> String? in
                line.kind == .context || line.kind == .added ? line.text : nil
            }

            let newStartIndex = findLineSequence(newSideLines, in: fileLines, startingAt: searchStartIndex)
                ?? findLineSequence(newSideLines, in: fileLines, startingAt: 0)

            if let newStartIndex {
                let newStart = newStartIndex + 1
                let oldStart = max(1, newStart - cumulativeDelta)
                inferredHunks.append(
                    DiffHunk(
                        header: hunk.header,
                        oldRange: oldCount > 0 ? DiffLineRange(start: oldStart, count: oldCount) : nil,
                        newRange: newCount > 0 ? DiffLineRange(start: newStart, count: newCount) : nil,
                        lines: hunk.lines
                    )
                )
                searchStartIndex = newStartIndex + max(newCount, 1)
            } else {
                inferredHunks.append(hunk)
            }

            cumulativeDelta += newCount - oldCount
        }

        return inferredHunks
    }
}

private enum UnifiedDiffParser {
    static func parse(_ rawText: String) -> DiffBundle? {
        let lines = normalizedLines(from: rawText)
        guard looksLikeUnifiedDiff(lines) else {
            return nil
        }

        var files: [DiffFile] = []
        var pendingHeaderPaths: (oldPath: String?, newPath: String?)?
        var currentFile = FileBuilder()
        var currentHunkHeader: String?
        var currentHunkOldRange: DiffLineRange?
        var currentHunkNewRange: DiffLineRange?
        var currentHunkLines: [DiffLine] = []

        func flushHunk() {
            guard let header = currentHunkHeader else { return }
            currentFile.hunks.append(
                DiffHunk(
                    header: header,
                    oldRange: currentHunkOldRange,
                    newRange: currentHunkNewRange,
                    lines: currentHunkLines
                )
            )
            currentHunkHeader = nil
            currentHunkOldRange = nil
            currentHunkNewRange = nil
            currentHunkLines.removeAll(keepingCapacity: true)
        }

        func flushFile() {
            flushHunk()
            if let file = currentFile.build(fallbackPaths: pendingHeaderPaths) {
                files.append(file)
            }
            pendingHeaderPaths = nil
            currentFile = FileBuilder()
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                flushFile()
                pendingHeaderPaths = parseGitPaths(from: line)
                continue
            }

            if let path = line.dropPrefix("rename from ") {
                currentFile.oldPath = path
                currentFile.change = .renamed
                continue
            }

            if let path = line.dropPrefix("rename to ") {
                currentFile.newPath = path
                currentFile.change = .renamed
                continue
            }

            if line.hasPrefix("new file mode ") {
                currentFile.change = .added
                continue
            }

            if line.hasPrefix("deleted file mode ") {
                currentFile.change = .deleted
                continue
            }

            if let path = line.dropPrefix("--- ") {
                currentFile.oldPath = normalizeDiffPath(path)
                continue
            }

            if let path = line.dropPrefix("+++ ") {
                currentFile.newPath = normalizeDiffPath(path)
                continue
            }

            if line.hasPrefix("@@") {
                flushHunk()
                currentHunkHeader = line
                let ranges = parseUnifiedRanges(from: line)
                currentHunkOldRange = ranges?.old
                currentHunkNewRange = ranges?.new
                continue
            }

            if currentHunkHeader != nil {
                if line.hasPrefix("+") {
                    currentHunkLines.append(DiffLine(kind: .added, text: String(line.dropFirst())))
                } else if line.hasPrefix("-") {
                    currentHunkLines.append(DiffLine(kind: .removed, text: String(line.dropFirst())))
                } else if line.hasPrefix(" ") {
                    currentHunkLines.append(DiffLine(kind: .context, text: String(line.dropFirst())))
                } else {
                    currentHunkLines.append(DiffLine(kind: .note, text: line))
                }
            }
        }

        flushFile()
        guard !files.isEmpty else { return nil }
        return DiffBundle(sourceFormat: .unified, files: files)
    }

    private static func looksLikeUnifiedDiff(_ lines: [String]) -> Bool {
        if lines.contains(where: { $0.hasPrefix("diff --git ") }) {
            return true
        }

        let oldHeaderIndex = lines.firstIndex { line in
            guard let path = line.dropPrefix("--- ") else { return false }
            return path == "/dev/null" || path.hasPrefix("a/") || path.hasPrefix("b/")
        }
        let newHeaderIndex = lines.firstIndex { line in
            guard let path = line.dropPrefix("+++ ") else { return false }
            return path == "/dev/null" || path.hasPrefix("a/") || path.hasPrefix("b/")
        }
        let hunkIndex = lines.firstIndex(where: { $0.hasPrefix("@@") })

        guard let oldHeaderIndex, let newHeaderIndex, let hunkIndex else {
            return false
        }

        return oldHeaderIndex < newHeaderIndex && newHeaderIndex < hunkIndex
    }

    private static func parseGitPaths(from line: String) -> (oldPath: String?, newPath: String?)? {
        let components = line.split(separator: " ", omittingEmptySubsequences: true)
        guard components.count >= 4 else { return nil }
        return (normalizeDiffPath(String(components[2])), normalizeDiffPath(String(components[3])))
    }

    private static func parseUnifiedRanges(from header: String) -> (old: DiffLineRange, new: DiffLineRange)? {
        guard let match = header.range(of: #"-([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))?"#, options: .regularExpression) else {
            return nil
        }

        let payload = String(header[match])
        let trimmed = payload.dropFirst()
        let parts = trimmed.split(separator: " ")
        guard parts.count == 2 else { return nil }

        func parseRange(_ token: Substring) -> DiffLineRange? {
            let values = token.split(separator: ",", omittingEmptySubsequences: false)
            guard let start = Int(values[0]) else { return nil }
            let count = values.count > 1 ? Int(values[1]) ?? 1 : 1
            return DiffLineRange(start: start, count: count)
        }

        guard let oldRange = parseRange(parts[0]), let newRange = parseRange(parts[1].dropFirst()) else {
            return nil
        }

        return (oldRange, newRange)
    }
}

private struct FileBuilder {
    var oldPath: String?
    var newPath: String?
    var change: DiffFile.ChangeKind = .modified
    var hunks: [DiffHunk] = []

    func build(fallbackPaths: (oldPath: String?, newPath: String?)?) -> DiffFile? {
        let resolvedOldPath = oldPath ?? fallbackPaths?.oldPath
        let resolvedNewPath = newPath ?? fallbackPaths?.newPath
        guard resolvedOldPath != nil || resolvedNewPath != nil || !hunks.isEmpty else { return nil }

        let resolvedChange: DiffFile.ChangeKind
        if change != .modified {
            resolvedChange = change
        } else if resolvedOldPath == nil {
            resolvedChange = .added
        } else if resolvedNewPath == nil {
            resolvedChange = .deleted
        } else if resolvedOldPath != resolvedNewPath {
            resolvedChange = .renamed
        } else {
            resolvedChange = .modified
        }

        let primaryPath = resolvedNewPath ?? resolvedOldPath ?? UUID().uuidString
        return DiffFile(
            id: "unified:\(primaryPath)",
            oldPath: resolvedOldPath,
            newPath: resolvedNewPath,
            change: resolvedChange,
            hunks: hunks,
            isBinary: false
        )
    }
}

private func normalizedLines(from text: String) -> [String] {
    text.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
}

private func readFileLines(at path: String) -> [String]? {
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
        return nil
    }

    return normalizedLines(from: contents)
}

private func findLineSequence(_ needle: [String], in haystack: [String], startingAt startIndex: Int) -> Int? {
    guard !needle.isEmpty, haystack.count >= needle.count else {
        return nil
    }

    let clampedStart = max(0, min(startIndex, haystack.count - needle.count))
    let lastStart = haystack.count - needle.count
    guard clampedStart <= lastStart else { return nil }

    for candidate in clampedStart...lastStart {
        if Array(haystack[candidate..<(candidate + needle.count)]) == needle {
            return candidate
        }
    }

    return nil
}

private func normalizeDiffPath(_ rawPath: String) -> String? {
    guard rawPath != "/dev/null" else { return nil }
    if rawPath.hasPrefix("a/") || rawPath.hasPrefix("b/") {
        return String(rawPath.dropFirst(2))
    }
    return rawPath
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

private extension JSONValue {
    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var object: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    func stringValue(forKey key: String) -> String? {
        object?[key]?.string
    }

    var diffStringCandidates: [String] {
        switch self {
        case .string(let value):
            return [value]
        case .array(let values):
            return values.flatMap(\.diffStringCandidates)
        case .object(let values):
            let preferredKeys = ["patchText", "diff", "patch", "stdout", "stderr", "text", "content"]
            let preferred = preferredKeys.compactMap { values[$0] }.flatMap(\.diffStringCandidates)
            if !preferred.isEmpty {
                return preferred
            }
            return values.values.flatMap(\.diffStringCandidates)
        case .number, .bool, .null:
            return []
        }
    }
}
