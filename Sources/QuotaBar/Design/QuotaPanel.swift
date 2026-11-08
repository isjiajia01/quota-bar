import SwiftUI

/// Panel template. Inputs: `PanelState` + refresh flag + hide-emails preference.
/// Local UI state: which providers' nearly-empty groups are open.
struct QuotaPanel: View {
    var state: PanelState
    var isRefreshing: Bool = false
    var hideEmails: Bool = false
    var actions = PanelActions()
    @State private var expanded: Set<String>

    init(state: PanelState, isRefreshing: Bool = false, hideEmails: Bool = false,
         actions: PanelActions = PanelActions(), initiallyExpanded: Set<String> = []) {
        self.state = state
        self.isRefreshing = isRefreshing
        self.hideEmails = hideEmails
        self.actions = actions
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(state: state, isRefreshing: isRefreshing, hideEmails: hideEmails, actions: actions)
            Hairline()
            content
            Hairline()
            PanelFooter(action: actions.openMagpie)
                .padding(.vertical, Space.xs)
        }
        .frame(width: Metric.panelWidth)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            LoadingPlaceholder()
        case .empty:
            StateMessage(symbol: "tray", title: "No accounts yet",
                         detail: "Add an account in Magpie to see its quota here.",
                         actionTitle: "Open Magpie", action: actions.openMagpie)
        case .error(let issue):
            StateMessage(symbol: "bolt.horizontal.circle", title: "Can't reach Magpie",
                         detail: issue.detail, actionTitle: "Retry", action: actions.refresh)
        case .stale(let snapshot, _), .content(let snapshot):
            BoundedScroll {
                ProviderList(providers: Presenter.providers(from: snapshot.accounts, hideEmails: hideEmails),
                             expanded: $expanded)
            }
        }
    }
}

struct ProviderList: View {
    var providers: [ProviderVM]
    @Binding var expanded: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(providers) { provider in
                ProviderSection(provider: provider, isExpanded: Binding(
                    get: { expanded.contains(provider.id) },
                    set: { if $0 { expanded.insert(provider.id) } else { expanded.remove(provider.id) } }
                ))
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.m)
    }
}
