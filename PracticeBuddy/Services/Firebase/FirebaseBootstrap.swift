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
            let readable = readableAuthError(error)
            statusMessage = readable
            PBLog.firebase.error("Anonymous Firebase auth sign-in failed: \(readable)")
        }
    }

    private func signInAnonymously() async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
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
        switch result {
        case .failure(let error):
            statusMessage = L10n.f("Apple sign-in failed: %@", error.localizedDescription)
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
        activeAppleAuthController = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        handleAppleSignInCompletion(.failure(error))
        activeAppleAuthController = nil
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
        preconditionFailure("No UIWindow available for Apple sign-in presentation anchor.")
    }


    func signInWithGoogle() {
        statusMessage = "Starting Google sign-in…"
        PBLog.firebase.info("Starting Google sign-in flow.")
        let provider = OAuthProvider(providerID: "google.com")
        provider.customParameters = ["prompt": "select_account"]

        if let user = Auth.auth().currentUser, user.isAnonymous {
            user.link(with: provider, uiDelegate: authUIDelegate) { [weak self] result, error in
                Task { @MainActor in
                    self?.handleGoogleProviderResult(result: result, error: error)
                }
            }
        } else {
            Auth.auth().signIn(with: provider, uiDelegate: authUIDelegate) { [weak self] result, error in
                Task { @MainActor in
                    self?.handleGoogleProviderResult(result: result, error: error)
                }
            }
        }
    }

    private func handleGoogleProviderResult(result: AuthDataResult?, error: Error?) {
        if let error {
            let msg = L10n.f("Google sign-in failed: %@", error.localizedDescription)
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
                    let result = try await signIn(with: credential)
                    refreshAuthState(user: result.user)
                    statusMessage = L10n.f("Signed in with %@.", providerName)
                    return
                } catch {
                    statusMessage = L10n.f("%@ sign-in failed: %@", providerName, error.localizedDescription)
                    return
                }
            }

            statusMessage = L10n.f("%@ sign-in failed: %@", providerName, error.localizedDescription)
            PBLog.firebase.error("\(providerName) sign-in failed: \(error.localizedDescription)")
        }
    }

    private func signIn(with credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
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
        precondition(length > 0)
        let charset: Array<Character> =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms: [UInt8] = Array(repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
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

    private func readableAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        let code = AuthErrorCode(rawValue: nsError.code)

        switch code {
        case .operationNotAllowed:
            return "Firebase auth failed: Anonymous sign-in is disabled in Firebase Console."
        case .networkError:
            return "Firebase auth failed: Network error. Check simulator/device connection."
        case .invalidAPIKey:
            return "Firebase auth failed: Invalid Firebase API key configuration."
        case .appNotAuthorized:
            return "Firebase auth failed: App is not authorized for this Firebase project."
        default:
            return "Firebase auth failed (\(nsError.domain):\(nsError.code)): \(nsError.localizedDescription)"
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
