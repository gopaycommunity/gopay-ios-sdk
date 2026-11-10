import Foundation

/// The GoPay client SDK that calls `POST /payments/{payment_id}/init-session`, the spec's
/// `Client-Type`. This SDK always sends ``sdkIos``; the Android SDK sends ``sdkAndroid``.
enum ClientType: String, Encodable, Sendable {
    case sdkBrowser = "SDK_BROWSER"
    case sdkAndroid = "SDK_ANDROID"
    case sdkIos = "SDK_IOS"
}

/// The body of `POST /payments/{payment_id}/init-session`: which SDK, and which version of it,
/// works with the payment.
struct InitSessionRequest: Encodable, Sendable {
    let clientType: ClientType
    let clientVersion: String

    enum CodingKeys: String, CodingKey {
        case clientType = "client_type"
        case clientVersion = "client_version"
    }

    /// This SDK, at ``GopaySDK/version``.
    static let current = InitSessionRequest(clientType: .sdkIos, clientVersion: GopaySDK.version)
}

/// The `Accept-Language` value for `languages`, the device's languages in its order, built as the
/// browser SDK's `buildAcceptLanguage` builds it: the first tag as it is, every next one with
/// `;q=` falling by 0.1 to no less than 0.1, nothing merged or dropped as a duplicate, for example
/// `cs-CZ,cs;q=0.9,en-GB;q=0.8`.
///
/// The gateway sets the payment's language from it. URLSession would send a value of its own
/// otherwise, which follows the app's localizations as much as the device's, so the SDK sends the
/// device's languages itself, as a browser does. `GopayConfig.locale` does not come into it:
/// that is the card form's language, not the payment's.
///
/// A tag that is not ASCII letters and digits in hyphen-separated parts cannot go into the header
/// and is left out, and the weights follow the order of what is left; the browser SDK filters
/// nothing, the Android SDK the same as here. With no tag left, the device's current language
/// stands alone, as the browser SDK falls back to `navigator.language`; `nil` when even that is
/// not usable, and the request then goes without the header.
func acceptLanguageHeader(_ languages: [String], fallback: String = currentLanguageTag()) -> String? {
    let usable = languages.filter(isHeaderSafeLanguageTag)
    let tags = usable.isEmpty ? [fallback].filter(isHeaderSafeLanguageTag) : usable
    guard !tags.isEmpty else { return nil }
    return tags.enumerated().map { index, tag in
        guard index > 0 else { return tag }
        // Tenths as integers, so the value is the browser SDK's `toFixed(1)` without the floats.
        let tenths = max(10 - index, 1)
        return "\(tag);q=0.\(tenths)"
    }.joined(separator: ",")
}

/// The device's current language as a BCP 47 tag, `cs-CZ` for the `cs_CZ` locale.
func currentLanguageTag() -> String {
    let identifier = Locale.current.identifier
    let withoutKeywords = identifier.split(separator: "@", maxSplits: 1).first.map(String.init) ?? identifier
    return withoutKeywords.replacingOccurrences(of: "_", with: "-")
}

/// The Android SDK's `[A-Za-z0-9]+(-[A-Za-z0-9]+)*`, spelled out in ASCII.
private func isHeaderSafeLanguageTag(_ tag: String) -> Bool {
    tag.range(of: "^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$", options: .regularExpression) != nil
}
