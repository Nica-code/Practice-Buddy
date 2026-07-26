import Foundation
import Combine
import UserNotifications
import os

struct PracticeMomentPrompt: Identifiable, Equatable {
    let sessionID: UUID
    let eligibleAt: Date
    var id: UUID { sessionID }
}

@MainActor
final class PracticeSessionCoordinator: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var accumulatedSeconds = 0
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var verifiedSeconds = 0
    @Published private(set) var unverifiedSeconds = 0
    @Published private(set) var checkInStatusMessage: String?
    @Published private(set) var activeTaskIndex = 0
    @Published private(set) var launchContext: PracticeLaunchContext?

    @Published var currentTask = "Open practice"
    @Published var currentPiece = "Your instrument"
    @Published var plannedMinutes = 30
    @Published var tasks: [PracticePlanTask] = []
    @Published var isVerified = true {
        didSet {
            defaults.set(isVerified, forKey: Key.verified)
            if !isVerified {
                appShield.stopShielding()
                clearPendingCheckInNotification()
                checkInStatusMessage = nil
            } else if isRunning {
                beginVerificationIfNeeded()
            }
        }
    }
    @Published var distractionBlockEnabled = true {
        didSet {
            defaults.set(distractionBlockEnabled, forKey: Key.distractionBlockEnabled)
            if !distractionBlockEnabled {
                appShield.stopShielding()
            } else if isRunning, isVerified {
                beginVerificationIfNeeded()
            }
        }
    }
    @Published var checkInsEnabled = true {
        didSet {
            defaults.set(checkInsEnabled, forKey: Key.checkInsEnabled)
            if !checkInsEnabled {
                clearPendingCheckInNotification()
                checkInStatusMessage = nil
            }
        }
    }
    @Published var checkInNotificationsEnabled = true {
        didSet {
            defaults.set(checkInNotificationsEnabled, forKey: Key.checkInNotificationsEnabled)
            if !checkInNotificationsEnabled {
                clearPendingCheckInNotification()
            }
        }
    }
    @Published var checkInInterval: PracticeCheckInInterval = .relaxed {
        didSet {
            defaults.set(checkInInterval.rawValue, forKey: Key.checkInInterval)
            checkInManager.updateConfiguration(promptRange: checkInInterval.rangeSeconds)
        }
    }
    @Published var studioPresented = false
    @Published var reflectionPresented = false
    @Published var momentPrompt: PracticeMomentPrompt?

    let appShield = PracticeAppShieldManager()
    let checkInManager = PracticeCheckInManager()
    let metronome = MetronomeEngine()
    let tuner = TunerEngine()

    private let defaults: UserDefaults
    private var startDate: Date?
    private var ticker: AnyCancellable?
    private var lastAccountedElapsed = 0
    private var backgroundEnteredAt: Date?
    private var sessionNotificationTask: Task<Void, Never>?

    private enum Key {
        static let accumulated = "pb.practice.accumulatedSeconds"
        static let startEpoch = "pb.practice.startEpoch"
        static let running = "pb.practice.isRunning"
        static let verifiedSeconds = "pb.practice.verifiedSeconds"
        static let unverifiedSeconds = "pb.practice.unverifiedSeconds"
        static let checkInCount = "pb.practice.checkinCount"
        static let missedCheckInCount = "pb.practice.missedCheckInCount"
        static let checkInEventsJSON = "pb.practice.checkinEventsJSON"
        static let distractionBlockEnabled = "pb.practice.distractionBlockEnabled"
        static let checkInsEnabled = "pb.practice.checkins.enabled"
        static let checkInNotificationsEnabled = "pb.practice.checkins.notifications"
        static let checkInInterval = "pb.practice.checkins.intervalPreset"
        static let task = "practiquest.practice.currentTask"
        static let piece = "practiquest.practice.currentPiece"
        static let plannedMinutes = "practiquest.practice.plannedMinutes"
        static let verified = "practiquest.practice.verified"
        static let launchContext = "practiquest.practice.launchContext"
        static let tasks = "practiquest.practice.tasks.v2"
        static let lastPiece = "practiquest.practice.lastPiece"
        static let lastTasks = "practiquest.practice.lastTasks.v2"
        static let lastVerified = "practiquest.practice.lastVerified"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        accumulatedSeconds = max(0, defaults.integer(forKey: Key.accumulated))
        verifiedSeconds = max(0, defaults.integer(forKey: Key.verifiedSeconds))
        unverifiedSeconds = max(0, defaults.integer(forKey: Key.unverifiedSeconds))
        isRunning = defaults.bool(forKey: Key.running)
        currentTask = defaults.string(forKey: Key.task) ?? "Open practice"
        currentPiece = defaults.string(forKey: Key.piece) ?? "Your instrument"

        let savedMinutes = defaults.integer(forKey: Key.plannedMinutes)
        plannedMinutes = savedMinutes > 0 ? savedMinutes : 30
        isVerified = defaults.object(forKey: Key.verified) as? Bool ?? true
        distractionBlockEnabled = defaults.object(forKey: Key.distractionBlockEnabled) as? Bool ?? true
        checkInsEnabled = defaults.object(forKey: Key.checkInsEnabled) as? Bool ?? true
        checkInNotificationsEnabled = defaults.object(forKey: Key.checkInNotificationsEnabled) as? Bool ?? true
        checkInInterval = PracticeCheckInInterval(
            rawValue: defaults.string(forKey: Key.checkInInterval) ?? ""
        ) ?? .relaxed

        if let data = defaults.data(forKey: Key.tasks),
           let decoded = try? JSONDecoder().decode([PracticePlanTask].self, from: data) {
            tasks = Self.sanitizedTasks(decoded)
        }
        if let data = defaults.data(forKey: Key.launchContext) {
            launchContext = try? JSONDecoder().decode(PracticeLaunchContext.self, from: data)
        }

        let checkInCount = max(0, defaults.integer(forKey: Key.checkInCount))
        let missedCheckInCount = max(0, defaults.integer(forKey: Key.missedCheckInCount))
        let events = Self.decodeCheckInEvents(defaults.string(forKey: Key.checkInEventsJSON) ?? "")
        checkInManager.updateConfiguration(promptRange: checkInInterval.rangeSeconds)
        checkInManager.restoreCounters(
            checkInCount: checkInCount,
            missedCheckInCount: missedCheckInCount,
            events: events
        )

        let epoch = defaults.double(forKey: Key.startEpoch)
        if isRunning, epoch > 0 {
            startDate = Date(timeIntervalSince1970: epoch)
        } else {
            isRunning = false
            startDate = nil
        }

        recalculateElapsed()
        lastAccountedElapsed = elapsedSeconds
        updateCurrentTask()
        if isRunning {
            startTicker()
            beginVerificationIfNeeded()
        }
    }

    deinit {
        ticker?.cancel()
        sessionNotificationTask?.cancel()
    }

    var state: PracticeDockState {
        if isRunning {
            return .running(elapsedSeconds: elapsedSeconds, task: currentTask, isVerified: verificationMechanismActive)
        }
        if elapsedSeconds > 0 {
            return .paused(elapsedSeconds: elapsedSeconds, task: currentTask)
        }
        if !tasks.isEmpty {
            return .planned(title: currentTask, durationMinutes: plannedMinutes)
        }
        return .idle
    }

    var progress: Double {
        let target = max(60, plannedDurationSeconds)
        return min(Double(elapsedSeconds) / Double(target), 1)
    }

    var plannedDurationSeconds: Int {
        if !tasks.isEmpty {
            return max(60, tasks.reduce(0) { $0 + max(1, $1.minutes) * 60 })
        }
        return max(60, plannedMinutes * 60)
    }

    var verificationMechanismActive: Bool {
        isVerified
            && distractionBlockEnabled
            && appShield.isShieldingActive
            && appShield.isAuthorized
            && appShield.selectedAppsCount > 0
    }

    var verificationConfigured: Bool {
        isVerified
            && distractionBlockEnabled
            && appShield.isVerificationConfigured
    }

    var checkInFlowActive: Bool {
        verificationMechanismActive && checkInsEnabled
    }

    var taskProgress: [PracticeTaskProgress] {
        var cursor = 0
        return tasks.enumerated().map { index, task in
            let taskSeconds = max(1, task.minutes) * 60
            let start = cursor
            let end = cursor + taskSeconds
            cursor = end
            let isComplete = elapsedSeconds >= end
            let isCurrent = !isComplete && elapsedSeconds >= start && elapsedSeconds < end
            let intoTask = max(0, min(taskSeconds, elapsedSeconds - start))
            return PracticeTaskProgress(
                id: task.id,
                title: task.title,
                minutes: task.minutes,
                progress: isComplete ? 1 : Double(intoTask) / Double(taskSeconds),
                remainingSeconds: isComplete ? 0 : max(0, end - elapsedSeconds),
                isCurrent: isCurrent,
                isComplete: isComplete
            )
        }
    }

    var snapshot: PracticeSessionSnapshot {
        PracticeSessionSnapshot(
            durationSeconds: max(0, elapsedSeconds),
            verifiedSeconds: max(0, verifiedSeconds),
            unverifiedSeconds: max(0, unverifiedSeconds),
            checkInCount: checkInManager.checkInCount,
            missedCheckInCount: checkInManager.missedCheckInCount,
            checkInLogJSON: checkInManager.eventsJSON(),
            piece: currentPiece,
            tasks: tasks,
            launchContext: launchContext
        )
    }

    func quickStart() {
        if elapsedSeconds > 0 {
            resume()
            studioPresented = true
            PracticeAnalytics.record(.practiceStarted(source: "dock_resume"))
            return
        }

        let lastPiece = defaults.string(forKey: Key.lastPiece) ?? "Your instrument"
        let lastVerified = defaults.object(forKey: Key.lastVerified) as? Bool ?? true
        let lastTasks: [PracticePlanTask]
        if let data = defaults.data(forKey: Key.lastTasks),
           let decoded = try? JSONDecoder().decode([PracticePlanTask].self, from: data),
           !decoded.isEmpty {
            lastTasks = Self.sanitizedTasks(decoded)
        } else {
            lastTasks = [PracticePlanTask(title: "Focused practice", minutes: 30)]
        }

        startPlan(
            piece: lastPiece,
            tasks: lastTasks,
            verified: lastVerified,
            launchContext: nil,
            source: "dock"
        )
    }

    func start(
        task: String,
        piece: String,
        durationMinutes: Int,
        verified: Bool,
        launchContext: PracticeLaunchContext? = nil
    ) {
        startPlan(
            piece: piece,
            tasks: [
                PracticePlanTask(
                    title: task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Focused practice"
                        : task,
                    minutes: max(1, durationMinutes)
                )
            ],
            verified: verified,
            launchContext: launchContext,
            source: "setup"
        )
    }

    func startPlan(
        piece: String,
        tasks: [PracticePlanTask],
        verified: Bool,
        launchContext: PracticeLaunchContext?,
        source: String = "setup"
    ) {
        reset(keepLastSetup: true)
        let cleanTasks = Self.sanitizedTasks(tasks)
        self.tasks = cleanTasks.isEmpty
            ? [PracticePlanTask(title: "Focused practice", minutes: 30)]
            : cleanTasks
        currentPiece = piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Your instrument"
            : piece.trimmingCharacters(in: .whitespacesAndNewlines)
        plannedMinutes = self.tasks.reduce(0) { $0 + $1.minutes }
        isVerified = verified
        self.launchContext = launchContext
        activeTaskIndex = 0
        currentTask = self.tasks.first?.title ?? "Focused practice"
        persistPlan()
        saveAsLastSetup()
        resume()
        studioPresented = true
        PracticeAnalytics.record(.practiceStarted(source: source))
    }

    func resume() {
        guard !isRunning else { return }
        startDate = Date()
        isRunning = true
        lastAccountedElapsed = elapsedSeconds
        persistClock()
        startTicker()
        beginVerificationIfNeeded()
        queueTaskNotifications()
        updateLiveActivity()
    }

    func pause() {
        guard isRunning else { return }
        recalculateElapsed()
        accountElapsedDelta()
        accumulatedSeconds = elapsedSeconds
        isRunning = false
        startDate = nil
        persistClock()
        persistCounters()
        stopTicker()
        appShield.stopShielding()
        clearPendingNotifications()
        updateLiveActivity()
        PracticeAnalytics.record(.practicePaused)
    }

    func requestFinish() {
        pause()
        guard elapsedSeconds > 0 else {
            studioPresented = false
            return
        }
        reflectionPresented = true
    }

    func respondToCheckIn(focusTag: String = "") {
        checkInManager.respond(focusTag: focusTag)
        checkInStatusMessage = focusTag.isEmpty
            ? "Check-in confirmed."
            : "Check-in confirmed · \(focusTag)"
        persistCounters()
        queueCheckInNotification()
    }

    func handleScenePhase(isActive: Bool) {
        if isActive {
            guard let backgroundEnteredAt else {
                updateLiveActivity()
                return
            }
            self.backgroundEnteredAt = nil
            guard isRunning else { return }

            recalculateElapsed()
            let backgroundSeconds = max(0, Int(Date().timeIntervalSince(backgroundEnteredAt)))
            if backgroundSeconds > 0 {
                unverifiedSeconds += backgroundSeconds
                lastAccountedElapsed = elapsedSeconds
                if isVerified {
                    checkInStatusMessage = "Background time counted as unverified."
                }
                persistCounters()
            }
            clearPendingCheckInNotification()
            queueTaskNotifications()
            updateLiveActivity()
        } else if isRunning {
            backgroundEnteredAt = Date()
            queueCheckInNotification()
            updateLiveActivity()
        }
    }

    func completeAfterSave(savedSessionID: UUID? = nil) {
        let completedContext = launchContext
        let completedDuration = elapsedSeconds
        PracticeLiveActivityManager.shared.end()
        stopAllTools()
        if let questID = completedContext?.questID, !questID.isEmpty {
            PracticeQuestProgressStore.shared.record(questID)
        }
        PracticeAnalytics.record(.practiceSaved(durationSeconds: elapsedSeconds))
        reset(keepLastSetup: true)
        reflectionPresented = false
        studioPresented = false
        if let savedSessionID, completedDuration >= 5 * 60 {
            momentPrompt = PracticeMomentPrompt(sessionID: savedSessionID, eligibleAt: .now)
        }
    }

    @discardableResult
    func complete() -> Int {
        let duration = elapsedSeconds
        completeAfterSave()
        return duration
    }

    func discard() {
        PracticeAnalytics.record(.practiceAbandoned(durationSeconds: elapsedSeconds))
        PracticeLiveActivityManager.shared.end()
        stopAllTools()
        reset(keepLastSetup: true)
        reflectionPresented = false
        studioPresented = false
    }

    func configureVerificationIfNeeded() async {
        guard isVerified, distractionBlockEnabled else { return }
        await appShield.configureAutoVerificationDefaults()
        if isRunning {
            await appShield.startShieldingIfPossible()
        }
    }

    private func reset(keepLastSetup: Bool) {
        stopTicker()
        sessionNotificationTask?.cancel()
        sessionNotificationTask = nil
        isRunning = false
        accumulatedSeconds = 0
        elapsedSeconds = 0
        verifiedSeconds = 0
        unverifiedSeconds = 0
        lastAccountedElapsed = 0
        startDate = nil
        backgroundEnteredAt = nil
        activeTaskIndex = 0
        currentTask = "Open practice"
        currentPiece = "Your instrument"
        plannedMinutes = 30
        tasks = []
        launchContext = nil
        checkInStatusMessage = nil
        checkInManager.reset()
        appShield.stopShielding()
        clearPendingNotifications()
        if !keepLastSetup {
            defaults.removeObject(forKey: Key.lastPiece)
            defaults.removeObject(forKey: Key.lastTasks)
            defaults.removeObject(forKey: Key.lastVerified)
        }
        persistPlan()
        persistClock()
        persistCounters()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.recalculateElapsed()
                self.accountElapsedDelta()
                self.updateCurrentTask()
                self.updateLiveActivity()
            }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func recalculateElapsed() {
        if isRunning, let startDate {
            elapsedSeconds = accumulatedSeconds + max(0, Int(Date().timeIntervalSince(startDate)))
        } else {
            elapsedSeconds = accumulatedSeconds
        }
    }

    private func accountElapsedDelta() {
        guard isRunning else { return }
        let delta = max(0, elapsedSeconds - lastAccountedElapsed)
        guard delta > 0 else { return }

        for _ in 0..<delta {
            if checkInFlowActive {
                switch checkInManager.tick(enabled: true) {
                case .none:
                    break
                case .triggered:
                    checkInStatusMessage = "Check-in required."
                case .missed:
                    checkInStatusMessage = "Missed check-in. Session paused."
                    unverifiedSeconds += 1
                    lastAccountedElapsed += 1
                    persistCounters()
                    pauseAfterMissedCheckIn()
                    return
                }
            }

            if checkInFlowActive && checkInManager.isAwaitingResponse {
                unverifiedSeconds += 1
            } else if verificationMechanismActive {
                verifiedSeconds += 1
            } else {
                unverifiedSeconds += 1
            }
            lastAccountedElapsed += 1
        }
        persistCounters()
    }

    private func pauseAfterMissedCheckIn() {
        accumulatedSeconds = elapsedSeconds
        isRunning = false
        startDate = nil
        persistClock()
        stopTicker()
        appShield.stopShielding()
        clearPendingNotifications()
        updateLiveActivity()
    }

    private func updateCurrentTask() {
        guard !tasks.isEmpty else { return }
        let rows = taskProgress
        let index = rows.firstIndex(where: \.isCurrent)
            ?? rows.firstIndex(where: { !$0.isComplete })
            ?? max(rows.count - 1, 0)
        activeTaskIndex = min(max(index, 0), max(tasks.count - 1, 0))
        currentTask = tasks[activeTaskIndex].title
    }

    private func beginVerificationIfNeeded() {
        guard isVerified, distractionBlockEnabled else { return }
        Task {
            await appShield.startShieldingIfPossible()
            if !appShield.isShieldingActive {
                checkInStatusMessage = appShield.statusLine
            }
        }
    }

    private func saveAsLastSetup() {
        defaults.set(currentPiece, forKey: Key.lastPiece)
        defaults.set(isVerified, forKey: Key.lastVerified)
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: Key.lastTasks)
        }
    }

    private func persistPlan() {
        defaults.set(currentTask, forKey: Key.task)
        defaults.set(currentPiece, forKey: Key.piece)
        defaults.set(plannedMinutes, forKey: Key.plannedMinutes)
        defaults.set(isVerified, forKey: Key.verified)
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: Key.tasks)
        }
        if let launchContext, let data = try? JSONEncoder().encode(launchContext) {
            defaults.set(data, forKey: Key.launchContext)
        } else {
            defaults.removeObject(forKey: Key.launchContext)
        }
    }

    private func persistClock() {
        defaults.set(accumulatedSeconds, forKey: Key.accumulated)
        defaults.set(startDate?.timeIntervalSince1970 ?? 0, forKey: Key.startEpoch)
        defaults.set(isRunning, forKey: Key.running)
    }

    private func persistCounters() {
        defaults.set(verifiedSeconds, forKey: Key.verifiedSeconds)
        defaults.set(unverifiedSeconds, forKey: Key.unverifiedSeconds)
        defaults.set(checkInManager.checkInCount, forKey: Key.checkInCount)
        defaults.set(checkInManager.missedCheckInCount, forKey: Key.missedCheckInCount)
        defaults.set(checkInManager.eventsJSON(), forKey: Key.checkInEventsJSON)
    }

    private func updateLiveActivity() {
        guard isRunning || elapsedSeconds > 0 else {
            PracticeLiveActivityManager.shared.end()
            return
        }

        let remaining = max(0, plannedDurationSeconds - elapsedSeconds)
        let verified = DurationFormatter.string(from: verifiedSeconds)
        let unverified = DurationFormatter.string(from: unverifiedSeconds)
        PracticeLiveActivityManager.shared.ensureUpdated(
            isRunning: isRunning,
            mode: .session(
                title: currentPiece,
                subtitle: "\(currentTask) · V \(verified) · U \(unverified)",
                elapsedSeconds: elapsedSeconds,
                remainingSeconds: remaining,
                progress: progress
            )
        )
    }

    private func stopAllTools() {
        metronome.stop()
        tuner.stopListening()
        tuner.stopReferenceTone()
    }

    private func queueTaskNotifications() {
        sessionNotificationTask?.cancel()
        sessionNotificationTask = Task { [weak self] in
            await self?.syncTaskNotifications()
        }
    }

    private func syncTaskNotifications() async {
        let center = UNUserNotificationCenter.current()
        let prefix = "pb.practice.session.task."
        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        if !existing.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existing)
        }

        guard isRunning, !tasks.isEmpty else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral else { return }

        var boundary = 0
        for (index, task) in tasks.enumerated() {
            boundary += max(1, task.minutes) * 60
            let secondsFromNow = boundary - elapsedSeconds
            guard secondsFromNow > 0 else { continue }

            let content = UNMutableNotificationContent()
            let isLast = index == tasks.count - 1
            content.title = isLast ? "Session complete" : "Next: \(task.title)"
            content.body = isLast ? "Your practice plan is complete." : "\(task.title) starts now."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "\(prefix)\(index)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(max(1, secondsFromNow)),
                    repeats: false
                )
            )
            do {
                try await center.add(request)
            } catch {
                PBLog.sessionStore.error(
                    "Practice task notification failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func queueCheckInNotification() {
        guard checkInNotificationsEnabled, checkInFlowActive, isRunning else { return }
        let center = UNUserNotificationCenter.current()
        clearPendingCheckInNotification()
        let content = UNMutableNotificationContent()
        content.title = "Practice check-in"
        content.body = "Still practicing? Open PractiQuest to confirm."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "pb.practice.checkin.prompt",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(max(10, checkInManager.secondsUntilPrompt)),
                repeats: false
            )
        )
        center.add(request) { error in
            if let error {
                PBLog.sessionStore.error(
                    "Practice check-in notification failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func clearPendingCheckInNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["pb.practice.checkin.prompt"]
        )
    }

    private func clearPendingNotifications() {
        sessionNotificationTask?.cancel()
        sessionNotificationTask = nil
        let center = UNUserNotificationCenter.current()
        clearPendingCheckInNotification()
        Task {
            let identifiers = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix("pb.practice.session.task.") }
            if !identifiers.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: identifiers)
            }
        }
    }

    private static func sanitizedTasks(_ tasks: [PracticePlanTask]) -> [PracticePlanTask] {
        tasks.compactMap { task in
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return PracticePlanTask(id: task.id, title: title, minutes: max(1, task.minutes))
        }
    }

    private static func decodeCheckInEvents(_ raw: String) -> [PracticeCheckInEvent] {
        guard let data = raw.data(using: .utf8),
              let events = try? JSONDecoder().decode([PracticeCheckInEvent].self, from: data) else {
            return []
        }
        return events
    }
}

enum PracticeAnalytics {
    enum Event {
        case onboardingCompleted
        case practiceStarted(source: String)
        case practicePaused
        case practiceSaved(durationSeconds: Int)
        case practiceAbandoned(durationSeconds: Int)
        case dockOpened(state: String)
        case toolOpened(String)
        case questEntered(String)
        case duelEntered
        case signInConversion(source: String)
        case routeOpened(depth: Int)
        case profileUpgradeCompleted
        case smartCoachPreview
        case practiceMomentPublished
        case avatarRoomEdited

        var name: String {
            switch self {
            case .onboardingCompleted: "onboarding_completed"
            case .practiceStarted: "practice_started"
            case .practicePaused: "practice_paused"
            case .practiceSaved: "practice_saved"
            case .practiceAbandoned: "practice_abandoned"
            case .dockOpened: "practice_dock_opened"
            case .toolOpened: "practice_tool_opened"
            case .questEntered: "quest_entered"
            case .duelEntered: "duel_entered"
            case .signInConversion: "sign_in_conversion"
            case .routeOpened: "route_opened"
            case .profileUpgradeCompleted: "profile_upgrade_completed"
            case .smartCoachPreview: "smart_coach_preview"
            case .practiceMomentPublished: "practice_moment_published"
            case .avatarRoomEdited: "avatar_room_edited"
            }
        }

        var safeDimensions: [String: String] {
            switch self {
            case .practiceStarted(let source):
                ["source": source]
            case .practiceSaved(let durationSeconds), .practiceAbandoned(let durationSeconds):
                ["duration_bucket": Self.durationBucket(durationSeconds)]
            case .dockOpened(let state):
                ["state": state]
            case .toolOpened(let toolID), .questEntered(let toolID):
                ["item_id": toolID]
            case .signInConversion(let source):
                ["source": source]
            case .routeOpened(let depth):
                ["depth": String(max(1, depth))]
            case .onboardingCompleted, .practicePaused, .duelEntered, .profileUpgradeCompleted, .smartCoachPreview, .practiceMomentPublished, .avatarRoomEdited:
                [:]
            }
        }

        private static func durationBucket(_ seconds: Int) -> String {
            switch max(0, seconds) {
            case ..<300: "under_5m"
            case ..<900: "5_to_15m"
            case ..<1800: "15_to_30m"
            case ..<3600: "30_to_60m"
            default: "over_60m"
            }
        }
    }

    static func record(_ event: Event) {
        // Content-free by design. Do not add notes, messages, audio, profile text,
        // friend codes, or any user-authored strings to this payload.
        let countKey = "practiquest.analytics.\(event.name).count"
        let nextCount = UserDefaults.standard.integer(forKey: countKey) + 1
        UserDefaults.standard.set(nextCount, forKey: countKey)

        if !event.safeDimensions.isEmpty,
           let data = try? JSONEncoder().encode(event.safeDimensions) {
            UserDefaults.standard.set(data, forKey: "practiquest.analytics.\(event.name).last_dimensions")
        }
        PBLog.sessionStore.info("Analytics event: \(event.name, privacy: .public) count=\(nextCount, privacy: .public)")
    }
}
