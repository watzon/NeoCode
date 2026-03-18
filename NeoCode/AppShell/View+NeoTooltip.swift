import AppKit
import SwiftUI

private struct NeoTooltipModifier: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        content.overlay {
            if let text, !text.isEmpty {
                NeoTooltipView(text: text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

extension View {
    func neoTooltip(_ text: String?) -> some View {
        modifier(NeoTooltipModifier(text: text))
    }
}

private struct NeoTooltipView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipHostingView {
        let view = TooltipHostingView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: TooltipHostingView, context: Context) {
        nsView.toolTip = text
    }
}

private final class TooltipHostingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
