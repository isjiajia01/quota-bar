import AppKit
import Testing
@testable import QuotaBar

@MainActor @Suite struct PanelGlassTests {
    @Test func unknownWindowFallsBackWithoutHidingContentOrChangingOpacity() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Metric.panelWidth, height: 300),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let originalBackground = NSColor.windowBackgroundColor
        window.backgroundColor = originalBackground
        window.isOpaque = true
        let root = NSView(frame: NSRect(x: 0, y: 0, width: Metric.panelWidth, height: 300))
        window.contentView = root
        let sibling = NSView(frame: root.bounds)
        root.addSubview(sibling)
        let glass = PanelGlass.GlassView(frame: root.bounds)
        root.addSubview(glass)
        glass.reconcile()
        #expect(window.isOpaque)
        #expect(window.backgroundColor == originalBackground)
        #expect(sibling.alphaValue == 1)
        #expect(root.subviews.count == 2)
        #expect(glass.subviews.compactMap { $0 as? NSVisualEffectView }.count == 1)
        #expect(glass.subviews.compactMap { $0 as? NSVisualEffectView }.first?.isHidden == true)
        glass.detach()
        glass.removeFromSuperview()
        #expect(window.isOpaque)
        #expect(window.backgroundColor == originalBackground)
        window.close()
    }
}
