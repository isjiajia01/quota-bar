import Foundation

/// Display thresholds on `window.remaining` (percent left). See DESIGN.md › Rules.
enum QuotaRules {
    static let low: Double = 30          // <= 30 → orange
    static let critical: Double = 10     // <= 10 → red
    static let nearlyEmpty: Double = 5   // <= 5 → folded into "N nearly empty"
    /// Account `readAt` older than this (vs. render `now`) gets a quiet "old read" glyph.
    static let oldRead: TimeInterval = 30 * 60
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
    var level: QuotaLevel { QuotaLevel(remaining: remaining) }
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
    var chips: [WindowVM]
    var rows: [AccountVM]
    var nearlyEmpty: [AccountVM]
    var problems: [AccountVM]
    /// Shown under the provider name when there is no hero (single error / no quota).
    var headerNote: String?
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
            chips: hero.map { chips(for: $0.windows) } ?? [],
            rows: rest.filter { $0.status == .usable },
            nearlyEmpty: rest.filter { $0.status == .nearlyEmpty },
            problems: hero == nil && problems.count == 1 ? [] : problems,
            headerNote: hero == nil && problems.count == 1 ? problems[0].note : nil
        )
    }

    static func account(_ a: Account, id: String, ordinal: Int, commonPlan: String?, hideEmails: Bool) -> AccountVM {
        let windows = a.windows.map {
            WindowVM(name: $0.name, short: shortWindowName($0.name), remaining: $0.remaining,
                     resetsAt: $0.resetsAt, display: $0.display)
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

    /// Two lowest windows of the hero, in their original order.
    static func chips(for windows: [WindowVM]) -> [WindowVM] {
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
