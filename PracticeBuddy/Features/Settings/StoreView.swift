import SwiftUI
import StoreKit

struct StoreView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pb.tab.selection") private var selectedTab: Int = 4

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
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PractiQuest Pro")
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)

                    Text("Auto-renewing monthly subscription with account-aware extras.")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)

                    Text(statusText)
                        .font(type.footnote)
                        .foregroundStyle(statusColor)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(palette.surface)

            if let intro = introOffer, intro.paymentMode == .freeTrial {
                Section("Free Trial") {
                    Text(trialSummaryText(for: intro))
                        .font(type.footnote)
                        .foregroundStyle(theme.accent)
                }
                .listRowBackground(palette.surface)
            }

            Section("Included For Everyone") {
                featureRow("Advanced analytics and trends")
                featureRow("Practice templates and session builder")
                featureRow("PDF/CSV export")
                featureRow("Enhanced metronome and tuner modes")
            }
            .listRowBackground(palette.surface)

            Section("Teacher Tools (Pro features)") {
                if purchaseManager.isPro {
                    Button {
                        selectedTab = 0
                    } label: {
                        Label("Studio Manager", systemImage: "person.3")
                            .font(type.body)
                    }
                } else {
                    Text("Unlock Pro to open Studio Manager.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                featureRow("Studio roster and invites")
                featureRow("Assignments and submissions")
                featureRow("Teacher dashboard and feedback workflow")
            }
            .listRowBackground(palette.surface)

            Section("Student Tools (Pro features)") {
                if purchaseManager.isPro {
                    NavigationLink {
                        PBLazyView(StudioManagerView(entryMode: .student))
                    } label: {
                        Label("Join Studio", systemImage: "person.3")
                            .font(type.body)
                    }
                } else {
                    Text("Unlock Pro to join a studio.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                featureRow("Smart Practice Plan Generator")
                featureRow("Assignment checklist")
                featureRow("Smart reminder path")
                featureRow("Weekly report to teacher")
            }
            .listRowBackground(palette.surface)

            Section {
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

                if let status = purchaseManager.syncStatus {
                    Text(status)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await purchaseManager.loadProducts()
            await purchaseManager.refreshEntitlements()
        }
    }

    @ViewBuilder
    private func featureRow(_ title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.accent)
            Text(LocalizedStringKey(title))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
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
