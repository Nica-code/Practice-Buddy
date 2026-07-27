import Foundation
import Combine
import os
import CryptoKit
import AuthenticationServices
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import UIKit

@MainActor
final class FirebaseBootstrap: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private static var didMarkConfigured = false

    static func markConfiguredAtLaunch() {
        didMarkConfigured = true
    }

    @Published private(set) var isReady = false
    @Published private(set) var currentUserID: String?
    @Published private(set) var currentUserEmail: String?
    @Published private(set) var isAnonymousUser: Bool = true
    @Published private(set) var statusMessage: String?

    private var isStarting = false
    private var currentNonce: String?
    private var activeAppleAuthController: ASAuthorizationController?
    private let authUIDelegate = FirebaseAuthPresentationDelegate()
    private lazy var callable: FirebaseCallableTransport = FirebaseCallableClient()

    func start() async {
        guard !isReady, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        guard await waitForFirebaseConfiguration() else { return }
        await ensureAnonymousAuth()
    }

    private func waitForFirebaseConfiguration() async -> Bool {
        // Configure is expected to happen in PracticeBuddyApp.init().
        // Avoid polling FirebaseApp.app() here because querying before configure
        // can emit noisy startup warnings in console.
        guard Self.didMarkConfigured else {
            statusMessage = "Firebase is not configured yet."
            PBLog.firebase.error("Firebase not marked as configured at launch.")
            return false
        }
        _ = Firestore.firestore()
        isReady = true
        statusMessage = "Firebase initialized."
        PBLog.firebase.info("Firebase already configured.")
        return true
    }

    private func ensureAnonymousAuth() async {
        if let user = Auth.auth().currentUser {
            refreshAuthState(user: user)
            statusMessage = "Authenticated."
            PBLog.firebase.info("Firebase auth user already available.")
            return
        }

        do {
            let result = try await signInAnonymously()
            refreshAuthState(user: result.user)
            statusMessage = "Authenticated."
            PBLog.firebase.info("Anonymous Firebase auth sign-in succeeded.")
        } catch {
            let readable = userFacingAuthError(error)
            statusMessage = readable
            PBLog.firebase.error("Anonymous Firebase auth sign-in failed: \(error.localizedDescription)")
        }
    }

    private func signInAnonymously() async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            Auth.auth().signInAnonymously { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else {
                    continuation.resume(throwing: NSError(
                        domain: "PracticeBuddy.FirebaseBootstrap",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No auth result returned."]
                    ))
                    return
                }

                continuation.resume(returning: result)
            }
        }
    }

    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        statusMessage = "Starting Apple sign-in…"
    }

    func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        defer {
            currentNonce = nil
            activeAppleAuthController = nil
        }
        switch result {
        case .failure(let error):
            statusMessage = userFacingAuthError(error, provider: "Apple")
            PBLog.firebase.error("Apple sign-in failed: \(error.localizedDescription)")

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                statusMessage = "Apple sign-in failed: Invalid credential."
                return
            }

            guard let nonce = currentNonce else {
                statusMessage = "Apple sign-in failed: Missing request nonce."
                return
            }

            guard
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                statusMessage = "Apple sign-in failed: Missing identity token."
                return
            }

            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: credential.fullName
            )

            Task { await signInWithCredential(firebaseCredential, providerName: "Apple") }
        }
    }

    func startAppleSignInFlowFallback() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        prepareAppleSignInRequest(request)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        activeAppleAuthController = controller
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        handleAppleSignInCompletion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        handleAppleSignInCompletion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }),
           let keyWindow = activeScene.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        if let anyWindow = scenes.flatMap(\.windows).first {
            return anyWindow
        }
        if let fallbackScene = scenes.first {
            PBLog.firebase.error("No UIWindow available for Apple sign-in presentation anchor. Using scene fallback window.")
            return UIWindow(windowScene: fallbackScene)
        }
        preconditionFailure("No UIWindowScene available for Apple sign-in presentation anchor.")
    }


    func signInWithGoogle() {
        statusMessage = "Starting Google sign-in…"
        PBLog.firebase.info("Starting Google sign-in flow.")
        let provider = OAuthProvider(providerID: "google.com")
        provider.customParameters = ["prompt": "select_account"]
        let shouldLinkAnonymous = (Auth.auth().currentUser?.isAnonymous == true)
        runGoogleSignIn(provider: provider, attemptLink: shouldLinkAnonymous)
    }

    @discardableResult
    func signUpWithEmail(email: String, password: String, displayName: String?) async -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedEmail.isEmpty else {
            statusMessage = "Please enter an email address."
            return false
        }

        do {
            let result: AuthDataResult
            if let user = Auth.auth().currentUser, user.isAnonymous {
                let credential = EmailAuthProvider.credential(withEmail: normalizedEmail, password: password)
                result = try await linkCurrentUser(with: credential)
            } else {
                result = try await createUser(withEmail: normalizedEmail, password: password)
            }

            try await updateDisplayNameIfNeeded(normalizedName, for: result.user)
            refreshAuthState(user: result.user)
            statusMessage = "Email account created."
            PBLog.firebase.info("Signed up with email/password.")
            return true
        } catch {
            let ns = error as NSError
            if ns.domain == AuthErrorDomain,
               ns.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                do {
                    let result = try await signIn(withEmail: normalizedEmail, password: password)
                    refreshAuthState(user: result.user)
                    statusMessage = "Signed in with Email."
                    PBLog.firebase.info("Credential already in use; signed in with existing email account.")
                    return true
                } catch {
                    statusMessage = userFacingAuthError(error, provider: "Email")
                    PBLog.firebase.error("Email sign-up fallback sign-in failed: \(error.localizedDescription)")
                    return false
                }
            }

            statusMessage = userFacingAuthError(error, provider: "Email")
            PBLog.firebase.error("Email sign-up failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func signInWithEmail(email: String, password: String) async -> Bool {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else {
            statusMessage = "Please enter an email address."
            return false
        }

        do {
            let result = try await signIn(withEmail: normalizedEmail, password: password)
            refreshAuthState(user: result.user)
            statusMessage = "Signed in with Email."
            PBLog.firebase.info("Signed in with email/password.")
            return true
        } catch {
            statusMessage = userFacingAuthError(error, provider: "Email")
            PBLog.firebase.error("Email sign-in failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func signOutCurrentUser() -> Bool {
        do {
            try Auth.auth().signOut()
            currentUserID = nil
            currentUserEmail = nil
            isAnonymousUser = true
            statusMessage = "Signed out."
            PBLog.firebase.info("Signed out current Firebase user.")
            return true
        } catch {
            statusMessage = "We couldn't sign you out. Check your connection and try again."
            PBLog.firebase.error("Sign out failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func deleteCurrentAccount() async -> Bool {
        guard Auth.auth().currentUser != nil else {
            statusMessage = "No signed-in account to delete."
            return false
        }
        do {
            let response = try await callable.call("deleteAccountV2", data: [:])
            guard response["ok"] as? Bool == true else {
                let message = (response["error"] as? String) ?? "Account deletion failed."
                statusMessage = message
                return false
            }

            try? Auth.auth().signOut()
            currentUserID = nil
            currentUserEmail = nil
            isAnonymousUser = true
            statusMessage = "Account deleted."
            PBLog.firebase.info("Deleted current Firebase account and signed out.")
            return true
        } catch {
            let message = L10n.f("Account deletion failed: %@", error.localizedDescription)
            statusMessage = message
            PBLog.firebase.error("Account deletion failed: \(error.localizedDescription)")
            return false
        }
    }

    private func handleGoogleProviderResult(result: AuthDataResult?, error: Error?) {
        if let error {
            let msg = userFacingAuthError(error, provider: "Google")
            statusMessage = msg
            PBLog.firebase.error("\(msg)")
            return
        }

        guard let result else {
            let msg = "Google sign-in failed: No auth result returned."
            statusMessage = msg
            PBLog.firebase.error("\(msg)")
            return
        }

        refreshAuthState(user: result.user)
        statusMessage = "Signed in with Google."
        PBLog.firebase.info("Signed in with Google.")
    }

    private func runGoogleSignIn(provider: OAuthProvider, attemptLink: Bool) {
        if attemptLink, let user = Auth.auth().currentUser, user.isAnonymous {
            user.link(with: provider, uiDelegate: authUIDelegate) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let ns = error as NSError?,
                       ns.domain == AuthErrorDomain,
                       ns.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                        // Fall back to direct Google sign-in if this Google account already exists.
                        self.runGoogleSignIn(provider: provider, attemptLink: false)
                        return
                    }
                    self.handleGoogleProviderResult(result: result, error: error)
                }
            }
            return
        }

        Auth.auth().signIn(with: provider, uiDelegate: authUIDelegate) { [weak self] result, error in
            Task { @MainActor in
                self?.handleGoogleProviderResult(result: result, error: error)
            }
        }
    }

    private func signInWithCredential(_ credential: AuthCredential, providerName: String) async {
        do {
            let result: AuthDataResult
            if let user = Auth.auth().currentUser, user.isAnonymous {
                result = try await linkCurrentUser(with: credential)
                PBLog.firebase.info("Linked anonymous user with \(providerName) credential.")
            } else {
                result = try await signIn(with: credential)
                PBLog.firebase.info("Signed in with \(providerName) credential.")
            }

            refreshAuthState(user: result.user)
            statusMessage = L10n.f("Signed in with %@.", providerName)
        } catch {
            let ns = error as NSError
            if ns.domain == AuthErrorDomain,
               ns.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                do {
                    let fallbackCredential = (ns.userInfo[AuthErrorUserInfoUpdatedCredentialKey] as? AuthCredential) ?? credential
                    let result = try await signIn(with: fallbackCredential)
                    refreshAuthState(user: result.user)
                    statusMessage = L10n.f("Signed in with %@.", providerName)
                    return
                } catch {
                    statusMessage = userFacingAuthError(error, provider: providerName)
                    return
                }
            }

            statusMessage = userFacingAuthError(error, provider: providerName)
            PBLog.firebase.error("\(providerName) sign-in failed: \(error.localizedDescription)")
        }
    }

    private func signIn(with credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            Auth.auth().signIn(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else {
                    continuation.resume(throwing: NSError(
                        domain: "PracticeBuddy.FirebaseBootstrap",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "No sign-in result returned."]
                    ))
                    return
                }

                continuation.resume(returning: result)
            }
        }
    }

    private func createUser(withEmail email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: NSError(
                        domain: "PracticeBuddy.FirebaseBootstrap",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "No create-user result returned."]
                    ))
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func signIn(withEmail email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: NSError(
                        domain: "PracticeBuddy.FirebaseBootstrap",
                        code: -6,
                        userInfo: [NSLocalizedDescriptionKey: "No email sign-in result returned."]
                    ))
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func linkCurrentUser(with credential: AuthCredential) async throws -> AuthDataResult {
        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "PracticeBuddy.FirebaseBootstrap",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "No current user available for account linking."]
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            user.link(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result else {
                    continuation.resume(throwing: NSError(
                        domain: "PracticeBuddy.FirebaseBootstrap",
                        code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "No link result returned."]
                    ))
                    return
                }

                continuation.resume(returning: result)
            }
        }
    }

    private func updateDisplayNameIfNeeded(_ displayName: String?, for user: User) async throws {
        guard let displayName, !displayName.isEmpty else { return }
        let request = user.createProfileChangeRequest()
        request.displayName = displayName
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            request.commitChanges { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func refreshAuthState(user: User) {
        currentUserID = user.uid
        currentUserEmail = user.email
        isAnonymousUser = user.isAnonymous
        Task {
            await PushTokenManager.shared.syncPendingTokenIfPossible()
        }
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func randomNonceString(length: Int = 32) -> String {
        guard length > 0 else {
            PBLog.firebase.error("randomNonceString called with non-positive length. Falling back to default length.")
            return randomNonceString(length: 32)
        }
        let charset: Array<Character> =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms: [UInt8] = Array(repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                PBLog.firebase.error("SecRandomCopyBytes failed (\(errorCode, privacy: .public)). Using UUID fallback nonce source.")
                while remainingLength > 0 {
                    let fallback = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                    for scalar in fallback.unicodeScalars {
                        if remainingLength == 0 { break }
                        let idx = Int(scalar.value) % charset.count
                        result.append(charset[idx])
                        remainingLength -= 1
                    }
                }
                break
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func userFacingAuthError(_ error: Error, provider: String? = nil) -> String {
        let nsError = error as NSError
        let code = AuthErrorCode(rawValue: nsError.code)
        let prefix = provider.map { "\($0) sign-in" } ?? "Account setup"

        switch code {
        case .wrongPassword, .invalidCredential, .userNotFound:
            return "\(prefix) couldn't be completed. Check your email and password, then try again."
        case .emailAlreadyInUse, .credentialAlreadyInUse, .accountExistsWithDifferentCredential:
            return "That account already exists. Sign in using the method you originally chose."
        case .weakPassword:
            return "Choose a stronger password with at least six characters."
        case .invalidEmail:
            return "Enter a valid email address."
        case .userDisabled:
            return "This account is unavailable. Contact support if you think this is a mistake."
        case .operationNotAllowed:
            return "\(prefix) is temporarily unavailable. Try another sign-in method."
        case .networkError:
            return "You're offline. Reconnect and try again."
        case .tooManyRequests:
            return "Too many attempts were made. Wait a moment, then try again."
        case .invalidAPIKey, .appNotAuthorized:
            return "\(prefix) is temporarily unavailable. Please try again later."
        default:
            return "\(prefix) couldn't be completed. Please try again."
        }
    }
}

private final class FirebaseAuthPresentationDelegate: NSObject, AuthUIDelegate {
    func present(_ viewController: UIViewController, animated: Bool, completion: (() -> Void)?) {
        guard let presenter = topViewController() else {
            completion?()
            return
        }
        presenter.present(viewController, animated: animated, completion: completion)
    }

    func dismiss(animated: Bool, completion: (() -> Void)?) {
        guard let presenter = topViewController() else {
            completion?()
            return
        }
        presenter.dismiss(animated: animated, completion: completion)
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        let root = windows.first(where: { $0.isKeyWindow })?.rootViewController ?? windows.first?.rootViewController
        return topMost(from: root)
    }

    private func topMost(from root: UIViewController?) -> UIViewController? {
        guard let root else { return nil }
        if let presented = root.presentedViewController {
            return topMost(from: presented)
        }
        if let nav = root as? UINavigationController {
            return topMost(from: nav.visibleViewController ?? nav.topViewController)
        }
        if let tab = root as? UITabBarController {
            return topMost(from: tab.selectedViewController)
        }
        return root
    }
}
