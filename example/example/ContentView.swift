//
//  ContentView.swift
//  example
//
//  Created by Jiří Hauser on 24.03.2025.
//
//  Demonstrates the per-payment session flow:
//   1. (server-side, simulated here) create a payment -> payment_id + payment_secret
//   2. startPaymentSession(paymentId:paymentSecret:)
//   3. session.getStatus / chargeWithApplePay / handle3dsVerification / getChargeState / getQrPaymentInfo
//   4. card form -> JWE (which your server tokenizes)
//   5. session.close()
//

import SwiftUI
import UIKit
import GopaySDK

struct ContentView: View {
    @State private var paymentId = ""
    @State private var paymentSecret = ""
    @State private var session: PaymentSession?
    @State private var cardToken: String = ""
    @State private var jwe: String = ""
    @State private var pending3dsURL: URL?
    @State private var isFormValid: Bool?
    // Flipped true when the user taps submit, revealing the form's inline validation errors.
    @State private var didAttemptSubmit = false
    // nil follows the SDK/device default locale (which falls back to Czech).
    @State private var selectedLocale: String?

    @State private var responseText = "Ready."
    @State private var busyLabel: String?

    private var isBusy: Bool { busyLabel != nil }

    var body: some View {
        // Presented inside `RootView`'s NavigationStack — no navigation container of its own.
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                merchantSection
                sessionSection
                if session != nil {
                    operationsSection
                    cardFormSection
                }
                responseSection
            }
            .padding()
        }
        .navigationTitle("Developer sandbox")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var merchantSection: some View {
        section("1. Merchant backend (simulated)") {
            Text("In production your server does this with merchant credentials and returns the pair below.")
                .font(.footnote).foregroundColor(.secondary)
            button("Create payment on \"server\"", system: "server.rack") {
                let created = try await MerchantBackendSimulator.createPayment(amount: 1000, currency: "CZK")
                await MainActor.run {
                    paymentId = created.paymentId
                    paymentSecret = created.paymentSecret
                }
                log("// merchant backend created a payment\npayment_id: \(created.paymentId)\npayment_secret: \(created.paymentSecret)")
            }
            labeledField("payment_id", text: $paymentId)
            labeledField("payment_secret", text: $paymentSecret)
        }
    }

    private var sessionSection: some View {
        section("2. Payment session") {
            button(session == nil ? "Start session" : "Restart session", system: "key.fill") {
                if let existing = session { await existing.close() }
                let started = try await GopaySDK.shared.startPaymentSession(
                    paymentId: paymentId,
                    paymentSecret: paymentSecret
                )
                await MainActor.run { session = started }
                log("// startPaymentSession() — eager auth OK\npayment_id: \(paymentId)\nscope: \(PaymentSession.defaultScope)")
            }
            .disabled(paymentId.isEmpty || paymentSecret.isEmpty)

            if session != nil {
                button("Close session", system: "xmark.circle", role: .destructive) {
                    if let session = session { await session.close() }
                    await MainActor.run { session = nil }
                    log("Session closed.")
                }
            }
        }
    }

    private var operationsSection: some View {
        section("3. Operations") {
            button("Get status", system: "doc.text.magnifyingglass") {
                logResponse("getStatus() -> PaymentDetails", try await requireSession().getStatus())
            }
            button("Get Apple Pay info", system: "info.circle") {
                logResponse("getApplePayInfo() -> GopayApplePayAppInfoResponse",
                            try await requireSession().getApplePayInfo())
            }
            button("Charge with Apple Pay", system: "applelogo") {
                try await chargeWithApplePay()
            }
            button("Get test card token (server)", system: "wand.and.stars") {
                try await fetchTestCardToken()
            }
            labeledField("card_token (from your server's tokenization)", text: $cardToken)
            button("Charge a payment", system: "creditcard.fill") {
                try await chargeWithCardToken()
            }
            .disabled(cardToken.isEmpty)
            button("Get charge state", system: "arrow.clockwise") {
                let state = try await requireSession().getChargeState()
                logResponse("getChargeState() -> ChargePaymentResponse", state)
                if let redirect = state.action?.redirectUrl, let url = URL(string: redirect) {
                    await MainActor.run { pending3dsURL = url }
                }
            }
            button("Handle 3DS verification", system: "lock.shield") {
                guard let url = pending3dsURL else { return }
                await MainActor.run { pending3dsURL = nil }
                try await handle3ds(url)
            }
            .disabled(pending3dsURL == nil)
            button("Get QR payment info", system: "qrcode") {
                logResponse("getQrPaymentInfo(format: .png) -> QrPaymentDetails",
                            try await requireSession().getQrPaymentInfo(format: .png))
            }
        }
    }

    private var cardFormSection: some View {
        section("4. Card form → JWE") {
            // Locale selector — switch the language of the form labels/placeholders live.
            Picker("Locale", selection: $selectedLocale) {
                Text("System default").tag(String?.none)
                ForEach(GopayLocales.availableCodes(), id: \.self) { code in
                    Text(code).tag(String?.some(code))
                }
            }
            .pickerStyle(.menu)

            // Re-create the form when the locale changes so it picks up the new strings.
            // `.onSubmit` shows the localized error messages only after the user taps submit.
            GopayCardForm(locale: selectedLocale, validation: .onSubmit(attempted: $didAttemptSubmit), isValid: $isFormValid)
                .id(selectedLocale ?? "system")
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

            button("Encrypt card → JWE", system: "lock.fill") {
                // Reveal inline validation errors; only encrypt once the form is valid.
                await MainActor.run { didAttemptSubmit = true }
                guard isFormValid != false else { return }
                let encrypted = try await GopaySDK.shared.submitCardForm()
                await MainActor.run { jwe = encrypted }
                log("// submitCardForm() -> JWE (filled into the field below)\n\(encrypted)")
            }

            labeledField("JWE (from on-device card encryption)", text: $jwe)
            button("Charge with encrypted card (JWE)", system: "lock.circle.fill") {
                try await chargeWithEncryptedCard()
            }
            .disabled(jwe.isEmpty)
        }
    }

    private var responseSection: some View {
        section("Response") {
            if let busyLabel = busyLabel {
                HStack { ProgressView(); Text(busyLabel) }
            }
            Text(responseText)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
        }
    } 

    // MARK: - Flows

    /// Test-only convenience: encrypts a static test card with the SDK, tokenizes the JWE on the
    /// simulated "server", then fills the card_token field and copies the token to the clipboard.
    /// In production the SDK only produces the JWE; tokenization happens on your real server.
    private func fetchTestCardToken() async throws {
        let card = GopayCardData(cardPan: "4444444444444448", expMonth: "12", expYear: "28", cvv: "123")
        let jwe = try await GopaySDK.shared.encryptCardData(card)
        let token = try await MerchantBackendSimulator.tokenizeCard(jwe: jwe)
        await MainActor.run {
            cardToken = token
            UIPasteboard.general.string = token
        }
        log("// test card 4444…4448 (12/28) tokenized on \"server\"\ncard_token: \(token)\n(filled into the field above + copied to clipboard)")
    }

    private func chargeWithCardToken() async throws {
        let session = try requireSession()
        let request = ChargePaymentRequest.cardToken(
            cardToken,
            browserData: await BrowserData.deviceDefault(),
            challengePreference: .auto
        )
        let charge = try await session.charge(request)
        logResponse("charge(.cardToken) -> ChargePaymentResponse", charge)
        if let redirect = charge.action?.redirectUrl, let url = URL(string: redirect) {
            await MainActor.run { pending3dsURL = url }
            log("3DS required — tap \"Handle 3DS verification\" to continue.")
        }
    }

    /// Charges the JWE from the field directly via the `ENCRYPTED_CARD` input — no
    /// `POST /cards/tokens` round-trip. The field is autofilled by "Encrypt card → JWE" above.
    private func chargeWithEncryptedCard() async throws {
        let session = try requireSession()
        let request = ChargePaymentRequest.encryptedCard(
            jwe.trimmingCharacters(in: .whitespacesAndNewlines),
            browserData: await BrowserData.deviceDefault(),
            challengePreference: .auto
        )
        let charge = try await session.charge(request)
        logResponse("charge(.encryptedCard) -> ChargePaymentResponse", charge)
        if let redirect = charge.action?.redirectUrl, let url = URL(string: redirect) {
            await MainActor.run { pending3dsURL = url }
            log("3DS required — tap \"Handle 3DS verification\" to continue.")
        }
    }

    private func chargeWithApplePay() async throws {
        let session = try requireSession()
        guard GopaySDK.canUseApplePay() else {
            log("Apple Pay is not available on this device.")
            return
        }
        let charge = try await session.chargeWithApplePay()
        logResponse("chargeWithApplePay() -> ChargePaymentResponse", charge)
        if let redirect = charge.action?.redirectUrl, let url = URL(string: redirect) {
            await MainActor.run { pending3dsURL = url }
            log("3DS required — tap \"Handle 3DS verification\" to continue.")
        }
    }

    private func handle3ds(_ url: URL) async throws {
        let session = try requireSession()
        try await session.handle3dsVerification(redirectURL: url)
        await MainActor.run { pending3dsURL = nil }
        logResponse("getChargeState() after 3DS -> ChargePaymentResponse", try await session.getChargeState())
    }

    private func requireSession() throws -> PaymentSession {
        guard let session = session else {
            throw NSError(domain: "example", code: 0, userInfo: [NSLocalizedDescriptionKey: "Start a session first"])
        }
        return session
    }

    // MARK: - UI helpers

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
    }

    private func button(
        _ title: String,
        system: String,
        role: ButtonRole? = nil,
        _ action: @escaping () async throws -> Void
    ) -> some View {
        Button(role: role) {
            Task { await run(title, action) }
        } label: {
            Label(title, systemImage: system).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isBusy)
    }

    @MainActor
    private func run(_ label: String, _ work: @escaping () async throws -> Void) async {
        responseText = ""
        busyLabel = label
        defer { busyLabel = nil }
        do {
            try await work()
        } catch is CancellationError {
            log("Cancelled by user.")
        } catch let error as GopaySDKError {
            log("Error [\(error.code.rawValue)]: \(error.message)")
        } catch {
            log("Error: \(error.localizedDescription)")
        }
    }

    /// Appends a labeled, pretty-printed JSON dump of an SDK response so an integrating developer
    /// can see the full shape the method returns.
    @MainActor
    private func logResponse<T: Encodable>(_ label: String, _ value: T) {
        log("// \(label)\n" + JSONPreview.string(value))
    }

    @MainActor
    private func log(_ message: String) {
        responseText += responseText.isEmpty ? message : "\n\n\(message)"
    }
}

#Preview {
    NavigationStack { ContentView() }
}
