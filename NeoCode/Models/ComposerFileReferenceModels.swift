import Foundation

struct ComposerPromptFileReference: Equatable, Hashable, Sendable {
    struct SourceText: Equatable, Hashable, Sendable {
        let value: String
        let start: Int
        let end: Int
    }

    let relativePath: String
    let absolutePath: String
    let sourceText: SourceText

    var requestURL: String {
        URL(fileURLWithPath: absolutePath).absoluteString
    }
}

enum ComposerPromptFileReferenceBuilder {
    private struct MentionMatch {
        let path: String
        let sourceText: ComposerPromptFileReference.SourceText
    }

    nonisolated static func build(text: String, projectPath: String, candidatePaths: some Sequence<String>) -> [ComposerPromptFileReference] {
        var referencesByPath: [String: ComposerPromptFileReference] = [:]

        for path in candidatePaths {
            guard let sourceText = lastMentionSourceText(for: path, in: text) else { continue }

            let absolutePath = URL(fileURLWithPath: projectPath, isDirectory: true)
                .appendingPathComponent(path)
                .path

            referencesByPath[path] = ComposerPromptFileReference(
                relativePath: path,
                absolutePath: absolutePath,
                sourceText: sourceText
            )
        }

        return referencesByPath.values.sorted {
            if $0.sourceText.start != $1.sourceText.start {
                return $0.sourceText.start < $1.sourceText.start
            }
            return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    nonisolated static func mentionedPaths(in text: String, candidatePaths: some Sequence<String>) -> Set<String> {
        Set(candidatePaths.filter { lastMentionSourceText(for: $0, in: text) != nil })
    }

    nonisolated static func mentionSourceTexts(in text: String) -> [ComposerPromptFileReference.SourceText] {
        mentionMatches(in: text).map(\.sourceText)
    }

    nonisolated static func references(projectPath: String, matches: [(path: String, sourceText: ComposerPromptFileReference.SourceText)]) -> [ComposerPromptFileReference] {
        var referencesByPath: [String: ComposerPromptFileReference] = [:]

        for match in matches {
            let absolutePath = URL(fileURLWithPath: projectPath, isDirectory: true)
                .appendingPathComponent(match.path)
                .path

            referencesByPath[match.path] = ComposerPromptFileReference(
                relativePath: match.path,
                absolutePath: absolutePath,
                sourceText: match.sourceText
            )
        }

        return referencesByPath.values.sorted {
            if $0.sourceText.start != $1.sourceText.start {
                return $0.sourceText.start < $1.sourceText.start
            }
            return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    nonisolated static func matchedPaths(in text: String) -> [(path: String, sourceText: ComposerPromptFileReference.SourceText)] {
        mentionMatches(in: text).map { ($0.path, $0.sourceText) }
    }

    private nonisolated static func lastMentionSourceText(for path: String, in text: String) -> ComposerPromptFileReference.SourceText? {
        let token = "@\(path)"
        var searchStart = text.startIndex
        var match: Range<String.Index>?

        while let range = text.range(of: token, range: searchStart..<text.endIndex) {
            match = range
            searchStart = range.upperBound
        }

        guard let match else { return nil }

        let start = text.distance(from: text.startIndex, to: match.lowerBound)
        let end = text.distance(from: text.startIndex, to: match.upperBound)
        return ComposerPromptFileReference.SourceText(value: token, start: start, end: end)
    }

    private nonisolated static func mentionMatches(in text: String) -> [MentionMatch] {
        let trailingPunctuation = CharacterSet(charactersIn: ",.;:!?)]}")
        var matches: [MentionMatch] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "@" else {
                index = text.index(after: index)
                continue
            }

            let atIndex = index
            if atIndex > text.startIndex {
                let previousIndex = text.index(before: atIndex)
                guard text[previousIndex].isWhitespace else {
                    index = text.index(after: index)
                    continue
                }
            }

            var endIndex = text.index(after: atIndex)
            while endIndex < text.endIndex, !text[endIndex].isWhitespace {
                endIndex = text.index(after: endIndex)
            }

            var tokenRange = atIndex..<endIndex
            while tokenRange.upperBound > tokenRange.lowerBound {
                let previousIndex = text.index(before: tokenRange.upperBound)
                let scalar = text[previousIndex].unicodeScalars.first
                guard let scalar, trailingPunctuation.contains(scalar) else { break }
                tokenRange = tokenRange.lowerBound..<previousIndex
            }

            guard text.distance(from: tokenRange.lowerBound, to: tokenRange.upperBound) > 1 else {
                index = endIndex
                continue
            }

            let value = String(text[tokenRange])
            let path = String(value.dropFirst())
            guard !path.isEmpty else {
                index = endIndex
                continue
            }

            matches.append(
                MentionMatch(
                    path: path,
                    sourceText: ComposerPromptFileReference.SourceText(
                        value: value,
                        start: text.distance(from: text.startIndex, to: tokenRange.lowerBound),
                        end: text.distance(from: text.startIndex, to: tokenRange.upperBound)
                    )
                )
            )

            index = endIndex
        }

        return matches
    }
}

enum ComposerPromptFileReferenceDeletion {
    nonisolated static func backwardDeleteRange(
        in text: String,
        sourceTexts: [ComposerPromptFileReference.SourceText],
        cursorLocation: Int
    ) -> NSRange? {
        let textLength = (text as NSString).length
        guard cursorLocation > 0, cursorLocation <= textLength else { return nil }

        let mentionRanges = sourceTexts
            .map { NSRange(location: $0.start, length: $0.end - $0.start) }
            .filter { $0.location >= 0 && NSMaxRange($0) <= textLength }

        for range in mentionRanges {
            if cursorLocation > range.location && cursorLocation <= NSMaxRange(range) {
                return range
            }
        }

        let nsText = text as NSString
        let previousCharacterRange = NSRange(location: cursorLocation - 1, length: 1)
        let previousCharacter = nsText.substring(with: previousCharacterRange)

        guard previousCharacter == " " else { return nil }

        for range in mentionRanges where NSMaxRange(range) == cursorLocation - 1 {
            return NSRange(location: range.location, length: range.length + 1)
        }

        return nil
    }
}
