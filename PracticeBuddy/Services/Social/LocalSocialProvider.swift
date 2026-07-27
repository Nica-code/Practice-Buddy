import Foundation
import SwiftData
import SwiftUI
import UIKit
import Combine

@MainActor
final class LocalSocialProvider: ObservableObject, SocialProvider {

    let providerName: String = "Local (Share)"
    let isSignedIn: Bool = true

    @Published var totals: SocialTotals = .init()
    @Published var lastRefresh: Date?

    private var modelContext: ModelContext?

    private let keyDailyGoalMinutes = "pb.settings.dailyGoalMinutes"
    private let keyGoalScope = "pb.settings.goalScope"

    // Cached day buckets for streak (startOfDay -> seconds)
    private var cachedSecondsByDay: [Date: Int] = [:]

    // Cached time bounds used in the last refresh
    private var cachedTodayInterval: DateInterval?
    private var cachedWeekInterval: DateInterval?
    private var cachedMonthInterval: DateInterval?

    func configure(modelContext: ModelContext) {
        if self.modelContext != nil { return }
        self.modelContext = modelContext
        refresh()
    }

    func refresh() {
        guard let modelContext else { return }

        let now = Date()
        let cal = Calendar.current

        let todayInterval = cal.dateInterval(of: .day, for: now)
        let weekInterval = cal.dateInterval(of: .weekOfYear, for: now)
        let monthInterval = cal.dateInterval(of: .month, for: now)

        cachedTodayInterval = todayInterval
        cachedWeekInterval = weekInterval
        cachedMonthInterval = monthInterval

        // Decide how far back we need to fetch:
        // - month start covers today/week/month totals
        // - extend back only if streak might be shown
        let monthStart = monthInterval?.start ?? cal.startOfDay(for: now)
        var start = monthStart

        let goalMinutes = UserDefaults.standard.integer(forKey: keyDailyGoalMinutes)
        let scope = (UserDefaults.standard.string(forKey: keyGoalScope) ?? "today").lowercased()

        if goalMinutes > 0, scope == "today" {
            let todayStart = cal.startOfDay(for: now)
            let streakStart = cal.date(byAdding: .day, value: -400, to: todayStart) ?? todayStart
            start = min(monthStart, streakStart)
        }

        let descriptor = FetchDescriptor<PracticeSessionModel>(
            predicate: #Predicate { $0.date >= start }
        )

        let sessions: [PracticeSessionModel]
        do {
            sessions = try modelContext.fetch(descriptor)
        } catch {
            totals = .init()
            cachedSecondsByDay = [:]
            lastRefresh = now
            return
        }

        var t = SocialTotals()
        var byDay: [Date: Int] = [:]

        for s in sessions {
            let secs = max(0, s.durationSeconds)

            if let todayInterval, s.date >= todayInterval.start, s.date < todayInterval.end {
                t.todaySeconds += secs
            }
            if let weekInterval, s.date >= weekInterval.start, s.date < weekInterval.end {
                t.weekSeconds += secs
            }
            if let monthInterval, s.date >= monthInterval.start, s.date < monthInterval.end {
                t.monthSeconds += secs
            }

            let day = cal.startOfDay(for: s.date)
            byDay[day, default: 0] += secs
        }

        totals = t
        cachedSecondsByDay = byDay
        lastRefresh = now
    }

    func shareText(for period: SocialPeriod) -> String {
        let seconds = totals.seconds(for: period)
        let minutes = max(0, seconds / 60)

        var lines: [String] = []
        lines.append("PractiQuest 🎻")
        lines.append("\(period.title): \(minutes) min")
        lines.append(dateRangeLabel(for: period))

        if let streak = streakTextIfRelevant() {
            lines.append(streak)
        }

        lines.append("Tracked with PractiQuest")
        return lines.joined(separator: "\n")
    }

    func shareImageURL(for period: SocialPeriod) -> URL? {
        let seconds = totals.seconds(for: period)
        let minutes = max(0, seconds / 60)

        let subtitle = subtitleForShareCard(period: period)
        let streak = streakTextIfRelevant()

        let content = SocialShareCardView(
            title: "PractiQuest 🎻",
            subtitle: subtitle,
            valueText: "\(minutes) min",
            streakText: streak
        )
        .frame(width: 360, height: 200)

        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2.0

            guard let uiImage = renderer.uiImage else { return nil }
            guard let pngData = uiImage.pngData() else { return nil }

            let fileName = "practiquest-\(period.rawValue)-share.png"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            do {
                try pngData.write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        } else {
            return nil
        }
    }

    // MARK: Date labels

    private func subtitleForShareCard(period: SocialPeriod) -> String {
        switch period {
        case .today:
            return "Today • \(Formatters.day.string(from: Date()))"
        case .week:
            let (start, end) = currentWeekBounds()
            return "Week of \(Formatters.shortMonthDay.string(from: start)) – \(Formatters.shortMonthDay.string(from: end))"
        case .month:
            return Formatters.monthYear.string(from: Date())
        }
    }

    private func dateRangeLabel(for period: SocialPeriod) -> String {
        switch period {
        case .today:
            return "Date: \(Formatters.day.string(from: Date()))"
        case .week:
            let (start, end) = currentWeekBounds()
            return "Week: \(Formatters.shortMonthDay.string(from: start)) – \(Formatters.shortMonthDay.string(from: end))"
        case .month:
            return "Month: \(Formatters.monthYear.string(from: Date()))"
        }
    }

    private func currentWeekBounds() -> (Date, Date) {
        let cal = Calendar.current
        let now = Date()
        let interval = cal.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 0)

        let start = interval.start
        let end = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return (start, end)
    }

    // MARK: Streak (no extra fetch)

    private func streakTextIfRelevant() -> String? {
        let goalMinutes = UserDefaults.standard.integer(forKey: keyDailyGoalMinutes)
        if goalMinutes <= 0 { return nil }

        let scope = (UserDefaults.standard.string(forKey: keyGoalScope) ?? "today").lowercased()
        guard scope == "today" else { return nil }

        let streakDays = computeDailyGoalStreak(goalMinutes: goalMinutes)
        guard streakDays > 0 else { return nil }

        let dayWord = (streakDays == 1) ? "day" : "days"
        return "🔥 Streak: \(streakDays) \(dayWord)"
    }

    private func computeDailyGoalStreak(goalMinutes: Int) -> Int {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let goalSeconds = goalMinutes * 60

        var streak = 0
        var cursor = todayStart

        let hardCapDays = 3650

        for _ in 0..<hardCapDays {
            let total = cachedSecondsByDay[cursor, default: 0]
            if total >= goalSeconds {
                streak += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = prev
            } else {
                break
            }
        }

        return streak
    }

    // MARK: Formatters (cached)

    private enum Formatters {
        static let day: DateFormatter = {
            let df = DateFormatter()
            df.locale = .current
            df.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
            return df
        }()

        static let shortMonthDay: DateFormatter = {
            let df = DateFormatter()
            df.locale = .current
            df.setLocalizedDateFormatFromTemplate("MMM d")
            return df
        }()

        static let monthYear: DateFormatter = {
            let df = DateFormatter()
            df.locale = .current
            df.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return df
        }()
    }
}
