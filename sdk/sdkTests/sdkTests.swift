//
//  sdkTests.swift
//  sdkTests
//
//  Created by Jiří Hauser on 21.03.2025.
//

import Testing
@testable import sdk

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

        let config = GopaySDKConfig(environment: .development);
        
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
        let config = GopaySDKConfig(environment: .development, errorCallback: { _ in errorCallbackCalled = true })
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
        // Helper to create a JWT with a given exp value
        func makeJWT(exp: TimeInterval?) -> String {
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

}
