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
    @State private var themeName = ThemeShowcase.shared.names.first ?? "Default"

    @State private var responseText = "Ready."
    @State private var busyLabel: String?

    /// How long the console watches a charge, for a 3DS action after the charge and for the
    /// terminal state after the verification, before giving up. The Android demo watches for the
    /// same twenty seconds.
    private static let pollInterval: Double = 1.0
    private static let pollAttempts = 20

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
                // `amount` is in minor units: 100 = 1 CZK.
                let created = try await MerchantBackendSimulator.createPayment(amount: 100, currency: "CZK")
                await MainActor.run {
                    paymentId = created.paymentId
                    paymentSecret = created.paymentSecret
                }
                log("// merchant backend created a payment (1 CZK)\npayment_id: \(created.paymentId)\npayment_secret: \(created.paymentSecret)")
            }
            labeledField("payment_id", text: $paymentId)
            labeledField("payment_secret", text: $paymentSecret)
        }
    }

    private var sessionSection: some View {
        section("2. Payment session") {
            button(session == nil ? "Start session" : "Restart session", system: "key.fill") {
                if let existing = session { await existing.close() }
                // Dropped before the call, not after it: a start that throws would otherwise
                // leave the previous payment's link armed, and the next tap would open the
                // verification of a long dead payment. Android drops it here too.
                await MainActor.run { pending3dsURL = nil }
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
                    await MainActor.run {
                        session = nil
                        pending3dsURL = nil
                    }
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
                // The link stays armed until the verification returns: `handle3ds` drops it on
                // success, and after a failed or dismissed verification it is kept, because a
                // refused presentation is exactly the error the SDK invites the caller to retry.
                guard let url = pending3dsURL else { return }
                try await handle3ds(url)
            }
            .disabled(pending3dsURL == nil)
            button("Get QR payment info", system: "qrcode") {
                logResponse("getQrPaymentInfo(format: .png) -> QrPaymentDetails",
                            try await requireSession().getQrPaymentInfo(format: .png))
            }
        }
    }

    /// Themes the form from a JSON document, the way a host would apply one its backend sent.
    /// The same documents ship with the Android demo, so a parameter can be compared side by side.
    private var themeMenu: some View {
        HStack {
            Text("Theme:")
            Picker("Theme", selection: $themeName) {
                ForEach(ThemeShowcase.shared.names, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer()
        }
    }

    /// Switches the language of the labels and placeholders live.
    private var localeMenu: some View {
        HStack {
            Text("Locale:")
            Picker("Locale", selection: $selectedLocale) {
                Text("System default").tag(String?.none)
                ForEach(GopayLocales.availableCodes(), id: \.self) { code in
                    Text(code).tag(String?.some(code))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Spacer()
        }
    }

    private var cardFormSection: some View {
        section("4. Card form → JWE") {
            // Theme first, then locale, in the same order as the Android demo.
            themeMenu
            localeMenu

            // Re-create the form when the locale changes so it picks up the new strings. The theme
            // is deliberately not part of the identity: it is a plain property the SDK reapplies,
            // so switching it restyles the form live and the typed card stays where it is.
            // `.onSubmit` shows the localized error messages only after the user taps submit.
            GopayCardForm(
                theme: ThemeShowcase.shared.theme(named: themeName),
                locale: selectedLocale,
                validation: .onSubmit(attempted: $didAttemptSubmit),
                isValid: $isFormValid
            )
                .id(selectedLocale ?? "system")
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

            button("Encrypt card → JWE", system: "lock.fill") {
                // Reveal inline validation errors; only encrypt once the form is valid.
                await MainActor.run { didAttemptSubmit = true }
                guard isFormValid != false else { return }
                let encrypted = try await GopaySDK.shared.submitCardForm()
                // The SDK empties the fields on success; the submit flag goes back with them,
                // otherwise the emptied fields light up with "This field is required".
                await MainActor.run {
                    jwe = encrypted
                    didAttemptSubmit = false
                }
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
        try await runCharge(labelled: "charge(.cardToken)") { session, browserData in
            try await session.charge(
                .cardToken(cardToken, browserData: browserData, challengePreference: .auto)
            )
        }
    }

    /// Charges the JWE from the field directly via the `ENCRYPTED_CARD` input — no
    /// `POST /cards/tokens` round-trip. The field is autofilled by "Encrypt card → JWE" above.
    private func chargeWithEncryptedCard() async throws {
        try await runCharge(labelled: "charge(.encryptedCard)") { session, browserData in
            try await session.charge(
                .encryptedCard(
                    jwe.trimmingCharacters(in: .whitespacesAndNewlines),
                    browserData: browserData,
                    challengePreference: .auto
                )
            )
        }
    }

    /// The shape every charge in this console shares, wallets included: drop the previous
    /// charge's 3DS link, log the browser data going out, send the request, then either arm the
    /// 3DS button or watch the charge for the action the gateway reports a few seconds late.
    ///
    /// The buttons differ only in the call they make, so everything around it lives here rather
    /// than in copies that drift. The Android demo keeps the same shape in `chargeAndReport`.
    private func runCharge(
        labelled label: String,
        _ charge: (PaymentSession, BrowserData) async throws -> ChargePaymentResponse
    ) async throws {
        let session = try requireSession()
        // A new charge invalidates the previous charge's 3DS link, whether or not this one
        // produces its own.
        await MainActor.run { pending3dsURL = nil }
        let response = try await charge(session, try await browserDataForCharge(session))
        logResponse("\(label) -> ChargePaymentResponse", response)
        let armed = await arm3dsButton(for: response)
        if !armed {
            try await watchForAction(session)
        }
    }

    /// Arms the 3DS button when the charge already carries a redirect. Returns whether it did.
    private func arm3dsButton(for charge: ChargePaymentResponse) async -> Bool {
        guard let redirect = charge.action?.redirectUrl, let url = URL(string: redirect) else {
            return false
        }
        await MainActor.run { pending3dsURL = url }
        log("3DS required — tap \"Handle 3DS verification\" to continue.")
        return true
    }

    private func chargeWithApplePay() async throws {
        guard GopaySDK.canUseApplePay() else {
            log("Apple Pay is not available on this device.")
            return
        }
        // Down the same path as the card charges: a wallet charge gets its action late just as
        // often, and the console has to show the browser data it sent either way.
        try await runCharge(labelled: "chargeWithApplePay()") { session, browserData in
            try await session.chargeWithApplePay(browserData: browserData)
        }
    }

    /// The device data the gateway forwards to the issuer, which weighs it when deciding between
    /// a frictionless approval and a 3DS challenge. Completed through the session the way the
    /// charge would complete it, logged, and then passed explicitly, so the console shows exactly
    /// what went out rather than a second guess at it. The charge sees every field set and does
    /// not ask the gateway a second time.
    private func browserDataForCharge(_ session: PaymentSession) async throws -> BrowserData {
        let data = try await session.completeBrowserData(await BrowserData.deviceDefault())
        log("""
            // browser_data sent with this charge
            user_agent: \(data.userAgent ?? "nil")
            language: \(data.language), timezone: \(data.timezone)
            screen: \(data.screenWidth)x\(data.screenHeight), color_depth: \(data.colorDepth)
            ip: \(Self.maskIp(data.ip))
            accept_header: \(data.acceptHeader ?? "nil")
            """)
        return data
    }

    /// The address as the run's protocol may carry it: the first two groups stay, so the log can
    /// be matched against the gateway's records, and the rest is replaced, so the log does not
    /// name the tester's network. `nil` reads as such, because a missing address is the finding.
    private static func maskIp(_ ip: String?) -> String {
        guard let ip = ip else { return "nil" }
        let separator: Character = ip.contains(":") ? ":" : "."
        let groups = ip.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard groups.count >= 3 else { return ip }
        let kept = groups.prefix(2).joined(separator: String(separator))
        let masked = groups.dropFirst(2).map { _ in "x" }.joined(separator: String(separator))
        return kept + String(separator) + masked
    }

    /// Watches a charge for a 3DS action when the charge response did not carry one.
    ///
    /// The gateway usually does answer the charge with the action, but not always: it can arrive
    /// a couple of seconds later and then only through `getChargeState()`. That is why the
    /// callers check the response first and fall back to this. Without it the tester has to race
    /// the gateway by hand, and the challenge window is only tens of seconds long.
    private func watchForAction(_ session: PaymentSession) async throws {
        let found = try await watch(session) { state, attempt in
            if let action = state.action {
                log("// poll \(attempt) -> \(state.state.rawValue)\n"
                    + "Action: \(action.actionType.rawValue) (\(action.state?.rawValue ?? "nil"))\n"
                    + "Redirect: \(action.redirectUrl ?? "N/A")")
                if let redirect = action.redirectUrl, let url = URL(string: redirect) {
                    pending3dsURL = url
                    log("3DS required — tap \"Handle 3DS verification\" now, the window is short.")
                }
                return true
            }
            if Self.isTerminal(state.state) {
                log("// poll \(attempt) -> \(state.state.rawValue), no action")
                return true
            }
            return false
        }
        if !found {
            log("No action after \(Self.pollAttempts) polls; charge still in flight.")
        }
    }

    private func handle3ds(_ url: URL) async throws {
        let session = try requireSession()
        try await session.handle3dsVerification(redirectURL: url)
        await MainActor.run { pending3dsURL = nil }
        let finalState = try await session.getChargeState()
        logResponse("getChargeState() after 3DS -> ChargePaymentResponse", finalState)
        if !Self.isTerminal(finalState.state) {
            try await watchForFinalState(session)
        }
    }

    /// Watches a charge for its terminal state after a 3DS verification returned.
    ///
    /// The gateway still answers PROCESSING right after the WebView comes back, and the final
    /// state can take a minute to appear, so a single read after the return reports an in-flight
    /// charge as the outcome. The watch runs with the same interval and cap as the action watch.
    private func watchForFinalState(_ session: PaymentSession) async throws {
        let settled = try await watch(session) { state, attempt in
            log("// poll \(attempt) -> \(state.state.rawValue)")
            return Self.isTerminal(state.state)
        }
        if !settled {
            log("No terminal state after \(Self.pollAttempts) polls; charge still in flight, tap \"Get charge state\" later.")
        }
    }

    /// The one polling loop behind both watches: reads the charge state once a second, up to
    /// ``pollAttempts`` times, and hands each answer to `isDone`, which logs what it saw and says
    /// whether the watch is over. Returns `false` when the cap ran out first.
    ///
    /// One failed poll must not end the watch. The action appears in a window only tens of
    /// seconds long, and giving up on the first transient error is how the tester loses it. A
    /// cancellation is the console itself going away, so that one is passed on.
    private func watch(
        _ session: PaymentSession,
        until isDone: @MainActor (ChargePaymentResponse, _ attempt: Int) -> Bool
    ) async throws -> Bool {
        for attempt in 1...Self.pollAttempts {
            try await Task.sleep(for: .seconds(Self.pollInterval))
            let state: ChargePaymentResponse
            do {
                state = try await session.getChargeState()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                log("// poll \(attempt) failed, still watching: \(error.localizedDescription)")
                continue
            }
            if isDone(state, attempt) { return true }
        }
        return false
    }

    private static func isTerminal(_ state: ChargeState) -> Bool {
        state == .succeeded || state == .failed
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
