import SwiftUI
import AuthenticationServices

struct AccountSetupView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pb.settings.language") private var appLanguageRaw: String = AppLanguage.english.rawValue
    @State private var animateIn: Bool = false

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private let onboardingLanguageOptions: [AppLanguage] = [.english, .korean, .romanian]

    private var onboardingLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: {
                let selected = AppLanguage(rawValue: appLanguageRaw) ?? .english
                return selected == .system ? .english : selected
            },
            set: { appLanguageRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PBBackdropView(palette: palette)

                VStack(alignment: .leading, spacing: 14) {
                    Spacer(minLength: 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PractiQuest")
                            .font(type.appTitle)
                            .foregroundStyle(palette.textPrimary)
                            .tracking(type.heroTracking)

                        Text("Your practice studio, now with duels and progress tracking.")
                            .font(type.body)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .offset(y: animateIn ? 0 : 10)
                    .opacity(animateIn ? 1 : 0)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sign in to continue")
                            .font(type.sectionTitle)
                            .foregroundStyle(palette.textPrimary)

                        HStack(spacing: 10) {
                            Image(systemName: "globe")
                                .foregroundStyle(palette.accent)
                            Picker("Language", selection: onboardingLanguageBinding) {
                                ForEach(onboardingLanguageOptions) { lang in
                                    Text(LocalizedStringKey(lang.titleKey)).tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .font(type.footnote)

                        Button {
                            firebase.signInWithGoogle()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "globe")
                                Text("Continue with Google")
                                    .font(type.body)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(PBActionButtonStyle(variant: .secondary, palette: palette))

                        SignInWithAppleButton(.continue) { request in
                            firebase.prepareAppleSignInRequest(request)
                        } onCompletion: { result in
                            firebase.handleAppleSignInCompletion(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))

                        Text("PractiQuest is actively improving with frequent updates and new features.")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let status = firebase.statusMessage, !status.isEmpty {
                            Text(LocalizedStringKey(status))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                        if let syncStatus = purchaseManager.syncStatus, !syncStatus.isEmpty {
                            Text(LocalizedStringKey(syncStatus))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .padding(PBLayout.padLG)
                    .pbModernCard(palette: palette)
                    .offset(y: animateIn ? 0 : 14)
                    .opacity(animateIn ? 1 : 0)

                    Spacer()
                }
                .padding(PBLayout.padLG)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                    animateIn = true
                }
            }
        }
    }
}
