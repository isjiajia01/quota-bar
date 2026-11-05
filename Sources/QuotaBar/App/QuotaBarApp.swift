import AppKit
import SwiftUI

/// Menu-bar app. `--fixture` (or QUOTABAR_SOURCE=fixture) reads the sample instead of the tunnel.
struct QuotaBarApp: App {
    @State private var store: QuotaStore
    @AppStorage("hideEmails") private var hideEmails = false

    init() {
        let useFixture = CommandLine.arguments.contains("--fixture")
            || ProcessInfo.processInfo.environment["QUOTABAR_SOURCE"] == "fixture"
        let store = QuotaStore(source: useFixture ? FixtureQuotaSource() : LiveQuotaSource())
        store.refresh()
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
                    openMagpie: { /* TODO(Main): Magpie bundle id / URL scheme not specified. */ },
                    setHideEmails: { hideEmails = $0 },
                    quit: { NSApplication.shared.terminate(nil) }
                )
            )
        } label: {
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
