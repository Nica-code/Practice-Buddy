import SwiftUI
import StoreKit

struct ShopView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var adFreeProduct: Product? {
        purchaseManager.availableProducts.first(where: { PurchaseManager.adFreeSubscriptionProductIDs.contains($0.id) })
    }
    private var introOffer: Product.SubscriptionOffer? {
        adFreeProduct?.subscription?.introductoryOffer
    }

    var body: some View {
        List {
            Section("Ad-Free") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PractiQuest Ad-Free")
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)

                    Text("All features are free. This monthly subscription removes ads.")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)

                    Text(statusText)
                        .font(type.footnote)
                        .foregroundStyle(statusColor)
                }
                .padding(.vertical, 4)

                if let intro = introOffer, intro.paymentMode == .freeTrial {
                    Text(trialSummaryText(for: intro))
                        .font(type.footnote)
                        .foregroundStyle(theme.accent)
                }

                Button {
                    Task {
                        await purchaseManager.buy(productID: PurchaseManager.adFreeMonthlyProductID)
                    }
                } label: {
                    Text(primaryCTA)
                        .font(type.body)
                        .foregroundStyle(purchaseManager.hasAdFree ? palette.textSecondary : .white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(purchaseManager.hasAdFree ? palette.surfaceAlt : theme.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(primaryCTADisabled)

                if trialEligible {
                    Button("Start 7-Day Trial") {
                        Task {
                            _ = await purchaseManager.startServerTrialIfEligible()
                        }
                    }
                    .font(type.body)
                    .foregroundStyle(theme.accent)
                }

                Button("Restore Purchases") {
                    Task { await purchaseManager.restore() }
                }
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            }
            .listRowBackground(palette.surface)

            Section("Cosmetics") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Coming soon")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)

                    NavigationLink {
                        InventoryView()
                    } label: {
                        Label("Open Inventory", systemImage: "shippingbox.fill")
                            .font(type.body)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(palette.surface)

            Section("Skins") {
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
        if purchaseManager.hasAdFree {
            return String(localized: "Ad-Free Active")
        }
        if let adFreeProduct {
            if let intro = introOffer, intro.paymentMode == .freeTrial {
                return trialCTA(for: intro)
            }
            return L10n.f("Subscribe (%@ / month)", adFreeProduct.displayPrice)
        }
        return String(localized: "Subscribe (Unavailable)")
    }

    private var primaryCTADisabled: Bool {
        purchaseManager.hasAdFree || adFreeProduct == nil
    }

    private var statusText: String {
        if isServerTrialActive {
            return "Status: Trial Active (\(trialDaysRemainingText) left)"
        }
        if purchaseManager.hasAdFree {
            return String(localized: "Status: Ad-Free Active")
        }
        return String(localized: "Status: Ads Enabled")
    }

    private var statusColor: Color {
        if isServerTrialActive {
            return theme.accent
        }
        if purchaseManager.hasAdFree {
            return theme.accent
        }
        return palette.textSecondary
    }

    private var trialEligible: Bool {
        !purchaseManager.hasAdFree && !purchaseManager.trialUsed
    }

    private var isServerTrialActive: Bool {
        guard let trialEndsAt = purchaseManager.trialEndsAt else { return false }
        return trialEndsAt > Date() && !purchaseManager.hasActiveSubscription
    }

    private var trialDaysRemainingText: String {
        guard let trialEndsAt = purchaseManager.trialEndsAt else { return "0d" }
        let seconds = max(0, Int(trialEndsAt.timeIntervalSinceNow))
        let days = max(1, Int(ceil(Double(seconds) / 86_400.0)))
        return "\(days)d"
    }

    private func trialCTA(for offer: Product.SubscriptionOffer) -> String {
        let duration = offerDurationText(offer.period)
        return "Start \(duration) Free Trial"
    }

    private func trialSummaryText(for offer: Product.SubscriptionOffer) -> String {
        let duration = offerDurationText(offer.period)
        return "\(duration) free trial available for eligible users."
    }

    private func offerDurationText(_ period: Product.SubscriptionPeriod) -> String {
        let value = period.value
        switch period.unit {
        case .day:
            return value == 1 ? "1-day" : "\(value)-day"
        case .week:
            return value == 1 ? "1-week" : "\(value)-week"
        case .month:
            return value == 1 ? "1-month" : "\(value)-month"
        case .year:
            return value == 1 ? "1-year" : "\(value)-year"
        @unknown default:
            return "\(value)-day"
        }
    }
}
