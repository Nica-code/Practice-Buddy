import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class IdentityUpgradeCoordinator: ObservableObject {
    @Published private(set) var state: ProfileUpgradeState = .loading
    @Published private(set) var profile: IdentityProfile?
    @Published private(set) var statusMessage: String?

    private let db = Firestore.firestore()
    private let urlSession: URLSession
    private var configuredUID: String?
    private var isAnonymous = true

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    var blocksOnlineFeatures: Bool {
        switch state {
        case .required, .offlineRestricted: true
        default: false
        }
    }

    func configure(uid: String?, isAnonymous: Bool, upgradeRequired: Bool = true) async {
        guard let uid, !uid.isEmpty else {
            configuredUID = nil
            self.isAnonymous = true
            profile = nil
            state = .notRequired
            return
        }
        configuredUID = uid
        self.isAnonymous = isAnonymous
        guard !isAnonymous, upgradeRequired else {
            state = .notRequired
            return
        }
        await refresh()
    }

    func refresh() async {
        guard let uid = configuredUID else {
            state = .notRequired
            return
        }
        guard !isAnonymous else {
            state = .notRequired
            return
        }

        state = .loading
        do {
            let snapshot = try await db.collection("users").document(uid).getDocument(source: .server)
            let data = snapshot.data() ?? [:]
            let schemaVersion = max(0, data["profileSchemaVersion"] as? Int ?? 0)
            guard schemaVersion >= 2,
                  let parsed = parseProfile(uid: uid, data: data) else {
                state = .required
                return
            }
            profile = parsed
            state = .complete
        } catch {
            if isOffline(error) {
                state = .offlineRestricted
                statusMessage = "Finish your profile upgrade when you reconnect. Private practice remains available."
            } else {
                state = .failed("We couldn’t check your profile. Try again shortly.")
            }
        }
    }

    func complete(
        displayName rawName: String,
        handle rawHandle: String,
        dateOfBirth: Date,
        instrument rawInstrument: String,
        privacy: ProfilePrivacy
    ) async -> Bool {
        guard let uid = configuredUID,
              let user = Auth.auth().currentUser else {
            state = .failed("Sign in before completing your profile.")
            return false
        }
        let displayName = StudioQuestIdentityValidator.normalizedDisplayName(rawName)
        let handle = StudioQuestIdentityValidator.normalizedHandle(rawHandle)
        let instrument = String(rawInstrument.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))

        for result in [
            StudioQuestIdentityValidator.validateDisplayName(displayName),
            StudioQuestIdentityValidator.validateHandle(handle),
            StudioQuestIdentityValidator.validateDateOfBirth(dateOfBirth)
        ] where !result.isValid {
            state = .failed(result.message ?? "Review your profile details.")
            return false
        }
        guard !instrument.isEmpty else {
            state = .failed("Choose your main instrument.")
            return false
        }
        guard let baseURL = AppInfo.duelFunctionsBaseURL else {
            state = .failed("Profile setup is unavailable in this build.")
            return false
        }

        do {
            let token = try await user.getIDToken()
            let payload: [String: Any] = [
                "displayName": displayName,
                "handle": handle,
                "dateOfBirth": ISO8601DateFormatter().string(from: dateOfBirth),
                "instrument": instrument,
                "privacy": [
                    "isPrivate": privacy.isPrivate,
                    "showBio": privacy.showBio,
                    "showInstrument": privacy.showInstrument,
                    "showPracticeTotals": privacy.showPracticeTotals,
                    "showMomentsToFollowers": privacy.showMomentsToFollowers
                ]
            ]
            let response = try await post(baseURL.appendingPathComponent("identityCompleteProfile"), token: token, payload: payload)
            guard response["ok"] as? Bool == true else {
                throw IdentityCoordinatorError.server(response["error"] as? String ?? "Profile setup failed.")
            }
            profile = IdentityProfile(
                uid: uid,
                displayName: displayName,
                handle: handle,
                dateOfBirth: dateOfBirth,
                instrument: instrument,
                privacy: privacy,
                profileSchemaVersion: 2,
                handleChangedAt: .now
            )
            state = .complete
            statusMessage = "Your public musician profile is ready."
            PracticeAnalytics.record(.profileUpgradeCompleted)
            return true
        } catch {
            if isOffline(error) {
                state = .offlineRestricted
                statusMessage = "You can keep practicing privately while offline. Finish this when you reconnect."
            } else {
                state = .failed(userFacing(error))
            }
            return false
        }
    }

    func changeHandle(_ rawHandle: String) async -> Bool {
        guard let user = Auth.auth().currentUser,
              let baseURL = AppInfo.duelFunctionsBaseURL else { return false }
        let handle = StudioQuestIdentityValidator.normalizedHandle(rawHandle)
        guard StudioQuestIdentityValidator.validateHandle(handle).isValid else { return false }
        do {
            let token = try await user.getIDToken()
            let response = try await post(
                baseURL.appendingPathComponent("identityChangeHandle"),
                token: token,
                payload: ["handle": handle]
            )
            guard response["ok"] as? Bool == true else {
                statusMessage = response["error"] as? String ?? "Couldn’t update your handle."
                return false
            }
            if var profile {
                profile.handle = handle
                profile.handleChangedAt = .now
                self.profile = profile
            }
            statusMessage = "Handle updated. Your old handle will redirect temporarily."
            return true
        } catch {
            statusMessage = userFacing(error)
            return false
        }
    }

    func updatePrivacy(_ privacy: ProfilePrivacy) async -> Bool {
        guard let user = Auth.auth().currentUser,
              let baseURL = AppInfo.duelFunctionsBaseURL else {
            statusMessage = "Privacy settings are unavailable in this build."
            return false
        }
        do {
            let token = try await user.getIDToken()
            let response = try await post(
                baseURL.appendingPathComponent("identityUpdatePrivacy"),
                token: token,
                payload: ["privacy": privacyPayload(privacy)]
            )
            guard response["ok"] as? Bool == true else {
                statusMessage = response["error"] as? String ?? "Couldn’t update privacy settings."
                return false
            }
            if var profile {
                profile.privacy = privacy
                self.profile = profile
            }
            statusMessage = "Privacy settings updated."
            return true
        } catch {
            statusMessage = userFacing(error)
            return false
        }
    }

    private func post(_ url: URL, token: String, payload: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IdentityCoordinatorError.server("Invalid server response.")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            throw IdentityCoordinatorError.server(json["error"] as? String ?? "Profile service failed (\(http.statusCode)).")
        }
        return json
    }

    private func privacyPayload(_ privacy: ProfilePrivacy) -> [String: Bool] {
        [
            "isPrivate": privacy.isPrivate,
            "showBio": privacy.showBio,
            "showInstrument": privacy.showInstrument,
            "showPracticeTotals": privacy.showPracticeTotals,
            "showMomentsToFollowers": privacy.showMomentsToFollowers
        ]
    }

    private func parseProfile(uid: String, data: [String: Any]) -> IdentityProfile? {
        guard let displayName = data["displayName"] as? String,
              let handle = data["handle"] as? String,
              let birthDate = (data["dateOfBirth"] as? Timestamp)?.dateValue(),
              let instrument = data["instrument"] as? String else {
            return nil
        }
        let privacyData = data["profilePrivacy"] as? [String: Any] ?? [:]
        let privacy = ProfilePrivacy(
            isPrivate: privacyData["isPrivate"] as? Bool ?? true,
            showBio: privacyData["showBio"] as? Bool ?? true,
            showInstrument: privacyData["showInstrument"] as? Bool ?? true,
            showPracticeTotals: privacyData["showPracticeTotals"] as? Bool ?? false,
            showMomentsToFollowers: privacyData["showMomentsToFollowers"] as? Bool ?? true
        )
        return IdentityProfile(
            uid: uid,
            displayName: displayName,
            handle: handle,
            dateOfBirth: birthDate,
            instrument: instrument,
            privacy: privacy,
            profileSchemaVersion: max(2, data["profileSchemaVersion"] as? Int ?? 2),
            handleChangedAt: (data["handleChangedAt"] as? Timestamp)?.dateValue()
        )
    }

    private func isOffline(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.code == FirestoreErrorCode.unavailable.rawValue
            || ns.domain == NSURLErrorDomain && [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost].contains(ns.code)
    }

    private func userFacing(_ error: Error) -> String {
        if case IdentityCoordinatorError.server(let message) = error { return message }
        return "We couldn’t save your profile. Check your connection and try again."
    }
}

private enum IdentityCoordinatorError: LocalizedError {
    case server(String)
    var errorDescription: String? {
        if case .server(let message) = self { return message }
        return nil
    }
}
