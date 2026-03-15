import Foundation
import Testing
@testable import NeoCode

@MainActor
@Suite(.serialized)
struct ToolCallPresentationTests {
    @Test func applyPatchPresentationCreatesPerFileItems() {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFileURL = tempDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("swift")
        try? "prefix\nnew line\nsuffix\n".write(to: tempFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFileURL) }

        let toolCall = ChatMessage.ToolCall(
            name: "apply_patch",
            status: .completed,
            detail: "apply_patch completed",
            input: .object([
                "patchText": .string(
                    """
                    *** Begin Patch
                    *** Update File: \(tempFileURL.path)
                    @@
                    -old line
                    +new line
                    *** Add File: NeoCode/Models/Temp.swift
                    +struct Temp {}
                    *** End Patch
                    """
                )
            ])
        )

        let presentation = ToolCallPresentation(toolCall: toolCall)

        #expect(presentation.items.count == 2)
        #expect(presentation.items[0].title == "Patched \(tempFileURL.path)")
        #expect(presentation.items[1].title == "Added NeoCode/Models/Temp.swift")

        guard case .diff(let file) = presentation.items[0].content else {
            Issue.record("Expected first item to render as a diff")
            return
        }
        
        #expect(file.change == .modified)
        #expect(file.hunks.count == 1)
        #expect(file.hunks[0].oldRange == DiffLineRange(start: 2, count: 1))
        #expect(file.hunks[0].newRange == DiffLineRange(start: 2, count: 1))
        #expect(file.hunks[0].lines.map(\.kind) == [.removed, .added])
    }

    @Test func unifiedDiffPresentationParsesBashOutput() {
        let toolCall = ChatMessage.ToolCall(
            name: "bash",
            status: .completed,
            output: .string(
                """
                diff --git a/NeoCode/AppStore.swift b/NeoCode/AppStore.swift
                --- a/NeoCode/AppStore.swift
                +++ b/NeoCode/AppStore.swift
                @@ -10,2 +10,3 @@
                 let value = 1
                -let oldThing = 2
                +let newThing = 2
                +let extraThing = 3
                """
            )
        )

        let presentation = ToolCallPresentation(toolCall: toolCall)

        #expect(presentation.items.count == 1)

        guard case .diff(let file) = presentation.items[0].content else {
            Issue.record("Expected bash output to render as a diff")
            return
        }

        #expect(file.displayPath == "NeoCode/AppStore.swift")
        #expect(file.hunks.first?.oldRange == DiffLineRange(start: 10, count: 2))
        #expect(file.hunks.first?.newRange == DiffLineRange(start: 10, count: 3))
    }

    @Test func nonDiffToolFallsBackToTextItem() {
        let toolCall = ChatMessage.ToolCall(
            name: "read",
            status: .completed,
            detail: "read completed\n{\n  \"path\" : \"README.md\"\n}"
        )

        let presentation = ToolCallPresentation(toolCall: toolCall)

        #expect(presentation.items.count == 1)

        guard case .text(let text) = presentation.items[0].content else {
            Issue.record("Expected non-diff tool to render as text")
            return
        }

        #expect(text.contains("read completed"))
    }

    @Test func bashWarningsDoNotPretendToBeDiffs() {
        let toolCall = ChatMessage.ToolCall(
            name: "bash",
            status: .completed,
            output: .string("--- xcodebuild: WARNING: Using the first of multiple matching destinations:")
        )

        let presentation = ToolCallPresentation(toolCall: toolCall)

        #expect(presentation.items.count == 1)

        guard case .text(let text) = presentation.items[0].content else {
            Issue.record("Expected warning output to stay as plain text")
            return
        }

        #expect(text.contains("xcodebuild: WARNING"))
    }
}
