import Foundation

struct PersistedProjectsStore {
    private static let persistenceQueue = DispatchQueue(
        label: "tech.watzon.NeoCode.project-persistence",
        qos: .utility
    )

    private static let key = "tech.watzon.NeoCode.projects"
    private static let cacheDirectoryName = "tech.watzon.NeoCode"
    private static let cacheFileName = "projects-cache.json"
    private static let backupFileName = "projects-cache.previous.json"

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default

    func loadProjects() -> [ProjectSummary] {
        guard let data = loadPersistedData() else {
            return []
        }

        if let cachedProjects = try? JSONDecoder().decode([ProjectSummary].self, from: data) {
            return cachedProjects.map(\.restoredFromCache)
        }

        if let legacyProjects = try? JSONDecoder().decode([PersistedProject].self, from: data) {
            return legacyProjects.map {
                ProjectSummary(
                    id: $0.id,
                    name: $0.name,
                    path: $0.path,
                    settings: .init(
                        isCollapsedInSidebar: $0.isCollapsedInSidebar ?? false,
                        preferredEditorID: $0.preferredEditorID
                    )
                )
            }
        }

        return []
    }

    func saveProjects(_ projects: [ProjectSummary], transcriptStatesBySessionID: [String: SessionTranscriptState]) {
        let defaults = defaults
        let fileManager = fileManager
        let payload = ProjectPersistencePayload(
            projects: projects,
            transcriptStatesBySessionID: transcriptStatesBySessionID
        )

        Self.persistenceQueue.async {
            let snapshots = payload.projects.map {
                $0.cacheSnapshot(transcriptStatesBySessionID: payload.transcriptStatesBySessionID)
            }

            guard let data = try? JSONEncoder().encode(snapshots) else { return }
            Self.persist(data, defaults: defaults, fileManager: fileManager)
        }
    }

    private func loadPersistedData() -> Data? {
        if let cacheURL,
           let data = try? Data(contentsOf: cacheURL) {
            return data
        }

        guard let data = defaults.data(forKey: Self.key) else {
            return nil
        }

        if persist(data) {
            defaults.removeObject(forKey: Self.key)
        }

        return data
    }

    @discardableResult
    private func persist(_ data: Data) -> Bool {
        Self.persist(data, defaults: defaults, fileManager: fileManager)
    }

    @discardableResult
    private static func persist(_ data: Data, defaults: UserDefaults, fileManager: FileManager) -> Bool {
        guard let cacheURL = cacheURL(using: fileManager) else { return false }

        do {
            try fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let backupURL = backupURL(using: fileManager),
               let existingData = try? Data(contentsOf: cacheURL),
               existingData != data {
                try? existingData.write(to: backupURL, options: .atomic)
            }
            try data.write(to: cacheURL, options: .atomic)
            defaults.removeObject(forKey: Self.key)
            return true
        } catch {
            return false
        }
    }

    private var cacheURL: URL? {
        Self.cacheURL(using: fileManager)
    }

    private static func cacheURL(using fileManager: FileManager) -> URL? {
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.cacheFileName, isDirectory: false)
    }

    private var backupURL: URL? {
        Self.backupURL(using: fileManager)
    }

    private static func backupURL(using fileManager: FileManager) -> URL? {
        guard let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return applicationSupportURL
            .appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.backupFileName, isDirectory: false)
    }
}

actor PersistedPromptDraftsStore {
    private let defaults = UserDefaults.standard
    private let key = "tech.watzon.NeoCode.promptDrafts"
    private var cachedDrafts: [String: String]?

    func loadDraft(forKey promptKey: String) -> String {
        let drafts = loadDrafts()
        return drafts[promptKey] ?? ""
    }

    func saveDraft(_ value: String, forKey promptKey: String) {
        var drafts = loadDrafts()
        if value.isEmpty {
            drafts.removeValue(forKey: promptKey)
        } else {
            drafts[promptKey] = value
        }
        cachedDrafts = drafts
        defaults.set(drafts, forKey: key)
    }

    func clearAll() {
        cachedDrafts = [:]
        defaults.removeObject(forKey: key)
    }

    private func loadDrafts() -> [String: String] {
        if let cachedDrafts {
            return cachedDrafts
        }

        let drafts = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        cachedDrafts = drafts
        return drafts
    }
}

struct PersistedYoloPreferencesStore {
    private let defaults = UserDefaults.standard
    private let key = "tech.watzon.NeoCode.yoloModeSessions"
    private let legacyRuleKey = "tech.watzon.NeoCode.permissionAutoRespondRules"
    private let legacyEditKey = "tech.watzon.NeoCode.permissionAutoRespondEditSessions"

    func loadYoloSessionKeys() -> Set<String> {
        let stored = Set(defaults.stringArray(forKey: key) ?? [])
        let legacyRules = Set(defaults.stringArray(forKey: legacyRuleKey) ?? []).map(Self.stripLegacyPermissionSuffix)
        let legacyEdit = Set(defaults.stringArray(forKey: legacyEditKey) ?? [])
        return stored.union(legacyRules).union(legacyEdit)
    }

    func saveYoloSessionKeys(_ keys: Set<String>) {
        defaults.set(Array(keys).sorted(), forKey: key)
        defaults.removeObject(forKey: legacyRuleKey)
        defaults.removeObject(forKey: legacyEditKey)
    }

    nonisolated private static func stripLegacyPermissionSuffix(_ key: String) -> String {
        if key.hasSuffix("::edit") {
            return String(key.dropLast("::edit".count))
        }
        if key.hasSuffix("::external_directory") {
            return String(key.dropLast("::external_directory".count))
        }
        return key
    }
}

struct PersistedFavoriteModelsStore {
    private let defaults = UserDefaults.standard
    private let key = "tech.watzon.NeoCode.favoriteModels"

    func loadFavoriteModelIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func saveFavoriteModelIDs(_ ids: Set<String>) {
        defaults.set(Array(ids).sorted(), forKey: key)
    }
}

struct PersistedProject: Codable {
    let id: UUID
    let name: String
    let path: String
    let isCollapsedInSidebar: Bool?
    let preferredEditorID: String?
}

private struct ProjectPersistencePayload: @unchecked Sendable {
    let projects: [ProjectSummary]
    let transcriptStatesBySessionID: [String: SessionTranscriptState]
}

private extension ProjectSummary {
    func cacheSnapshot(transcriptStatesBySessionID: [String: SessionTranscriptState]) -> ProjectSummary {
        var project = self
        project.status = .idle
        project.sessions = sessions
            .filter { !$0.isEphemeral }
            .map { session in
                let transcript = transcriptStatesBySessionID[session.id]?.messages ?? session.transcript
                return session.cacheSnapshot(transcript: transcript)
            }
        return project
    }

    var cacheSnapshot: ProjectSummary {
        var project = self
        project.status = .idle
        project.sessions = sessions
            .filter { !$0.isEphemeral }
            .map(\.cacheSnapshot)
        return project
    }

    var restoredFromCache: ProjectSummary {
        var project = self
        project.status = .idle
        project.sessions = sessions.map(\.restoredFromCache)
        return project
    }
}

private extension SessionSummary {
    func cacheSnapshot(transcript: [ChatMessage]) -> SessionSummary {
        var session = self
        session.status = .idle
        session.transcript = transcript.map(\.cacheSnapshot)
        session.isEphemeral = false
        return session
    }

    var cacheSnapshot: SessionSummary {
        var session = self
        session.status = .idle
        session.transcript = transcript.map(\.cacheSnapshot)
        session.isEphemeral = false
        return session
    }

    var restoredFromCache: SessionSummary {
        var session = self
        session.status = .idle
        session.transcript = transcript.map(\.restoredFromCache)
        session.isEphemeral = false
        return session
    }
}

private extension ChatMessage {
    var cacheSnapshot: ChatMessage {
        var message = self
        message.isInProgress = false
        return message
    }

    var restoredFromCache: ChatMessage {
        var message = self
        message.isInProgress = false
        return message
    }
}
