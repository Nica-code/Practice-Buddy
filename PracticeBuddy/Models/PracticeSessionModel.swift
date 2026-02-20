import Foundation
import SwiftData

@Model
final class PracticeSessionModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var durationSeconds: Int
    var notes: String
    var noteTitle: String
    var noteFocus: String
    var noteMoodRaw: String
    var noteStructuredJSON: String

    // MARK: - Convenience (non-persistent)

    var durationMinutes: Int {
        max(0, durationSeconds / 60)
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
        notes: String = "",
        noteTitle: String = "",
        noteFocus: String = "",
        noteMoodRaw: String = "",
        noteStructuredJSON: String = ""
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.noteTitle = noteTitle
        self.noteFocus = noteFocus
        self.noteMoodRaw = noteMoodRaw
        self.noteStructuredJSON = noteStructuredJSON
    }
}
