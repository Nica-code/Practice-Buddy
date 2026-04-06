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
    @State private var showEmailAuthSheet: Bool = false

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
                                googleMark
                                Text("Continue with Google")
                                    .font(type.body)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(
                                cornerRadius: PBLayout.radiusControl,
                                style: .continuous
                            )
                            .fill(palette.surfaceAlt)
                            .overlay(
                                RoundedRectangle(
                                    cornerRadius: PBLayout.radiusControl,
                                    style: .continuous
                                )
                                .stroke(
                                    palette.accent.opacity(0.20),
                                    lineWidth: 1
                                )
                            )
                        )
                        .foregroundStyle(palette.textPrimary)
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: PBLayout.radiusControl,
                                style: .continuous
                            )
                        )

                        SignInWithAppleButton(.continue) { request in
                            firebase.prepareAppleSignInRequest(request)
                        } onCompletion: { result in
                            firebase.handleAppleSignInCompletion(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))

                        Button {
                            showEmailAuthSheet = true
                        } label: {
                            Text("Sign up with Email")
                                .font(type.body)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: PBLayout.radiusControl,
                                        style: .continuous
                                    )
                                    .fill(palette.surfaceAlt)
                                    .overlay(
                                        RoundedRectangle(
                                            cornerRadius: PBLayout.radiusControl,
                                            style: .continuous
                                        )
                                        .stroke(
                                            palette.accent.opacity(0.20),
                                            lineWidth: 1
                                        )
                                    )
                                )
                                .foregroundStyle(palette.textPrimary)
                        }
                        .buttonStyle(.plain)

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
            .sheet(isPresented: $showEmailAuthSheet) {
                EmailAuthSheet()
                    .environmentObject(firebase)
            }
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
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @State private var mode: Mode = .signUp
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var displayName: String = ""
    @State private var localErrorMessage: String?
    @State private var isSubmitting: Bool = false

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(mode == .signUp ? "Create account details" : "Account details") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)

                    SecureField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textContentType(mode == .signUp ? .newPassword : .password)

                    if mode == .signUp {
                        SecureField("Confirm password", text: $confirmPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textContentType(.newPassword)

                        TextField("Display name (optional)", text: $displayName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled(true)
                    }
                }

                if mode == .signUp {
                    Section("Password requirements") {
                        Text("At least 8 characters, with at least 1 letter and 1 number.")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Text(mode.submitLabel)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .disabled(isSubmitting)
                }

                if let localErrorMessage, !localErrorMessage.isEmpty {
                    Section {
                        Text(localErrorMessage)
                            .font(type.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.title)
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
