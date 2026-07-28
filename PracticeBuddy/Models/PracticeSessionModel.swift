import Foundation
import SwiftData

@Model
final class PracticeSessionModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var durationSeconds: Int
    var verifiedSeconds: Int
    var unverifiedSeconds: Int
    var notes: String
    var noteTitle: String
    var noteFocus: String
    var noteMoodRaw: String
    var noteStructuredJSON: String
    var launchSource: String?
    var toolIDRaw: String?
    var toolResultJSON: String?

    // MARK: - Convenience (non-persistent)

    var durationMinutes: Int {
        max(0, durationSeconds / 60)
    }

    var verifiedMinutes: Int {
        max(0, verifiedSeconds / 60)
    }

    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    var isEmpty: Bool {
        durationSeconds <= 0 && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        id: UUID = UUID(),
        date: Date,
        durationSeconds: Int,
        verifiedSeconds: Int = 0,
        unverifiedSeconds: Int = 0,
        notes: String = "",
        noteTitle: String = "",
        noteFocus: String = "",
        noteMoodRaw: String = "",
        noteStructuredJSON: String = "",
        launchSource: String? = nil,
        toolIDRaw: String? = nil,
        toolResultJSON: String? = nil
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.verifiedSeconds = verifiedSeconds
        self.unverifiedSeconds = unverifiedSeconds
        self.notes = notes
        self.noteTitle = noteTitle
        self.noteFocus = noteFocus
        self.noteMoodRaw = noteMoodRaw
        self.noteStructuredJSON = noteStructuredJSON
        self.launchSource = launchSource
        self.toolIDRaw = toolIDRaw
        self.toolResultJSON = toolResultJSON
    }
}
