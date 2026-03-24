import Foundation

enum OnboardingTutorialState {
    private static let completionPrefix = "pb.onboarding.tutorial.completed."

    static func isCompleted(uid: String) -> Bool {
        let normalized = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return UserDefaults.standard.bool(forKey: completionPrefix + normalized)
    }

    static func markCompleted(uid: String) {
        let normalized = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: completionPrefix + normalized)
    }

    static func reset(uid: String) {
        let normalized = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: completionPrefix + normalized)
    }
}

