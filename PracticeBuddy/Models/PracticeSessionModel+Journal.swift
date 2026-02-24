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

    var checkInEvents: [PracticeCheckInEvent] {
        let raw = checkInLogJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        guard let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PracticeCheckInEvent].self, from: data)) ?? []
    }

    var hasVerificationData: Bool {
        verifiedSeconds > 0 || unverifiedSeconds > 0 || checkInCount > 0 || missedCheckInCount > 0
    }
}
