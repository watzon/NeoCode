import SwiftUI

struct MetaballOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart = Date()

    let size: CGFloat
    let renderScale: CGFloat
    let internalResolutionScale: CGFloat

    init(size: CGFloat, renderScale: CGFloat = 1.24, internalResolutionScale: CGFloat = 2) {
        self.size = size
        self.renderScale = renderScale
        self.internalResolutionScale = internalResolutionScale
    }

    var body: some View {
        let renderDiameter = size * renderScale
        let shaderDiameter = renderDiameter * internalResolutionScale

        Color.clear
            .frame(width: size, height: size)
            .overlay {
                shaderSurface(shaderDiameter: shaderDiameter)
                    .frame(width: shaderDiameter, height: shaderDiameter)
                    .scaleEffect(1 / internalResolutionScale)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

    @ViewBuilder
    private func shaderSurface(shaderDiameter: CGFloat) -> some View {
        if reduceMotion {
            shaderRect(time: 0, shaderDiameter: shaderDiameter)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                shaderRect(time: timeline.date.timeIntervalSince(animationStart), shaderDiameter: shaderDiameter)
            }
        }
    }

    private func shaderRect(time: TimeInterval, shaderDiameter: CGFloat) -> some View {
        Rectangle()
            .fill(.white)
            .colorEffect(
                ShaderLibrary.default.livingNodeOrb(
                    .float2(shaderDiameter, shaderDiameter),
                    .float(time)
                )
            )
            .drawingGroup(opaque: false, colorMode: .linear)
    }
}
