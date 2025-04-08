// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "GopaySDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "GopaySDK",
            targets: ["GopaySDK"]),
    ],
    targets: [
        .target(
            name: "GopaySDK",
            path: "sdk/sdk"),
    ],
    swiftLanguageVersions: [.v5]
) 