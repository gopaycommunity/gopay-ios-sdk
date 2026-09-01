import Foundation

/// Async HTTP surface used by the per-payment session API layer.
///
/// Returns the `HTTPURLResponse` alongside the body so callers can branch on the status code
/// (e.g. retry a 401, map a 4xx/5xx to ``GopaySDKError``).
protocol AsyncHTTPClient {
    var baseURL: String { get }
    func makeURL(path: String) -> URL?
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession-backed HTTP client. The single low-level networking primitive for the SDK.
public class DefaultNetworkClient: NSObject, URLSessionDelegate {
    public let baseURL: String
    private let session: URLSession

    public init(baseURL: String, configuration: URLSessionConfiguration = .default) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        super.init()
    }

    /// Builds a request URL by concatenating `path` onto ``baseURL``, or returns `nil` when the
    /// result is not an absolute `http(s)` URL with a host.
    ///
    /// The guard is there because an empty or scheme-less ``baseURL`` — possible only through
    /// `.development(baseURL:)` — yields a *relative* URL that
    /// `URL(string:)` accepts happily and `URLSession` then rejects as `unsupported URL (-1002)`,
    /// far from the configuration that caused it. Callers map `nil` to
    /// ``GopaySDKError/Code/invalidBaseURL`` (`CONFIG_006`) instead, which names the real problem.
    /// OkHttp's `HttpUrl` on Android refuses the same inputs, so this keeps the two SDKs aligned.
    public func makeURL(path: String) -> URL? {
        guard let url = URL(string: baseURL + path),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    // URLSessionDelegate methods for SSL pinning or custom certificate handling can be added here.
}

extension DefaultNetworkClient: AsyncHTTPClient {
    /// Sends a request and returns the body together with the `HTTPURLResponse`.
    ///
    /// Wraps the completion-based `dataTask` in a continuation — `URLSession.data(for:)` is iOS
    /// 15+, while this SDK supports iOS 13. Attaches the `User-Agent` header.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var mutableRequest = request
        let userAgent = "GoPay iOS SDK \(GopaySDK.version)"
        mutableRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: mutableRequest) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
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
            task.resume()
        }
    }
}
