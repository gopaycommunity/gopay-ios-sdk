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

    public func makeURL(path: String) -> URL? {
        return URL(string: baseURL + path)
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
