import Foundation
import SwiftData

@Model
final class ScaleIntonationTakeModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var exerciseTypeRaw: String
    var keyRaw: String
    var modeRaw: String
    var baseOctave: Int
    var referenceHz: Int
    var tempoBPM: Int
    var noteCount: Int
    var overallScore: Int
    var centeringScore: Double
    var stabilityScore: Double
    var consistencyScore: Double
    var meanOffsetCents: Double
    var suggestionsRaw: String
    var perNoteJSON: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        exerciseTypeRaw: String,
        keyRaw: String,
        modeRaw: String,
        baseOctave: Int,
        referenceHz: Int,
        tempoBPM: Int,
        noteCount: Int,
        overallScore: Int,
        centeringScore: Double,
        stabilityScore: Double,
        consistencyScore: Double,
        meanOffsetCents: Double,
        suggestionsRaw: String,
        perNoteJSON: String
    ) {
        self.id = id
        self.date = date
        self.exerciseTypeRaw = exerciseTypeRaw
        self.keyRaw = keyRaw
        self.modeRaw = modeRaw
        self.baseOctave = min(max(baseOctave, 1), 7)
        self.referenceHz = min(max(referenceHz, 380), 470)
        self.tempoBPM = min(max(tempoBPM, 40), 220)
        self.noteCount = max(0, noteCount)
        self.overallScore = min(max(overallScore, 0), 100)
        self.centeringScore = centeringScore
        self.stabilityScore = stabilityScore
        self.consistencyScore = consistencyScore
        self.meanOffsetCents = meanOffsetCents
        self.suggestionsRaw = suggestionsRaw
        self.perNoteJSON = perNoteJSON
    }
}

