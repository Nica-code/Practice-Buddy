import Foundation

enum SocialPeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        }
    }
}

struct SocialTotals {
    var todaySeconds: Int = 0
    var weekSeconds: Int = 0
    var monthSeconds: Int = 0

    func seconds(for period: SocialPeriod) -> Int {
        switch period {
        case .today: return todaySeconds
        case .week: return weekSeconds
        case .month: return monthSeconds
        }
    }
}
