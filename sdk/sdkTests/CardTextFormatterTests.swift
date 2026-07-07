//
//  CardTextFormatterTests.swift
//  sdkTests
//
//  Tests for the digits-only sanitize/format contract driving FormattedTextField's
//  real-time card number and expiration formatting.
//

import Testing
@testable import sdk

struct CardTextFormatterTests {

    // MARK: - Card number

    @Test func cardNumber_format_groupsInFours() {
        #expect(CardTextFormatter.cardNumber.format("4444333322221111") == "4444 3333 2222 1111")
    }

    @Test func cardNumber_format_partialGroupIsNotPadded() {
        #expect(CardTextFormatter.cardNumber.format("444433332222111") == "4444 3333 2222 111")
        #expect(CardTextFormatter.cardNumber.format("4") == "4")
        #expect(CardTextFormatter.cardNumber.format("") == "")
    }

    @Test func cardNumber_sanitize_isIdentity() {
        // Length capping happens upstream in the coordinator; sanitize itself does nothing extra.
        #expect(CardTextFormatter.cardNumber.sanitize("123456") == "123456")
    }

    // MARK: - Expiration sanitize

    @Test func expiration_sanitize_allowsAnyTwoDigitsUpTo12() {
        #expect(CardTextFormatter.expiration.sanitize("01") == "01")
        #expect(CardTextFormatter.expiration.sanitize("12") == "12")
    }

    @Test func expiration_sanitize_twoDigitsOver12CollapsesToFirstDigit() {
        #expect(CardTextFormatter.expiration.sanitize("13") == "1")
        #expect(CardTextFormatter.expiration.sanitize("99") == "9")
    }

    @Test func expiration_sanitize_shortInputPassesThroughUnchanged() {
        #expect(CardTextFormatter.expiration.sanitize("") == "")
        #expect(CardTextFormatter.expiration.sanitize("1") == "1")
    }

    @Test func expiration_sanitize_validMonthKeepsYearDigits() {
        #expect(CardTextFormatter.expiration.sanitize("1299") == "1299")
        #expect(CardTextFormatter.expiration.sanitize("015") == "015")
    }

    @Test func expiration_sanitize_invalidMonthWithYearDigitsCollapsesToFirstDigit() {
        #expect(CardTextFormatter.expiration.sanitize("139") == "1")
        #expect(CardTextFormatter.expiration.sanitize("999") == "9")
    }

    // MARK: - Expiration format

    @Test func expiration_format_noSlashUnderTwoDigits() {
        #expect(CardTextFormatter.expiration.format("") == "")
        #expect(CardTextFormatter.expiration.format("1") == "1")
    }

    @Test func expiration_format_trailingSlashAtExactlyTwoDigits() {
        #expect(CardTextFormatter.expiration.format("12") == "12/")
    }

    @Test func expiration_format_insertsSlashBetweenMonthAndYear() {
        #expect(CardTextFormatter.expiration.format("129") == "12/9")
        #expect(CardTextFormatter.expiration.format("1299") == "12/99")
    }
}
