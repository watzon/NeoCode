import Foundation
import Testing
@testable import NeoCode

@Suite(.serialized)
@MainActor
struct ComposerAuxiliaryTests {
    @Test func slashTriggerOnlyMatchesLeadingCommandToken() {
        let trigger = ComposerAuxiliaryParser.activeTrigger(in: "/rev")

        switch trigger?.kind {
        case .slashCommand: break
        default: Issue.record("Expected a slash command trigger")
        }
        #expect(trigger?.query == "rev")
        #expect(trigger?.replacementStart == 0)
        #expect(ComposerAuxiliaryParser.activeTrigger(in: "/review later") == nil)
    }

    @Test func fileMentionTriggerMatchesStartAndWhitespaceBoundaries() {
        let leading = ComposerAuxiliaryParser.activeTrigger(in: "@Conv")
        switch leading?.kind {
        case .fileMention: break
        default: Issue.record("Expected a file mention trigger at the start")
        }
        #expect(leading?.query == "Conv")
        #expect(leading?.replacementStart == 0)

        let trailing = ComposerAuxiliaryParser.activeTrigger(in: "Check @Conv")
        switch trailing?.kind {
        case .fileMention: break
        default: Issue.record("Expected a file mention trigger after whitespace")
        }
        #expect(trailing?.query == "Conv")
        #expect(trailing?.replacementStart == 6)
    }

    @Test func fileMentionTriggerIgnoresInlineAtSymbolsAndTrailingWhitespace() {
        #expect(ComposerAuxiliaryParser.activeTrigger(in: "email@example.com") == nil)
        #expect(ComposerAuxiliaryParser.activeTrigger(in: "Check @ file") == nil)

        switch ComposerAuxiliaryParser.activeTrigger(in: "Check @")?.kind {
        case .fileMention: break
        default: Issue.record("Expected a file mention trigger for a bare @ token")
        }
    }

    @Test func auxiliaryReplacementKeepsLeadingText() throws {
        let trigger = try #require(ComposerAuxiliaryParser.activeTrigger(in: "Inspect @Conv"))
        let replacement = trigger.applyingReplacement("@NeoCode/AppShell/ConversationViews.swift ", to: "Inspect @Conv")

        #expect(replacement.text == "Inspect @NeoCode/AppShell/ConversationViews.swift ")
        #expect(replacement.cursorLocation == replacement.text.count)
    }

    @Test func fileMentionReplacementCanInsertPlainPathText() throws {
        let trigger = try #require(ComposerAuxiliaryParser.activeTrigger(in: "Open @Conv"))
        let replacement = trigger.applyingReplacement("@NeoCode/AppShell/ConversationViews.swift ", to: "Open @Conv")

        #expect(replacement.text == "Open @NeoCode/AppShell/ConversationViews.swift ")
    }

    @Test func fileReferenceBuilderUsesLatestMentionRangePerPath() {
        let text = "Review @Docs/Guide.md and compare with @Docs/Guide.md"
        let references = ComposerPromptFileReferenceBuilder.build(
            text: text,
            projectPath: "/tmp/NeoCode",
            candidatePaths: ["Docs/Guide.md"]
        )

        let reference = references.first
        #expect(references.count == 1)
        #expect(reference?.requestURL == "file:///tmp/NeoCode/Docs/Guide.md")
        #expect(reference?.sourceText.value == "@Docs/Guide.md")
        #expect(reference?.sourceText.start == 39)
        #expect(reference?.sourceText.end == 53)
    }

    @Test func fileReferenceBuilderParsesManualMentionsAndTrimsTrailingPunctuation() {
        let mentions = ComposerPromptFileReferenceBuilder.matchedPaths(in: "See @Docs/Guide.md, then @src/App.swift!")

        #expect(mentions.count == 2)
        #expect(mentions[0].path == "Docs/Guide.md")
        #expect(mentions[0].sourceText.value == "@Docs/Guide.md")
        #expect(mentions[1].path == "src/App.swift")
        #expect(mentions[1].sourceText.value == "@src/App.swift")
    }

    @Test func fileSearchServiceResolvesManuallyTypedMentions() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let docsURL = rootURL.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        try "guide".write(to: docsURL.appendingPathComponent("Guide.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let references = await ProjectFileSearchService.shared.resolveFileReferences(
            in: rootURL.path,
            text: "Check @Docs/Guide.md before we continue."
        )

        #expect(references.count == 1)
        #expect(references[0].relativePath == "Docs/Guide.md")
        #expect(references[0].sourceText.value == "@Docs/Guide.md")
    }
}
