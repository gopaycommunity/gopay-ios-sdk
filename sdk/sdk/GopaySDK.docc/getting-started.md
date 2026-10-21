# Getting Started with GopaySDK

Learn how to initialize and configure the GopaySDK in your iOS app, including how to select the environment.

## Step 1: Import the SDK

```swift
import GopaySDK
```

## Step 2: Choose the Environment

Select the appropriate environment for your use case:

```swift
let environment: GopayEnvironment = .sandbox // or .development(baseURL: "https://your-dev-url.com"), .production
```

## Step 3: Configure the SDK

Create a configuration object with your `clientId` and `shareableKey`. They are safe to embed in
the app and cannot charge by themselves, but encrypting a card needs them, and so does every charge
whose ``BrowserData`` does not already carry both `ip` and `acceptHeader`. You can also enable
debug logging and provide an error callback, which hears every ``GopaySDKError`` the SDK throws
once, except the two outcomes of a payment window, `PAYMENT_007` and `PAYMENT_011`, and a
cancellation; the rule is the same on Android:

```swift
let config = GopaySDKConfig(
    environment: environment,
    clientId: "<your-client-id>",
    shareableKey: "<your-shareable-key>",
    enableDebugLogging: true, // Optional
    errorCallback: { error in // Optional
        print("GopaySDK Error: \(error)")
    }
)
```

## Step 4: Initialize the SDK

Initialize the SDK with your configuration. Every call that needs the gateway before this one
throws ``GopaySDKError/Code/sdkNotInitialized``:

```swift
GopaySDK.shared.initialize(with: config)
```

## Step 5: Charge a payment

Start a session for the payment your backend created and charge it with the calls both SDKs
share, then wait for the result:

```swift
let session = try await GopaySDK.shared.startPaymentSession(paymentId: paymentId, paymentSecret: paymentSecret)
_ = try await session.chargeWithCardToken(cardToken)       // or chargeWithEncryptedCard(jwe), chargeWithWallet()
let charge = try await session.awaitChargeState(AwaitChargeOptions(returnURL: returnURL))
```

## Full Example

```swift
import GopaySDK

let config = GopaySDKConfig(
    environment: .sandbox, // or .development(baseURL: "https://your-dev-url.com"), .production
    clientId: "<your-client-id>",
    shareableKey: "<your-shareable-key>",
    enableDebugLogging: true,
    errorCallback: { error in
        print("GopaySDK Error: \(error)")
    }
)

GopaySDK.shared.initialize(with: config)
```

---

For more details, see the API reference for [`GopaySDK`](<doc:GopaySDK>), [`GopaySDKConfig`](<doc:GopaySDKConfig>), and [`GopayEnvironment`](<doc:GopayEnvironment>). 