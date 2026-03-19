import AppKit
import BeautifulMermaid
import Foundation
import OSLog
import SwiftUI

struct MarkdownMermaidBlockView: View {
    let source: String
    let fallbackSource: String
    let textColor: Color

    @SwiftUI.State private var phase: MermaidRenderPhase = .idle

    var body: some View {
        Group {
            switch phase {
            case .idle, .loading:
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 96)
                .padding(12)
            case .success(let image):
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            case .failure:
                MarkdownCodeBlockView(source: fallbackSource, textColor: textColor)
            }
        }
        .task(id: renderCacheKey) {
            await renderDiagramIfNeeded()
        }
    }

    private var renderCacheKey: NSString {
        let theme = MermaidThemeSpec.current
        return "\(theme.signature)\u{0}\(source)" as NSString
    }

    @MainActor
    private func renderDiagramIfNeeded() async {
        guard MarkdownRenderBudget.shouldRenderMermaid(source: source) else {
            MermaidDiagramLogger.logger.notice(
                "Skipping Mermaid render because the source exceeds the safe render budget"
            )
            phase = .failure
            return
        }

        if let cachedImage = MermaidDiagramCache.shared.object(forKey: renderCacheKey) {
            phase = .success(cachedImage)
            return
        }

        phase = .loading

        do {
            let image = try await MermaidDiagramRenderer.render(
                source: source,
                theme: .current
            )

            MermaidDiagramCache.shared.setObject(image, forKey: renderCacheKey)
            phase = .success(image)
        } catch {
            MermaidDiagramLogger.logger.error("Failed to render Mermaid diagram: \(error.localizedDescription, privacy: .public)")
            phase = .failure
        }
    }
}

private enum MermaidRenderPhase {
    case idle
    case loading
    case success(NSImage)
    case failure
}

private enum MermaidDiagramRenderer {
    static func render(source: String, theme: MermaidThemeSpec) async throws -> NSImage {
        try await Task.detached(priority: .utility) {
            guard let image = try MermaidRenderer.renderImage(
                source: source,
                theme: theme.diagramTheme,
                scale: 2.0
            ) else {
                throw MermaidRenderError.emptyImage
            }

            return image
        }.value
    }
}

private enum MermaidDiagramLogger {
    static let logger = Logger(subsystem: "tech.watzon.NeoCode", category: "MarkdownMermaid")
}

private final class MermaidDiagramCache {
    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()
}

private enum MermaidRenderError: LocalizedError {
    case emptyImage

    var errorDescription: String? {
        switch self {
        case .emptyImage:
            return "BeautifulMermaid returned no image"
        }
    }
}

private struct MermaidThemeSpec: Sendable {
    let background: String
    let foreground: String
    let line: String
    let accent: String
    let muted: String
    let surface: String
    let border: String

    static var current: MermaidThemeSpec {
        MermaidThemeSpec(
            background: NeoCodeTheme.panelRaisedColor.neoHexString ?? "#1F1F1F",
            foreground: NeoCodeTheme.textPrimaryColor.neoHexString ?? "#F2F2F2",
            line: NeoCodeTheme.lineStrongColor.neoHexString ?? "#5C5C5C",
            accent: NeoCodeTheme.accentColor.neoHexString ?? "#DDA858",
            muted: NeoCodeTheme.textMutedColor.neoHexString ?? "#8C8C8C",
            surface: NeoCodeTheme.panelColor.neoHexString ?? "#171717",
            border: NeoCodeTheme.lineColor.neoHexString ?? "#3C3C3C"
        )
    }

    nonisolated var signature: String {
        [background, foreground, line, accent, muted, surface, border].joined(separator: "|")
    }

    nonisolated var diagramTheme: DiagramTheme {
        DiagramTheme(
            background: NSColor(neoHex: background) ?? .textBackgroundColor,
            foreground: NSColor(neoHex: foreground) ?? .labelColor,
            line: NSColor(neoHex: line) ?? .separatorColor,
            accent: NSColor(neoHex: accent) ?? .systemOrange,
            muted: NSColor(neoHex: muted) ?? .secondaryLabelColor,
            surface: NSColor(neoHex: surface) ?? .controlBackgroundColor,
            border: NSColor(neoHex: border) ?? .separatorColor
        )
    }
}

private extension NSColor {
    var neoHexString: String? {
        guard let resolved = usingColorSpace(.deviceRGB) else { return nil }

        let red = Int(round(resolved.redComponent * 255))
        let green = Int(round(resolved.greenComponent * 255))
        let blue = Int(round(resolved.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
