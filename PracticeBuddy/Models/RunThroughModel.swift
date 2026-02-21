import Foundation
import SwiftData

@Model
final class RunThroughModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var durationSeconds: Int
    var audioFilePath: String
    var notes: String
    var selfRating: Int
    var noPauseMode: Bool
    var usedMetronome: Bool

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        durationSeconds: Int,
        audioFilePath: String,
        notes: String,
        selfRating: Int,
        noPauseMode: Bool,
        usedMetronome: Bool
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = max(0, durationSeconds)
        self.audioFilePath = audioFilePath
        self.notes = notes
        self.selfRating = min(max(selfRating, 1), 5)
        self.noPauseMode = noPauseMode
        self.usedMetronome = usedMetronome
    }
}

