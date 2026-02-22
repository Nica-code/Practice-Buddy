import Foundation
import Combine

struct JourneyQuestRow: Identifiable, Equatable {
    let id: String
    let title: String
    let progress: Int
    let target: Int
    let rewardTokens: Int
    let subtitle: String

    var isCompleted: Bool { progress >= target }
}

@MainActor
final class JourneyProgressManager: ObservableObject {
    private enum Keys {
        static let seeded = "pb.journey.seeded"
        static let totalXP = "pb.journey.totalXP"
        static let processedSessionIDs = "pb.journey.processedSessionIDs"
        static let xpLedgerByDay = "pb.journey.xpLedgerByDay"
    }

    @Published private(set) var totalXP: Int
    @Published private(set) var level: Int = 1
    @Published private(set) var xpIntoLevel: Int = 0
    @Published private(set) var xpForNextLevel: Int = 60
    @Published private(set) var xpToNextLevel: Int = 60
    @Published private(set) var todayXP: Int = 0
    @Published private(set) var dailyQuests: [JourneyQuestRow] = []
    @Published private(set) var weeklyQuests: [JourneyQuestRow] = []

    private var processedSessionIDs: Set<UUID> = []
    private var xpLedgerByDay: [String: Int] = [:]
    private let defaults = UserDefaults.standard
    private let isoDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    init() {
        totalXP = defaults.integer(forKey: Keys.totalXP)
        loadProcessedIDs()
        loadLedger()
        recalculateLevel()
        todayXP = xpLedgerByDay[dayKey(for: Date())] ?? 0
    }

    func handleSessionSnapshot(_ sessions: [PracticeSessionModel]) {
        if !defaults.bool(forKey: Keys.seeded) {
            seedFromExistingSessions(sessions)
            defaults.set(true, forKey: Keys.seeded)
        } else {
            awardXPForNewSessions(sessions)
        }
        updateQuestProgress(from: sessions)
    }

    private func seedFromExistingSessions(_ sessions: [PracticeSessionModel]) {
        var xp = 0
        var ids: Set<UUID> = []
        var ledger = xpLedgerByDay

        for session in sessions {
            ids.insert(session.id)
            let earned = max(0, session.durationSeconds / 60)
            xp += earned
            if earned > 0 {
                let key = dayKey(for: session.date)
                ledger[key, default: 0] += earned
            }
        }

        totalXP = xp
        processedSessionIDs = ids
        xpLedgerByDay = ledger
        persistAll()
        recalculateLevel()
        todayXP = xpLedgerByDay[dayKey(for: Date())] ?? 0
    }

    private func awardXPForNewSessions(_ sessions: [PracticeSessionModel]) {
        let newSessions = sessions.filter { !processedSessionIDs.contains($0.id) }
        guard !newSessions.isEmpty else { return }

        var gained = 0
        for session in newSessions {
            processedSessionIDs.insert(session.id)
            let earned = max(0, session.durationSeconds / 60)
            guard earned > 0 else { continue }
            gained += earned
            let key = dayKey(for: session.date)
            xpLedgerByDay[key, default: 0] += earned
        }

        if gained > 0 {
            totalXP += gained
            recalculateLevel()
        }
        todayXP = xpLedgerByDay[dayKey(for: Date())] ?? 0
        persistAll()
    }

    private func updateQuestProgress(from sessions: [PracticeSessionModel]) {
        let cal = Calendar.current
        let now = Date()
        let todayInterval = cal.dateInterval(of: .day, for: now)
        let weekInterval = cal.dateInterval(of: .weekOfYear, for: now)

        let todaySessions = sessions.filter { s in
            guard let it = todayInterval else { return false }
            return s.date >= it.start && s.date < it.end
        }
        let weekSessions = sessions.filter { s in
            guard let it = weekInterval else { return false }
            return s.date >= it.start && s.date < it.end
        }

        let todayMinutes = todaySessions.reduce(0) { $0 + max(0, $1.durationSeconds / 60) }
        let todayReflectiveSessions = todaySessions.filter(hasReflectionContent).count
        let todayCount = todaySessions.count

        let weekMinutes = weekSessions.reduce(0) { $0 + max(0, $1.durationSeconds / 60) }
        let activeDays = Set(weekSessions.map { cal.startOfDay(for: $0.date) }).count

        dailyQuests = [
            JourneyQuestRow(
                id: "dq_minutes",
                title: "Daily Time Builder",
                progress: todayMinutes,
                target: 25,
                rewardTokens: 15,
                subtitle: "Practice 25 minutes today"
            ),
            JourneyQuestRow(
                id: "dq_sessions",
                title: "Two Session Day",
                progress: todayCount,
                target: 2,
                rewardTokens: 12,
                subtitle: "Complete 2 sessions today"
            ),
            JourneyQuestRow(
                id: "dq_reflect",
                title: "Reflect & Improve",
                progress: todayReflectiveSessions,
                target: 1,
                rewardTokens: 10,
                subtitle: "Save 1 session with notes/reflection"
            )
        ]

        weeklyQuests = [
            JourneyQuestRow(
                id: "wq_minutes",
                title: "Weekly Volume",
                progress: weekMinutes,
                target: 180,
                rewardTokens: 50,
                subtitle: "Reach 180 minutes this week"
            ),
            JourneyQuestRow(
                id: "wq_days",
                title: "Consistency Week",
                progress: activeDays,
                target: 5,
                rewardTokens: 40,
                subtitle: "Practice on 5 different days"
            )
        ]
    }

    private func hasReflectionContent(_ session: PracticeSessionModel) -> Bool {
        if !session.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !session.noteFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !session.noteStructuredJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }

    private func recalculateLevel() {
        var remaining = max(0, totalXP)
        var currentLevel = 1

        while true {
            let nextCost = xpCostToAdvance(from: currentLevel)
            if remaining < nextCost { break }
            remaining -= nextCost
            currentLevel += 1
        }

        level = currentLevel
        xpIntoLevel = remaining
        xpForNextLevel = xpCostToAdvance(from: currentLevel)
        xpToNextLevel = max(0, xpForNextLevel - xpIntoLevel)
    }

    private func xpCostToAdvance(from level: Int) -> Int {
        let base = 50
        let growth = 10
        return base + growth * level * level
    }

    private func dayKey(for date: Date) -> String {
        isoDayFormatter.string(from: date)
    }

    private func persistAll() {
        defaults.set(totalXP, forKey: Keys.totalXP)
        saveProcessedIDs()
        saveLedger()
    }

    private func loadProcessedIDs() {
        guard let raw = defaults.array(forKey: Keys.processedSessionIDs) as? [String] else {
            processedSessionIDs = []
            return
        }
        processedSessionIDs = Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private func saveProcessedIDs() {
        let raw = processedSessionIDs.map(\.uuidString)
        defaults.set(raw, forKey: Keys.processedSessionIDs)
    }

    private func loadLedger() {
        guard let data = defaults.data(forKey: Keys.xpLedgerByDay),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            xpLedgerByDay = [:]
            return
        }
        xpLedgerByDay = decoded
    }

    private func saveLedger() {
        guard let data = try? JSONEncoder().encode(xpLedgerByDay) else { return }
        defaults.set(data, forKey: Keys.xpLedgerByDay)
    }
}

