import SwiftUI

/// Header: title, quiet status line (replaces the old red banner), refresh, ⋯ menu.
struct PanelHeader: View {
    var state: PanelState
    var isRefreshing: Bool
    var hideEmails: Bool
    var actions: PanelActions
    @Environment(\.panelRenderMode) private var mode
    @Environment(\.timeZone) private var tz

    var body: some View {
        HStack(alignment: .center, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text("Quota left").font(TypeRole.title).foregroundStyle(Palette.textPrimary)
                StatusLine(state: state, isRefreshing: isRefreshing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(symbol: "arrow.clockwise", label: retryLabel) { actions.refresh() }
                .disabled(isRefreshing)
                .opacity(isRefreshing ? Metric.disabledOpacity : 1)
            menu
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
    }

    private var retryLabel: String {
        switch state {
        case .stale, .error: "Retry"
        default: "Refresh"
        }
    }

    @ViewBuilder private var menu: some View {
        let glyph = Image(systemName: "ellipsis.circle").foregroundStyle(Palette.textSecondary)
            .frame(width: Metric.iconButton, height: Metric.iconButton)
        if mode == .interactive {
            Menu {
                Toggle("Hide emails", isOn: Binding(get: { hideEmails }, set: { actions.setHideEmails($0) }))
                Divider()
                Button("Quit QuotaBar") { actions.quit() }.keyboardShortcut("q")
            } label: { glyph }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
        } else {
            glyph
        }
    }
}

/// "Updated HH:mm" · stale: "Updated HH:mm · couldn't refresh" with a small amber glyph.
struct StatusLine: View {
    var state: PanelState
    var isRefreshing: Bool
    @Environment(\.timeZone) private var tz

    var body: some View {
        HStack(spacing: Space.xs) {
            if case .stale = state {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.low)
            }
            Text(text)
        }
        .font(TypeRole.status)
        // Stale: amber text as well as the glyph, so "couldn't refresh" is not colour-only or easy to miss.
        .foregroundStyle(isStale ? Palette.lowText : Palette.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .help(help)
    }

    private var isStale: Bool { if case .stale = state { true } else { false } }

    private var text: String {
        if isRefreshing, case .loading = state { return "Loading…" }
        let refreshing = isRefreshing ? " · refreshing…" : ""
        switch state {
        case .loading: return "Loading…"
        case .empty(let at): return "Updated \(Fmt.clock(at, tz: tz))\(refreshing)"
        case .content(let s): return "Updated \(Fmt.clock(s.fetchedAt, tz: tz))\(refreshing)"
        case .stale(let s, _): return "Updated \(Fmt.clock(s.fetchedAt, tz: tz)) · couldn't refresh"
        case .error: return isRefreshing ? "Retrying…" : "Not connected"
        }
    }

    private var help: String {
        switch state {
        case .stale(_, let issue), .error(let issue): issue.detail
        default: ""
        }
    }
}

struct PanelFooter: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text("Open Magpie").font(TypeRole.row).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("⌘⇧M").font(TypeRole.meta).foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: Metric.rowHeight + Space.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}

/// Centered message for empty / no-data error.
struct StateMessage: View {
    var symbol: String
    var title: String
    var detail: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(TypeRole.stateIcon)
                .foregroundStyle(Palette.textTertiary)
                .frame(height: Metric.stateIcon)
            Text(title).font(TypeRole.stateTitle).foregroundStyle(Palette.textPrimary)
            Text(detail)
                .font(TypeRole.meta)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .font(TypeRole.row.weight(.medium))
                        .padding(.horizontal, Space.m)
                        .padding(.vertical, Space.xs)
                        .background(RoundedRectangle(cornerRadius: Radius.chip).fill(Palette.chipFill))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.l + Space.s)
    }
}

/// Static placeholder cards (no shimmer: no continuous animation in a transient panel).
struct LoadingPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(Metric.skeletonWidths.enumerated()), id: \.offset) { _, width in
                Card {
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack {
                            RoundedRectangle(cornerRadius: Radius.skeleton).fill(Palette.skeleton)
                                .frame(width: width, height: Metric.skeletonLine)
                            Spacer()
                            RoundedRectangle(cornerRadius: Radius.skeleton).fill(Palette.skeleton)
                                .frame(width: Metric.valueColumn, height: Metric.skeletonLine * 2)
                        }
                        Capsule().fill(Palette.skeleton).frame(height: Metric.barHeight)
                    }
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading quotas")
    }
}

/// Bounded list region. Live: ScrollView sized to content, capped at `Metric.scrollCap`.
/// Snapshot: same cap via clipping (offscreen ScrollView is AppKit-backed).
struct BoundedScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.panelRenderMode) private var mode
    @State private var contentHeight: CGFloat = Metric.scrollCap

    var body: some View {
        switch mode {
        case .interactive:
            ScrollView(.vertical) {
                content
                    // MenuBarExtra extends native scrolling past its content bounds. Constrain the
                    // document width explicitly so that extension cannot widen the provider cards.
                    .frame(width: Metric.panelWidth)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, Metric.scrollCap))
        case .snapshot:
            // Ideal height first (no compression), then cap and clip.
            content
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: Metric.scrollCap, alignment: .top)
                .fixedSize(horizontal: false, vertical: true)
                .clipped()
        case .snapshotFull:
            // Every row at its ideal height: without the rigid vertical size the renderer's second
            // layout pass squeezes the card stack and stacked row bars overlap.
            content.fixedSize(horizontal: false, vertical: true)
        }
    }
}
