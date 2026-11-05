import SwiftUI

/// Every panel state, driven by fixtures/quotas.sample.json. No network.
enum StatePage: String, CaseIterable, Identifiable, Sendable {
    case loading, empty, error, stale, content, expanded, hiddenEmails

    var id: String { rawValue }

    /// Fixed clocks so renders are deterministic.
    static let fetchedAt = QuotaDate.parse("2026-11-05T20:48:30Z")!
    static let now = QuotaDate.parse("2026-11-05T20:49:00Z")!

    @MainActor static let payload = FixtureQuotaSource.loadSync()

    @MainActor var panelState: PanelState {
        let snap = PanelSnapshot(accounts: Self.payload.data, fetchedAt: Self.fetchedAt)
        switch self {
        case .loading: return .loading
        case .empty: return .empty(fetchedAt: Self.fetchedAt)
        case .error: return .error(.unreachable)
        case .stale: return .stale(snap, .unreachable)
        case .content, .expanded, .hiddenEmails: return .content(snap)
        }
    }

    @MainActor var initiallyExpanded: Set<String> {
        self == .expanded ? Set(Self.payload.data.map(\.provider)) : []
    }

    var hideEmails: Bool { self == .hiddenEmails }

    @MainActor func panel() -> some View {
        QuotaPanel(state: panelState, hideEmails: hideEmails, initiallyExpanded: initiallyExpanded)
            .environment(\.panelNow, Self.now)
    }
}

/// Backdrop for state pages / snapshots. The live panel uses the system material instead.
struct StatePageFrame<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(Palette.stateBackdrop)
            .clipShape(RoundedRectangle(cornerRadius: Radius.page))
    }
}

/// `swift run QuotaBar --state-pages`: all states, dark row + light row.
/// `--state=<name>` limits the gallery to one page (dark + light).
struct StateGallery: View {
    var pages: [StatePage] = {
        let arg = CommandLine.arguments.first { $0.hasPrefix("--state=") }
        if let name = arg?.dropFirst("--state=".count), let page = StatePage(rawValue: String(name)) {
            return [page]
        }
        return StatePage.allCases
    }()

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: Space.l) {
                ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                    HStack(alignment: .top, spacing: Space.l) {
                        ForEach(pages) { page in
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(page.rawValue).font(TypeRole.meta).foregroundStyle(Palette.textSecondary)
                                StatePageFrame { page.panel() }
                                    .environment(\.colorScheme, scheme)
                            }
                        }
                    }
                }
            }
            .padding(Space.l)
        }
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
    }
}
