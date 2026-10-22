## [2.2.1](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/compare/2.2.0...2.2.1) (2026-10-22)


### Bug Fixes

* point the README install at 2.2 GPMOB-144 ([ed16f9f](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/ed16f9fdcd428fb9d4c2b69f7a23818ffe34f542))
* read the submitted card form outside the async context GPMOB-144 ([58854ee](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/58854ee17f1a893aeb3171d17affdb47c7ec38de))

# [2.2.0](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/compare/2.1.0...2.2.0) (2026-10-21)


### Bug Fixes

* clear the PR's SonarCloud findings GPMOB-160 ([0315f05](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/0315f050ec4332b558ae5b421a3dbccc4f75c3b1))
* report each SDK error to errorCallback once GPMOB-160 ([433172c](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/433172c7a893d718df9633ef6f3760773b7b42b7))
* throw the shared error codes instead of platform exceptions GPMOB-160 ([cdd72be](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/cdd72bed6b8c60a25ec2194900429c9cc1c8c129))


### Features

* add the card, wallet and form API shared with Android/iOS GPMOB-160 ([30a438d](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/30a438d2f020103ea0d2b73a889f67dca8642526))
* use the shared API in the demo GPMOB-160 ([49928d3](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/49928d3c2f9c238fb5a6f57ca583f442070b7052))

# [2.1.0](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/compare/2.0.0...2.1.0) (2026-10-20)


### Features

* add awaitChargeState with PAYMENT_006 and PAYMENT_007 GPMOB-159 ([3709403](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/3709403ce9d7c4b72520304e398d2c6db6484fdb))
* await the charge in the demo checkout and sandbox GPMOB-159 ([d3a1189](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/d3a11898f31e8decb8a072c71733bf9be5393d6f))

# [2.0.0](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/compare/1.5.0...2.0.0) (2026-10-20)

A major release with a new error contract, a rebuilt card form theme and a changed 3DS flow; see [Migrating from 1.x](README.md#migrating-from-1x) in the README before upgrading.


### Bug Fixes

* charge 1 Kč in the demo checkout GPMOB-158 ([164c597](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/164c5973b0dfc86ff4dc0963c38a188c2dc92864))
* clamp the themed lengths and font sizes to what the form can render GPMOB-145 ([6eac3fc](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/6eac3fc91902b398dce72ac6344c984f7a81e197))
* clear card form data from memory after submit GPMOB-140 ([aa2cada](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/aa2cada740bdd27358c640bb9b1240c4fb3258ed))
* clear the card form after a successful encryption GPMOB-149 ([9eab32d](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/9eab32df78fe6ddabb3a74ccb1c49516859a4c54))
* complete browser_data from the gateway before a charge GPMOB-149 ([eb04826](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/eb04826bdb019f0dc73ad1d85b808e6f36338216))
* date the card JWE by the gateway's clock GPMOB-155 ([d88e930](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/d88e93075a2d6b449c1ba84f359daa41d5eb920d))
* default the card form to the platform's own appearance GPMOB-145 ([8939831](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/89398312d5493705e2c22693b0033f6cf7fac6a9))
* end a 3DS screen closed elsewhere GPMOB-156 ([394aad7](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/394aad7d5d7f6a317df051cff99480945a439288))
* end the 3DS verification on the payment's own return URL GPMOB-149 ([5108cf7](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/5108cf776e11178dd7c62226504c3b9b4db792fc))
* fail clearly when the selected environment has no base URL GPMOB-146 ([3f5096e](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/3f5096e9c309dfabb8d77429abaf3ea1eb8e59d5))
* give network failures SDK codes GPMOB-158 ([5ddc778](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/5ddc77860ccdc55c028d4fa3dbb7937d5dadcda0))
* give the demo's dark themes a readable placeholder GPMOB-145 ([8584f93](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/8584f93dd8fd11e176e4f781c8bb92a06ea1ebb0))
* hide the required errors once the form empties itself GPMOB-158 ([eecde95](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/eecde958d559e343550d40b835be35b17eda4415))
* keep an input's content and border inside the field GPMOB-145 ([55aecc8](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/55aecc837c18146c7b7ea7e26c036d9f58397d5a))
* keep the expiration and CVV inputs on one line GPMOB-145 ([275d8d8](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/275d8d89698fa93c646aec99caa3dafadeb1969d))
* name built-in gateways in the demo badge and charge 1 CZK GPMOB-146 ([3dacb76](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/3dacb76919b4c36e45066a5fd28d84a2731b93df))
* read inputHeight as the minimum height of the whole field GPMOB-145 ([c682b5e](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/c682b5e17deed756cda07ac6f743fc461e7d6818))
* report an unreachable 3DS challenge as PAYMENT_010 GPMOB-149 ([a9ce820](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/a9ce8203fa37cd11fa1ce639cbe0d203b8e2218c))
* require fresh card entry on checkout retry GPMOB-140 ([a69545a](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/a69545a2047ffe29ec4087a19eba53f4271b9e83))
* scale the input text with the same text size as its field GPMOB-145 ([6fd35f4](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/6fd35f40d7083dcdbe48a282020df7717485e96d))
* stop offering return_url on the charge request GPMOB-149 ([0d2439c](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/0d2439c8bca879268a42db23645379a74490c54f))
* take the 3DS return URL from the backend, not the charge GPMOB-158 ([de7f1be](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/de7f1bea2b8560ab182584edf02e89acbe678429))
* type the Apple Pay failures GPMOB-158 ([3fcd09d](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/3fcd09d1027ad76f3fe20493f50a59665b6d03ef))


### Code Refactoring

* drop getPublicEncryptionKey and hide the card encryption GPMOB-155 ([80e33ba](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/80e33ba0cced5604db477ed6631601ee15941607))
* settle the theme defaults and drop the standard factory GPMOB-145 ([c54384c](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/c54384ca5c0baba1a6c042644745e57bbb3f8a5b))


### Features

* add demo checkout page GPMOB-138 ([83553dc](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/83553dc87557d52c55d6bafe25aaf40f27957b78))
* configure the demo app from a gitignored xcconfig GPMOB-146 ([a431147](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/a431147dac8cb4a07ffae71534a8cb4f1fa4c5c6))
* example checkout page GPMOB-138 ([b9c7018](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/b9c701814a04c272d960af4cf5e0a896f9731507))
* keep the gateway's error body on GopaySDKError GPMOB-158 ([386d0aa](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/386d0aa441b16e08b2adb5d633094af01561c80a))
* let a 3DS challenge hand off to a banking app GPMOB-149 ([109cdef](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/109cdef115a0d1335da321765fcf3982f0f700ea))
* make ChargePaymentResponse.returnUrl optional GPMOB-149 ([eccabb9](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/eccabb9c3d477436b103db3a53f4b04f2fd693be))
* read gateway enum values the SDK does not know as unknown GPMOB-156 ([15b410b](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/15b410b07846ba10cf18548afc08c900316313af))
* rebuild the card form theme around the cc-v4 parameter set GPMOB-145 ([d095902](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/d09590207087421f210ee2059f2855f9f52addd2))
* render the typography and input text theme params GPMOB-145 ([4e0d975](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/4e0d9752fdea510726fd6fba190795281bd23d8f))
* report a closed payment window as PAYMENT_011 GPMOB-158 ([27640ee](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/27640eeca829c765d6a0cec7348210a6aee7b828))
* ship a privacy manifest with the SDK GPMOB-158 ([d0ad60f](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/d0ad60fb9a801f6a6d5b53ba78b597f2e259e53d))
* watch the charge for a 3DS action in the demo console GPMOB-149 ([8767d5c](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/8767d5ccb0f155540ff82e830dce571d5dae8d2f))


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

# [1.5.0](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/compare/1.4.0...1.5.0) (2026-07-28)


### Features

* fill browser data on charge GPMOB-123 ([5745f29](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/5745f29540dcd944ee8ef55b2989c84cf42fa65a))

# [1.4.0](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/compare/1.3.1...1.4.0) (2026-07-24)


### Bug Fixes

* sonarQube issues GPMOB-133 ([f1113ff](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/f1113ffce334b46418c61ec9ef4f567054b12e48))


### Features

* add charge payment endpoint with web transaction ([61f3d6b](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/61f3d6b22d67f7cacd91295752669e1e39c16160))
* add create payment API method GPMOB-117 ([a259af2](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/a259af27ca2674cb78d465249fb560830345c6dd))
* add example usage of create payment endpoint GPMOB-117 ([ec8d5dd](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/ec8d5ddcf06a4276684266f5a5ad87397e2abdb1))
* add payement charge status method GPMOB-121 ([552c445](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/552c44597969e660547e2ec8799cf4bf34d6957a))
* add Payment status method GPMOB-120 ([91f3950](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/91f39507789dc3cbbc8abc6c98cf90861cba2fdf))
* add QR payment info method GPMOB-122 ([5042e07](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/5042e07c7fdff1655ac3e445c414df35daeb7b23))
* added form locales and localization logic GPMOB-125 ([5d5d301](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/5d5d3014694fea08ca2192e51ae3453d71b34d28))
* added formatting textField in payment form GPMOB-136 ([0b13c40](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/0b13c40e8e2f654d2352c6773cbc2a8b43ebc4f3))
* charge with JWE payload GPMOB-134 ([fdfef38](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/fdfef38af7a815401805f487f658d55e30708e4e))

## [1.3.1](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/compare/1.3.0...1.3.1) (2026-06-02)


### Bug Fixes

* avoid exporting credentials and quote variable in release step GPOMA-2293 ([c6aefff](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/c6aefffd2d48733dfcf9b8af3cbb861b7a05f720))
# [2.0.0](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/compare/1.3.0...2.0.0) (2026-06-16)


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

# [1.3.0](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/compare/1.2.0...1.3.0) (2026-03-03)


### Features

* add cocopods config and readme docs GPMOB-116 ([3fca483](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/3fca483a85115b61af9c0b83744d855d8ae00024))

# [1.2.0](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/compare/1.1.0...1.2.0) (2026-03-03)


### Features

* add card tokenization network request GPMOB-65 ([213b6e6](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/213b6e6bc1c2c52f175d3b464d829bed815a9df6))
* add cardTokenization example app demo GPMOB-65 ([727b408](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/727b4085c7ca61c856e19fa23a566448b10e8eb1))
* add JWE utils for card tokenization GPMOB-66 ([361b272](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/361b272d5f21fc2458fcbbb875335d0480e5910f))
* add user-agent version on network request GPMOB-110 ([9b3fa90](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/9b3fa90f776b512b704d971fce5b2b101eaa2bf2))
* cardFormUI and internal data submitting GPMOB-68 ([bcc7877](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/bcc7877bb140edb4452ea32c5490eb5f541c1919))

# [1.1.0](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/compare/1.0.0...1.1.0) (2025-12-09)


### Features

* add auth service GPMOB-58 ([a7f4583](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/a7f458337db479305e4efd3a5f97e4845771a82b))
* add authentication response setter GPMOB-58 ([660bac2](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/660bac2c5f3d0bd39170218ba0905023663747ff))
* add environment configuration GPMOB-54 ([b853fc9](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/b853fc925ac4d16e5d9367f05b205a5e25434630))
* add get public key api request GPMOB-64 ([767fa22](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/767fa22e78cc80317e59b19f3fc9c7c67f9fb5fe))
* add getting started documentation GPMOB-54 ([ce7e3ab](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/ce7e3abc829e3388ab6f0e09fc9532d08a53448c))
* add jwt utils GPMOB-58 ([95eb713](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/95eb71306ca5ad048726b3bb83c36a32ae47b16c))
* add network client GPMOB-56 ([1ed4d51](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/1ed4d517f0ff0c498ee841aeb671b47614c21f48))
* add option for custom dev env setting GPMOB-54 ([a5cbe4c](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/a5cbe4cabb635d2d7a8559f7781540b44b91361f))

# 1.0.0 (2025-07-07)


### Features

* project init GPMOB-8 ([48670dd](https://bitbucket.org/gp-gopay/gp-gw-ios-sdk/commits/48670ddb0260ebaec70dc684a78562a276c3ac0c))
