import Foundation

/// Async HTTP surface used by the per-payment session API layer.
///
/// Returns the `HTTPURLResponse` alongside the body so callers can branch on the status code
/// (e.g. retry a 401, map a 4xx/5xx to ``GopaySDKError``).
protocol AsyncHTTPClient {
    var baseUrl: String { get }
    func makeURL(path: String) -> URL?
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// ``send(_:)``, and when `cancellable` is `true`, a cancelled task drops the request in flight
    /// and throws `CancellationError` instead of waiting for the answer.
    func send(_ request: URLRequest, cancellable: Bool) async throws -> (Data, HTTPURLResponse)
}

extension AsyncHTTPClient {
    /// A client that cannot drop a request in flight sends it as ``send(_:)`` does.
    func send(_ request: URLRequest, cancellable _: Bool) async throws -> (Data, HTTPURLResponse) {
        try await send(request)
    }
}

/// URLSession-backed HTTP client. The single low-level networking primitive for the SDK.
/// `@unchecked Sendable`: its two properties are set once and `URLSession` is thread-safe.
final class DefaultNetworkClient: @unchecked Sendable {
    let baseUrl: String
    private let session: URLSession

    init(baseUrl: String, configuration: URLSessionConfiguration = .default) {
        self.baseUrl = baseUrl
        self.session = URLSession(configuration: configuration)
    }

    /// Builds a request URL by concatenating `path` onto ``baseUrl``, or returns `nil` when the
    /// result is not an absolute `http(s)` URL with a host.
    ///
    /// The guard is there because an empty or scheme-less ``baseUrl`` — possible only through
    /// `.development(baseUrl:)` — yields a *relative* URL that
    /// `URL(string:)` accepts happily and `URLSession` then rejects as `unsupported URL (-1002)`,
    /// far from the configuration that caused it. Callers map `nil` to
    /// ``GopaySDKError/Code/invalidBaseURL`` (`CONFIG_006`) instead, which names the real problem.
    /// OkHttp's `HttpUrl` on Android refuses the same inputs, so this keeps the two SDKs aligned.
    func makeURL(path: String) -> URL? {
        guard let url = URL(string: baseUrl + path),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    /// What the SDK's own requests send as `User-Agent`: the gateway's, and the telemetry's.
    static var userAgent: String { "GoPay iOS SDK \(GopaySDK.version)" }
}

extension DefaultNetworkClient: AsyncHTTPClient {
    /// Sends a request and returns the body together with the `HTTPURLResponse`.
    ///
    /// Wraps the completion-based `dataTask` in a continuation — `URLSession.data(for:)` is iOS
    /// 15+, while this SDK supports iOS 13.
    ///
    /// Identifies the SDK in the `User-Agent` header of every request that does not set one
    /// itself. A request that names its own User-Agent keeps it: `GET /cards/browser-data` sends
    /// the 3DS challenge WebView's, because the gateway echoes the header back as
    /// `browser_data.user_agent` and the issuer expects that value to match the browser it later
    /// sees. Overwriting it here would put the SDK's HTTP client name into the AReq instead.
    ///
    /// A request that gets no HTTP response throws a ``GopaySDKError`` from
    /// ``GopaySDKError/transport(_:)``, never the bare `URLError`; a cancelled one throws
    /// `CancellationError`.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await send(request, cancellable: false)
    }

    /// ``send(_:)``, which with `cancellable` also drops the data task when the calling task is
    /// cancelled. Only `POST /payments/{id}/init-session` asks for that: every other request runs
    /// to its answer, so a charge the caller stops waiting for still ends as the gateway decided.
    func send(_ request: URLRequest, cancellable: Bool) async throws -> (Data, HTTPURLResponse) {
        var mutableRequest = request
        if mutableRequest.value(forHTTPHeaderField: "User-Agent") == nil {
            mutableRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        }

        guard cancellable else {
            return try await withCheckedThrowingContinuation { continuation in
                dataTask(mutableRequest, continuation: continuation).resume()
            }
        }
        let handle = DataTaskHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                handle.start(dataTask(mutableRequest, continuation: continuation))
            }
        } onCancel: {
            handle.cancel()
        }
    }

    private func dataTask(
        _ request: URLRequest,
        continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
    ) -> URLSessionDataTask {
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                // A cancelled request is not a failed transport and must not read as NETWORK_007.
                // Only a cancellable request is ever cancelled.
                if (error as? URLError)?.code == .cancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: GopaySDKError.transport(error))
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                continuation.resume(throwing: GopaySDKError(
                    .unexpected,
                    message: "Expected an HTTP response but got none"
                ))
                return
            }
            continuation.resume(returning: (data ?? Data(), http))
        }
    }
}

/// The data task of one cancellable request, which the cancellation handler may reach before the
/// task exists: a cancel that comes first keeps the task from being sent at all.
private final class DataTaskHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    func start(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let cancelled = self.cancelled
        lock.unlock()
        // Cancelled before it started: never sent. Cancelling a task that was never resumed still
        // completes it, with URLError.cancelled, so the caller's continuation is resumed.
        if cancelled {
            task.cancel()
        } else {
            task.resume()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}
