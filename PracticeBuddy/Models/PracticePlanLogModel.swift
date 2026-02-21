import Foundation
import SwiftData

@Model
final class PracticePlanLogModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var targetMinutes: Int
    var actualSeconds: Int
    var goalsRaw: String
    var blocksRaw: String
    var reflectionWins: String
    var reflectionFix: String
    var reflectionNext: String
    var selfRating: Int

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        targetMinutes: Int,
        actualSeconds: Int,
        goalsRaw: String,
        blocksRaw: String,
        reflectionWins: String,
        reflectionFix: String,
        reflectionNext: String,
        selfRating: Int
    ) {
        self.id = id
        self.date = date
        self.targetMinutes = max(1, targetMinutes)
        self.actualSeconds = max(0, actualSeconds)
        self.goalsRaw = goalsRaw
        self.blocksRaw = blocksRaw
        self.reflectionWins = reflectionWins
        self.reflectionFix = reflectionFix
        self.reflectionNext = reflectionNext
        self.selfRating = min(max(selfRating, 1), 5)
    }
}

