import AppKit
import Foundation
import os

/// Magpie's web entry point. DESIGN.md defines no URL, so this App-layer constant is the only
/// place it lives; the footer button and the ⌘⇧M hotkey both read it.
enum MagpieLink {
    static let url = URL(string: "https://magpie.isjia.page/")!
}

/// The impure edge: opens a page in Safari, or in the user's default browser when Safari is
/// not installed. Both paths activate the browser, which deactivates QuotaBar and lets the
/// system dismiss its transient panel (docs/PLATFORM_CONSTRAINTS.md › focus/dismissal:
/// `MenuBarExtra` exposes no public dismiss, so nothing here probes its window).
@MainActor
enum BrowserOpener {
    static let safariBundleIdentifier = "com.apple.Safari"

    /// The Safari-saved "magpie" web app (~/Applications/magpie.app).
    static let webAppBundleIdentifier = "com.apple.Safari.WebApp.73540D0F-FDAE-42D1-AB8E-68154FDA2761"

    static func open(_ url: URL) {
        let log = Logger(subsystem: "page.isjia.quotabar", category: "opener")
        let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: webAppBundleIdentifier)
        log.notice("open: webApp=\(found?.path ?? "nil", privacy: .public)")
        if let webApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: webAppBundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: webApp, configuration: configuration) { _, _ in }
            return
        }
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: safariBundleIdentifier) else {
            NSWorkspace.shared.open(url)  // no Safari: the default browser is the only handler left
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: configuration) { _, _ in }
    }
}

/// "Open Magpie" as one callable, emitted by the footer button and by the hotkey.
/// `open` is the injectable seam: tests record the URL instead of launching a browser.
struct OpenMagpieAction {
    var open: @MainActor (URL) -> Void = BrowserOpener.open

    @MainActor func callAsFunction() {
        open(MagpieLink.url)
    }
}
