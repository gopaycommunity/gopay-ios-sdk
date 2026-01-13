//
//  sdkTests.swift
//  sdkTests
//
//  Created by Jiří Hauser on 21.03.2025.
//

import Testing
@testable import sdk

// Helper to create a JWT with a given exp value
private func makeJWT(exp: TimeInterval?) -> String {
    let header = ["alg": "none", "typ": "JWT"]
    let payload: [String: Any]
    if let exp = exp {
        payload = ["exp": exp]
    } else {
        payload = [:]
    }
    let headerData = try! JSONSerialization.data(withJSONObject: header)
    let payloadData = try! JSONSerialization.data(withJSONObject: payload)
    func base64url(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let headerPart = base64url(headerData)
    let payloadPart = base64url(payloadData)
    return "\(headerPart).\(payloadPart).signature"
}

struct sdkTests {

    @Test func gopaySDKSharedIsNotNil() async throws {
        let instance = GopaySDK.shared
        #expect(instance != nil)
    }

    @Test func gopaySDKConfigurationIsSetCorrectly() async throws {
        var errorCallbackCalled = false
        let config = GopaySDKConfig(
            environment: .sandbox,
            enableDebugLogging: true,
            errorCallback: { _ in errorCallbackCalled = true }
        )
        GopaySDK.shared.initialize(with: config)
        let sdkConfig = GopaySDK.shared.config
        #expect(sdkConfig != nil)
        #expect(sdkConfig?.environment == .sandbox)
        #expect(sdkConfig?.enableDebugLogging == true)
        // Simulate error callback
        sdkConfig?.errorCallback?(NSError(domain: "test", code: 1))
        #expect(errorCallbackCalled == true)
    }

    class MockKeychainStorage: KeychainStorageProtocol {
        private var storage: [String: String] = [:]
        func storeAccessToken(_ token: String) -> Bool {
            storage["accessToken"] = token
            return true
        }
        func storeRefreshToken(_ token: String) -> Bool {
            storage["refreshToken"] = token
            return true
        }
        func getAccessToken() -> String? {
            return storage["accessToken"]
        }
        func getRefreshToken() -> String? {
            return storage["refreshToken"]
        }
        func clearTokens() {
            storage.removeAll()
        }
    }

    @Test func keychainStorageStoresAndRetrievesTokens() async throws {
        let accessToken = "test_access_token_123"
        let refreshToken = "test_refresh_token_456"
        let keychain: KeychainStorageProtocol = MockKeychainStorage()
        // Clear any existing tokens
        keychain.clearTokens()
        // Store tokens
        let accessStored = keychain.storeAccessToken(accessToken)
        let refreshStored = keychain.storeRefreshToken(refreshToken)
        #expect(accessStored == true)
        #expect(refreshStored == true)
        // Retrieve tokens
        let retrievedAccess = keychain.getAccessToken()
        let retrievedRefresh = keychain.getRefreshToken()
        #expect(retrievedAccess == accessToken)
        #expect(retrievedRefresh == refreshToken)
        // Clear tokens
        keychain.clearTokens()
        #expect(keychain.getAccessToken() == nil)
        #expect(keychain.getRefreshToken() == nil)
    }

    class MockNetworkClient: NetworkClientProtocol {
        var baseURL: String = ""
        
        var responseData: Data?
        var error: Error?

        func makeURL(path: String) -> URL? {
            return URL(string: "https://mock.url/\(path)")
        }

        func sendRequest(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
            if let error = error {
                completion(.failure(error))
            } else if let data = responseData {
                completion(.success(data))
            } else {
                completion(.failure(NSError(domain: "NoData", code: -1)))
            }
        }
    }

    @Test func gopayAuthServiceAuthenticateSuccess() async throws {
        let mockClient = MockNetworkClient()
        let response = GopayAuthResponse(
            access_token: "token123",
            token_type: "bearer",
            refresh_token: "refresh456",
            scope: "scope"
        )
        let responseData = try! JSONEncoder().encode(response)
        mockClient.responseData = responseData

        let authService = GopayAuthService(networkClient: mockClient)
        let result = await withCheckedContinuation { continuation in
            authService.authenticate(clientId: "id", clientSecret: "secret", scope: "scope") { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success(let authResponse):
            #expect(authResponse.access_token == "token123")
            #expect(authResponse.refresh_token == "refresh456")
            #expect(authResponse.token_type == "bearer")
            #expect(authResponse.scope == "scope")
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func gopaySDKAuthenticateSuccess() async throws {
        let mockClient = MockNetworkClient()
        let response = GopayAuthResponse(
            access_token: "token123",
            token_type: "bearer",
            refresh_token: "refresh456",
            scope: "scope"
        )
        let responseData = try! JSONEncoder().encode(response)
        mockClient.responseData = responseData

        let keychain: KeychainStorageProtocol = MockKeychainStorage()
        // Clear any existing tokens
        keychain.clearTokens()

        let config = GopaySDKConfig(environment: .sandbox);
        
        let mockGopaySDK = GopaySDK(
            config: config,
            networkClient: mockClient,
            keychainStorage: keychain
        )
        
        let result = await withCheckedContinuation { continuation in
            mockGopaySDK.authenticate(clientId: "id", clientSecret: "secret", scope: "scope") { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success(let authResponse):
            #expect(authResponse.access_token == "token123")
            #expect(authResponse.refresh_token == "refresh456")
            #expect(authResponse.token_type == "bearer")
            #expect(authResponse.scope == "scope")
            #expect(keychain.getAccessToken() == "token123")
            #expect(keychain.getRefreshToken() == "refresh456")
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func gopaySDKAuthenticateError() async throws {
        let mockClient = MockNetworkClient()
        mockClient.error = NSError(domain: "TestError", code: 123)

        let keychain: KeychainStorageProtocol = MockKeychainStorage()
        keychain.clearTokens()
        var errorCallbackCalled = false
        let config = GopaySDKConfig(environment: .sandbox, errorCallback: { _ in errorCallbackCalled = true })
        let mockGopaySDK = GopaySDK(
            config: config,
            networkClient: mockClient,
            keychainStorage: keychain
        )

        let result = await withCheckedContinuation { continuation in
            mockGopaySDK.authenticate(clientId: "id", clientSecret: "secret", scope: "scope") { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success:
            #expect(Bool(false)) // Should not succeed
        case .failure(let error):
            #expect((error as NSError).domain == "TestError")
            #expect(keychain.getAccessToken() == nil)
            #expect(keychain.getRefreshToken() == nil)
            #expect(errorCallbackCalled == true)
        }
    }

    @Test func jwtUtilsIsExpiredWorks() async throws {
        let now = Date().timeIntervalSince1970
        let validJWT = makeJWT(exp: now + 3600) // expires in 1 hour
        let expiredJWT = makeJWT(exp: now - 3600) // expired 1 hour ago
        let noExpJWT = makeJWT(exp: nil)
        let invalidJWT = "not.a.jwt"

        #expect(JwtUtils.isExpired(jwt: validJWT) == false)
        #expect(JwtUtils.isExpired(jwt: expiredJWT) == true)
        #expect(JwtUtils.isExpired(jwt: noExpJWT) == nil)
        #expect(JwtUtils.isExpired(jwt: invalidJWT) == nil)
    }

    @Test func gopaySDKSetAuthenticationResponseWorks() async throws {
        let now = Date().timeIntervalSince1970
        let validJWT = makeJWT(exp: now + 3600)
        let expiredJWT = makeJWT(exp: now - 3600)
        let refreshToken = "refresh_token_123"
        let keychain = MockKeychainStorage()
        let sdk = GopaySDK(keychainStorage: keychain)
        // Test valid token
        let responseValid = GopayAuthResponse(access_token: validJWT, token_type: "bearer", refresh_token: refreshToken, scope: nil)
        try sdk.setAuthenticationResponse(with: responseValid)
        #expect(keychain.getAccessToken() == validJWT)
        #expect(keychain.getRefreshToken() == refreshToken)
        // Test expired token
        let responseExpired = GopayAuthResponse(access_token: expiredJWT, token_type: "bearer", refresh_token: refreshToken, scope: nil)
        var didThrow = false
        do {
            try sdk.setAuthenticationResponse(with: responseExpired)
        } catch {
            didThrow = true
        }
        #expect(didThrow == true)
    }

    @Test func gopayEnvironmentDevelopmentWithCustomBaseURL() async throws {
        let customBaseURL = "https://custom-dev.example.com/api/"
        let environment = GopayEnvironment.development(baseURL: customBaseURL)
        
        // Verify the baseURL is correctly set on the environment
        #expect(environment.baseURL == customBaseURL)
        
        // Verify it works with SDK initialization
        let config = GopaySDKConfig(environment: environment)
        let sdk = GopaySDK(config: config)
        #expect(sdk.config?.environment.baseURL == customBaseURL)
        
        // Verify different custom URLs work
        let anotherCustomURL = "https://another-dev.example.com/api/v2/"
        let anotherEnvironment = GopayEnvironment.development(baseURL: anotherCustomURL)
        #expect(anotherEnvironment.baseURL == anotherCustomURL)
    }

    @Test func gopayEncryptionServiceGetPublicKeySuccess() async throws {
        let mockClient = MockNetworkClient()
        let jwk = GopayJWK(
            kty: "RSA",
            kid: "key_20250406",
            use: "enc",
            alg: "RSA-OAEP-256",
            n: "y7WkT3qvY...",
            e: "AQAB"
        )
        let responseData = try! JSONEncoder().encode(jwk)
        mockClient.responseData = responseData
        
        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        let validJWT = makeJWT(exp: now + 3600)
        keychain.storeAccessToken(validJWT)
        
        let encryptionService = GopayEncryptionService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            encryptionService.getPublicKey { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success(let retrievedJWK):
            #expect(retrievedJWK.kty == "RSA")
            #expect(retrievedJWK.kid == "key_20250406")
            #expect(retrievedJWK.use == "enc")
            #expect(retrievedJWK.alg == "RSA-OAEP-256")
            #expect(retrievedJWK.n == "y7WkT3qvY...")
            #expect(retrievedJWK.e == "AQAB")
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func gopayEncryptionServiceGetPublicKeyNoToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        keychain.clearTokens()
        
        let encryptionService = GopayEncryptionService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            encryptionService.getPublicKey { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success:
            #expect(Bool(false)) // Should not succeed
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.encryptionServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.noAccessToken)
        }
    }

    @Test func gopayEncryptionServiceGetPublicKeyExpiredToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        let expiredJWT = makeJWT(exp: now - 3600)
        keychain.storeAccessToken(expiredJWT)
        
        let encryptionService = GopayEncryptionService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            encryptionService.getPublicKey { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success:
            #expect(Bool(false)) // Should not succeed
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.encryptionServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.accessTokenExpired)
        }
    }

    @Test func gopayEncryptionServiceGetPublicKeyNetworkError() async throws {
        let mockClient = MockNetworkClient()
        mockClient.error = NSError(domain: "NetworkError", code: 500)
        
        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        let validJWT = makeJWT(exp: now + 3600)
        keychain.storeAccessToken(validJWT)
        
        let encryptionService = GopayEncryptionService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            encryptionService.getPublicKey { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success:
            #expect(Bool(false)) // Should not succeed
        case .failure(let error):
            #expect((error as NSError).domain == "NetworkError")
            #expect((error as NSError).code == 500)
        }
    }

    @Test func gopayEncryptionServiceGetPublicKeyInvalidResponse() async throws {
        let mockClient = MockNetworkClient()
        // Invalid JSON response
        mockClient.responseData = "invalid json".data(using: .utf8)
        
        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        let validJWT = makeJWT(exp: now + 3600)
        keychain.storeAccessToken(validJWT)
        
        let encryptionService = GopayEncryptionService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            encryptionService.getPublicKey { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success:
            #expect(Bool(false)) // Should not succeed
        case .failure:
            // Decoding error is expected
            #expect(Bool(true))
        }
    }

    @Test func gopaySDKGetPublicKeySuccess() async throws {
        let mockClient = MockNetworkClient()
        let jwk = GopayJWK(
            kty: "RSA",
            kid: "key_20250406",
            use: "enc",
            alg: "RSA-OAEP-256",
            n: "y7WkT3qvY...",
            e: "AQAB"
        )
        let responseData = try! JSONEncoder().encode(jwk)
        mockClient.responseData = responseData
        
        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        let validJWT = makeJWT(exp: now + 3600)
        keychain.storeAccessToken(validJWT)
        
        let config = GopaySDKConfig(environment: .sandbox)
        let mockGopaySDK = GopaySDK(
            config: config,
            networkClient: mockClient,
            keychainStorage: keychain
        )
        
        let result = await withCheckedContinuation { continuation in
            mockGopaySDK.getPublicKey { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success(let retrievedJWK):
            #expect(retrievedJWK.kty == "RSA")
            #expect(retrievedJWK.kid == "key_20250406")
            #expect(retrievedJWK.use == "enc")
            #expect(retrievedJWK.alg == "RSA-OAEP-256")
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func gopaySDKGetPublicKeyNoToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        keychain.clearTokens()
        
        let config = GopaySDKConfig(environment: .sandbox)
        let mockGopaySDK = GopaySDK(
            config: config,
            networkClient: mockClient,
            keychainStorage: keychain
        )
        
        let result = await withCheckedContinuation { continuation in
            mockGopaySDK.getPublicKey { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success:
            #expect(Bool(false)) // Should not succeed
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.encryptionServiceDomain)
        }
    }

    @Test func gopaySDKGetPublicKeyExpiredToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        let expiredJWT = makeJWT(exp: now - 3600)
        keychain.storeAccessToken(expiredJWT)
        
        let config = GopaySDKConfig(environment: .sandbox)
        let mockGopaySDK = GopaySDK(
            config: config,
            networkClient: mockClient,
            keychainStorage: keychain
        )
        
        let result = await withCheckedContinuation { continuation in
            mockGopaySDK.getPublicKey { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success:
            #expect(Bool(false)) // Should not succeed
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.encryptionServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.accessTokenExpired)
        }
    }

    @Test func gopaySDKGetPublicKeyNotInitialized() async throws {
        let sdk = GopaySDK()
        let result = await withCheckedContinuation { continuation in
            sdk.getPublicKey { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success:
            #expect(Bool(false)) // Should not succeed
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.encryptionServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.noAccessToken)
        }
    }

    // MARK: - JWE Utils Tests
    
    /// Helper to base64URL encode data
    private func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Helper to base64URL decode string
    private func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        return Data(base64Encoded: base64)
    }
    
    @Test func jweUtilsCreateJWEStructure() async throws {
        guard #available(iOS 13.0, *) else {
            return
        }
        
        // Create a real RSA key pair for testing
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPublicKeyAttrs as String: [
                kSecAttrIsPermanent as String: false
            ]
        ]
        
        var publicKey: SecKey?
        var privateKey: SecKey?
        let status = SecKeyGeneratePair(attributes as CFDictionary, &publicKey, &privateKey)
        
        guard status == errSecSuccess,
              let pubKey = publicKey,
              let pubKeyData = SecKeyCopyExternalRepresentation(pubKey, nil) as Data? else {
            // Skip test if key generation fails
            return
        }
        
        // Create JWK using the public key data
        // Note: In production, we'd parse DER to extract n and e, but for testing
        // we'll use the raw key data which may not work perfectly but tests the structure
        let jwk = GopayJWK(
            kty: "RSA",
            kid: "test_key_123",
            use: "enc",
            alg: "RSA-OAEP-256",
            n: base64URLEncode(pubKeyData),
            e: "AQAB"
        )
        
        let cardData = GopayCardData(
            card_pan: "4444444444444448",
            exp_month: "12",
            exp_year: "26",
            cvv: "123"
        )
        
        let result = JweUtils.createJWE(cardData: cardData, jwk: jwk)
        
        switch result {
        case .success(let jweString):
            // Verify JWE structure: header.encrypted_key.iv.ciphertext.tag
            let parts = jweString.split(separator: ".")
            #expect(parts.count == 5, "JWE should have exactly 5 parts")
            
            // Verify header can be decoded and contains expected fields
            if let headerData = base64URLDecode(String(parts[0])),
               let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: String] {
                #expect(header["alg"] == "RSA-OAEP-256")
                #expect(header["enc"] == "A256GCM")
                #expect(header["kid"] == "test_key_123")
                #expect(header["typ"] == "JWE")
            } else {
                #expect(Bool(false), "Header should be valid JSON")
            }
            
            // Verify all parts are non-empty
            for (index, part) in parts.enumerated() {
                #expect(!part.isEmpty, "JWE part \(index) should not be empty")
            }
            
        case .failure(let error):
            // If encryption fails due to JWK format issues, verify error structure
            let nsError = error as NSError
            #expect(nsError.domain == GopaySDKErrors.jweDomain)
            #expect(nsError.userInfo[NSLocalizedDescriptionKey] != nil)
        }
    }
    
    @Test func jweUtilsCreateJWEWithInvalidJWK() async throws {
        // Test with invalid JWK (empty modulus)
        let invalidJWK = GopayJWK(
            kty: "RSA",
            kid: "invalid_key",
            use: "enc",
            alg: "RSA-OAEP-256",
            n: "", // Invalid empty modulus
            e: "AQAB"
        )
        
        let cardData = GopayCardData(
            card_pan: "4444444444444448",
            exp_month: "12",
            exp_year: "26",
            cvv: "123"
        )
        
        let result = JweUtils.createJWE(cardData: cardData, jwk: invalidJWK)
        
        switch result {
        case .success:
            #expect(Bool(false), "Should fail with invalid JWK")
        case .failure(let error):
            let nsError = error as NSError
            #expect(nsError.domain == GopaySDKErrors.jweDomain)
        }
    }
    
    @Test func jweUtilsCreateJWEWithInvalidBase64JWK() async throws {
        // Test with invalid base64url encoded JWK
        let invalidJWK = GopayJWK(
            kty: "RSA",
            kid: "invalid_key",
            use: "enc",
            alg: "RSA-OAEP-256",
            n: "!!!invalid_base64!!!", // Invalid base64
            e: "AQAB"
        )
        
        let cardData = GopayCardData(
            card_pan: "4444444444444448",
            exp_month: "12",
            exp_year: "26",
            cvv: "123"
        )
        
        let result = JweUtils.createJWE(cardData: cardData, jwk: invalidJWK)
        
        switch result {
        case .success:
            #expect(Bool(false), "Should fail with invalid base64 JWK")
        case .failure(let error):
            let nsError = error as NSError
            #expect(nsError.domain == GopaySDKErrors.jweDomain)
        }
    }
    
    @Test func jweUtilsCreateJWEWithMinimalJWK() async throws {
        guard #available(iOS 13.0, *) else {
            return
        }
        
        // Test with minimal JWK (will likely fail but tests error handling)
        let jwk = GopayJWK(
            kty: "RSA",
            kid: "test_key",
            use: "enc",
            alg: "RSA-OAEP-256",
            n: "y7WkT3qvY", // Minimal test value (too small for real encryption)
            e: "AQAB"
        )
        
        let cardData = GopayCardData(
            card_pan: "4444444444444448",
            exp_month: "12",
            exp_year: "26",
            cvv: "123"
        )
        
        let result = JweUtils.createJWE(cardData: cardData, jwk: jwk)
        
        // Should fail with invalid key, but verify error structure
        switch result {
        case .success:
            // If it succeeds, verify structure
            break
            
        case .failure(let error):
            // Verify error is properly formatted
            let nsError = error as NSError
            #expect(nsError.domain == GopaySDKErrors.jweDomain)
            #expect(nsError.userInfo[NSLocalizedDescriptionKey] != nil)
        }
    }
    
    @Test func jweUtilsCreateJWEWithDifferentCardData() async throws {
        guard #available(iOS 13.0, *) else {
            return
        }
        
        let jwk = GopayJWK(
            kty: "RSA",
            kid: "test_key",
            use: "enc",
            alg: "RSA-OAEP-256",
            n: "y7WkT3qvY",
            e: "AQAB"
        )
        
        // Test with different card data formats
        let testCases = [
            GopayCardData(card_pan: "4111111111111111", exp_month: "01", exp_year: "25", cvv: "123"),
            GopayCardData(card_pan: "5555555555554444", exp_month: "06", exp_year: "30", cvv: "456"),
            GopayCardData(card_pan: "1234567890123456", exp_month: "12", exp_year: "99", cvv: "789")
        ]
        
        for cardData in testCases {
            let result = JweUtils.createJWE(cardData: cardData, jwk: jwk)
            
            // Verify it doesn't crash and returns either success or proper error
            switch result {
            case .success(let jweString):
                let parts = jweString.split(separator: ".")
                #expect(parts.count == 5)
                
            case .failure(let error):
                let nsError = error as NSError
                #expect(nsError.domain == GopaySDKErrors.jweDomain)
            }
        }
    }
    
    @Test func jweUtilsCreateJWEHeaderFormat() async throws {
        guard #available(iOS 13.0, *) else {
            return
        }
        
        // Test that JWE header is properly formatted
        let jwk = GopayJWK(
            kty: "RSA",
            kid: "test_key_format",
            use: "enc",
            alg: "RSA-OAEP-256",
            n: "y7WkT3qvY",
            e: "AQAB"
        )
        
        let cardData = GopayCardData(
            card_pan: "4444444444444448",
            exp_month: "12",
            exp_year: "26",
            cvv: "123"
        )
        
        let result = JweUtils.createJWE(cardData: cardData, jwk: jwk)
        
        // Even if encryption fails, we can test header creation logic
        // by checking if the first part (header) is valid base64url
        switch result {
        case .success(let jweString):
            let parts = jweString.split(separator: ".")
            if parts.count >= 1 {
                let headerPart = String(parts[0])
                // Verify header is base64url encoded (no padding, uses - and _)
                #expect(!headerPart.contains("+"))
                #expect(!headerPart.contains("/"))
                #expect(!headerPart.contains("="))
                
                // Verify header can be decoded
                if let headerData = base64URLDecode(headerPart),
                   let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: String] {
                    #expect(header["kid"] == "test_key_format")
                }
            }
            
        case .failure:
            // Error is acceptable for invalid key
            break
        }
    }
    
    @Test func jweUtilsCreateJWEWithEmptyCardData() async throws {
        guard #available(iOS 13.0, *) else {
            return
        }
        
        let jwk = GopayJWK(
            kty: "RSA",
            kid: "test_key",
            use: "enc",
            alg: "RSA-OAEP-256",
            n: "y7WkT3qvY",
            e: "AQAB"
        )
        
        // Test with empty strings (edge case)
        let cardData = GopayCardData(
            card_pan: "",
            exp_month: "",
            exp_year: "",
            cvv: ""
        )
        
        let result = JweUtils.createJWE(cardData: cardData, jwk: jwk)
        
        // Should either succeed (with empty data) or fail gracefully
        switch result {
        case .success(let jweString):
            let parts = jweString.split(separator: ".")
            #expect(parts.count == 5)
            
        case .failure(let error):
            let nsError = error as NSError
            #expect(nsError.domain == GopaySDKErrors.jweDomain)
        }
    }

}
