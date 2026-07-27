import Foundation
import Combine
import os
import FirebaseFirestore

struct StudioQuestFeatureFlagSnapshot: Codable, Equatable {
    var practiceMoments: Bool
    var publicExplore: Bool
    var identityUpgradeRequired: Bool
    var smartCoach: Bool
    var newAvatarRenderer: Bool

    static let productionDefaults = StudioQuestFeatureFlagSnapshot(
        practiceMoments: true,
        publicExplore: false,
        identityUpgradeRequired: true,
        smartCoach: true,
        newAvatarRenderer: true
    )

    func applying(_ values: [String: Any]) -> StudioQuestFeatureFlagSnapshot {
        StudioQuestFeatureFlagSnapshot(
            practiceMoments: values["practiceMoments"] as? Bool ?? practiceMoments,
            publicExplore: values["publicExplore"] as? Bool ?? publicExplore,
            identityUpgradeRequired: values["identityUpgradeRequired"] as? Bool ?? identityUpgradeRequired,
            smartCoach: values["smartCoach"] as? Bool ?? smartCoach,
            newAvatarRenderer: values["newAvatarRenderer"] as? Bool ?? newAvatarRenderer
        )
    }
}

@MainActor
final class StudioQuestFeatureFlags: ObservableObject {
    @Published private(set) var snapshot: StudioQuestFeatureFlagSnapshot
    @Published private(set) var lastRefreshAt: Date?

    private static let cacheKey = "practiquest.featureFlags.v1"
    private lazy var db = Firestore.firestore()
    private let defaults: UserDefaults
    private let usesDeterministicQAValues: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        usesDeterministicQAValues = ProcessInfo.processInfo.arguments.contains {
            $0.hasPrefix("--qa-")
        }
        #else
        usesDeterministicQAValues = false
        #endif

        if usesDeterministicQAValues {
            snapshot = .productionDefaults
        } else if let data = defaults.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(StudioQuestFeatureFlagSnapshot.self, from: data) {
            snapshot = cached
        } else {
            snapshot = .productionDefaults
        }
    }

    func refresh() async {
        guard !usesDeterministicQAValues else { return }
        do {
            let document = try await db.collection("appConfig")
                .document("practiquestV2")
                .getDocument(source: .server)
            let updated = snapshot.applying(document.data() ?? [:])
            snapshot = updated
            lastRefreshAt = .now
            if let encoded = try? JSONEncoder().encode(updated) {
                defaults.set(encoded, forKey: Self.cacheKey)
            }
        } catch {
            // Cached/default values intentionally remain active offline. Feature
            // flags must never block private practice because configuration
            // could not be refreshed.
            PBLog.firebase.warning(
                "Feature flag refresh failed; cached defaults remain active: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
