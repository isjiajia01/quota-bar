import Foundation
import Testing
@testable import QuotaBar

/// DESIGN.md › Row window pair: every row stacks the 5-hour window above the 7-day window,
/// keeps an unreported slot as a placeholder, and falls back to one line without either slot.
@Suite struct RowLinesTests {
    let h: TimeInterval = 3_600

    private func account(_ windows: [QuotaWindow], plan: String? = nil) -> AccountVM {
        Presenter.account(Account(provider: "p", name: "P", plan: plan, user: "u@example.com", windows: windows),
                          id: "p|u", ordinal: 1, commonPlan: plan, hideEmails: false)
    }

    private func window(_ name: String, _ remaining: Double?) -> QuotaWindow {
        QuotaWindow(name: name, remaining: remaining)
    }

    @Test func slotComesFromTheParsedLength() {
        #expect(Presenter.slot(of: WindowVM(name: "5 hours", remaining: 50)) == .fiveHour)
        #expect(Presenter.slot(of: WindowVM(name: "Gemini · 5 hours", remaining: 50)) == .fiveHour)
        #expect(Presenter.slot(of: WindowVM(name: "7 days", remaining: 50)) == .weekly)
        #expect(Presenter.slot(of: WindowVM(name: "Claude & GPT · 7 days", remaining: 50)) == .weekly)
        // Neither slot: credits, month, model pools, single days/hours.
        #expect(Presenter.slot(of: WindowVM(name: "Credits", remaining: 50)) == nil)
        #expect(Presenter.slot(of: WindowVM(name: "Extra credits", remaining: 50)) == nil)
        #expect(Presenter.slot(of: WindowVM(name: "Month", remaining: 50)) == nil)
        #expect(Presenter.slot(of: WindowVM(name: "1 day", remaining: 50)) == nil)
        #expect(Presenter.slot(of: WindowVM(name: "Claude Opus 4.6 (Thinking)", remaining: 50)) == nil)
        // Slot lengths are the parsed window lengths, not the abbreviated label.
        #expect(WindowSlot.fiveHour.length == 5 * h)
        #expect(WindowSlot.weekly.length == 7 * 86_400)
    }

    @Test func bothSlotsStackFiveHourAboveSevenDay() throws {
        let vm = account([window("5 hours", 80), window("7 days", 42)])
        let lines = Presenter.rowLines(for: vm)
        #expect(lines.map(\.slot) == [.fiveHour, .weekly])
        #expect(lines.map(\.label) == ["5h", "7d"])
        #expect(lines.map(\.window?.remaining) == [80, 42])
        // The tightest line is the one the row colours and projects from.
        #expect(lines.map(\.isTightest) == [false, true])
        #expect(Presenter.tightestWindow(in: lines)?.remaining == 42)
        #expect(try #require(Presenter.tightestWindow(in: lines)).name == "7 days")
    }

    @Test func payloadOrderDoesNotDecideTheStack() {
        let vm = account([window("7 days", 90), window("5 hours", 12)])
        let lines = Presenter.rowLines(for: vm)
        #expect(lines.map(\.slot) == [.fiveHour, .weekly])
        #expect(lines.map(\.isTightest) == [true, false])
    }

    @Test func tightestOfEachSlotWinsWhenPoolsQualifyTheName() {
        // Four windows (two pools): the row keeps one 5h and one 7d, each the tightest of its length.
        let vm = account([window("Gemini · 7 days", 66), window("Gemini · 5 hours", 99),
                          window("Claude & GPT · 7 days", 100), window("Claude & GPT · 5 hours", 30)])
        let lines = Presenter.rowLines(for: vm)
        #expect(lines.map(\.window?.name) == ["Claude & GPT · 5 hours", "Gemini · 7 days"])
        #expect(lines.map(\.label) == ["5h", "7d"])
        #expect(lines.map(\.isTightest) == [true, false])
    }

    @Test func equalRemainingKeepsTheFiveHourLineTightest() {
        let lines = Presenter.rowLines(for: account([window("5 hours", 40), window("7 days", 40)]))
        #expect(lines.map(\.isTightest) == [true, false])
        #expect(Presenter.tightestWindow(in: lines)?.name == "5 hours")
    }

    @Test func missingWeeklyKeepsTheSlotAsAPlaceholder() throws {
        let vm = account([window("5 hours", 12)])
        let lines = Presenter.rowLines(for: vm)
        #expect(lines.count == 2)
        let weekly = try #require(lines.last)
        #expect(weekly.slot == .weekly)
        #expect(weekly.window == nil)          // grey track + "—", columns stay aligned
        #expect(weekly.isTightest == false)
        #expect(lines.first?.isTightest == true)
        #expect(weekly.accessibilityText == "7-day window not reported")
    }

    @Test func missingFiveHourKeepsTheSlotAsAPlaceholder() throws {
        let vm = account([window("7 days", 0)])
        let lines = Presenter.rowLines(for: vm)
        let five = try #require(lines.first)
        #expect(five.slot == .fiveHour)
        #expect(five.window == nil)
        #expect(five.accessibilityText == "5-hour window not reported")
        // The reported slot is still the tightest, even at 0 %.
        #expect(lines.map(\.isTightest) == [false, true])
        #expect(Presenter.tightestWindow(in: lines)?.remaining == 0)
    }

    @Test func neitherSlotKeepsTheSingleLineRow() {
        // Credit-only account: one line with its abbreviated window name, as before.
        let credits = Presenter.rowLines(for: account([window("Credits", 74), window("Extra credits", 8)]))
        #expect(credits.count == 1)
        #expect(credits[0].slot == nil)
        #expect(credits[0].label == "Extra")           // abbreviation rule, binding window
        #expect(credits[0].window?.remaining == 8)
        #expect(credits[0].isTightest)
        // Model-pool-only account, and a slotted-plus-unslotted account (Month stays in the tooltip).
        #expect(Presenter.rowLines(for: account([window("Gemini 3 Flash", 100)])).map(\.slot) == [nil])
        let mixed = Presenter.rowLines(for: account([window("5 hours", 100), window("7 days", 99),
                                                     window("Month", 100)]))
        #expect(mixed.map(\.slot) == [.fiveHour, .weekly])
        #expect(mixed.compactMap(\.window?.name) == ["5 hours", "7 days"])
        // No window at all → nothing to draw (error / no-quota rows use their own layout).
        #expect(Presenter.rowLines(for: account([])).isEmpty)
    }

    @Test func slotWindowWithoutRemainingIsNotTightest() {
        let lines = Presenter.rowLines(for: account([window("5 hours", nil), window("7 days", 55)]))
        #expect(lines.map(\.window?.remaining) == [nil, 55])
        #expect(lines.map(\.isTightest) == [false, true])
        // A slot whose only window has no value stays selected (label + "—"), never dropped.
        let unknown = Presenter.rowLines(for: account([window("5 hours", nil)]))
        #expect(unknown.map(\.slot) == [.fiveHour, .weekly])
        #expect(unknown.map(\.isTightest) == [false, false])
        #expect(Presenter.tightestWindow(in: unknown) == nil)
    }

    @Test func valueColumnTextUsesABareEmDashForAMissingSlot() {
        #expect(Presenter.percentText(47) == "47%")
        #expect(Presenter.percentText(0.3) == "<1%")
        #expect(Presenter.percentText(nil) == "—")
        let lines = Presenter.rowLines(for: account([window("5 hours", 12)]))
        #expect(lines.map { Presenter.percentText($0.window?.remaining) } == ["12%", "—"])
    }

    @Test func accessibilityTextNamesTheFullWindow() throws {
        let lines = Presenter.rowLines(for: account([window("Gemini · 5 hours", 47), window("7 days", 96)]))
        #expect(try #require(lines.first).accessibilityText == "Gemini · 5 hours: 47% left")
        #expect(try #require(lines.last).accessibilityText == "7 days: 96% left")
    }

    @Test func everyFixtureUsableRowDrawsOneOrTwoAlignedLines() throws {
        let providers = Presenter.providers(from: FixtureQuotaSource.loadSync().data, hideEmails: false)
        let rows = providers.flatMap { [$0.hero].compactMap { $0 } + $0.rows + $0.nearlyEmpty }
        #expect(!rows.isEmpty)
        for row in rows {
            let lines = Presenter.rowLines(for: row)
            #expect((1...2).contains(lines.count), "\(row.label) has \(lines.count) lines")
            #expect(Set(lines.map(\.id)).count == lines.count)
            // At most one tightest line, and it is the one with the lowest known remaining.
            #expect(lines.filter(\.isTightest).count <= 1)
            let known = lines.compactMap(\.window?.remaining)
            if let tightest = lines.first(where: \.isTightest) {
                #expect(tightest.window?.remaining == known.min())
            } else {
                #expect(known.isEmpty)
            }
            // Two-line rows always carry both slots, in order.
            if lines.count == 2 { #expect(lines.map(\.slot) == [.fiveHour, .weekly]) }
        }
        // The fixture's 7d-only account keeps a placeholder 5h slot.
        let codex = try #require(providers.first { $0.id == "codex" })
        let sevenDayOnly = try #require(codex.nearlyEmpty.first { $0.label == "account6" })
        #expect(Presenter.rowLines(for: sevenDayOnly).map { $0.window?.name } == [nil, "7 days"])
    }
}
