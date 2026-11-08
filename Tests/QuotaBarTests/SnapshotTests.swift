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
        if page == .content || page == .expanded { assertCardInsets(image) }
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
            assertCardInsets(image)
        }
    }

    /// Pace / projection / credit facts (synthetic, example.com only): fast burn on the hero's 5h
    /// window (projection line), a row with a projection, low + critical levels, credit amounts with
    /// expiry, an old read. Written as `pace-<scheme>.png`.
    @Test func rendersPaceAndCredits() throws {
        let now = StatePage.now
        let h: TimeInterval = 3_600
        let accounts = [
            Account(provider: "p", name: "Claude Code", plan: "max", user: "alpha@example.com",
                    windows: [QuotaWindow(name: "5 hours", used: 72, remaining: 28, resetsAt: now.addingTimeInterval(3 * h)),
                              QuotaWindow(name: "7 days", used: 30, remaining: 70, resetsAt: now.addingTimeInterval(120 * h))],
                    readAt: now.addingTimeInterval(-60)),
            Account(provider: "p", name: "Claude Code", plan: "max", user: "beta@example.com",
                    windows: [QuotaWindow(name: "5 hours", used: 40, remaining: 60, resetsAt: now.addingTimeInterval(4 * h)),
                              QuotaWindow(name: "7 days", used: 75, remaining: 25, resetsAt: now.addingTimeInterval(110 * h))],
                    readAt: now.addingTimeInterval(-60)),
            Account(provider: "c", name: "WorkBuddy AI", plan: "Free plan", user: "gamma@example.com",
                    windows: [QuotaWindow(name: "Credits", used: 25.7, remaining: 74.3, resetsAt: now.addingTimeInterval(400 * h),
                                          display: "64.3 / 250", unit: "credits"),
                              QuotaWindow(name: "Extra credits", used: 92, remaining: 8, display: "276 / 300",
                                          unit: "credits", runsOutAt: now.addingTimeInterval(170 * h))],
                    readAt: now.addingTimeInterval(-3 * h)),
        ]
        let snap = PanelSnapshot(accounts: accounts, fetchedAt: StatePage.fetchedAt)
        for scheme in [ColorScheme.dark, .light] {
            let view = StatePageFrame { QuotaPanel(state: .content(snap)).environment(\.panelNow, now) }
            let image = try render(view: view, name: "pace", scheme: scheme, mode: .snapshotFull)
            #expect(image.width == Int(Metric.panelWidth * Self.scale))
        }
    }

    /// Row window pair (synthetic, example.com only): every row stacks 5h above 7d with its own
    /// pace tick and percent; an unreported slot keeps a neutral track and "—"; a credit-only
    /// account keeps the single-line layout. Written as `rows-<scheme>.png`.
    @Test func rendersRowWindowPairs() throws {
        let now = StatePage.now
        let h: TimeInterval = 3_600
        let accounts = [
            Account(provider: "p", name: "Claude Code", plan: "max", user: "alpha@example.com",
                    windows: [QuotaWindow(name: "5 hours", used: 72, remaining: 28, resetsAt: now.addingTimeInterval(3 * h)),
                              QuotaWindow(name: "7 days", used: 30, remaining: 70, resetsAt: now.addingTimeInterval(120 * h))],
                    readAt: now.addingTimeInterval(-60)),
            Account(provider: "p", name: "Claude Code", plan: "max", user: "beta@example.com",
                    windows: [QuotaWindow(name: "5 hours", used: 38, remaining: 62, resetsAt: now.addingTimeInterval(4 * h)),
                              QuotaWindow(name: "7 days", used: 78, remaining: 22, resetsAt: now.addingTimeInterval(100 * h))],
                    readAt: now.addingTimeInterval(-60)),
            // 5h only → the 7d slot is a placeholder.
            Account(provider: "p", name: "Claude Code", plan: "max", user: "gamma@example.com",
                    windows: [QuotaWindow(name: "5 hours", used: 52, remaining: 48, resetsAt: now.addingTimeInterval(2 * h))]),
            // Credit-only → single-line row, unchanged.
            Account(provider: "p", name: "Claude Code", plan: "max", user: "delta@example.com",
                    windows: [QuotaWindow(name: "Credits", used: 80, remaining: 20, resetsAt: now.addingTimeInterval(400 * h),
                                          display: "50 / 250", unit: "credits")]),
            // 7d only and nearly empty → expanded group shows the missing 5h slot.
            Account(provider: "p", name: "Claude Code", plan: "max", user: "epsilon@example.com",
                    windows: [QuotaWindow(name: "7 days", used: 97, remaining: 3, resetsAt: now.addingTimeInterval(60 * h))]),
            // Qualified pool names: the row keeps the tightest 5h and the tightest 7d.
            Account(provider: "g", name: "Antigravity", plan: "Google AI Pro", user: "zeta@example.com",
                    windows: [QuotaWindow(name: "Gemini · 7 days", remaining: 66, resetsAt: now.addingTimeInterval(150 * h)),
                              QuotaWindow(name: "Gemini · 5 hours", remaining: 99, resetsAt: now.addingTimeInterval(1 * h)),
                              QuotaWindow(name: "Claude & GPT · 7 days", remaining: 100, resetsAt: now.addingTimeInterval(150 * h)),
                              QuotaWindow(name: "Claude & GPT · 5 hours", remaining: 100, resetsAt: now.addingTimeInterval(1 * h))]),
            Account(provider: "g", name: "Antigravity", plan: "Google AI Pro", user: "eta@example.com",
                    windows: [QuotaWindow(name: "Gemini · 7 days", remaining: 91, resetsAt: now.addingTimeInterval(150 * h)),
                              QuotaWindow(name: "Gemini · 5 hours", remaining: 12, resetsAt: now.addingTimeInterval(1 * h)),
                              QuotaWindow(name: "Claude & GPT · 7 days", remaining: 100, resetsAt: now.addingTimeInterval(150 * h)),
                              QuotaWindow(name: "Claude & GPT · 5 hours", remaining: 84, resetsAt: now.addingTimeInterval(1 * h))]),
        ]
        let snap = PanelSnapshot(accounts: accounts, fetchedAt: StatePage.fetchedAt)
        for scheme in [ColorScheme.dark, .light] {
            let view = StatePageFrame {
                QuotaPanel(state: .content(snap), initiallyExpanded: ["p", "g"])
                    .environment(\.panelNow, now)
            }
            let image = try render(view: view, name: "rows", scheme: scheme, mode: .snapshotFull)
            #expect(image.width == Int(Metric.panelWidth * Self.scale))
            assertCardInsets(image)
        }
    }

    /// Card layers over an unblurred synthetic backdrop: composition stress only, NOT the real panel glass.
    /// ImageRenderer cannot draw AppKit's behind-window effect. Native captures supply material evidence.
    @Test func rendersGlassOverColourfulBackdrop() throws {
        for scheme in [ColorScheme.dark, .light] {
            let view = StatePage.content.panel()
                .background(LinearGradient(colors: Self.backdrop, startPoint: .topLeading, endPoint: .bottomTrailing))
            let image = try render(view: view, name: "glass-backdrop", scheme: scheme, mode: .snapshot)
            #expect(image.width == Int(Metric.panelWidth * Self.scale))
        }
    }

    /// Reduce Transparency and Increase Contrast fall back to the solid `cardFill` (`rt-*` / `ic-*`, content page).
    @Test func rendersSolidCardFallbacks() throws {
        for scheme in [ColorScheme.dark, .light] {
            let rt = StatePageFrame { StatePage.content.panel() }.environment(\._accessibilityReduceTransparency, true)
            _ = try render(view: rt, name: "rt-content", scheme: scheme, mode: .snapshot)
            let ic = StatePageFrame { StatePage.content.panel() }.environment(\._colorSchemeContrast, .increased)
            _ = try render(view: ic, name: "ic-content", scheme: scheme, mode: .snapshot)
        }
        // Not rendered over the colourful backdrop: cardFill is translucent by design and relies on the system
        // making the panel background opaque under Reduce Transparency (live-only behaviour).
    }

    /// Synthetic wallpaper stand-in (test-only colours): white, yellow, cyan, magenta, blue, black.
    static let backdrop: [Color] = [
        Color(red: 1, green: 1, blue: 1), Color(red: 1, green: 0.9, blue: 0), Color(red: 0, green: 0.9, blue: 1),
        Color(red: 1, green: 0.18, blue: 0.58), Color(red: 0.12, green: 0.25, blue: 1), Color(red: 0, green: 0, blue: 0),
    ]

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

    private func assertCardInsets(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        let y = Int(80 * Self.scale) // below the first card's rounded corner; clear of its text
        let outer = Int((Space.m / 2) * Self.scale)
        let inside = Int((Space.m + Space.xxs) * Self.scale)
        let left = rep.colorAt(x: outer, y: y)
        let right = rep.colorAt(x: image.width - 1 - outer, y: y)
        #expect(left == right, "both side gutters must have the same untouched backdrop")
        #expect(left != rep.colorAt(x: inside, y: y), "card surface must start inside its 12pt gutter")
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
