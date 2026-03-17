import SwiftUI

struct WorkspaceToolIconView: View {
    let tool: WorkspaceTool
    var size: CGFloat = 16

    private let service = WorkspaceToolService()

    var body: some View {
        Group {
            if let image = service.icon(for: tool) {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: tool.fallbackSystemImage)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
            }
        }
        .frame(width: size, height: size)
    }
}
