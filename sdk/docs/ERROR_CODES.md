# Gopay SDK Error Codes Reference (iOS)

`GopaySDKError` carries a stable `code` following the pattern `DOMAIN_XXX`, a human-readable
`message`, and — for failures originating from an HTTP response — the offending `statusCode`. It
conforms to `LocalizedError`, so `error.localizedDescription` reads like
`[AUTH_010] payment_credentials rejected: HTTP 401`.

The codes are a **shared cross-platform contract**: they mirror the Android SDK's `GopayErrorCodes`
so both platforms report the same code for the same condition. The iOS SDK throws the subset below;
the full catalog, including codes only the Android surface can raise, is in that SDK's
[`ERROR_CODES.md`](https://github.com/gopaycommunity/gopay-android-sdk/blob/master/sdk/docs/ERROR_CODES.md).
Never add, rename, or repurpose a code on one platform alone.

## Error Code Structure

- **AUTH_XXX**: authentication and authorization errors
- **NETWORK_XXX**: HTTP errors returned by the gateway
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
  - The SDK re-authenticates once automatically on a 401; a second 401 surfaces this code
  - Start a new `PaymentSession` for the payment

### AUTH_010: Invalid Payment Credentials
- **Case**: `authPaymentCredentialsInvalid`
- **Description**: The `payment_id` / `payment_secret` pair was rejected by `/oauth2/token`
- **Common Causes**:
  - Pair belongs to a different environment than the SDK is configured for
  - Payment already closed or expired on the gateway
- **Developer Action**:
  - Re-fetch the pair from your merchant backend
  - Confirm the SDK's environment matches the one that created the payment

### AUTH_011: Shareable Key Missing
- **Case**: `authShareableKeyMissing`
- **Description**: `clientId` / `shareableKey` are absent from `GopaySDKConfig` but required by the requested operation
- **Common Causes**:
  - SDK initialized without them, then a public-resource endpoint was called (`GET /cards/public-key`)
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

### NETWORK_002: HTTP Client Error (4xx)
- **Case**: `networkClientError`
- **Description**: The gateway returned a 4xx status
- **Common Causes**:
  - The operation is not enabled for the merchant (e.g. Apple Pay in-app returns 403)
  - Malformed request or a payment in the wrong state
- **Developer Action**:
  - Read `statusCode` and `message`; both come straight from the gateway response

### NETWORK_003: HTTP Server Error (5xx)
- **Case**: `networkServerError`
- **Description**: The gateway returned a 5xx status
- **Common Causes**:
  - Gateway or downstream outage
- **Developer Action**:
  - Retry with backoff; surface a transient-failure message to the user

## Configuration Errors (CONFIG_XXX)

### CONFIG_001: SDK Not Initialized
- **Case**: `sdkNotInitialized`
- **Description**: An API was called before `GopaySDK.shared.initialize(with:)`
- **Common Causes**:
  - `startPaymentSession` or `getPublicEncryptionKey` called on app start before initialization
- **Developer Action**:
  - Initialize once on app start, before any other SDK call

### CONFIG_003: Missing Required Parameter
- **Case**: `configMissingParameter`
- **Description**: A required configuration parameter is missing
- **Developer Action**:
  - Check the values passed into `GopaySDKConfig`

### CONFIG_006: Invalid Base URL
- **Case**: `invalidBaseURL`
- **Description**: The resolved API base URL is empty, or concatenating a path onto it does not yield an absolute `http(s)` URL with a host
- **Common Causes**:
  - A malformed or empty URL passed to `.development(baseURL:)`
- **Developer Action**:
  - Pass an absolute `https://` URL ending in `/`; `initialize(with:)` also logs a warning when the selected environment has no base URL
  - `.sandbox` and `.production` carry their own hosts and cannot hit this

## Payment Errors (PAYMENT_XXX)

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

## Validation Errors (VALIDATION_XXX)

### VALIDATION_007: Invalid Input
- **Case**: `validationInvalidInput`
- **Description**: Invalid input data was provided to an SDK call
- **Common Causes**:
  - Empty `paymentId` / `paymentSecret`
  - `submitCardForm` or `encryptCardData` called with data that fails validation
- **Developer Action**:
  - Validate before calling, and drive the submit button from `GopayCardForm`'s `isValid` binding

## Internal Errors (INTERNAL_XXX)

### INTERNAL_001: Unexpected
- **Case**: `unexpected`
- **Description**: An unexpected internal error
- **Developer Action**:
  - Enable `enableDebugLogging` and report the message

### INTERNAL_003: Decoding
- **Case**: `decoding`
- **Description**: A response could not be decoded
- **Common Causes**:
  - Gateway returned a payload shape the SDK does not expect
- **Developer Action**:
  - Check that the SDK version matches the gateway's API version

## Cancellation

Neither path reports a `GopaySDKError`, and the two differ:

- Dismissing the **3DS WebView** throws `CancellationError`.
- Dismissing the **Apple Pay sheet** throws a `GopaySDK` `NSError` (domain `GopaySDK`, code `-1`)
  carrying "Apple Pay payment was cancelled by the user." — not `CancellationError`.

Treat both as a user action rather than a failure, but catch the Apple Pay case in a general
`catch`.
