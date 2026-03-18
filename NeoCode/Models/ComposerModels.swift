import Foundation
import UniformTypeIdentifiers

enum ComposerAttachmentContent: Hashable {
    case file(path: String)
    case dataURL(String)
}

enum ComposerAttachmentImportItem: Hashable {
    case fileURL(URL)
    case imageData(Data, filename: String, mimeType: String)
}

struct ComposerAttachment: Identifiable, Hashable {
    let id: UUID
    var name: String
    var mimeType: String
    var content: ComposerAttachmentContent

    init(id: UUID = UUID(), name: String, mimeType: String, content: ComposerAttachmentContent) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.content = content
    }

    nonisolated var isImage: Bool {
        mimeType.lowercased().hasPrefix("image/")
    }

    nonisolated var requestURL: String {
        switch content {
        case .file(let path):
            return URL(fileURLWithPath: path).absoluteString
        case .dataURL(let value):
            return value
        }
    }

    nonisolated var deduplicationKey: String {
        requestURL
    }

    nonisolated var filePath: String? {
        guard case .file(let path) = content else { return nil }
        return path
    }

    static func makeAttachments(from urls: [URL]) async -> [ComposerAttachment] {
        await makeAttachments(from: urls.map(ComposerAttachmentImportItem.fileURL))
    }

    static func makeAttachments(from items: [ComposerAttachmentImportItem]) async -> [ComposerAttachment] {
        var attachments: [ComposerAttachment] = []
        for item in items {
            if let attachment = await makeAttachment(from: item) {
                attachments.append(attachment)
            }
        }
        return attachments
    }

    private static func makeAttachment(from item: ComposerAttachmentImportItem) async -> ComposerAttachment? {
        switch item {
        case .fileURL(let url):
            return await makeAttachment(from: url)
        case .imageData(let data, let filename, let mimeType):
            return makeImageAttachment(data: data, filename: filename, mimeType: mimeType)
        }
    }

    private static func makeAttachment(from url: URL) async -> ComposerAttachment? {
        let loaded = await Task.detached(priority: .userInitiated) { () -> (name: String, mimeType: String, content: ComposerAttachmentContent)? in
            let resolvedURL = url.standardizedFileURL.resolvingSymlinksInPath()
            guard resolvedURL.isFileURL else { return nil }

            let values = try? resolvedURL.resourceValues(forKeys: [.contentTypeKey, .nameKey, .isRegularFileKey])
            if values?.isRegularFile == false {
                return nil
            }

            let name = values?.name ?? resolvedURL.lastPathComponent
            let mimeType = values?.contentType?.preferredMIMEType
                ?? UTType(filenameExtension: resolvedURL.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"

            return (name, mimeType, .file(path: resolvedURL.path))
        }.value

        guard let loaded else { return nil }
        return ComposerAttachment(name: loaded.name, mimeType: loaded.mimeType, content: loaded.content)
    }

    private static func makeImageAttachment(data: Data, filename: String, mimeType: String) -> ComposerAttachment? {
        guard mimeType.lowercased().hasPrefix("image/") else { return nil }

        guard let fileURL = persistImportedImageData(data: data, filename: filename, mimeType: mimeType) else {
            return nil
        }

        return ComposerAttachment(
            name: filename,
            mimeType: mimeType,
            content: .file(path: fileURL.path)
        )
    }

    private static func persistImportedImageData(data: Data, filename: String, mimeType: String) -> URL? {
        let fileManager = FileManager.default

        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directoryURL = applicationSupportURL
            .appendingPathComponent("tech.watzon.NeoCode", isDirectory: true)
            .appendingPathComponent("ImportedAttachments", isDirectory: true)

        let sanitizedBaseName = sanitizedAttachmentBaseName(from: filename)
        let fileExtension = inferredAttachmentExtension(filename: filename, mimeType: mimeType)
        let fileURL = directoryURL.appendingPathComponent(
            "\(sanitizedBaseName)-\(UUID().uuidString).\(fileExtension)",
            isDirectory: false
        )

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    private static func sanitizedAttachmentBaseName(from filename: String) -> String {
        let baseName = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let sanitized = baseName.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        return sanitized.isEmpty ? "attachment" : sanitized
    }

    private static func inferredAttachmentExtension(filename: String, mimeType: String) -> String {
        let pathExtension = URL(fileURLWithPath: filename).pathExtension
        if !pathExtension.isEmpty {
            return pathExtension
        }

        if let extensionForMimeType = UTType(mimeType: mimeType)?.preferredFilenameExtension,
           !extensionForMimeType.isEmpty {
            return extensionForMimeType
        }

        return "bin"
    }
}

struct ComposerQueuedMessage: Identifiable, Hashable {
    enum DeliveryMode: String, Hashable {
        case sendWhenDone
        case steer

        var title: String {
            title(locale: .autoupdatingCurrent)
        }

        func title(locale: Locale) -> String {
            switch self {
            case .sendWhenDone:
                return localized("Send once done", locale: locale)
            case .steer:
                return localized("Steer", locale: locale)
            }
        }
    }

    struct OptionsSnapshot: Hashable {
        let model: ComposerModelOption?
        let agentName: String?
        let variant: String?
    }

    let id: UUID
    var text: String
    var attachments: [ComposerAttachment]
    let createdAt: Date
    var options: OptionsSnapshot
    var deliveryMode: DeliveryMode

    init(
        id: UUID = UUID(),
        text: String,
        attachments: [ComposerAttachment] = [],
        createdAt: Date = .now,
        options: OptionsSnapshot,
        deliveryMode: DeliveryMode = .sendWhenDone
    ) {
        self.id = id
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
        self.options = options
        self.deliveryMode = deliveryMode
    }

    var hasText: Bool {
        text.nonEmptyTrimmed != nil
    }

    var hasContent: Bool {
        hasText || !attachments.isEmpty
    }
}

struct SessionComposerState: Codable, Hashable {
    var selectedModelID: String?
    var selectedModelVariant: String?
    var selectedAgent: String?
    var selectedThinkingLevel: String?
    var ephemeralAgentModels: [String: String]
    var preferredFallbackModelID: String?

    init(
        selectedModelID: String? = nil,
        selectedModelVariant: String? = nil,
        selectedAgent: String? = nil,
        selectedThinkingLevel: String? = nil,
        ephemeralAgentModels: [String: String] = [:],
        preferredFallbackModelID: String? = nil
    ) {
        self.selectedModelID = selectedModelID
        self.selectedModelVariant = selectedModelVariant
        self.selectedAgent = selectedAgent
        self.selectedThinkingLevel = selectedThinkingLevel
        self.ephemeralAgentModels = ephemeralAgentModels
        self.preferredFallbackModelID = preferredFallbackModelID
    }
}

struct ComposerModelOption: Identifiable, Hashable {
    let id: String
    let providerID: String
    let modelID: String
    let title: String
    let contextWindow: Int?
    let variants: [String]
}

enum LocalComposerSlashCommand: String, CaseIterable, Hashable, Identifiable {
    case new
    case compact
    case model
    case agent
    case branch
    case reasoning
    case workspace
    case yolo

    nonisolated var id: String { rawValue }

    nonisolated var name: String { rawValue }

    nonisolated var title: String {
        title(locale: .autoupdatingCurrent)
    }

    nonisolated func title(locale: Locale) -> String {
        switch self {
        case .new:
            return localized("New Session", locale: locale)
        case .compact:
            return localized("Compact Session", locale: locale)
        case .model:
            return localized("Switch Model", locale: locale)
        case .agent:
            return localized("Switch Agent", locale: locale)
        case .branch:
            return localized("Switch Branch", locale: locale)
        case .reasoning:
            return localized("Set Reasoning", locale: locale)
        case .workspace:
            return localized("Open Workspace", locale: locale)
        case .yolo:
            return localized("Toggle YOLO", locale: locale)
        }
    }

    nonisolated var description: String {
        description(locale: .autoupdatingCurrent)
    }

    nonisolated func description(locale: Locale) -> String {
        switch self {
        case .new:
            return localized("Create a new session. Add text after it to seed the new draft.", locale: locale)
        case .compact:
            return localized("Summarize the current session to reduce context size.", locale: locale)
        case .model:
            return localized("Change the selected model by name, provider, or model id.", locale: locale)
        case .agent:
            return localized("Change the selected agent by name.", locale: locale)
        case .branch:
            return localized("Change the selected git branch.", locale: locale)
        case .reasoning:
            return localized("Set the current reasoning level, like low, medium, or high.", locale: locale)
        case .workspace:
            return localized("Open the current project in the preferred workspace tool.", locale: locale)
        case .yolo:
            return localized("Turn YOLO mode on, off, or toggle it for the current session.", locale: locale)
        }
    }

    nonisolated var aliases: [String] {
        switch self {
        case .compact:
            return ["summarize"]
        case .reasoning:
            return ["thinking"]
        default:
            return []
        }
    }

    nonisolated var keywords: [String] {
        [title, description] + aliases
    }

    nonisolated var badgeTitle: String? { "app" }

    nonisolated func matches(name candidate: String) -> Bool {
        candidate == name || aliases.contains(candidate)
    }
}

struct ComposerSlashCommand: Identifiable, Hashable {
    enum Kind: Hashable {
        case local(LocalComposerSlashCommand)
        case remote
    }

    let kind: Kind
    let name: String
    let title: String
    let description: String?
    let badgeTitle: String?
    let keywords: [String]

    var id: String {
        switch kind {
        case .local(let command):
            return "local:\(command.rawValue)"
        case .remote:
            return "remote:\(name)"
        }
    }

    nonisolated static func local(_ command: LocalComposerSlashCommand, locale: Locale = .autoupdatingCurrent) -> Self {
        Self(
            kind: .local(command),
            name: command.name,
            title: command.title(locale: locale),
            description: command.description(locale: locale),
            badgeTitle: command.badgeTitle,
            keywords: [command.title(locale: locale), command.description(locale: locale)] + command.aliases
        )
    }

}

extension String {
    nonisolated var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated var thinkingLevelSortKey: Int {
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
