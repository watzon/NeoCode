import AppKit
import SwiftUI

struct DeveloperPanelShortcutMonitor: NSViewRepresentable {
    let onOpen: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpen: onOpen)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.installMonitorIfNeeded()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onOpen = onOpen
        context.coordinator.installMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var onOpen: () -> Void
        private var monitor: Any?

        init(onOpen: @escaping () -> Void) {
            self.onOpen = onOpen
        }

        func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard self.matchesDeveloperPanelShortcut(event) else { return event }
                self.onOpen()
                return nil
            }
        }

        func removeMonitor() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func matchesDeveloperPanelShortcut(_ event: NSEvent) -> Bool {
            if event.keyCode == 111 {
                return true
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers == [.command, .option] else { return false }
            return event.charactersIgnoringModifiers?.lowercased() == "d"
        }
    }
}
