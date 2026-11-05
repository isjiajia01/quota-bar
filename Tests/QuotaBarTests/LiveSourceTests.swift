import Foundation
import Testing
@testable import QuotaBar

/// URLProtocol stub for the live source. Handlers are keyed by request URL, so tests that run
/// in parallel never share one. No test here touches the real tunnel.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int = 200
        var body: Data = Data()

        static func json(_ text: String) -> Reply { Reply(body: Data(text.utf8)) }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable (URLRequest) throws -> Reply] = [:]
    nonisolated(unsafe) private static var counts: [String: Int] = [:]

    static func install(for url: URL, _ handler: @escaping @Sendable (URLRequest) throws -> Reply) {
        lock.lock(); defer { lock.unlock() }
        handlers[url.absoluteString] = handler
        counts[url.absoluteString] = 0
    }

    static func uninstall(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        handlers[url.absoluteString] = nil
        counts[url.absoluteString] = nil
    }

    /// Number of requests the stub answered for `url`.
    static func requestCount(_ url: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[url.absoluteString] ?? 0
    }

    private static func take(for url: URL?) -> (@Sendable (URLRequest) throws -> Reply)? {
        guard let key = url?.absoluteString else { return nil }
        lock.lock(); defer { lock.unlock() }
        counts[key, default: 0] += 1
        return handlers[key]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.take(for: request.url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let reply = try handler(request)
            let url = request.url ?? LiveQuotaSource.endpoint
            let response = HTTPURLResponse(url: url, statusCode: reply.status,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// Each test gets its own stub URL, so nothing here is order-dependent.
enum StubTunnel {
    static func url(_ name: String) -> URL {
        URL(string: "http://127.0.0.1:13425/v1/magpie/quotas/\(name)")!
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        // A stub that throws is what models a timeout; this only bounds a stuck stub.
        config.timeoutIntervalForRequest = 2
        return URLSession(configuration: config)
    }

    static func source(_ url: URL) -> LiveQuotaSource {
        LiveQuotaSource(endpoint: url, timeout: 2, session: session())
    }
}

private let oneAccountJSON = #"""
{"data":[{"provider":"claude","name":"Claude","plan":"Claude Max",
"windows":[{"name":"5 hours","used":57.5,"remaining":42.5,"resetsAt":"2026-11-05T21:49:00Z"}]}]}
"""#

@Suite struct LiveQuotaSourceTests {
    @Test func decodesSuccessResponse() async throws {
        let url = StubTunnel.url("success")
        StubURLProtocol.install(for: url) { _ in .json(oneAccountJSON) }
        defer { StubURLProtocol.uninstall(url) }

        let payload = try await StubTunnel.source(url).fetch()
        #expect(payload.data.count == 1)
        #expect(payload.data[0].provider == "claude")
        #expect(payload.data[0].windows[0].remaining == 42.5)
        #expect(payload.data[0].windows[0].resetsAt != nil)
    }

    @Test func refusedConnectionIsUnreachable() async throws {
        let url = StubTunnel.url("refused")
        StubURLProtocol.install(for: url) { _ in throw URLError(.cannotConnectToHost) }
        defer { StubURLProtocol.uninstall(url) }

        do {
            _ = try await StubTunnel.source(url).fetch()
            Issue.record("connection refusal must throw")
        } catch {
            #expect(TransportIssue(error) == .unreachable)
        }
    }

    @Test func nonSuccessStatusIsHTTPIssue() async throws {
        let url = StubTunnel.url("http500")
        StubURLProtocol.install(for: url) { _ in
            StubURLProtocol.Reply(status: 500, body: Data("{}".utf8))
        }
        defer { StubURLProtocol.uninstall(url) }

        do {
            _ = try await StubTunnel.source(url).fetch()
            Issue.record("HTTP 500 must throw")
        } catch {
            #expect(TransportIssue(error) == .http(500))
        }
    }

    @Test func unreadableBodyIsMalformed() async throws {
        let url = StubTunnel.url("malformed")
        StubURLProtocol.install(for: url) { _ in .json(#"{"data":"not a list"}"#) }
        defer { StubURLProtocol.uninstall(url) }

        do {
            _ = try await StubTunnel.source(url).fetch()
            Issue.record("malformed body must throw")
        } catch {
            #expect(TransportIssue(error) == .malformed)
        }
    }
}

@MainActor @Suite struct QuotaStoreTests {
    @Test func firstSuccessIsContent() async throws {
        let url = StubTunnel.url("store-content")
        StubURLProtocol.install(for: url) { _ in .json(oneAccountJSON) }
        defer { StubURLProtocol.uninstall(url) }

        let store = QuotaStore(source: StubTunnel.source(url))
        #expect(store.state == .loading)
        await store.refresh().value
        #expect(store.isRefreshing == false)
        guard case .content(let snapshot) = store.state else {
            Issue.record("expected content, got \(store.state)")
            return
        }
        #expect(snapshot.accounts.count == 1)
    }

    @Test func firstFailureWithoutDataIsError() async throws {
        let url = StubTunnel.url("store-first-refused")
        StubURLProtocol.install(for: url) { _ in throw URLError(.cannotConnectToHost) }
        defer { StubURLProtocol.uninstall(url) }

        let store = QuotaStore(source: StubTunnel.source(url))
        await store.refresh().value
        #expect(store.state == .error(.unreachable))
    }

    @Test func timeoutKeepsLastSnapshotAsStale() async throws {
        let url = StubTunnel.url("store-timeout")
        let phase = Phase()
        StubURLProtocol.install(for: url) { _ in
            if phase.matches(1) { return .json(oneAccountJSON) }
            throw URLError(.timedOut)
        }
        defer { StubURLProtocol.uninstall(url) }

        let store = QuotaStore(source: StubTunnel.source(url))
        await store.refresh().value
        let good = try #require(store.state.snapshot)
        #expect(store.state == .content(good))

        phase.set(2)
        await store.refresh().value
        guard case .stale(let kept, let issue) = store.state else {
            Issue.record("expected stale, got \(store.state)")
            return
        }
        #expect(issue == .timedOut)
        #expect(kept == good)  // accounts and fetchedAt unchanged
        #expect(store.isRefreshing == false)
    }

    @Test func emptyPayloadIsEmptyStateAndLaterFailureIsError() async throws {
        let url = StubTunnel.url("store-empty")
        let phase = Phase()
        StubURLProtocol.install(for: url) { _ in
            if phase.matches(1) { return .json(#"{"data":[]}"#) }
            throw URLError(.cannotConnectToHost)
        }
        defer { StubURLProtocol.uninstall(url) }

        let store = QuotaStore(source: StubTunnel.source(url))
        await store.refresh().value
        guard case .empty = store.state else {
            Issue.record("expected empty, got \(store.state)")
            return
        }
        #expect(store.state.snapshot == nil)

        phase.set(2)
        await store.refresh().value
        #expect(store.state == .error(.unreachable))  // there is no list to keep visible
    }

    @Test func supersededRefreshNeverReportsAnError() async throws {
        let url = StubTunnel.url("store-supersede")
        StubURLProtocol.install(for: url) { _ in
            Thread.sleep(forTimeInterval: 0.2)  // keep the first attempt in flight
            return .json(oneAccountJSON)
        }
        defer { StubURLProtocol.uninstall(url) }

        let store = QuotaStore(source: StubTunnel.source(url))
        let first = store.refresh()
        let second = store.refresh()  // cancels the first
        await first.value
        // URLSession surfaces cancellation as URLError(.cancelled): it must not become state.
        if case .error(let issue) = store.state { Issue.record("superseded attempt reported \(issue)") }
        await second.value
        #expect(store.isRefreshing == false)
        #expect(store.state.snapshot != nil)
    }

    @Test func autoRefreshRefetchesOnIntervalAndStops() async throws {
        let url = StubTunnel.url("store-loop")
        StubURLProtocol.install(for: url) { _ in .json(oneAccountJSON) }
        defer { StubURLProtocol.uninstall(url) }

        let store = QuotaStore(source: StubTunnel.source(url))
        store.startAutoRefresh(interval: 0.05)
        for _ in 0..<200 where StubURLProtocol.requestCount(url) < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(StubURLProtocol.requestCount(url) >= 3)
        #expect(store.state.snapshot != nil)

        store.stopAutoRefresh()
        let settled = StubURLProtocol.requestCount(url)
        try await Task.sleep(for: .milliseconds(300))
        #expect(StubURLProtocol.requestCount(url) == settled)
    }
}

/// Phase switch shared with a stub handler (the stub runs off the main actor).
final class Phase: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 1

    func matches(_ phase: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return value == phase
    }

    func set(_ phase: Int) {
        lock.lock(); defer { lock.unlock() }
        value = phase
    }
}
