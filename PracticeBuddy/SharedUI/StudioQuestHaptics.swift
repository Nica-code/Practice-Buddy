import UIKit

enum StudioQuestHaptics {
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "practiquest.haptics.enabled") as? Bool ?? true
    }

    static func tap() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.75)
    }

    static func success() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
