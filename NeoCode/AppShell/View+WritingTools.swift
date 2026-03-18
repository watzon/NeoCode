import SwiftUI

extension View {
    @ViewBuilder
    func neoWritingToolsDisabled() -> some View {
        if #available(macOS 15.0, *) {
            writingToolsBehavior(.disabled)
        } else {
            self
        }
    }
}
