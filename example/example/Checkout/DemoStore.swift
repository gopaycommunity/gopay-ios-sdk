//
//  DemoStore.swift
//  example
//
//  A hardcoded basket so the checkout has something real to charge for. The total is what gets
//  passed to `MerchantBackendSimulator.createPayment` — the gateway amount always matches the UI.
//

import Foundation

struct CartItem: Identifiable {
    let id = UUID()
    let emoji: String
    let name: String
    let variant: String
    /// Unit price in minor units (haléře).
    let unitPrice: Int
    let quantity: Int

    var lineTotal: Int { unitPrice * quantity }
}

struct DemoCart {
    let items: [CartItem]
    /// Minor units.
    let shipping: Int
    let currency = "CZK"

    var subtotal: Int { items.reduce(0) { $0 + $1.lineTotal } }
    var total: Int { subtotal + shipping }

    static let sample = DemoCart(
        items: [
            CartItem(emoji: "🎧", name: "Studio headphones", variant: "Over-ear · Graphite", unitPrice: 249_000, quantity: 1),
            CartItem(emoji: "☕️", name: "Single-origin beans", variant: "Ethiopia · 500 g", unitPrice: 39_000, quantity: 2),
            CartItem(emoji: "📓", name: "Dotted notebook", variant: "A5 · Sage", unitPrice: 24_900, quantity: 1)
        ],
        shipping: 9_900
    )

    /// Formats minor units as a localized currency amount (`1 234 Kč`).
    func formatted(_ minorUnits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.maximumFractionDigits = minorUnits % 100 == 0 ? 0 : 2
        let amount = Decimal(minorUnits) / 100
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) \(currency)"
    }
}
