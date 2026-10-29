//
//  CardDataDescriptionTests.swift
//  sdkTests
//
//  GopayCardData prints masked, the way the Android SDK's CardData.toString() does, so a host that
//  logs the value or hands it to a crash reporter does not leak the PAN or the CVV.
//

import Testing
import Foundation
@testable import sdk

struct CardDataDescriptionTests {

    private let card = GopayCardData(cardPan: "4111111111111111", expMonth: "12", expYear: "29", cvv: "737")

    @Test func descriptionHidesThePanAndTheCvv() {
        let text = "\(card)"
        #expect(!text.contains("4111111111111111"))
        #expect(!text.contains("737"))
        #expect(text == "GopayCardData(cardPan=****1111, expMonth=12, expYear=29, cvv=***)")
    }

    @Test func debugDescriptionHidesThePanAndTheCvv() {
        let text = String(reflecting: card)
        #expect(!text.contains("4111111111111111"))
        #expect(!text.contains("737"))
        #expect(text == "\(card)")
    }

    @Test func dumpAndMirrorHideThePanAndTheCvv() {
        var dumped = ""
        dump(card, to: &dumped)
        #expect(!dumped.contains("4111111111111111"))
        #expect(!dumped.contains("737"))
        let children = Mirror(reflecting: card).children.map { "\($0.value)" }
        #expect(children == ["****1111", "12", "29", "***"])
    }

    @Test func shortPanIsMaskedWhole() {
        let short = GopayCardData(cardPan: "411111", expMonth: "12", expYear: "29", cvv: "737")
        #expect("\(short)" == "GopayCardData(cardPan=****, expMonth=12, expYear=29, cvv=***)")
    }

    @Test func panMaskingStartsAtThirteenDigits() {
        #expect(GopayCardData.maskedPan("411111111111") == "****")
        #expect(GopayCardData.maskedPan("4111111111111") == "****1111")
    }

    @Test func encodingStillCarriesTheWholeCard() throws {
        let json = try #require(String(data: JSONEncoder().encode(card), encoding: .utf8))
        #expect(json.contains("\"card_pan\":\"4111111111111111\""))
        #expect(json.contains("\"cvv\":\"737\""))
    }
}
