import SwiftUI

struct MetaballOrb: View {
    private struct BeatEnvelope {
        var startedAt: Date = .distantPast
        var strength: CGFloat = 0
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var animationStart = Date()
    @State private var clickBeat = BeatEnvelope()
    @State private var reactiveBeat = BeatEnvelope()

    let size: CGFloat
    let animated: Bool
    let renderScale: CGFloat
    let internalResolutionScale: CGFloat
    let animationInterval: TimeInterval
    let intensity: CGFloat
    let pulse: CGFloat
    let warmth: CGFloat
    let reactsToClicks: Bool
    let beatTrigger: Int
    let beatStrength: CGFloat

    init(
        size: CGFloat,
        animated: Bool = true,
        renderScale: CGFloat = 1.12,
        internalResolutionScale: CGFloat = 1.2,
        animationInterval: TimeInterval = 1.0 / 24.0,
        intensity: CGFloat = 0,
        pulse: CGFloat = 0,
        warmth: CGFloat = 0,
        reactsToClicks: Bool = true,
        beatTrigger: Int = 0,
        beatStrength: CGFloat = 0
    ) {
        self.size = size
        self.animated = animated
        self.renderScale = renderScale
        self.internalResolutionScale = internalResolutionScale
        self.animationInterval = animationInterval
        self.intensity = intensity
        self.pulse = pulse
        self.warmth = warmth
        self.reactsToClicks = reactsToClicks
        self.beatTrigger = beatTrigger
        self.beatStrength = beatStrength
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
            .contentShape(Circle())
            .onTapGesture {
                guard reactsToClicks else { return }
                triggerTapPulse()
            }
            .onChange(of: beatTrigger) { _, _ in
                guard beatStrength > 0 else { return }
                reactiveBeat = BeatEnvelope(startedAt: .now, strength: beatStrength)
            }
    }

    @ViewBuilder
    private func shaderSurface(shaderDiameter: CGFloat) -> some View {
        if reduceMotion || !animated || scenePhase != .active {
            shaderRect(
                time: 0,
                shaderDiameter: shaderDiameter,
                visualizerPulse: pulse,
                visualizerWarmth: warmth,
                orbScale: 1 + pulse * 0.02 + intensity * 0.006
            )
        } else {
            TimelineView(.animation(minimumInterval: animationInterval)) { timeline in
                let pulseBoost = beatContribution(from: reactiveBeat, at: timeline.date) + beatContribution(from: clickBeat, at: timeline.date)
                let combinedPulse = min(1, max(0, pulse + pulseBoost))
                let combinedWarmth = min(1, max(0, warmth + pulseBoost * 0.42))
                let orbScale = 1 + combinedPulse * 0.03 + intensity * 0.008

                shaderRect(
                    time: timeline.date.timeIntervalSince(animationStart),
                    shaderDiameter: shaderDiameter,
                    visualizerPulse: combinedPulse,
                    visualizerWarmth: combinedWarmth,
                    orbScale: orbScale
                )
            }
        }
    }

    private func shaderRect(
        time: TimeInterval,
        shaderDiameter: CGFloat,
        visualizerPulse: CGFloat,
        visualizerWarmth: CGFloat,
        orbScale: CGFloat
    ) -> some View {
        Rectangle()
            .fill(.white)
            .colorEffect(
                ShaderLibrary.default.livingNodeOrb(
                    .float2(shaderDiameter, shaderDiameter),
                    .float(time),
                    .float(intensity),
                    .float(visualizerPulse),
                    .float(visualizerWarmth)
                )
            )
            .scaleEffect(orbScale)
    }

    private func triggerTapPulse() {
        clickBeat = BeatEnvelope(startedAt: .now, strength: 0.95)
    }

    private func beatContribution(from beat: BeatEnvelope, at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSince(beat.startedAt)
        guard elapsed >= 0, elapsed < 1.6, beat.strength > 0 else {
            return 0
        }

        let envelope = exp(-elapsed * 2.35)
        let primary = 0.56 + 0.44 * sin(elapsed * 9.5)
        let secondary = 0.70 + 0.30 * sin(elapsed * 14.0 + 0.9)
        return beat.strength * envelope * primary * secondary
    }
}

struct DraftReactiveMetaballOrb: View {
    let size: CGFloat
    let text: String
    let renderScale: CGFloat
    let internalResolutionScale: CGFloat
    let animationInterval: TimeInterval

    @State private var wakeLevel: CGFloat = 0
    @State private var wakeStartedAt: Date = .distantPast

    init(
        size: CGFloat,
        text: String,
        renderScale: CGFloat = 1.12,
        internalResolutionScale: CGFloat = 1.2,
        animationInterval: TimeInterval = 1.0 / 24.0
    ) {
        self.size = size
        self.text = text
        self.renderScale = renderScale
        self.internalResolutionScale = internalResolutionScale
        self.animationInterval = animationInterval
    }

    var body: some View {
        let normalizedCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let steadyIntensity = min(1, sqrt(CGFloat(normalizedCount)) / 10)
        let idleIntensity: CGFloat = 0.10
        let idlePulse: CGFloat = 0.035
        let basePulse = min(0.24, idlePulse + steadyIntensity * 0.10)
        let warmth = min(1, steadyIntensity * 0.42)

        TimelineView(.animation(minimumInterval: animationInterval)) { timeline in
            let wake = wakeContribution(at: timeline.date)

            MetaballOrb(
                size: size,
                renderScale: renderScale,
                internalResolutionScale: internalResolutionScale,
                animationInterval: animationInterval,
                intensity: min(1, idleIntensity + steadyIntensity * 0.46 + wake * 0.34),
                pulse: min(0.38, basePulse + wake * 0.16),
                warmth: min(1, warmth + wake * 0.14),
                beatTrigger: 0,
                beatStrength: 0
            )
        }
        .onChange(of: text) { oldValue, newValue in
            triggerTypingBeat(from: oldValue, to: newValue)
        }
    }

    private func triggerTypingBeat(from oldValue: String, to newValue: String) {
        guard oldValue != newValue else { return }

        let changeMagnitude = abs(newValue.count - oldValue.count)
        let wakeBoost = min(0.26, 0.07 + CGFloat(changeMagnitude) * 0.035)

        wakeLevel = min(1, wakeContribution(at: .now) + wakeBoost)
        wakeStartedAt = .now
    }

    private func wakeContribution(at date: Date) -> CGFloat {
        guard wakeLevel > 0 else { return 0 }

        let elapsed = date.timeIntervalSince(wakeStartedAt)
        guard elapsed > 0 else { return wakeLevel }
        return wakeLevel * CGFloat(exp(-elapsed * 0.55))
    }
}
