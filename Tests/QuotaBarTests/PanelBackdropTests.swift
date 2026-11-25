import AppKit
import Testing
@testable import QuotaBar

@MainActor @Suite struct PanelBackdropTests {
    @Test func accessibilitySettingsAlwaysChooseSolid() {
        for liquid in [true, false] {
            #expect(PanelBackdrop.kind(reduceTransparency: true, increaseContrast: false, liquidGlassAvailable: liquid) == .solid)
            #expect(PanelBackdrop.kind(reduceTransparency: false, increaseContrast: true, liquidGlassAvailable: liquid) == .solid)
        }
    }

    @Test func liquidGlassWhenAvailableElseVibrancy() {
        #expect(PanelBackdrop.kind(reduceTransparency: false, increaseContrast: false, liquidGlassAvailable: true) == .liquidGlass)
        #expect(PanelBackdrop.kind(reduceTransparency: false, increaseContrast: false, liquidGlassAvailable: false) == .vibrancy)
    }

    @Test func everyBackdropHostsTheContentAndFallbacksRoundTheCorners() {
        for kind in [PanelBackdrop.Kind.liquidGlass, .vibrancy, .solid] {
            let content = NSView()
            let backdrop = PanelBackdrop.make(kind, content: content)
            #expect(content.isDescendant(of: backdrop))
            if kind != .liquidGlass {
                #expect(backdrop.layer?.cornerRadius == Radius.panel)
                #expect(backdrop.layer?.masksToBounds == true)
            }
        }
    }
}
