//
//  DemoCartTests.swift
//  exampleTests
//

import Testing
@testable import example

struct DemoCartTests {

    /// With a real card on production every demo payment is real, so it charges 1 Kč.
    @Test func theSampleCartChargesOneCrown() {
        let cart = DemoCart.sample
        #expect(cart.subtotal == 351_900)
        #expect(cart.shipping == 9_900)
        #expect(cart.discount == 361_700)
        #expect(cart.total == 100)
    }
}
