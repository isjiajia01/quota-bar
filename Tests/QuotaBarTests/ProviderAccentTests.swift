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

    @Test func unknownProvidersGetAStableNonWarningAccent() {
        let first = Palette.accent(forProvider: "some-new-provider").name
        #expect(Palette.accent(forProvider: "some-new-provider").name == first)  // FNV-1a, not Hasher
        #expect(!["terracotta"].contains(first))  // fallbacks exclude the warm brand hue next to amber
    }
}
