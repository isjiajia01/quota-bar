import AppKit
import SwiftUI

/// Menu-bar app. Live tunnel by default; `--fixture` (or QUOTABAR_SOURCE=fixture) reads the sample.
/// Data lives at app lifetime (not in the transient panel's `.task`): one refresh loop, 60 s cadence.
struct QuotaBarApp: App {
    @State private var store: QuotaStore
    @AppStorage("hideEmails") private var hideEmails = false

    init() {
        let useFixture = CommandLine.arguments.contains("--fixture")
            || ProcessInfo.processInfo.environment["QUOTABAR_SOURCE"] == "fixture"
        let store = QuotaStore(source: useFixture ? FixtureQuotaSource() : LiveQuotaSource())
        store.startAutoRefresh()  // immediate fetch, then every 60 s; Retry/⟳ refresh on demand
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            QuotaPanel(
                state: store.state,
                isRefreshing: store.isRefreshing,
                hideEmails: hideEmails,
                actions: PanelActions(
                    refresh: { store.refresh() },
                    openMagpie: { /* No gateway URL is specified in DESIGN.md, so this stays a no-op. */ },
                    setHideEmails: { hideEmails = $0 },
                    quit: { NSApplication.shared.terminate(nil) }
                )
            )
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
