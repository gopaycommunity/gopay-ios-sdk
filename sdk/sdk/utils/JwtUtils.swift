import Foundation

/// Utility for JWT operations
public struct JwtUtils {
    /// Checks if a JWT is expired based on the `exp` claim.
    /// - Parameter jwt: The JWT string.
    /// - Returns: `true` if expired, `false` if not expired, or `nil` if invalid.
    public static func isExpired(jwt: String) -> Bool? {
        let segments = jwt.split(separator: ".")
        guard segments.count == 3 else { return nil }
        
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        
        guard let payloadData = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval else {
            return nil
        }
        let now = Date().timeIntervalSince1970
        return now > exp
    }
}