import AppKit
import SwiftUI

if CommandLine.arguments.contains("--state-pages") {
    StatePagesApp.main()
} else {
    // Accessory: no Dock icon even under `swift run` (the packaged bundle also sets LSUIElement).
    let app = NSApplication.shared
    let delegate = QuotaBarAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
