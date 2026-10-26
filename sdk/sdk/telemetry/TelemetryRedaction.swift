import Foundation

/// What may leave the device in an operational event, scrubbed the way the browser SDK scrubs it.
///
/// Two kinds of text are sent: messages, which are not key-structured and so get the shape-based
/// scrub of ``safeErrorMessage(_:)``, and the bodies of the SDK's own requests, which are redacted
/// key by key first and then get the same scrub on every string that survives
/// (``serializeBody(_:contentType:)``). Both are ports of the browser SDK's `sanitize.ts`, with the
/// same constants and the same order of steps, so the two producers drop the same things.
///
/// The patterns are written for ICU so that they match what the JavaScript ones match: `[0-9]`
/// rather than `\d` and an explicit ASCII class rather than `\w` or `\b`, which ICU would extend to
/// every script.
///
/// Mirrors the Android `Redaction`.
enum TelemetryRedaction {

    static let redacted = "[redacted]"

    /// Longest message kept; anything past it is cut.
    static let maxMessageLength = 500

    /// The cap per request or response body.
    static let maxBodyLength = 2000

    /// Nested deeper than this is dropped whole. The root is depth 0.
    static let maxDepth = 4

    // MARK: - Messages

    /// A message safe to put in an event: no e-mail, no signed card-comm URL, no query string or
    /// fragment, no `name=value` pair for a name worth never printing, no compact JOSE token, no
    /// PAN-shaped digits, at most ``maxMessageLength`` characters. Same steps in the same order as
    /// the browser SDK's `safeErrorMessage`.
    static func safeErrorMessage(_ text: String) -> String {
        var result = redactEmails(text)
        result = cardCommURL.stringByReplacingMatches(in: result, range: whole(result), withTemplate: "$1\(redacted)")
        // Keeps the `?` or `#`, so a reader can see what was dropped.
        result = queryOrFragment.stringByReplacingMatches(in: result, range: whole(result), withTemplate: "$1\(redacted)")
        result = sensitivePair.stringByReplacingMatches(in: result, range: whole(result), withTemplate: redacted)
        result = replacing(joseRun, in: result, with: redactJose)
        // Last: the rules above leave `[redacted]` behind, and a PAN can still sit in what they
        // did not match.
        result = panLike.stringByReplacingMatches(in: result, range: whole(result), withTemplate: redacted)
        return capped(result, at: maxMessageLength)
    }

    /// 12 to 19 digits, written whole or in groups split by one space or dash.
    private static let panLike = regex(#"[0-9](?:[ -]?[0-9]){11,18}"#)

    /// A card-comm form URL keeps its form-type letter and loses the signed token after it.
    private static let cardCommURL = regex(#"(/gp-card-comm/[a-z0-9]+/)\S+"#, caseInsensitive: true)

    /// A query string or a fragment, either of which can carry a token or an e-mail.
    private static let queryOrFragment = regex(#"([?#])\S*"#)

    /// A run long enough to be a compact JOSE token. Whether it is one is decided by
    /// ``redactJose(_:)``, not by the pattern, which keeps the match linear.
    private static let joseRun = regex(#"[A-Za-z0-9._-]{26,}"#)

    /// `name=value` for the names worth never printing, any name ending in `token` or `secret`
    /// included. The look-behind stands in for JavaScript's ASCII `\b`.
    private static let sensitivePair = regex(
        #"(?<![A-Za-z0-9_])(?:MD|PaRes|CRes|creq|authorization|password|[A-Za-z0-9_]*(?:token|secret))\s*=\s*\S+"#,
        caseInsensitive: true
    )

    /// The domain half of an e-mail address, anchored on the `@` so the match stays linear. The
    /// local part is walked back from it in ``redactEmails(_:)``.
    private static let emailDomain = regex(#"@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+"#)

    private static func redactEmails(_ text: String) -> String {
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in emailDomain.matches(in: text, range: whole(text)) {
            let at = match.range.location
            var start = at
            while start > last, isEmailLocalCharacter(ns.character(at: start - 1)) {
                start -= 1
            }
            // An `@` with nothing usable in front of it is not an address.
            if start == at { continue }
            out += ns.substring(with: NSRange(location: last, length: start - last)) + redacted
            last = at + match.range.length
        }
        return out + ns.substring(from: last)
    }

    private static func isEmailLocalCharacter(_ unit: unichar) -> Bool {
        switch unit {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        case 0x2E, 0x5F, 0x25, 0x2B, 0x2D: return true // . _ % + -
        default: return false
        }
    }

    /// Three to five segments of at least eight characters each, after trimming the dots a greedy
    /// run takes from the punctuation around it. A token ending a sentence keeps its full stop.
    private static func redactJose(_ run: String) -> String {
        let characters = Array(run)
        var start = 0
        var end = characters.count
        while start < end, characters[start] == "." { start += 1 }
        while end > start, characters[end - 1] == "." { end -= 1 }
        let parts = String(characters[start..<end]).split(separator: ".", omittingEmptySubsequences: false)
        guard (3...5).contains(parts.count), parts.allSatisfy({ $0.count >= 8 }) else { return run }
        return String(characters[..<start]) + redacted + String(characters[end...])
    }

    // MARK: - Bodies

    /// A request or response body as `req_body` / `res_body` carry it: parsed, redacted by key,
    /// every remaining string scrubbed, then JSON cut at ``maxBodyLength``. `nil` for no body.
    ///
    /// A form-encoded body is read as the fields it carries, as the browser SDK hands over the
    /// token request's form; JSON is read as JSON, and anything else as text, which is itself
    /// parsed when it starts with `{` or `[`. Never fails: a body is only a diagnostic.
    static func serializeBody(_ data: Data?, contentType: String?) -> String? {
        guard let data = data, !data.isEmpty else { return nil }
        let value: Any
        if let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            value = parsed
        } else if let text = String(data: data, encoding: .utf8) {
            if contentType?.lowercased().hasPrefix("application/x-www-form-urlencoded") == true {
                value = formFields(text)
            } else {
                value = text
            }
        } else {
            return nil
        }
        return serialize(value)
    }

    /// ``sanitizeLogData(_:depth:)`` then JSON, capped. `nil` when the result is not valid JSON.
    static func serialize(_ value: Any) -> String? {
        let sanitized = sanitizeLogData(value)
        guard JSONSerialization.isValidJSONObject([sanitized]),
              let data = try? JSONSerialization.data(
                withJSONObject: sanitized,
                options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
              ),
              let json = String(data: data, encoding: .utf8)
        else { return nil }
        return capped(json, at: maxBodyLength)
    }

    /// The value with every sensitive key replaced by `[redacted]`, every string scrubbed and
    /// anything past ``maxDepth`` dropped. Structure is otherwise kept, so a reader still sees what
    /// was there. A string holding JSON is read as the structure it is, at the same depth.
    static func sanitizeLogData(_ value: Any, depth: Int = 0) -> Any {
        if depth >= maxDepth {
            return redacted
        }
        if let text = value as? String {
            if let parsed = parseJSONText(text) {
                return sanitizeLogData(parsed, depth: depth)
            }
            return safeErrorMessage(text)
        }
        if let array = value as? [Any] {
            return array.map { sanitizeLogData($0, depth: depth + 1) }
        }
        if let object = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, item) in object {
                result[key] = isSensitiveKey(key) ? redacted : sanitizeLogData(item, depth: depth + 1)
            }
            return result
        }
        if value is NSNumber || value is NSNull {
            return value
        }
        // Only plain data is walked; anything else is never serialized.
        return redacted
    }

    /// JSON that arrived as text, parsed, or `nil` when it does not start like an object or an
    /// array or does not parse as one.
    private static func parseJSONText(_ text: String) -> Any? {
        guard let first = text.drop(while: { $0.isWhitespace }).first, first == "{" || first == "[",
              let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              parsed is [Any] || parsed is [String: Any]
        else { return nil }
        return parsed
    }

    private static func formFields(_ text: String) -> [String: Any] {
        var fields: [String: Any] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let decode: (Substring) -> String = {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            fields[decode(parts[0])] = parts.count > 1 ? decode(parts[1]) : ""
        }
        return fields
    }

    /// Compared without case and without separators, so `redirect_url` hits `redirecturl`.
    static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = String(String.UnicodeScalarView(key.lowercased().unicodeScalars.filter {
            ("a"..."z").contains($0) || ("0"..."9").contains($0)
        }))
        return sensitiveContainerKeys.contains(normalized)
            || sensitiveKeySubstrings.contains { normalized.contains($0) }
    }

    /// Keys whose whole value is dropped, matched exactly.
    private static let sensitiveContainerKeys: Set<String> = [
        "response", "payment", "paymentdata", "applepaypaymentdata", "googlepaymentdata", "card",
        "cards", "maskedcard", "maskedcards", "profile", "profiles", "srcprofile", "consumer",
        "consumeridentity", "identity", "threeds", "threedsdata", "challenge", "acs", "acsdata",
        "credential", "credentials", "checkout", "checkoutresponse", "checkoutresponsesignature",
        "redirectparams", "merchantsession", "merchantsessionidentifier", "validationdata",
        "encryptedcard", "recognitiontoken", "idtoken", "idtokens", "digitalcardid",
        "recipientaddress", "accountname", "bic", "input", "customer", "contact", "payer", "ip",
        "ipaddress", "useragent",
        // The QR payment's answer: the codes encode the recipient's account and the payment's
        // variable symbol, and `recipient.bank_account` spells them out. Not on the browser SDK's
        // list, which has the same gap.
        "qrcode", "spayd", "sepa", "mnbqr", "paybysquare", "bankaccount", "recipient",
    ]

    /// Fragments that drop any key containing them.
    private static let sensitiveKeySubstrings: [String] = [
        "pan", "token", "jwe", "cvv", "cvc", "cryptogram", "cavv", "secret", "signature", "password",
        "identityvalue", "cardnumber", "digitalcardid", "authentication", "otp", "email", "phone",
        "mobile", "firstname", "lastname", "accountnumber", "iban", "redirecturl",
        "maskedvalidationchannel", "encrypted", "signedmessage", "signedkey", "publickey", "nonce",
        "gwurl", "address", "holder", "fingerprint", "expiration", "expiry", "expmonth", "expyear",
        "securitycode", "cardformurl",
    ]

    // MARK: - Paths and URLs

    /// A request path as a template: segments of digits only or UUIDs become `{id}`, the query
    /// goes. `/payments/3273103424/charge` is `/payments/{id}/charge`.
    static func endpointTemplate(_ path: String) -> String {
        let withoutQuery = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let trimmed = withoutQuery.hasPrefix("/") ? withoutQuery.dropFirst() : withoutQuery
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: false).map { segment -> String in
            let text = String(segment)
            let isDigits = !text.isEmpty && text.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
            let isUUID = text.count == 36 && UUID(uuidString: text) != nil
            return (isDigits || isUUID) ? "{id}" : text
        }
        return "/" + segments.joined(separator: "/")
    }

    /// The last segment of a template that names something: `/payments/{id}` is `payments`.
    static func action(ofTemplate template: String) -> String {
        template.split(separator: "/").last { !$0.hasPrefix("{") }.map(String.init) ?? ""
    }

    /// Where a URL points, as far as it may be recorded: scheme, host and path, scrubbed like a
    /// message, without the query or the fragment.
    static func safeTarget(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host != nil
        else { return nil }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        guard let text = components.string else { return nil }
        return safeErrorMessage(text)
    }

    // MARK: - Helpers

    /// `text` cut to `length` Unicode scalars, the unit the ingest's schema counts in.
    static func capped(_ text: String, at length: Int) -> String {
        guard text.unicodeScalars.count > length else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.prefix(length)))
    }

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        // The patterns are constants; a typo here is caught by the first test that runs them.
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    private static func whole(_ text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }

    private static func replacing(
        _ regex: NSRegularExpression,
        in text: String,
        with transform: (String) -> String
    ) -> String {
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: text, range: whole(text)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            out += transform(ns.substring(with: match.range))
            last = match.range.location + match.range.length
        }
        return out + ns.substring(from: last)
    }
}
