import Foundation

/// A successful fetch, retained separately from the last attempt's failure.
struct PanelSnapshot: Sendable, Equatable {
    var accounts: [Account]
    var fetchedAt: Date
}

/// Transport-level failure (never a single account's `error`).
enum TransportIssue: Sendable, Equatable {
    case unreachable
    case timedOut
    case http(Int)
    case malformed
    case other(String)

    var detail: String {
        switch self {
        case .unreachable: "Magpie isn't reachable on 127.0.0.1:13425. Is the SSH tunnel up?"
        case .timedOut: "Magpie didn't answer in time."
        case .http(let code): "Magpie answered HTTP \(code)."
        case .malformed: "Magpie sent data QuotaBar can't read."
        case .other(let text): text
        }
    }
}

/// The only data input the panel takes. Disclosure (`expanded`) is local UI state,
/// passed separately as `initiallyExpanded`; see `StatePage.expanded`.
enum PanelState: Sendable, Equatable {
    case loading
    case empty(fetchedAt: Date)
    case error(TransportIssue)
    case stale(PanelSnapshot, TransportIssue)
    case content(PanelSnapshot)

    var snapshot: PanelSnapshot? {
        switch self {
        case .stale(let s, _), .content(let s): s
        default: nil
        }
    }
}

/// Actions the panel emits. Nothing else leaves the UI.
struct PanelActions {
    var refresh: @MainActor () -> Void = {}
    var openMagpie: @MainActor () -> Void = {}
    var setHideEmails: @MainActor (Bool) -> Void = { _ in }
    var quit: @MainActor () -> Void = {}
}
