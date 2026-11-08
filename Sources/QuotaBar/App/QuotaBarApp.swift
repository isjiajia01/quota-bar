import AppKit
import SwiftUI

/// Menu-bar app. Live tunnel by default; `--fixture` (or QUOTABAR_SOURCE=fixture) reads the sample.
/// Data lives at app lifetime (not in the transient panel's `.task`): one refresh loop, 60 s cadence.
struct QuotaBarApp: App {
    @State private var store: QuotaStore
    @AppStorage("hideEmails") private var hideEmails = false
    /// One action for both entry points: the panel footer and ⌘⇧M (App/GlobalHotKey.swift).
    private let openMagpie: OpenMagpieAction
    /// Held for the process: the Carbon handler keeps only an unretained pointer to it.
    private let hotKey: GlobalHotKey

    init() {
        let useFixture = CommandLine.arguments.contains("--fixture")
            || ProcessInfo.processInfo.environment["QUOTABAR_SOURCE"] == "fixture"
        #if DEBUG
        // Fixture-only appearance override for material QA; never changes the user's system setting.
        if useFixture, let mode = ProcessInfo.processInfo.environment["QUOTABAR_FIXTURE_APPEARANCE"] {
            NSApplication.shared.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        }
        #endif
        let store = QuotaStore(source: useFixture ? FixtureQuotaSource() : LiveQuotaSource())
        store.startAutoRefresh()  // immediate fetch, then every 60 s; Retry/⟳ refresh on demand
        _store = State(initialValue: store)

        let openMagpie = OpenMagpieAction()
        self.openMagpie = openMagpie
        // Carbon hot key: no Accessibility permission. Registration failure is logged once
        // inside `register()` and the app continues without the shortcut.
        let hotKey = GlobalHotKey(action: { openMagpie() })
        hotKey.register()
        self.hotKey = hotKey
    }

    var body: some Scene {
        MenuBarExtra {
            QuotaPanel(
                state: store.state,
                isRefreshing: store.isRefreshing,
                hideEmails: hideEmails,
                actions: PanelActions(
                    refresh: { store.refresh() },
                    // No public dismiss exists for a MenuBarExtra panel, so the panel is not
                    // closed here: activating Safari deactivates QuotaBar and the system drops
                    // the transient panel (PLATFORM_CONSTRAINTS › focus and dismissal).
                    openMagpie: { openMagpie() },
                    setHideEmails: { hideEmails = $0 },
                    quit: { NSApplication.shared.terminate(nil) }
                )
            )
            .background(PanelGlass())
        } label: {
            // DESIGN.md specifies no status-item summary, so the label stays a template symbol
            // (no text, no level colours in the menu bar).
            Image(systemName: "gauge.with.dots.needle.33percent")
                .accessibilityLabel("Quota left")
        }
        .menuBarExtraStyle(.window)
    }
}

/// State-page viewer (regular window, Dock icon) for design review.
struct StatePagesApp: App {
    init() {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate()
        }
    }

    var body: some Scene {
        WindowGroup("QuotaBar — state pages") { StateGallery() }
            .defaultSize(Metric.galleryDefault)
    }
}
