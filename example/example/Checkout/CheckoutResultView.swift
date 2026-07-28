//
//  CheckoutResultView.swift
//  example
//
//  Terminal screen of the checkout: succeeded, failed, or still pending. The pending case is real —
//  a charge can sit in PROCESSING after 3DS, so the screen offers `getChargeState()` on demand.
//

import SwiftUI
import GopaySDK

struct CheckoutResultView: View {
    let outcome: CheckoutViewModel.Outcome
    let cart: DemoCart
    let paymentId: String?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onRetry: () -> Void
    let onDone: () -> Void

    @State private var showsDeveloperDetails = false

    var body: some View {
        ZStack {
            CheckoutTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    badge

                    VStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(CheckoutTheme.ink)
                        Text(subtitle)
                            .font(.system(size: 15))
                            .foregroundStyle(CheckoutTheme.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 8)

                    receipt

                    if let response = outcome.response {
                        developerDetails(response)
                    }

                    actions
                }
                .padding(CheckoutTheme.gutter)
                .padding(.top, 40)
            }
        }
    }

    // MARK: - Pieces

    private var badge: some View {
        ZStack {
            Circle().fill(tint.opacity(0.14)).frame(width: 92, height: 92)
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private var receipt: some View {
        SurfaceCard {
            VStack(spacing: 0) {
                row("Amount", cart.formatted(cart.total))
                if let details = outcome.response?.paymentInstrument?.details {
                    if let pan = details.maskedPan {
                        row("Card", pan)
                    }
                    if let scheme = details.scheme {
                        row("Scheme", scheme.rawValue.capitalized)
                    }
                    row("Input", friendlyInputType(details.inputType))
                }
                if let paymentId {
                    row("Payment", paymentId)
                }
                row("Charge state", outcome.state.rawValue)
                if let message = outcome.message, !message.isEmpty {
                    row("Reason", message, valueColor: CheckoutTheme.danger)
                }
            }
        }
    }

    private func developerDetails(_ response: ChargePaymentResponse) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showsDeveloperDetails.toggle() }
                } label: {
                    HStack {
                        Label("Developer details", systemImage: "curlybraces")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(CheckoutTheme.ink)
                        Spacer()
                        Image(systemName: showsDeveloperDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CheckoutTheme.inkMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsDeveloperDetails {
                    Text(JSONPreview.string(response))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(CheckoutTheme.inkMuted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if isPending {
                Button {
                    onRefresh()
                } label: {
                    HStack(spacing: 8) {
                        if isRefreshing { ProgressView().tint(CheckoutTheme.onAccent) }
                        Text(isRefreshing ? "Refreshing…" : "Refresh status")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isRefreshing)
            }

            if outcome.isFailure {
                Button("Try another method", action: onRetry)
                    .buttonStyle(PrimaryButtonStyle())
            }

            Button(outcome.isSuccess ? "Back to shop" : "Cancel order", action: onDone)
                .buttonStyle(outcome.isSuccess ? AnyButtonStyleBox(PrimaryButtonStyle()) : AnyButtonStyleBox(SecondaryButtonStyle()))
        }
        .padding(.top, 4)
    }

    private func row(_ label: String, _ value: String, valueColor: Color = CheckoutTheme.ink) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(CheckoutTheme.inkMuted)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
    }

    // MARK: - Presentation

    private var isPending: Bool {
        switch outcome.state {
        case .requested, .processing, .actionRequired: true
        case .succeeded, .failed: false
        }
    }

    private var tint: Color {
        if outcome.isSuccess { return CheckoutTheme.accent }
        if outcome.isFailure { return CheckoutTheme.danger }
        return CheckoutTheme.warning
    }

    private var symbol: String {
        if outcome.isSuccess { return "checkmark.circle.fill" }
        if outcome.isFailure { return "exclamationmark.triangle.fill" }
        return "clock.fill"
    }

    private var title: String {
        if outcome.isSuccess { return "Payment complete" }
        if outcome.isFailure { return "Payment failed" }
        return "Payment pending"
    }

    private var subtitle: String {
        if outcome.isSuccess { return "Thanks! We've emailed your receipt and the order is on its way." }
        if outcome.isFailure { return outcome.message ?? "The bank declined the charge. No money was taken." }
        return "We polled the gateway and the bank hasn't confirmed yet. A real shop would also get the final state on its notification URL."
    }

    private func friendlyInputType(_ raw: String) -> String {
        switch raw {
        case "ENCRYPTED_CARD": "Card entered in app"
        case "CARD_TOKEN": "Saved card"
        case "APPLE_PAY": "Apple Pay"
        default: raw
        }
    }
}

/// Lets the "Back to shop" / "Cancel order" button swap between two styles.
private struct AnyButtonStyleBox: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
