import Foundation
import Security
import CommonCrypto
import CryptoKit

/// Utility for JWE (JSON Web Encryption) operations following RFC 7516.
public struct JweUtils {
    /// Creates a JWE string by encrypting card data using the provided JWK.
    /// - Parameters:
    ///   - cardData: The card data to encrypt.
    ///   - jwk: The JSON Web Key for encryption.
    /// - Returns: A Result containing the JWE string or an error.
    public static func createJWE(cardData: GopayCardData, jwk: GopayJWK) -> Result<String, Error> {
        // Step 1: Create JWE header first (needed for AAD)
        let header: [String: String] = [
            "alg": jwk.alg,
            "enc": "A256GCM",
            "kid": jwk.kid,
            "typ": "JWE"
        ]
        
        // Use compact JSON serialization (no whitespace)
        guard let headerData = try? JSONSerialization.data(
            withJSONObject: header,
            options: []
        ) else {
            return .failure(GopaySDKErrors.jweError(GopaySDKErrors.jweHeaderEncodingFailed))
        }
        
        // Step 2: Generate random CEK (Content Encryption Key) - 32 bytes for AES-256
        var cek = Data(count: 32)
        let cekStatus = cek.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        guard cekStatus == errSecSuccess else {
            return .failure(GopaySDKErrors.jweError(GopaySDKErrors.jweKeyGenerationFailed))
        }
        
        // Step 3: Generate random IV (12 bytes for AES-GCM)
        var iv = Data(count: 12)
        let ivStatus = iv.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 12, bytes.baseAddress!)
        }
        guard ivStatus == errSecSuccess else {
            return .failure(GopaySDKErrors.jweError(GopaySDKErrors.jweIVGenerationFailed))
        }
        
        // Step 4: Encrypt card data JSON with AES-256-GCM using CEK, IV, and header as AAD
        let cardDataJSON: [String: String] = [
            "card_pan": cardData.cardPan,
            "exp_month": cardData.expMonth,
            "exp_year": cardData.expYear,
            "cvv": cardData.cvv
        ]
        
        // Use compact JSON serialization (no whitespace)
        guard let cardDataJSONData = try? JSONSerialization.data(
            withJSONObject: cardDataJSON,
            options: []
        ) else {
            return .failure(GopaySDKErrors.jweError(GopaySDKErrors.jweCardDataEncodingFailed))
        }
        
        // Base64URL encode header for AAD (according to JWE spec, AAD is the encoded header)
        let encodedHeader = base64URLEncode(headerData)
        let aad = encodedHeader.data(using: .utf8) ?? Data()
        
        let aesResult = aes256GCMEncrypt(data: cardDataJSONData, key: cek, iv: iv, aad: aad)
        switch aesResult {
        case .success(let (ciphertext, tag)):
            // Step 5: Encrypt CEK with RSA-OAEP-256 using JWK public key
            let encryptedKeyResult = encryptCEK(cek: cek, jwk: jwk)
            switch encryptedKeyResult {
            case .success(let encryptedKey):
                // Step 6: Base64URL encode and concatenate: header.encrypted_key.iv.ciphertext.tag
                let headerB64 = encodedHeader
                let encryptedKeyB64 = base64URLEncode(encryptedKey)
                let ivB64 = base64URLEncode(iv)
                let ciphertextB64 = base64URLEncode(ciphertext)
                let tagB64 = base64URLEncode(tag)
                
                let jweString = "\(headerB64).\(encryptedKeyB64).\(ivB64).\(ciphertextB64).\(tagB64)"
                return .success(jweString)
                
            case .failure(let error):
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    // MARK: - Private Methods
    
    /// Encrypts data using AES-256-GCM with AAD (Additional Authenticated Data).
    private static func aes256GCMEncrypt(data: Data, key: Data, iv: Data, aad: Data) -> Result<(ciphertext: Data, tag: Data), Error> {
        // Use CryptoKit for proper AES-GCM encryption (iOS 13+)
        if #available(iOS 13.0, *) {
            return aes256GCMEncryptCryptoKit(data: data, key: key, iv: iv, aad: aad)
        }
        
        // Fallback: return error for older iOS versions
        return .failure(GopaySDKErrors.jweError(GopaySDKErrors.jweAESGCMNotAvailable))
    }
    
    /// AES-256-GCM encryption using CryptoKit (iOS 13+) with AAD support.
    @available(iOS 13.0, *)
    private static func aes256GCMEncryptCryptoKit(data: Data, key: Data, iv: Data, aad: Data) -> Result<(ciphertext: Data, tag: Data), Error> {
        guard key.count == 32 else {
            return .failure(GopaySDKErrors.jweError(GopaySDKErrors.jweInvalidKeySize))
        }
        
        guard iv.count == 12 else {
            return .failure(GopaySDKErrors.jweError(GopaySDKErrors.jweInvalidIVSize))
        }
        
        let symmetricKey = SymmetricKey(data: key)
        
        guard let nonce = try? AES.GCM.Nonce(data: iv) else {
            return .failure(GopaySDKErrors.jweError(GopaySDKErrors.jweNonceCreationFailed))
        }
        
        do {
            // CryptoKit's seal method with AAD parameter
            let sealedBox = try AES.GCM.seal(data, using: symmetricKey, nonce: nonce, authenticating: aad)
            return .success((ciphertext: sealedBox.ciphertext, tag: sealedBox.tag))
        } catch {
            return .failure(GopaySDKErrors.jweError(GopaySDKErrors.jweEncryptionFailed))
        }
    }
    
    /// Encrypts the CEK (Content Encryption Key) using RSA-OAEP-256.
    private static func encryptCEK(cek: Data, jwk: GopayJWK) -> Result<Data, Error> {
        // Convert JWK to SecKey
        guard let publicKey = jwkToSecKey(jwk: jwk) else {
            return .failure(GopaySDKErrors.jweError(GopaySDKErrors.jwePublicKeyCreationFailed))
        }
        
        // Encrypt CEK using RSA-OAEP-256
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            cek as CFData,
            &error
        ) as Data? else {
            let errorMessage = error?.takeRetainedValue().localizedDescription ?? GopaySDKErrors.jweCEKEncryptionFailed
            return .failure(GopaySDKErrors.jweError(errorMessage))
        }
        
        return .success(encryptedData)
    }
    
    /// Converts a JWK to a SecKey.
    private static func jwkToSecKey(jwk: GopayJWK) -> SecKey? {
        // Decode base64url encoded modulus and exponent
        guard let nData = base64URLDecode(jwk.n),
              let eData = base64URLDecode(jwk.e) else {
            return nil
        }
        
        // Remove leading zeros from modulus if present (but keep at least one byte)
        var modulus = nData
        while modulus.count > 1 && modulus.first == 0 {
            modulus.removeFirst()
        }
        
        // Remove leading zeros from exponent if present
        var exponent = eData
        while exponent.count > 1 && exponent.first == 0 {
            exponent.removeFirst()
        }
        
        // Create RSA public key in DER format (PKCS#1 RSAPublicKey)
        // RSAPublicKey ::= SEQUENCE {
        //     modulus           INTEGER,  -- n
        //     publicExponent    INTEGER   -- e
        // }
        var rsaPublicKey = Data()
        
        // Modulus INTEGER
        var modulusBytes = Data(modulus)
        // Add leading zero if MSB is set (to ensure positive integer in DER)
        if let firstByte = modulusBytes.first, firstByte & 0x80 != 0 {
            modulusBytes.insert(0, at: 0)
        }
        rsaPublicKey.append(0x02) // INTEGER tag
        rsaPublicKey.append(contentsOf: encodeDERLength(modulusBytes.count))
        rsaPublicKey.append(modulusBytes)
        
        // Exponent INTEGER
        var exponentBytes = Data(exponent)
        // Add leading zero if MSB is set
        if let firstByte = exponentBytes.first, firstByte & 0x80 != 0 {
            exponentBytes.insert(0, at: 0)
        }
        rsaPublicKey.append(0x02) // INTEGER tag
        rsaPublicKey.append(contentsOf: encodeDERLength(exponentBytes.count))
        rsaPublicKey.append(exponentBytes)
        
        // Wrap RSAPublicKey in SEQUENCE
        var rsaPublicKeySequence = Data()
        rsaPublicKeySequence.append(0x30) // SEQUENCE tag
        rsaPublicKeySequence.append(contentsOf: encodeDERLength(rsaPublicKey.count))
        rsaPublicKeySequence.append(rsaPublicKey)
        
        // Create SubjectPublicKeyInfo structure (X.509 format)
        // SubjectPublicKeyInfo ::= SEQUENCE {
        //     algorithm AlgorithmIdentifier,
        //     subjectPublicKey BIT STRING
        // }
        // AlgorithmIdentifier ::= SEQUENCE {
        //     algorithm OBJECT IDENTIFIER,
        //     parameters NULL
        // }
        
        // RSA algorithm OID: 1.2.840.113549.1.1.1
        let rsaAlgorithmOID: [UInt8] = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]
        
        // Wrap RSA public key in BIT STRING
        var bitString = Data()
        bitString.append(0x03) // BIT STRING tag
        bitString.append(contentsOf: encodeDERLength(rsaPublicKeySequence.count + 1))
        bitString.append(0x00) // Unused bits
        bitString.append(rsaPublicKeySequence)
        
        // Create SubjectPublicKeyInfo
        var subjectPublicKeyInfo = Data()
        subjectPublicKeyInfo.append(contentsOf: rsaAlgorithmOID) // AlgorithmIdentifier
        subjectPublicKeyInfo.append(bitString) // subjectPublicKey
        
        // Wrap in outer SEQUENCE
        var outerSequence = Data()
        outerSequence.append(0x30) // SEQUENCE tag
        outerSequence.append(contentsOf: encodeDERLength(subjectPublicKeyInfo.count))
        outerSequence.append(subjectPublicKeyInfo)
        
        // Create RSA key dictionary
        let keyDict: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: modulus.count * 8,
            kSecAttrIsPermanent as String: false
        ]
        
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(outerSequence as CFData, keyDict as CFDictionary, &error) else {
            // If SubjectPublicKeyInfo fails, try RSAPublicKey format directly
            let keyDict2: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
                kSecAttrKeySizeInBits as String: modulus.count * 8,
                kSecAttrIsPermanent as String: false
            ]
            var error2: Unmanaged<CFError>?
            return SecKeyCreateWithData(rsaPublicKeySequence as CFData, keyDict2 as CFDictionary, &error2)
        }
        
        return secKey
    }
    
    /// Encodes length for DER format.
    private static func encodeDERLength(_ length: Int) -> [UInt8] {
        if length < 128 {
            return [UInt8(length)]
        } else {
            let bytes = length.bytes
            return [UInt8(0x80 | bytes.count)] + bytes
        }
    }
    
    /// Base64URL encodes data.
    private static func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Base64URL decodes string to data.
    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        return Data(base64Encoded: base64)
    }
}

// Extension to convert Int to bytes
extension Int {
    var bytes: [UInt8] {
        var value = self
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return bytes
    }
}

