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
