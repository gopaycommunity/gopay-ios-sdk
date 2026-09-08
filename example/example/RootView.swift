//
//  RootView.swift
//  example
//
//  Entry point of the demo app: pick which face of the SDK you want to see.
//
//   • Demo checkout   — a realistic e-shop checkout exercising every payment method.
//   • Developer sandbox — the raw call-by-call console with JSON responses.
//

import SwiftUI
import GopaySDK

struct RootView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                CheckoutTheme.canvas.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GoPay SDK")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(CheckoutTheme.ink)
                        Text("iOS demo · version \(GopaySDK.version)")
                            .font(.system(size: 14))
                            .foregroundStyle(CheckoutTheme.inkMuted)
                    }
                    .padding(.bottom, 6)

                    NavigationLink {
                        CheckoutView()
                    } label: {
                        DestinationCard(
                            symbol: "bag.fill",
                            title: "Demo checkout",
                            subtitle: "A realistic e-shop checkout — card form, Apple Pay, saved card, bank transfer and 3DS, end to end.",
                            accent: CheckoutTheme.accent
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ContentView()
                    } label: {
                        DestinationCard(
                            symbol: "terminal.fill",
                            title: "Developer sandbox",
                            subtitle: "Call each SDK method on its own and inspect the raw JSON the gateway returns.",
                            accent: CheckoutTheme.ink
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(spacing: 8) {
                        EnvironmentBadge()
                        Text("Both surfaces talk to this gateway and share DemoConfig.")
                            .font(.system(size: 12))
                            .foregroundStyle(CheckoutTheme.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(CheckoutTheme.gutter)
                .padding(.top, 24)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Which gateway both demo surfaces are pointed at, and a tap target to switch it. Reads
/// `DemoConfig.shared` — the same object `select(_:)` updates — so it's never possible to demo
/// against one environment while the label claims another.
private struct EnvironmentBadge: View {
    private var environment: DemoEnvironment { DemoConfig.shared.environment }

    var body: some View {
        Menu {
            Picker("Environment", selection: Binding(
                get: { environment },
                set: { DemoConfig.shared.select($0) }
            )) {
                ForEach(DemoEnvironment.selectable(for: DemoConfig.baseURL)) { env in
                    Text(env.title).tag(env)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                if let host {
                    Text(host)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(CheckoutTheme.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CheckoutTheme.inkMuted)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
        }
    }

    private var name: String {
        switch environment {
        case .development: "DEVELOPMENT"
        case .sandbox: "SANDBOX"
        case .production: "PRODUCTION"
        }
    }

    /// Sandbox and production resolve to fixed hosts inside the SDK; `baseURL` is public
    /// specifically so this can read them without duplicating the URLs here.
    private var host: String? {
        URL(string: environment.gopayEnvironment.baseURL)?.host
    }

    private var tint: Color {
        switch environment {
        case .production: CheckoutTheme.danger
        case .sandbox: CheckoutTheme.warning
        case .development: CheckoutTheme.accent
        }
    }
}

private struct DestinationCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        SurfaceCard(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.14))
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CheckoutTheme.ink)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(CheckoutTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CheckoutTheme.inkMuted)
                    .padding(.top, 4)
            }
        }
    }
}

#Preview {
    RootView()
}
