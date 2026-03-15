import AppKit
import SwiftUI

enum FloatingPanelDirection {
    case up
    case down
}

struct AnchoredFloatingPanelPresenter<Content: View>: NSViewRepresentable {
    let isPresented: Bool
    let direction: FloatingPanelDirection
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchorView = nsView
        context.coordinator.update(
            isPresented: isPresented,
            direction: direction,
            onDismiss: onDismiss,
            content: AnyView(content())
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    final class Coordinator {
        weak var anchorView: NSView?
        private let hostingController = NSHostingController(rootView: AnyView(EmptyView()))
        private var panel: FloatingPanel?
        private var localMonitor: Any?
        private var onDismiss: (() -> Void)?

        func update(
            isPresented: Bool,
            direction: FloatingPanelDirection,
            onDismiss: @escaping () -> Void,
            content: AnyView
        ) {
            guard let anchorView else {
                dismiss()
                return
            }

            self.onDismiss = onDismiss
            if isPresented {
                hostingController.rootView = content
                presentIfNeeded(from: anchorView)
                updateFrame(from: anchorView, direction: direction)
            } else {
                dismiss()
            }
        }

        func dismiss() {
            removeMonitor()
            if let panel,
               let parent = panel.parent {
                parent.removeChildWindow(panel)
            }
            panel?.orderOut(nil)
            panel = nil
        }

        private func dismissAndNotify() {
            dismiss()
            onDismiss?()
        }

        private func presentIfNeeded(from anchorView: NSView) {
            if panel == nil {
                let panel = FloatingPanel(
                    contentRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: true
                )
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.hasShadow = false
                panel.level = .floating
                panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
                panel.hidesOnDeactivate = true
                panel.ignoresMouseEvents = false
                panel.contentView = hostingController.view
                self.panel = panel
                installMonitor()
            }

            if let panel,
               let window = anchorView.window,
               panel.parent !== window {
                window.addChildWindow(panel, ordered: .above)
            }

            panel?.orderFrontRegardless()
            panel?.makeKey()
        }

        private func installMonitor() {
            guard localMonitor == nil else { return }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self,
                      let panel
                else {
                    return event
                }

                if event.window === panel || isEventInsideAnchorView(event) {
                    return event
                }

                if event.window !== panel {
                    dismissAndNotify()
                }
                return event
            }
        }

        private func removeMonitor() {
            guard let localMonitor else { return }
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        private func isEventInsideAnchorView(_ event: NSEvent) -> Bool {
            guard let anchorView,
                  event.window === anchorView.window
            else {
                return false
            }

            let pointInAnchor = anchorView.convert(event.locationInWindow, from: nil)
            return anchorView.bounds.contains(pointInAnchor)
        }

        private func updateFrame(from anchorView: NSView, direction: FloatingPanelDirection) {
            guard let panel,
                  let window = anchorView.window
            else {
                return
            }

            hostingController.view.layoutSubtreeIfNeeded()
            let fittingSize = hostingController.view.fittingSize
            hostingController.view.frame = CGRect(origin: .zero, size: fittingSize)

            let anchorFrameInWindow = anchorView.convert(anchorView.bounds, to: nil)
            let anchorFrameOnScreen = window.convertToScreen(anchorFrameInWindow)
            let panelOrigin = CGPoint(x: anchorFrameOnScreen.minX, y: panelOriginY(for: direction, anchorFrameOnScreen: anchorFrameOnScreen, panelHeight: fittingSize.height))

            panel.setFrame(CGRect(origin: panelOrigin, size: fittingSize), display: true)
        }

        private func panelOriginY(
            for direction: FloatingPanelDirection,
            anchorFrameOnScreen: CGRect,
            panelHeight: CGFloat
        ) -> CGFloat {
            switch direction {
            case .up:
                return anchorFrameOnScreen.maxY + 6
            case .down:
                return anchorFrameOnScreen.minY - 6 - panelHeight
            }
        }
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
