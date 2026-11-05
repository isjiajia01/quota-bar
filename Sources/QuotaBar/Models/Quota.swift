import Foundation

/// Wire format of `GET /v1/magpie/quotas`. Unknown keys are ignored by `Decodable`.
/// Only the fields the panel renders are decoded; nested `holds`/`resetsUsed`
/// detail is intentionally skipped (may contain identities).
struct QuotaPayload: Decodable, Sendable, Equatable {
    var data: [Account]
}

struct Account: Decodable, Sendable, Equatable {
    var provider: String
    var name: String
    var kind: String?
    var plan: String?
    var user: String?
    var windows: [QuotaWindow]
    var readAt: Date?
    var lastServedAt: Date?
    var error: String?
    /// Account-level "until" (meaning not specified by the endpoint; shown neutrally).
    var until: Date?
    var resets: ResetCredits?

    enum CodingKeys: String, CodingKey {
        case provider, name, kind, plan, user, windows, readAt, lastServedAt, error, until, resets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decode(String.self, forKey: .provider)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? provider
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        user = try c.decodeIfPresent(String.self, forKey: .user)
        windows = try c.decodeIfPresent([QuotaWindow].self, forKey: .windows) ?? []
        readAt = try c.decodeQuotaDateIfPresent(forKey: .readAt)
        lastServedAt = try c.decodeQuotaDateIfPresent(forKey: .lastServedAt)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        until = try c.decodeQuotaDateIfPresent(forKey: .until)
        resets = try c.decodeIfPresent(ResetCredits.self, forKey: .resets)
    }

    init(provider: String, name: String, kind: String? = nil, plan: String? = nil, user: String? = nil,
         windows: [QuotaWindow] = [], readAt: Date? = nil, lastServedAt: Date? = nil,
         error: String? = nil, until: Date? = nil, resets: ResetCredits? = nil) {
        self.provider = provider; self.name = name; self.kind = kind; self.plan = plan; self.user = user
        self.windows = windows; self.readAt = readAt; self.lastServedAt = lastServedAt
        self.error = error; self.until = until; self.resets = resets
    }
}

struct QuotaWindow: Decodable, Sendable, Equatable {
    var name: String
    /// Fractional percentages, raw (not clamped).
    var used: Double?
    var remaining: Double?
    var resetsAt: Date?
    var pool: String?
    var display: String?
    var unit: String?
    var runsOutAt: Date?

    enum CodingKeys: String, CodingKey {
        case name, used, remaining, resetsAt, pool, display, unit, runsOutAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        used = try c.decodeIfPresent(Double.self, forKey: .used)
        remaining = try c.decodeIfPresent(Double.self, forKey: .remaining)
        resetsAt = try c.decodeQuotaDateIfPresent(forKey: .resetsAt)
        pool = try c.decodeIfPresent(String.self, forKey: .pool)
        display = try c.decodeIfPresent(String.self, forKey: .display)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        runsOutAt = try c.decodeQuotaDateIfPresent(forKey: .runsOutAt)
    }

    init(name: String, used: Double? = nil, remaining: Double?, resetsAt: Date? = nil,
         pool: String? = nil, display: String? = nil, unit: String? = nil, runsOutAt: Date? = nil) {
        self.name = name; self.used = used; self.remaining = remaining; self.resetsAt = resetsAt
        self.pool = pool; self.display = display; self.unit = unit; self.runsOutAt = runsOutAt
    }
}

/// Reset credits held by the account. Not the window `resetsAt`. Read-only.
struct ResetCredits: Decodable, Sendable, Equatable {
    var count: Int
    var until: Date?

    enum CodingKeys: String, CodingKey { case count, until }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        until = try c.decodeQuotaDateIfPresent(forKey: .until)
    }

    init(count: Int, until: Date? = nil) { self.count = count; self.until = until }
}

extension QuotaPayload {
    static func decode(_ data: Data) throws -> QuotaPayload {
        try JSONDecoder().decode(QuotaPayload.self, from: data)
    }
}
