//
//  CheckoutView.swift
//  example
//
//  A deliberately ordinary-looking e-shop checkout. Everything payment-related is real: the
//  amounts come from `DemoCart`, the payment is created through `MerchantBackendSimulator`, and
//  each method drives the actual SDK call (see `CheckoutViewModel`).
//

import SwiftUI
import GopaySDK

struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = CheckoutViewModel()

    var body: some View {
        ZStack {
            CheckoutTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    orderSummary
                    methodPicker
                    trustFooter
                }
                .padding(.horizontal, CheckoutTheme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            // Without this the expanded card form pulls the initial scroll position down past
            // the order summary.
            .defaultScrollAnchor(.top)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { payBar }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { model.qrDetails != nil },
            set: { if !$0 { model.qrDetails = nil } }
        )) {
            if let details = model.qrDetails {
                BankTransferSheet(details: details, cart: model.cart)
                    .presentationDetents([.medium, .large])
            }
        }
        .fullScreenCover(item: $model.outcome) { outcome in
            CheckoutResultView(
                outcome: outcome,
                cart: model.cart,
                paymentId: model.paymentId,
                isRefreshing: model.isBusy,
                onRefresh: { Task { await model.refreshChargeState() } },
                onRetry: { model.resumeShopping() },
                onDone: {
                    model.resumeShopping()
                    Task {
                        await model.finish()
                        dismiss()
                    }
                }
            )
        }
        .animation(.easeInOut(duration: 0.22), value: model.selectedMethod)
        .animation(.easeInOut(duration: 0.22), value: model.busyLabel)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await model.finish()
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CheckoutTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(CheckoutTheme.surface, in: Circle())
                    .overlay(Circle().stroke(CheckoutTheme.hairline, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Checkout")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(CheckoutTheme.ink)
                Text("Northline Supply")
                    .font(.system(size: 12.5))
                    .foregroundStyle(CheckoutTheme.inkMuted)
            }

            Spacer()

            localeMenu
        }
        .padding(.horizontal, CheckoutTheme.gutter)
        .padding(.vertical, 10)
        .background(CheckoutTheme.canvas)
    }

    /// Demonstrates `GopayLocales` — the card form ships with 20 built-in languages, plus any
    /// custom locale registered at init time (`"xx"` in `exampleApp.swift`).
    private var localeMenu: some View {
        Menu {
            Picker("Language", selection: $model.locale) {
                Text("System default").tag(String?.none)
                ForEach(GopayLocales.availableCodes(), id: \.self) { code in
                    Text(code.uppercased()).tag(String?.some(code))
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                Text(model.locale?.uppercased() ?? "AUTO")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(CheckoutTheme.ink)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(CheckoutTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(CheckoutTheme.hairline, lineWidth: 1))
        }
    }

    // MARK: - Order summary

    private var orderSummary: some View {
        SurfaceCard {
            VStack(spacing: 14) {
                HStack {
                    Text("Your order")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CheckoutTheme.ink)
                    Spacer()
                    Text("\(model.cart.items.count) items")
                        .font(.system(size: 13))
                        .foregroundStyle(CheckoutTheme.inkMuted)
                }

                ForEach(model.cart.items) { item in
                    HStack(spacing: 12) {
                        Text(item.emoji)
                            .font(.system(size: 22))
                            .frame(width: 44, height: 44)
                            .background(CheckoutTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(CheckoutTheme.ink)
                            Text(item.quantity > 1 ? "\(item.variant) · ×\(item.quantity)" : item.variant)
                                .font(.system(size: 12.5))
                                .foregroundStyle(CheckoutTheme.inkMuted)
                        }

                        Spacer(minLength: 8)

                        Text(model.cart.formatted(item.lineTotal))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CheckoutTheme.ink)
                    }
                }

                Divider().overlay(CheckoutTheme.hairline)

                totalRow("Subtotal", model.cart.formatted(model.cart.subtotal), emphasized: false)
                totalRow("Shipping", model.cart.formatted(model.cart.shipping), emphasized: false)
                totalRow("Total", model.cart.formatted(model.cart.total), emphasized: true)
            }
        }
    }

    private func totalRow(_ label: String, _ value: String, emphasized: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: emphasized ? 16 : 14, weight: emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? CheckoutTheme.ink : CheckoutTheme.inkMuted)
            Spacer()
            Text(value)
                .font(.system(size: emphasized ? 19 : 14, weight: emphasized ? .bold : .medium))
                .foregroundStyle(CheckoutTheme.ink)
        }
    }

    // MARK: - Payment methods

    private var methodPicker: some View {
        SurfaceCard(padding: CheckoutTheme.gutter) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Payment method")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CheckoutTheme.ink)
                    .padding(.bottom, 4)

                ForEach(Array(model.availableMethods.enumerated()), id: \.element.id) { index, method in
                    if index > 0 {
                        Divider().overlay(CheckoutTheme.hairline)
                    }
                    PaymentMethodRow(
                        method: method,
                        isSelected: model.selectedMethod == method,
                        onSelect: { model.selectedMethod = method }
                    ) {
                        expandedContent(for: method)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func expandedContent(for method: CheckoutViewModel.Method) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if method == .card {
                // The SDK's own component, themed to match the shop. Card data never leaves it —
                // `submitCardForm()` hands back a JWE, not a PAN.
                GopayCardForm(
                    theme: CheckoutTheme.cardForm,
                    locale: model.locale,
                    validation: .onSubmit(attempted: $model.didAttemptSubmit),
                    isValid: $model.isCardFormValid
                )
                .id(model.locale ?? "system")
            }
            SDKNote(text: method.sdkNote)
        }
    }

    // MARK: - Pay bar

    private var payBar: some View {
        VStack(spacing: 10) {
            if let banner = model.banner {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                    Text(banner).font(.system(size: 13))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(CheckoutTheme.warning)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CheckoutTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button {
                Task { await model.pay() }
            } label: {
                HStack(spacing: 8) {
                    if let busy = model.busyLabel {
                        ProgressView().tint(CheckoutTheme.onAccent)
                        Text(busy)
                    } else {
                        if model.selectedMethod == .applePay {
                            Image(systemName: "applelogo")
                        }
                        Text(model.payButtonTitle)
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle(
                background: model.selectedMethod == .applePay ? CheckoutTheme.ink : CheckoutTheme.accent,
                foreground: model.selectedMethod == .applePay ? CheckoutTheme.canvas : CheckoutTheme.onAccent
            ))
            .disabled(model.isBusy)
        }
        .padding(.horizontal, CheckoutTheme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private var trustFooter: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 11))
                Text("Secured by GoPay · card details never touch this app")
            }
            Text("GopaySDK \(GopaySDK.version)")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(CheckoutTheme.inkMuted)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

#Preview {
    NavigationStack { CheckoutView() }
}
