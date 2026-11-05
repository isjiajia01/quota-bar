import Foundation
import Observation

/// Data source boundary: one fetch per call, no scheduling policy.
protocol QuotaSource: Sendable {
    func fetch() async throws -> QuotaPayload
}

enum QuotaSourceError: Error, Sendable { case http(Int), malformed }

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

/// The tunnel endpoint. No auth: `ssh -N -L 13425:127.0.0.1:3425 oracle` forwards loopback only.
struct LiveQuotaSource: QuotaSource {
    static let endpoint = URL(string: "http://127.0.0.1:13425/v1/magpie/quotas")!
    /// Bound on one attempt, a stalled tunnel included.
    static let timeout: TimeInterval = 8

    var endpoint: URL = LiveQuotaSource.endpoint
    var timeout: TimeInterval = LiveQuotaSource.timeout
    var session: URLSession = .quotas

    func fetch() async throws -> QuotaPayload {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw QuotaSourceError.http(http.statusCode)
        }
        // The body never reaches a log: only its decode result or the issue kind leaves here.
        do { return try QuotaPayload.decode(data) } catch { throw QuotaSourceError.malformed }
    }
}

extension URLSession {
    /// Ephemeral session for the tunnel: no cache, no connectivity waiting, bounded attempts.
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
        case let e as URLError where e.code == .timedOut: self = .timedOut
        case let e as URLError where [.cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .notConnectedToInternet].contains(e.code):
            self = .unreachable
        default: self = .other("Couldn't load quotas.")  // no raw error text: may carry identities
        }
    }
}

/// App-lifetime owner of data. One fetch in flight; a new refresh supersedes the old.
/// The loop and the immediate refresh both go through `refresh()`, so Retry/⟳ never stacks work.
@MainActor @Observable
final class QuotaStore {
    /// Best effort, not an exact schedule: App Nap and timer coalescing apply.
    static let refreshInterval: TimeInterval = 60

    private(set) var state: PanelState = .loading
    private(set) var isRefreshing = false
    private var lastGood: PanelSnapshot?
    private var attempt: Task<Void, Never>?
    private var loop: Task<Void, Never>?
    private let source: any QuotaSource

    init(source: any QuotaSource) { self.source = source }

    /// Refreshes now, then every `interval` until `stopAutoRefresh()`. Idempotent.
    func startAutoRefresh(interval: TimeInterval = QuotaStore.refreshInterval) {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh().value
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopAutoRefresh() {
        loop?.cancel()
        loop = nil
    }

    @discardableResult
    func refresh() -> Task<Void, Never> {
        attempt?.cancel()
        isRefreshing = true
        let task = Task { [source] in
            do {
                let payload = try await source.fetch()
                try Task.checkCancellation()
                apply(payload)
            } catch {
                // URLSession reports its own cancellation as `URLError(.cancelled)`, so the
                // task flag — not the error type — decides whether this attempt still counts.
                if Task.isCancelled { return }  // superseded; the newer attempt owns `isRefreshing`
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
