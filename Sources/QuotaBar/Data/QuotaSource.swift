import Foundation
import Observation
import Security

/// Data source boundary: one fetch per call, no scheduling policy.
protocol QuotaSource: Sendable {
    func fetch() async throws -> QuotaPayload
}

enum QuotaSourceError: Error, Sendable { case http(Int), malformed, noToken }

/// Reads the scrubbed sample. Path is resolved from the source tree (dev/test only;
/// a packaged app would need a resource bundle).
struct FixtureQuotaSource: QuotaSource {
    static let defaultURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Data
        .deletingLastPathComponent()  // QuotaBar
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // repo root
        .appending(path: "fixtures/quotas.sample.json")

    var url: URL = defaultURL

    func fetch() async throws -> QuotaPayload {
        do { return try QuotaPayload.decode(try Data(contentsOf: url)) }
        catch is DecodingError { throw QuotaSourceError.malformed }
    }

    static func loadSync() -> QuotaPayload {
        (try? QuotaPayload.decode(Data(contentsOf: defaultURL))) ?? QuotaPayload(data: [])
    }
}

/// The Magpie endpoint behind the public HTTPS gateway (Caddy on llm.isjia.page → :3425);
/// Magpie authenticates the bearer token. No Tailscale or tunnel: works with any VPN on.
struct LiveQuotaSource: QuotaSource {
    static let endpoint = URL(string: "https://llm.isjia.page/v1/magpie/quotas")!
    /// Bound on one attempt.
    static let timeout: TimeInterval = 8

    var endpoint: URL = LiveQuotaSource.endpoint
    var timeout: TimeInterval = LiveQuotaSource.timeout
    var session: URLSession = .quotas
    /// Injected in tests; the app reads the login Keychain.
    var token: @Sendable () -> String? = MagpieToken.current

    func fetch() async throws -> QuotaPayload {
        guard let bearer = token(), !bearer.isEmpty else { throw QuotaSourceError.noToken }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw QuotaSourceError.http(http.statusCode)
        }
        // The body never reaches a log: only its decode result or the issue kind leaves here.
        do { return try QuotaPayload.decode(data) } catch { throw QuotaSourceError.malformed }
    }
}

/// The Magpie bearer token, read from the login Keychain. Never a file, a default or a log line.
/// `QUOTABAR_TOKEN` exists for a development run only.
enum MagpieToken {
    static let service = "magpie-quota"
    static let account = "quota-bar"

    static func current() -> String? {
        if let env = ProcessInfo.processInfo.environment["QUOTABAR_TOKEN"], !env.isEmpty { return env }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }
}

extension URLSession {
    /// Ephemeral session: no cache, no connectivity waiting, bounded attempts.
    static let quotas: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = LiveQuotaSource.timeout
        config.timeoutIntervalForResource = LiveQuotaSource.timeout * 2
        return URLSession(configuration: config)
    }()
}

extension TransportIssue {
    init(_ error: Error) {
        switch error {
        case QuotaSourceError.http(let code): self = .http(code)
        case QuotaSourceError.malformed: self = .malformed
        case QuotaSourceError.noToken:
            self = .other("No Magpie token. Add it to Keychain: service magpie-quota, account quota-bar.")
        case let e as URLError where e.code == .timedOut: self = .timedOut
        case let e as URLError where [.cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .notConnectedToInternet].contains(e.code):
            self = .unreachable
        default: self = .other("Couldn't load quotas.")  // no raw error text: may carry identities
        }
    }
}

/// When the store fetches (pure, so the cadence is testable without a clock).
/// The status item shows no number, so a hidden panel only needs data that is fresh enough
/// to open on: it polls slowly, and opening the panel refreshes at once when the data is old.
struct RefreshPolicy: Sendable, Equatable {
    /// Cadence while the panel is on screen.
    var visible: Duration = .seconds(60)
    /// Cadence while the panel is closed.
    var hidden: Duration = .seconds(300)
    /// Ceiling for the failure backoff (doubling from the current cadence).
    var maxBackoff: Duration = .seconds(900)
    /// Opening the panel refreshes immediately when the last attempt is older than this.
    var staleOnOpen: Duration = .seconds(30)

    static let standard = RefreshPolicy()

    /// One fixed cadence (tests, dev runs): no visibility split, no backoff growth.
    static func fixed(_ interval: Duration) -> RefreshPolicy {
        RefreshPolicy(visible: interval, hidden: interval, maxBackoff: interval, staleOnOpen: interval)
    }

    /// Delay between attempts: the visibility cadence, doubled per consecutive failure, capped.
    func delay(panelVisible: Bool, failures: Int) -> Duration {
        let base = panelVisible ? visible : hidden
        guard failures > 0 else { return base }
        let factor = 1 << min(failures, 10)
        let cap = max(base, maxBackoff)
        return base * factor > cap ? cap : base * factor
    }

    /// Timer slack handed to the system so wake-ups coalesce with other work (10 % of the delay).
    func tolerance(for delay: Duration) -> Duration { delay / 10 }
}

/// Why polling is paused. Polling resumes only when every reason has cleared.
enum RefreshPause: Hashable, Sendable { case systemSleep, screensAsleep, sessionInactive }

/// App-lifetime owner of data. One fetch in flight; a new refresh supersedes the old.
/// The loop and the immediate refresh both go through `refresh()`, so Retry/⟳ never stacks work.
/// Cadence follows `RefreshPolicy`: fast while the panel is open, slow while it is closed,
/// backing off after failures, and paused while the Mac sleeps, the screens are off or the
/// user session is switched out.
@MainActor @Observable
final class QuotaStore {
    private(set) var state: PanelState = .loading
    private(set) var isRefreshing = false
    private var lastGood: PanelSnapshot?
    private var attempt: Task<Void, Never>?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let source: any QuotaSource
    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private var policy: RefreshPolicy = .standard
    @ObservationIgnored private var running = false
    @ObservationIgnored private var lastAttempt: ContinuousClock.Instant?
    @ObservationIgnored private(set) var consecutiveFailures = 0
    @ObservationIgnored private(set) var isPanelVisible = false
    @ObservationIgnored private var pauses: Set<RefreshPause> = []

    init(source: any QuotaSource) { self.source = source }

    /// Refreshes now, then on the policy's cadence until `stopAutoRefresh()`. Idempotent.
    func startAutoRefresh(policy: RefreshPolicy = .standard) {
        guard !running else { return }
        self.policy = policy
        running = true
        restartLoop()
    }

    /// Fixed cadence (tests and dev runs).
    func startAutoRefresh(interval: TimeInterval) {
        startAutoRefresh(policy: .fixed(.milliseconds(Int(interval * 1000))))
    }

    func stopAutoRefresh() {
        running = false
        loop?.cancel()
        loop = nil
    }

    /// The panel came on screen: refresh at once if the data is old, then poll at the visible cadence.
    func panelDidOpen() {
        isPanelVisible = true
        if pauses.isEmpty, lastGood == nil || age(atLeast: policy.staleOnOpen) { refresh() }
        restartLoop()
    }

    /// The panel left the screen: fall back to the hidden cadence (no immediate fetch).
    func panelDidClose() {
        isPanelVisible = false
        restartLoop()
    }

    /// Pauses or resumes polling for one reason. Resuming fetches at once only if an attempt is due.
    func setPaused(_ reason: RefreshPause, _ paused: Bool) {
        let wasPaused = !pauses.isEmpty
        if paused { pauses.insert(reason) } else { pauses.remove(reason) }
        if wasPaused != !pauses.isEmpty { restartLoop() }
    }

    /// The loop sleeps until the next attempt is due, measured from the last attempt of any kind,
    /// so a manual ⟳ or an open-refresh postpones the timer instead of adding a fetch.
    private func restartLoop() {
        loop?.cancel()
        loop = nil
        guard running, pauses.isEmpty else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = self.timeUntilDue()
                if wait > .zero {
                    try? await Task.sleep(for: wait, tolerance: self.policy.tolerance(for: wait), clock: .continuous)
                    continue  // re-check: a manual refresh may have moved the due time
                }
                await self.refresh().value
            }
        }
    }

    private func timeUntilDue() -> Duration {
        guard let lastAttempt else { return .zero }
        let delay = policy.delay(panelVisible: isPanelVisible, failures: consecutiveFailures)
        return delay - (clock.now - lastAttempt)
    }

    private func age(atLeast limit: Duration) -> Bool {
        guard let lastAttempt else { return true }
        return clock.now - lastAttempt >= limit
    }

    @discardableResult
    func refresh() -> Task<Void, Never> {
        attempt?.cancel()
        isRefreshing = true
        lastAttempt = clock.now
        let task = Task { [source] in
            do {
                let payload = try await source.fetch()
                try Task.checkCancellation()
                consecutiveFailures = 0
                apply(payload)
            } catch {
                // URLSession reports its own cancellation as `URLError(.cancelled)`, so the
                // task flag — not the error type — decides whether this attempt still counts.
                if Task.isCancelled { return }  // superseded; the newer attempt owns `isRefreshing`
                consecutiveFailures += 1
                fail(TransportIssue(error))
            }
            isRefreshing = false
        }
        attempt = task
        return task
    }

    private func apply(_ payload: QuotaPayload) {
        let snapshot = PanelSnapshot(accounts: payload.data, fetchedAt: .now)
        guard !payload.data.isEmpty else {
            // An empty answer keeps the empty page: there is no list to retain, so a later
            // failure reports the connection, not a blank stale panel.
            lastGood = nil
            state = .empty(fetchedAt: snapshot.fetchedAt)
            return
        }
        lastGood = snapshot
        state = .content(snapshot)
    }

    private func fail(_ issue: TransportIssue) {
        state = lastGood.map { .stale($0, issue) } ?? .error(issue)
    }
}
