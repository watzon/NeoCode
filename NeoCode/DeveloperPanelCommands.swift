import SwiftUI

struct DeveloperPanelCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Developer") {
            Button("Open Developer Panel") {
                openWindow(id: DeveloperPanelView.windowID)
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }
}
