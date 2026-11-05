import AppKit
import SwiftUI
import Testing
@testable import QuotaBar

/// ImageRenderer render tests: every state × light/dark renders non-nil, at panel width,
/// within the height bound. Set QUOTABAR_SNAPSHOT_DIR to also write PNGs for review.
/// Offscreen renders do not prove material, focus, scroll or status-item behaviour.
@MainActor @Suite struct SnapshotTests {
    static let scale: CGFloat = 2
    /// Header + footer + scroll cap, with slack.
    static let maxHeight = Metric.scrollCap + 120

    @Test(arguments: StatePage.allCases, [ColorScheme.dark, .light])
    func rendersState(page: StatePage, scheme: ColorScheme) throws {
        let image = try render(page: page, scheme: scheme, mode: .snapshot)
        #expect(image.width == Int(Metric.panelWidth * Self.scale))
        let height = CGFloat(image.height) / Self.scale
        #expect(height > 60)
        #expect(height <= Self.maxHeight, "panel must stay bounded")
        #expect(!isBlank(image))
    }

    /// Uncapped render of every row, for visual review only.
    @Test func rendersFullListForReview() throws {
        for scheme in [ColorScheme.dark, .light] {
            let image = try render(page: .expanded, scheme: scheme, mode: .snapshotFull, suffix: "-full")
            #expect(CGFloat(image.height) / Self.scale > Self.maxHeight, "fixture should overflow the cap")
        }
    }

    @Test func contentIsTallerThanEmpty() throws {
        let content = try render(page: .content, scheme: .dark, mode: .snapshot, write: false)
        let empty = try render(page: .empty, scheme: .dark, mode: .snapshot, write: false)
        #expect(content.height > empty.height)
    }

    private func render(page: StatePage, scheme: ColorScheme, mode: PanelRenderMode,
                        suffix: String = "", write: Bool = true) throws -> CGImage {
        let view = StatePageFrame { page.panel() }
            .environment(\.colorScheme, scheme)
            .environment(\.panelRenderMode, mode)
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        renderer.proposedSize = ProposedViewSize(width: Metric.panelWidth, height: nil)
        let image = try #require(renderer.cgImage, "ImageRenderer returned nil for \(page)")
        if write, let dir = ProcessInfo.processInfo.environment["QUOTABAR_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appending(path: "\(page.rawValue)-\(scheme == .dark ? "dark" : "light")\(suffix).png")
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        return image
    }

    private func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return true }
        let length = CFDataGetLength(data)
        let first = bytes[0]
        var i = 0
        while i < length { if bytes[i] != first { return false }; i += 97 }
        return true
    }
}
