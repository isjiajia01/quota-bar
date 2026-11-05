import AppKit
import Carbon.HIToolbox
import os

/// Carbon identifiers for this app's one hot key: `'QBTR'` and id 1.
private let hotKeySignature: OSType = 0x51425452
private let hotKeyIdentifier: UInt32 = 1
private let hotKeyLog = Logger(subsystem: "page.isjia.quotabar", category: "hotkey")

/// Process-wide ⌘⇧M through Carbon's `RegisterEventHotKey`: it needs no Accessibility grant and
/// no event tap. A failed registration logs one line and is ignored — the app keeps running,
/// the panel's button still opens the page.
///
/// The Carbon handler is installed on the application event target, which dispatches on the main
/// thread, and it holds an **unretained** pointer to this object: the App layer keeps the instance
/// alive for the process (and it unregisters itself on `NSApplication.willTerminateNotification`).
@MainActor
final class GlobalHotKey: NSObject {
    private let action: @MainActor () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)),
                                               name: NSApplication.willTerminateNotification, object: nil)
    }

    /// Installs the handler, then registers the combination. Returns whether ⌘⇧M is live.
    @discardableResult
    func register() -> Bool {
        guard hotKey == nil, handler == nil else { return true }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), quotaBarHotKeyHandler, 1, &eventType,
                                            Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else {
            handler = nil
            hotKeyLog.error("Command-Shift-M unavailable: handler install returned \(installed, privacy: .public)")
            return false
        }

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: hotKeySignature, id: hotKeyIdentifier)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(cmdKey | shiftKey), identifier,
                                             GetApplicationEventTarget(), 0, &reference)
        guard registered == noErr, let reference else {
            hotKeyLog.error("Command-Shift-M unavailable: registration returned \(registered, privacy: .public)")
            removeHandler()
            return false
        }
        hotKey = reference
        return true
    }

    /// Releases the combination and the Carbon handler. Repeated calls are no-ops.
    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        removeHandler()
    }

    private func removeHandler() {
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        unregister()
    }

    fileprivate func perform() {
        action()
    }
}

/// Carbon callback: checks the event carries this hot key's id, then runs the action on the main
/// actor. `userData` is the owning `GlobalHotKey`, unretained (the App layer holds it).
private func quotaBarHotKeyHandler(_ call: EventHandlerCallRef?, _ event: EventRef?,
                                   _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var identifier = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &identifier)
    guard status == noErr, identifier.signature == hotKeySignature, identifier.id == hotKeyIdentifier else {
        return OSStatus(eventNotHandledErr)
    }

    let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { owner.perform() }  // application event target: main thread
    return noErr
}
