# Getting Started with GopaySDK

Learn how to initialize and configure the GopaySDK in your iOS app, including how to select the environment.

## Step 1: Import the SDK

```swift
import GopaySDK
```

## Step 2: Choose the Environment

Select the appropriate environment for your use case:

```swift
let environment: GopayEnvironment = .sandbox // or .development(baseUrl: "https://your-dev-url.com"), .production
```

## Step 3: Configure the SDK

Create a configuration object with your `clientId` and `shareableKey`. They are safe to embed in
the app and cannot charge by themselves, but encrypting a card needs them, and so does every charge
whose ``BrowserData`` does not already carry both `ip` and `acceptHeader`. You can also enable
debug logging and provide an error callback, which hears every ``GopaySDKError`` the SDK throws
once, except the two outcomes of a payment window, `PAYMENT_007` and `PAYMENT_011`, and a
cancellation; the rule is the same on Android:

```swift
let config = GopayConfig(
    environment: environment,
    clientId: "<your-client-id>",
    shareableKey: "<your-shareable-key>",
    debugLoggingEnabled: true, // Optional
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

## Step 5: Start the session when the checkout opens

Have your backend create the payment when the checkout opens, and start the payment's session
right away, not when the customer taps Pay. The SDK then has the payment ready before the customer
pays, for a card and for a wallet button alike:

```swift
let session = try await GopaySDK.shared.startPaymentSession(paymentId: paymentId, paymentSecret: paymentSecret)
```

## Step 6: Charge when the customer pays

Charge the session with the calls both SDKs share, then wait for the result:

```swift
_ = try await session.chargeWithCardToken(cardToken)       // or chargeWithEncryptedCard(jwe), chargeWithWallet()
let charge = try await session.awaitChargeState(AwaitChargeOptions(returnUrl: returnUrl))
```

Show the Apple Pay button by the device check alone (`GopaySDK.isWalletAvailable()`), and ask for
the wallet's configuration only once the customer has picked the wallet: `chargeWithWallet()`
fetches it itself, so you do not call `getWalletInfo()` when the checkout opens.

A payment is paid once: after a declined charge, create a new payment and start its session.
Close the session when the payment is over and when the customer leaves the checkout, not in
`.onDisappear`: the 3DS screen covers the checkout while the payment is still running on the
session.
``PaymentCardForm`` also works without a payment and a session; that is for encrypting a card to
tokenize and save it.

## Full Example

```swift
import GopaySDK

let config = GopayConfig(
    environment: .sandbox, // or .development(baseUrl: "https://your-dev-url.com"), .production
    clientId: "<your-client-id>",
    shareableKey: "<your-shareable-key>",
    debugLoggingEnabled: true,
    errorCallback: { error in
        print("GopaySDK Error: \(error)")
    }
)

GopaySDK.shared.initialize(with: config)
```

---

For more details, see the API reference for [`GopaySDK`](<doc:GopaySDK>), [`GopayConfig`](<doc:GopayConfig>), and [`GopayEnvironment`](<doc:GopayEnvironment>). 