//
//  BankTransferSheet.swift
//  example
//
//  Renders `QrPaymentDetails` from `session.getQrPaymentInfo(format:)` — the recipient account
//  plus a scannable code — for shoppers who'd rather pay from their banking app.
//

import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import GopaySDK

struct BankTransferSheet: View {
    let details: QrPaymentDetails
    let cart: DemoCart

    @Environment(\.dismiss) private var dismiss
    @State private var copied: String?
    @State private var isSharePresented = false

    private var local: QrLocalBankAccount? { details.recipient?.bankAccount?.local }
    private var international: QrInternationalBankAccount? { details.recipient?.bankAccount?.international }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text("Transfer this amount")
                            .font(.system(size: 13))
                            .foregroundStyle(CheckoutTheme.inkMuted)
                        Text(cart.formatted(details.amount))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(CheckoutTheme.ink)
                    }
                    .padding(.top, 8)

                    qrCode

                    // Every field on QrPaymentDetails is optional — render the card only when the
                    // gateway actually returned something, otherwise it collapses to a blank box.
                    if !detailRows.isEmpty {
                        SurfaceCard {
                            VStack(spacing: 0) {
                                ForEach(Array(detailRows.enumerated()), id: \.element.label) { index, row in
                                    if index > 0 {
                                        Divider().overlay(CheckoutTheme.hairline)
                                    }
                                    detailRow(row.label, row.value)
                                }
                            }
                        }
                    } else {
                        Text("The gateway returned no recipient account for this payment — scan the code above to pay.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(CheckoutTheme.inkMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }

                    Text("Your order completes once the transfer arrives. Nothing is charged from this screen.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(CheckoutTheme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Button("Done") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(CheckoutTheme.gutter)
            }
            .background(CheckoutTheme.canvas)
            .navigationTitle("Bank transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSharePresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $isSharePresented) {
                ShareSheet(activityItems: shareItems)
                    .presentationDetents([.medium, .large])
            }
            .overlay(alignment: .bottom) {
                if let copied {
                    Text("\(copied) copied")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CheckoutTheme.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(CheckoutTheme.accent, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: copied)
        }
    }

    // MARK: - QR

    @ViewBuilder
    private var qrCode: some View {
        if let image = qrImage {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: CheckoutTheme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CheckoutTheme.cardRadius, style: .continuous)
                        .stroke(CheckoutTheme.hairline, lineWidth: 1)
                )
        } else {
            SurfaceCard {
                Label(
                    "The gateway returned no QR payload for this payment — use the account details below.",
                    systemImage: "qrcode"
                )
                .font(.system(size: 13))
                .foregroundStyle(CheckoutTheme.inkMuted)
            }
        }
    }

    /// `format: .png` is expected to return a base64-encoded image; if the gateway hands back the
    /// raw payment string instead, we render it locally so the code is always scannable.
    private var qrImage: UIImage? {
        guard let payload = details.qrCode?.spayd ?? details.qrCode?.sepa ?? details.qrCode?.paybysquare else {
            return nil
        }
        if let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
           let image = UIImage(data: data) {
            return image
        }
        return Self.generateQR(from: payload)
    }

    private static func generateQR(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Details

    private var accountNumber: String? {
        guard let local, let number = local.accountNumber else { return nil }
        if let prefix = local.prefix, !prefix.isEmpty { return "\(prefix)-\(number)" }
        return number
    }

    /// Text + image handed to the share sheet. `UIActivityViewController` accepts heterogeneous
    /// items directly — no `ShareLink`-style item-type gymnastics needed.
    private var shareText: String {
        var lines = ["Bank transfer — \(cart.formatted(details.amount))"]
        lines.append(contentsOf: detailRows.map { "\($0.label): \($0.value)" })
        return lines.joined(separator: "\n")
    }

    private var shareItems: [Any] {
        var items: [Any] = [shareText]
        if let qrImage { items.append(qrImage) }
        return items
    }

    private var detailRows: [(label: String, value: String)] {
        [
            ("Recipient", details.recipient?.name),
            ("Account", accountNumber),
            ("Bank code", local?.bankCode),
            ("Variable symbol", local?.variableSymbol),
            ("IBAN", international?.iban),
            ("BIC", international?.bic),
            ("Reference", international?.reference)
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return (label, value)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(CheckoutTheme.inkMuted)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(CheckoutTheme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                UIPasteboard.general.string = value
                copied = label
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    if copied == label { copied = nil }
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundStyle(CheckoutTheme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 9)
    }
}
