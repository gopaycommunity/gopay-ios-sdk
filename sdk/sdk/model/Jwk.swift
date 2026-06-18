import Foundation

/// JSON Web Key (RFC 7517) for the merchant's public encryption key, fetched from
/// `GET /cards/public-key`. Used to encrypt card data into a JWE.
public struct GopayJWK: Decodable, Encodable {
    /// Key type. Always `"RSA"`.
    public let kty: String
    /// Key ID containing information about the key age.
    public let kid: String
    /// Key usage. Always `"enc"`.
    public let use: String
    /// Algorithm to be used for encryption with the key.
    public let alg: String
    /// The RSA public key modulus.
    public let n: String
    /// The RSA public key exponent.
    public let e: String
}
