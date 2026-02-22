import SwiftUI
import AuthenticationServices

struct AccountSetupView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type

    @State private var selectedRole: PBAccountType = .student

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 8)

                Text("Practice Buddy")
                    .font(type.appTitle)
                    .foregroundStyle(theme.textPrimary)

                if firebase.isAnonymousUser {
                    Text("Sign in to create your account and sync your progress across devices.")
                        .font(type.body)
                        .foregroundStyle(theme.textSecondary)

                    Button {
                        // Coming soon
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text("Continue with Google (Coming Soon)")
                        }
                        .font(type.body.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(theme.surfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(true)

                    SignInWithAppleButton(.continue) { request in
                        firebase.prepareAppleSignInRequest(request)
                    } onCompletion: { result in
                        firebase.handleAppleSignInCompletion(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
                } else if !purchaseManager.hasCompletedInitialRoleSelection {
                    Text("Choose your account type.")
                        .font(type.body)
                        .foregroundStyle(theme.textSecondary)

                    Picker("Account Type", selection: $selectedRole) {
                        ForEach(PBAccountType.allCases) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(
                        purchaseManager.canSwitchRoleFreely
                        ? "Master account can switch between Student and Teacher anytime in Settings."
                        : "You can change this once later in Settings if needed."
                    )
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)

                    Button("Continue") {
                        purchaseManager.completeInitialAccountSetup(as: selectedRole)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Loading your account…")
                        .font(type.body)
                        .foregroundStyle(theme.textSecondary)
                }

                if let status = firebase.statusMessage, !status.isEmpty {
                    Text(status)
                        .font(type.footnote)
                        .foregroundStyle(theme.textSecondary)
                }
                if let syncStatus = purchaseManager.syncStatus, !syncStatus.isEmpty {
                    Text(syncStatus)
                        .font(type.footnote)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer()
            }
            .padding(PBLayout.padLG)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                selectedRole = purchaseManager.accountType
            }
        }
    }
}
