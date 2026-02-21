import SwiftUI
import StoreKit

struct StoreView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var proProduct: Product? {
        purchaseManager.availableProducts.first(where: { $0.id == PurchaseManager.proProductID })
    }
    @State private var selectedAccountType: PBAccountType = .student
    @State private var pendingAccountType: PBAccountType?
    @State private var showAccountTypeConfirm = false

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

                    Text(purchaseManager.isPro ? "Status: Unlocked" : "Status: Free")
                        .font(type.footnote)
                        .foregroundStyle(purchaseManager.isPro ? theme.accent : palette.textSecondary)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(palette.surface)

            Section("Account Type") {
                Picker(
                    "Type",
                    selection: Binding(
                        get: { selectedAccountType },
                        set: { selectedAccountType = $0 }
                    )
                ) {
                    ForEach(PBAccountType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!purchaseManager.hasCompletedInitialRoleSelection || purchaseManager.accountTypeChangeUsed)

                Text(accountTypeHelpText)
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            .listRowBackground(palette.surface)

            Section("Included For Everyone (Pro Core)") {
                featureRow("Advanced analytics and trends")
                featureRow("Practice templates and session builder")
                featureRow("PDF/CSV export")
                featureRow("Enhanced metronome and tuner modes")
            }
            .listRowBackground(palette.surface)

            if purchaseManager.accountType == .teacher {
                Section("Teacher Tools") {
                    if purchaseManager.isPro {
                        NavigationLink {
                            PBLazyView(StudioManagerView())
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
            } else {
                Section("Student Tools") {
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
                    featureRow("Assignment checklist")
                    featureRow("Smart reminder path")
                    featureRow("Weekly report to teacher")
                }
                .listRowBackground(palette.surface)
            }

            Section {
                Button {
                    Task {
                        await purchaseManager.buy(productID: PurchaseManager.proProductID)
                    }
                } label: {
                    Text(primaryCTA)
                        .font(type.body.weight(.semibold))
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
        .onAppear {
            selectedAccountType = purchaseManager.accountType
        }
        .onChange(of: purchaseManager.accountType) { _, newValue in
            selectedAccountType = newValue
        }
        .onChange(of: selectedAccountType) { _, newValue in
            guard newValue != purchaseManager.accountType else { return }
            guard purchaseManager.hasCompletedInitialRoleSelection,
                  !purchaseManager.accountTypeChangeUsed else {
                selectedAccountType = purchaseManager.accountType
                return
            }
            pendingAccountType = newValue
            showAccountTypeConfirm = true
            selectedAccountType = purchaseManager.accountType
        }
        .alert("Change Account Type?", isPresented: $showAccountTypeConfirm, presenting: pendingAccountType) { newType in
            Button("Cancel", role: .cancel) {
                pendingAccountType = nil
            }
            Button("Change to \(newType.title)") {
                purchaseManager.setAccountType(newType)
                pendingAccountType = nil
            }
        } message: { _ in
            Text("You can only change account type once after setup. This action cannot be undone.")
        }
    }

    @ViewBuilder
    private func featureRow(_ title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.accent)
            Text(title)
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
        }
    }

    private var primaryCTA: String {
        if purchaseManager.isPro {
            return "Pro Unlocked"
        }
        if let proProduct {
            return "Unlock Pro (\(proProduct.displayPrice), One-time)"
        }
        return "Unlock Pro (Unavailable)"
    }

    private var primaryCTADisabled: Bool {
        purchaseManager.isPro || proProduct == nil
    }

    private var accountTypeHelpText: String {
        if !purchaseManager.hasCompletedInitialRoleSelection {
            return "Set during account setup after sign-in."
        }
        if purchaseManager.accountTypeChangeUsed {
            return "Your one account type change has been used."
        }
        return "You can change account type once if needed."
    }
}
