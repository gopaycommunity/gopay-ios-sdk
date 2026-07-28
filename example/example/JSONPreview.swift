//
//  JSONPreview.swift
//  example
//
//  Shared pretty-printer used by both demo surfaces: the developer sandbox dumps every SDK
//  response through it, and the checkout hides one behind a "Developer details" disclosure.
//

import Foundation

enum JSONPreview {
    static func string<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }
}
