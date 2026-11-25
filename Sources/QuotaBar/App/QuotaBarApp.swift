import AppKit
import SwiftUI

/// Menu-bar app. Live Magpie by default; `--fixture` (or QUOTABAR_SOURCE=fixture) reads the sample.
/// Data lives at app lifetime (QuotaStore); the panel's SwiftUI tree exists only while it is open
/// (App/PanelController.swift). Cadence: RefreshPolicy (60 s open · 5 min closed · backoff · paused asleep).
@MainActor
final class QuotaBarAppDelegate: NSObject, NSApplicationDelegate {
    private var store: QuotaStore?
    private var panel: PanelController?
    /// Held for the process: the Carbon handler keeps only an unretained pointer to it.
    private var hotKey: GlobalHotKey?
    private var activity: SystemActivityMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let useFixture = CommandLine.arguments.contains("--fixture")
            || ProcessInfo.processInfo.environment["QUOTABAR_SOURCE"] == "fixture"
        #if DEBUG
        // Fixture-only appearance override for material QA; never changes the user's system setting.
        if useFixture, let mode = ProcessInfo.processInfo.environment["QUOTABAR_FIXTURE_APPEARANCE"] {
            NSApplication.shared.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
        }
        #endif
        let store = QuotaStore(source: useFixture ? FixtureQuotaSource() : LiveQuotaSource())
        store.startAutoRefresh()  // immediate fetch, then RefreshPolicy.standard; Retry/⟳ on demand
        self.store = store
        activity = SystemActivityMonitor(store: store)

        // One action for both entry points: the panel footer and ⌘⇧M (App/GlobalHotKey.swift).
        let openMagpie = OpenMagpieAction()
        let panel = PanelController(store: store, openMagpie: openMagpie)
        self.panel = panel
        // Carbon hot key: no Accessibility permission. Registration failure is logged once
        // inside `register()` and the app continues without the shortcut.
        let hotKey = GlobalHotKey(action: { [weak panel] in
            panel?.close()
            openMagpie()
        })
        hotKey.register()
        self.hotKey = hotKey
    }
}

/// Pauses polling while the Mac sleeps, the displays are off, or the user session is switched out.
@MainActor
final class SystemActivityMonitor {
    private var tokens: [NSObjectProtocol] = []

    init(store: QuotaStore) {
        let center = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, RefreshPause, Bool)] = [
            (NSWorkspace.willSleepNotification, .systemSleep, true),
            (NSWorkspace.didWakeNotification, .systemSleep, false),
            (NSWorkspace.screensDidSleepNotification, .screensAsleep, true),
            (NSWorkspace.screensDidWakeNotification, .screensAsleep, false),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionInactive, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionInactive, false),
        ]
        tokens = pairs.map { name, reason, paused in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak store] _ in
                MainActor.assumeIsolated { store?.setPaused(reason, paused) }
            }
        }
    }
    // Lives for the process (held by the app delegate), so the observers are never removed.
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
