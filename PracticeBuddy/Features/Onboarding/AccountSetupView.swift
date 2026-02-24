import SwiftUI
import AuthenticationServices

struct AccountSetupView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Spacer(minLength: 8)

                Text("Practice Buddy")
                    .font(type.appTitle)
                    .foregroundStyle(theme.textPrimary)

                Text("Sign in to continue.")
                    .font(type.body)
                    .foregroundStyle(theme.textSecondary)

                Button {
                    firebase.signInWithGoogle()
                } label: {
                    HStack {
                        Image(systemName: "globe")
                        Text("Continue with Google")
                    }
                    .font(type.body)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(theme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
                }
                .buttonStyle(.plain)

                SignInWithAppleButton(.continue) { request in
                    firebase.prepareAppleSignInRequest(request)
                } onCompletion: { result in
                    firebase.handleAppleSignInCompletion(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))

                if let status = firebase.statusMessage, !status.isEmpty {
                    Text(LocalizedStringKey(status))
                        .font(type.footnote)
                        .foregroundStyle(theme.textSecondary)
                }
                if let syncStatus = purchaseManager.syncStatus, !syncStatus.isEmpty {
                    Text(LocalizedStringKey(syncStatus))
                        .font(type.footnote)
                        .foregroundStyle(theme.textSecondary)
                }

                Spacer()
            }
            .padding(PBLayout.padLG)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
