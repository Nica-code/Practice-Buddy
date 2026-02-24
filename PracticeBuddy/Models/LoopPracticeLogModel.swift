import Foundation
import SwiftData

@Model
final class LoopPracticeLogModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var loopsCompleted: Int
    var totalWorkSeconds: Int
    var loopDurationSeconds: Int
    var restSeconds: Int
    var tempoStartBPM: Int
    var tempoEndBPM: Int
    var targetLoops: Int
    var tagsRaw: String
    var tempoLadderEnabled: Bool
    var ladderCleanLoopsRequired: Int

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        loopsCompleted: Int,
        totalWorkSeconds: Int,
        loopDurationSeconds: Int,
        restSeconds: Int,
        tempoStartBPM: Int,
        tempoEndBPM: Int,
        targetLoops: Int,
        tagsRaw: String,
        tempoLadderEnabled: Bool = false,
        ladderCleanLoopsRequired: Int = 0
    ) {
        self.id = id
        self.date = date
        self.loopsCompleted = max(0, loopsCompleted)
        self.totalWorkSeconds = max(0, totalWorkSeconds)
        self.loopDurationSeconds = max(1, loopDurationSeconds)
        self.restSeconds = max(0, restSeconds)
        self.tempoStartBPM = max(0, tempoStartBPM)
        self.tempoEndBPM = max(0, tempoEndBPM)
        self.targetLoops = max(0, targetLoops)
        self.tagsRaw = tagsRaw
        self.tempoLadderEnabled = tempoLadderEnabled
        self.ladderCleanLoopsRequired = max(0, ladderCleanLoopsRequired)
    }
}
