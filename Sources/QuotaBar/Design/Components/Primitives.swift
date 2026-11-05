import SwiftUI

/// `.interactive` = live panel (ScrollView, Menu). `.snapshot` = ImageRenderer-safe
/// stand-ins (AppKit-backed controls render as placeholders offscreen).
/// `.snapshotFull` = snapshot without the scroll cap (review of every row).
enum PanelRenderMode: Sendable { case interactive, snapshot, snapshotFull }

extension EnvironmentValues {
    @Entry var panelRenderMode: PanelRenderMode = .interactive
    @Entry var panelNow: Date = .now
}

extension QuotaLevel {
    var fill: Color {
        switch self {
        case .healthy: Palette.healthy
        case .low: Palette.low
        case .critical: Palette.critical
        case .unknown: Palette.track
        }
    }

    var text: Color {
        switch self {
        case .low: Palette.lowText
        case .critical: Palette.criticalText
        default: Palette.textPrimary
        }
    }
}

/// Provider gauge: one ring, remaining fraction of the hero's binding window.
/// Unknown (no quota / error) = dashed track.
struct QuotaRing: View {
    var remaining: Double?
    var body: some View {
        let level = QuotaLevel(remaining: remaining)
        ZStack {
            if let r = remaining {
                Circle().stroke(Palette.track, lineWidth: Metric.ringStroke)
                Circle()
                    .trim(from: 0, to: max(0, min(1, r / 100)))
                    .stroke(level.fill, style: StrokeStyle(lineWidth: Metric.ringStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle().stroke(Palette.track, style: StrokeStyle(lineWidth: Metric.ringStroke, dash: Metric.ringDash))
            }
        }
        .padding(Metric.ringStroke / 2)
        .frame(width: Metric.ring, height: Metric.ring)
        .accessibilityHidden(true)
    }
}

/// Thin horizontal usage bar (remaining fill). Visual clamp only.
struct UsageBar: View {
    var remaining: Double?
    var body: some View {
        let fraction = max(0, min(1, (remaining ?? 0) / 100))
        Capsule()
            .fill(Palette.track)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(QuotaLevel(remaining: remaining).fill)
                    .frame(width: Metric.barWidth * fraction)
            }
            .frame(width: Metric.barWidth, height: Metric.barHeight)
            .accessibilityHidden(true)
    }
}

/// Small neutral label chip (plan, window value, reset credits, until).
struct Chip<Label: View>: View {
    @ViewBuilder var label: Label
    var body: some View {
        label
            .font(TypeRole.chip)
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, Space.hair)
            .background(RoundedRectangle(cornerRadius: Radius.chip).fill(Palette.chipFill))
            // Chips never ellipsize: the surrounding layout wraps or reflows instead.
            .fixedSize()
    }
}

extension Chip where Label == Text {
    init(_ text: String) { self.init { Text(text) } }
}

/// Window value chip: "5h 47" with level-coloured number.
struct WindowChip: View {
    var window: WindowVM
    var body: some View {
        Chip {
            HStack(spacing: Space.xxs) {
                Text(window.short)
                Text(Presenter.percent(window.remaining))
                    .foregroundStyle(window.level == .healthy ? Palette.textPrimary : window.level.text)
            }
        }
        .accessibilityElement(children: .combine)
        .help("\(window.name): \(Presenter.percent(window.remaining))% left")
    }
}

/// One row when every child fits at its ideal width within the offered width (and `maxRow`,
/// if set); otherwise one child per line, aligned leading or trailing. Used so chips and
/// secondary labels move to a second line instead of truncating.
struct RowOrStack: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = Space.xs
    var maxRow: CGFloat? = nil

    /// Empty children (e.g. a badge stack with no badges) take no space or gap.
    private func visible(_ subviews: Subviews) -> [LayoutSubview] {
        subviews.filter { $0.sizeThatFits(.unspecified).width > 0 }
    }

    private func rowWidth(_ ideal: [CGSize]) -> CGFloat {
        ideal.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, ideal.count - 1))
    }

    private func fitsRow(_ ideal: [CGSize], width: CGFloat?) -> Bool {
        rowWidth(ideal) <= min(width ?? .infinity, maxRow ?? .infinity)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let views = visible(subviews)
        let ideal = views.map { $0.sizeThatFits(.unspecified) }
        if fitsRow(ideal, width: proposal.width) {
            return CGSize(width: rowWidth(ideal), height: ideal.map(\.height).max() ?? 0)
        }
        let sizes = views.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        return CGSize(width: sizes.map(\.width).max() ?? 0,
                      height: sizes.map(\.height).reduce(0, +) + Space.xxs * CGFloat(max(0, sizes.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for view in subviews where view.sizeThatFits(.unspecified).width <= 0 {
            view.place(at: bounds.origin, proposal: .zero)
        }
        let views = visible(subviews)
        let ideal = views.map { $0.sizeThatFits(.unspecified) }
        if fitsRow(ideal, width: bounds.width) {
            let rowHeight = ideal.map(\.height).max() ?? 0
            var x = alignment == .trailing ? bounds.maxX - rowWidth(ideal) : bounds.minX
            for (view, size) in zip(views, ideal) {
                view.place(at: CGPoint(x: x, y: bounds.minY + (rowHeight - size.height) / 2),
                           proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            return
        }
        var y = bounds.minY
        for view in views {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let x = alignment == .trailing ? bounds.maxX - size.width : bounds.minX
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += size.height + Space.xxs
        }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Palette.separator).frame(height: Metric.hairline) }
}

/// Borderless symbol button (SwiftUI-rendered, snapshot-safe).
struct IconButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: Metric.iconButton, height: Metric.iconButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

enum Fmt {
    static func clock(_ date: Date, tz: TimeZone) -> String { formatter("HH:mm", tz).string(from: date) }
    static func day(_ date: Date, tz: TimeZone) -> String { formatter("d MMM", tz).string(from: date) }
    static func dayTime(_ date: Date, tz: TimeZone) -> String { formatter("d MMM HH:mm", tz).string(from: date) }

    /// "3h 12m", "2d 4h", "45m" — recomputed from timestamps on every render.
    static func duration(from now: Date, to date: Date) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86_400, h = (s % 86_400) / 3_600, m = (s % 3_600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(max(m, 1))m"
    }

    private static func formatter(_ format: String, _ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = format
        return f
    }
}
