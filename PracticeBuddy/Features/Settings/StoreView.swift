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
        purchaseManager.availableProducts.first(where: { $0.id == PurchaseManager.proProductID })
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Practice Buddy Pro")
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)

                    Text("One-time unlock with account-aware extras.")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)

                    Text(statusText)
                        .font(type.footnote)
                        .foregroundStyle(statusColor)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(palette.surface)

            Section("Free Trial") {
                if purchaseManager.hasLifetimePro {
                    Text("You already own Practice Buddy Pro permanently.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                } else if purchaseManager.isProTrialActive {
                    if let end = purchaseManager.proTrialEndsAt {
                        Text(L10n.f("Trial active until %@.", end.formatted(date: .abbreviated, time: .shortened)))
                            .font(type.footnote)
                            .foregroundStyle(theme.accent)
                        Text(trialCountdownText(until: end))
                            .font(type.footnote)
                            .foregroundStyle(theme.accent)
                    } else {
                        Text("Trial active.")
                            .font(type.footnote)
                            .foregroundStyle(theme.accent)
                    }
                    Text("After trial, Pro features lock again unless you unlock permanently.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
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
            }
            .listRowBackground(palette.surface)

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
                        PBLazyView(StudioManagerView())
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

    private func trialCountdownText(until end: Date) -> String {
        let now = Date()
        guard end > now else { return "Trial ended." }

        let secondsLeft = end.timeIntervalSince(now)
        let daysLeft = Int(ceil(secondsLeft / 86_400))
        if daysLeft >= 1 {
            return daysLeft == 1 ? "1 day left in trial." : "\(daysLeft) days left in trial."
        }

        let hoursLeft = max(1, Int(ceil(secondsLeft / 3_600)))
        return hoursLeft == 1 ? "1 hour left in trial." : "\(hoursLeft) hours left in trial."
    }
}
