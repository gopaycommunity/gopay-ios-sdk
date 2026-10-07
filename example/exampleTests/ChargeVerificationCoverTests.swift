//
//  ChargeVerificationCoverTests.swift
//  exampleTests
//
//  Runs in the demo app, which has a window scene, so UIKit finishes the presentations the SDK's
//  own test bundle can only start.
//

import Testing
import UIKit
@testable import GopaySDK

@MainActor
struct ChargeVerificationCoverTests {

    /// A 3DS screen covered by a screen of the host's is not closed, so it reports nothing: the
    /// challenge is still running under the cover. Reporting it as closed would end a live
    /// verification halfway through.
    @Test func aScreenCoveredByTheHostReportsNothing() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        var results: [GopayChargeVerificationResult] = []
        let screen = GopayChargeVerificationViewController(
            redirectURL: URL(string: "about:blank")!,
            returnURL: nil
        ) { results.append($0) }
        presenter.present(screen, animated: false)
        try await Task.sleep(nanoseconds: 500_000_000)

        let cover = UIViewController()
        cover.modalPresentationStyle = .fullScreen
        screen.present(cover, animated: false)
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(screen.presentedViewController === cover)
        #expect(results.isEmpty)

        presenter.dismiss(animated: false)
    }
}
