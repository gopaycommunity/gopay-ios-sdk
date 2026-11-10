//
//  JSONPreview.swift
//  example
//
//  Shared pretty-printer used by both demo surfaces: the developer sandbox dumps every SDK
//  response through it, and the checkout hides one behind a "Developer details" disclosure.
//
//  A `payment_secret` in a response is never printed: the console is a place people copy from
//  and take screenshots of, and the secret authorizes a charge. Neither are the customer's
//  `email` and `phone_number`, which a payment carries since 3.0: personal data has no place in
//  a screenshot either.
//

import Foundation

enum JSONPreview {
    /// What stands in for a value the demo does not print.
    static let hidden = "(hidden)"

    /// The keys whose values are replaced by ``hidden``, at any depth.
    private static let secretKeys: Set<String> = ["payment_secret", "email", "phone_number"]

    static func string<T: Encodable>(_ value: T) -> String {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        guard let encoded = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: encoded, options: .fragmentsAllowed),
              let data = try? JSONSerialization.data(withJSONObject: redacted(object), options: options),
              let string = String(data: data, encoding: .utf8) else {
            // Never the value's own description: that could print what the keys above hide.
            return "(\(T.self) could not be shown)"
        }
        return string
    }

    private static func redacted(_ object: Any) -> Any {
        if let dictionary = object as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = secretKeys.contains(entry.key) && !(entry.value is NSNull)
                    ? hidden
                    : redacted(entry.value)
            }
        }
        if let array = object as? [Any] {
            return array.map(redacted)
        }
        return object
    }
}
