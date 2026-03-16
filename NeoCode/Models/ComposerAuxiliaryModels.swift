import Foundation

enum ComposerAuxiliaryTriggerKind: Equatable {
    case slashCommand
    case fileMention
}

struct ComposerAuxiliaryDismissal: Equatable {
    let kind: ComposerAuxiliaryTriggerKind
    let query: String
}

struct ComposerAuxiliaryTrigger: Equatable {
    let kind: ComposerAuxiliaryTriggerKind
    let query: String
    let replacementStart: Int

    var dismissal: ComposerAuxiliaryDismissal {
        ComposerAuxiliaryDismissal(kind: kind, query: query)
    }

    func applyingReplacement(_ replacement: String, to text: String) -> ComposerAuxiliaryReplacement {
        let startIndex = text.index(text.startIndex, offsetBy: replacementStart)
        let updatedText = String(text[..<startIndex]) + replacement
        return ComposerAuxiliaryReplacement(text: updatedText, cursorLocation: updatedText.count)
    }
}

struct ComposerAuxiliaryReplacement: Equatable {
    let text: String
    let cursorLocation: Int
}

enum ComposerAuxiliaryParser {
    static func activeTrigger(in text: String) -> ComposerAuxiliaryTrigger? {
        slashCommandTrigger(in: text) ?? fileMentionTrigger(in: text)
    }

    static func slashCommandTrigger(in text: String) -> ComposerAuxiliaryTrigger? {
        guard text.hasPrefix("/") else { return nil }

        let remainder = text.dropFirst()
        guard !remainder.contains(where: { $0.isWhitespace }) else {
            return nil
        }

        return ComposerAuxiliaryTrigger(kind: .slashCommand, query: String(remainder), replacementStart: 0)
    }

    static func fileMentionTrigger(in text: String) -> ComposerAuxiliaryTrigger? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }

        let replacementStart = text.distance(from: text.startIndex, to: atIndex)
        let mentionBodyStart = text.index(after: atIndex)
        let mentionBody = text[mentionBodyStart...]

        guard !mentionBody.contains(where: { $0.isWhitespace }) else {
            return nil
        }

        if atIndex > text.startIndex {
            let previousIndex = text.index(before: atIndex)
            guard text[previousIndex].isWhitespace else {
                return nil
            }
        }

        return ComposerAuxiliaryTrigger(kind: .fileMention, query: String(mentionBody), replacementStart: replacementStart)
    }
}
