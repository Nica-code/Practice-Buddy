import Foundation
import SwiftData

@Model
final class RhythmAccuracyTakeModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var bpm: Int
    var beatsAnalyzed: Int
    var averageOffsetMs: Double
    var grooveScore: Int
    var usedMetronome: Bool
    var detailJSON: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        bpm: Int,
        beatsAnalyzed: Int,
        averageOffsetMs: Double,
        grooveScore: Int,
        usedMetronome: Bool,
        detailJSON: String
    ) {
        self.id = id
        self.date = date
        self.bpm = min(max(bpm, 40), 220)
        self.beatsAnalyzed = max(0, beatsAnalyzed)
        self.averageOffsetMs = averageOffsetMs
        self.grooveScore = min(max(grooveScore, 0), 100)
        self.usedMetronome = usedMetronome
        self.detailJSON = detailJSON
    }
}

