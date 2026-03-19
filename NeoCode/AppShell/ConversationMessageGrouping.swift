import SwiftUI

func buildDisplayMessageGroups(from visibleMessages: [ChatMessage]) -> [DisplayMessageGroup] {
    var groups: [DisplayMessageGroup] = []
    var currentUserTurn: [ChatMessage] = []
    var currentAssistantTurn: [ChatMessage] = []

    func flushUserTurn() {
        guard !currentUserTurn.isEmpty else { return }
        groups.append(.userTurn(currentUserTurn))
        currentUserTurn.removeAll(keepingCapacity: true)
    }

    func flushAssistantTurn() {
        guard !currentAssistantTurn.isEmpty else { return }
        groups.append(.assistantTurn(currentAssistantTurn))
        currentAssistantTurn.removeAll(keepingCapacity: true)
    }

    var index = 0
    while index < visibleMessages.count {
        let message = visibleMessages[index]

        if message.kind.isCompactionMarker {
            flushUserTurn()
            flushAssistantTurn()

            var compactionMessages = [message]
            index += 1

            while index < visibleMessages.count {
                let nextMessage = visibleMessages[index]
                guard nextMessage.role == .assistant || nextMessage.role == .tool else { break }
                compactionMessages.append(nextMessage)
                index += 1
            }

            groups.append(.compaction(compactionMessages))
            continue
        }

        if message.role == .assistant || message.role == .tool {
            flushUserTurn()
            currentAssistantTurn.append(message)
        } else if message.role == .user {
            flushAssistantTurn()
            if let previous = currentUserTurn.last,
               previous.turnGroupID != message.turnGroupID {
                flushUserTurn()
            }
            currentUserTurn.append(message)
        } else {
            flushUserTurn()
            flushAssistantTurn()
            groups.append(.message(message))
        }

        index += 1
    }

    flushUserTurn()
    flushAssistantTurn()

    return groups
}
