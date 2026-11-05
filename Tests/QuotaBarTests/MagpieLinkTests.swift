import Foundation
import Testing
@testable import QuotaBar

/// "Open Magpie" is one URL constant plus one injectable call. `BrowserOpener` — the live edge
/// that launches Safari — is never reached here: tests record the URL instead.
@MainActor @Suite struct MagpieLinkTests {
    @Test func urlIsTheMagpieWebsite() {
        #expect(MagpieLink.url.absoluteString == "https://magpie.isjia.page/")
        #expect(MagpieLink.url.scheme == "https")
        #expect(MagpieLink.url.host() == "magpie.isjia.page")
    }

    @Test func openActionHandsThePageToTheOpener() {
        var received: [URL] = []
        let action = OpenMagpieAction(open: { received.append($0) })

        action()
        action()

        #expect(received == [MagpieLink.url, MagpieLink.url], "one open per call, always the same page")
    }
}
