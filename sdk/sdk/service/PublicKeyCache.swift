import Foundation

/// In-memory cache for the merchant's encryption JWK fetched from `GET /cards/public-key`.
///
/// Cleared on process death by design — the key is non-sensitive but rotates, and the SDK avoids
/// on-disk persistence. Concurrent fetches are single-flighted: callers that arrive while a fetch
/// is in flight await the same `Task` rather than each firing their own request. Mirrors the
/// Android `PublicKeyCache`.
actor PublicKeyCache {
    private let publicAPI: PublicAPI
    private var cached: GopayJWK?
    private var inFlight: Task<GopayJWK, Error>?

    init(publicAPI: PublicAPI) {
        self.publicAPI = publicAPI
    }

    func get(forceRefresh: Bool = false) async throws -> GopayJWK {
        if !forceRefresh, let cached = cached {
            return cached
        }
        if let inFlight = inFlight {
            return try await inFlight.value
        }

        let task = Task { try await publicAPI.getPublicKey() }
        inFlight = task
        defer { inFlight = nil }

        let jwk = try await task.value
        cached = jwk
        return jwk
    }

    func invalidate() {
        cached = nil
    }
}
