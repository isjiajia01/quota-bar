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
