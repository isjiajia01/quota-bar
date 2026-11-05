import Foundation

/// RFC 3339 parser tolerant of 0 or 1–9 fractional digits (fixture uses none, 3, 6 and 9).
enum QuotaDate {
    static func parse(_ string: String) -> Date? {
        // Split "2026-11-05T20:28:16.190556575Z" into base + fraction + zone.
        guard let tIndex = string.firstIndex(of: "T") else { return nil }
        var base = string
        var fraction: Double = 0
        if let dot = string[tIndex...].firstIndex(of: ".") {
            let afterDot = string[string.index(after: dot)...]
            let digits = afterDot.prefix(while: \.isNumber)
            guard !digits.isEmpty else { return nil }
            fraction = Double("0." + digits) ?? 0
            base = String(string[..<dot]) + String(afterDot.dropFirst(digits.count))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: base) else { return nil }
        return date.addingTimeInterval(fraction)
    }
}

extension KeyedDecodingContainer {
    func decodeQuotaDateIfPresent(forKey key: Key) throws -> Date? {
        guard let raw = try decodeIfPresent(String.self, forKey: key) else { return nil }
        return QuotaDate.parse(raw)
    }
}
