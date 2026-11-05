import SwiftUI

/// One account line. States: usable · nearly empty (red value) · error (glyph + note) ·
/// no quota (tertiary note). Badges: differing plan, `until`, reset credits, old read.
struct AccountRow: View {
    var account: AccountVM
    @Environment(\.panelNow) private var now
    @Environment(\.timeZone) private var tz

    var body: some View {
        Group {
            switch account.status {
            case .usable, .nearlyEmpty: quotaLine
            case .error, .noQuota: problemLine
            }
        }
        .frame(minHeight: Metric.rowHeight)
        .help(tooltip)
        .accessibilityElement(children: .combine)
    }

    private var quotaLine: some View {
        HStack(spacing: Space.s) {
            nameAndBadges
            UsageBar(remaining: account.binding?.remaining)
            Text("\(Presenter.percent(account.binding?.remaining))%")
                .font(TypeRole.rowValue)
                .foregroundStyle(QuotaLevel(remaining: account.binding?.remaining).text)
                .fixedSize()
                .frame(minWidth: Metric.valueColumn, alignment: .trailing)
            // Window label: abbreviated by rule, then wraps (never ellipsized).
            Text(account.binding?.short ?? "")
                .font(TypeRole.meta)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: Metric.windowColumn, alignment: .leading)
        }
        .padding(.vertical, Space.xxs)
    }

    private var problemLine: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                if account.status == .error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(TypeRole.chip)
                        .foregroundStyle(Palette.low)
                        .accessibilityLabel("Problem")
                }
                nameAndBadges
            }
            if let note = account.note {
                Text(note)
                    .font(TypeRole.meta)
                    .foregroundStyle(account.status == .error ? Palette.textSecondary : Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Space.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameAndBadges: some View {
        // Badges drop under the label when both do not fit. Only the identifier ellipsizes (middle).
        RowOrStack {
            Text(account.label)
                .font(TypeRole.row)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            AccountBadges(account: account)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tooltip: String {
        var lines = [account.label]
        lines += account.windows.map { w in
            var s = "\(w.name): \(Presenter.percent(w.remaining))% left"
            if let d = w.display { s += " (\(d))" }
            if let r = w.resetsAt { s += " · resets in \(Fmt.duration(from: now, to: r)) (\(Fmt.dayTime(r, tz: tz)))" }
            return s
        }
        if let until = account.until { lines.append("Until \(Fmt.dayTime(until, tz: tz))") }
        if account.resetCredits > 0 {
            var s = "\(account.resetCredits) reset credit\(account.resetCredits == 1 ? "" : "s")"
            if let u = account.resetCreditsUntil { s += ", first expires \(Fmt.day(u, tz: tz))" }
            lines.append(s)
        }
        if let read = account.readAt { lines.append("Quota read \(Fmt.duration(from: read, to: now)) ago") }
        if let note = account.note { lines.append(note) }
        return lines.joined(separator: "\n")
    }
}

struct AccountBadges: View {
    var account: AccountVM
    /// false in the provider header: only the old-read glyph, to keep the account name whole.
    var showsChips = true
    @Environment(\.panelNow) private var now
    @Environment(\.timeZone) private var tz

    var body: some View {
        HStack(spacing: Space.xs) {
            if showsChips, account.showsPlan, let plan = account.plan { Chip(plan) }
            if showsChips, let until = account.until {
                Chip {
                    HStack(spacing: Space.hair) {
                        Image(systemName: "hourglass")
                        Text(Fmt.day(until, tz: tz))
                    }
                }
                .fixedSize()
                .accessibilityLabel("Until \(Fmt.day(until, tz: tz))")
            }
            if showsChips, account.resetCredits > 0 {
                Chip {
                    HStack(spacing: Space.hair) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("\(account.resetCredits)")
                    }
                }
                .fixedSize()
                .accessibilityLabel("\(account.resetCredits) reset credits")
            }
            if let read = account.readAt, now.timeIntervalSince(read) > QuotaRules.oldRead {
                Image(systemName: "clock")
                    .font(TypeRole.chip)
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityLabel("Quota read \(Fmt.duration(from: read, to: now)) ago")
            }
        }
    }
}
