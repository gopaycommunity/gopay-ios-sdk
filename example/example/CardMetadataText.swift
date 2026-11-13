//
//  CardMetadataText.swift
//  example
//
//  How the console prints the metadata `submitCardFormWithMetadata` returned: one line with the
//  fields the gateway sent, or `noMetadata`. The Android demo prints the same line.
//

import GopaySDK

enum CardMetadataText {

    static let noMetadata = "cardMetadata: no metadata"

    /// The scheme and the service type are printed in the gateway's spelling, in capitals, as the
    /// Android demo prints its enum names.
    static func line(_ metadata: CardMetadata?) -> String {
        guard let metadata else { return noMetadata }
        let fields: [String?] = [
            "scheme=\(metadata.scheme.rawValue)",
            "corporate=\(metadata.corporate)",
            metadata.brand.map { "brand=\($0)" },
            metadata.serviceType.map { "serviceType=\($0.rawValue)" },
            metadata.issuer.map { "issuer=\($0)" },
            metadata.issuerCountry.map { "issuerCountry=\($0)" },
        ]
        return "cardMetadata: " + fields.compactMap { $0 }.joined(separator: ", ")
    }
}
