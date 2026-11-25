import Foundation
import Testing
@testable import QuotaBar

@Suite struct RefreshPolicyTests {
    let policy = RefreshPolicy.standard

    @Test func cadenceFollowsPanelVisibility() {
        #expect(policy.delay(panelVisible: true, failures: 0) == .seconds(60))
        #expect(policy.delay(panelVisible: false, failures: 0) == .seconds(300))
    }

    @Test func failuresDoubleTheDelayUpToTheCap() {
        #expect(policy.delay(panelVisible: true, failures: 1) == .seconds(120))
        #expect(policy.delay(panelVisible: true, failures: 2) == .seconds(240))
        #expect(policy.delay(panelVisible: true, failures: 5) == .seconds(900))
        #expect(policy.delay(panelVisible: false, failures: 1) == .seconds(600))
        #expect(policy.delay(panelVisible: false, failures: 3) == .seconds(900))
        #expect(policy.delay(panelVisible: false, failures: 1_000) == .seconds(900))
    }

    @Test func fixedPolicyNeverGrows() {
        let fixed = RefreshPolicy.fixed(.milliseconds(50))
        #expect(fixed.delay(panelVisible: false, failures: 0) == .milliseconds(50))
        #expect(fixed.delay(panelVisible: true, failures: 4) == .milliseconds(50))
    }

    @Test func toleranceIsATenth() {
        #expect(policy.tolerance(for: .seconds(300)) == .seconds(30))
    }
}
