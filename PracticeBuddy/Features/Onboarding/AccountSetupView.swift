import SwiftUI
import AuthenticationServices

struct AccountSetupView: View {
    let embedsNavigationStack: Bool

    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pb.settings.language") private var appLanguageRaw: String = AppLanguage.english.rawValue
    @State private var showEmailAuthSheet: Bool = false
    @State private var presentedAsAnonymous = true

    init(embedsNavigationStack: Bool = true) {
        self.embedsNavigationStack = embedsNavigationStack
    }

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

    @ViewBuilder
    var body: some View {
        if embedsNavigationStack {
            NavigationStack { accountContent }
        } else {
            accountContent
        }
    }

    private var accountContent: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(
                    title: "Protect your progress",
                    subtitle: "Sign in when you want community, duels, and cloud backup."
                )

                StudioQuestSection {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Your practice stays yours", systemImage: "checkmark.shield.fill")
                            .font(StudioQuestTokens.Typography.sectionTitle)
                            .foregroundStyle(StudioQuestTokens.ColorRole.mint)
                        Text("Link the anonymous account already on this device. Your sessions, XP, tokens, and settings stay in place.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                StudioQuestSection {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Language", systemImage: "globe")
                                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                            Spacer()
                            Picker("Language", selection: onboardingLanguageBinding) {
                                ForEach(onboardingLanguageOptions) { lang in
                                    Text(LocalizedStringKey(lang.titleKey)).tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Button {
                            firebase.signInWithGoogle()
                        } label: {
                            HStack(spacing: 10) {
                                googleMark
                                Text("Continue with Google")
                            }
                        }
                        .buttonStyle(StudioQuestSecondaryButtonStyle())
                        .accessibilityIdentifier("account.google")

                        SignInWithAppleButton(.continue) { request in
                            firebase.prepareAppleSignInRequest(request)
                        } onCompletion: { result in
                            firebase.handleAppleSignInCompletion(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: StudioQuestTokens.Radius.control,
                                style: .continuous
                            )
                        )

                        Button {
                            showEmailAuthSheet = true
                        } label: {
                            Label("Continue with email", systemImage: "envelope.fill")
                        }
                        .buttonStyle(StudioQuestSecondaryButtonStyle())
                        .accessibilityIdentifier("account.email")
                    }
                }

                if let status = firebase.statusMessage, !status.isEmpty {
                    StudioQuestInlineStatus(text: status, kind: .information)
                }
                if let syncStatus = purchaseManager.syncStatus, !syncStatus.isEmpty {
                    StudioQuestInlineStatus(text: syncStatus, kind: .information)
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if embedsNavigationStack {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showEmailAuthSheet) {
            EmailAuthSheet()
                .environmentObject(firebase)
        }
        .onAppear {
            presentedAsAnonymous = firebase.isAnonymousUser
        }
        .onChange(of: firebase.isAnonymousUser) { _, isAnonymous in
            guard presentedAsAnonymous, !isAnonymous else { return }
            PracticeAnalytics.record(.signInConversion(source: "account_setup"))
            dismiss()
        }
    }

    private var googleMark: some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.26, green: 0.52, blue: 0.96), // blue
                            Color(red: 0.92, green: 0.30, blue: 0.24), // red
                            Color(red: 0.98, green: 0.75, blue: 0.20), // yellow
                            Color(red: 0.20, green: 0.72, blue: 0.36), // green
                            Color(red: 0.26, green: 0.52, blue: 0.96), // blue
                        ],
                        center: .center
                    ),
                    lineWidth: 1.8
                )

            Text("G")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                .offset(x: 0.2)
        }
        .frame(width: 18, height: 18)
    }
}

private struct EmailAuthSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signUp
        case signIn

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signUp: return "Sign Up"
            case .signIn: return "Sign In"
            }
        }

        var submitLabel: String {
            switch self {
            case .signUp: return "Create Account"
            case .signIn: return "Sign In"
            }
        }
    }

    @EnvironmentObject private var firebase: FirebaseBootstrap
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var mode: Mode = .signUp
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var displayName: String = ""
    @State private var localErrorMessage: String?
    @State private var isSubmitting: Bool = false

    var body: some View {
        NavigationStack {
            StudioQuestScrollPage {
                VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                    StudioQuestPageTitle(
                        title: LocalizedStringKey(mode.title),
                        subtitle: mode == .signUp
                            ? "Create a permanent account without losing this device’s practice history."
                            : "Reconnect your profile, progress, and community."
                    )

                    modePicker

                    StudioQuestSection {
                        VStack(alignment: .leading, spacing: 12) {
                            StudioQuestEyebrow(
                                LocalizedStringKey(
                                    mode == .signUp ? "Create account details" : "Account details"
                                )
                            )

                            TextField("Email", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .studioQuestAuthField(colorScheme: colorScheme)
                                .accessibilityIdentifier("auth.email")

                            SecureField("Password", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .textContentType(mode == .signUp ? .newPassword : .password)
                                .studioQuestAuthField(colorScheme: colorScheme)
                                .accessibilityIdentifier("auth.password")

                            if mode == .signUp {
                                SecureField("Confirm password", text: $confirmPassword)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .textContentType(.newPassword)
                                    .studioQuestAuthField(colorScheme: colorScheme)
                                    .accessibilityIdentifier("auth.confirmPassword")

                                TextField("Display name (optional)", text: $displayName)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled(true)
                                    .studioQuestAuthField(colorScheme: colorScheme)
                                    .accessibilityIdentifier("auth.displayName")
                                    .onChange(of: displayName) { _, newValue in
                                        let normalized = FirebaseBuddiesRepository.normalizedDisplayName(from: newValue)
                                        if normalized != newValue {
                                            displayName = normalized
                                        }
                                    }
                            }
                        }
                    }

                    if mode == .signUp {
                        StudioQuestSection {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Password requirements", systemImage: "key.fill")
                                    .font(StudioQuestTokens.Typography.sectionTitle)
                                Text("Use at least 8 characters with at least one letter and one number.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Divider()
                                    Label("Display name", systemImage: "person.text.rectangle")
                                        .font(.headline)
                                    Text("Use 2–30 letters, numbers, spaces, apostrophes, periods, underscores, or hyphens.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(LocalizedStringKey(mode.submitLabel))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("auth.submit")

                    if let localErrorMessage, !localErrorMessage.isEmpty {
                        StudioQuestInlineStatus(text: localErrorMessage, kind: .warning)
                            .accessibilityIdentifier("auth.error")
                    }

                    Text("A permanent profile is required only for community, duels, and cloud-linked identity. Private practice remains available without it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, StudioQuestTokens.Spacing.lg)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: mode) { _, _ in
                localErrorMessage = nil
            }
        }
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases) { option in
                StudioQuestInteractiveSurface(action: { mode = option }) {
                    Text(LocalizedStringKey(option.title))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .foregroundStyle(mode == option ? Color.white : Color.primary)
                        .background(
                            mode == option
                                ? StudioQuestTokens.ColorRole.cobalt
                                : StudioQuestTokens.ColorRole.surface(colorScheme),
                            in: Capsule()
                        )
                }
                .accessibilityAddTraits(mode == option ? .isSelected : [])
                .accessibilityIdentifier("auth.mode.\(option.rawValue)")
            }
        }
        .padding(4)
        .background(
            StudioQuestTokens.ColorRole.raisedSurface(colorScheme),
            in: Capsule()
        )
    }

    private func submit() async {
        localErrorMessage = nil

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(normalizedEmail) else {
            localErrorMessage = "Please enter a valid email address."
            return
        }

        if mode == .signUp {
            guard passwordSatisfiesRules(password) else {
                localErrorMessage = "Password must be at least 8 characters and include at least 1 letter and 1 number."
                return
            }
            guard password == confirmPassword else {
                localErrorMessage = "Passwords do not match."
                return
            }
            let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDisplayName.isEmpty && !FirebaseBuddiesRepository.isValidDisplayName(trimmedDisplayName) {
                localErrorMessage = "Display name must be 2-30 chars and use only letters, numbers, spaces, apostrophes, dots, underscores, or hyphens."
                return
            }
        } else if password.isEmpty {
            localErrorMessage = "Please enter your password."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let success: Bool
        switch mode {
        case .signUp:
            success = await firebase.signUpWithEmail(
                email: normalizedEmail,
                password: password,
                displayName: displayName
            )
        case .signIn:
            success = await firebase.signInWithEmail(
                email: normalizedEmail,
                password: password
            )
        }

        if success {
            dismiss()
        } else {
            localErrorMessage = firebase.statusMessage ?? "Authentication failed. Please try again."
        }
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 5 else { return false }
        let parts = trimmed.split(separator: "@")
        guard parts.count == 2 else { return false }
        guard parts[0].isEmpty == false, parts[1].isEmpty == false else { return false }
        return parts[1].contains(".")
    }

    private func passwordSatisfiesRules(_ value: String) -> Bool {
        guard value.count >= 8 else { return false }
        let hasLetter = value.rangeOfCharacter(from: .letters) != nil
        let hasNumber = value.rangeOfCharacter(from: .decimalDigits) != nil
        return hasLetter && hasNumber
    }
}

private extension View {
    func studioQuestAuthField(colorScheme: ColorScheme) -> some View {
        self
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(
                StudioQuestTokens.ColorRole.raisedSurface(colorScheme),
                in: RoundedRectangle(
                    cornerRadius: StudioQuestTokens.Radius.control,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: StudioQuestTokens.Radius.control,
                    style: .continuous
                )
                .stroke(
                    StudioQuestTokens.ColorRole.separator(colorScheme),
                    lineWidth: 1
                )
            }
    }
}
