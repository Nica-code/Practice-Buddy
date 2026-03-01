import Foundation
import os

enum PBLog {
    static let subsystem: String = {
        Bundle.main.bundleIdentifier ?? "PracticeBuddy"
    }()

    // Renamed from `store` -> `sessionStore` to avoid "Ambiguous use of store"
    static let sessionStore = Logger(subsystem: subsystem, category: "session-store")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let gamecenter = Logger(subsystem: subsystem, category: "gamecenter")
    static let firebase = Logger(subsystem: subsystem, category: "firebase")
}

enum PBGrowthMetric: String {
    case buddyInviteShareClicked = "buddy_invite_share_clicked"
    case buddyInviteAutoSent = "buddy_invite_auto_sent"
}

enum PBGrowthMetrics {
    private static let defaults = UserDefaults.standard
    private static let keyPrefix = "pb.growth.metric."

    static func record(_ metric: PBGrowthMetric) {
        let key = keyPrefix + metric.rawValue
        let nextCount = defaults.integer(forKey: key) + 1
        defaults.set(nextCount, forKey: key)
        PBLog.ui.info("growth_metric \(metric.rawValue, privacy: .public) count=\(nextCount, privacy: .public)")
    }

    static func count(for metric: PBGrowthMetric) -> Int {
        defaults.integer(forKey: keyPrefix + metric.rawValue)
    }
}
