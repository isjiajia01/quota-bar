import Testing
@testable import QuotaBar

@Suite struct ProviderAccentTests {
    @Test func knownProvidersHaveTheirOwnHue() {
        let names = ["claude", "codex", "antigravity", "workbuddy-ai", "workbuddy", "zcode"]
            .map { Palette.accent(forProvider: $0).name }
        #expect(Set(names).count == names.count)  // each a distinct accent
        #expect(Palette.accent(forProvider: "claude").name == "terracotta")
        #expect(Palette.accent(forProvider: "Claude").name == "terracotta")  // case-insensitive
        #expect(Palette.accent(forProvider: "opencode-go").name == Palette.accent(forProvider: "opencode-zen-free").name)
    }

    @Test func unknownProvidersNeverTakeAWarningHue() {
        let first = Palette.accent(forProvider: "some-new-provider").name
        #expect(Palette.accent(forProvider: "some-new-provider").name == first)  // stable for one ID
        #expect(!["terracotta"].contains(first))  // fallbacks exclude the warm brand hue next to amber
    }

    @Test func newProvidersAvoidKnownHuesWhileFreeHuesLast() {
        let known = ["claude", "codex", "antigravity", "workbuddy-ai", "workbuddy", "zcode"]
        let accents = Palette.accents(for: known + ["new-a", "new-b"])
        let knownHues = known.compactMap { Palette.accent(forProvider: $0).hue }
        for newcomer in ["new-a", "new-b"] {
            let hue = accents[newcomer]?.hue ?? -1
            #expect(hue >= 0)
            #expect(knownHues.allSatisfy { known in
                let d = abs(known - hue).truncatingRemainder(dividingBy: 360)
                return min(d, 360 - d) > 15
            })
        }
        #expect(accents["new-a"]?.name != accents["new-b"]?.name)
    }

    @Test func assignmentDoesNotDependOnPayloadOrder() {
        let forward = Palette.accents(for: ["new-a", "new-b", "claude"])
        let reversed = Palette.accents(for: ["claude", "new-b", "new-a"])
        #expect(forward["new-a"]?.name == reversed["new-a"]?.name)
        #expect(forward["new-b"]?.name == reversed["new-b"]?.name)
    }

    @Test func emptyAndSingleProviderPayloadsWork() {
        #expect(Palette.accents(for: []).isEmpty)
        #expect(Palette.accents(for: ["solo"])["solo"] != nil)
    }
}
