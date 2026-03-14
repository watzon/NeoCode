import AppKit
import Foundation
import UniformTypeIdentifiers

struct WorkspaceTool: Identifiable, Hashable {
    enum Kind: Hashable {
        case editor
        case terminal
        case fileManager
    }

    let id: String
    let label: String
    let kind: Kind
    let applicationURL: URL?
    let fallbackSystemImage: String
}

struct WorkspaceToolService {
    private let fileManager = FileManager.default

    func discoveredTools() -> [WorkspaceTool] {
        let queryResults = QueryResults(
            textEditors: queryApplicationsOpeningText(),
            commandHandlers: queryApplicationsOpeningCommand(),
            folderHandlers: queryApplicationsOpeningFolders()
        )
        let installedApps = installedApplicationMetadata(using: queryResults)
        let editors = discoveredEditors(from: installedApps)
        let terminals = discoveredTerminals(from: installedApps)
        let fileManagers = discoveredFileManagers(from: installedApps)

        return deduplicated(editors + terminals + fileManagers)
    }

    func isAvailable(_ tool: WorkspaceTool) -> Bool {
        tool.kind == .fileManager || tool.applicationURL != nil
    }

    func icon(for tool: WorkspaceTool) -> NSImage? {
        guard let applicationURL = tool.applicationURL,
              let iconURL = applicationIconURL(for: applicationURL),
              let image = NSImage(contentsOf: iconURL)
        else {
            return nil
        }

        image.size = NSSize(width: 32, height: 32)
        image.isTemplate = false
        return image
    }

    func defaultToolID(from tools: [WorkspaceTool]) -> String? {
        let preferredBundleIDs = [
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "dev.zed.Zed",
            "com.apple.dt.Xcode",
            "com.apple.finder"
        ]

        for bundleID in preferredBundleIDs {
            if let match = tools.first(where: { metadataBundleIdentifier(for: $0) == bundleID }) {
                return match.id
            }
        }

        return tools.first(where: { $0.kind == .editor })?.id ?? tools.first?.id
    }

    func openProject(at projectPath: String, with tool: WorkspaceTool) {
        let projectURL = URL(fileURLWithPath: projectPath)

        if tool.kind == .fileManager {
            NSWorkspace.shared.activateFileViewerSelecting([projectURL])
            return
        }

        guard let applicationURL = tool.applicationURL else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([projectURL], withApplicationAt: applicationURL, configuration: configuration)
    }

    private func installedApplicationMetadata(using queryResults: QueryResults) -> [InstalledApplication] {
        let allApps = queryResults.textEditors
            .union(queryResults.commandHandlers)
            .union(queryResults.folderHandlers)

        return allApps.compactMap { installedApplication(for: $0, queryResults: queryResults) }
    }

    private func discoveredEditors(from apps: [InstalledApplication]) -> [WorkspaceTool] {
        apps
            .filter { $0.supportsTextEditing }
            .filter { $0.isLikelyEditor }
            .sorted(by: appSort)
            .map {
                WorkspaceTool(
                    id: toolIdentifier(for: $0),
                    label: $0.displayName,
                    kind: .editor,
                    applicationURL: $0.url,
                    fallbackSystemImage: "chevron.left.forwardslash.chevron.right"
                )
            }
    }

    private func discoveredTerminals(from apps: [InstalledApplication]) -> [WorkspaceTool] {
        apps
            .filter { $0.supportsCommandExecution }
            .filter { $0.isLikelyTerminal }
            .sorted(by: appSort)
            .map {
                WorkspaceTool(
                    id: toolIdentifier(for: $0),
                    label: $0.displayName,
                    kind: .terminal,
                    applicationURL: $0.url,
                    fallbackSystemImage: "terminal"
                )
            }
    }

    private func discoveredFileManagers(from apps: [InstalledApplication]) -> [WorkspaceTool] {
        if let finder = apps.first(where: { $0.bundleIdentifier == "com.apple.finder" }) {
            return [
                WorkspaceTool(
                    id: toolIdentifier(for: finder),
                    label: finder.displayName,
                    kind: .fileManager,
                    applicationURL: finder.url,
                    fallbackSystemImage: "folder"
                )
            ]
        }

        if let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") {
            return [
                WorkspaceTool(
                    id: "com.apple.finder",
                    label: "Finder",
                    kind: .fileManager,
                    applicationURL: finderURL,
                    fallbackSystemImage: "folder"
                )
            ]
        }

        return []
    }

    private func queryApplicationsOpeningText() -> Set<URL> {
        let sampleURL = fileManager.temporaryDirectory.appendingPathComponent("neocode-sample.txt")
        try? "NeoCode".write(to: sampleURL, atomically: true, encoding: .utf8)
        return Set(NSWorkspace.shared.urlsForApplications(toOpen: sampleURL))
    }

    private func queryApplicationsOpeningCommand() -> Set<URL> {
        let sampleURL = fileManager.temporaryDirectory.appendingPathComponent("neocode-sample.command")
        try? "#!/bin/zsh\necho NeoCode\n".write(to: sampleURL, atomically: true, encoding: .utf8)
        return Set(NSWorkspace.shared.urlsForApplications(toOpen: sampleURL))
    }

    private func queryApplicationsOpeningFolders() -> Set<URL> {
        Set(NSWorkspace.shared.urlsForApplications(toOpen: fileManager.homeDirectoryForCurrentUser))
    }

    private func installedApplication(for url: URL, queryResults: QueryResults) -> InstalledApplication? {
        guard let bundle = Bundle(url: url) else { return nil }

        let info = bundle.infoDictionary ?? [:]
        let documentTypes = (info["CFBundleDocumentTypes"] as? [[String: Any]]) ?? []
        let contentTypeIdentifiers = documentTypes
            .flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] }

        let typeSet = Set(contentTypeIdentifiers.compactMap(UTType.init))
        let bundleIdentifier = bundle.bundleIdentifier
        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let category = info["LSApplicationCategoryType"] as? String

        return InstalledApplication(
            url: url,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            category: category,
            handledTypes: typeSet,
            isTextEditorCandidate: queryResults.textEditors.contains(url),
            isCommandHandlerCandidate: queryResults.commandHandlers.contains(url),
            isFolderHandlerCandidate: queryResults.folderHandlers.contains(url)
        )
    }

    private func toolIdentifier(for app: InstalledApplication) -> String {
        app.bundleIdentifier ?? app.url.path
    }

    private func metadataBundleIdentifier(for tool: WorkspaceTool) -> String? {
        guard let applicationURL = tool.applicationURL else { return nil }
        return Bundle(url: applicationURL)?.bundleIdentifier
    }

    private func deduplicated(_ tools: [WorkspaceTool]) -> [WorkspaceTool] {
        var seen = Set<String>()
        var result: [WorkspaceTool] = []

        for tool in tools where seen.insert(tool.id).inserted {
            result.append(tool)
        }

        return result
    }

    private func appSort(_ lhs: InstalledApplication, _ rhs: InstalledApplication) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func applicationIconURL(for applicationURL: URL) -> URL? {
        guard let bundle = Bundle(url: applicationURL) else { return nil }

        let resourcesURL = applicationURL.appendingPathComponent("Contents/Resources", isDirectory: true)

        if let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let iconURL = iconURL(named: iconName, in: resourcesURL) {
            return iconURL
        }

        if let iconName = bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
           let iconURL = iconURL(named: iconName, in: resourcesURL) {
            return iconURL
        }

        return firstIconURL(in: resourcesURL)
    }

    private func iconURL(named iconName: String, in resourcesURL: URL) -> URL? {
        let normalizedName = (iconName as NSString).deletingPathExtension
        let exactURL = resourcesURL.appendingPathComponent(iconName)
        if fileManager.fileExists(atPath: exactURL.path) {
            return exactURL
        }

        let icnsURL = resourcesURL.appendingPathComponent(normalizedName).appendingPathExtension("icns")
        if fileManager.fileExists(atPath: icnsURL.path) {
            return icnsURL
        }

        let pngURL = resourcesURL.appendingPathComponent(normalizedName).appendingPathExtension("png")
        if fileManager.fileExists(atPath: pngURL.path) {
            return pngURL
        }

        return nil
    }

    private func firstIconURL(in resourcesURL: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: resourcesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            switch url.pathExtension.lowercased() {
            case "icns", "png":
                return url
            default:
                continue
            }
        }

        return nil
    }
}

private struct QueryResults {
    let textEditors: Set<URL>
    let commandHandlers: Set<URL>
    let folderHandlers: Set<URL>
}

private struct InstalledApplication {
    let url: URL
    let bundleIdentifier: String?
    let displayName: String
    let category: String?
    let handledTypes: Set<UTType>
    let isTextEditorCandidate: Bool
    let isCommandHandlerCandidate: Bool
    let isFolderHandlerCandidate: Bool

    var handlesPlainText: Bool {
        handledTypes.contains(where: { $0.conforms(to: .plainText) || $0.conforms(to: .text) || $0.conforms(to: .sourceCode) })
    }

    var handlesCommandScript: Bool {
        handledTypes.contains(where: {
            $0.identifier == "public.shell-script"
        })
    }

    var handlesUnixExecutable: Bool {
        handledTypes.contains(where: { $0.identifier == "public.unix-executable" })
    }

    var handlesFolder: Bool {
        handledTypes.contains(where: {
            $0.identifier == "public.folder" || $0.identifier == "public.directory" || $0.conforms(to: .folder)
        })
    }

    var isDeveloperTool: Bool {
        category == "public.app-category.developer-tools"
    }

    var normalizedName: String {
        displayName.lowercased()
    }

    var normalizedBundleIdentifier: String {
        bundleIdentifier?.lowercased() ?? ""
    }

    var supportsTextEditing: Bool {
        isTextEditorCandidate || handlesPlainText
    }

    var supportsCommandExecution: Bool {
        isCommandHandlerCandidate || handlesCommandScript || handlesUnixExecutable
    }

    var isLikelyEditor: Bool {
        guard supportsTextEditing else { return false }
        guard !isLikelyTerminal else { return false }
        guard !isKnownNonEditor else { return false }

        return isDeveloperTool || isKnownEditor || isFolderHandlerCandidate
    }

    var isLikelyTerminal: Bool {
        let tokens = ["terminal", "iterm", "ghostty", "warp", "wezterm", "kitty", "alacritty", "hyper"]
        return tokens.contains(where: { normalizedName.contains($0) || normalizedBundleIdentifier.contains($0) })
            || (isDeveloperTool && supportsCommandExecution && !supportsTextEditing)
    }

    var isKnownEditor: Bool {
        let tokens = [
            "code", "cursor", "zed", "xcode", "idea", "fleet", "sublime", "nova", "textmate",
            "android studio", "trae", "kiro", "windsurf", "antigravity"
        ]
        return tokens.contains(where: { normalizedName.contains($0) || normalizedBundleIdentifier.contains($0.replacingOccurrences(of: " ", with: "")) })
    }

    var isKnownNonEditor: Bool {
        let tokens = [
            "bear", "notes", "photomator", "vlc", "iconjar", "safari", "chrome", "opera", "duckduckgo",
            "books", "quicktime", "preview", "ulysses", "numbers"
        ]
        return tokens.contains(where: { normalizedName.contains($0) || normalizedBundleIdentifier.contains($0) })
    }
}
