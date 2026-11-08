import Foundation
import Testing
@testable import QuotaBar

@Suite struct ModelTests {
    let payload = FixtureQuotaSource.loadSync()

    @Test func decodesWholeFixture() {
        #expect(payload.data.count == 22)
        #expect(Set(payload.data.map(\.provider)).count == 8)
    }

    @Test func fractionalPercentagesArePreserved() throws {
        let wb = try #require(payload.data.first { $0.windows.count == 4 && $0.provider == "workbuddy-ai" })
        #expect(wb.windows[1].remaining == 96.976000004)
    }

    @Test func emptyWindowsAndOptionalFields() throws {
        let zcode = try #require(payload.data.first { $0.provider == "zcode" })
        #expect(zcode.windows.isEmpty)
        #expect(zcode.error != nil)
        let go = try #require(payload.data.first { $0.provider == "opencode-go" })
        #expect(go.user == nil)
        #expect(go.windows[0].resetsAt == nil)
    }

    @Test(arguments: [
        ("2026-11-05T21:49:00Z", 0.0),
        ("2026-11-06T19:08:02.492Z", 0.492),
        ("2026-11-30T19:22:49.832064Z", 0.832064),
        ("2026-11-05T20:28:16.190556575Z", 0.190556575),
    ])
    func parsesTimestamps(raw: String, fraction: Double) throws {
        let date = try #require(QuotaDate.parse(raw))
        let whole = date.timeIntervalSince1970.rounded(.down)
        #expect(abs(date.timeIntervalSince1970 - whole - fraction) < 0.000_01)
    }

    @Test func unknownKeysAndMissingWindowsDecode() throws {
        let json = #"{"data":[{"provider":"x","name":"X","surprise":{"a":1}}],"object":"list"}"#
        let p = try QuotaPayload.decode(Data(json.utf8))
        #expect(p.data[0].windows.isEmpty)
    }
}

@Suite struct PresenterTests {
    let providers = Presenter.providers(from: FixtureQuotaSource.loadSync().data, hideEmails: false)

    @Test func keepsEveryAccountAndProviderOrder() {
        #expect(providers.map(\.id) == ["claude", "codex", "zcode", "workbuddy", "workbuddy-ai",
                                        "antigravity", "opencode-zen-free", "opencode-go"])
        let shown = providers.reduce(0) { n, p in
            n + (p.hero == nil ? 0 : 1) + p.rows.count + p.nearlyEmpty.count + p.problems.count
                + (p.headerNote == nil ? 0 : 1)
        }
        #expect(shown == 22)
    }

    @Test func heroIsHighestBindingAndNearlyEmptyUsesThreshold() throws {
        let claude = try #require(providers.first { $0.id == "claude" })
        #expect(claude.hero?.label == "account0")
        #expect(claude.hero?.binding?.remaining == 47)
        #expect(claude.nearlyEmpty.map(\.label) == ["account1"])  // 2 <= 5
        let codex = try #require(providers.first { $0.id == "codex" })
        #expect(codex.hero?.binding?.remaining == 95)
        #expect(Set(codex.nearlyEmpty.map(\.label)) == ["account3", "account6"])
        #expect(codex.problems.map(\.status) == [.error])
    }

    @Test func emailsArePrivate() throws {
        let hidden = Presenter.providers(from: FixtureQuotaSource.loadSync().data, hideEmails: true)
        let all = hidden.flatMap { [$0.hero].compactMap { $0 } + $0.rows + $0.nearlyEmpty + $0.problems }
        #expect(all.allSatisfy { !$0.label.contains("@") && !$0.label.contains("account") })
        let expired = try #require(all.first { $0.status == .error })
        #expect(expired.note?.hasPrefix("This account's sign-in has expired") == true)
        #expect(Presenter.redact("mail me@x.io now") == "mail This account now")
        let shown = Presenter.providers(from: FixtureQuotaSource.loadSync().data, hideEmails: false)
        let notes = shown.flatMap { $0.problems.compactMap(\.note) + [$0.headerNote].compactMap { $0 } }
        #expect(notes.allSatisfy { !$0.contains("@") })
    }

    @Test func identityCollisionsKeepRows() {
        let a = Account(provider: "p", name: "P", windows: [QuotaWindow(name: "5 hours", remaining: 50)])
        let vm = Presenter.provider(id: "p", accounts: [a, a, a], hideEmails: false)
        let ids = [vm.hero!.id] + vm.rows.map(\.id)
        #expect(Set(ids).count == 3)
    }

    @Test func percentLabels() {
        #expect(Presenter.percent(99.905276) == "99")
        #expect(Presenter.percent(0.3) == "<1")
        #expect(Presenter.percent(0) == "0")
        #expect(Presenter.percent(130) == "100")
        #expect(Presenter.percent(nil) == "—")
        #expect(Presenter.shortWindowName("Gemini · 7 days") == "Gemini 7d")
    }

    /// DESIGN.md › Text fitting: window abbreviation rule.
    @Test func windowAbbreviationRule() {
        #expect(Presenter.shortWindowName("5 hours") == "5h")
        #expect(Presenter.shortWindowName("1 day") == "1d")
        #expect(Presenter.shortWindowName("30 minutes") == "30m")
        #expect(Presenter.shortWindowName("Claude & GPT · 5 hours") == "Claude & GPT 5h")
        #expect(Presenter.shortWindowName("Claude Opus 4.6 (Thinking)") == "Claude Opus 4.6")
        #expect(Presenter.shortWindowName("Extra credits") == "Extra")
        #expect(Presenter.shortWindowName("Total credits") == "Total")
        #expect(Presenter.shortWindowName("Free model tokens") == "Free model")
        #expect(Presenter.shortWindowName("Credits") == "Credits")
        #expect(Presenter.shortWindowName("Month") == "Month")
        #expect(Presenter.shortWindowName("(Thinking)") == "(Thinking)")
    }
}

/// DESIGN.md › Pace: window length parsing, even-pace tick, fact-only run-out projection.
@Suite struct PaceTests {
    let now = QuotaDate.parse("2026-11-05T20:00:00Z")!
    let h: TimeInterval = 3_600

    @Test func parsesWindowLength() {
        #expect(Pace.windowLength("5 hours") == 5 * h)
        #expect(Pace.windowLength("Gemini · 7 days") == 7.0 * 86_400)
        #expect(Pace.windowLength("30 minutes") == 1_800)
        #expect(Pace.windowLength("1 day") == 86_400)
        #expect(Pace.windowLength("2 weeks") == 14.0 * 86_400)
        #expect(Pace.windowLength("Month") == nil)
        #expect(Pace.windowLength("Credits") == nil)
        #expect(Pace.windowLength("Gemini 2.5 Flash") == nil)
    }

    @Test func elapsedFraction() throws {
        let w = WindowVM(name: "5 hours", remaining: 47, resetsAt: now.addingTimeInterval(1 * h))
        #expect(abs(try #require(Pace.elapsed(w, at: now)) - 0.8) < 1e-9)
        #expect(Pace.elapsed(WindowVM(name: "5 hours", remaining: 47), at: now) == nil)          // no resetsAt
        #expect(Pace.elapsed(WindowVM(name: "Month", remaining: 47, resetsAt: now), at: now) == nil)
        // Outside the window (reset already passed, or further away than the window) → no tick.
        #expect(Pace.elapsed(WindowVM(name: "5 hours", remaining: 47, resetsAt: now.addingTimeInterval(-60)), at: now) == nil)
        #expect(Pace.elapsed(WindowVM(name: "5 hours", remaining: 47, resetsAt: now.addingTimeInterval(6 * h)), at: now) == nil)
    }

    @Test func projectionOnlyWhenBurningFasterAndBeforeReset() throws {
        // 2h of 5h elapsed (0.4), 72% used → pace 1.8; 28% left at 36%/h → ~46.7 min.
        let fast = WindowVM(name: "5 hours", remaining: 28, resetsAt: now.addingTimeInterval(3 * h))
        let out = try #require(Pace.projectedRunOut(fast, readAt: now, now: now))
        #expect(abs(out.timeIntervalSince(now) - 0.28 / 0.36 * h) < 1)
        #expect(try #require(Pace.ratio(fast, at: now)) > 1)
        // Slower than the clock → nothing.
        let slow = WindowVM(name: "5 hours", remaining: 47, resetsAt: now.addingTimeInterval(1 * h))
        #expect(Pace.projectedRunOut(slow, readAt: now, now: now) == nil)
        // Exactly on pace (50% used, half elapsed) → nothing. (Linearly, pace > 1 always empties
        // before the reset; the reset guard only matters at the boundary.)
        let even = WindowVM(name: "5 hours", remaining: 50, resetsAt: now.addingTimeInterval(2.5 * h))
        #expect(Pace.projectedRunOut(even, readAt: now, now: now) == nil)
        // Barely faster (7d: 30% used, 28.6% elapsed): would empty ~8h before reset, < 10% lead → nothing.
        let marginal = WindowVM(name: "7 days", remaining: 70, resetsAt: now.addingTimeInterval(120 * h))
        #expect(Pace.projectedRunOut(marginal, readAt: now, now: now) == nil)
        // Too early in the window, empty, or unknown length → nothing.
        let early = WindowVM(name: "7 days", remaining: 90, resetsAt: now.addingTimeInterval(160 * h))
        #expect(Pace.projectedRunOut(early, readAt: now, now: now) == nil)
        let empty = WindowVM(name: "5 hours", remaining: 0, resetsAt: now.addingTimeInterval(3 * h))
        #expect(Pace.projectedRunOut(empty, readAt: now, now: now) == nil)
        let month = WindowVM(name: "Month", remaining: 5, resetsAt: now.addingTimeInterval(3 * h))
        #expect(Pace.projectedRunOut(month, readAt: now, now: now) == nil)
    }

    @Test func projectionUsesReadTimeAndNeverReportsThePast() {
        // Measured 2h ago at a pace that empties 47 min after the read → already past: no claim.
        let w = WindowVM(name: "5 hours", remaining: 28, resetsAt: now.addingTimeInterval(1 * h))
        #expect(Pace.projectedRunOut(w, readAt: now.addingTimeInterval(-2 * h), now: now) == nil)
    }

    @Test func fixtureCodexRowProjects() throws {
        let providers = Presenter.providers(from: FixtureQuotaSource.loadSync().data, hideEmails: false)
        let now = StatePage.now
        let codex = try #require(providers.first { $0.id == "codex" })
        let acct5 = try #require(codex.rows.first { $0.label == "account5" })
        let out = try #require(Pace.projectedRunOut(acct5.binding!, readAt: acct5.readAt, now: now))
        #expect(out < acct5.binding!.resetsAt!)
        // Claude hero 5h: 53% used with 80% elapsed → on pace, no projection.
        let claude = try #require(providers.first { $0.id == "claude" })
        #expect(claude.heroWindows.allSatisfy { Pace.projectedRunOut($0, readAt: claude.hero?.readAt, now: now) == nil })
    }

    @Test func amountText() {
        #expect(WindowVM(name: "Extra credits", remaining: 97, display: "7.56 / 250", unit: "credits").amountText
                == "7.56 / 250 credits used")
        #expect(WindowVM(name: "x", remaining: 1, display: "1 / 2").amountText == "1 / 2 used")
        #expect(WindowVM(name: "5 hours", remaining: 1).amountText == nil)
    }
}

@Suite struct TokenLintTests {
    @Test func noRawValuesOutsideTokens() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [root.appending(path: "scripts/lint-tokens.sh").path]
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run(); p.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(p.terminationStatus == 0, "\(text)")
    }
}
