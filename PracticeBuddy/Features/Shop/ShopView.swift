import SwiftUI
import StoreKit

struct ShopView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var journey: JourneyProgressManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var proProduct: Product? {
        purchaseManager.availableProducts.first(where: { PurchaseManager.proSubscriptionProductIDs.contains($0.id) })
    }
    private var introOffer: Product.SubscriptionOffer? {
        proProduct?.subscription?.introductoryOffer
    }

    var body: some View {
        List {
            Section("Pro") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Practice Buddy Pro")
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)

                    Text("Auto-renewing monthly subscription with Pro tools for student and teacher workflows.")
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
                        await purchaseManager.buy(productID: PurchaseManager.proMonthlyProductID)
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
                    cosmeticStatusRow(
                        title: "Duel Intro Card",
                        equippedID: journey.equippedRewardID(for: .duelIntroCard),
                        equippedName: "Spotlight"
                    )
                    cosmeticStatusRow(
                        title: "Duel Finisher FX",
                        equippedID: journey.equippedRewardID(for: .duelFinisherFX),
                        equippedName: "Resonance"
                    )
                    cosmeticStatusRow(
                        title: "Session Card Skin",
                        equippedID: journey.equippedRewardID(for: .sessionCardSkin),
                        equippedName: "Aurora"
                    )

                    Text("Unlock and equip cosmetics from Play > Rewards.")
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
            return String(localized: "Pro Active")
        }
        if let proProduct {
            if let intro = introOffer, intro.paymentMode == .freeTrial {
                return trialCTA(for: intro)
            }
            return L10n.f("Subscribe (%@ / month)", proProduct.displayPrice)
        }
        return String(localized: "Subscribe (Unavailable)")
    }

    private var primaryCTADisabled: Bool {
        purchaseManager.isPro || proProduct == nil
    }

    private var statusText: String {
        if isServerTrialActive {
            return "Status: Trial Active (\(trialDaysRemainingText) left)"
        }
        if purchaseManager.isPro {
            return String(localized: "Status: Active")
        }
        return String(localized: "Status: Free")
    }

    private var statusColor: Color {
        if isServerTrialActive {
            return theme.accent
        }
        if purchaseManager.isPro {
            return theme.accent
        }
        return palette.textSecondary
    }

    private var trialEligible: Bool {
        !purchaseManager.isPro && !purchaseManager.trialUsed
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

    @ViewBuilder
    private func cosmeticStatusRow(title: String, equippedID: String?, equippedName: String) -> some View {
        HStack {
            Text(title)
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            if equippedID == nil {
                Text("Not equipped")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Text("Equipped: \(equippedName)")
                    .font(type.footnote)
                    .foregroundStyle(theme.accent)
            }
        }
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
