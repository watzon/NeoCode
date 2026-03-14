import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppStore {
    private let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "AppStore")
    private let projectPersistence = PersistedProjectsStore()
    private let promptDraftPersistence = PersistedPromptDraftsStore()
    private let yoloPreferencePersistence = PersistedYoloPreferencesStore()
    private let newSessionTitle = SessionSummary.defaultTitle
    private let autoRespondedPermissionTTL: TimeInterval = 60 * 60

    var projects: [ProjectSummary]
    var selectedProjectID: ProjectSummary.ID?
    var selectedSessionID: String?
    var draft = "" {
        didSet {
            persistDraftIfNeeded()
        }
    }
    var attachedFiles: [ComposerAttachment] = []
    var availableModels: [ComposerModelOption] = []
    var selectedModelID: String?
    var selectedModelVariant: String?
    var selectedAgent = ""
    var availableAgents: [String] = []
    var availableCommands: [OpenCodeCommand] = []
    var availableThinkingLevels: [String] = []
    var selectedThinkingLevel: String?
    var selectedBranch = "main"
    var availableBranches: [String] = []
    var isLoadingSessions = false
    var loadingTranscriptSessionID: String?
    var isSending = false
    var isRespondingToPrompt = false
    var isPromptReady = true
    var promptLoadingText: String?
    var lastError: String?

    private var composerOptionsProjectPath: String?
    private let runtimeIdleTTL: Duration = .seconds(60)
    private var liveServices: [ProjectSummary.ID: any OpenCodeServicing] = [:]
    private var serviceConnectionIdentifiers: [ProjectSummary.ID: String] = [:]
    private var eventTasks: [ProjectSummary.ID: Task<Void, Never>] = [:]
    private var eventSubscriptionTokens: [ProjectSummary.ID: UUID] = [:]
    private var refreshTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var subscribedConnectionIdentifiers: [ProjectSummary.ID: String] = [:]
    private var runtimeIdleTasks: [ProjectSummary.ID: Task<Void, Never>] = [:]
    private var streamingRecoveryTasks: [String: Task<Void, Never>] = [:]
    private var messageRoles: [String: ChatMessage.Role] = [:]
    private var liveSessionStatuses: [String: OpenCodeSessionActivity] = [:]
    private var pendingPermissionsBySession: [String: [OpenCodePermissionRequest]] = [:]
    private var pendingQuestionsBySession: [String: [OpenCodeQuestionRequest]] = [:]
    private var promptDraftsByKey: [String: String] = [:]
    private var loadedPromptKeys = Set<String>()
    private var isHydratingPrompt = false
    private var promptPersistTask: Task<Void, Never>?
    private var yoloSessionKeys: Set<String>
    private var autoRespondedPermissionIDs: [String: Date] = [:]
    private var activeTranscriptLoadKeys = Set<String>()

    init() {
        let persistedProjects = Self.normalizedProjects(PersistedProjectsStore().loadProjects())
        self.projects = persistedProjects
        self.selectedProjectID = persistedProjects.first?.id
        self.selectedSessionID = persistedProjects.first?.sessions.first?.id
        self.loadingTranscriptSessionID = persistedProjects.first?.sessions.first?.id
        self.yoloSessionKeys = PersistedYoloPreferencesStore().loadYoloSessionKeys()
        seedComposerDefaults()
    }

    init(projects: [ProjectSummary]) {
        let normalizedProjects = Self.normalizedProjects(projects)
        self.projects = normalizedProjects
        self.selectedProjectID = normalizedProjects.first?.id
        self.selectedSessionID = normalizedProjects.first?.sessions.first?.id
        self.loadingTranscriptSessionID = normalizedProjects.first?.sessions.first?.id
        self.yoloSessionKeys = PersistedYoloPreferencesStore().loadYoloSessionKeys()
        seedComposerDefaults()
    }

    var selectedSession: SessionSummary? {
        guard let selectedSessionID else { return nil }
        return projects
            .flatMap(\.sessions)
            .first(where: { $0.id == selectedSessionID })
    }

    var selectedProject: ProjectSummary? {
        if let selectedSessionID,
           let project = projects.first(where: { project in
                project.sessions.contains(where: { $0.id == selectedSessionID })
           }) {
            return project
        }

        if let selectedProjectID,
           let project = projects.first(where: { $0.id == selectedProjectID }) {
            return project
        }

        return projects.first
    }

    func project(for sessionID: String) -> ProjectSummary? {
        projects.first(where: { project in
            project.sessions.contains(where: { $0.id == sessionID })
        })
    }

    func preferredEditorID(for projectID: ProjectSummary.ID) -> String? {
        projects.first(where: { $0.id == projectID })?.settings.preferredEditorID
    }

    func setPreferredEditorID(_ editorID: String?, for projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[projectIndex].settings.preferredEditorID = editorID
        scheduleProjectPersistence()
    }

    func setProjectCollapsed(_ isCollapsed: Bool, for projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[projectIndex].settings.isCollapsedInSidebar = isCollapsed
        scheduleProjectPersistence()
    }

    func pendingPermission(for sessionID: String) -> OpenCodePermissionRequest? {
        pendingPermissionsBySession[sessionID]?.first
    }

    func pendingQuestion(for sessionID: String) -> OpenCodeQuestionRequest? {
        pendingQuestionsBySession[sessionID]?.first
    }

    func isYoloModeEnabled(for sessionID: String) -> Bool {
        guard let key = yoloPreferenceKey(for: sessionID) else { return false }
        return yoloSessionKeys.contains(key)
    }

    func setYoloMode(_ enabled: Bool, for sessionID: String) {
        guard let key = yoloPreferenceKey(for: sessionID) else { return }

        if enabled {
            yoloSessionKeys.insert(key)
        } else {
            yoloSessionKeys.remove(key)
        }

        yoloPreferencePersistence.saveYoloSessionKeys(yoloSessionKeys)
    }

    func preparePrompt(for sessionID: String?) async {
        guard let sessionID,
              let promptKey = promptDraftKey(for: sessionID)
        else {
            isPromptReady = true
            promptLoadingText = nil
            isHydratingPrompt = true
            draft = ""
            isHydratingPrompt = false
            return
        }

        if loadedPromptKeys.contains(promptKey), let cached = promptDraftsByKey[promptKey] {
            isPromptReady = true
            promptLoadingText = nil
            isHydratingPrompt = true
            draft = cached
            isHydratingPrompt = false
            return
        }

        isPromptReady = false
        promptLoadingText = promptDraftsByKey[promptKey].flatMap { $0.nonEmptyTrimmed }

        let loadedDraft = await promptDraftPersistence.loadDraft(forKey: promptKey)
        guard selectedSessionID == sessionID else {
            promptDraftsByKey[promptKey] = loadedDraft
            loadedPromptKeys.insert(promptKey)
            return
        }

        promptDraftsByKey[promptKey] = loadedDraft
        loadedPromptKeys.insert(promptKey)
        isHydratingPrompt = true
        draft = loadedDraft
        isHydratingPrompt = false
        promptLoadingText = nil
        isPromptReady = true
    }

    func selectProject(_ destinationProjectID: ProjectSummary.ID) {
        guard projects.contains(where: { $0.id == destinationProjectID }) else { return }
        if selectedProjectID != destinationProjectID {
            discardSelectedEphemeralSessionIfNeeded()
        }
        selectedProjectID = destinationProjectID
        if let selectedSessionID,
           projectID(for: selectedSessionID) != destinationProjectID {
            self.selectedSessionID = nil
            primePromptState(for: nil)
        }
    }

    func selectSession(_ sessionID: String) {
        guard selectedSessionID != sessionID else { return }
        discardSelectedEphemeralSessionIfNeeded(excluding: sessionID)
        selectedSessionID = sessionID
        selectedProjectID = projectID(for: sessionID)
        if selectedSession?.isEphemeral == true {
            loadingTranscriptSessionID = nil
        } else {
            loadingTranscriptSessionID = sessionID
        }
        primePromptState(for: sessionID)
    }

    func addProject(directoryURL: URL) {
        let resolvedURL = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let projectPath = resolvedURL.path

        if let existingProject = projects.first(where: { $0.path == projectPath }) {
            discardSelectedEphemeralSessionIfNeeded()
            selectedProjectID = existingProject.id
            selectedSessionID = existingProject.sessions.first?.id
            primePromptState(for: selectedSessionID)
            lastError = nil
            return
        }

        discardSelectedEphemeralSessionIfNeeded()
        let project = ProjectSummary(name: resolvedURL.lastPathComponent, path: projectPath)
        projects.append(project)
        scheduleProjectPersistence()
        selectedProjectID = project.id
        selectedSessionID = nil
        primePromptState(for: nil)
        lastError = nil
    }

    func toggleProjectCollapsed(_ projectID: ProjectSummary.ID) {
        setProjectCollapsed(!isProjectCollapsed(projectID), for: projectID)
    }

    func isProjectCollapsed(_ projectID: ProjectSummary.ID) -> Bool {
        projects.first(where: { $0.id == projectID })?.settings.isCollapsedInSidebar ?? false
    }

    func connect(to runtime: OpenCodeRuntime) async {
        guard let project = selectedProject else {
            logger.debug("Disconnecting all live state because no project is selected")
            disconnectLiveState()
            runtime.stop()
            return
        }

        _ = await connectProject(project.id, using: runtime, includeComposerOptions: true)
        reevaluateRuntimeRetention(using: runtime)
    }

    func createSession(using runtime: OpenCodeRuntime) async {
        guard let projectID = selectedProject?.id else { return }
        createEphemeralSession(in: projectID)
    }

    func createSession(in projectID: ProjectSummary.ID, using runtime: OpenCodeRuntime) async {
        _ = runtime
        selectedProjectID = projectID
        createEphemeralSession(in: projectID)
    }

    func refreshSessions(in projectID: ProjectSummary.ID, using runtime: OpenCodeRuntime) async {
        guard projects.contains(where: { $0.id == projectID }) else { return }

        selectProject(projectID)

        guard let service = await liveService(for: projectID, runtime: runtime) else { return }

        await loadSessions(using: service, for: projectID)
        await loadSessionStatuses(using: service, for: projectID)
        await loadPendingPermissions(using: service, for: projectID)
        await loadPendingQuestions(using: service, for: projectID)
        reevaluateRuntimeRetention(using: runtime)
    }

    func syncSelectedSession(using runtime: OpenCodeRuntime) async {
        guard let selectedSessionID else {
            loadingTranscriptSessionID = nil
            return
        }

        loadingTranscriptSessionID = selectedSessionID

        guard let projectID = projectID(for: selectedSessionID),
              let project = projects.first(where: { $0.id == projectID }),
              session(for: selectedSessionID)?.isEphemeral != true
        else {
            if loadingTranscriptSessionID == selectedSessionID {
                loadingTranscriptSessionID = nil
            }
            return
        }

        guard let service = await connectProject(projectID, using: runtime, includeComposerOptions: selectedProjectID == projectID),
              let connection = runtime.connection(for: project.path)
        else {
            if loadingTranscriptSessionID == selectedSessionID {
                loadingTranscriptSessionID = nil
            }
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        let connectionIdentifier = Self.connectionIdentifier(for: connection)
        guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else {
            if loadingTranscriptSessionID == selectedSessionID {
                loadingTranscriptSessionID = nil
            }
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        await loadMessages(for: selectedSessionID, using: service, projectID: projectID, allowCachedFallback: true)
        reevaluateRuntimeRetention(using: runtime)
    }

    func renameSession(_ sessionID: String, to title: String, using runtime: OpenCodeRuntime) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let projectID = projectID(for: sessionID)
        else { return }

        if updateEphemeralSessionTitleIfNeeded(sessionID: sessionID, projectID: projectID, title: trimmed) {
            lastError = nil
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        guard let service = await liveService(for: projectID, runtime: runtime)
        else { return }

        do {
            let updated = try await service.updateSession(sessionID: sessionID, title: trimmed)
            upsert(session: SessionSummary(session: updated, fallbackTitle: trimmed), in: projectID, preferTopInsertion: false)
            lastError = nil
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to rename session: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    func deleteSession(_ sessionID: String, using runtime: OpenCodeRuntime) async {
        guard let projectID = projectID(for: sessionID) else { return }

        if removeEphemeralSessionIfNeeded(sessionID: sessionID, projectID: projectID) {
            lastError = nil
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        guard let service = await liveService(for: projectID, runtime: runtime) else { return }

        do {
            _ = try await service.deleteSession(sessionID: sessionID)
            removeSession(sessionID, in: projectID)
            lastError = nil
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to delete session: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    private func liveService(for projectID: ProjectSummary.ID, runtime: OpenCodeRuntime) async -> (any OpenCodeServicing)? {
        guard let project = projects.first(where: { $0.id == projectID }) else {
            logger.error("Could not resolve project for id: \(projectID.uuidString, privacy: .public)")
            lastError = "Could not find the selected project."
            return nil
        }

        if let service = await connectProject(projectID, using: runtime, includeComposerOptions: selectedProjectID == projectID),
           let connection = runtime.connection(for: project.path) {
            let connectionIdentifier = Self.connectionIdentifier(for: connection)
            if serviceConnectionIdentifiers[projectID] == connectionIdentifier,
               isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) {
                return service
            }
        }

        if let connection = runtime.connection(for: project.path) {
            logger.debug("Creating fallback OpenCode client from runtime connection for project: \(project.path, privacy: .public)")
            let liveClient = OpenCodeClient(connection: connection)
            liveServices[projectID] = liveClient
            serviceConnectionIdentifiers[projectID] = Self.connectionIdentifier(for: connection)
            reevaluateRuntimeRetention(using: runtime)
            return liveClient
        }

        logger.error("Runtime connection unavailable after bootstrap. Detail: \(runtime.detailLabel(for: project.path), privacy: .public)")
        lastError = lastError ?? runtime.detailLabel(for: project.path)
        reevaluateRuntimeRetention(using: runtime)
        return nil
    }

    func sendDraft(using runtime: OpenCodeRuntime) async {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachedFiles.isEmpty,
              let projectID = selectedProject?.id
        else { return }

        if let localCommand = localSlashCommandInvocation(in: trimmed) {
            let handled = await executeLocalSlashCommand(localCommand, in: projectID, using: runtime)
            if handled {
                logger.info(
                    "Handled local slash command project=\(projectID.uuidString, privacy: .public) command=\(localCommand.command.name, privacy: .public)"
                )
            }
            reevaluateRuntimeRetention(using: runtime)
            return
        }

        guard let service = await liveService(for: projectID, runtime: runtime) else {
            logger.error("Cannot send draft because live service is unavailable for project: \(projectID.uuidString, privacy: .public)")
            return
        }

        guard let sessionID = await resolveSessionForSend(projectID: projectID, service: service) else { return }

        let accepted = await sendDraft(using: service, projectID: projectID, sessionID: sessionID)
        if accepted {
            scheduleStreamingRecoveryCheck(for: sessionID, projectID: projectID, using: runtime)
        }

        reevaluateRuntimeRetention(using: runtime)
    }

    @discardableResult
    func sendDraft(using service: any OpenCodeServicing, projectID: ProjectSummary.ID, sessionID: String) async -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = attachedFiles
        guard !trimmed.isEmpty || !attachments.isEmpty else { return false }

        let slashCommand = slashCommandInvocation(in: trimmed)
        let shouldShowOptimisticUserMessage = slashCommand == nil

        isSending = true
        lastError = nil
        if let slashCommand {
            logger.info(
                "Sending slash command session=\(sessionID, privacy: .public) command=\(slashCommand.command.name, privacy: .public) argumentLength=\(slashCommand.arguments.count, privacy: .public) project=\(projectID.uuidString, privacy: .public)"
            )
        } else {
            logger.info(
                "Sending draft session=\(sessionID, privacy: .public) characters=\(trimmed.count, privacy: .public) project=\(projectID.uuidString, privacy: .public)"
            )
        }

        let optimisticID = "optimistic-user-\(UUID().uuidString)"
        let now = Date()
        if shouldShowOptimisticUserMessage && !trimmed.isEmpty {
            upsertMessage(
                ChatMessage(id: optimisticID, role: .user, text: trimmed, timestamp: now, emphasis: .normal),
                in: sessionID,
                projectID: projectID
            )
        }
        if shouldShowOptimisticUserMessage {
            for attachment in attachments {
                upsertMessage(
                    ChatMessage(
                        id: "optimistic-user-attachment-\(UUID().uuidString)",
                        role: .user,
                        text: ChatAttachment(attachment: attachment).displayTitle,
                        timestamp: now,
                        emphasis: .normal,
                        attachment: ChatAttachment(attachment: attachment)
                    ),
                    in: sessionID,
                    projectID: projectID
                )
            }
        }
        draft = ""
        attachedFiles = []
        setSessionStatus(.running, sessionID: sessionID, projectID: projectID)

        do {
            if let slashCommand {
                try await service.sendCommand(
                    sessionID: sessionID,
                    command: slashCommand.command.name,
                    arguments: slashCommand.arguments,
                    attachments: attachments,
                    options: OpenCodePromptOptions(
                        model: selectedModel,
                        agentName: selectedAgent.isEmpty ? nil : selectedAgent,
                        variant: selectedThinkingLevel
                    )
                )
                logger.info(
                    "Slash command accepted for session \(sessionID, privacy: .public): \(slashCommand.command.name, privacy: .public)"
                )
            } else {
                try await service.sendPromptAsync(
                    sessionID: sessionID,
                    text: trimmed,
                    attachments: attachments,
                    options: OpenCodePromptOptions(
                        model: selectedModel,
                        agentName: selectedAgent.isEmpty ? nil : selectedAgent,
                        variant: selectedThinkingLevel
                    )
                )
                logger.info("Draft accepted for session: \(sessionID, privacy: .public)")
            }
        } catch {
            logger.error("Failed to send draft for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if shouldShowOptimisticUserMessage && !trimmed.isEmpty {
                removeMessage(id: optimisticID, sessionID: sessionID, projectID: projectID)
            }
            if shouldShowOptimisticUserMessage {
                removeOptimisticAttachmentMessages(in: sessionID, projectID: projectID)
            }
            draft = trimmed
            attachedFiles = attachments
            setSessionStatus(.attention, sessionID: sessionID, projectID: projectID)
            lastError = error.localizedDescription
            isSending = false
            return false
        }

        isSending = false
        return true
    }

    @discardableResult
    func resendEditedMessage(messageID: String, newText: String, in sessionID: String, using runtime: OpenCodeRuntime) async -> Bool {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let projectID = projectID(for: sessionID)
        else {
            return false
        }

        guard session(for: sessionID)?.status != .running else {
            lastError = "Wait for the current response to finish before editing an earlier message."
            return false
        }

        guard let service = await liveService(for: projectID, runtime: runtime) else {
            logger.error("Cannot resend edited message because live service is unavailable for project: \(projectID.uuidString, privacy: .public)")
            return false
        }

        let didResend = await resendEditedMessage(messageID: messageID, newText: trimmed, in: sessionID, projectID: projectID, using: service)
        if didResend {
            scheduleStreamingRecoveryCheck(for: sessionID, projectID: projectID, using: runtime)
        }
        return didResend
    }

    @discardableResult
    func resendEditedMessage(
        messageID: String,
        newText: String,
        in sessionID: String,
        projectID: ProjectSummary.ID,
        using service: any OpenCodeServicing
    ) async -> Bool {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let session = sessionSummary(for: sessionID, projectID: projectID),
              let messageIndex = session.transcript.firstIndex(where: { $0.id == messageID }),
              session.transcript[messageIndex].role == .user
        else {
            return false
        }

        let targetMessage = session.transcript[messageIndex]
        let upstreamMessageID = targetMessage.messageID ?? targetMessage.id
        let originalTranscript = session.transcript
        let originalUpdatedAt = session.lastUpdatedAt
        let truncatedTranscript = Array(originalTranscript.prefix(messageIndex))
        let optimisticID = "optimistic-user-\(UUID().uuidString)"
        let now = Date()
        var didRevert = false

        isSending = true
        lastError = nil
        logger.info(
            "Resending edited message session=\(sessionID, privacy: .public) message=\(messageID, privacy: .public) characters=\(trimmed.count, privacy: .public)"
        )

        do {
            _ = try await service.revertSession(sessionID: sessionID, messageID: upstreamMessageID, partID: nil)
            didRevert = true

            replaceTranscript(in: sessionID, projectID: projectID, with: truncatedTranscript)
            upsertMessage(
                ChatMessage(id: optimisticID, role: .user, text: trimmed, timestamp: now, emphasis: .normal),
                in: sessionID,
                projectID: projectID
            )
            touchSession(sessionID: sessionID, projectID: projectID, updatedAt: now)
            setSessionStatus(.running, sessionID: sessionID, projectID: projectID)

            try await service.sendPromptAsync(
                sessionID: sessionID,
                text: trimmed,
                attachments: [],
                options: OpenCodePromptOptions(
                    model: selectedModel,
                    agentName: selectedAgent.isEmpty ? nil : selectedAgent,
                    variant: selectedThinkingLevel
                )
            )
            logger.info("Edited message accepted for session: \(sessionID, privacy: .public)")
            isSending = false
            return true
        } catch {
            logger.error(
                "Failed to resend edited message for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )

            if didRevert {
                do {
                    _ = try await service.unrevertSession(sessionID: sessionID)
                } catch {
                    logger.error(
                        "Failed to restore reverted transcript for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            replaceTranscript(in: sessionID, projectID: projectID, with: originalTranscript)
            touchSession(sessionID: sessionID, projectID: projectID, updatedAt: originalUpdatedAt)
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
            cancelStreamingRecoveryCheck(for: sessionID)
            lastError = error.localizedDescription
            isSending = false
            return false
        }
    }

    func stopSelectedSession(using runtime: OpenCodeRuntime) async {
        guard let sessionID = selectedSessionID,
              let projectID = projectID(for: sessionID),
              session(for: sessionID)?.status == .running
        else { return }

        guard let service = await liveService(for: projectID, runtime: runtime) else {
            logger.error("Cannot stop session because live service is unavailable for project: \(projectID.uuidString, privacy: .public)")
            return
        }

        do {
            logger.info("Aborting session: \(sessionID, privacy: .public)")
            try await service.abortSession(sessionID: sessionID)
            liveSessionStatuses[sessionID] = .idle
            setSessionStatus(.idle, sessionID: sessionID, projectID: projectID)
            cancelStreamingRecoveryCheck(for: sessionID)
            refreshSelectedSessionMessages(projectID: projectID)
            lastError = nil
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to abort session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    func addAttachments(from urls: [URL]) async {
        let attachments = await ComposerAttachment.makeAttachments(from: urls)
        addAttachments(attachments)
    }

    func addAttachments(from items: [ComposerAttachmentImportItem]) async {
        let attachments = await ComposerAttachment.makeAttachments(from: items)
        addAttachments(attachments)
    }

    func addAttachments(_ attachments: [ComposerAttachment]) {
        let existing = Set(attachedFiles.map(\.deduplicationKey))
        let newAttachments = attachments.filter { !existing.contains($0.deduplicationKey) }
        attachedFiles.append(contentsOf: newAttachments)
    }

    func removeAttachment(id: ComposerAttachment.ID) {
        attachedFiles.removeAll(where: { $0.id == id })
    }

    func createBranch(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedBranch = trimmed
        if !availableBranches.contains(trimmed) {
            availableBranches.insert(trimmed, at: 0)
        }
    }

    func apply(event: OpenCodeEvent) {
        guard let projectID = selectedProject?.id else { return }
        apply(event: event, projectID: projectID)
    }

    private func apply(event: OpenCodeEvent, projectID: ProjectSummary.ID) {
        switch event {
        case .sessionCreated(let session), .sessionUpdated(let session):
            if session.isRootVisible {
                let fallbackTitle = sessionSummary(for: session.id, projectID: projectID)?.title ?? SessionSummary.defaultTitle
                upsert(session: SessionSummary(session: session, fallbackTitle: fallbackTitle), in: projectID, preferTopInsertion: event.isCreated)
            } else {
                removeSession(session.id, in: projectID)
            }
        case .sessionDeleted(let sessionID):
            removeSession(sessionID, in: projectID)
        case .sessionStatusChanged(let sessionID, let status):
            liveSessionStatuses[sessionID] = status
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
        case .permissionAsked(let request):
            if let service = liveServices[projectID],
               shouldAutoRespond(to: request) {
                Task { [weak self] in
                    await self?.autoRespondToPermission(request, projectID: projectID, service: service)
                }
            } else {
                upsertPendingPermission(request, in: projectID)
            }
        case .permissionReplied(let event):
            removePendingPermission(requestID: event.requestID, sessionID: event.sessionID, projectID: projectID)
        case .questionAsked(let request):
            upsertPendingQuestion(request, in: projectID)
        case .questionReplied(let event):
            removePendingQuestion(requestID: event.requestID, sessionID: event.sessionID, projectID: projectID)
        case .questionRejected(let event):
            removePendingQuestion(requestID: event.requestID, sessionID: event.sessionID, projectID: projectID)
        case .messageUpdated(let info):
            messageRoles[info.id] = info.chatRole
            if let sessionID = info.sessionID {
                touchSession(sessionID: sessionID, projectID: projectID, updatedAt: info.updatedAt ?? info.createdAt ?? Date())
            }
        case .messagePartUpdated(let part):
            apply(part: part, projectID: projectID)
        case .messagePartDelta(let delta):
            apply(delta: delta, projectID: projectID)
        case .connected, .ignored:
            break
        }
    }

    @discardableResult
    private func connectProject(
        _ projectID: ProjectSummary.ID,
        using runtime: OpenCodeRuntime,
        includeComposerOptions: Bool,
        allowCachedFallback: Bool = true
    ) async -> (any OpenCodeServicing)? {
        guard let project = projects.first(where: { $0.id == projectID }) else {
            logger.error("Could not resolve project for id: \(projectID.uuidString, privacy: .public)")
            lastError = "Could not find the selected project."
            return nil
        }

        await runtime.ensureRunning(for: project.path)

        guard let connection = runtime.connection(for: project.path) else {
            logger.debug("Disconnecting live state because runtime connection is missing for project: \(project.path, privacy: .public)")
            disconnectLiveState(for: projectID)
            lastError = lastError ?? runtime.detailLabel(for: project.path)
            return nil
        }

        logger.info("Connecting store to runtime for project: \(project.path, privacy: .public)")
        let service = OpenCodeClient(connection: connection)
        let connectionIdentifier = Self.connectionIdentifier(for: connection)
        let connectionChanged = serviceConnectionIdentifiers[projectID] != connectionIdentifier || liveServices[projectID] == nil

        logger.debug(
            "Runtime connection id=\(connectionIdentifier, privacy: .public) changed=\(connectionChanged, privacy: .public) composerOptions=\(includeComposerOptions, privacy: .public) cachedFallback=\(allowCachedFallback, privacy: .public)"
        )

        if connectionChanged {
            logger.info("Detected runtime connection change for project: \(project.path, privacy: .public)")
        }

        if includeComposerOptions && composerOptionsProjectPath != project.path {
            await loadComposerOptions(using: service, projectPath: project.path)
            guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else { return nil }
        }

        if connectionChanged {
            await loadSessions(using: service, for: projectID, allowCachedFallback: allowCachedFallback)
            guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else { return nil }

            await loadSessionStatuses(using: service, for: projectID)
            guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else { return nil }

            await loadPendingPermissions(using: service, for: projectID)
            guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else { return nil }

            await loadPendingQuestions(using: service, for: projectID)
            guard isCurrentConnection(connectionIdentifier, for: projectID, runtime: runtime) else { return nil }
        }

        liveServices[projectID] = service
        serviceConnectionIdentifiers[projectID] = connectionIdentifier

        if connectionChanged || eventTasks[projectID] == nil || subscribedConnectionIdentifiers[projectID] != connectionIdentifier {
            logger.info(
                "Starting event subscription project=\(project.path, privacy: .public) connection=\(connectionIdentifier, privacy: .public) existingTask=\(self.eventTasks[projectID] != nil, privacy: .public)"
            )
            subscribeToEvents(using: service, projectID: projectID, connectionIdentifier: connectionIdentifier, runtime: runtime)
        } else {
            logger.debug(
                "Reusing existing event subscription project=\(project.path, privacy: .public) connection=\(connectionIdentifier, privacy: .public)"
            )
        }

        runtime.markUsed(for: project.path)
        return service
    }

    func disconnectLiveState() {
        for projectID in Set(liveServices.keys)
            .union(eventTasks.keys)
            .union(runtimeIdleTasks.keys) {
            disconnectLiveState(for: projectID)
        }

        refreshTask?.cancel()
        refreshTask = nil
        composerOptionsProjectPath = nil
        availableCommands = []
        messageRoles = [:]
        liveSessionStatuses = [:]
        pendingPermissionsBySession = [:]
        pendingQuestionsBySession = [:]
        isLoadingSessions = false
        isSending = false
        isRespondingToPrompt = false
        isPromptReady = true
        promptLoadingText = nil
    }

    private func disconnectLiveState(for projectID: ProjectSummary.ID) {
        logger.info("Disconnecting live state for project id: \(projectID.uuidString, privacy: .public)")
        eventTasks[projectID]?.cancel()
        eventTasks.removeValue(forKey: projectID)
        eventSubscriptionTokens.removeValue(forKey: projectID)
        liveServices.removeValue(forKey: projectID)
        serviceConnectionIdentifiers.removeValue(forKey: projectID)
        subscribedConnectionIdentifiers.removeValue(forKey: projectID)
        runtimeIdleTasks[projectID]?.cancel()
        runtimeIdleTasks.removeValue(forKey: projectID)

        let sessionIDs = projectSessionIDs(for: projectID)
        for sessionID in sessionIDs {
            cancelStreamingRecoveryCheck(for: sessionID)
            liveSessionStatuses.removeValue(forKey: sessionID)
            pendingPermissionsBySession.removeValue(forKey: sessionID)
            pendingQuestionsBySession.removeValue(forKey: sessionID)
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
        }

        if composerOptionsProjectPath == projectPath(for: projectID) {
            composerOptionsProjectPath = nil
            availableCommands = []
        }
    }

    private func loadComposerOptions(using service: any OpenCodeServicing, projectPath: String) async {
        async let providersTask = service.listProviders()
        async let agentsTask = service.listAgents()
        async let commandsTask = service.listCommands()
        async let branchesTask = GitBranchService().listBranches(in: projectPath)
        async let currentBranchTask = GitBranchService().currentBranch(in: projectPath)

        do {
            let providersResponse = try await providersTask
            let agents = try await agentsTask
            let commands = (try? await commandsTask) ?? []
            let branches = (try? await branchesTask) ?? []
            let currentBranch = (try? await currentBranchTask) ?? selectedBranch

            let models = providersResponse.providers
                .flatMap { provider in
                    provider.models.values.map {
                        ComposerModelOption(
                            id: "\(provider.id)/\($0.id)",
                            providerID: provider.id,
                            modelID: $0.id,
                            title: $0.name,
                            variants: ($0.variants?.keys.sorted()) ?? []
                        )
                    }
                }
                .sorted { $0.title < $1.title }

            availableModels = models
            if selectedModelID == nil || !models.contains(where: { $0.id == selectedModelID }) {
                selectedModelID = models.first?.id
            }

            availableAgents = agents
                .filter { !($0.hidden ?? false) }
                .filter { ($0.mode ?? "primary") != "subagent" }
                .map(\.name)
                .sorted { displayAgentName($0) < displayAgentName($1) }
            if !availableAgents.contains(selectedAgent) {
                selectedAgent = availableAgents.first ?? ""
            }

            availableCommands = commands.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            logger.info(
                "Loaded composer options project=\(projectPath, privacy: .public) models=\(models.count, privacy: .public) agents=\(self.availableAgents.count, privacy: .public) commands=\(self.availableCommands.count, privacy: .public)"
            )

            refreshThinkingLevels()

            availableBranches = branches
            if !currentBranch.isEmpty {
                selectedBranch = currentBranch
                if !availableBranches.contains(currentBranch) {
                    availableBranches.insert(currentBranch, at: 0)
                }
            }
            composerOptionsProjectPath = projectPath
        } catch {
            logger.error("Failed to load composer options: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadPendingPermissions(using service: any OpenCodeServicing, for projectID: ProjectSummary.ID) async {
        do {
            let requests = try await service.listPermissions()
            var pendingRequests: [OpenCodePermissionRequest] = []
            for request in requests {
                if shouldAutoRespond(to: request) {
                    await autoRespondToPermission(request, projectID: projectID, service: service)
                } else {
                    pendingRequests.append(request)
                }
            }
            replacePendingPermissions(pendingRequests, in: projectID)
        } catch {
            logger.error("Failed to load pending permissions: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadPendingQuestions(using service: any OpenCodeServicing, for projectID: ProjectSummary.ID) async {
        do {
            let requests = try await service.listQuestions()
            replacePendingQuestions(requests, in: projectID)
        } catch {
            logger.error("Failed to load pending questions: \(error.localizedDescription, privacy: .public)")
        }
    }

    func replyToPermission(requestID: String, sessionID: String, reply: OpenCodePermissionReply, message: String? = nil, using runtime: OpenCodeRuntime) async {
        guard !isRespondingToPrompt,
              let projectID = projectID(for: sessionID),
              let service = await liveService(for: projectID, runtime: runtime)
        else { return }

        isRespondingToPrompt = true
        lastError = nil
        defer { isRespondingToPrompt = false }

        do {
            try await service.replyToPermission(requestID: requestID, reply: reply, message: message)
            removePendingPermission(requestID: requestID, sessionID: sessionID, projectID: projectID)
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to reply to permission \(requestID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    func replyToQuestion(requestID: String, sessionID: String, answers: [OpenCodeQuestionAnswer], using runtime: OpenCodeRuntime) async {
        guard !isRespondingToPrompt,
              let projectID = projectID(for: sessionID),
              let service = await liveService(for: projectID, runtime: runtime)
        else { return }

        isRespondingToPrompt = true
        lastError = nil
        defer { isRespondingToPrompt = false }

        do {
            try await service.replyToQuestion(requestID: requestID, answers: answers)
            removePendingQuestion(requestID: requestID, sessionID: sessionID, projectID: projectID)
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to reply to question \(requestID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    func rejectQuestion(requestID: String, sessionID: String, using runtime: OpenCodeRuntime) async {
        guard !isRespondingToPrompt,
              let projectID = projectID(for: sessionID),
              let service = await liveService(for: projectID, runtime: runtime)
        else { return }

        isRespondingToPrompt = true
        lastError = nil
        defer { isRespondingToPrompt = false }

        do {
            try await service.rejectQuestion(requestID: requestID)
            removePendingQuestion(requestID: requestID, sessionID: sessionID, projectID: projectID)
            reevaluateRuntimeRetention(using: runtime)
        } catch {
            logger.error("Failed to reject question \(requestID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            reevaluateRuntimeRetention(using: runtime)
        }
    }

    func refreshThinkingLevels() {
        let variants = (selectedModel?.variants ?? []).sorted(using: KeyPathComparator(\.thinkingLevelSortKey))
        availableThinkingLevels = variants
        if variants.isEmpty {
            selectedThinkingLevel = nil
        } else if selectedThinkingLevel == nil || !variants.contains(selectedThinkingLevel ?? "") {
            selectedThinkingLevel = variants.first
        }
    }

    var selectedModel: ComposerModelOption? {
        availableModels.first(where: { $0.id == selectedModelID })
    }

    func displayAgentName(_ rawName: String) -> String {
        rawName
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func slashCommandInvocation(in text: String) -> SlashCommandInvocation? {
        guard text.hasPrefix("/") else { return nil }

        let components = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = components.first else { return nil }

        let name = String(first.dropFirst())
        guard !name.isEmpty,
              let command = availableCommands.first(where: { $0.name == name })
        else {
            return nil
        }

        let arguments = components.count > 1 ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return SlashCommandInvocation(command: command, arguments: arguments)
    }

    private func localSlashCommandInvocation(in text: String) -> LocalSlashCommandInvocation? {
        guard text.hasPrefix("/") else { return nil }

        let components = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = components.first else { return nil }

        let name = String(first.dropFirst()).lowercased()
        guard !name.isEmpty,
              let command = LocalComposerSlashCommand.allCases.first(where: { $0.matches(name: name) })
        else {
            return nil
        }

        let arguments = components.count > 1 ? String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return LocalSlashCommandInvocation(command: command, arguments: arguments)
    }

    private func executeLocalSlashCommand(
        _ invocation: LocalSlashCommandInvocation,
        in projectID: ProjectSummary.ID,
        using runtime: OpenCodeRuntime
    ) async -> Bool {
        lastError = nil

        switch invocation.command {
        case .new:
            createEphemeralSession(in: projectID)
            draft = invocation.arguments
            return true

        case .model:
            guard let query = invocation.arguments.nonEmptyTrimmed else {
                lastError = "Usage: /model <name>"
                return false
            }
            guard let match = bestMatchingModel(for: query) else {
                lastError = "No model matches '\(query)'."
                return false
            }
            selectedModelID = match.id
            refreshThinkingLevels()
            draft = ""
            return true

        case .agent:
            guard let query = invocation.arguments.nonEmptyTrimmed else {
                lastError = "Usage: /agent <name>"
                return false
            }
            guard let match = bestMatchingAgent(for: query) else {
                lastError = "No agent matches '\(query)'."
                return false
            }
            selectedAgent = match
            draft = ""
            return true

        case .branch:
            guard let query = invocation.arguments.nonEmptyTrimmed else {
                lastError = "Usage: /branch <name>"
                return false
            }
            guard let match = bestMatchingBranch(for: query) else {
                lastError = "No branch matches '\(query)'."
                return false
            }
            selectedBranch = match
            draft = ""
            return true

        case .reasoning:
            guard let query = invocation.arguments.nonEmptyTrimmed else {
                lastError = "Usage: /reasoning <level>"
                return false
            }
            guard let match = bestMatchingThinkingLevel(for: query) else {
                lastError = "No reasoning level matches '\(query)'."
                return false
            }
            selectedThinkingLevel = match
            draft = ""
            return true

        case .workspace:
            guard let project = projects.first(where: { $0.id == projectID }) else {
                lastError = "Select a project before opening a workspace."
                return false
            }
            let service = WorkspaceToolService()
            let tools = service.discoveredTools()
            guard !tools.isEmpty else {
                lastError = "No supported workspace tools were found."
                return false
            }
            let preferredID = preferredEditorID(for: projectID)
            let tool = tools.first(where: { $0.id == preferredID })
                ?? service.defaultToolID(from: tools).flatMap { id in tools.first(where: { $0.id == id }) }
                ?? tools.first
            guard let tool else {
                lastError = "No supported workspace tools were found."
                return false
            }
            setPreferredEditorID(tool.id, for: projectID)
            service.openProject(at: project.path, with: tool)
            draft = ""
            return true

        case .yolo:
            guard let sessionID = selectedSession?.id else {
                lastError = "Select a session before changing YOLO mode."
                return false
            }
            let action = invocation.arguments.lowercased()
            let nextValue: Bool
            switch action {
            case "", "toggle":
                nextValue = !isYoloModeEnabled(for: sessionID)
            case "on", "enable", "enabled", "true":
                nextValue = true
            case "off", "disable", "disabled", "false":
                nextValue = false
            default:
                lastError = "Usage: /yolo [on|off|toggle]"
                return false
            }
            setYoloMode(nextValue, for: sessionID)
            draft = ""
            _ = runtime
            return true
        }
    }

    private func bestMatchingModel(for query: String) -> ComposerModelOption? {
        bestMatch(in: availableModels, query: query) { model in
            [model.title, model.providerID, model.modelID, model.id]
        }
    }

    private func bestMatchingAgent(for query: String) -> String? {
        bestMatch(in: availableAgents, query: query) { agent in
            [agent, displayAgentName(agent)]
        }
    }

    private func bestMatchingBranch(for query: String) -> String? {
        bestMatch(in: availableBranches, query: query) { [$0] }
    }

    private func bestMatchingThinkingLevel(for query: String) -> String? {
        bestMatch(in: availableThinkingLevels, query: query) { [$0] }
    }

    private func bestMatch<T>(in values: [T], query: String, searchableText: (T) -> [String]) -> T? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return nil }

        return values.first(where: { value in
            searchableText(value).contains(where: { $0.lowercased() == normalizedQuery })
        }) ?? values.first(where: { value in
            searchableText(value).contains(where: { $0.lowercased().hasPrefix(normalizedQuery) })
        }) ?? values.first(where: { value in
            searchableText(value).contains(where: { $0.lowercased().contains(normalizedQuery) })
        })
    }

    private func seedComposerDefaults() {
        let fallback = ComposerModelOption(id: "openai/gpt-5.4", providerID: "openai", modelID: "gpt-5.4", title: "GPT-5.4", variants: ["high", "medium", "low"])
        availableModels = [fallback]
        selectedModelID = fallback.id
        availableAgents = ["Builder"]
        availableCommands = []
        selectedAgent = "Builder"
        availableThinkingLevels = fallback.variants
        selectedThinkingLevel = fallback.variants.first
        availableBranches = ["main"]
        selectedBranch = "main"
    }

    private func loadSessions(using service: any OpenCodeServicing, for projectID: ProjectSummary.ID, allowCachedFallback: Bool = false) async {
        isLoadingSessions = true
        defer { isLoadingSessions = false }

        let keepsCurrentUI = allowCachedFallback && (hasCachedSessions(in: projectID) || selectedSession?.isEphemeral == true)

        do {
            let sessions = try await service.listSessions()
                .filter(\.isRootVisible)
                .sorted { $0.updatedAt > $1.updatedAt }
            replaceSessions(
                in: projectID,
                with: sessions.map { session in
                    let fallbackTitle = sessionSummary(for: session.id, projectID: projectID)?.title ?? SessionSummary.defaultTitle
                    return SessionSummary(session: session, fallbackTitle: fallbackTitle)
                }
            )

            if selectedProjectID == projectID, selectedSessionID == nil {
                selectedSessionID = sessions.first?.id
            }

            if let selectedSessionID,
               self.projectID(for: selectedSessionID) == projectID,
               session(for: selectedSessionID)?.isEphemeral != true {
                await loadMessages(for: selectedSessionID, using: service, projectID: projectID, allowCachedFallback: allowCachedFallback)
            }

            if !keepsCurrentUI {
                lastError = nil
            }
        } catch {
            logger.error("Failed to load sessions: \(error.localizedDescription, privacy: .public)")
            if !keepsCurrentUI {
                lastError = error.localizedDescription
            }
        }
    }

    private func loadSessionStatuses(using service: any OpenCodeServicing, for projectID: ProjectSummary.ID) async {
        do {
            let remoteStatuses = try await service.listSessionStatuses()
            applyLiveSessionStatuses(remoteStatuses, projectID: projectID)
        } catch {
            logger.error("Failed to load session statuses: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadMessages(for sessionID: String, using service: any OpenCodeServicing, projectID: ProjectSummary.ID, allowCachedFallback: Bool = false) async {
        let loadKey = "\(projectID.uuidString)|\(sessionID)"
        guard activeTranscriptLoadKeys.insert(loadKey).inserted else { return }

        let keepsCurrentUI = allowCachedFallback && hasCachedTranscript(for: sessionID, projectID: projectID)
        let shouldTrackVisibleLoadingState = selectedSessionID == sessionID && selectedProjectID == projectID

        if shouldTrackVisibleLoadingState {
            loadingTranscriptSessionID = sessionID
        }

        defer {
            activeTranscriptLoadKeys.remove(loadKey)

            if loadingTranscriptSessionID == sessionID {
                loadingTranscriptSessionID = nil
            }
        }

        do {
            let messages = try await service.listMessages(sessionID: sessionID)
            let transcript = ChatMessage.makeTranscript(from: messages)
            for message in messages {
                messageRoles[message.info.id] = message.info.chatRole
            }
            replaceTranscript(in: sessionID, projectID: projectID, with: transcript)
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
            if !keepsCurrentUI {
                lastError = nil
            }
        } catch {
            logger.error("Failed to load messages for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if !keepsCurrentUI {
                lastError = error.localizedDescription
                setSessionStatus(.attention, sessionID: sessionID, projectID: projectID)
            }
        }
    }

    private func subscribeToEvents(
        using service: any OpenCodeServicing,
        projectID: ProjectSummary.ID,
        connectionIdentifier: String,
        runtime: OpenCodeRuntime
    ) {
        logger.info(
            "Subscribing to live event stream for project id: \(projectID.uuidString, privacy: .public) connection=\(connectionIdentifier, privacy: .public)"
        )
        eventTasks[projectID]?.cancel()
        let subscriptionToken = UUID()
        logger.debug("Created event subscription token=\(subscriptionToken.uuidString, privacy: .public)")
        eventSubscriptionTokens[projectID] = subscriptionToken
        subscribedConnectionIdentifiers[projectID] = connectionIdentifier

        guard let projectPath = projectPath(for: projectID) else { return }

        eventTasks[projectID] = Task { [weak self] in
            guard let self else { return }
            defer { clearEventSubscriptionIfCurrent(for: projectID, token: subscriptionToken) }
            var reconnectAttempt = 0
            var streamService = service

            while !Task.isCancelled {
                guard self.hasActiveSubscription(projectID: projectID, connectionIdentifier: connectionIdentifier, token: subscriptionToken) else {
                    return
                }

                do {
                    logger.info(
                        "Opening live event stream attempt=\(reconnectAttempt + 1, privacy: .public) project=\(projectID.uuidString, privacy: .public)"
                    )
                    let stream = try streamService.eventStream()
                    for try await event in stream {
                        if Task.isCancelled || !self.hasActiveSubscription(projectID: projectID, connectionIdentifier: connectionIdentifier, token: subscriptionToken) {
                            return
                        }

                        runtime.markUsed(for: projectPath)

                        if case .connected = event {
                            reconnectAttempt = 0
                            logger.info(
                                "Live event stream connected for project id: \(projectID.uuidString, privacy: .public) token=\(subscriptionToken.uuidString, privacy: .public)"
                            )
                            lastError = nil
                            refreshSelectedSessionMessages(projectID: projectID)
                        } else {
                            reconnectAttempt = 0
                            logger.debug("Received live event: \(event.debugName, privacy: .public)")
                        }

                        self.apply(event: event, projectID: projectID)
                        self.reevaluateRuntimeRetention(using: runtime)
                    }

                    if Task.isCancelled || !self.hasActiveSubscription(projectID: projectID, connectionIdentifier: connectionIdentifier, token: subscriptionToken) {
                        return
                    }

                    reconnectAttempt += 1
                    let delay = reconnectDelay(for: reconnectAttempt)
                    logger.warning(
                        "Live event stream ended for project id: \(projectID.uuidString, privacy: .public). Reconnecting in \(delay.components.seconds, privacy: .public)s"
                    )
                    do {
                        try await Task.sleep(for: delay)
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }

                    if let nextService = await self.connectProject(projectID, using: runtime, includeComposerOptions: false) {
                        streamService = nextService
                    }
                } catch is CancellationError {
                    logger.debug(
                        "Live event stream task cancelled project=\(projectID.uuidString, privacy: .public) token=\(subscriptionToken.uuidString, privacy: .public)"
                    )
                    return
                } catch {
                    guard self.hasActiveSubscription(projectID: projectID, connectionIdentifier: connectionIdentifier, token: subscriptionToken) else {
                        return
                    }
                    reconnectAttempt += 1
                    let delay = reconnectDelay(for: reconnectAttempt)
                    logger.error(
                        "Live event stream failed for project id: \(projectID.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public). Reconnecting in \(delay.components.seconds, privacy: .public)s"
                    )
                    do {
                        try await Task.sleep(for: delay)
                    } catch is CancellationError {
                        return
                    } catch {
                        return
                    }

                    if let nextService = await self.connectProject(projectID, using: runtime, includeComposerOptions: false) {
                        streamService = nextService
                    }
                }
            }
        }
    }

    private func refreshSelectedSessionMessages(projectID: ProjectSummary.ID) {
        guard let selectedSessionID,
              session(for: selectedSessionID)?.isEphemeral != true,
              self.projectID(for: selectedSessionID) == projectID,
              let service = liveServices[projectID]
        else { return }

        logger.debug(
            "Scheduling transcript refresh after stream connect session=\(selectedSessionID, privacy: .public) project=\(projectID.uuidString, privacy: .public)"
        )
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            await self.loadMessages(for: selectedSessionID, using: service, projectID: projectID, allowCachedFallback: true)
        }
    }

    private func scheduleStreamingRecoveryCheck(
        for sessionID: String,
        projectID: ProjectSummary.ID,
        using runtime: OpenCodeRuntime,
        attemptsRemaining: Int = 3,
        baselineRevision: String? = nil
    ) {
        guard attemptsRemaining > 0 else {
            cancelStreamingRecoveryCheck(for: sessionID)
            return
        }

        let initialRevision = baselineRevision ?? transcriptRevision(for: sessionID, projectID: projectID)
        logger.debug(
            "Scheduling streaming recovery check session=\(sessionID, privacy: .public) attemptsRemaining=\(attemptsRemaining, privacy: .public) baselineHash=\(initialRevision.hashValue, privacy: .public)"
        )
        streamingRecoveryTasks[sessionID]?.cancel()
        streamingRecoveryTasks[sessionID] = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled,
                  let session = sessionSummary(for: sessionID, projectID: projectID),
                  session.status == .running
            else {
                logger.debug(
                    "Skipping streaming recovery check session=\(sessionID, privacy: .public) because task cancelled or session no longer running"
                )
                cancelStreamingRecoveryCheck(for: sessionID)
                return
            }

            let currentRevision = transcriptRevision(for: sessionID, projectID: projectID)
            guard currentRevision == initialRevision else {
                logger.debug(
                    "Streaming recovery check satisfied by transcript progress session=\(sessionID, privacy: .public) baselineHash=\(initialRevision.hashValue, privacy: .public) currentHash=\(currentRevision.hashValue, privacy: .public)"
                )
                cancelStreamingRecoveryCheck(for: sessionID)
                return
            }

            logger.warning(
                "No streamed updates detected for running session \(sessionID, privacy: .public); refreshing transcript"
            )

            if let service = await connectProject(projectID, using: runtime, includeComposerOptions: false) {
                await loadMessages(for: sessionID, using: service, projectID: projectID, allowCachedFallback: true)
            }

            scheduleStreamingRecoveryCheck(
                for: sessionID,
                projectID: projectID,
                using: runtime,
                attemptsRemaining: attemptsRemaining - 1,
                baselineRevision: transcriptRevision(for: sessionID, projectID: projectID)
            )
        }
    }

    private func cancelStreamingRecoveryCheck(for sessionID: String) {
        if streamingRecoveryTasks[sessionID] != nil {
            logger.debug("Cancelling streaming recovery check session=\(sessionID, privacy: .public)")
        }
        streamingRecoveryTasks[sessionID]?.cancel()
        streamingRecoveryTasks.removeValue(forKey: sessionID)
    }

    private func apply(part: OpenCodePart, projectID: ProjectSummary.ID) {
        guard let sessionID = part.sessionID else { return }
        let defaultRole = part.messageID.flatMap { messageRoles[$0] } ?? .assistant
        guard let message = ChatMessage(part: part, defaultRole: defaultRole) ?? streamingPlaceholder(for: part, defaultRole: defaultRole) else {
            return
        }

        if message.role == .user {
            reconcileOptimisticUserMessage(with: message, sessionID: sessionID, projectID: projectID)
            reconcileOptimisticAttachmentMessage(with: message, sessionID: sessionID, projectID: projectID)
        }

        upsertMessage(message, in: sessionID, projectID: projectID)
        touchSession(sessionID: sessionID, projectID: projectID, updatedAt: message.timestamp)
        refreshSessionStatus(sessionID: sessionID, projectID: projectID)
    }

    private func apply(delta: OpenCodePartDelta, projectID: ProjectSummary.ID) {
        guard delta.field == "text",
              let indices = indices(for: delta.sessionID, projectID: projectID)
        else {
            return
        }

        let messageIndex: Int
        if let existingIndex = projects[indices.project].sessions[indices.session].transcript.firstIndex(where: { $0.id == delta.partID }) {
            messageIndex = existingIndex
        } else if let placeholder = streamingPlaceholder(for: delta, projectID: projectID) {
            projects[indices.project].sessions[indices.session].transcript.append(placeholder)
            messageIndex = projects[indices.project].sessions[indices.session].transcript.endIndex - 1
            logger.debug(
                "Created streaming placeholder for delta session=\(delta.sessionID, privacy: .public) part=\(delta.partID, privacy: .public)"
            )
        } else {
            logger.debug(
                "Dropping text delta for missing part session=\(delta.sessionID, privacy: .public) part=\(delta.partID, privacy: .public) field=\(delta.field, privacy: .public)"
            )
            return
        }

        projects[indices.project].sessions[indices.session].transcript[messageIndex].text += delta.delta
        projects[indices.project].sessions[indices.session].lastUpdatedAt = .now
        projects[indices.project].sessions[indices.session].status = resolvedSessionStatus(
            sessionID: delta.sessionID,
            transcript: projects[indices.project].sessions[indices.session].transcript
        )
        applyInferredTitleIfNeeded(sessionIndex: indices.session, projectIndex: indices.project)
        scheduleProjectPersistence()
    }

    private func reconnectDelay(for attempt: Int) -> Duration {
        let cappedAttempt = min(max(attempt, 1), 6)
        let baseSeconds = min(pow(2, Double(cappedAttempt - 1)) * 0.5, 8)
        let jitterSeconds = Double.random(in: 0 ... 0.25)
        return .milliseconds(Int((baseSeconds + jitterSeconds) * 1000))
    }

    private func isCurrentConnection(_ connectionIdentifier: String, for projectID: ProjectSummary.ID, runtime: OpenCodeRuntime) -> Bool {
        guard let project = projects.first(where: { $0.id == projectID }),
              let connection = runtime.connection(for: project.path)
        else {
            return false
        }

        return Self.connectionIdentifier(for: connection) == connectionIdentifier
    }

    private func hasActiveSubscription(projectID: ProjectSummary.ID, connectionIdentifier: String, token: UUID) -> Bool {
        eventSubscriptionTokens[projectID] == token && subscribedConnectionIdentifiers[projectID] == connectionIdentifier
    }

    private func clearEventSubscriptionIfCurrent(for projectID: ProjectSummary.ID, token: UUID) {
        guard eventSubscriptionTokens[projectID] == token else { return }
        logger.debug(
            "Clearing event subscription project=\(projectID.uuidString, privacy: .public) token=\(token.uuidString, privacy: .public)"
        )
        eventTasks.removeValue(forKey: projectID)
        eventSubscriptionTokens.removeValue(forKey: projectID)
    }

    private func reevaluateRuntimeRetention(using runtime: OpenCodeRuntime) {
        let knownProjectIDs = Set(projects.map(\.id))

        for projectID in runtimeIdleTasks.keys where !knownProjectIDs.contains(projectID) {
            runtimeIdleTasks[projectID]?.cancel()
            runtimeIdleTasks.removeValue(forKey: projectID)
        }

        for project in projects {
            if shouldKeepRuntimeAlive(for: project.id) {
                runtimeIdleTasks[project.id]?.cancel()
                runtimeIdleTasks.removeValue(forKey: project.id)
                continue
            }

            if liveServices[project.id] != nil || eventTasks[project.id] != nil || runtime.state(for: project.path) != .idle {
                scheduleRuntimeIdleShutdown(for: project.id, using: runtime)
            }
        }
    }

    private func scheduleRuntimeIdleShutdown(for projectID: ProjectSummary.ID, using runtime: OpenCodeRuntime) {
        guard runtimeIdleTasks[projectID] == nil else { return }

        runtimeIdleTasks[projectID] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.runtimeIdleTTL)
            if Task.isCancelled { return }

            await MainActor.run {
                self.runtimeIdleTasks[projectID] = nil

                guard !self.shouldKeepRuntimeAlive(for: projectID),
                      let project = self.projects.first(where: { $0.id == projectID })
                else {
                    return
                }

                self.logger.info("Stopping idle runtime for project: \(project.path, privacy: .public)")
                self.disconnectLiveState(for: projectID)
                runtime.stop(projectPath: project.path)
            }
        }
    }

    private func shouldKeepRuntimeAlive(for projectID: ProjectSummary.ID) -> Bool {
        guard let project = projects.first(where: { $0.id == projectID }) else { return false }

        if selectedProjectID == projectID {
            return true
        }

        return project.sessions.contains { session in
            session.status == .running || pendingPermission(for: session.id) != nil || pendingQuestion(for: session.id) != nil
        }
    }

    private func projectSessionIDs(for projectID: ProjectSummary.ID) -> [String] {
        projects.first(where: { $0.id == projectID })?.sessions.map(\.id) ?? []
    }

    private func projectPath(for projectID: ProjectSummary.ID) -> String? {
        projects.first(where: { $0.id == projectID })?.path
    }

    private static func connectionIdentifier(for connection: OpenCodeRuntime.Connection) -> String {
        "\(connection.projectPath)|\(connection.baseURL.absoluteString)|\(connection.username)"
    }

    private func replaceSessions(in projectID: ProjectSummary.ID, with sessions: [SessionSummary]) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let ephemeralSessions = projects[projectIndex].sessions.filter(\.isEphemeral)
        let cachedSessions = Self.sessionLookup(for: projects[projectIndex].sessions)
        let mergedSessions = ephemeralSessions + sessions.map { incoming in
            guard let existing = cachedSessions[incoming.id] else {
                return incoming.applyingInferredTitle(from: incoming.transcript)
            }

            var merged = incoming
            merged.transcript = existing.transcript
            merged.status = existing.status
            merged.lastUpdatedAt = max(existing.lastUpdatedAt, incoming.lastUpdatedAt)
            return merged.applyingInferredTitle(from: merged.transcript)
        }
        projects[projectIndex].sessions = mergedSessions
        if selectedProjectID == projectID,
           (selectedSessionID == nil || !mergedSessions.contains(where: { $0.id == selectedSessionID })) {
            self.selectedSessionID = mergedSessions.first?.id
        }
        scheduleProjectPersistence()
    }

    private func replaceTranscript(in sessionID: String, projectID: ProjectSummary.ID, with transcript: [ChatMessage]) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        projects[indices.project].sessions[indices.session].transcript = transcript
        applyInferredTitleIfNeeded(sessionIndex: indices.session, projectIndex: indices.project)
        scheduleProjectPersistence()
    }

    private func upsert(session: SessionSummary, in projectID: ProjectSummary.ID, preferTopInsertion: Bool) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        if let sessionIndex = projects[projectIndex].sessions.firstIndex(where: { $0.id == session.id }) {
            let existingTranscript = projects[projectIndex].sessions[sessionIndex].transcript
            var updated = session
            if !existingTranscript.isEmpty {
                updated.transcript = existingTranscript
            }
            updated = updated.applyingInferredTitle(from: updated.transcript)
            projects[projectIndex].sessions[sessionIndex] = updated
            projects[projectIndex].sessions[sessionIndex].status = resolvedSessionStatus(
                sessionID: session.id,
                transcript: projects[projectIndex].sessions[sessionIndex].transcript,
                fallback: projects[projectIndex].sessions[sessionIndex].status
            )
        } else if preferTopInsertion {
            var inserted = session.applyingInferredTitle(from: session.transcript)
            inserted.status = resolvedSessionStatus(sessionID: session.id, transcript: inserted.transcript, fallback: inserted.status)
            projects[projectIndex].sessions.insert(inserted, at: 0)
        } else {
            var inserted = session.applyingInferredTitle(from: session.transcript)
            inserted.status = resolvedSessionStatus(sessionID: session.id, transcript: inserted.transcript, fallback: inserted.status)
            projects[projectIndex].sessions.append(inserted)
        }

        if selectedProjectID == projectID, selectedSessionID == nil {
            selectedSessionID = session.id
        }
        scheduleProjectPersistence()
    }

    private func removeSession(_ sessionID: String, in projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[projectIndex].sessions.removeAll(where: { $0.id == sessionID })
        cancelStreamingRecoveryCheck(for: sessionID)
        liveSessionStatuses.removeValue(forKey: sessionID)
        pendingPermissionsBySession.removeValue(forKey: sessionID)
        pendingQuestionsBySession.removeValue(forKey: sessionID)
        if selectedSessionID == sessionID {
            selectedSessionID = projects[projectIndex].sessions.first?.id
        }
        scheduleProjectPersistence()
    }

    private func upsertMessage(_ message: ChatMessage, in sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        if let messageIndex = projects[indices.project].sessions[indices.session].transcript.firstIndex(where: { $0.id == message.id }) {
            projects[indices.project].sessions[indices.session].transcript[messageIndex] = message
        } else {
            projects[indices.project].sessions[indices.session].transcript.append(message)
        }
        applyInferredTitleIfNeeded(sessionIndex: indices.session, projectIndex: indices.project)
        scheduleProjectPersistence()
    }

    private func removeMessage(id: String, sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        projects[indices.project].sessions[indices.session].transcript.removeAll(where: { $0.id == id })
        scheduleProjectPersistence()
    }

    private func setSessionStatus(_ status: SessionStatus, sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        projects[indices.project].sessions[indices.session].status = status
        if status != .running {
            cancelStreamingRecoveryCheck(for: sessionID)
        }
        scheduleProjectPersistence()
    }

    private func refreshSessionStatus(sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        let transcript = projects[indices.project].sessions[indices.session].transcript
        projects[indices.project].sessions[indices.session].status = resolvedSessionStatus(
            sessionID: sessionID,
            transcript: transcript,
            fallback: projects[indices.project].sessions[indices.session].status
        )
        if projects[indices.project].sessions[indices.session].status != .running {
            cancelStreamingRecoveryCheck(for: sessionID)
        }
        scheduleProjectPersistence()
    }

    private func transcriptRevision(for sessionID: String, projectID: ProjectSummary.ID) -> String {
        guard let session = sessionSummary(for: sessionID, projectID: projectID) else { return "" }
        return session.transcript.map { message in
            "\(message.id):\(message.text.count):\(message.isInProgress ? 1 : 0):\(message.timestamp.timeIntervalSinceReferenceDate)"
        }.joined(separator: "|")
    }

    private func applyLiveSessionStatuses(_ statuses: [String: OpenCodeSessionActivity], projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }

        for session in projects[projectIndex].sessions {
            liveSessionStatuses[session.id] = statuses[session.id] ?? .idle
        }

        for session in projects[projectIndex].sessions {
            refreshSessionStatus(sessionID: session.id, projectID: projectID)
        }
    }

    private func resolvedSessionStatus(sessionID: String, transcript: [ChatMessage], fallback: SessionStatus = .idle) -> SessionStatus {
        if pendingPermission(for: sessionID) != nil {
            return .attention
        }

        if pendingQuestion(for: sessionID) != nil {
            return .attention
        }

        if let activity = liveSessionStatuses[sessionID] {
            switch activity {
            case .idle:
                return .idle
            case .busy:
                return .running
            case .retry:
                return .attention
            }
        }

        return transcriptDerivedStatus(for: transcript, fallback: fallback)
    }

    private func transcriptDerivedStatus(for transcript: [ChatMessage], fallback: SessionStatus = .idle) -> SessionStatus {
        if transcript.contains(where: \.isInProgress) {
            return .running
        }

        if let lastMessage = transcript.last,
           case .toolCall(_, let toolStatus, _) = lastMessage.kind,
           toolStatus == .error {
            return .attention
        }

        return fallback == .attention ? .attention : .idle
    }

    private func reconcileOptimisticUserMessage(with message: ChatMessage, sessionID: String, projectID: ProjectSummary.ID) {
        guard message.attachment == nil else { return }

        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        let transcript = projects[indices.project].sessions[indices.session].transcript

        guard let optimisticIndex = transcript.firstIndex(where: {
            $0.id.hasPrefix("optimistic-user-") && $0.role == .user && $0.text == message.text
        }) else {
            return
        }

        projects[indices.project].sessions[indices.session].transcript.remove(at: optimisticIndex)
    }

    private func reconcileOptimisticAttachmentMessage(with message: ChatMessage, sessionID: String, projectID: ProjectSummary.ID) {
        guard let attachment = message.attachment,
              let indices = indices(for: sessionID, projectID: projectID)
        else {
            return
        }

        let transcript = projects[indices.project].sessions[indices.session].transcript
        guard let optimisticIndex = transcript.firstIndex(where: {
            $0.id.hasPrefix("optimistic-user-attachment-") && $0.attachment?.optimisticKey == attachment.optimisticKey
        }) else {
            return
        }

        projects[indices.project].sessions[indices.session].transcript.remove(at: optimisticIndex)
    }

    private func removeOptimisticAttachmentMessages(in sessionID: String, projectID: ProjectSummary.ID) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        projects[indices.project].sessions[indices.session].transcript.removeAll(where: {
            $0.id.hasPrefix("optimistic-user-attachment-")
        })
    }

    private func streamingPlaceholder(for part: OpenCodePart, defaultRole: ChatMessage.Role) -> ChatMessage? {
        guard (part.type == .text || part.type == .reasoning), part.text?.isEmpty ?? true else {
            return nil
        }

        return ChatMessage(
            id: part.id,
            messageID: part.messageID,
            role: part.chatRole(defaultRole: defaultRole),
            text: "",
            timestamp: part.updatedAt ?? Date(),
            emphasis: part.chatEmphasis,
            kind: .plain,
            isInProgress: true
        )
    }

    private func streamingPlaceholder(for delta: OpenCodePartDelta, projectID: ProjectSummary.ID) -> ChatMessage? {
        let defaultRole = messageRoles[delta.messageID] ?? .assistant
        guard defaultRole != .user else { return nil }

        return ChatMessage(
            id: delta.partID,
            messageID: delta.messageID,
            role: defaultRole,
            text: "",
            timestamp: Date(),
            emphasis: .normal,
            kind: .plain,
            isInProgress: true
        )
    }

    private func touchSession(sessionID: String, projectID: ProjectSummary.ID, updatedAt: Date) {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        projects[indices.project].sessions[indices.session].lastUpdatedAt = updatedAt
        scheduleProjectPersistence()
    }

    private func replacePendingPermissions(_ requests: [OpenCodePermissionRequest], in projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let sessionIDs = Set(projects[projectIndex].sessions.map(\.id))

        for sessionID in sessionIDs {
            pendingPermissionsBySession.removeValue(forKey: sessionID)
        }

        for request in requests where sessionIDs.contains(request.sessionID) {
            upsertPendingPermission(request, in: projectID)
        }

        for sessionID in sessionIDs {
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
        }
    }

    private func upsertPendingPermission(_ request: OpenCodePermissionRequest, in projectID: ProjectSummary.ID) {
        var requests = pendingPermissionsBySession[request.sessionID] ?? []

        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            requests[index] = request
        } else {
            requests.append(request)
            requests.sort { $0.id < $1.id }
        }

        pendingPermissionsBySession[request.sessionID] = requests
        refreshSessionStatus(sessionID: request.sessionID, projectID: projectID)
    }

    private func removePendingPermission(requestID: String, sessionID: String, projectID: ProjectSummary.ID) {
        guard var requests = pendingPermissionsBySession[sessionID] else { return }
        requests.removeAll(where: { $0.id == requestID })

        if requests.isEmpty {
            pendingPermissionsBySession.removeValue(forKey: sessionID)
        } else {
            pendingPermissionsBySession[sessionID] = requests
        }

        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        let transcript = projects[indices.project].sessions[indices.session].transcript
        projects[indices.project].sessions[indices.session].status = resolvedSessionStatus(
            sessionID: sessionID,
            transcript: transcript,
            fallback: .idle
        )
        scheduleProjectPersistence()
    }

    private func shouldAutoRespond(to request: OpenCodePermissionRequest) -> Bool {
        guard isYoloModeEnabled(for: request.sessionID)
        else {
            return false
        }

        pruneAutoRespondedPermissions()
        return autoRespondedPermissionIDs[request.id] == nil
    }

    private func autoRespondToPermission(_ request: OpenCodePermissionRequest, projectID: ProjectSummary.ID, service: any OpenCodeServicing) async {
        pruneAutoRespondedPermissions()
        guard autoRespondedPermissionIDs[request.id] == nil else { return }

        autoRespondedPermissionIDs[request.id] = Date()

        do {
            try await service.replyToPermission(requestID: request.id, reply: .once, message: nil)
            removePendingPermission(requestID: request.id, sessionID: request.sessionID, projectID: projectID)
        } catch {
            autoRespondedPermissionIDs.removeValue(forKey: request.id)
            logger.error("Failed to auto-respond to permission \(request.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            upsertPendingPermission(request, in: projectID)
        }
    }

    private func pruneAutoRespondedPermissions(now: Date = Date()) {
        autoRespondedPermissionIDs = autoRespondedPermissionIDs.filter { now.timeIntervalSince($0.value) < autoRespondedPermissionTTL }
    }

    private func persistDraftIfNeeded() {
        guard !isHydratingPrompt,
              isPromptReady,
              let sessionID = selectedSessionID,
              let promptKey = promptDraftKey(for: sessionID)
        else {
            return
        }

        promptDraftsByKey[promptKey] = draft
        loadedPromptKeys.insert(promptKey)

        promptPersistTask?.cancel()
        let promptDraftPersistence = promptDraftPersistence
        let value = draft
        promptPersistTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await promptDraftPersistence.saveDraft(value, forKey: promptKey)
        }
    }

    private func primePromptState(for sessionID: String?) {
        attachedFiles = []

        guard let sessionID,
              let promptKey = promptDraftKey(for: sessionID)
        else {
            isPromptReady = true
            promptLoadingText = nil
            isHydratingPrompt = true
            draft = ""
            isHydratingPrompt = false
            return
        }

        if loadedPromptKeys.contains(promptKey) {
            isPromptReady = true
            promptLoadingText = nil
            isHydratingPrompt = true
            draft = promptDraftsByKey[promptKey] ?? ""
            isHydratingPrompt = false
            return
        }

        isPromptReady = false
        promptLoadingText = promptDraftsByKey[promptKey].flatMap { $0.nonEmptyTrimmed }
        isHydratingPrompt = true
        draft = ""
        isHydratingPrompt = false
    }

    private func storePromptDraft(_ value: String, forKey promptKey: String) async {
        promptDraftsByKey[promptKey] = value
        loadedPromptKeys.insert(promptKey)
        await promptDraftPersistence.saveDraft(value, forKey: promptKey)
    }

    private func promptDraftKey(for sessionID: String) -> String? {
        guard let project = selectedProject ?? project(for: sessionID),
              session(for: sessionID) != nil
        else {
            return nil
        }

        if session(for: sessionID)?.isEphemeral == true {
            return "\(project.path)::workspace"
        }

        return "\(project.path)::\(sessionID)"
    }

    private func yoloPreferenceKey(for sessionID: String) -> String? {
        guard let project = selectedProject ?? project(for: sessionID) else { return nil }
        return "\(project.path)::\(sessionID)"
    }

    private func replacePendingQuestions(_ requests: [OpenCodeQuestionRequest], in projectID: ProjectSummary.ID) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let sessionIDs = Set(projects[projectIndex].sessions.map(\.id))

        for sessionID in sessionIDs {
            pendingQuestionsBySession.removeValue(forKey: sessionID)
        }

        for request in requests where sessionIDs.contains(request.sessionID) {
            upsertPendingQuestion(request, in: projectID)
        }

        for sessionID in sessionIDs {
            refreshSessionStatus(sessionID: sessionID, projectID: projectID)
        }
    }

    private func upsertPendingQuestion(_ request: OpenCodeQuestionRequest, in projectID: ProjectSummary.ID) {
        var requests = pendingQuestionsBySession[request.sessionID] ?? []

        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            requests[index] = request
        } else {
            requests.append(request)
            requests.sort { $0.id < $1.id }
        }

        pendingQuestionsBySession[request.sessionID] = requests
        refreshSessionStatus(sessionID: request.sessionID, projectID: projectID)
    }

    private func removePendingQuestion(requestID: String, sessionID: String, projectID: ProjectSummary.ID) {
        guard var requests = pendingQuestionsBySession[sessionID] else { return }
        requests.removeAll(where: { $0.id == requestID })

        if requests.isEmpty {
            pendingQuestionsBySession.removeValue(forKey: sessionID)
        } else {
            pendingQuestionsBySession[sessionID] = requests
        }

        guard let indices = indices(for: sessionID, projectID: projectID) else { return }
        let transcript = projects[indices.project].sessions[indices.session].transcript
        projects[indices.project].sessions[indices.session].status = resolvedSessionStatus(
            sessionID: sessionID,
            transcript: transcript,
            fallback: .idle
        )
        scheduleProjectPersistence()
    }

    private func hasCachedSessions(in projectID: ProjectSummary.ID) -> Bool {
        guard let project = projects.first(where: { $0.id == projectID }) else { return false }
        return project.sessions.contains(where: { !$0.isEphemeral })
    }

    private func hasCachedTranscript(for sessionID: String, projectID: ProjectSummary.ID) -> Bool {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return false }
        return !projects[indices.project].sessions[indices.session].transcript.isEmpty
    }

    private func sessionSummary(for sessionID: String, projectID: ProjectSummary.ID) -> SessionSummary? {
        guard let indices = indices(for: sessionID, projectID: projectID) else { return nil }
        return projects[indices.project].sessions[indices.session]
    }

    private func indices(for sessionID: String, projectID: ProjectSummary.ID) -> (project: Int, session: Int)? {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }),
              let sessionIndex = projects[projectIndex].sessions.firstIndex(where: { $0.id == sessionID })
        else { return nil }
        return (projectIndex, sessionIndex)
    }

    private func projectID(for sessionID: String) -> ProjectSummary.ID? {
        projects.first(where: { project in
            project.sessions.contains(where: { $0.id == sessionID })
        })?.id
    }

    private func session(for sessionID: String) -> SessionSummary? {
        projects
            .flatMap(\.sessions)
            .first(where: { $0.id == sessionID })
    }

    private func createEphemeralSession(in projectID: ProjectSummary.ID) {
        discardSelectedEphemeralSessionIfNeeded()

        let session = SessionSummary(
            id: "draft-session-\(UUID().uuidString)",
            title: newSessionTitle,
            lastUpdatedAt: .now,
            isEphemeral: true
        )
        upsert(session: session, in: projectID, preferTopInsertion: true)
        selectedProjectID = projectID
        selectedSessionID = session.id
        primePromptState(for: session.id)
        lastError = nil
    }

    private func discardSelectedEphemeralSessionIfNeeded(excluding sessionID: String? = nil) {
        guard let selectedSessionID,
              selectedSessionID != sessionID,
              let projectID = projectID(for: selectedSessionID),
              session(for: selectedSessionID)?.isEphemeral == true
        else {
            return
        }

        removeSession(selectedSessionID, in: projectID)
    }

    private func updateEphemeralSessionTitleIfNeeded(sessionID: String, projectID: ProjectSummary.ID, title: String) -> Bool {
        guard let indices = indices(for: sessionID, projectID: projectID),
              projects[indices.project].sessions[indices.session].isEphemeral
        else {
            return false
        }

        projects[indices.project].sessions[indices.session].title = title
        projects[indices.project].sessions[indices.session].lastUpdatedAt = .now
        scheduleProjectPersistence()
        return true
    }

    private func removeEphemeralSessionIfNeeded(sessionID: String, projectID: ProjectSummary.ID) -> Bool {
        guard session(for: sessionID)?.isEphemeral == true else { return false }
        removeSession(sessionID, in: projectID)
        return true
    }

    private func resolveSessionForSend(projectID: ProjectSummary.ID, service: any OpenCodeServicing) async -> String? {
        guard let currentSessionID = selectedSessionID,
              let session = self.session(for: currentSessionID)
        else {
            return nil
        }

        guard session.isEphemeral else {
            return session.id
        }

        do {
            logger.info("Persisting draft session in project id: \(projectID.uuidString, privacy: .public)")
            let created = try await service.createSession(title: session.requestedServerTitle)
            logger.info("Persisted draft session as id: \(created.id, privacy: .public)")
            await promoteEphemeralSession(session.id, in: projectID, to: created)
            lastError = nil
            return created.id
        } catch {
            logger.error("Failed to persist draft session: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            return nil
        }
    }

    func promoteEphemeralSession(_ ephemeralSessionID: String, in projectID: ProjectSummary.ID, to created: OpenCodeSession) async {
        guard let ephemeralSession = session(for: ephemeralSessionID) else { return }

        let ephemeralPromptKey = promptDraftKey(for: ephemeralSessionID)
        replaceSession(
            ephemeralSessionID,
            in: projectID,
            with: SessionSummary(session: created, fallbackTitle: ephemeralSession.title)
        )
        selectedSessionID = created.id

        if let ephemeralPromptKey {
            promptPersistTask?.cancel()
            promptPersistTask = nil
            await storePromptDraft("", forKey: ephemeralPromptKey)
        }
    }

    private func replaceSession(_ sessionID: String, in projectID: ProjectSummary.ID, with session: SessionSummary) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }

        projects[projectIndex].sessions.removeAll(where: { $0.id == session.id && $0.id != sessionID })

        guard let sessionIndex = projects[projectIndex].sessions.firstIndex(where: { $0.id == sessionID }) else {
            upsert(session: session, in: projectID, preferTopInsertion: true)
            return
        }

        let existing = projects[projectIndex].sessions[sessionIndex]
        var replacement = session.applyingInferredTitle(from: existing.transcript)
        replacement.status = existing.status
        replacement.transcript = existing.transcript
        replacement.lastUpdatedAt = max(existing.lastUpdatedAt, session.lastUpdatedAt)
        projects[projectIndex].sessions[sessionIndex] = replacement
        scheduleProjectPersistence()
    }

    private static func normalizedProjects(_ projects: [ProjectSummary]) -> [ProjectSummary] {
        projects.map { project in
            var normalized = project
            normalized.sessions = deduplicatedSessions(project.sessions)
            return normalized
        }
    }

    private static func deduplicatedSessions(_ sessions: [SessionSummary]) -> [SessionSummary] {
        var orderedIDs: [String] = []
        var sessionsByID: [String: SessionSummary] = [:]

        for session in sessions {
            if let existing = sessionsByID[session.id] {
                sessionsByID[session.id] = mergeSession(existing, with: session)
            } else {
                orderedIDs.append(session.id)
                sessionsByID[session.id] = session
            }
        }

        return orderedIDs.compactMap { sessionsByID[$0] }
    }

    private static func sessionLookup(for sessions: [SessionSummary]) -> [String: SessionSummary] {
        var lookup: [String: SessionSummary] = [:]

        for session in deduplicatedSessions(sessions) {
            lookup[session.id] = session
        }

        return lookup
    }

    private static func mergeSession(_ existing: SessionSummary, with incoming: SessionSummary) -> SessionSummary {
        let preferredMetadata = incoming.lastUpdatedAt >= existing.lastUpdatedAt ? incoming : existing
        let fallbackMetadata = preferredMetadata.lastUpdatedAt == existing.lastUpdatedAt ? incoming : existing

        var merged = preferredMetadata

        if merged.hasPlaceholderTitle && !fallbackMetadata.hasPlaceholderTitle {
            merged.title = fallbackMetadata.title
        }

        if merged.transcript.isEmpty || fallbackMetadata.transcript.count > merged.transcript.count {
            merged.transcript = fallbackMetadata.transcript
        }

        if sessionStatusPriority(fallbackMetadata.status) > sessionStatusPriority(merged.status) {
            merged.status = fallbackMetadata.status
        }

        merged.lastUpdatedAt = max(existing.lastUpdatedAt, incoming.lastUpdatedAt)
        merged.isEphemeral = existing.isEphemeral && incoming.isEphemeral
        return merged.applyingInferredTitle(from: merged.transcript)
    }

    private static func sessionStatusPriority(_ status: SessionStatus) -> Int {
        switch status {
        case .idle:
            return 0
        case .running:
            return 1
        case .attention:
            return 2
        }
    }

    private func applyInferredTitleIfNeeded(sessionIndex: Int, projectIndex: Int) {
        let session = projects[projectIndex].sessions[sessionIndex]
        let inferred = session.applyingInferredTitle(from: session.transcript)
        guard inferred.title != session.title else { return }
        projects[projectIndex].sessions[sessionIndex].title = inferred.title
    }

    private func scheduleProjectPersistence() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            projectPersistence.saveProjects(projects)
        }
    }
}

private struct SlashCommandInvocation {
    let command: OpenCodeCommand
    let arguments: String
}

private struct LocalSlashCommandInvocation {
    let command: LocalComposerSlashCommand
    let arguments: String
}
