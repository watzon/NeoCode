import Foundation

struct SessionActivityState: Equatable, Sendable {
    let status: SessionStatus
    let liveActivity: OpenCodeSessionActivity?
    let isResponding: Bool
    let hasBlockingActivity: Bool
    let hasBufferedTextDeltas: Bool
    let hasLocalActivity: Bool
}
