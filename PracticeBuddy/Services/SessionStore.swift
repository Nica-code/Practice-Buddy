import Foundation
import Combine
import SwiftData
import SwiftUI
import os   // ✅ Required for Logger string interpolation + privacy

@MainActor
final class SessionStore: ObservableObject {

    // MARK: - Constants

    private enum Constants {
        static let dayCacheWindowDays = 400        // bound cache size
        static let streakHardCapDays = 3650        // ~10 years safety cap
    }

    // MARK: - Published State

    @Published private(set) var sessions: [PracticeSessionModel] = [] {
        didSet { rebuildCaches() }
    }
    @Published private(set) var totalAllMinutes: Int = 0

    // User-presentable errors (used by ContentView alert)
    @Published var lastAppError: PBAppError? = nil

    @AppStorage("pb.settings.historyRetention") private var historyRetention: Int = 0

    // MARK: - SwiftData

    private var modelContext: ModelContext?

    // MARK: - Caches

    private var secondsByDay: [Date: Int] = [:]

    // MARK: - Configure

    func configure(context: ModelContext) {
        if modelContext != nil { return }
        modelContext = context
        reload()
        pruneToRetentionIfNeeded()
    }

    // MARK: - Totals

    var totalTodaySeconds: Int {
        secondsByDay[Calendar.current.startOfDay(for: Date())] ?? 0
    }

    var totalThisWeekSeconds: Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return totalSeconds(in: interval)
    }

    var totalThisMonthSeconds: Int {
        guard let interval = Calendar.current.dateInterval(of: .month, for: Date()) else { return 0 }
        return totalSeconds(in: interval)
    }

    private func totalSeconds(in interval: DateInterval) -> Int {
        let cal = Calendar.current
        var total = 0

        var day = cal.startOfDay(for: interval.start)
        while day < interval.end {
            total += secondsByDay[day] ?? 0
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return total
    }

    func totalSeconds(onDayContaining date: Date) -> Int {
        secondsByDay[Calendar.current.startOfDay(for: date)] ?? 0
    }

    // MARK: - Streak

    func currentStreakDays(dailyGoalMinutes: Int) -> Int {
        let goalSeconds = dailyGoalMinutes * 60
        guard goalSeconds > 0 else { return 0 }

        let cal = Calendar.current
        var cursor = cal.startOfDay(for: Date())
        var streak = 0

        for _ in 0..<Constants.streakHardCapDays {
            let seconds = secondsByDay[cursor] ?? 0
            if seconds >= goalSeconds {
                streak += 1
            } else {
                break
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        return streak
    }

    // MARK: - Reload

    func reload() {
        guard let modelContext else { return }

        do {
            let descriptor = FetchDescriptor<PracticeSessionModel>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            sessions = try modelContext.fetch(descriptor)
        } catch {
            PBLog.sessionStore.error("SwiftData fetch failed: \(String(describing: error), privacy: .public)")
            sessions = []
            lastAppError = PBAppError(
                title: "Load Failed",
                message: "Your practice history couldn't be loaded. Please try again."
            )
        }
    }

    // MARK: - CRUD

    func addSession(
        date: Date,
        durationSeconds: Int,
        verifiedSeconds: Int? = nil,
        unverifiedSeconds: Int = 0,
        checkInCount: Int = 0,
        missedCheckInCount: Int = 0,
        checkInLogJSON: String = "",
        notes: String,
        noteTitle: String = "",
        noteFocus: String = "",
        noteMoodRaw: String = "",
        noteStructuredJSON: String = ""
    ) {
        guard let modelContext else { return }

        let s = PracticeSessionModel(
            date: date,
            durationSeconds: durationSeconds,
            verifiedSeconds: max(0, verifiedSeconds ?? durationSeconds),
            unverifiedSeconds: max(0, unverifiedSeconds),
            checkInCount: max(0, checkInCount),
            missedCheckInCount: max(0, missedCheckInCount),
            checkInLogJSON: checkInLogJSON,
            notes: notes,
            noteTitle: noteTitle,
            noteFocus: noteFocus,
            noteMoodRaw: noteMoodRaw,
            noteStructuredJSON: noteStructuredJSON
        )
        modelContext.insert(s)

        do {
            try modelContext.save()
            sessions.insert(s, at: 0)
            pruneToRetentionIfNeeded()
        } catch {
            PBLog.sessionStore.error("SwiftData save failed (addSession): \(String(describing: error), privacy: .public)")
            lastAppError = PBAppError(
                title: "Save Failed",
                message: "Your session couldn't be saved. Please try again."
            )
        }
    }

    func updateNotes(for sessionID: UUID, notes: String) {
        guard let modelContext else { return }

        do {
            guard let match = sessions.first(where: { $0.id == sessionID }) else { return }
            if match.notes == notes { return }
            match.notes = notes
            try modelContext.save()
            objectWillChange.send()
        } catch {
            PBLog.sessionStore.error("SwiftData update failed (updateNotes): \(String(describing: error), privacy: .public)")
            lastAppError = PBAppError(
                title: "Update Failed",
                message: "Your notes couldn't be updated. Please try again."
            )
        }
    }

    func deleteSessions(at offsets: IndexSet) {
        guard let modelContext else { return }

        let toDelete = offsets.map { sessions[$0] }
        for s in toDelete { modelContext.delete(s) }
        var didSave = false

        do {
            try modelContext.save()
            didSave = true
        } catch {
            PBLog.sessionStore.error("SwiftData save failed (deleteSessions): \(String(describing: error), privacy: .public)")
            lastAppError = PBAppError(
                title: "Delete Failed",
                message: "Some sessions couldn't be deleted. Please try again."
            )
        }
        if didSave {
            sessions.remove(atOffsets: offsets)
        }
    }

    func deleteSessions(withIDs ids: [UUID]) {
        guard let modelContext else { return }
        let idSet = Set(ids)
        let toDelete = sessions.filter { idSet.contains($0.id) }
        var didSave = false

        do {
            for match in toDelete { modelContext.delete(match) }
            try modelContext.save()
            didSave = true
        } catch {
            PBLog.sessionStore.error("SwiftData delete by IDs failed: \(String(describing: error), privacy: .public)")
            lastAppError = PBAppError(
                title: "Delete Failed",
                message: "Some sessions couldn't be deleted. Please try again."
            )
        }
        if didSave {
            sessions.removeAll { idSet.contains($0.id) }
        }
    }

    // MARK: - Retention

    func retentionChanged() {
        pruneToRetentionIfNeeded()
    }

    private func pruneToRetentionIfNeeded() {
        guard let modelContext else { return }
        let retention = historyRetention
        guard retention > 0 else { return }
        guard sessions.count > retention else { return }

        let extras = sessions.dropFirst(retention)
        for s in extras { modelContext.delete(s) }
        var didSave = false

        do {
            try modelContext.save()
            didSave = true
        } catch {
            PBLog.sessionStore.error("SwiftData save failed (prune): \(String(describing: error), privacy: .public)")
            lastAppError = PBAppError(
                title: "Cleanup Failed",
                message: "Old sessions couldn't be cleaned up. Please try again."
            )
        }
        if didSave {
            sessions = Array(sessions.prefix(retention))
        }
    }

    // MARK: - Cache rebuild

    private func rebuildCaches() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let cutoff = cal.date(byAdding: .day, value: -Constants.dayCacheWindowDays, to: today) ?? today

        var dayTotals: [Date: Int] = [:]
        dayTotals.reserveCapacity(min(Constants.dayCacheWindowDays, sessions.count))

        for s in sessions {
            let duration = max(0, s.durationSeconds)
            if s.date < cutoff { continue }

            let day = cal.startOfDay(for: s.date)
            dayTotals[day, default: 0] += duration
        }

        secondsByDay = dayTotals
        totalAllMinutes = max(0, sessions.reduce(0) { $0 + max(0, $1.durationSeconds) } / 60)
    }
}
