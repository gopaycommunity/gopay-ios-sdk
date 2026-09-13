//
//  ThemeShowcase.swift
//  example
//
//  Themes the card form from JSON documents, the way a host applies a theme its own backend sent
//  down. The documents live in `ThemeShowcase.json`; the Android demo ships the same file as
//  `assets/theme-showcase.json`, so one document can be compared across iOS, Android and the web
//  card form whose parameter names they use.
//

import Foundation
import GopaySDK

/// The demo's theme documents, in the order the picker shows them.
///
/// The two the GoPay web card form ships with, `Dark` and `Red`, written out key for key, plus
/// `Default`, which is an empty document and therefore renders the SDK defaults. The web demo
/// offers the same three, so the same theme can be compared across all three channels.
struct ThemeShowcase {
    static let shared = ThemeShowcase()

    /// Document names in file order, so the picker matches the Android demo.
    let names: [String]

    private let documents: [String: Data]

    private init() {
        guard
            let url = Bundle.main.url(forResource: "ThemeShowcase", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let order = root["order"] as? [String],
            let themes = root["themes"] as? [String: Any]
        else {
            names = []
            documents = [:]
            return
        }

        names = order.filter { themes[$0] != nil }
        documents = themes.compactMapValues { try? JSONSerialization.data(withJSONObject: $0) }
    }

    /// The named document applied over the SDK defaults, or the defaults when the name is unknown.
    ///
    /// `applying(_:)` never throws: a key the SDK cannot use drops on its own and is reported in
    /// the debug log, which is the behavior a host wants for a document it did not write.
    func theme(named name: String) -> GopayCardFormTheme {
        guard let document = documents[name] else { return GopayCardFormTheme() }
        return GopayCardFormTheme().applying(document)
    }
}
