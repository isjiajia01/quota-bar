import SwiftUI

/// Provider header: ring + name/plan + "Most left · <account>" + hero value and window chips.
struct ProviderHeader: View {
    var provider: ProviderVM

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            QuotaRing(remaining: provider.hero?.binding?.remaining)
            VStack(alignment: .leading, spacing: Space.hair) {
                HStack(spacing: Space.xs) {
                    Text(provider.name)
                        .font(TypeRole.provider)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(2)
                    if let plan = provider.plan { Chip(plan) }
                }
                subtitle
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let hero = provider.hero {
                VStack(alignment: .trailing, spacing: Space.hair) {
                    Text("\(Presenter.percent(hero.binding?.remaining))%")
                        .font(TypeRole.heroValue)
                        .foregroundStyle(QuotaLevel(remaining: hero.binding?.remaining).text)
                    HStack(spacing: Space.xs) {
                        ForEach(provider.chips) { WindowChip(window: $0) }
                    }
                }
                .frame(maxWidth: Metric.heroColumn, alignment: .trailing)
            }
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
            Text(note)
                .font(TypeRole.meta)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Header, other usable accounts, folded nearly-empty group, then problem accounts.
struct ProviderSection: View {
    var provider: ProviderVM
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ProviderHeader(provider: provider)
            if !provider.rows.isEmpty || !provider.nearlyEmpty.isEmpty || !provider.problems.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(provider.rows) { AccountRow(account: $0) }
                    if !provider.nearlyEmpty.isEmpty {
                        NearlyEmptyGroup(accounts: provider.nearlyEmpty, isExpanded: $isExpanded)
                    }
                    ForEach(provider.problems) { AccountRow(account: $0) }
                }
                .padding(.leading, Metric.ring + Space.s)
            }
        }
        .padding(.vertical, Space.s)
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
                        .font(TypeRole.meta.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(minHeight: Metric.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(accounts.count) nearly empty accounts")
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
