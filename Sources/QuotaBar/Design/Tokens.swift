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
    static let bar: CGFloat = 3
    static let chip: CGFloat = 4
    static let skeleton: CGFloat = 3
    /// Provider card (extend 2026-11-08).
    static let card: CGFloat = 10
    static let page: CGFloat = 10
}

/// Fixed component metrics. Panel width/scroll cap are app choices, not OS limits.
enum Metric {
    static let panelWidth: CGFloat = 392
    /// Max height of the scrolling provider list. Header + footer add ~76 pt.
    static let scrollCap: CGFloat = 500
    /// Usage bar: thickness, fixed row width (hero meters flex), pace tick overhang/width.
    static let barHeight: CGFloat = 6
    static let barWidth: CGFloat = 56
    static let paceTickWidth: CGFloat = 2
    static let paceTickOverhang: CGFloat = 3
    static let valueColumn: CGFloat = 38
    /// Shared trailing column: row window label and hero-meter reset time. Wraps, never ellipsized.
    static let trailingColumn: CGFloat = 80
    /// Hero meter window label column (wraps).
    static let meterLabelColumn: CGFloat = 58
    static let rowHeight: CGFloat = 22
    static let dot: CGFloat = 6
    static let guide: CGFloat = 1
    static let hairline: CGFloat = 1
    static let cardStroke: CGFloat = 0.5
    static let glassRim: CGFloat = 1
    static let iconButton: CGFloat = 24
    static let skeletonLine: CGFloat = 8
    static let skeletonWidths: [CGFloat] = [120, 150, 100]
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
    /// The one dominant number per provider. Rounded, monospaced digits.
    static let heroValue = Font.system(.title, design: .rounded).weight(.semibold).monospacedDigit()
    static let heroUnit = Font.system(.title3, design: .rounded).weight(.medium)
    static let meta = Font.subheadline                                 // "Most left · …", window column
    static let row = Font.callout                                      // account label
    static let rowValue = Font.system(.callout, design: .rounded).weight(.semibold).monospacedDigit()
    static let meterLabel = Font.subheadline.weight(.medium)
    static let detail = Font.caption.monospacedDigit()                 // resets, amounts, projection
    static let chip = Font.caption.monospacedDigit()
    static let stateTitle = Font.body.weight(.semibold)
    static let stateIcon = Font.title2
}

/// Colour roles — "Spruce" palette (extend 2026-11-08, colour pass).
/// One signature hue (spruce, a desaturated blue-green) carries the healthy state and tints every
/// neutral surface (track, chip, card, stroke, separator). Low = ochre, critical = muted crimson.
/// Every custom role is a dynamic colour with light / dark / Increase Contrast (light, dark) variants.
/// Text stays on labelColor so it inherits system contrast handling.
enum Palette {
    typealias RGBA = (Int, Int, Int, Double)

    static let textPrimary = Color.primary
    /// Opaque spruce inks: translucent labelColor loses contrast over a variable desktop backdrop.
    static let textSecondary = dynamic(light: (0x2E, 0x37, 0x34, 1), dark: (0xD2, 0xDC, 0xD8, 1))
    /// Glyphs and incidental marks only (chevrons, separators-in-text). Never body text.
    static let textTertiary = Color.primary.opacity(0.42)

    // Neutrals, tinted toward spruce so surfaces and the signature hue read as one family.
    static let track = dynamic(light: (0x1C, 0x3E, 0x3A, 0.09), dark: (0xC4, 0xE6, 0xDF, 0.10),
                               hcLight: (0x1C, 0x3E, 0x3A, 0.24), hcDark: (0xC4, 0xE6, 0xDF, 0.26))
    static let chipFill = dynamic(light: (0x1C, 0x3E, 0x3A, 0.065), dark: (0xC4, 0xE6, 0xDF, 0.06),
                                  hcLight: (0x1C, 0x3E, 0x3A, 0.14), hcDark: (0xC4, 0xE6, 0xDF, 0.18))
    static let separator = dynamic(light: (0x1C, 0x3E, 0x3A, 0.11), dark: (0xDC, 0xF0, 0xEB, 0.09),
                                   hcLight: (0x00, 0x00, 0x00, 0.40), hcDark: (0xFF, 0xFF, 0xFF, 0.40))
    static let skeleton = track
    static let stateBackdrop = Color(nsColor: .windowBackgroundColor)

    /// One AppKit behind-window material for the entire panel. Cards do not own blur surfaces.
    static let panelMaterial: NSVisualEffectView.Material = .hudWindow
    /// A single contrast scrim over the window blur; still transmits underlying colour/structure.
    static let panelGlassTint = dynamic(light: (0xFF, 0xFF, 0xFF, 0.38), dark: (0x00, 0x00, 0x00, 0.50))
    static let cardGlassTint = dynamic(light: (0xF2, 0xF9, 0xF7, 0.30), dark: (0x12, 0x2C, 0x29, 0.30))
    /// Glass sheen: light catching the top of the pane, fading out by mid-height. Glass state only.
    static let cardSheenTop = dynamic(light: (0xFF, 0xFF, 0xFF, 0.55), dark: (0xFF, 0xFF, 0xFF, 0.13))
    static let cardSheenBottom = dynamic(light: (0xFF, 0xFF, 0xFF, 0.0), dark: (0xFF, 0xFF, 0xFF, 0.0))
    static let cardSheen = LinearGradient(colors: [cardSheenTop, cardSheenBottom], startPoint: .top, endPoint: .center)
    /// Glass rim: bright specular edge, brighter at the top.
    static let glassRimTop = dynamic(light: (0xFF, 0xFF, 0xFF, 0.95), dark: (0xFF, 0xFF, 0xFF, 0.34))
    static let glassRimBottom = dynamic(light: (0x1C, 0x3E, 0x3A, 0.14), dark: (0xFF, 0xFF, 0xFF, 0.07))
    static let glassRim = LinearGradient(colors: [glassRimTop, glassRimBottom], startPoint: .top, endPoint: .bottom)

    /// Provider card solid fallback (Reduce Transparency / Increase Contrast): a quiet tonal lift on the panel
    /// material. Edge (both modes): a hairline lighter at the top in dark (catches light), firmer at the bottom
    /// in light. No shadows.
    static let cardFill = dynamic(light: (0xFB, 0xFD, 0xFC, 0.74), dark: (0xD8, 0xEC, 0xE7, 0.05),
                                  hcLight: (0xFF, 0xFF, 0xFF, 0.92), hcDark: (0xD8, 0xEC, 0xE7, 0.08))
    static let cardStrokeTop = dynamic(light: (0x1C, 0x3E, 0x3A, 0.07), dark: (0xE6, 0xF6, 0xF2, 0.13),
                                       hcLight: (0x00, 0x00, 0x00, 0.45), hcDark: (0xFF, 0xFF, 0xFF, 0.45))
    static let cardStrokeBottom = dynamic(light: (0x1C, 0x3E, 0x3A, 0.12), dark: (0xE6, 0xF6, 0xF2, 0.055),
                                          hcLight: (0x00, 0x00, 0x00, 0.45), hcDark: (0xFF, 0xFF, 0xFF, 0.45))
    static let cardStroke = LinearGradient(colors: [cardStrokeTop, cardStrokeBottom], startPoint: .top, endPoint: .bottom)

    /// Even-pace tick: near-black ink (light) / near-white (dark); the 3 pt overhang above and below the
    /// bar sits on the card, so the tick reads on every fill and on the bare track.
    static let paceTick = dynamic(light: (0x16, 0x24, 0x22, 0.80), dark: (0xF1, 0xF6, 0xF4, 0.88),
                                  hcLight: (0x00, 0x00, 0x00, 1), hcDark: (0xFF, 0xFF, 0xFF, 1))

    /// Level colours, solid (glyphs, dots). Spruce · ochre · crimson.
    static let healthy = dynamic(light: (0x2E, 0x7D, 0x72, 1), dark: (0x58, 0xB4, 0xA5, 1),
                                 hcLight: (0x1D, 0x5E, 0x55, 1), hcDark: (0x7F, 0xD6, 0xC7, 1))
    static let low = dynamic(light: (0xB0, 0x78, 0x26, 1), dark: (0xD6, 0xA0, 0x4C, 1),
                             hcLight: (0x86, 0x55, 0x0C, 1), hcDark: (0xF0, 0xC0, 0x6E, 1))
    static let critical = dynamic(light: (0xB4, 0x45, 0x4B, 1), dark: (0xDC, 0x6E, 0x69, 1),
                                  hcLight: (0x92, 0x24, 0x2E, 1), hcDark: (0xFF, 0x96, 0x8E, 1))

    /// Bar fills: a gentle same-hue gradient, deeper at the start of the fill and softer at its tip.
    /// Under Increase Contrast both stops collapse to the solid HC level colour.
    static let healthyFill = barFill(
        start: dynamic(light: (0x38, 0x85, 0x79, 1), dark: (0x37, 0x92, 0x85, 1),
                       hcLight: (0x1D, 0x5E, 0x55, 1), hcDark: (0x7F, 0xD6, 0xC7, 1)),
        end: dynamic(light: (0x5A, 0xA6, 0x98, 1), dark: (0x5C, 0xB6, 0xA7, 1),
                     hcLight: (0x1D, 0x5E, 0x55, 1), hcDark: (0x7F, 0xD6, 0xC7, 1)))
    static let lowFill = barFill(
        start: dynamic(light: (0xA6, 0x6E, 0x1E, 1), dark: (0xA8, 0x76, 0x2E, 1),
                       hcLight: (0x86, 0x55, 0x0C, 1), hcDark: (0xF0, 0xC0, 0x6E, 1)),
        end: dynamic(light: (0xCB, 0x96, 0x40, 1), dark: (0xDE, 0xAA, 0x56, 1),
                     hcLight: (0x86, 0x55, 0x0C, 1), hcDark: (0xF0, 0xC0, 0x6E, 1)))
    static let criticalFill = barFill(
        start: dynamic(light: (0xA6, 0x38, 0x42, 1), dark: (0xAE, 0x47, 0x4D, 1),
                       hcLight: (0x92, 0x24, 0x2E, 1), hcDark: (0xFF, 0x96, 0x8E, 1)),
        end: dynamic(light: (0xC9, 0x5E, 0x5F, 1), dark: (0xE2, 0x7A, 0x72, 1),
                     hcLight: (0x92, 0x24, 0x2E, 1), hcDark: (0xFF, 0x96, 0x8E, 1)))
    static let unknownFill = barFill(start: track, end: track)

    /// Level *text*: ochre / crimson inks tuned for >= 4.5:1 on cards in both appearances.
    static let lowText = dynamic(light: (0x4D, 0x30, 0x02, 1), dark: (0xF6, 0xCC, 0x84, 1),
                                 hcLight: (0x4D, 0x30, 0x02, 1), hcDark: (0xF6, 0xCC, 0x84, 1))
    static let criticalText = dynamic(light: (0x78, 0x20, 0x2B, 1), dark: (0xFF, 0xB8, 0xAC, 1),
                                      hcLight: (0x80, 0x18, 0x24, 1), hcDark: (0xFF, 0xAE, 0xA6, 1))

    private static func barFill(start: Color, end: Color) -> LinearGradient {
        LinearGradient(colors: [start, end], startPoint: .leading, endPoint: .trailing)
    }

    private static func dynamic(light: RGBA, dark: RGBA, hcLight: RGBA? = nil, hcDark: RGBA? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua,
                                                    .accessibilityHighContrastDarkAqua,
                                                    .accessibilityHighContrastAqua])
            let c: RGBA
            switch match {
            case .accessibilityHighContrastDarkAqua: c = hcDark ?? dark
            case .accessibilityHighContrastAqua: c = hcLight ?? light
            case .darkAqua: c = dark
            default: c = light
            }
            return NSColor(srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255,
                           alpha: CGFloat(c.3))
        })
    }
}

/// Max two curves. Both are dropped under Reduce Motion.
enum Motion {
    static let disclosure = Animation.snappy(duration: 0.18)
    static let value = Animation.easeOut(duration: 0.25)

    static func disclosure(reduced: Bool) -> Animation? { reduced ? nil : disclosure }
}
