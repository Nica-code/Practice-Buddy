import Foundation

enum DurationFormatter {
    static func string(from totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)

        if seconds >= 3600 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            let s = seconds % 60
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            let m = seconds / 60
            let s = seconds % 60
            return String(format: "%d:%02d", m, s)
        }
    }
}
