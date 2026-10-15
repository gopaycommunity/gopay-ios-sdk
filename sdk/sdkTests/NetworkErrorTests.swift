//
//  NetworkErrorTests.swift
//  sdkTests
//
//  Pins the error contract at the edge of the network: a request without an HTTP response is a
//  GopaySDKError with a transport code, and /oauth2/token reports AUTH_010 only for rejected
//  credentials. The Android SDK maps the same failures to the same codes.
//

import Testing
import Foundation
@testable import sdk

struct TransportErrorMappingTests {

    @Test(arguments: [
        (URLError.Code.timedOut, GopaySDKError.Code.networkTimeout),
        (.notConnectedToInternet, .networkNoConnection),
        (.cannotFindHost, .networkNoConnection),
        (.cannotConnectToHost, .networkNoConnection),
        (.dnsLookupFailed, .networkNoConnection),
        (.dataNotAllowed, .networkNoConnection),
        (.internationalRoamingOff, .networkNoConnection),
        (.callIsActive, .networkNoConnection),
        (.secureConnectionFailed, .networkIOError),
        (.serverCertificateUntrusted, .networkSSLError),
        (.serverCertificateHasBadDate, .networkSSLError),
        (.serverCertificateHasUnknownRoot, .networkSSLError),
        (.serverCertificateNotYetValid, .networkSSLError),
        (.clientCertificateRejected, .networkSSLError),
        (.clientCertificateRequired, .networkSSLError),
        (.networkConnectionLost, .networkIOError),
        (.badServerResponse, .networkIOError)
    ])
    func aUrlErrorMapsToItsTransportCode(urlError: URLError.Code, code: GopaySDKError.Code) {
        let mapped = GopaySDKError.transport(URLError(urlError))
        #expect(mapped.code == code)
        #expect(mapped.httpStatus == nil)
        #expect((mapped.underlying as? URLError)?.code == urlError)
    }

    @Test func anyOtherTransportFailureIsNetworkIOError() {
        let mapped = GopaySDKError.transport(NSError(domain: "other", code: 1))
        #expect(mapped.code == .networkIOError)
        #expect((mapped.underlying as NSError?)?.domain == "other")
    }
}

extension SessionNetworkTests {

    private func sdk() -> GopaySDK {
        let config = GopaySDKConfig(
            environment: .development(baseURL: stubBaseURL),
            clientId: "c",
            shareableKey: "k"
        )
        return GopaySDK(config: config, networkClient: stubbedClient())
    }

    // MARK: Transport failures

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, GopaySDKError.Code.networkNoConnection),
        (.timedOut, .networkTimeout),
        (.serverCertificateUntrusted, .networkSSLError),
        (.secureConnectionFailed, .networkIOError),
        (.networkConnectionLost, .networkIOError)
    ])
    func aPaymentCallWithoutResponseThrowsItsTransportCode(urlError: URLError.Code, code: GopaySDKError.Code) async throws {
        let isOffline = Flag()
        StubURLProtocol.reset(transportError: urlError) { req in
            if isOffline.value { return (StubURLProtocol.transportFailure, Data()) }
            return (req.url?.path ?? "").hasSuffix("oauth2/token") ? tokenResponse() : (404, Data())
        }
        let session = try await makeSession()
        isOffline.value = true

        do {
            _ = try await session.getChargeState()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == code)
            #expect((error.underlying as? URLError)?.code == urlError)
        } catch {
            Issue.record("expected a GopaySDKError, got \(error)")
        }
    }

    /// A cancelled request is a cancellation, not a transport failure.
    @Test func aCancelledRequestThrowsCancellation() async throws {
        let isCancelled = Flag()
        StubURLProtocol.reset(transportError: .cancelled) { req in
            if isCancelled.value { return (StubURLProtocol.transportFailure, Data()) }
            return (req.url?.path ?? "").hasSuffix("oauth2/token") ? tokenResponse() : (404, Data())
        }
        let session = try await makeSession()
        isCancelled.value = true

        do {
            _ = try await session.getChargeState()
            Issue.record("expected cancellation")
        } catch {
            #expect(error is CancellationError, "got \(error)")
        }
    }

    @Test func aTokenRefreshWithoutResponseKeepsItsTransportCode() async throws {
        let tokenCalls = Counter()
        StubURLProtocol.reset(transportError: .notConnectedToInternet) { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("oauth2/token") {
                return tokenCalls.increment() == 1 ? tokenResponse() : (StubURLProtocol.transportFailure, Data())
            }
            return (401, Data("{}".utf8))
        }
        let session = try await makeSession()

        do {
            _ = try await session.getStatus()
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .networkNoConnection)
        }
    }

    // MARK: /oauth2/token

    @Test(arguments: [
        (400, GopaySDKError.Code.authPaymentCredentialsInvalid),
        (401, .authPaymentCredentialsInvalid),
        (403, .authPaymentCredentialsInvalid),
        (404, .networkClientError),
        (500, .networkServerError),
        (503, .networkServerError)
    ])
    func startingASessionReportsCredentialsOnlyWhenTheGatewayRejectsThem(status: Int, code: GopaySDKError.Code) async throws {
        StubURLProtocol.reset { _ in (status, json(["error": "x"])) }

        do {
            _ = try await sdk().startPaymentSession(paymentId: "token-\(status)", paymentSecret: "s")
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == code)
            #expect(error.httpStatus == status)
        }
    }

    @Test(arguments: [
        (URLError.Code.notConnectedToInternet, GopaySDKError.Code.networkNoConnection),
        (.timedOut, .networkTimeout),
        (.serverCertificateUntrusted, .networkSSLError)
    ])
    func startingASessionOfflineIsNotACredentialsError(urlError: URLError.Code, code: GopaySDKError.Code) async throws {
        StubURLProtocol.reset(transportError: urlError) { _ in (StubURLProtocol.transportFailure, Data()) }

        do {
            _ = try await sdk().startPaymentSession(paymentId: "offline-\(urlError.rawValue)", paymentSecret: "s")
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == code)
        }
    }

    /// The key fetch before encrypting a card goes through the same client.
    @Test func aCardEncryptionOfflineThrowsNoConnection() async throws {
        StubURLProtocol.reset(transportError: .notConnectedToInternet) { _ in (StubURLProtocol.transportFailure, Data()) }

        do {
            _ = try await sdk().encryptCardData(
                GopayCardData(cardPan: "4444333322221111", expMonth: "12", expYear: "30", cvv: "123")
            )
            Issue.record("expected failure")
        } catch let error as GopaySDKError {
            #expect(error.code == .networkNoConnection)
        }
    }
}
