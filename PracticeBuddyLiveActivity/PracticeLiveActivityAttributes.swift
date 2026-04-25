import Foundation
import ActivityKit

struct PracticeLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var modeRaw: String
        var title: String
        var subtitle: String
        var progress: Double
        var isRunning: Bool
        var referenceStartDate: Date
        var elapsedSeconds: Int
        var remainingSeconds: Int
    }

    var startedAt: Date
}

