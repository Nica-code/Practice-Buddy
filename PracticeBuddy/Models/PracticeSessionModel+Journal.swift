import Foundation

@MainActor
extension PracticeSessionModel {
    var noteMood: PracticeNoteMood? {
        PracticeNoteMood(rawValue: noteMoodRaw)
    }

    var journal: PracticeSessionJournal? {
        let raw = noteStructuredJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PracticeSessionJournal.self, from: data)
    }
}
