# Gopay iOS SDK — Example App

A self-contained demo of the whole Payments 4.0 flow: it fakes the merchant backend in-app, starts
a payment session, and exercises every `PaymentSession` operation plus the card form.

## Prerequisites

- Xcode 13.2+ and an iOS 13+ simulator (the project's own deployment target is higher — Xcode will
  tell you if your simulator is too old).
- **GoPay VPN.** `DemoConfig.baseURL` points at `gw.alpha8.dev.gopay.com`, which resolves to a
  private `10.26.x.x` address. Without the VPN every "server" button fails — after up to ~60 s,
  since `URLSession`'s default request timeout applies and nothing overrides it.
- Merchant credentials for the dev environment (below).

## Configuration

All demo values live in `DemoConfig` in
[`exampleApp.swift`](example/exampleApp.swift): `baseURL`, `clientId`, `shareableKey`,
`clientSecret` and `goid`. `shareableKey` and `clientSecret` ship as placeholders, so fill them in
before running — `goid` is required too, since the simulated backend posts to
`/eshops/{goid}/payments`.

The dev credentials rotate whenever the alpha8 environment is reset. When that has happened every
call fails with `401 UNAUTHORIZED — Invalid client_id or client_secret`, which looks like a code
bug but isn't; check with a token request before debugging anything else:

```bash
curl -s -X POST "https://gw.alpha8.dev.gopay.com/gp-gw/api/4.0/oauth2/token" \
  -u "<client_id>:<client_secret>" \
  -d "grant_type=client_credentials&scope=payment:write payment:read card:write card:read"
```

`clientSecret` is a **merchant** secret. It exists here only so `MerchantBackendSimulator` can
stand in for your server — never ship it in a real app.

## Running

```bash
cd example
open example.xcodeproj
```

Pick the `example` scheme and Run (⌘R). There is no checked-in `.xcscheme`; Xcode autocreates one
for the single `example` target. You may also need to set your own signing team.

## The screen

Four sections, top to bottom. Sections 3 and 4 only appear once a session is live.

1. **Merchant backend (simulated)** — *Create payment on "server"* acquires a merchant token and
   creates a payment, filling in `payment_id` and `payment_secret`.
2. **Payment session** — *Start session* exchanges that pair for a payment-scoped JWT.
   *Close session* wipes the secret and token.
3. **Operations** — *Get status*, *Get Apple Pay info*, *Charge with Apple Pay*,
   *Get test card token (server)*, *Charge a payment*, *Get charge state*,
   *Handle 3DS verification*, *Get QR payment info*.
4. **Card form → JWE** — a locale picker, `GopayCardForm`, *Encrypt card → JWE*, and
   *Charge with encrypted card (JWE)*.

Every result — or a `GopaySDKError` with its code — is logged into the **Response** box at the
bottom.

Two operations need setup the demo doesn't ship with. Apple Pay needs the Apple Pay capability and
a Merchant ID entitlement added in Xcode, and the merchant must have Apple Pay in-app enabled on
the gateway; without that, *Get Apple Pay info* returns `NETWORK_002` / HTTP 403. Completing a real
Apple Pay authorization also needs a physical device with a test card in Wallet.

## Code references

- App entry and demo constants: [`exampleApp.swift`](example/exampleApp.swift)
- The whole UI and flow: [`ContentView.swift`](example/ContentView.swift)
- Simulated backend (token, create payment, card tokenization):
  [`MerchantBackendSimulator.swift`](example/MerchantBackendSimulator.swift)

For SDK API details see the top-level [README.md](../README.md).
