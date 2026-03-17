import AppKit
import SwiftUI

@MainActor
final class TitlebarUpdateAccessoryController {
    private weak var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    func attach(to window: NSWindow, updateService: AppUpdateService) {
        guard self.window !== window else { return }

        detach()

        guard let zoomButton = window.standardWindowButton(.zoomButton),
              let titlebarContainer = zoomButton.superview
        else {
            return
        }

        let hostingView = NSHostingView(rootView: AnyView(WindowTitlebarUpdateButton().environment(updateService)))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.required, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titlebarContainer.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: zoomButton.trailingAnchor, constant: 8),
            hostingView.centerYAnchor.constraint(equalTo: zoomButton.centerYAnchor),
            hostingView.heightAnchor.constraint(equalToConstant: 20),
        ])

        self.window = window
        self.hostingView = hostingView
    }

    private func detach() {
        hostingView?.removeFromSuperview()
        hostingView = nil
        window = nil
    }
}
