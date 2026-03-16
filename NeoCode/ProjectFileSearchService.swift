import Foundation

struct ProjectFileSearchResult: Identifiable, Hashable, Sendable {
    let relativePath: String
    let displayName: String
    let directoryPath: String?

    var id: String { relativePath }
}

actor ProjectFileSearchService {
    static let shared = ProjectFileSearchService()

    private struct IndexedFile: Hashable, Sendable {
        let relativePath: String
        let displayName: String
        let directoryPath: String?
        let normalizedRelativePath: String
        let normalizedDisplayName: String
    }

    private struct CachedIndex: Sendable {
        let createdAt: Date
        let files: [IndexedFile]
    }

    private var cachedIndexes: [String: CachedIndex] = [:]
    private let cacheLifetime: TimeInterval = 30
    private let resultLimit = 40
    private let skippedDirectoryNames: Set<String> = [
        "build",
        "DerivedData",
        "node_modules",
        ".build",
        ".swiftpm"
    ]

    func searchFiles(in projectPath: String, query: String) async -> [ProjectFileSearchResult] {
        let indexedFiles = fileIndex(for: projectPath)
        guard !Task.isCancelled else { return [] }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rankedFiles = rank(indexedFiles, for: normalizedQuery)

        return rankedFiles.prefix(resultLimit).map {
            ProjectFileSearchResult(
                relativePath: $0.relativePath,
                displayName: $0.displayName,
                directoryPath: $0.directoryPath
            )
        }
    }

    func resolveFileReferences(in projectPath: String, text: String) async -> [ComposerPromptFileReference] {
        let indexedFiles = fileIndex(for: projectPath)
        guard !Task.isCancelled else { return [] }

        let filesByNormalizedPath = Dictionary(
            indexedFiles.map { ($0.normalizedRelativePath, $0.relativePath) },
            uniquingKeysWith: { first, _ in first }
        )

        let matches: [(path: String, sourceText: ComposerPromptFileReference.SourceText)] = ComposerPromptFileReferenceBuilder.matchedPaths(in: text).compactMap { match in
            guard let resolvedPath = filesByNormalizedPath[match.path.lowercased()] else {
                return nil
            }

            return (path: resolvedPath, sourceText: match.sourceText)
        }

        return ComposerPromptFileReferenceBuilder.references(projectPath: projectPath, matches: matches)
    }

    private func fileIndex(for projectPath: String) -> [IndexedFile] {
        if let cached = cachedIndexes[projectPath],
           Date().timeIntervalSince(cached.createdAt) < cacheLifetime {
            return cached.files
        }

        let files = buildFileIndex(for: projectPath)
        cachedIndexes[projectPath] = CachedIndex(createdAt: Date(), files: files)
        return files
    }

    private func buildFileIndex(for projectPath: String) -> [IndexedFile] {
        let rootURL = URL(fileURLWithPath: projectPath, isDirectory: true)
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [IndexedFile] = []
        let pathPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"

        for case let fileURL as URL in enumerator {
            if Task.isCancelled {
                return []
            }

            let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys)
            let name = fileURL.lastPathComponent

            if resourceValues?.isDirectory == true {
                if skippedDirectoryNames.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard resourceValues?.isRegularFile == true else {
                continue
            }

            let fullPath = fileURL.path
            guard fullPath.hasPrefix(pathPrefix) else { continue }

            let relativePath = String(fullPath.dropFirst(pathPrefix.count))
                .replacingOccurrences(of: "\\", with: "/")
            let directoryPath = (relativePath as NSString).deletingLastPathComponent
            let normalizedDirectory = directoryPath == "." ? nil : directoryPath

            files.append(
                IndexedFile(
                    relativePath: relativePath,
                    displayName: fileURL.lastPathComponent,
                    directoryPath: normalizedDirectory,
                    normalizedRelativePath: relativePath.lowercased(),
                    normalizedDisplayName: fileURL.lastPathComponent.lowercased()
                )
            )
        }

        return files.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
        }
    }

    private func rank(_ files: [IndexedFile], for query: String) -> [IndexedFile] {
        guard !query.isEmpty else { return files }

        return files
            .compactMap { file -> (IndexedFile, Int)? in
                let score = score(for: file, query: query)
                return score.map { (file, $0) }
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 < rhs.1
                }

                if lhs.0.relativePath.count != rhs.0.relativePath.count {
                    return lhs.0.relativePath.count < rhs.0.relativePath.count
                }

                return lhs.0.relativePath.localizedCaseInsensitiveCompare(rhs.0.relativePath) == .orderedAscending
            }
            .map(\.0)
    }

    private func score(for file: IndexedFile, query: String) -> Int? {
        if file.normalizedRelativePath == query {
            return 0
        }

        if file.normalizedDisplayName == query {
            return 1
        }

        if file.normalizedDisplayName.hasPrefix(query) {
            return 10
        }

        if file.normalizedRelativePath.hasPrefix(query) {
            return 20
        }

        if let range = file.normalizedDisplayName.range(of: query) {
            return 30 + file.normalizedDisplayName.distance(from: file.normalizedDisplayName.startIndex, to: range.lowerBound)
        }

        if let range = file.normalizedRelativePath.range(of: query) {
            return 60 + file.normalizedRelativePath.distance(from: file.normalizedRelativePath.startIndex, to: range.lowerBound)
        }

        return nil
    }
}
