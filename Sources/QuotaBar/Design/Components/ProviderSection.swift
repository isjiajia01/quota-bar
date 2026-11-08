import SwiftUI

/// Provider header: name + plan chip, "Most left · <account>" subtitle, and the one dominant number.
struct ProviderHeader: View {
    var provider: ProviderVM

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                // Provider name wraps rather than truncates; the plan chip drops to its own line
                // when name + chip do not fit beside the hero number.
                RowOrStack {
                    Text(provider.name)
                        .font(TypeRole.provider)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let plan = provider.plan { Chip(plan) }
                }
                subtitle
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Never compressed; the left column yields.
            HeroValue(remaining: provider.hero?.binding?.remaining)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var subtitle: some View {
        if let hero = provider.hero {
            HStack(spacing: Space.xs) {
                if provider.accountCount > 1 { Text("Most left ·").fixedSize() }
                Text(hero.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .help(hero.label)
                AccountBadges(account: hero, showsChips: false)
            }
            .font(TypeRole.meta)
            .foregroundStyle(Palette.textSecondary)
        } else if let note = provider.headerNote {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                if provider.headerIsError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.low)
                        .accessibilityLabel("Problem")
                }
                Text(note).fixedSize(horizontal: false, vertical: true)
            }
            .font(TypeRole.meta)
            .foregroundStyle(Palette.textSecondary)
            .help(note)
        }
    }
}

/// One hero window: label · flexible bar with even-pace tick · value · reset time,
/// plus fact lines (amount used, credit expiry, run-out projection) when the payload has them.
struct WindowMeter: View {
    var window: WindowVM
    var readAt: Date?
    @Environment(\.panelNow) private var now
    @Environment(\.timeZone) private var tz

    var body: some View {
        let projection = Pace.projectedRunOut(window, readAt: readAt, now: now)
        VStack(alignment: .leading, spacing: Space.hair) {
            HStack(spacing: Space.s) {
                Text(window.short)
                    .font(TypeRole.meterLabel)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Metric.meterLabelColumn, alignment: .leading)
                UsageBar(remaining: window.remaining, pace: Pace.elapsed(window, at: now), width: nil)
                Text("\(Presenter.percent(window.remaining))%")
                    .font(TypeRole.rowValue)
                    .foregroundStyle(window.level.text)
                    .fixedSize()
                    .frame(minWidth: Metric.valueColumn, alignment: .trailing)
                Text(window.resetsAt.map { "resets \(Fmt.duration(from: now, to: $0))" } ?? "")
                    .font(TypeRole.detail)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: Metric.trailingColumn, alignment: .leading)
            }
            .frame(minHeight: Metric.rowHeight)
            let facts = [window.amountText, window.runsOutAt.map { "expires \(Fmt.day($0, tz: tz))" }]
                .compactMap { $0 }
            if !facts.isEmpty {
                Text(facts.joined(separator: " · "))
                    .font(TypeRole.detail)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Metric.meterLabelColumn + Space.s)
            }
            if let projection {
                ProjectionNote(date: projection)
                    .padding(.leading, Metric.meterLabelColumn + Space.s)
            }
        }
        .help(WindowText.tooltip(window, readAt: readAt, now: now, tz: tz))
        .accessibilityElement(children: .combine)
    }
}

/// "may run out ~14:05": fact-only linear projection, amber text + glyph (never colour alone).
struct ProjectionNote: View {
    var date: Date
    @Environment(\.panelNow) private var now
    @Environment(\.timeZone) private var tz

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Image(systemName: "speedometer").accessibilityHidden(true)
            Text("may run out ~\(Fmt.when(date, now: now, tz: tz))")
        }
        .font(TypeRole.detail)
        .foregroundStyle(Palette.lowText)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shared tooltip text for a window (meters and rows). Full name, never abbreviated.
enum WindowText {
    static func tooltip(_ w: WindowVM, readAt: Date?, now: Date, tz: TimeZone) -> String {
        var s = "\(w.name): \(Presenter.percent(w.remaining))% left"
        if let a = w.amountText { s += " (\(a))" }
        if let r = w.resetsAt { s += " · resets in \(Fmt.duration(from: now, to: r)) (\(Fmt.dayTime(r, tz: tz)))" }
        if let e = Pace.elapsed(w, at: now) {
            s += "\n  Tick = even pace: \(Int((e * 100).rounded()))% of the window has passed"
        }
        if let p = Pace.projectedRunOut(w, readAt: readAt, now: now) {
            s += "\n  At this pace it may run out ~\(Fmt.when(p, now: now, tz: tz)), before it resets"
        }
        if let x = w.runsOutAt { s += "\n  Credits expire \(Fmt.dayTime(x, tz: tz))" }
        return s
    }
}

/// Card: header, hero meters, then other usable accounts, folded nearly-empty group, problem accounts.
struct ProviderSection: View {
    var provider: ProviderVM
    @Binding var isExpanded: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.s) {
                ProviderHeader(provider: provider)
                if let hero = provider.hero, !provider.heroWindows.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        ForEach(provider.heroWindows) { WindowMeter(window: $0, readAt: hero.readAt) }
                    }
                }
                if !provider.rows.isEmpty || !provider.nearlyEmpty.isEmpty || !provider.problems.isEmpty {
                    Hairline()
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(provider.rows) { AccountRow(account: $0) }
                        if !provider.nearlyEmpty.isEmpty {
                            NearlyEmptyGroup(accounts: provider.nearlyEmpty, isExpanded: $isExpanded)
                        }
                        ForEach(provider.problems) { AccountRow(account: $0) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Folded "N nearly empty · a–b%" row. Expanded rows hang off a guide line,
/// indented one step, so they read as members of the provider, not a new section.
struct NearlyEmptyGroup: View {
    var accounts: [AccountVM]
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.disclosure(reduced: reduceMotion)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: "chevron.right")
                        .font(TypeRole.chip)
                        .foregroundStyle(Palette.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Circle().fill(Palette.critical).frame(width: Metric.dot, height: Metric.dot)
                    Text("\(accounts.count) nearly empty")
                        .font(TypeRole.meta)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: Space.s)
                    Text(Presenter.range(accounts))
                        .font(TypeRole.rowValue)
                        .foregroundStyle(Palette.criticalText)
                        .frame(minWidth: Metric.valueColumn, alignment: .trailing)
                    // Keeps the range in the shared value column.
                    Color.clear.frame(width: Metric.trailingColumn + Space.xs, height: Metric.hairline)
                }
                .frame(minHeight: Metric.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(accounts.count) nearly empty accounts, \(Presenter.range(accounts))")
            .accessibilityValue(isExpanded ? "expanded" : "collapsed")

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(accounts) { AccountRow(account: $0) }
                }
                .padding(.leading, Space.m)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Palette.separator).frame(width: Metric.guide)
                        .padding(.leading, Space.xs)
                }
                .transition(.opacity)
            }
        }
    }
}
