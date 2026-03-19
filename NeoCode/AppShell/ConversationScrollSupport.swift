import AppKit
import SwiftUI

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TranscriptScrollMetrics: Equatable {
    let contentOffsetY: CGFloat
    let contentHeight: CGFloat
    let visibleMaxY: CGFloat
}

extension View {
    func readHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self, perform: onChange)
    }
}
