import Foundation

/// Response from `POST /oauth2/token`, shaped to the `Access-Token` schema in Payments.yaml.
///
/// Distinct from the legacy auth response: the new schema has **no `refresh_token`** and adds an
/// `expires_in` field. Tokens are short-lived (900s default) and re-acquired from the cached
/// `payment_id` / `payment_secret` rather than refreshed.
struct AccessTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
    }
}
