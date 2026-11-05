import Foundation
import Observation

/// Data source stub boundary. Polling policy is out of scope for the skeleton.
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

struct LiveQuotaSource: QuotaSource {
    static let endpoint = URL(string: "http://127.0.0.1:13425/v1/magpie/quotas")!
    var timeout: TimeInterval = 5

    func fetch() async throws -> QuotaPayload {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw QuotaSourceError.http(http.statusCode)
        }
        do { return try QuotaPayload.decode(data) } catch { throw QuotaSourceError.malformed }
    }
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

/// App-lifetime owner of data. One refresh at a time; a new refresh supersedes the old.
@MainActor @Observable
final class QuotaStore {
    private(set) var state: PanelState = .loading
    private(set) var isRefreshing = false
    private var lastGood: PanelSnapshot?
    private var task: Task<Void, Never>?
    private let source: any QuotaSource

    init(source: any QuotaSource) { self.source = source }

    func refresh() {
        task?.cancel()
        isRefreshing = true
        task = Task { [source] in
            do {
                let payload = try await source.fetch()
                try Task.checkCancellation()
                let snap = PanelSnapshot(accounts: payload.data, fetchedAt: .now)
                lastGood = snap
                state = payload.data.isEmpty ? .empty(fetchedAt: snap.fetchedAt) : .content(snap)
            } catch is CancellationError {
                return
            } catch {
                let issue = TransportIssue(error)
                state = lastGood.map { .stale($0, issue) } ?? .error(issue)
            }
            isRefreshing = false
        }
    }
}
