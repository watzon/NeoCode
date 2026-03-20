import Foundation
import OSLog

extension AppStore {
    func refreshThinkingLevels() {
        let variants = (selectedModel?.variants ?? []).sorted(using: KeyPathComparator(\.thinkingLevelSortKey))

        if let selectedModelID,
           let selectedThinkingLevel,
           !selectedThinkingLevel.isEmpty {
            lastThinkingLevelByModelID[selectedModelID] = selectedThinkingLevel
        }

        availableThinkingLevels = variants
        if variants.isEmpty {
            persistComposerStateForSelectedSession()
            return
        }

        if let selectedModelID,
           let rememberedLevel = lastThinkingLevelByModelID[selectedModelID],
           variants.contains(rememberedLevel) {
            selectedThinkingLevel = rememberedLevel
        } else if selectedThinkingLevel == nil || !variants.contains(selectedThinkingLevel ?? "") {
            selectedThinkingLevel = variants.first
        }

        persistComposerStateForSelectedSession()
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

    func selectAgent(_ agentName: String) {
        defer { persistComposerStateForSelectedSession() }

        if !selectedAgent.isEmpty,
           selectedAgent != agentName,
           let selectedModelID,
           availableModels.contains(where: { $0.id == selectedModelID }) {
            ephemeralAgentModels[selectedAgent] = selectedModelID
        }

        selectedAgent = agentName

        guard let agent = availableAgentObjects.first(where: { $0.name == agentName }) else { return }

        if let ephemeralModelID = ephemeralAgentModels[agentName],
           availableModels.contains(where: { $0.id == ephemeralModelID }) {
            selectedModelID = ephemeralModelID
            logger.info("Switched to ephemeral model for agent \(agentName): \(ephemeralModelID)")
            refreshSelectedSessionStats()
            return
        }

        if let agentModel = agent.model {
            let modelOptionID = "\(agentModel.providerID)/\(agentModel.modelID)"
            if availableModels.contains(where: { $0.id == modelOptionID }) {
                selectedModelID = modelOptionID
                logger.info("Switched to agent \(agentName)'s configured model: \(modelOptionID)")
                refreshSelectedSessionStats()
                return
            } else {
                logger.warning("Agent \(agentName)'s configured model \(modelOptionID) is not available")
            }
        }

        if let preferredFallbackModelID,
           availableModels.contains(where: { $0.id == preferredFallbackModelID }) {
            selectedModelID = preferredFallbackModelID
            logger.debug("Switched to fallback model for agent \(agentName): \(preferredFallbackModelID)")
            refreshSelectedSessionStats()
            return
        }

        if let firstModel = availableModels.first {
            selectedModelID = firstModel.id
            logger.info("Fell back to first available model for agent \(agentName): \(firstModel.id)")
            refreshSelectedSessionStats()
        }
    }

    func setModelForCurrentAgent(_ modelID: String) {
        selectedModelID = modelID
        preferredFallbackModelID = modelID

        if !selectedAgent.isEmpty {
            ephemeralAgentModels[selectedAgent] = modelID
            logger.info("Stored ephemeral model for agent \(self.selectedAgent): \(modelID)")
        }

        persistComposerStateForSelectedSession()
        refreshSelectedSessionStats()
    }

    func reconcileSelectedModel(using models: [ComposerModelOption]) {
        if let selectedModelID,
           models.contains(where: { $0.id == selectedModelID }) {
            return
        }

        if !selectedAgent.isEmpty,
           let ephemeralModelID = ephemeralAgentModels[selectedAgent],
           models.contains(where: { $0.id == ephemeralModelID }) {
            selectedModelID = ephemeralModelID
            return
        }

        if let preferredFallbackModelID,
           models.contains(where: { $0.id == preferredFallbackModelID }) {
            selectedModelID = preferredFallbackModelID
            return
        }

        selectedModelID = models.first?.id
    }
}
