# Gopay SDK Error Codes Reference (iOS)

`GopaySDKError` carries a stable `code` following the pattern `DOMAIN_XXX`, a human-readable
`message`, and, for failures originating from an HTTP response, the offending `httpStatus` and
the gateway's error body as `gatewayError` (`error`, `message`, `detail`, each optional). The
gateway's `message` is appended to the SDK's own. It conforms to `LocalizedError`, so
`error.localizedDescription` reads like
`[AUTH_010] payment_credentials rejected: HTTP 401: Invalid payment_id or payment_secret`.

The codes are a **shared cross-platform contract**: they mirror the Android SDK's `GopayErrorCodes`
so both platforms report the same code for the same condition. The iOS SDK throws the subset below;
the full catalog, including codes only the Android surface can raise, is in that SDK's
[`ERROR_CODES.md`](https://github.com/gopaycommunity/gopay-android-sdk/blob/master/sdk/docs/ERROR_CODES.md).
Never add, rename, or repurpose a code on one platform alone.

## The `errorCallback` rule

`GopaySDKConfig.errorCallback` is for central logging and monitoring, not a substitute for
catching the error at the call. The rule is the same on both platforms:

- Every `GopaySDKError` a public call of `GopaySDK` or of a `PaymentSession` throws reaches the
  callback **once**. A call made of several steps, such as `chargeWithWallet`, which reads the
  wallet configuration and then charges, or `awaitChargeState`, which reads the charge again and
  again, reports the one error it ends with, not each step on the way. An error wrapped into
  another on the way out, the gateway's 401 behind `AUTH_010` or the browser-data fetch behind a
  charge error, is reported as the one you catch; the inner one is its `underlying`.
- `reauthenticate()` on a session is a public call like any other, so a refresh it fails is
  reported once by it; a refresh that fails inside another call is reported by that call.
- Two codes never reach it, because they are outcomes of a payment window rather than failures:
  `PAYMENT_007` (the charge is still undecided) and `PAYMENT_011` (the sheet or the 3DS screen
  closed early).
- A `CancellationError` from a task the host cancelled never reaches it, and no error of a type
  other than `GopaySDKError` does. Constructing a `GopaySDKError` yourself reports nothing.
- `CONFIG_001` is thrown before `initialize`, when no callback is installed yet, so it does not
  reach one.

The callback runs on whatever thread the failing call ends on, not necessarily the main thread.

## Error Code Structure

- **AUTH_XXX**: authentication and authorization errors
- **NETWORK_XXX**: HTTP errors returned by the gateway, and the transport failing before one
- **CONFIG_XXX**: configuration and initialization errors
- **PAYMENT_XXX**: payment flow errors
- **VALIDATION_XXX**: input validation errors
- **INTERNAL_XXX**: internal SDK errors

## Authentication Errors (AUTH_XXX)

### AUTH_009: Payment Token Expired
- **Case**: `authPaymentTokenExpired`
- **Description**: The payment-scoped JWT expired and could not be re-acquired from the cached payment credentials
- **Common Causes**:
  - Session left idle past the token lifetime
  - `payment_secret` no longer valid for the payment
- **Developer Action**:
  - The SDK re-authenticates once automatically on a 401 and retries; this code is thrown when the retry gets a second 401 after that re-authentication succeeded, on both platforms. A re-authentication the gateway refuses is `AUTH_010`
  - Start a new `PaymentSession` for the payment

### AUTH_010: Invalid Payment Credentials
- **Case**: `authPaymentCredentialsInvalid`
- **Description**: The `payment_id` / `payment_secret` pair was rejected by `/oauth2/token`, which answered HTTP 400, 401 or 403
- **Common Causes**:
  - Pair belongs to a different environment than the SDK is configured for
  - Payment already closed or expired on the gateway
  - `payment_secret` older than seven days, which the gateway refuses with a 403
  - A `scope` the gateway does not accept for payment credentials, passed to `startPaymentSession` (only `payment:read` and `payment:charge` are)
- **Developer Action**:
  - Re-fetch the pair from your merchant backend
  - Confirm the SDK's environment matches the one that created the payment
- **Note**: any other answer keeps its own code: another 4xx is `NETWORK_002`, a 5xx is `NETWORK_003`, and no response at all is one of the transport codes below. Only this code means the credentials are wrong

### AUTH_011: Shareable Key Missing
- **Case**: `authShareableKeyMissing`
- **Description**: `clientId` / `shareableKey` are absent from `GopaySDKConfig` but required by the requested operation
- **Common Causes**:
  - SDK initialized without them, then a card was encrypted (`encryptCardData` / `submitCardForm` fetch `GET /cards/public-key` every time); no request is sent
  - A charge, which first fetches `GET /cards/browser-data` with the same credentials; the charge is not sent
- **Developer Action**:
  - Supply both in `GopaySDKConfig` — they are safe to embed in the app

### AUTH_012: Payment Session Already Exists
- **Case**: `authPaymentSessionAlreadyExists`
- **Description**: A `PaymentSession` for the given `payment_id` is already registered
- **Common Causes**:
  - `startPaymentSession` called twice for the same payment
- **Developer Action**:
  - Reuse it via `getPaymentSession(_:)`, or `close()` it before starting another

### AUTH_013: Payment Session Closed
- **Case**: `authPaymentSessionClosed`
- **Description**: An operation was invoked on a `PaymentSession` that has been closed
- **Common Causes**:
  - Session used after `close()` or `closeAllPaymentSessions()`
- **Developer Action**:
  - Start a new session for the payment

## Network Errors (NETWORK_XXX)

A request that got no HTTP response throws one of `NETWORK_001`, `NETWORK_004`, `NETWORK_005` or
`NETWORK_007`, with the `URLError` as `underlying`. The same mapping applies on Android.

### NETWORK_001: Timeout
- **Case**: `networkTimeout`
- **Description**: The request timed out before the gateway answered
- **Common Causes**:
  - Slow or congested connection
- **Developer Action**:
  - Retry with backoff; read `getChargeState()` before charging again, since a charge may have reached the gateway

### NETWORK_002: HTTP Client Error (4xx)
- **Case**: `networkClientError`
- **Description**: The gateway returned a 4xx status
- **Common Causes**:
  - The operation is not enabled for the merchant (e.g. Apple Pay in-app returns 403)
  - Malformed request or a payment in the wrong state
- **Developer Action**:
  - Read `httpStatus` and `gatewayError`; both come straight from the gateway response, and the gateway's `message` is in the error's `message` too

### NETWORK_003: HTTP Server Error (5xx)
- **Case**: `networkServerError`
- **Description**: The gateway returned a 5xx status
- **Common Causes**:
  - Gateway or downstream outage
- **Developer Action**:
  - Retry with backoff; surface a transient-failure message to the user

### NETWORK_004: No Connection
- **Case**: `networkNoConnection`
- **Description**: No connection to the gateway: the device is offline, the host does not resolve, or the connection is refused
- **Common Causes**:
  - Device offline, in flight mode, or without data allowed for the app
- **Developer Action**:
  - Tell the user they are offline and let them retry; the request was not delivered

### NETWORK_005: TLS Error
- **Case**: `networkSSLError`
- **Description**: A certificate failed: the gateway's was not accepted, or a client certificate was asked for or refused; the `URLError` is the `underlying`. Any other TLS failure, a connection reset during the handshake included, is `NETWORK_007`
- **Common Causes**:
  - A captive portal or an intercepting proxy presenting its own certificate
  - A wrong device clock, which makes a valid certificate look expired
- **Developer Action**:
  - Retry on another network; `underlying` carries the `URLError`

### NETWORK_007: Network I/O Error
- **Case**: `networkIOError`
- **Description**: The request never got an HTTP response for any other reason
- **Common Causes**:
  - The connection dropped halfway through the request
- **Developer Action**:
  - Retry; `underlying` carries the `URLError`
  - When it was a charge, read `getChargeState()` first: the charge may have reached the gateway. When it was the browser data fetch a charge runs first, the charge itself was not sent

## Configuration Errors (CONFIG_XXX)

### CONFIG_001: SDK Not Initialized
- **Case**: `sdkNotInitialized`
- **Description**: An API was called before `GopaySDK.shared.initialize(with:)`
- **Common Causes**:
  - `startPaymentSession`, `encryptCardData` or `submitCardForm` called on app start before initialization
- **Developer Action**:
  - Initialize once on app start, before any other SDK call
- **Note**: the one code `errorCallback` cannot carry, since the callback arrives with the config. The Android `getInstance()` throws the same code

### CONFIG_003: Missing Required Parameter
- **Case**: `configMissingParameter`
- **Description**: A required configuration parameter is missing
- **Developer Action**:
  - Check the values passed into `GopaySDKConfig`
- **Note**: the SDK does not throw this code. The case is deprecated and will be removed in 3.0

### CONFIG_006: Invalid Base URL
- **Case**: `invalidBaseURL`
- **Description**: The resolved API base URL is empty, or concatenating a path onto it does not yield an absolute `http(s)` URL with a host
- **Common Causes**:
  - A malformed or empty URL passed to `.development(baseURL:)`
- **Developer Action**:
  - Pass an absolute `https://` URL ending in `/`; `initialize(with:)` also logs a warning when the selected environment has no base URL
  - `.sandbox` and `.production` carry their own hosts and cannot hit this
- **Note**: thrown when the request is built, so the first call that needs the gateway fails with it. The Android SDK throws it from `Environment.DEVELOPMENT` and `initialize` instead, before any call

## Payment Errors (PAYMENT_XXX)

### PAYMENT_003: Payment Processing Failed
- **Case**: `paymentProcessingFailed`
- **Description**: The wallet produced no usable payment token
- **Common Causes**:
  - Apple Pay returned a token the SDK cannot read
  - Apple Pay returned an empty token, which is what the iOS Simulator does
- **Developer Action**:
  - Let the user try again or pick another method
  - Test Apple Pay on a device with an Apple Pay sandbox tester account, not in the Simulator
- **Note**: a charge that fails after the token was read keeps the code of its own failure. On Android the same code covers a Google Pay error, empty payment data and a Google Pay token the SDK cannot parse, and also a Google Pay set up wrongly for the app, which on iOS is `PAYMENT_004` (see there)

### PAYMENT_004: Payment Method Unavailable
- **Case**: `paymentMethodUnavailable`
- **Description**: The wallet cannot be used for this payment
- **Common Causes**:
  - The device cannot pay with Apple Pay
  - The payment allows no card network the SDK can offer in the sheet
  - The sheet could not be shown: the Apple Pay capability or the merchant ID is missing from the app
- **Developer Action**:
  - Hide the Apple Pay button and offer another method; check the entitlement when it happens on a device that has Apple Pay
- **Note**: a wallet set up wrongly for the app differs between the platforms. On iOS the sheet then cannot be shown, which is this code; on Android Google Pay answers with an error, which is `PAYMENT_003`. The Android SDK uses this code only when Google Pay itself cannot be used

### PAYMENT_006: Charge Failed
- **Case**: `paymentDeclined`
- **Description**: The charge ended `failed`. Thrown by `awaitChargeState()` only, which polls the charge for you; the manual path reads the same state from `getChargeState()` without an error
- **Common Causes**:
  - The issuer declined the card
  - 3DS authentication failed or was refused
  - Fraud prevention
- **Developer Action**:
  - Read the charge on `GopaySDKError.chargeState`; its `failReason`, when the gateway gives one, is also in the message
  - Inform the user and offer another payment method
  - Create a new payment to try again: a payment is charged once, so a retry means a new `payment_id`
- **Note**: thrown by both SDKs since 2.1; `chargeState` is set on `PAYMENT_006` and `PAYMENT_007`, and the Android SDK exposes the same field

### PAYMENT_007: Charge Timeout
- **Case**: `paymentTimeout`
- **Description**: The charge stayed undecided, in `requested` / `processing` / `unknown`, or in `actionRequired` without a new address (no `redirect_url`, an empty one, or one already reported), for the whole initial timeout of `awaitChargeState()` (`initialTimeout`, 30 s by default), counted from the call. The first `actionRequired` with a redirect URL lifts the timeout, because a 3DS challenge takes as long as the user needs; in `ThreeDSMode.automatic` it starts again once the challenge returns, in `ThreeDSMode.manual` it stays lifted
- **Common Causes**:
  - A slow issuer or acquirer
  - Gateway load
- **Developer Action**:
  - Not a failed payment: the gateway may still decide it. Do not offer a new payment right away
  - Read the charge as last read on `GopaySDKError.chargeState`, then `getChargeState()` again, or call `awaitChargeState()` again, or wait for the notification GoPay sends your backend (`notification_url`), which the GoPay guide treats as the authoritative signal
- **Note**: thrown by both SDKs since 2.1 and not reported through `errorCallback` on either platform, see the rule at the top. The read on the deadline decides: a charge still undecided there is this code, one that moved is handled as that state

### PAYMENT_008: Verification Already In Progress
- **Case**: `paymentVerificationInProgress`
- **Description**: A 3DS verification is already running; only one can run at a time
- **Common Causes**:
  - `handle3dsVerification` invoked while a verification sheet is open
- **Developer Action**:
  - Await the in-flight verification before starting another

### PAYMENT_009: Apple Pay Sheet Already In Progress
- **Case**: `paymentApplePayInProgress`
- **Description**: An Apple Pay sheet is already running; only one can run at a time (the Android SDK uses this code for Google Pay)
- **Common Causes**:
  - `chargeWithApplePay` invoked twice, e.g. from a double tap
- **Developer Action**:
  - Disable the pay button while a charge is in flight
- **Note**: used only for a sheet that is already up, never for a wallet failure (see `PAYMENT_003` and `PAYMENT_004`)

### PAYMENT_010: Verification Unreachable
- **Case**: `paymentVerificationUnreachable`
- **Description**: The 3DS challenge never reached the user, so there was nothing for them to answer
- **Common Causes**:
  - The redirect URL has been retired by the gateway, e.g. the charge it belonged to is long finished
  - The redirect URL is not an `http(s)` address, so the WebView could never have loaded it
  - No connectivity while the challenge was opening
  - The verification screen could not be presented, e.g. a previous one was still animating away
  - The challenge asked to hand off to a banking app and nothing on the device opened it
- **Developer Action**:
  - Read the charge state and report the payment as unverified rather than as abandoned
  - Do not treat it as a user dismissal, which arrives as `PAYMENT_011` instead
  - Charge again to obtain a fresh redirect URL
  - A presentation that was refused can be retried as soon as the screen is free
  - A hand-off nobody took usually means the banking app is not installed; offer the user another way to authorize
- **Note**: when the page answered with an error status, `httpStatus` carries it. The refused
  presentation is an iOS-only cause: UIKit will not present while the previous screen is still
  animating away, and the Android activity has no such window. The Android SDK reports the same
  code without `httpStatus` and without that cause.

### PAYMENT_011: Payment Cancelled
- **Case**: `paymentCancelled`
- **Description**: The payment window closed before it finished: the Apple Pay sheet or the 3DS screen was closed, or the 3DS page failed after it had started rendering
- **Common Causes**:
  - The Apple Pay sheet was closed without paying
  - The 3DS verification screen was closed, by the user or by the app's own navigation, e.g. after the return from a banking app
  - The 3DS page failed after it had started rendering, when the user may already have answered
- **Developer Action**:
  - Not a failed payment, and not necessarily one that did not happen: read `getChargeState()` before offering the payment again. A 3DS challenge may have been answered
  - When there is no charge (`NETWORK_002`, HTTP 404) or it did not go through, let the user pick a method again
- **Note**: cancelling the task that awaits the call is not this code, see Cancellation below. Not reported through `errorCallback`, see the rule at the top. The Android SDK reports the same code for Google Pay and its 3DS screen

## Validation Errors (VALIDATION_XXX)

### VALIDATION_007: Invalid Input
- **Case**: `validationInvalidInput`
- **Description**: Invalid input data was provided to an SDK call
- **Common Causes**:
  - Empty `paymentId` / `paymentSecret` passed to `startPaymentSession`
  - `encryptCardData` called with a card that fails validation: the PAN is not 13 to 19 digits, the month is not `01` to `12`, the year is not 2 to 4 digits, or the CVV is not 3 or 4 digits. The same rules apply on Android
  - `submitCardForm` called while no `GopayCardForm` holds a card (after a successful submit, or before one was typed), or while the held card is invalid
  - `awaitChargeState()` called with an `interval` or `initialTimeout` that is not positive; nothing is sent
- **Developer Action**:
  - Validate before calling, and drive the submit button from `GopayCardForm`'s `isValid` binding
- **Note**: the Android SDK adds one cause of its own: a card charge helper called without `browserData` and without an `activity`, since it derives the device's browser data from the latter. On iOS the helpers derive it from the device on their own

## Internal Errors (INTERNAL_XXX)

### INTERNAL_001: Unexpected
- **Case**: `unexpected`
- **Description**: An unexpected internal error
- **Common Causes**:
  - The card encryption itself failed in `encryptCardData` or `submitCardForm`: the merchant's public key could not be read, or a step of building the JWE failed. The message names the step and `underlying` carries the system's error when there is one. The key fetch failing keeps its own `NETWORK_*` or `AUTH_011` code; this one is only the encryption. The Android SDK throws the same code for the same failure
  - A request got a response that is not an HTTP response
  - No view controller could be found to present the 3DS screen from
- **Developer Action**:
  - Enable `enableDebugLogging` and report the message

### INTERNAL_003: Decoding
- **Case**: `decoding`
- **Description**: A response could not be decoded
- **Common Causes**:
  - Gateway returned a payload shape the SDK does not expect
- **Developer Action**:
  - Check that the SDK version matches the gateway's API version
- **Note**: a new value in one of the response enums is not a decoding error: it decodes as `unknown` and the original value goes to the debug log

## Cancellation

Two different things end a payment window early, and they are reported differently:

- **The window closed**: the Apple Pay sheet closed without paying, the 3DS screen closed by the
  user or by anything other than the SDK, or the 3DS page failing after it had started rendering.
  That throws `PAYMENT_011` (see above). The next verification or sheet can start right away. An
  Apple Pay sheet that closes while its charge is still running is not this case: the call waits
  for the charge and returns its result or its error.
- **Your code cancelled the task** that awaits the call. For `handle3dsVerification` that closes
  the 3DS screen and throws `CancellationError`, which is not a `GopaySDKError`.
  `chargeWithApplePay` cancelled before the sheet is shown throws it and shows nothing. A sheet
  already up is not closed: the call waits until the sheet closes, then returns the charge if it
  succeeded and otherwise throws `CancellationError` in place of `PAYMENT_011` or the charge's
  error, and reports neither. The Android SDK differs here, see its `ERROR_CODES.md`.

A 3DS challenge that never reached the user is neither: it throws `PAYMENT_010` (see above), and
the payment is unverified rather than abandoned. Anything that breaks after the challenge has
started rendering is reported as `PAYMENT_011`, because by then the user may already have
answered and only `getChargeState()` can say how the payment ended.
