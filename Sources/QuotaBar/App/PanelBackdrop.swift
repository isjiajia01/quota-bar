import AppKit

/// The panel's window background. QuotaBar owns its panel window (App/PanelController.swift), so
/// the backdrop is simply the window's content view: no system hierarchy is inspected or hidden.
///
/// - **liquidGlass** (macOS 26+): one `NSGlassEffectView`, the system's own Liquid Glass.
/// - **vibrancy** (older systems): one `.behindWindow` `NSVisualEffectView` plus the contrast tint.
/// - **solid**: Reduce Transparency or Increase Contrast — opaque `windowBackgroundColor`.
///
/// The choice is made when the panel opens; the panel is rebuilt on every open, so a changed
/// accessibility setting applies from the next open.
@MainActor
enum PanelBackdrop {
    enum Kind: Equatable, Sendable { case liquidGlass, vibrancy, solid }

    static func kind(reduceTransparency: Bool, increaseContrast: Bool, liquidGlassAvailable: Bool) -> Kind {
        if reduceTransparency || increaseContrast { return .solid }
        return liquidGlassAvailable ? .liquidGlass : .vibrancy
    }

    static var currentKind: Kind {
        let workspace = NSWorkspace.shared
        let liquid: Bool
        if #available(macOS 26, *) { liquid = true } else { liquid = false }
        return kind(reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                    increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                    liquidGlassAvailable: liquid)
    }

    /// Wraps `content` in the backdrop for `kind`. The returned view becomes the window's content view.
    static func make(_ kind: Kind = currentKind, content: NSView) -> NSView {
        switch kind {
        case .liquidGlass:
            if #available(macOS 26, *) {
                let glass = NSGlassEffectView()
                glass.cornerRadius = Radius.panel
                glass.tintColor = NSColor(Palette.panelLiquidTint)
                glass.contentView = content
                return glass
            }
            return vibrancy(content)
        case .vibrancy:
            return vibrancy(content)
        case .solid:
            let container = roundedContainer()
            NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            fill(container, with: content)
            return container
        }
    }

    private static func vibrancy(_ content: NSView) -> NSView {
        let container = roundedContainer()
        let effect = NSVisualEffectView()
        effect.blendingMode = .behindWindow
        effect.material = Palette.panelMaterial
        effect.state = .active
        effect.isEmphasized = false
        fill(container, with: effect)
        let tint = NSView()
        tint.wantsLayer = true
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            tint.layer?.backgroundColor = NSColor(Palette.panelGlassTint).cgColor
        }
        fill(container, with: tint)
        fill(container, with: content)
        return container
    }

    private static func roundedContainer() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = Radius.panel
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    private static func fill(_ container: NSView, with child: NSView) {
        child.frame = container.bounds
        child.autoresizingMask = [.width, .height]
        container.addSubview(child)
    }
}
