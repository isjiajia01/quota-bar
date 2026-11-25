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
    /// Live panel outline (Liquid Glass and its fallbacks). Larger than the card radius so the
    /// 12 pt-inset cards read as nested inside the panel's corner.
    static let panel: CGFloat = 16
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
    static let iconButton: CGFloat = 24
    static let skeletonLine: CGFloat = 8
    static let skeletonWidths: [CGFloat] = [120, 150, 100]
    static let stateIcon: CGFloat = 24
    static let disabledOpacity: Double = 0.4
    /// Gap between the status item's bottom edge and the panel's top edge.
    static let panelMenuBarGap: CGFloat = 4
    /// Minimum distance from the panel to the edges of the screen's visible frame.
    static let panelScreenInset: CGFloat = 8
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

/// Colour roles — "Provider accents" (extend 2026-11-25; replaces the single-hue "Spruce" pass).
/// Each provider has its own accent (header dot, card wash, bar fill); neutrals are plain greys.
/// Low = amber number, critical = muted crimson bar and number.
/// Every custom role is a dynamic colour with light / dark / Increase Contrast (light, dark) variants.
/// Text stays on labelColor so it inherits system contrast handling.
enum Palette {
    typealias RGBA = (Int, Int, Int, Double)

    static let textPrimary = Color.primary
    /// Opaque neutral inks: translucent labelColor loses contrast over a variable desktop backdrop.
    static let textSecondary = dynamic(light: (0x36, 0x38, 0x3D, 1), dark: (0xD4, 0xD6, 0xDB, 1))
    /// Glyphs and incidental marks only (chevrons, separators-in-text). Never body text.
    static let textTertiary = Color.primary.opacity(0.42)

    // Neutrals: plain system-grey family. Colour belongs to the provider accents and the warning levels.
    static let track = dynamic(light: (0x3C, 0x3C, 0x43, 0.10), dark: (0xEB, 0xEB, 0xF5, 0.12),
                               hcLight: (0x3C, 0x3C, 0x43, 0.26), hcDark: (0xEB, 0xEB, 0xF5, 0.28))
    static let chipFill = dynamic(light: (0x3C, 0x3C, 0x43, 0.07), dark: (0xEB, 0xEB, 0xF5, 0.08),
                                  hcLight: (0x3C, 0x3C, 0x43, 0.15), hcDark: (0xEB, 0xEB, 0xF5, 0.18))
    static let separator = dynamic(light: (0x3C, 0x3C, 0x43, 0.12), dark: (0xEB, 0xEB, 0xF5, 0.10),
                                   hcLight: (0x00, 0x00, 0x00, 0.40), hcDark: (0xFF, 0xFF, 0xFF, 0.40))
    static let skeleton = track
    static let stateBackdrop = Color(nsColor: .windowBackgroundColor)

    /// Vibrancy fallback (pre-macOS 26): one AppKit behind-window material for the whole panel.
    static let panelMaterial: NSVisualEffectView.Material = .hudWindow
    /// A single contrast scrim over the vibrancy blur; still transmits underlying colour/structure.
    static let panelGlassTint = dynamic(light: (0xFF, 0xFF, 0xFF, 0.38), dark: (0x00, 0x00, 0x00, 0.50))
    /// Liquid Glass tint (macOS 26+, `NSGlassEffectView.tintColor`). Lighter than the vibrancy scrim:
    /// the regular glass style already adds its own legibility layer. Re-measure contrast natively.
    static let panelLiquidTint = dynamic(light: (0xFF, 0xFF, 0xFF, 0.22), dark: (0x00, 0x00, 0x00, 0.28))
    /// Card on glass: one quiet neutral lift (no sheen, no gradient rim). The provider wash sits on top.
    static let cardGlassTint = dynamic(light: (0xFF, 0xFF, 0xFF, 0.42), dark: (0xFF, 0xFF, 0xFF, 0.06))
    /// Solid fallback card (Reduce Transparency / Increase Contrast).
    static let cardFill = dynamic(light: (0xFF, 0xFF, 0xFF, 0.80), dark: (0xFF, 0xFF, 0xFF, 0.06),
                                  hcLight: (0xFF, 0xFF, 0xFF, 0.95), hcDark: (0xFF, 0xFF, 0xFF, 0.10))
    /// One flat hairline edge for every card state.
    static let cardStroke = dynamic(light: (0x3C, 0x3C, 0x43, 0.10), dark: (0xFF, 0xFF, 0xFF, 0.09),
                                    hcLight: (0x00, 0x00, 0x00, 0.45), hcDark: (0xFF, 0xFF, 0xFF, 0.45))

    /// Even-pace tick: near-black ink (light) / near-white (dark); the 3 pt overhang above and below the
    /// bar sits on the card, so the tick reads on every fill and on the bare track.
    static let paceTick = dynamic(light: (0x1D, 0x1D, 0x1F, 0.80), dark: (0xF5, 0xF5, 0xF7, 0.88),
                                  hcLight: (0x00, 0x00, 0x00, 1), hcDark: (0xFF, 0xFF, 0xFF, 1))

    // MARK: Provider accents (extend 2026-11-25)

    /// One accent per provider: the header dot, the card's top wash and every healthy/low bar fill.
    /// Known provider IDs map to a hue near their brand; any other ID takes a stable pick from
    /// `fallbackAccents` (FNV-1a of the ID, so it never changes between launches). Critical overrides
    /// the accent with crimson; low keeps the accent bar and turns the number amber.
    static func accent(forProvider id: String) -> ProviderAccent {
        if let known = knownAccents[id.lowercased()] { return known }
        var hash: UInt32 = 0x811C_9DC5
        for byte in id.lowercased().utf8 { hash = (hash ^ UInt32(byte)) &* 0x0100_0193 }
        return fallbackAccents[Int(hash % UInt32(fallbackAccents.count))]
    }

    /// Default outside a provider card (never a warning hue).
    static var neutralAccent: ProviderAccent { graphite }

    private static let knownAccents: [String: ProviderAccent] = [
        "claude": terracotta,
        "codex": jade,
        "antigravity": googleBlue,
        "workbuddy-ai": violet,
        "workbuddy": plum,
        "zcode": indigo,
        "opencode-go": graphite,
        "opencode-zen-free": graphite,
    ]
    /// Distinct from crimson/amber so an accent never reads as a warning.
    private static let fallbackAccents: [ProviderAccent] = [sky, plum, jade, indigo, violet, graphite]

    private static let terracotta = providerAccent(
        "terracotta", light: (0xC1, 0x5F, 0x3C), lightTip: (0xDE, 0x8B, 0x69), dark: (0xD9, 0x77, 0x57), darkTip: (0xF0, 0xA0, 0x80),
        hcLight: (0x93, 0x40, 0x22), hcDark: (0xFF, 0xB8, 0x9C))
    private static let jade = providerAccent(
        "jade", light: (0x0E, 0x8A, 0x6C), lightTip: (0x3A, 0xB2, 0x90), dark: (0x16, 0xA3, 0x80), darkTip: (0x52, 0xD2, 0xAE),
        hcLight: (0x05, 0x63, 0x4C), hcDark: (0x7E, 0xE8, 0xC8))
    private static let googleBlue = providerAccent(
        "googleBlue", light: (0x2F, 0x6E, 0xDB), lightTip: (0x5F, 0x95, 0xEE), dark: (0x40, 0x7D, 0xE8), darkTip: (0x84, 0xAF, 0xF9),
        hcLight: (0x18, 0x4C, 0xAB), hcDark: (0xAA, 0xC8, 0xFF))
    private static let violet = providerAccent(
        "violet", light: (0x74, 0x50, 0xD4), lightTip: (0x9B, 0x82, 0xE9), dark: (0x82, 0x66, 0xDE), darkTip: (0xB8, 0xA2, 0xF8),
        hcLight: (0x52, 0x2F, 0xA0), hcDark: (0xCB, 0xBA, 0xFF))
    private static let plum = providerAccent(
        "plum", light: (0xA3, 0x45, 0x92), lightTip: (0xC7, 0x74, 0xB6), dark: (0xBB, 0x5C, 0xA9), darkTip: (0xE3, 0x95, 0xD3),
        hcLight: (0x7A, 0x24, 0x6B), hcDark: (0xF5, 0xB4, 0xE8))
    private static let indigo = providerAccent(
        "indigo", light: (0x48, 0x52, 0xC4), lightTip: (0x73, 0x7B, 0xE0), dark: (0x58, 0x62, 0xD6), darkTip: (0x9A, 0xA1, 0xF6),
        hcLight: (0x2D, 0x35, 0x99), hcDark: (0xB6, 0xBB, 0xFF))
    private static let sky = providerAccent(
        "sky", light: (0x0F, 0x82, 0xA8), lightTip: (0x3F, 0xA8, 0xCB), dark: (0x1E, 0x9C, 0xC4), darkTip: (0x66, 0xC9, 0xE8),
        hcLight: (0x05, 0x5E, 0x7C), hcDark: (0x95, 0xDE, 0xF5))
    private static let graphite = providerAccent(
        "graphite", light: (0x55, 0x5C, 0x66), lightTip: (0x7E, 0x85, 0x8F), dark: (0x82, 0x89, 0x93), darkTip: (0xB8, 0xBF, 0xC9),
        hcLight: (0x2D, 0x32, 0x38), hcDark: (0xD6, 0xDB, 0xE1))

    typealias RGB = (Int, Int, Int)
    private static func providerAccent(_ name: String, light: RGB, lightTip: RGB, dark: RGB, darkTip: RGB,
                                       hcLight: RGB, hcDark: RGB) -> ProviderAccent {
        func c(_ v: RGB, _ a: Double = 1) -> RGBA { (v.0, v.1, v.2, a) }
        let hcL = c(hcLight), hcD = c(hcDark)
        return ProviderAccent(
            name: name,
            solid: dynamic(light: c(light), dark: c(darkTip), hcLight: hcL, hcDark: hcD),
            fill: barFill(start: dynamic(light: c(light), dark: c(dark), hcLight: hcL, hcDark: hcD),
                          end: dynamic(light: c(lightTip), dark: c(darkTip), hcLight: hcL, hcDark: hcD)),
            wash: dynamic(light: c(light, 0.10), dark: c(dark, 0.16), hcLight: c(light, 0), hcDark: c(dark, 0)))
    }

    /// Warning colours, solid (glyphs, dots). Amber · crimson.
    static let low = dynamic(light: (0xB0, 0x78, 0x26, 1), dark: (0xD6, 0xA0, 0x4C, 1),
                             hcLight: (0x86, 0x55, 0x0C, 1), hcDark: (0xF0, 0xC0, 0x6E, 1))
    static let critical = dynamic(light: (0xB4, 0x45, 0x4B, 1), dark: (0xDC, 0x6E, 0x69, 1),
                                  hcLight: (0x92, 0x24, 0x2E, 1), hcDark: (0xFF, 0x96, 0x8E, 1))

    /// Critical bar fill: crimson overrides the provider accent. Under Increase Contrast both stops
    /// collapse to the solid HC colour.
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

/// A provider's colour set (see `Palette.accent(forProvider:)`).
struct ProviderAccent: @unchecked Sendable {
    /// Token name (tests, diagnostics).
    var name: String
    /// Header dot.
    var solid: Color
    /// Bar fill (deeper start → softer tip).
    var fill: LinearGradient
    /// Card top wash, fading to clear by mid-card. Clear under Increase Contrast.
    var wash: Color
}
