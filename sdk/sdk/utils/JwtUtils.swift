import Foundation

/// Utility for JWT operations
public struct JwtUtils {
    /// Extracts the `exp` claim (Unix seconds) from a JWT.
    ///
    /// Returns `0` when the claim is absent or the token can't be decoded — callers treat `0` as
    /// "no known expiry". Use this to capture the expiry once at token-issue time and avoid
    /// re-parsing the JWT on every request; the 401-retry path is the safety net for any token
    /// the server rejects regardless of its local `exp`.
    /// - Parameter jwt: The JWT string.
    /// - Returns: The `exp` claim in Unix seconds, or `0` if missing/malformed.
    public static func expirationSeconds(jwt: String) -> TimeInterval {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3 else { return 0 }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }

        guard let payloadData = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval else {
            return 0
        }
        return exp
    }
}