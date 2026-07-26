import Foundation
import Combine

@MainActor
final class PracticeQuestProgressStore: ObservableObject {
    static let shared = PracticeQuestProgressStore()

    @Published private(set) var counts: [String: Int]
    private let defaults: UserDefaults
    private let key = "practiquest.quest.events.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.counts = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    func count(for questID: String) -> Int {
        counts[questID, default: 0]
    }

    func record(_ questID: String) {
        guard !questID.isEmpty else { return }
        counts[questID, default: 0] += 1
        defaults.set(counts, forKey: key)
    }

    #if DEBUG
    func applyStudioQuestFixture() {
        counts["warm-up-warrior"] = 1
        counts["rhythm-clarity"] = 1
        counts["dynamic-control"] = 1
        counts["expression-mastery"] = 0
        defaults.set(counts, forKey: key)
    }
    #endif
}
