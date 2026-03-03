# Gopay iOS SDK (`GopaySDK`)

## Overview

This repository contains the official **Gopay iOS SDK** and a simple example app.

The SDK provides:
- **Token-based authentication** against Gopay.
- **Card data encryption** and **card tokenization** via Gopay APIs.
- A secure **SwiftUI card form UI** (`GopayCardForm`) that keeps sensitive card data inside the SDK.

The public library product is named **`GopaySDK`** and targets **iOS 13+**.

---

## Requirements

- **iOS**: 13.0 or later  
- **Swift**: 5.0 or later  
- **Xcode**: 13 or later  

---

## Installation

### Swift Package Manager (Xcode GUI)

- **Step 1**: In Xcode, open your app project.
- **Step 2**: Go to **File → Add Packages…**.
- **Step 3**: Enter the repository URL of this SDK (for example `https://github.com/<your-org>/gpy-sdk-ios.git`).
- **Step 4**: Choose a version rule (e.g. **Up to Next Major**).
- **Step 5**: Select the **`GopaySDK`** library product and add it to your app target.

### Swift Package Manager (`Package.swift`)

If you manage dependencies in `Package.swift`, add the SDK as a dependency:

```swift
// In your Package.swift
dependencies: [
    .package(url: "https://github.com/<your-org>/gpy-sdk-ios.git", from: "1.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "GopaySDK", package: "gpy-sdk-ios")
        ]
    )
]
```

Then import the module in your code:

```swift
import GopaySDK
```

---

## Initialization

Before using any SDK features, configure and initialize `GopaySDK`:

```swift
import GopaySDK

// 1. Choose environment
let environment: GopayEnvironment = .sandbox
// or:
// let environment: GopayEnvironment = .development(baseURL: "https://your-dev-url.com")
// let environment: GopayEnvironment = .production

// 2. Create config
let config = GopaySDKConfig(
    environment: environment,
    enableDebugLogging: true,
    errorCallback: { error in
        print("GopaySDK Error: \(error)")
    }
)

// 3. Initialize the shared SDK instance
GopaySDK.shared.initialize(with: config)
```

Initialization should typically happen once during app startup (e.g. in your `App` / `AppDelegate`).

---

## Public API Overview

### `GopayEnvironment`

**Purpose**: Selects the backend environment used by the SDK.

```swift
let envDev: GopayEnvironment = .development(baseURL: "https://your-dev-url.com/gp-gw/api/4.0/")
let envSandbox: GopayEnvironment = .sandbox
let envProd: GopayEnvironment = .production
```

The base URL is resolved internally by the SDK.

---

### `GopaySDKConfig`

**Purpose**: Holds SDK configuration such as environment, logging and a global error callback.

```swift
let config = GopaySDKConfig(
    environment: .sandbox,
    enableDebugLogging: true,
    errorCallback: { error in
        // Centralized error handling
        print("GopaySDK error:", error)
    }
)

GopaySDK.shared.initialize(with: config)
```

---

### `GopaySDK`

#### Version

**Purpose**: Inspect the SDK version at runtime.

```swift
let sdkVersion = GopaySDK.version
print("Using GopaySDK version: \(sdkVersion)")
```

---

#### Authentication – `authenticate(clientId:clientSecret:scope:completion:)`

**Purpose**: Obtain access and (optionally) refresh tokens from Gopay.

```swift
GopaySDK.shared.authenticate(
    clientId: "<your-client-id>",
    clientSecret: "<your-client-secret>",
    scope: "payment-all"
) { result in
    switch result {
    case .success(let authResponse):
        // authResponse: GopayAuthResponse
        // Tokens are automatically stored in the secure storage.
        print("Access token: \(authResponse.accessToken)")
    case .failure(let error):
        print("Authentication failed:", error)
    }
}
```

> Note: On success, the SDK automatically stores the access and refresh tokens in secure storage.

---

#### Manually setting tokens – `setAuthenticationResponse(with:)`

**Purpose**: Inject an externally obtained `GopayAuthResponse` (for example from your own backend).

```swift
do {
    let response = GopayAuthResponse(
        accessToken: "<jwt-access-token>",
        refreshToken: "<optional-refresh-token>",
        tokenType: "Bearer",
        expiresIn: 3600
    )

    try GopaySDK.shared.setAuthenticationResponse(with: response)
} catch {
    print("Failed to set authentication response:", error)
}
```

The SDK validates that the access token is not already expired before accepting it.

---

#### Fetch encryption key – `getPublicKey(completion:)`

**Purpose**: Retrieve the public JWK used to encrypt card data.

```swift
GopaySDK.shared.getPublicKey { result in
    switch result {
    case .success(let jwk):
        // jwk: GopayJWK – JWK structure for encryption
        print("Received JWK:", jwk)
    case .failure(let error):
        print("Failed to fetch public key:", error)
    }
}
```

The SDK validates token expiry before requesting the key.

---

#### Direct card tokenization – `createCardToken(...)`

**Purpose**: Encrypt raw card data and create a card token using the Gopay API.

```swift
GopaySDK.shared.createCardToken(
    cardPan: "4111111111111111",
    expMonth: "12",
    expYear: "30",
    cvv: "123",
    permanent: true
) { result in
    switch result {
    case .success(let tokenResponse):
        // tokenResponse: GopayCreateCardTokenResponse
        print("Card token: \(tokenResponse.cardToken)")
    case .failure(let error):
        print("Failed to create card token:", error)
    }
}
```

Use this API only if you are allowed to handle raw card details in your app.  
For a more secure flow where card data stays inside the SDK, use `GopayCardForm` + `submitCardForm`.

---

#### Submit card form (single / latest form) – `submitCardForm(permanent:completion:)`

**Purpose**: Create a card token using card data entered into `GopayCardForm`, without exposing PAN/CVV to your code.

```swift
@State private var isCardValid: Bool? = nil

var body: some View {
    VStack(spacing: 16) {
        GopayCardForm(isValid: $isCardValid)

        Button("Save card") {
            GopaySDK.shared.submitCardForm(permanent: true) { result in
                switch result {
                case .success(let tokenResponse):
                    print("Card token:", tokenResponse.cardToken)
                case .failure(let error):
                    print("Failed to create card token:", error)
                }
            }
        }
        .disabled(!(isCardValid ?? false))
    }
    .padding()
}
```

The SDK automatically uses the most recently active `GopayCardForm` instance.

---

#### Submit a specific form – `submitCardForm(formId:permanent:completion:)`

**Purpose**: Use card data from a particular `GopayCardForm` when multiple forms are on screen.

```swift
@State private var isPrimaryValid: Bool? = nil
@State private var isSecondaryValid: Bool? = nil

let primaryFormId = "primary-card"
let secondaryFormId = "secondary-card"

var body: some View {
    VStack(spacing: 24) {
        GopayCardForm(isValid: $isPrimaryValid, formId: primaryFormId)
        GopayCardForm(isValid: $isSecondaryValid, formId: secondaryFormId)

        Button("Use primary card") {
            GopaySDK.shared.submitCardForm(formId: primaryFormId, permanent: true) { result in
                // Handle result
            }
        }
        .disabled(!(isPrimaryValid ?? false))

        Button("Use secondary card") {
            GopaySDK.shared.submitCardForm(formId: secondaryFormId, permanent: false) { result in
                // Handle result
            }
        }
        .disabled(!(isSecondaryValid ?? false))
    }
}
```

---

## Card Form UI (`GopayCardForm`)

### Basic usage

**Purpose**: Collect card details in a PCI-friendly way where card data never leaves the SDK.

```swift
import SwiftUI
import GopaySDK

struct PaymentView: View {
    @State private var isCardValid: Bool? = nil

    var body: some View {
        VStack(spacing: 20) {
            GopayCardForm(isValid: $isCardValid)

            Button("Pay") {
                GopaySDK.shared.submitCardForm(permanent: true) { result in
                    // Handle tokenization result
                }
            }
            .disabled(!(isCardValid ?? false))
        }
        .padding()
    }
}
```

The form:
- Manages card data internally.
- Syncs data securely to `GopaySDK`.
- Allows you to react to validation state via the optional `isValid` binding.

### Customizing appearance with `GopayCardFormTheme`

```swift
let customTheme = GopayCardFormTheme(
    textColor: .blue,
    backgroundColor: Color(.systemGray6),
    borderColor: .gray,
    focusedBorderColor: .blue,
    borderWidth: 1.0,
    cornerRadius: 12.0,
    font: .body,
    labelFont: .caption,
    spacing: 16.0,
    textFieldPadding: 12.0
)

GopayCardForm(theme: customTheme)
```

You can also override `formId` when you need to reference a specific form:

```swift
GopayCardForm(theme: customTheme, formId: "checkout-card")
```

---

## Running the Example App

This repository includes a minimal SwiftUI example app that demonstrates integrating the SDK.

### From Xcode

- **Step 1**: Open the example project:

```bash
cd example
open example.xcodeproj
```

- **Step 2**: In Xcode, select the `example` scheme.
- **Step 3**: Choose a simulator or a connected device.
- **Step 4**: Press **Run** (⌘R).

### Customizing the example

- Import `GopaySDK` in your example views.
- Configure and initialize `GopaySDK.shared` (as shown in the **Initialization** section).
- Add `GopayCardForm` and use the tokenization methods (`submitCardForm` / `createCardToken`) to experiment with real flows.

---

## Support & Contributions

- **Issues / bugs**: Please open a GitHub issue in this repository with reproduction steps, logs, and SDK version.  
- **Feature requests**: Describe your use case and desired API; we’ll use this to iterate on the SDK.
