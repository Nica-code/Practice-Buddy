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
final class FirebaseBootstrap: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var currentUserID: String?
    @Published private(set) var isAnonymousUser: Bool = true
    @Published private(set) var statusMessage: String?

    private var didStart = false
    private var currentNonce: String?

    func start() async {
        guard !didStart else { return }
        didStart = true

        configureFirebaseIfNeeded()
        await ensureAnonymousAuth()
    }

    private func configureFirebaseIfNeeded() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            PBLog.firebase.info("Firebase configured.")
        } else {
            PBLog.firebase.info("Firebase already configured.")
        }

        _ = Firestore.firestore()
        isReady = true
        statusMessage = "Firebase initialized."
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
    }

    func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            statusMessage = "Apple sign-in failed: \(error.localizedDescription)"
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

    func signInWithGoogle() {
        Task {
            do {
                let credential = try await googleCredential()
                await signInWithCredential(credential, providerName: "Google")
            } catch {
                let msg = "Google sign-in failed: \(error.localizedDescription)"
                statusMessage = msg
                PBLog.firebase.error("\(msg)")
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
            statusMessage = "Signed in with \(providerName)."
        } catch {
            let ns = error as NSError
            if ns.domain == AuthErrorDomain,
               ns.code == AuthErrorCode.credentialAlreadyInUse.rawValue {
                do {
                    let result = try await signIn(with: credential)
                    refreshAuthState(user: result.user)
                    statusMessage = "Signed in with \(providerName)."
                    return
                } catch {
                    statusMessage = "\(providerName) sign-in failed: \(error.localizedDescription)"
                    return
                }
            }

            statusMessage = "\(providerName) sign-in failed: \(error.localizedDescription)"
            PBLog.firebase.error("\(providerName) sign-in failed: \(error.localizedDescription)")
        }
    }

    private func googleCredential() async throws -> AuthCredential {
        try await withCheckedThrowingContinuation { continuation in
            let provider = OAuthProvider(providerID: "google.com")
            provider.customParameters = ["prompt": "select_account"]
            provider.getCredentialWith(nil) { credential, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let credential else {
                    continuation.resume(throwing: NSError(
                        domain: "PracticeBuddy.FirebaseBootstrap",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "No Google auth credential returned."]
                    ))
                    return
                }
                continuation.resume(returning: credential)
            }
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
