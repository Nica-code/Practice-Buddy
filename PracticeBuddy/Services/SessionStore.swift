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
    @Published private(set) var lastSavedSessionID: UUID?

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
        PBLog.sessionStore.info("configure(context:) attached")
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
        PBLog.sessionStore.info("reload() started")

        do {
            let descriptor = FetchDescriptor<PracticeSessionModel>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            sessions = try modelContext.fetch(descriptor)
            PBLog.sessionStore.info("reload() loaded \(self.sessions.count, privacy: .public) sessions")
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

    /// Commits the canonical practice session and its typed tool result as one
    /// idempotent SwiftData save. Specialized tool models are inserted by the
    /// tool-specific adapters during their rebuild; the canonical result is
    /// retained here so History never loses attribution.
    @discardableResult
    func savePracticeCompletion(
        _ payload: PracticeSavePayload,
        insertSpecializedResult: ((ModelContext) throws -> Void)? = nil
    ) -> Bool {
        guard let modelContext else {
            PBLog.sessionStore.error("savePracticeCompletion failed: modelContext is nil")
            return false
        }

        let sessionID = payload.sessionID
        let existingDescriptor = FetchDescriptor<PracticeSessionModel>(
            predicate: #Predicate { row in
                row.id == sessionID
            }
        )
        if let existing = try? modelContext.fetch(existingDescriptor).first {
            lastSavedSessionID = existing.id
            return true
        }

        let resultJSON: String? = {
            guard let result = payload.toolResult,
                  let data = try? JSONEncoder().encode(result) else { return nil }
            return String(data: data, encoding: .utf8)
        }()
        let snapshot = payload.snapshot
        let session = PracticeSessionModel(
            id: sessionID,
            date: payload.date,
            durationSeconds: max(0, snapshot.durationSeconds),
            verifiedSeconds: max(0, snapshot.verifiedSeconds),
            unverifiedSeconds: max(0, snapshot.unverifiedSeconds),
            checkInCount: max(0, snapshot.checkInCount),
            missedCheckInCount: max(0, snapshot.missedCheckInCount),
            checkInLogJSON: snapshot.checkInLogJSON,
            notes: payload.notes,
            noteTitle: payload.noteTitle,
            noteFocus: payload.noteFocus,
            noteMoodRaw: payload.noteMoodRaw,
            noteStructuredJSON: payload.noteStructuredJSON,
            launchSource: snapshot.launchContext?.source,
            toolIDRaw: payload.toolResult?.toolID.rawValue,
            toolResultJSON: resultJSON
        )
        modelContext.insert(session)

        do {
            var resultIDs = Set<UUID>()
            for result in ([payload.toolResult].compactMap { $0 } + payload.attachedToolResults)
            where resultIDs.insert(result.id).inserted {
                try insertSpecializedResultIfNeeded(result, context: modelContext)
            }
            try insertSpecializedResult?(modelContext)
            try modelContext.save()
            lastSavedSessionID = session.id
            reload()
            if !sessions.contains(where: { $0.id == session.id }) {
                sessions.insert(session, at: 0)
            }
            pruneToRetentionIfNeeded()
            PBLog.sessionStore.info(
                "savePracticeCompletion committed id=\(session.id.uuidString, privacy: .public)"
            )
            return true
        } catch {
            modelContext.rollback()
            PBLog.sessionStore.error(
                "SwiftData save failed (savePracticeCompletion): \(String(describing: error), privacy: .public)"
            )
            lastAppError = PBAppError(
                title: "Save Failed",
                message: "Your practice session couldn't be saved. Nothing was awarded. Please try again."
            )
            return false
        }
    }

    private func insertSpecializedResultIfNeeded(
        _ result: PracticeToolResult?,
        context: ModelContext
    ) throws {
        guard let result else { return }
        switch result.toolID {
        case .smartLoop:
            guard let data = result.payloadJSON.data(using: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let payload = try JSONDecoder().decode(
                SmartLoopResultPayload.self,
                from: data
            )
            context.insert(
                LoopPracticeLogModel(
                    id: result.id,
                    date: payload.completedAt,
                    loopsCompleted: payload.loopsCompleted,
                    totalWorkSeconds: payload.totalWorkSeconds,
                    loopDurationSeconds: payload.settings.loopDurationSeconds,
                    restSeconds: payload.settings.restDurationSeconds,
                    tempoStartBPM: payload.settings.metronomeEnabled
                        ? payload.settings.startingTempoBPM
                        : 0,
                    tempoEndBPM: payload.settings.metronomeEnabled
                        ? payload.endingTempoBPM
                        : 0,
                    targetLoops: payload.settings.runsUntilStopped
                        ? 0
                        : payload.settings.targetLoops,
                    tagsRaw: payload.tags.joined(separator: ","),
                    tempoLadderEnabled: payload.settings.tempoLadderEnabled,
                    ladderCleanLoopsRequired: payload.settings.tempoLadderEnabled
                        ? payload.settings.cleanLoopsRequired
                        : 0,
                    parentSessionID: payload.parentSessionID,
                    launchSource: payload.launchSource.rawValue,
                    toolVersion: payload.toolVersion
                )
            )
        case .planExecuteReflect:
            guard let data = result.payloadJSON.data(using: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let payload = try JSONDecoder().decode(
                GuidedPracticeResultPayload.self,
                from: data
            )
            context.insert(
                PracticePlanLogModel(
                    id: result.id,
                    date: payload.completedAt,
                    targetMinutes: payload.targetMinutes,
                    actualSeconds: payload.actualSeconds,
                    goalsRaw: payload.goals.map(\.rawValue).joined(separator: ","),
                    blocksRaw: payload.blocks.map(\.kind.rawValue).joined(separator: ","),
                    reflectionWins: payload.reflectionWins,
                    reflectionFix: payload.reflectionFix,
                    reflectionNext: payload.reflectionNext,
                    selfRating: payload.selfRating,
                    parentSessionID: payload.parentSessionID,
                    launchSource: payload.launchSource.rawValue,
                    toolVersion: payload.toolVersion
                )
            )
        case .runThrough:
            guard let data = result.payloadJSON.data(using: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let payload = try JSONDecoder().decode(
                RunThroughResultPayload.self,
                from: data
            )
            context.insert(
                RunThroughModel(
                    id: result.id,
                    date: payload.completedAt,
                    durationSeconds: payload.durationSeconds,
                    audioFilePath: payload.audioFilePath,
                    notes: payload.notes,
                    selfRating: payload.selfRating,
                    noPauseMode: payload.settings.noPauseMode,
                    usedMetronome: payload.settings.useMetronome,
                    markerJSON: {
                        guard let markerData = try? JSONEncoder().encode(payload.markers) else {
                            return ""
                        }
                        return String(data: markerData, encoding: .utf8) ?? ""
                    }(),
                    pieceName: payload.pieceName,
                    parentSessionID: payload.parentSessionID,
                    launchSource: payload.launchSource.rawValue,
                    toolVersion: payload.toolVersion
                )
            )
        case .rhythm:
            guard let data = result.payloadJSON.data(using: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let payload = try JSONDecoder().decode(
                RhythmAccuracyResultPayload.self,
                from: data
            )
            let detailData = try JSONEncoder().encode(payload.summary)
            context.insert(
                RhythmAccuracyTakeModel(
                    id: result.id,
                    date: payload.completedAt,
                    bpm: payload.settings.bpm,
                    beatsAnalyzed: payload.summary.beatsAnalyzed,
                    averageOffsetMs: payload.summary.averageOffsetMs,
                    grooveScore: payload.summary.grooveScore,
                    usedMetronome: payload.settings.pulseMode == .audibleHeadphones,
                    detailJSON: String(data: detailData, encoding: .utf8) ?? "",
                    parentSessionID: payload.parentSessionID,
                    launchSource: payload.launchSource.rawValue,
                    toolVersion: payload.toolVersion
                )
            )
        case .intonation:
            guard let data = result.payloadJSON.data(using: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let payload = try JSONDecoder().decode(
                IntonationResultPayload.self,
                from: data
            )
            let suggestions = payload.result.recommendations.joined(separator: "|")
            let noteData = try JSONEncoder().encode(payload.result.noteScores)
            context.insert(
                ScaleIntonationTakeModel(
                    id: result.id,
                    date: payload.completedAt,
                    exerciseTypeRaw: payload.settings.exercise.rawValue,
                    keyRaw: payload.settings.key.rawValue,
                    modeRaw: payload.settings.mode.rawValue,
                    baseOctave: payload.settings.octave.rawValue,
                    referenceHz: payload.settings.referenceHz,
                    tempoBPM: payload.settings.tempoBPM,
                    noteCount: payload.result.noteScores.count,
                    overallScore: payload.result.overallScore,
                    centeringScore: payload.result.centeringScore,
                    stabilityScore: payload.result.stabilityScore,
                    consistencyScore: payload.result.consistencyScore,
                    meanOffsetCents: payload.result.meanOffsetCents,
                    suggestionsRaw: suggestions,
                    perNoteJSON: String(data: noteData, encoding: .utf8) ?? "",
                    parentSessionID: payload.parentSessionID,
                    launchSource: payload.launchSource.rawValue,
                    toolVersion: payload.toolVersion
                )
            )
        default:
            break
        }
    }

    @discardableResult
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
    ) -> Bool {
        guard let modelContext else {
            PBLog.sessionStore.error("addSession failed: modelContext is nil")
            return false
        }

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
        PBLog.sessionStore.info("addSession() insert id=\(s.id.uuidString, privacy: .public) duration=\(s.durationSeconds, privacy: .public)")

        do {
            try modelContext.save()
            lastSavedSessionID = s.id
            reload()
            if !sessions.contains(where: { $0.id == s.id }) {
                sessions.insert(s, at: 0)
            }
            pruneToRetentionIfNeeded()
            PBLog.sessionStore.info("addSession() committed id=\(s.id.uuidString, privacy: .public)")
            return true
        } catch {
            PBLog.sessionStore.error("SwiftData save failed (addSession): \(String(describing: error), privacy: .public)")
            lastAppError = PBAppError(
                title: "Save Failed",
                message: "Your session couldn't be saved. Please try again."
            )
            return false
        }
    }

    #if DEBUG
    /// Replaces QA-only history on every deterministic populated launch.
    ///
    /// UI tool tests intentionally save real sessions through the production
    /// persistence path. Without a reset, those three-second test saves leaked
    /// into later screenshots and made identical launch arguments produce
    /// different Today and You states. This method is compiled only in DEBUG
    /// and is called only for an explicit QA fixture set.
    func applyStudioQuestFixture() {
        guard let modelContext else { return }

        for session in sessions {
            modelContext.delete(session)
        }

        do {
            try modelContext.save()
            sessions = []
        } catch {
            PBLog.sessionStore.error(
                "Could not reset deterministic session fixtures: \(String(describing: error), privacy: .public)"
            )
            lastAppError = PBAppError(
                title: "Fixture Setup Failed",
                message: "The deterministic practice history could not be prepared."
            )
            return
        }

        let calendar = Calendar.current
        let fixtures: [(id: UUID, daysAgo: Int, duration: Int, verified: Int, title: String, focus: String, mood: String)] = [
            (
                UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                0,
                2_520,
                2_340,
                "Bach: Partita No. 2",
                "Rhythm clarity",
                "focused"
            ),
            (
                UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
                1,
                1_860,
                1_860,
                "Technique and scales",
                "Even tone",
                "energized"
            ),
            (
                UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
                3,
                3_300,
                2_700,
                "Brahms: Sonata in F minor",
                "Dynamic control",
                "reflective"
            ),
            (
                UUID(uuidString: "00000000-0000-4000-8000-000000000004")!,
                5,
                1_440,
                1_260,
                "Sight-reading",
                "Keep moving",
                "calm"
            )
        ]

        for fixture in fixtures.reversed() {
            guard let date = calendar.date(byAdding: .day, value: -fixture.daysAgo, to: Date()) else { continue }
            modelContext.insert(
                PracticeSessionModel(
                    id: fixture.id,
                    date: date,
                    durationSeconds: fixture.duration,
                    verifiedSeconds: fixture.verified,
                    unverifiedSeconds: max(0, fixture.duration - fixture.verified),
                    notes: "A focused session with a clear next step.",
                    noteTitle: fixture.title,
                    noteFocus: fixture.focus,
                    noteMoodRaw: fixture.mood
                )
            )
        }

        do {
            try modelContext.save()
            reload()
        } catch {
            PBLog.sessionStore.error(
                "Could not commit deterministic session fixtures: \(String(describing: error), privacy: .public)"
            )
            lastAppError = PBAppError(
                title: "Fixture Setup Failed",
                message: "The deterministic practice history could not be prepared."
            )
        }
    }
    #endif

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
