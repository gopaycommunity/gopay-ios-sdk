# Gopay iOS SDK (`GopaySDK`)

## Overview

This repository contains the official **Gopay iOS SDK** and a simple example app.

The SDK provides:

- **Token-based authentication** against Gopay.
- **Card data encryption** and **card tokenization** via Gopay APIs.
- A secure **SwiftUI card form UI** (`GopayCardForm`) that keeps sensitive card data inside the SDK.
- **Payment charging** with automatic 3DS / PSD2 verification via an SDK-managed WebView.

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
- **Step 3**: Enter the repository URL of this SDK: `https://github.com/gopaycommunity/gopay-ios-sdk.git`.
- **Step 4**: Choose a version rule (e.g. **Up to Next Major**).
- **Step 5**: Select the **`GopaySDK`** library product and add it to your app target.

### Swift Package Manager (`Package.swift`)

If you manage dependencies in `Package.swift`, add the SDK as a dependency:

```swift
// In your Package.swift
dependencies: [
    .package(url: "https://github.com/gopaycommunity/gopay-ios-sdk.git", from: "1.0.0")
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

### CocoaPods

The SDK is also available as a CocoaPod named `GopaySDK`.

Add it to your `Podfile`:

```ruby
target 'YourApp' do
  use_frameworks!

  pod 'GopaySDK', '~> 1.2'
end
```

Then install:

```bash
pod repo update
pod install
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

#### Create payment – `createPayment(goid:request:completion:)`

**Purpose**: Create a new payment session via `POST /eshops/{goid}/payments`.

```swift
let request = GopayCreatePaymentRequest(
    amount: 10000, // cents
    currency: .czk,
    orderNumber: "2025010199",
    orderDescription: "Order #2025010199",
    additionalParams: [
        GopayAdditionalParam(name: "source", value: "ios-app")
    ],
    customer: GopayPaymentCustomer(
        email: "john.doe@example.com",
        firstName: "John",
        lastName: "Doe",
        phoneNumber: "+420123456789",
        city: "Prague",
        street: "Example street 10",
        postalCode: "10000",
        countryCode: "CZE",
        customerId: "customer420"
    ),
    callback: GopayPaymentCallback(
        notificationURL: "https://example.com/notify",
        returnURL: "https://example.com/return"
    )
)

GopaySDK.shared.createPayment(goid: "<your-goid>", request: request) { result in
    switch result {
    case .success(let response):
        print("Payment ID:", response.id)
        print("State:", response.state.rawValue)
        print("Gateway URL:", response.gatewayURL)
    case .failure(let error):
        print("Create payment failed:", error)
    }
}
```

Notes:

- You must authenticate first and have an unexpired access token.
- Token scope must include `payment:create`.
- `goid` is your e-shop identifier used in the API path.

---

#### Get payment status – `getPayment(paymentId:completion:)`

**Purpose**: Fetch the current payment status via `GET /payments/{payment_id}`.

```swift
GopaySDK.shared.getPayment(paymentId: "<payment-id>") { result in
    switch result {
    case .success(let response):
        print("Payment ID:", response.id)
        print("State:", response.state.rawValue)
        print("Amount:", response.amount, response.currency.rawValue)
        print("Gateway URL:", response.gatewayURL)
        if let charge = response.charge {
            print("Charge ID:", charge.id)
            print("Charge state:", charge.state.rawValue)
        }
    case .failure(let error):
        print("Get payment failed:", error)
    }
}
```

**Payment status response fields:**

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Payment identifier |
| `orderNumber` | `String` | Merchant order number |
| `state` | `GopayPaymentState` | Current payment state |
| `amount` | `Int` | Amount in minor units (e.g. cents) |
| `currency` | `GopayPaymentCurrency` | Payment currency |
| `customer` | `GopayPaymentCustomer` | Customer details |
| `gatewayURL` | `String` | GoPay gateway URL |
| `charge` | `GopayPaymentStatusCharge?` | Latest charge summary, when available |

Notes:

- You must authenticate first and have an unexpired access token with `payment:read` scope.
- Use this method after charging to confirm the final state (for example after a 3DS flow).

---

#### Get payment charge state – `getPaymentChargeState(paymentId:completion:)`

**Purpose**: Fetch the latest charge status via `GET /payments/{payment_id}/charge`.

```swift
GopaySDK.shared.getPaymentChargeState(paymentId: "<payment-id>") { result in
    switch result {
    case .success(let response):
        print("Charge ID:", response.id)
        print("Charge state:", response.state.rawValue)
        if let action = response.action {
            print("Action type:", action.actionType.rawValue)
            print("Redirect URL:", action.redirectURL ?? "-")
        }
    case .failure(let error):
        print("Get payment charge state failed:", error)
    }
}
```

Notes:

- You must authenticate first and have an unexpired access token with `payment:read` scope.
- Use this method after `chargePayment` when you want to query the charge-specific state directly.

---

#### Get payment QR info – `getPaymentQRInfo(paymentId:format:completion:)`

**Purpose**: Fetch QR payment data via `GET /payments/{payment_id}/qr-payment/info`.

```swift
GopaySDK.shared.getPaymentQRInfo(
    paymentId: "<payment-id>",
    format: .png // optional, default is .png (.svg is also supported)
) { result in
    switch result {
    case .success(let response):
        print("Amount:", response.amount, response.currency.rawValue)
        print("Recipient:", response.recipient.name)
        print("IBAN:", response.recipient.bankAccount.international.iban)
        print("SPAYD payload:", response.qrCode.spayd ?? "-")
    case .failure(let error):
        print("Get payment QR info failed:", error)
    }
}
```

Notes:

- You must authenticate first and have an unexpired access token with `payment:read` scope.
- `format` controls the QR payload variant returned by the API (`.png` or `.svg`).
- `paymentId` is the payment identifier returned by `createPayment`.

---

#### Charge payment – `chargePayment(paymentId:cardToken:challengePreference:presentingViewController:completion:)`

**Purpose**: Charge a payment using a card token. Calls `POST /payments/{payment_id}/charge`. If the server requires 3DS / PSD2 verification, the SDK automatically presents a WKWebView for the user to complete the challenge, then returns control to your completion handler.

The `return_url` sent to the API is managed entirely by the SDK — you do not need to provide or configure it.

```swift
GopaySDK.shared.chargePayment(
    paymentId: "<payment-id>",      // from createPayment response
    cardToken: "<card-token>",      // from createCardToken / submitCardForm
    challengePreference: .auto      // optional: .auto, .challengePreferred, .noChallengePreferred
) { result in
    switch result {
    case .success(let response):
        print("Charge state:", response.state.rawValue)
        // If 3DS was required, the WebView was shown and dismissed by the SDK.
        // Poll for the final payment state if response.state == .actionRequired.
    case .failure(let error):
        print("Charge failed:", error.localizedDescription)
    }
}
```

You can also control which view controller presents the verification WebView:

```swift
GopaySDK.shared.chargePayment(
    paymentId: "<payment-id>",
    cardToken: "<card-token>",
    challengePreference: .auto,
    presentingViewController: self   // pass nil to auto-detect the top-most VC
) { result in
    // …
}
```
**Charge response fields:**

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Charge identifier |
| `state` | `GopayChargeState` | Current charge state |
| `paymentInstrument` | `GopayChargePaymentInstrument?` | Details of the instrument used |
| `returnURL` | `String` | The SDK's internal return URL (informational) |
| `action` | `GopayChargeAction?` | Present if further action was required |

**`GopayChargeState` values:**

| Value | Meaning |
|---|---|
| `.requested` | Charge has been requested |
| `.processing` | Charge is being processed |
| `.actionRequired` | 3DS or other verification is required |
| `.succeeded` | Charge was successful |
| `.failed` | Charge failed |

> **Note**: After a successful 3DS verification the response state will still reflect the state at the time of the initial charge call (typically `.actionRequired`). Poll the payment status using a separate endpoint to confirm the final charge outcome.

Notes:

- You must authenticate first and have an unexpired access token with `payment:create` scope.
- `paymentId` is the `id` returned by `createPayment`.
- `cardToken` is the token string returned by `createCardToken` or `submitCardForm`.
- `WebKit` is loaded by the SDK only when a redirect action is present — no setup required in your app.

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

---

## Maintainer Notes – Releasing New Versions

This section is for developers maintaining the SDK.

### Releasing a new Swift Package version

- Bump the version in your Git tag (for example `0.0.1`, `1.0.0`, `1.1.0`).
- Ensure `Package.swift` is correct and committed at the repo root.
- Create and push a tag that matches the version you want to publish:

```bash
git tag 1.2.0
git push origin 1.2.0
```

Xcode / Swift Package Manager will pick up the new version from the Git tag.

### Releasing a new CocoaPods version

1. Update `GopaySDK.podspec`:
   - Set `spec.version` to the new version, for example `1.2.0`.
   - Make sure `spec.source` points to this repository and uses the same tag:
     ```ruby
     spec.source = { :git => "https://github.com/gopaycommunity/gopay-ios-sdk.git", :tag => "#{spec.version}" }
     ```
2. Commit and tag the release:

```bash
git add GopaySDK.podspec
git commit -m "Release 1.2.0"
git tag 1.2.0
git push origin main
git push origin 1.2.0
```

3. Lint and publish via CocoaPods Trunk (from the repo root):

```bash
pod lib lint GopaySDK.podspec --allow-warnings
pod trunk push GopaySDK.podspec --allow-warnings
```

After `pod trunk push` succeeds, the new `GopaySDK` version is available to integrating apps via CocoaPods.
