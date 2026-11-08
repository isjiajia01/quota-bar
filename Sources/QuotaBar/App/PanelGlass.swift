import AppKit
import SwiftUI

/// A deliberately narrow MenuBarExtra workaround. Never traverses or removes content views.
/// On the tested OS SwiftUI inserts three full-size graphics views *before* our background host.
/// One is opaque. A clear NSWindow alone cannot expose the desktop through that layer.
struct PanelGlass: NSViewRepresentable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func makeNSView(context: Context) -> GlassView { GlassView() }
    func updateNSView(_ view: GlassView, context: Context) {
        view.solid = reduceTransparency || contrast == .increased
        view.reconcile()
    }
    static func dismantleNSView(_ view: GlassView, coordinator: ()) { view.detach() }

    final class GlassView: NSView {
        private let effect = NSVisualEffectView()
        private let tint = NSView()
        private var suppressed: [(view: NSView, alpha: CGFloat)] = []
        private weak var attachedWindow: NSWindow?
        private var oldOpaque = false
        private var oldBackground: NSColor?
        private var reconciling = false
        var solid = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.cornerRadius = Radius.page
            layer?.masksToBounds = true
            effect.blendingMode = .behindWindow
            effect.material = Palette.panelMaterial
            effect.state = .active
            effect.isEmphasized = false
            effect.autoresizingMask = [.width, .height]
            addSubview(effect)
            tint.wantsLayer = true
            tint.autoresizingMask = [.width, .height]
            addSubview(tint)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            attachedWindow = window
            oldOpaque = window.isOpaque
            oldBackground = window.backgroundColor
            NotificationCenter.default.addObserver(self, selector: #selector(windowShown),
                name: NSWindow.didBecomeKeyNotification, object: window)
            reconcile()
            // SwiftUI may not have inserted all backing siblings during viewDidMoveToWindow.
            DispatchQueue.main.async { [weak self] in self?.reconcile() }
        }
        @objc private func windowShown() {
            reconcile()
            DispatchQueue.main.async { [weak self] in self?.reconcile() }
        }
        override func layout() {
            super.layout()
            effect.frame = bounds
            tint.frame = bounds
            reconcile()
        }
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            reconcile()
        }

        func reconcile() {
            guard !reconciling else { return }
            reconciling = true
            defer { reconciling = false }
            guard let window = attachedWindow, let root = window.contentView else { return }
            var host: NSView = self
            while let parent = host.superview, parent !== root { host = parent }
            guard host.superview === root,
                  String(describing: type(of: window)).hasPrefix("MenuBarExtraWindow"),
                  let index = root.subviews.firstIndex(where: { $0 === host }) else {
                restoreBacking()
                showSolid()
                return
            }
            let prefix = Array(root.subviews[..<index])
            // Fail closed on unrecognised OS layouts. No broad recursive hiding, KVC, or swizzling.
            guard Self.isSupportedBacking(prefix, bounds: root.bounds) else {
                restoreBacking()
                showSolid()
                return
            }
            for view in suppressed where !prefix.contains(where: { $0 === view.view }) {
                view.view.alphaValue = view.alpha
            }
            suppressed = prefix.map { view in
                (view, suppressed.first(where: { $0.view === view })?.alpha ?? view.alphaValue)
            }
            for entry in suppressed { entry.view.alphaValue = 0 }
            #if DEBUG
            if CommandLine.arguments.contains("--fixture"),
               let path = ProcessInfo.processInfo.environment["QUOTABAR_GLASS_DIAGNOSTICS"] {
                let summary = "backing=\(prefix.count) effect=\(effect.blendingMode.rawValue) solid=\(solid) reduceTransparency=\(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) window=\(window.frame)\n"
                    + root.subviews.map { "\(type(of: $0)) frame=\($0.frame) alpha=\($0.alphaValue)\n" }.joined()
                try? summary.write(toFile: path, atomically: true, encoding: .utf8)
            }
            #endif
            window.isOpaque = false
            window.backgroundColor = .clear
            if solid {
                showSolid()
            } else {
                effect.isHidden = false
                tint.isHidden = false
                effectiveAppearance.performAsCurrentDrawingAppearance {
                    tint.layer?.backgroundColor = NSColor(Palette.panelGlassTint).cgColor
                }
                layer?.backgroundColor = NSColor.clear.cgColor
            }
        }

        static func isSupportedBacking(_ views: [NSView], bounds: NSRect) -> Bool {
            views.count == 3 && views[1].layer?.backgroundColor?.alpha == 1 && views.allSatisfy {
                String(describing: type(of: $0)) == "_NSGraphicsView" && $0.frame == bounds
            }
        }
        private func showSolid() {
            effect.isHidden = true
            tint.isHidden = true
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
        }
        private func restoreBacking() {
            for entry in suppressed { entry.view.alphaValue = entry.alpha }
            suppressed.removeAll()
            attachedWindow?.isOpaque = oldOpaque
            attachedWindow?.backgroundColor = oldBackground
        }
        func detach() {
            NotificationCenter.default.removeObserver(self)
            restoreBacking()
            attachedWindow = nil
        }
        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
