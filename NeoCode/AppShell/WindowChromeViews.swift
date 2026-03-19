import AppKit
import SwiftUI

struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragRegionView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return self
    }
}

struct WindowChromeConfigurator: NSViewRepresentable {
    let updateService: AppUpdateService

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = NSSize(width: 980, height: 600)
        updateService.attach(to: window)
    }
}
