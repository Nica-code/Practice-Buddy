import SwiftUI
import StoreKit

struct ShopView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var proProduct: Product? {
        purchaseManager.availableProducts.first(where: { $0.id == PurchaseManager.proProductID })
    }

    var body: some View {
        List {
            Section("Pro") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Practice Buddy Pro")
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)

                    Text("One-time unlock with Pro tools for student and teacher workflows.")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)

                    Text(statusText)
                        .font(type.footnote)
                        .foregroundStyle(statusColor)
                }
                .padding(.vertical, 4)

                if purchaseManager.hasLifetimePro {
                    Text("You already own Practice Buddy Pro permanently.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                } else if purchaseManager.isProTrialActive {
                    if let end = purchaseManager.proTrialEndsAt {
                        Text(L10n.f("Trial active until %@.", end.formatted(date: .abbreviated, time: .shortened)))
                            .font(type.footnote)
                            .foregroundStyle(theme.accent)
                    } else {
                        Text("Trial active.")
                            .font(type.footnote)
                            .foregroundStyle(theme.accent)
                    }
                } else if purchaseManager.hasUsedProTrial {
                    Text("Free trial ended. Unlock Practice Buddy Pro to continue using Pro features.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    Button {
                        Task { await purchaseManager.startFreeTrial() }
                    } label: {
                        Text("Start 7-Day Free Trial")
                            .font(type.body)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(theme.accent)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task {
                        await purchaseManager.buy(productID: PurchaseManager.proProductID)
                    }
                } label: {
                    Text(primaryCTA)
                        .font(type.body)
                        .foregroundStyle(purchaseManager.isPro ? palette.textSecondary : .white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(purchaseManager.isPro ? palette.surfaceAlt : theme.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(primaryCTADisabled)

                Button("Restore Purchases") {
                    Task { await purchaseManager.restore() }
                }
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            }
            .listRowBackground(palette.surface)

            Section("Cosmetics") {
                Text("Coming soon")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            .listRowBackground(palette.surface)

            Section("Expressive") {
                Text("Coming soon")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            .listRowBackground(palette.surface)

            Section("Bundles") {
                Text("Coming soon")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .navigationTitle("Shop")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await purchaseManager.loadProducts()
            await purchaseManager.refreshEntitlements()
        }
    }

    private var primaryCTA: String {
        if purchaseManager.isPro {
            return String(localized: "Pro Unlocked")
        }
        if let proProduct {
            return L10n.f("Unlock Pro (%@, One-time)", proProduct.displayPrice)
        }
        return String(localized: "Unlock Pro (Unavailable)")
    }

    private var primaryCTADisabled: Bool {
        purchaseManager.isPro || proProduct == nil
    }

    private var statusText: String {
        if purchaseManager.hasLifetimePro {
            return String(localized: "Status: Unlocked (Purchased)")
        }
        if purchaseManager.isProTrialActive {
            return String(localized: "Status: Free Trial Active")
        }
        if purchaseManager.hasUsedProTrial {
            return String(localized: "Status: Free (Trial Ended)")
        }
        return String(localized: "Status: Free")
    }

    private var statusColor: Color {
        if purchaseManager.hasLifetimePro || purchaseManager.isProTrialActive {
            return theme.accent
        }
        return palette.textSecondary
    }
}
