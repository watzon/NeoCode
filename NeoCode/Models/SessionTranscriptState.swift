import Foundation

struct SessionTranscriptState: Sendable {
    var messages: [ChatMessage]
    var revision: Int

    init(messages: [ChatMessage] = [], revision: Int = 0) {
        self.messages = messages
        self.revision = revision
    }
}
