import SwiftUI
import AuthenticationServices

struct ProfileTabView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var journey: JourneyProgressManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var buddiesVM = BuddiesViewModel()

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    var body: some View {
        Group {
            if firebase.currentUserID == nil {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading your account…")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    PBBackdropView(palette: palette)
                }
            } else {
                UserProfileView(buddiesVM: buddiesVM)
                    .overlay(alignment: .bottom) {
                        if firebase.isAnonymousUser {
                            guestSignInBanner
                                .padding(.horizontal, 16)
                                .padding(.bottom, 10)
                        }
                    }
            }
        }
        .task(id: firebase.currentUserID) {
            guard let uid = firebase.currentUserID else { return }
            await buddiesVM.start(for: uid)
            await buddiesVM.syncPublicLevel(journey.level)
        }
        .task(id: journey.level) {
            guard firebase.currentUserID != nil else { return }
            await buddiesVM.syncPublicLevel(journey.level)
        }
    }

    private var guestSignInBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Guest account")
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            Text("Sign in with Apple to keep your account across devices.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
            SignInWithAppleButton(.continue) { request in
                firebase.prepareAppleSignInRequest(request)
            } onCompletion: { result in
                firebase.handleAppleSignInCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 42)
            .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
        }
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
    }
}
