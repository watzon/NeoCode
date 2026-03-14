import SwiftUI

enum NeoCodeTheme {
    static let canvas = Color(red: 0.03, green: 0.04, blue: 0.05)
    static let window = Color.clear
    static let sidebar = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let panel = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let panelRaised = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let panelSoft = Color.white.opacity(0.035)
    static let line = Color.white.opacity(0.08)
    static let lineStrong = Color.white.opacity(0.14)
    static let lineSoft = Color.white.opacity(0.05)
    static let textPrimary = Color(red: 0.94, green: 0.93, blue: 0.89)
    static let textSecondary = Color.white.opacity(0.62)
    static let textMuted = Color.white.opacity(0.4)
    static let accent = Color(red: 0.87, green: 0.66, blue: 0.34)
    static let accentDim = Color(red: 0.45, green: 0.34, blue: 0.18)
    static let success = Color(red: 0.35, green: 0.71, blue: 0.51)
    static let warning = Color(red: 0.80, green: 0.52, blue: 0.22)
}

extension Font {
    static let neoTitle = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let neoBody = Font.system(size: 13, weight: .regular, design: .default)
    static let neoMeta = Font.system(size: 11, weight: .medium, design: .default)
    static let neoAction = Font.system(size: 13, weight: .medium, design: .default)
    static let neoMono = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let neoMonoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
}
