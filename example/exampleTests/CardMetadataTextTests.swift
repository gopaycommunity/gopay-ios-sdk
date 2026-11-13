//
//  CardMetadataTextTests.swift
//  exampleTests
//
//  The line the console prints for the metadata `submitCardFormWithMetadata` returned. The
//  Android demo tests the same three lines.
//

import Testing
import GopaySDK
@testable import example

struct CardMetadataTextTests {

    @Test func noMetadataIsSaidAsSuch() {
        #expect(CardMetadataText.line(nil) == "cardMetadata: no metadata")
    }

    @Test func fullMetadataIsPrintedFieldByFieldInTheGatewaysSpelling() {
        let metadata = CardMetadata(
            scheme: .visa,
            corporate: false,
            brand: "GOLD",
            serviceType: .debit,
            issuer: "Example Bank",
            issuerCountry: "CZE"
        )

        #expect(
            CardMetadataText.line(metadata)
                == "cardMetadata: scheme=VISA, corporate=false, brand=GOLD, serviceType=DEBIT, "
                + "issuer=Example Bank, issuerCountry=CZE"
        )
    }

    @Test func aFieldTheGatewayDidNotSendIsLeftOut() {
        #expect(
            CardMetadataText.line(CardMetadata(scheme: .mastercard, corporate: true))
                == "cardMetadata: scheme=MASTERCARD, corporate=true"
        )
    }
}
