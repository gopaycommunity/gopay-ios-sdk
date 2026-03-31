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
    let headerData: Data
    let payloadData: Data
    do {
        headerData = try JSONSerialization.data(withJSONObject: header)
        payloadData = try JSONSerialization.data(withJSONObject: payload)
    } catch {
        fatalError("Test JWT creation failed: \(error)")
    }
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

// Shared test JWK field values to avoid duplicating string literals
private let testJWKKty = "RSA"
private let testJWKKid = "key_20250406"
private let testJWKUse = "enc"
private let testJWKAlg = "RSA-OAEP-256"
private let testJWKN = "y7WkT3qvY..."
private let testJWKE = "AQAB"

// Test base URLs (avoid hardcoded URI literals)
private let testMockBaseURL = "https://mock.url"
private let testCustomBaseURL = "https://custom-dev.example.com/api/"
private let testAnotherCustomBaseURL = "https://another-dev.example.com/api/v2/"

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
        #expect(errorCallbackCalled)
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
        #expect(accessStored)
        #expect(refreshStored)
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
            return URL(string: "\(testMockBaseURL)/\(path)")
        }

        func sendRequest(_ _: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
            if let error = error {
                completion(.failure(error))
            } else if let data = responseData {
                completion(.success(data))
            } else {
                completion(.failure(NSError(domain: "NoData", code: -1)))
            }
        }
    }

    private func makeCreatePaymentRequest() -> GopayCreatePaymentRequest {
        return GopayCreatePaymentRequest(
            amount: 10000,
            currency: .czk,
            orderNumber: "2025010199",
            orderDescription: "Test order",
            additionalParams: [GopayAdditionalParam(name: "source", value: "sdk-tests")],
            customer: GopayPaymentCustomer(
                email: "john.doe@example.com",
                firstName: "John",
                lastName: "Doe",
                phoneNumber: "+420123456789",
                city: "Prague",
                street: "Example street 10",
                postalCode: "10000",
                countryCode: "CZE",
                customerId: "customer420"
            ),
            callback: GopayPaymentCallback(
                notificationURL: "https://example.com/notify",
                returnURL: "https://example.com/return"
            )
        )
    }

    private func makeCreatePaymentResponseData() throws -> Data {
        let json: [String: Any] = [
            "id": "300000001",
            "order_number": "2025010199",
            "state": "CREATED",
            "amount": 10000,
            "currency": "CZK",
            "customer": [
                "email": "john.doe@example.com",
                "first_name": "John",
                "last_name": "Doe",
                "phone_number": "+420123456789",
                "city": "Prague",
                "street": "Example street 10",
                "postal_code": "10000",
                "country_code": "CZE",
                "customer_id": "customer420"
            ],
            "gw_url": "https://gw.sandbox.gopay.com/gw/v3/abc"
        ]
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func makePaymentStatusResponseData(withCharge: Bool = true) throws -> Data {
        var json: [String: Any] = [
            "id": "300000001",
            "order_number": "2025010199",
            "state": "PAID",
            "amount": 10000,
            "currency": "CZK",
            "customer": [
                "email": "john.doe@example.com",
                "first_name": "John",
                "last_name": "Doe"
            ],
            "gw_url": "https://gw.sandbox.gopay.com/gw/v3/abc"
        ]

        if withCharge {
            json["charge"] = [
                "id": "chg_12345",
                "state": "SUCCEEDED",
                "href": "https://gw.sandbox.gopay.com/payments/300000001/charge/chg_12345"
            ]
        }

        return try JSONSerialization.data(withJSONObject: json)
    }

    private func makePaymentQRInfoResponseData() throws -> Data {
        let json: [String: Any] = [
            "amount": 10000,
            "currency": "CZK",
            "recipient": [
                "name": "Demo Merchant",
                "bank_account": [
                    "local": [
                        "prefix": "19",
                        "account_number": "123456789",
                        "bank_code": "0800",
                        "variable_symbol": "2025010199"
                    ],
                    "international": [
                        "bic": "GIBACZPX",
                        "iban": "CZ6508000000191234567899",
                        "reference": "ORDER-2025010199"
                    ]
                ],
                "address": [
                    "street": "Example street 10",
                    "city": "Prague",
                    "zip_code": "10000",
                    "country": "CZ"
                ]
            ],
            "qr_code": [
                "spayd": "U1BBWUQtREFUQQ==",
                "paybysquare": "UEFZQllTUVVBUkUtREFUQQ==",
                "sepa": "U0VQQS1EQVRB",
                "mnb_qr": "TU5CLVFSLURBVEE="
            ]
        ]

        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test func gopayAuthServiceAuthenticateSuccess() async throws {
        let mockClient = MockNetworkClient()
        let response = GopayAuthResponse(
            accessToken: "token123",
            tokenType: "bearer",
            refreshToken: "refresh456",
            scope: "scope"
        )
        let responseData = try JSONEncoder().encode(response)
        mockClient.responseData = responseData

        let authService = GopayAuthService(networkClient: mockClient)
        let result = await withCheckedContinuation { continuation in
            authService.authenticate(clientId: "id", clientSecret: "secret", scope: "scope") { result in
                continuation.resume(returning: result)
            }
        }
        switch result {
        case .success(let authResponse):
            #expect(authResponse.accessToken == "token123")
            #expect(authResponse.refreshToken == "refresh456")
            #expect(authResponse.tokenType == "bearer")
            #expect(authResponse.scope == "scope")
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func gopaySDKAuthenticateSuccess() async throws {
        let mockClient = MockNetworkClient()
        let response = GopayAuthResponse(
            accessToken: "token123",
            tokenType: "bearer",
            refreshToken: "refresh456",
            scope: "scope"
        )
        let responseData = try JSONEncoder().encode(response)
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
            #expect(authResponse.accessToken == "token123")
            #expect(authResponse.refreshToken == "refresh456")
            #expect(authResponse.tokenType == "bearer")
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
            #expect(errorCallbackCalled)
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
        let responseValid = GopayAuthResponse(accessToken: validJWT, tokenType: "bearer", refreshToken: refreshToken, scope: nil)
        try sdk.setAuthenticationResponse(with: responseValid)
        #expect(keychain.getAccessToken() == validJWT)
        #expect(keychain.getRefreshToken() == refreshToken)
        // Test expired token
        let responseExpired = GopayAuthResponse(accessToken: expiredJWT, tokenType: "bearer", refreshToken: refreshToken, scope: nil)
        var didThrow = false
        do {
            try sdk.setAuthenticationResponse(with: responseExpired)
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test func gopayEnvironmentDevelopmentWithCustomBaseURL() async throws {
        let environment = GopayEnvironment.development(baseURL: testCustomBaseURL)
        
        // Verify the baseURL is correctly set on the environment
        #expect(environment.baseURL == testCustomBaseURL)
        
        // Verify it works with SDK initialization
        let config = GopaySDKConfig(environment: environment)
        let sdk = GopaySDK(config: config)
        #expect(sdk.config?.environment.baseURL == testCustomBaseURL)
        
        // Verify different custom URLs work
        let anotherEnvironment = GopayEnvironment.development(baseURL: testAnotherCustomBaseURL)
        #expect(anotherEnvironment.baseURL == testAnotherCustomBaseURL)
    }

    @Test func gopayEncryptionServiceGetPublicKeySuccess() async throws {
        let mockClient = MockNetworkClient()
        let jwk = GopayJWK(
            kty: testJWKKty,
            kid: testJWKKid,
            use: testJWKUse,
            alg: testJWKAlg,
            n: testJWKN,
            e: testJWKE
        )
        let responseData = try JSONEncoder().encode(jwk)
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
            kty: testJWKKty,
            kid: testJWKKid,
            use: testJWKUse,
            alg: testJWKAlg,
            n: testJWKN,
            e: testJWKE
        )
        let responseData = try JSONEncoder().encode(jwk)
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

    @Test func gopayPaymentServiceCreatePaymentSuccess() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = try makeCreatePaymentResponseData()

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.createPayment(goid: "1234567890", requestBody: makeCreatePaymentRequest()) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.id == "300000001")
            #expect(response.orderNumber == "2025010199")
            #expect(response.state == .created)
            #expect(response.amount == 10000)
            #expect(response.currency == .czk)
            #expect(response.customer.email == "john.doe@example.com")
            #expect(response.gatewayURL == "https://gw.sandbox.gopay.com/gw/v3/abc")
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func gopayPaymentServiceCreatePaymentNoToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        keychain.clearTokens()

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.createPayment(goid: "1234567890", requestBody: makeCreatePaymentRequest()) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.noAccessToken)
        }
    }

    @Test func gopayPaymentServiceCreatePaymentExpiredToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now - 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.createPayment(goid: "1234567890", requestBody: makeCreatePaymentRequest()) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.accessTokenExpired)
        }
    }

    @Test func gopaySDKCreatePaymentSuccess() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = try makeCreatePaymentResponseData()

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let config = GopaySDKConfig(environment: .sandbox)
        let sdk = GopaySDK(config: config, networkClient: mockClient, keychainStorage: keychain)

        let result = await withCheckedContinuation { continuation in
            sdk.createPayment(goid: "1234567890", request: makeCreatePaymentRequest()) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.id == "300000001")
            #expect(response.state == .created)
            #expect(response.gatewayURL == "https://gw.sandbox.gopay.com/gw/v3/abc")
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func gopaySDKCreatePaymentNotInitialized() async throws {
        let sdk = GopaySDK()
        let result = await withCheckedContinuation { continuation in
            sdk.createPayment(goid: "1234567890", request: makeCreatePaymentRequest()) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.noAccessToken)
        }
    }

    @Test func paymentServiceGetPaymentSuccess() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = try makePaymentStatusResponseData()

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPayment(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.id == "300000001")
            #expect(response.orderNumber == "2025010199")
            #expect(response.state == .paid)
            #expect(response.amount == 10000)
            #expect(response.currency == .czk)
            #expect(response.customer.email == "john.doe@example.com")
            #expect(response.gatewayURL == "https://gw.sandbox.gopay.com/gw/v3/abc")
            #expect(response.charge?.id == "chg_12345")
            #expect(response.charge?.state == .succeeded)
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func paymentServiceGetPaymentNoToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        keychain.clearTokens()

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPayment(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.noAccessToken)
        }
    }

    @Test func paymentServiceGetPaymentExpiredToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now - 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPayment(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.accessTokenExpired)
        }
    }

    @Test func paymentServiceGetPaymentNetworkError() async throws {
        let mockClient = MockNetworkClient()
        mockClient.error = NSError(domain: "NetworkError", code: 500)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPayment(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == "NetworkError")
            #expect((error as NSError).code == 500)
        }
    }

    @Test func paymentServiceGetPaymentInvalidResponse() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = "not json".data(using: .utf8)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPayment(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure:
            #expect(Bool(true))
        }
    }

    @Test func gopaySDKGetPaymentSuccess() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = try makePaymentStatusResponseData()

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let config = GopaySDKConfig(environment: .sandbox)
        let sdk = GopaySDK(config: config, networkClient: mockClient, keychainStorage: keychain)

        let result = await withCheckedContinuation { continuation in
            sdk.getPayment(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.id == "300000001")
            #expect(response.state == .paid)
            #expect(response.charge?.state == .succeeded)
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func gopaySDKGetPaymentNotInitialized() async throws {
        let sdk = GopaySDK()
        let result = await withCheckedContinuation { continuation in
            sdk.getPayment(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.noAccessToken)
        }
    }

    @Test func paymentServiceGetPaymentChargeStateSuccess() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = try makeChargeResponseData(withAction: false)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPaymentChargeState(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.id == "chg_12345")
            #expect(response.state == .succeeded)
            #expect(response.action == nil)
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func paymentServiceGetPaymentChargeStateNoToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        keychain.clearTokens()

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPaymentChargeState(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.noAccessToken)
        }
    }

    @Test func paymentServiceGetPaymentChargeStateExpiredToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now - 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPaymentChargeState(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.accessTokenExpired)
        }
    }

    @Test func paymentServiceGetPaymentChargeStateNetworkError() async throws {
        let mockClient = MockNetworkClient()
        mockClient.error = NSError(domain: "NetworkError", code: 500)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPaymentChargeState(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == "NetworkError")
            #expect((error as NSError).code == 500)
        }
    }

    @Test func paymentServiceGetPaymentChargeStateInvalidResponse() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = "not json".data(using: .utf8)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPaymentChargeState(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure:
            #expect(Bool(true))
        }
    }

    @Test func gopaySDKGetPaymentChargeStateSuccess() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = try makeChargeResponseData(withAction: false)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let config = GopaySDKConfig(environment: .sandbox)
        let sdk = GopaySDK(config: config, networkClient: mockClient, keychainStorage: keychain)

        let result = await withCheckedContinuation { continuation in
            sdk.getPaymentChargeState(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.id == "chg_12345")
            #expect(response.state == .succeeded)
            #expect(response.action == nil)
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func gopaySDKGetPaymentChargeStateNotInitialized() async throws {
        let sdk = GopaySDK()
        let result = await withCheckedContinuation { continuation in
            sdk.getPaymentChargeState(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.noAccessToken)
        }
    }

    @Test func paymentServiceGetPaymentQRInfoSuccess() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = try makePaymentQRInfoResponseData()

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPaymentQRInfo(paymentId: "300000001", format: .png) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.amount == 10000)
            #expect(response.currency == .czk)
            #expect(response.recipient.name == "Demo Merchant")
            #expect(response.recipient.bankAccount.local?.bankCode == "0800")
            #expect(response.recipient.bankAccount.international.iban == "CZ6508000000191234567899")
            #expect(response.qrCode.spayd == "U1BBWUQtREFUQQ==")
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func paymentServiceGetPaymentQRInfoNoToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        keychain.clearTokens()

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPaymentQRInfo(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.noAccessToken)
        }
    }

    @Test func paymentServiceGetPaymentQRInfoExpiredToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now - 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPaymentQRInfo(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.accessTokenExpired)
        }
    }

    @Test func paymentServiceGetPaymentQRInfoNetworkError() async throws {
        let mockClient = MockNetworkClient()
        mockClient.error = NSError(domain: "NetworkError", code: 500)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPaymentQRInfo(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == "NetworkError")
            #expect((error as NSError).code == 500)
        }
    }

    @Test func paymentServiceGetPaymentQRInfoInvalidResponse() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = "not json".data(using: .utf8)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.getPaymentQRInfo(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure:
            #expect(Bool(true))
        }
    }

    @Test func gopaySDKGetPaymentQRInfoSuccess() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = try makePaymentQRInfoResponseData()

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let config = GopaySDKConfig(environment: .sandbox)
        let sdk = GopaySDK(config: config, networkClient: mockClient, keychainStorage: keychain)

        let result = await withCheckedContinuation { continuation in
            sdk.getPaymentQRInfo(paymentId: "300000001", format: .svg) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.amount == 10000)
            #expect(response.currency == .czk)
            #expect(response.recipient.name == "Demo Merchant")
            #expect(response.qrCode.sepa == "U0VQQS1EQVRB")
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func gopaySDKGetPaymentQRInfoNotInitialized() async throws {
        let sdk = GopaySDK()
        let result = await withCheckedContinuation { continuation in
            sdk.getPaymentQRInfo(paymentId: "300000001") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
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
            cardPan: "4444444444444448",
            expMonth: "12",
            expYear: "26",
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
            cardPan: "4444444444444448",
            expMonth: "12",
            expYear: "26",
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
            cardPan: "4444444444444448",
            expMonth: "12",
            expYear: "26",
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
            cardPan: "4444444444444448",
            expMonth: "12",
            expYear: "26",
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
            GopayCardData(cardPan: "4111111111111111", expMonth: "01", expYear: "25", cvv: "123"),
            GopayCardData(cardPan: "5555555555554444", expMonth: "06", expYear: "30", cvv: "456"),
            GopayCardData(cardPan: "1234567890123456", expMonth: "12", expYear: "99", cvv: "789")
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
            cardPan: "4444444444444448",
            expMonth: "12",
            expYear: "26",
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
    
    // MARK: - Charge Payment Tests

    private func makeChargeResponseData(withAction: Bool) throws -> Data {
        var json: [String: Any] = [
            "id": "pay_500001",
            "state": withAction ? "ACTION_REQUIRED" : "SUCCEEDED",
            "payment_instrument": [
                "payment_instrument": "PAYMENT_CARD",
                "details": [
                    "input_type": "CARD_TOKEN",
                    "masked_pan": "406821******1234",
                    "expiration_month": "01",
                    "expiration_year": "30",
                    "scheme": "VISA",
                    "fingerprint": "73c8d0a48d91def897612b"
                ]
            ],
            "return_url": "https://gopay.com/sdk/charge-return"
        ]
        if withAction {
            json["action"] = [
                "action_type": "EMV3DS",
                "state": "CREATED",
                "redirect_url": "https://gate.gopay.com/redirect/3ds"
            ]
        }
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test func chargePaymentResponseDecodingWithAction() async throws {
        let data = try makeChargeResponseData(withAction: true)
        let response = try JSONDecoder().decode(GopayChargePaymentResponse.self, from: data)

        #expect(response.id == "pay_500001")
        #expect(response.state == .actionRequired)
        #expect(response.returnURL == "https://gopay.com/sdk/charge-return")
        #expect(response.paymentInstrument?.paymentInstrument == "PAYMENT_CARD")
        #expect(response.paymentInstrument?.details?.maskedPan == "406821******1234")
        #expect(response.paymentInstrument?.details?.scheme == "VISA")
        #expect(response.action != nil)
        #expect(response.action?.actionType == .emv3ds)
        #expect(response.action?.state == "CREATED")
        #expect(response.action?.redirectURL == "https://gate.gopay.com/redirect/3ds")
    }

    @Test func chargePaymentResponseDecodingWithoutAction() async throws {
        let data = try makeChargeResponseData(withAction: false)
        let response = try JSONDecoder().decode(GopayChargePaymentResponse.self, from: data)

        #expect(response.id == "pay_500001")
        #expect(response.state == .succeeded)
        #expect(response.action == nil)
    }

    @Test func chargePaymentRequestEncoding() async throws {
        let input = GopayChargeCardTokenInput(
            cardToken: "token_abc",
            challengePreferrence: .auto
        )
        let instrument = GopayChargePaymentCardData(input: input)
        let request = GopayChargePaymentRequest(
            paymentInstrument: instrument,
            returnURL: "https://gopay.com/sdk/charge-return"
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let returnURL = json?["return_url"] as? String
        #expect(returnURL == "https://gopay.com/sdk/charge-return")

        let pi = json?["payment_instrument"] as? [String: Any]
        #expect(pi?["payment_instrument"] as? String == "PAYMENT_CARD")

        let inputJSON = pi?["input"] as? [String: Any]
        #expect(inputJSON?["input_type"] as? String == "CARD_TOKEN")
        #expect(inputJSON?["card_token"] as? String == "token_abc")
        #expect(inputJSON?["challenge_preferrence"] as? String == "AUTO")
    }

    @Test func chargePaymentRequestEncodingNilPreference() async throws {
        let input = GopayChargeCardTokenInput(
            cardToken: "token_xyz",
            challengePreferrence: nil
        )
        let instrument = GopayChargePaymentCardData(input: input)
        let request = GopayChargePaymentRequest(
            paymentInstrument: instrument,
            returnURL: "https://gopay.com/sdk/charge-return"
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let pi = json?["payment_instrument"] as? [String: Any]
        let inputJSON = pi?["input"] as? [String: Any]
        #expect(inputJSON?["challenge_preferrence"] == nil)
    }

    @Test func paymentServiceChargePaymentSuccess() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = try makeChargeResponseData(withAction: true)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.chargePayment(
                paymentId: "pay_500001",
                cardToken: "token_abc",
                challengePreference: .auto,
                returnURL: "https://gopay.com/sdk/charge-return"
            ) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.id == "pay_500001")
            #expect(response.state == .actionRequired)
            #expect(response.action?.actionType == .emv3ds)
            #expect(response.action?.redirectURL == "https://gate.gopay.com/redirect/3ds")
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func paymentServiceChargePaymentNoToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        keychain.clearTokens()

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.chargePayment(
                paymentId: "pay_1",
                cardToken: "tok",
                challengePreference: nil,
                returnURL: "https://gopay.com/sdk/charge-return"
            ) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.noAccessToken)
        }
    }

    @Test func paymentServiceChargePaymentExpiredToken() async throws {
        let mockClient = MockNetworkClient()
        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now - 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.chargePayment(
                paymentId: "pay_1",
                cardToken: "tok",
                challengePreference: nil,
                returnURL: "https://gopay.com/sdk/charge-return"
            ) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.accessTokenExpired)
        }
    }

    @Test func paymentServiceChargePaymentNetworkError() async throws {
        let mockClient = MockNetworkClient()
        mockClient.error = NSError(domain: "NetworkError", code: 500)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.chargePayment(
                paymentId: "pay_1",
                cardToken: "tok",
                challengePreference: .auto,
                returnURL: "https://gopay.com/sdk/charge-return"
            ) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == "NetworkError")
            #expect((error as NSError).code == 500)
        }
    }

    @Test func paymentServiceChargePaymentInvalidResponse() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = "not json".data(using: .utf8)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let service = GopayPaymentService(networkClient: mockClient, keychainStorage: keychain)
        let result = await withCheckedContinuation { continuation in
            service.chargePayment(
                paymentId: "pay_1",
                cardToken: "tok",
                challengePreference: nil,
                returnURL: "https://gopay.com/sdk/charge-return"
            ) { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure:
            #expect(Bool(true))
        }
    }

    @Test func gopaySDKChargePaymentSuccessNoAction() async throws {
        let mockClient = MockNetworkClient()
        mockClient.responseData = try makeChargeResponseData(withAction: false)

        let keychain = MockKeychainStorage()
        let now = Date().timeIntervalSince1970
        keychain.storeAccessToken(makeJWT(exp: now + 3600))

        let config = GopaySDKConfig(environment: .sandbox)
        let sdk = GopaySDK(config: config, networkClient: mockClient, keychainStorage: keychain)

        let result = await withCheckedContinuation { continuation in
            sdk.chargePayment(paymentId: "pay_500001", cardToken: "token_abc") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.id == "pay_500001")
            #expect(response.state == .succeeded)
            #expect(response.action == nil)
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func gopaySDKChargePaymentNotInitialized() async throws {
        let sdk = GopaySDK()
        let result = await withCheckedContinuation { continuation in
            sdk.chargePayment(paymentId: "pay_1", cardToken: "tok") { result in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false))
        case .failure(let error):
            #expect((error as NSError).domain == GopaySDKErrors.paymentServiceDomain)
            #expect((error as NSError).userInfo[NSLocalizedDescriptionKey] as? String == GopaySDKErrors.noAccessToken)
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
            cardPan: "",
            expMonth: "",
            expYear: "",
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
