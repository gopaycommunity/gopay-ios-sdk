# 2.3.0 (2026-10-26)


### Bug Fixes

* ignore a second pay tap while the first is running GPMOB-184 b729759


### Features

* share the QR code by tapping it GPMOB-184 747432e

## 2.2.1 (2026-10-22)


### Bug Fixes

* point the README install at 2.2 GPMOB-144 ed16f9f
* read the submitted card form outside the async context GPMOB-144 58854ee

# 2.2.0 (2026-10-21)


### Bug Fixes

* clear the PR's SonarCloud findings GPMOB-160 0315f05
* report each SDK error to errorCallback once GPMOB-160 433172c
* throw the shared error codes instead of platform exceptions GPMOB-160 cdd72be


### Features

* add the card, wallet and form API shared with Android/iOS GPMOB-160 30a438d
* use the shared API in the demo GPMOB-160 49928d3

# 2.1.0 (2026-10-20)


### Features

* add awaitChargeState with PAYMENT_006 and PAYMENT_007 GPMOB-159 3709403
* await the charge in the demo checkout and sandbox GPMOB-159 d3a1189

# 2.0.0 (2026-10-20)

A major release with a new error contract, a rebuilt card form theme and a changed 3DS flow; see [Migrating from 1.x](README.md#migrating-from-1x) in the README before upgrading.


### Bug Fixes

* charge 1 Kč in the demo checkout GPMOB-158 164c597
* clamp the themed lengths and font sizes to what the form can render GPMOB-145 6eac3fc
* clear card form data from memory after submit GPMOB-140 aa2cada
* clear the card form after a successful encryption GPMOB-149 9eab32d
* complete browser_data from the gateway before a charge GPMOB-149 eb04826
* date the card JWE by the gateway's clock GPMOB-155 d88e930
* default the card form to the platform's own appearance GPMOB-145 8939831
* end a 3DS screen closed elsewhere GPMOB-156 394aad7
* end the 3DS verification on the payment's own return URL GPMOB-149 5108cf7
* fail clearly when the selected environment has no base URL GPMOB-146 3f5096e
* give network failures SDK codes GPMOB-158 5ddc778
* give the demo's dark themes a readable placeholder GPMOB-145 8584f93
* hide the required errors once the form empties itself GPMOB-158 eecde95
* keep an input's content and border inside the field GPMOB-145 55aecc8
* keep the expiration and CVV inputs on one line GPMOB-145 275d8d8
* name built-in gateways in the demo badge and charge 1 CZK GPMOB-146 3dacb76
* read inputHeight as the minimum height of the whole field GPMOB-145 c682b5e
* report an unreachable 3DS challenge as PAYMENT_010 GPMOB-149 a9ce820
* require fresh card entry on checkout retry GPMOB-140 a69545a
* scale the input text with the same text size as its field GPMOB-145 6fd35f4
* stop offering return_url on the charge request GPMOB-149 0d2439c
* take the 3DS return URL from the backend, not the charge GPMOB-158 de7f1be
* type the Apple Pay failures GPMOB-158 3fcd09d


### Code Refactoring

* drop getPublicEncryptionKey and hide the card encryption GPMOB-155 80e33ba
* settle the theme defaults and drop the standard factory GPMOB-145 c54384c


### Features

* add demo checkout page GPMOB-138 83553dc
* configure the demo app from a gitignored xcconfig GPMOB-146 a431147
* example checkout page GPMOB-138 b9c7018
* keep the gateway's error body on GopaySDKError GPMOB-158 386d0aa
* let a 3DS challenge hand off to a banking app GPMOB-149 109cdef
* make ChargePaymentResponse.returnUrl optional GPMOB-149 eccabb9
* read gateway enum values the SDK does not know as unknown GPMOB-156 15b410b
* rebuild the card form theme around the cc-v4 parameter set GPMOB-145 d095902
* render the typography and input text theme params GPMOB-145 4e0d975
* report a closed payment window as PAYMENT_011 GPMOB-158 27640ee
* ship a privacy manifest with the SDK GPMOB-158 d0ad60f
* watch the charge for a 3DS action in the demo console GPMOB-149 8767d5c


### BREAKING CHANGES

* closing the wallet sheet or the 3DS screen throws PAYMENT_011; a cancellation comes only from the caller cancelling
* Apple Pay failures are GopaySDKError PAYMENT_003/004 instead of a GopaySDK NSError
* transport failures are GopaySDKError NETWORK_001/004/005/007, AUTH_010 only on HTTP 400/401/403
* response enums gain an unknown case for values the gateway adds later
* getPublicEncryptionKey removed; encryption utilities and key models are internal
* ChargePaymentRequest no longer takes returnUrl
* ChargePaymentResponse.returnUrl is now String? instead of String and deprecated: GoPay is removing return_url from the charge response, so pass handle3dsVerification the callback.return_url your backend created the payment with. Android mirrors the same shape.
* GopayCardFormTheme.standard is gone; GopayCardFormTheme() is the same value.
The inputBorderRadius default changes from 8 to 5 and groupSpacing from 12 to 16, so a theme
that relied on either default renders a point tighter and a row further apart than before.
* GopayCardFormTheme is rebuilt around cc-v4 params, see README migration table.

# 1.5.0 (2026-07-28)


### Features

* fill browser data on charge GPMOB-123 5745f29

# 1.4.0 (2026-07-24)


### Bug Fixes

* sonarQube issues GPMOB-133 f1113ff


### Features

* add charge payment endpoint with web transaction 61f3d6b
* add create payment API method GPMOB-117 a259af2
* add example usage of create payment endpoint GPMOB-117 ec8d5dd
* add payement charge status method GPMOB-121 552c445
* add Payment status method GPMOB-120 91f3950
* add QR payment info method GPMOB-122 5042e07
* added form locales and localization logic GPMOB-125 5d5d301
* added formatting textField in payment form GPMOB-136 0b13c40
* charge with JWE payload GPMOB-134 fdfef38

## 1.3.1 (2026-06-02)


### Bug Fixes

* avoid exporting credentials and quote variable in release step GPOMA-2293 c6aefff
# 2.0.0 (2026-06-16)


### ⚠ BREAKING CHANGES

* Migrated to the Payments 4.0 per-payment session model. The global token surface is gone:
  `authenticate`, `setAuthenticationResponse`, `createPayment`, `getPayment`,
  `getPaymentChargeState`, `getPaymentQRInfo`, `chargePayment`, `createCardToken`, the
  token-returning `submitCardForm`, and Keychain token storage have all been removed. Use
  `GopaySDK.shared.startPaymentSession(paymentId:paymentSecret:)` and the returned
  `PaymentSession`. The public API is now async/await.


### Features

* per-payment `PaymentSession` with `payment_credentials` auth, in-memory tokens, single-flight
  re-auth and one-retry-on-401 GPMOB-133
* `shareable_key` basic auth for `GET /cards/public-key`; in-memory `PublicKeyCache` GPMOB-133
* `encryptCardData` / `submitCardForm` now return a JWE for server-side tokenization GPMOB-133
* Apple Pay and 3DS verification moved onto `PaymentSession`
  (`chargeWithApplePay`, `handle3dsVerification`) GPMOB-133
* structured `GopaySDKError` with stable error codes GPMOB-133

# 1.3.0 (2026-03-03)


### Features

* add cocopods config and readme docs GPMOB-116 3fca483

# 1.2.0 (2026-03-03)


### Features

* add card tokenization network request GPMOB-65 213b6e6
* add cardTokenization example app demo GPMOB-65 727b408
* add JWE utils for card tokenization GPMOB-66 361b272
* add user-agent version on network request GPMOB-110 9b3fa90
* cardFormUI and internal data submitting GPMOB-68 bcc7877

# 1.1.0 (2025-12-09)


### Features

* add auth service GPMOB-58 a7f4583
* add authentication response setter GPMOB-58 660bac2
* add environment configuration GPMOB-54 b853fc9
* add get public key api request GPMOB-64 767fa22
* add getting started documentation GPMOB-54 ce7e3ab
* add jwt utils GPMOB-58 95eb713
* add network client GPMOB-56 1ed4d51
* add option for custom dev env setting GPMOB-54 a5cbe4c

# 1.0.0 (2025-07-07)


### Features

* project init GPMOB-8 48670dd
