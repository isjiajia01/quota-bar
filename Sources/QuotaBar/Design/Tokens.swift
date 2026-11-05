import AppKit
import SwiftUI

// The ONLY file allowed to contain raw sizes, colours, radii, font sizes or durations.
// Enforced by scripts/lint-tokens.sh (and TokenLintTests).

/// Spacing scale (4 pt grid, plus a 2 pt hairline step).
enum Space {
    static let hair: CGFloat = 1
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
}

enum Radius {
    static let bar: CGFloat = 2
    static let chip: CGFloat = 4
    static let skeleton: CGFloat = 3
    static let page: CGFloat = 10
}

/// Fixed component metrics. Panel width/scroll cap are app choices, not OS limits.
enum Metric {
    static let panelWidth: CGFloat = 340
    /// Max height of the scrolling provider list. Header + footer add ~76 pt.
    static let scrollCap: CGFloat = 460
    static let ring: CGFloat = 28
    static let ringStroke: CGFloat = 3.5
    static let ringDash: [CGFloat] = [2, 3]
    static let barWidth: CGFloat = 44
    static let barHeight: CGFloat = 4
    static let valueColumn: CGFloat = 36
    static let windowColumn: CGFloat = 48
    /// Max width of the provider header value + window chips column.
    static let heroColumn: CGFloat = 150
    static let rowHeight: CGFloat = 22
    static let dot: CGFloat = 6
    static let guide: CGFloat = 1
    static let hairline: CGFloat = 1
    static let iconButton: CGFloat = 22
    static let skeletonLine: CGFloat = 8
    static let skeletonWidths: [CGFloat] = [180, 140, 200]
    static let stateIcon: CGFloat = 24
    static let disabledOpacity: Double = 0.4
    /// State-page viewer window (dev tool, not the panel).
    static let galleryDefault = CGSize(width: 800, height: 720)
}

/// Type roles. macOS text styles (fixed sizes; no Dynamic Type on macOS).
enum TypeRole {
    static let title = Font.headline                                   // "Quota left"
    static let status = Font.caption                                   // Updated HH:mm
    static let provider = Font.body.weight(.semibold)                  // provider name
    static let heroValue = Font.title3.weight(.semibold).monospacedDigit()
    static let meta = Font.subheadline                                 // "Most left · …", window column
    static let row = Font.callout                                      // account label
    static let rowValue = Font.callout.weight(.medium).monospacedDigit()
    static let chip = Font.caption.monospacedDigit()
    static let stateTitle = Font.body.weight(.semibold)
    static let stateIcon = Font.title2
}

/// Colour roles. Semantic/system colours so the panel follows appearance,
/// Increase Contrast and the system panel material.
enum Palette {
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let track = Color(nsColor: .quaternaryLabelColor)
    static let chipFill = Color(nsColor: .quaternaryLabelColor).opacity(0.5)
    static let separator = Color(nsColor: .separatorColor)
    static let skeleton = Color(nsColor: .quaternaryLabelColor)
    static let stateBackdrop = Color(nsColor: .windowBackgroundColor)

    /// Level fills (ring, bar, dots). System colours.
    static let healthy = Color(nsColor: .systemTeal)
    static let low = Color(nsColor: .systemOrange)
    static let critical = Color(nsColor: .systemRed)

    /// Level *text* colours, tuned for >= 4.5:1 on light panels (system red/orange are ~3.5:1).
    static let lowText = dynamic(light: (0x93, 0x58, 0x00), dark: (0xFF, 0x9F, 0x0A))
    static let criticalText = dynamic(light: (0xC0, 0x22, 0x2F), dark: (0xFF, 0x6B, 0x60))

    private static func dynamic(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
        })
    }
}

/// Max two curves. Both are dropped under Reduce Motion.
enum Motion {
    static let disclosure = Animation.snappy(duration: 0.18)
    static let value = Animation.easeOut(duration: 0.25)

    static func disclosure(reduced: Bool) -> Animation? { reduced ? nil : disclosure }
}
