import Foundation

/// JSON Web Key (RFC 7517) for the merchant's public encryption key, fetched from
/// `GET /cards/public-key`. Used to encrypt card data into a JWE.
struct GopayJWK: Decodable {
    /// Key type. Always `"RSA"`.
    let kty: String
    /// Key ID containing information about the key age.
    let kid: String
    /// Key usage. Always `"enc"`.
    let use: String
    /// Algorithm to be used for encryption with the key.
    let alg: String
    /// The RSA public key modulus.
    let n: String
    /// The RSA public key exponent.
    let e: String
}
