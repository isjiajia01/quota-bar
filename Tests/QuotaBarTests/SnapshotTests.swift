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

    /// Long-text stress case (synthetic, example.com only): long identifiers middle-truncate,
    /// chips and numbers stay whole, long names/errors wrap. Written as `stress-<scheme>.png`.
    @Test func rendersLongTextStress() throws {
        let long = "a.really.long.local.part.for.layout.testing"
        let accounts = [
            Account(provider: "s1", name: "Extraordinarily Long Provider Name", plan: "Enterprise Unlimited Plan",
                    user: "\(long)@example.com",
                    windows: [QuotaWindow(name: "Claude & GPT · 5 hours", remaining: 22),
                              QuotaWindow(name: "Gemini 3.1 Flash Image (Preview)", remaining: 8)]),
            Account(provider: "s1", name: "Extraordinarily Long Provider Name", plan: "Starter Quota Trial",
                    user: "\(long).second@example.com",
                    windows: [QuotaWindow(name: "Free model tokens", remaining: 57)],
                    until: StatePage.now.addingTimeInterval(86_400 * 9)),
            Account(provider: "s1", name: "Extraordinarily Long Provider Name", plan: "Enterprise Unlimited Plan",
                    user: "\(long).third@example.com",
                    error: "\(long).third@example.com could not be refreshed because the upstream sign-in "
                         + "session was revoked by an administrator; sign in again in Magpie to restore it"),
        ]
        let snap = PanelSnapshot(accounts: accounts, fetchedAt: StatePage.fetchedAt)
        for scheme in [ColorScheme.dark, .light] {
            let view = StatePageFrame { QuotaPanel(state: .content(snap)).environment(\.panelNow, StatePage.now) }
            let image = try render(view: view, name: "stress", scheme: scheme, mode: .snapshotFull)
            #expect(image.width == Int(Metric.panelWidth * Self.scale))
        }
    }

    @Test func contentIsTallerThanEmpty() throws {
        let content = try render(page: .content, scheme: .dark, mode: .snapshot, write: false)
        let empty = try render(page: .empty, scheme: .dark, mode: .snapshot, write: false)
        #expect(content.height > empty.height)
    }

    private func render(page: StatePage, scheme: ColorScheme, mode: PanelRenderMode,
                        suffix: String = "", write: Bool = true) throws -> CGImage {
        try render(view: StatePageFrame { page.panel() }, name: page.rawValue, scheme: scheme,
                   mode: mode, suffix: suffix, write: write)
    }

    private func render(view content: some View, name: String, scheme: ColorScheme, mode: PanelRenderMode,
                        suffix: String = "", write: Bool = true) throws -> CGImage {
        let view = content
            .environment(\.colorScheme, scheme)
            .environment(\.panelRenderMode, mode)
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        renderer.proposedSize = ProposedViewSize(width: Metric.panelWidth, height: nil)
        let image = try #require(renderer.cgImage, "ImageRenderer returned nil for \(name)")
        if write, let dir = ProcessInfo.processInfo.environment["QUOTABAR_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: dir).appending(path: "\(name)-\(scheme == .dark ? "dark" : "light")\(suffix).png")
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
