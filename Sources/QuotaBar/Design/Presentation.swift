import Foundation

/// Display thresholds on `window.remaining` (percent left). See DESIGN.md › Rules.
enum QuotaRules {
    static let low: Double = 30          // <= 30 → orange
    static let critical: Double = 10     // <= 10 → red
    static let nearlyEmpty: Double = 5   // <= 5 → folded into "N nearly empty"
    /// Account `readAt` older than this (vs. render `now`) gets a quiet "old read" glyph.
    static let oldRead: TimeInterval = 30 * 60
    /// A linear run-out projection needs at least this much of the window elapsed (early pace is noise).
    static let projectionMinElapsed: Double = 0.1
    /// ...and must land at least this share of the window before the reset (no "runs out 1h before reset" noise).
    static let projectionMinLead: Double = 0.1
}

enum QuotaLevel: Sendable, Equatable {
    case healthy, low, critical, unknown

    init(remaining: Double?) {
        guard let r = remaining else { self = .unknown; return }
        if r <= QuotaRules.critical { self = .critical }
        else if r <= QuotaRules.low { self = .low }
        else { self = .healthy }
    }
}

struct WindowVM: Sendable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var short: String
    /// Raw value (unclamped). Rendering clamps.
    var remaining: Double?
    var resetsAt: Date?
    var display: String?
    var unit: String?
    /// Payload credit expiry (not a projection, not the window reset).
    var runsOutAt: Date?
    var level: QuotaLevel { QuotaLevel(remaining: remaining) }

    init(name: String, short: String? = nil, remaining: Double?, resetsAt: Date? = nil,
         display: String? = nil, unit: String? = nil, runsOutAt: Date? = nil) {
        self.name = name; self.short = short ?? Presenter.shortWindowName(name)
        self.remaining = remaining; self.resetsAt = resetsAt
        self.display = display; self.unit = unit; self.runsOutAt = runsOutAt
    }

    /// "7.56 / 250 credits used" from `display` + `unit`; nil without `display`.
    var amountText: String? {
        guard let display, !display.isEmpty else { return nil }
        return unit.map { "\(display) \($0) used" } ?? "\(display) used"
    }
}

struct AccountVM: Sendable, Equatable, Identifiable {
    enum Status: Sendable, Equatable { case usable, nearlyEmpty, error, noQuota }

    var id: String
    var label: String
    var plan: String?
    /// Plan differs from the provider's common plan → show chip on the row.
    var showsPlan: Bool
    var binding: WindowVM?
    var windows: [WindowVM]
    var until: Date?
    var resetCredits: Int
    var resetCreditsUntil: Date?
    var readAt: Date?
    var note: String?
    var status: Status
}

struct ProviderVM: Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var plan: String?
    var accountCount: Int
    /// Usable account with the highest binding remaining. A data fact, not a routing claim.
    var hero: AccountVM?
    /// Hero windows drawn as meters (the two lowest, original order).
    var heroWindows: [WindowVM]
    var rows: [AccountVM]
    var nearlyEmpty: [AccountVM]
    var problems: [AccountVM]
    /// Shown under the provider name when there is no hero (single error / no quota).
    var headerNote: String?
    /// The header note is an account error (warning glyph), not "No quota reported".
    var headerIsError: Bool = false
}

enum Presenter {
    static func providers(from accounts: [Account], hideEmails: Bool) -> [ProviderVM] {
        var order: [String] = []
        var grouped: [String: [Account]] = [:]
        for a in accounts {
            if grouped[a.provider] == nil { order.append(a.provider) }
            grouped[a.provider, default: []].append(a)
        }
        return order.map { provider(id: $0, accounts: grouped[$0] ?? [], hideEmails: hideEmails) }
    }

    static func provider(id: String, accounts: [Account], hideEmails: Bool) -> ProviderVM {
        let commonPlan = mostCommon(accounts.compactMap(\.plan))
        var seen: [String: Int] = [:]
        let vms: [AccountVM] = accounts.enumerated().map { index, a in
            let key = "\(a.provider)|\(a.user ?? a.name)"
            let n = seen[key, default: 0]; seen[key] = n + 1
            return account(a, id: n == 0 ? key : "\(key)#\(n)", ordinal: index + 1,
                           commonPlan: commonPlan, hideEmails: hideEmails)
        }
        let usable = vms.filter { $0.status == .usable || $0.status == .nearlyEmpty }
            .sorted { ($0.binding?.remaining ?? -1) > ($1.binding?.remaining ?? -1) }
        let problems = vms.filter { $0.status == .error || $0.status == .noQuota }
        let hero = usable.first
        let rest = vms.count > 1 ? Array(usable.dropFirst()) : []
        let name = accounts.first?.name ?? id
        return ProviderVM(
            id: id,
            name: name,
            plan: commonPlan.flatMap { stripProvider($0, name: name) },
            accountCount: vms.count,
            hero: hero,
            heroWindows: hero.map { heroWindows(for: $0.windows) } ?? [],
            rows: rest.filter { $0.status == .usable },
            nearlyEmpty: rest.filter { $0.status == .nearlyEmpty },
            problems: hero == nil && problems.count == 1 ? [] : problems,
            headerNote: hero == nil && problems.count == 1 ? problems[0].note : nil,
            headerIsError: hero == nil && problems.count == 1 && problems[0].status == .error
        )
    }

    static func account(_ a: Account, id: String, ordinal: Int, commonPlan: String?, hideEmails: Bool) -> AccountVM {
        let windows = a.windows.map {
            WindowVM(name: $0.name, remaining: $0.remaining, resetsAt: $0.resetsAt,
                     display: $0.display, unit: $0.unit, runsOutAt: $0.runsOutAt)
        }
        let binding = windows.filter { $0.remaining != nil }.min { $0.remaining! < $1.remaining! }
        let status: AccountVM.Status
        var note: String?
        if let error = a.error {
            status = .error
            note = redact(error)
        } else if binding == nil {
            status = .noQuota
            note = "No quota reported"
        } else if let r = binding?.remaining, r <= QuotaRules.nearlyEmpty {
            status = .nearlyEmpty
        } else {
            status = .usable
        }
        return AccountVM(
            id: id,
            label: label(user: a.user, ordinal: ordinal, hideEmails: hideEmails),
            plan: a.plan.flatMap { stripProvider($0, name: a.name) },
            showsPlan: a.plan != nil && a.plan != commonPlan,
            binding: binding,
            windows: windows,
            until: a.until,
            resetCredits: a.resets?.count ?? 0,
            resetCreditsUntil: a.resets?.until,
            readAt: a.readAt,
            note: note,
            status: status
        )
    }

    // MARK: - Text rules

    /// Emails are private: show the full local part only; "Account N" when hidden.
    static func label(user: String?, ordinal: Int, hideEmails: Bool) -> String {
        guard let user, !hideEmails else { return "Account \(ordinal)" }
        return localPart(user)
    }

    static func localPart(_ email: String) -> String {
        email.split(separator: "@", maxSplits: 1).first.map(String.init) ?? email
    }

    /// Error strings can embed identities. Any address or scrub placeholder becomes
    /// "This account" regardless of the hide toggle: the row label already names it.
    static func redact(_ text: String) -> String {
        text.replacing(/\{\{EMAIL_[A-Za-z0-9_]+\}\}/, with: "This account")
            .replacing(/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/, with: "This account")
    }

    /// Window abbreviation rule (DESIGN.md › Text fitting). Applied in this order:
    /// 1. pool separator " · " → space  2. "N minutes/hours/days/weeks" → "Nm/Nh/Nd/Nw"
    /// 3. drop a trailing parenthetical ("(Thinking)")  4. drop a trailing unit word
    ///    ("credits"/"tokens") when a qualifier precedes it ("Extra credits" → "Extra").
    /// Never cuts characters; the full name stays in the row tooltip.
    static func shortWindowName(_ name: String) -> String {
        var s = name.replacing(" · ", with: " ")
            .replacing(/(\d+) minutes?/) { "\($0.output.1)m" }
            .replacing(/(\d+) hours?/) { "\($0.output.1)h" }
            .replacing(/(\d+) days?/) { "\($0.output.1)d" }
            .replacing(/(\d+) weeks?/) { "\($0.output.1)w" }
            .replacing(/\s*\([^()]*\)\s*$/, with: "")
        s = s.replacing(/^(.+\S)\s+(?i:credits?|tokens?)$/) { String($0.output.1) }
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? name : trimmed
    }

    /// Two lowest windows of the hero, in their original order (hero meters).
    static func heroWindows(for windows: [WindowVM]) -> [WindowVM] {
        let known = windows.filter { $0.remaining != nil }
        guard known.count > 2 else { return known }
        let lowest = Set(known.sorted { $0.remaining! < $1.remaining! }.prefix(2).map(\.name))
        return known.filter { lowest.contains($0.name) }
    }

    /// "ZCode Start Plan" → "Start Plan"; a plan equal to the provider name → nil.
    static func stripProvider(_ plan: String, name: String) -> String? {
        if plan == name { return nil }
        return plan.hasPrefix(name + " ") ? String(plan.dropFirst(name.count + 1)) : plan
    }

    /// Percent label: floor, but never show "0" for a non-zero remainder.
    static func percent(_ value: Double?) -> String {
        guard let v = value else { return "—" }
        if v > 0 && v < 1 { return "<1" }
        return String(Int(max(0, min(100, v)).rounded(.down)))
    }

    static func range(_ accounts: [AccountVM]) -> String {
        let values = accounts.compactMap { $0.binding?.remaining }
        guard let lo = values.min(), let hi = values.max() else { return "" }
        let a = percent(lo), b = percent(hi)
        return a == b ? "\(a)%" : "\(a)–\(b)%"
    }

    private static func mostCommon(_ values: [String]) -> String? {
        var counts: [String: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return values.first { counts[$0] == counts.values.max() }
    }
}

/// Pace and projection (DESIGN.md › Pace). Pure; every value is recomputed from timestamps.
enum Pace {
    /// Window length parsed from its name: "5 hours", "Gemini · 7 days", "30 minutes", "2 weeks".
    /// nil when the name carries no duration (e.g. "Month", "Credits").
    static func windowLength(_ name: String) -> TimeInterval? {
        guard let m = name.firstMatch(of: /(?i)(\d+)\s*(minute|hour|day|week)s?\b/),
              let n = Double(m.output.1), n > 0 else { return nil }
        let unit: TimeInterval = switch m.output.2.lowercased() {
        case "minute": 60
        case "hour": 3_600
        case "day": 86_400
        default: 604_800
        }
        return n * unit
    }

    /// Share of the window's time already gone at `date`: 1 − (resetsAt − date) / length.
    /// nil when the length is unknown, `resetsAt` is missing, or the result falls outside 0…1.
    static func elapsed(_ w: WindowVM, at date: Date) -> Double? {
        guard let length = windowLength(w.name), let reset = w.resetsAt else { return nil }
        let e = 1 - reset.timeIntervalSince(date) / length
        return (0...1).contains(e) ? e : nil
    }

    /// used ÷ elapsed. > 1 means quota is burning faster than the clock.
    static func ratio(_ w: WindowVM, at date: Date) -> Double? {
        guard let r = w.remaining, let e = elapsed(w, at: date), e > 0 else { return nil }
        return (100 - max(0, min(100, r))) / 100 / e
    }

    /// Linear projection: when, at the pace measured at `readAt` (else `now`), the window would empty.
    /// Only returned when pace > 1, enough of the window has elapsed, quota is left, and the
    /// projected time falls before the window resets. A fact about the trend, never advice.
    static func projectedRunOut(_ w: WindowVM, readAt: Date?, now: Date) -> Date? {
        let at = readAt ?? now
        guard let r = w.remaining, r > 0, let reset = w.resetsAt, let length = windowLength(w.name),
              let e = elapsed(w, at: at), e >= QuotaRules.projectionMinElapsed,
              let pace = ratio(w, at: at), pace > 1 else { return nil }
        let usedFraction = (100 - min(100, r)) / 100
        let perSecond = usedFraction / (e * length)
        let out = at.addingTimeInterval((min(100, r) / 100) / perSecond)
        let lead = reset.timeIntervalSince(out) / length
        return lead >= QuotaRules.projectionMinLead && out > now ? out : nil
    }
}
