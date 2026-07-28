//
//  PaymentMethodRow.swift
//  example
//
//  One selectable payment method. Selecting a row expands it to reveal the method's own content —
//  for cards that's the SDK's `GopayCardForm`, for everything else a short note about which SDK
//  call the row runs.
//

import SwiftUI

struct PaymentMethodRow<Expanded: View>: View {
    let method: CheckoutViewModel.Method
    let isSelected: Bool
    let onSelect: () -> Void
    @ViewBuilder var expanded: Expanded

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? CheckoutTheme.accent.opacity(0.14) : CheckoutTheme.surfaceSunken)
                        Image(systemName: method.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? CheckoutTheme.accent : CheckoutTheme.inkMuted)
                    }
                    .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(method.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CheckoutTheme.ink)
                        Text(method.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(CheckoutTheme.inkMuted)
                    }

                    Spacer(minLength: 8)

                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? CheckoutTheme.accent : CheckoutTheme.hairline, lineWidth: isSelected ? 6 : 1.5)
                            .frame(width: 22, height: 22)
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected {
                expanded
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// The short "what this row does in SDK terms" note shown under a selected non-card method.
struct SDKNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CheckoutTheme.inkMuted)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(CheckoutTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CheckoutTheme.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
