import AppKit
import SwiftUI

/// Status item + transient panel, owned by the app instead of `MenuBarExtra`.
///
/// - The SwiftUI tree exists only while the panel is on screen: it is built on open and released
///   on close, so a closed panel holds no view memory and never re-renders on a background fetch.
/// - The window is ours, so the backdrop (App/PanelBackdrop.swift) is its content view; nothing in a
///   system-provided hierarchy is probed or hidden.
/// - Dismissal is explicit: the status item again, Escape, a click in another app, the app or the
///   panel losing focus, a Space change, or Open Magpie.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let statusItem: NSStatusItem
    private let store: QuotaStore
    private let openMagpie: OpenMagpieAction
    private var panel: QuotaPanelWindow?
    private weak var hosting: NSView?
    private var outsideClickMonitor: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var isOpen: Bool { panel != nil }

    init(store: QuotaStore, openMagpie: OpenMagpieAction) {
        self.store = store
        self.openMagpie = openMagpie
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            // DESIGN.md specifies no status-item summary: a template symbol, no text, no level colours.
            let image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent",
                                accessibilityDescription: "Quota left")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if isOpen { close(restoreFocus: true) } else { open() }
    }

    func open() {
        guard panel == nil, statusItem.button?.window != nil else { return }

        let hosting = PanelHostingView(rootView: PanelRoot(store: store, actions: actions()))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.onIntrinsicSizeChange = { [weak self] in
            // Defer: resizing the window inside SwiftUI's layout pass re-enters layout.
            DispatchQueue.main.async { self?.fitAndPlace() }
        }

        let panel = QuotaPanelWindow.make()
        panel.contentView = PanelBackdrop.make(content: hosting)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close(restoreFocus: true) }
        self.panel = panel
        self.hosting = hosting

        fitAndPlace()
        // Tooltips and keyboard focus need an active app, as with the system menu-bar extras.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        installDismissalTriggers()
        store.panelDidOpen()
    }

    /// `restoreFocus`: hand activation back to the previous app when the user dismissed the panel
    /// from QuotaBar itself (status item, Escape). Not when another app already took focus.
    func close(restoreFocus: Bool = false) {
        guard let panel else { return }
        self.panel = nil
        removeDismissalTriggers()
        panel.delegate = nil
        panel.onCancel = nil
        panel.orderOut(nil)
        panel.contentView = nil  // releases the SwiftUI tree
        statusItem.button?.highlight(false)
        store.panelDidClose()
        if restoreFocus, NSApp.isActive { NSApp.hide(nil) }
    }

    private func actions() -> PanelActions {
        PanelActions(
            refresh: { [store] in store.refresh() },
            openMagpie: { [weak self] in
                guard let self else { return }
                // The panel closes itself first; the browser then takes focus.
                self.close()
                self.openMagpie()
            },
            setHideEmails: { UserDefaults.standard.set($0, forKey: PanelRoot.hideEmailsKey) },
            quit: { NSApplication.shared.terminate(nil) }
        )
    }

    /// Sizes the panel to the SwiftUI content and hangs it under the status item, inside the
    /// visible frame of the status item's screen. The top edge stays put when the height changes.
    private func fitAndPlace() {
        guard let panel, let hosting, let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchor
        let size = hosting.fittingSize
        let inset = Metric.panelScreenInset

        let x = min(max(anchor.midX - size.width / 2, visible.minX + inset), visible.maxX - size.width - inset)
        let top = min(anchor.minY - Metric.panelMenuBarGap, visible.maxY)
        let height = min(size.height, top - visible.minY - inset)
        panel.setFrame(NSRect(x: x, y: top - height, width: size.width, height: height), display: true)
        panel.invalidateShadow()
    }

    // MARK: Dismissal

    func windowDidResignKey(_ notification: Notification) { close() }

    private func installDismissalTriggers() {
        // Clicks delivered to other apps (desktop, other windows, other status items). Mouse-down
        // global monitors need no Accessibility permission.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        let app = NotificationCenter.default
        observe(app, NSApplication.didResignActiveNotification)
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        observers.append((center, token))
    }

    private func removeDismissalTriggers() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}

/// Borderless, transparent, non-activating panel at pop-up-menu level. It can become key so that
/// Escape, the ⋯ menu and keyboard navigation reach the SwiftUI content.
final class QuotaPanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    static func make() -> QuotaPanelWindow {
        let panel = QuotaPanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.hidesOnDeactivate = false  // dismissal is handled by PanelController
        panel.collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        return panel
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Reports SwiftUI-driven size changes (the list's measured height) so the window can follow.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    var onIntrinsicSizeChange: (() -> Void)?

    required init(rootView: Content) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { nil }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onIntrinsicSizeChange?()
    }
}

/// The panel's SwiftUI root. Reads the store directly, so only an open panel observes it.
struct PanelRoot: View {
    static let hideEmailsKey = "hideEmails"
    let store: QuotaStore
    let actions: PanelActions
    @AppStorage(PanelRoot.hideEmailsKey) private var hideEmails = false

    var body: some View {
        QuotaPanel(state: store.state, isRefreshing: store.isRefreshing, hideEmails: hideEmails, actions: actions)
    }
}
