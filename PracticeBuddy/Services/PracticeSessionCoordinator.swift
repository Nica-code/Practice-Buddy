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
    @Published private(set) var activeSessionID: UUID
    @Published private(set) var isRunning = false
    @Published private(set) var accumulatedSeconds = 0
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var verifiedSeconds = 0
    @Published private(set) var unverifiedSeconds = 0
    @Published private(set) var verificationStatusMessage: String?
    @Published private(set) var activeTaskIndex = 0
    @Published private(set) var launchContext: PracticeLaunchContext?
    @Published private(set) var activeToolID: PracticeToolID?
    @Published private(set) var toolLaunchContext: PracticeToolLaunchContext?
    @Published private(set) var latestToolResult: PracticeToolResult?
    @Published private(set) var attachedToolResults: [PracticeToolResult] = []
    @Published private(set) var nestedToolID: PracticeToolID?
    @Published private(set) var toolErrorMessage: String?
    @Published private(set) var pendingQuestIDs: Set<String> = []
    @Published private(set) var toolActivityState: PracticeActivityState?

    @Published var currentTask = "Open practice"
    @Published var currentPiece = "Your instrument"
    @Published var plannedMinutes = 30
    @Published var tasks: [PracticePlanTask] = []
    @Published var isVerified = true {
        didSet {
            defaults.set(isVerified, forKey: Key.verified)
            if !isVerified {
                appShield.stopShielding()
                verificationStatusMessage = nil
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
    @Published var studioPresented = false
    @Published var reflectionPresented = false
    @Published var momentPrompt: PracticeMomentPrompt?

    let appShield = PracticeAppShieldManager()
    let metronome = MetronomeEngine(managesAudioSession: false)
    let tuner = TunerEngine(managesAudioSession: false)
    let audioSession = PracticeAudioSessionCoordinator()

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
        static let distractionBlockEnabled = "pb.practice.distractionBlockEnabled"
        static let task = "practiquest.practice.currentTask"
        static let piece = "practiquest.practice.currentPiece"
        static let plannedMinutes = "practiquest.practice.plannedMinutes"
        static let verified = "practiquest.practice.verified"
        static let launchContext = "practiquest.practice.launchContext"
        static let tasks = "practiquest.practice.tasks.v2"
        static let lastPiece = "practiquest.practice.lastPiece"
        static let lastTasks = "practiquest.practice.lastTasks.v2"
        static let lastVerified = "practiquest.practice.lastVerified"
        static let activeSessionID = "practiquest.practice.activeSessionID"
        static let activeToolID = "practiquest.practice.activeToolID"
        static let toolLaunchContext = "practiquest.practice.toolLaunchContext"
        static let latestToolResult = "practiquest.practice.latestToolResult"
        static let attachedToolResults = "practiquest.practice.attachedToolResults"
        static let nestedToolID = "practiquest.practice.nestedToolID"
        static let pendingQuestIDs = "practiquest.practice.pendingQuestIDs"
        static let toolActivityState = "practiquest.practice.toolActivityState"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        activeSessionID = defaults.string(forKey: Key.activeSessionID)
            .flatMap(UUID.init(uuidString:))
            ?? UUID()
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

        if let data = defaults.data(forKey: Key.tasks),
           let decoded = try? JSONDecoder().decode([PracticePlanTask].self, from: data) {
            tasks = Self.sanitizedTasks(decoded)
        }
        if let data = defaults.data(forKey: Key.launchContext) {
            launchContext = try? JSONDecoder().decode(PracticeLaunchContext.self, from: data)
        }
        if let rawToolID = defaults.string(forKey: Key.activeToolID) {
            activeToolID = PracticeToolID(rawValue: rawToolID)
        }
        if let data = defaults.data(forKey: Key.toolLaunchContext) {
            toolLaunchContext = try? JSONDecoder().decode(
                PracticeToolLaunchContext.self,
                from: data
            )
        }
        if let data = defaults.data(forKey: Key.latestToolResult) {
            latestToolResult = try? JSONDecoder().decode(
                PracticeToolResult.self,
                from: data
            )
        }
        if let data = defaults.data(forKey: Key.attachedToolResults) {
            attachedToolResults = (try? JSONDecoder().decode(
                [PracticeToolResult].self,
                from: data
            )) ?? []
        }
        if let rawNestedToolID = defaults.string(forKey: Key.nestedToolID) {
            nestedToolID = PracticeToolID(rawValue: rawNestedToolID)
        }
        if let values = defaults.stringArray(forKey: Key.pendingQuestIDs) {
            pendingQuestIDs = Set(values.filter { !$0.isEmpty })
        }
        if let data = defaults.data(forKey: Key.toolActivityState) {
            toolActivityState = try? JSONDecoder().decode(
                PracticeActivityState.self,
                from: data
            )
        }

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
        if let activeToolID {
            if isRunning {
                return .focusedToolRunning(
                    tool: activeToolID,
                    elapsedSeconds: elapsedSeconds
                )
            }
            if elapsedSeconds > 0 {
                return .focusedToolPaused(
                    tool: activeToolID,
                    elapsedSeconds: elapsedSeconds
                )
            }
        }
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
            piece: currentPiece,
            tasks: tasks,
            launchContext: launchContext
        )
    }

    var hasActivePractice: Bool {
        isRunning || elapsedSeconds > 0 || !tasks.isEmpty
    }

    var isFocusedToolSession: Bool {
        activeToolID != nil
    }

    var toolElapsedSeconds: Int {
        toolActivityState?.elapsed() ?? 0
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
        preparePlan(
            piece: piece,
            tasks: tasks,
            verified: verified,
            launchContext: launchContext
        )
        resume()
        studioPresented = true
        PracticeAnalytics.record(.practiceStarted(source: source))
    }

    /// Configures a recoverable plan without starting its clock. This is used
    /// by planned Practice Dock states and keeps "planned" distinct from a
    /// zero-second paused session.
    func preparePlan(
        piece: String,
        tasks: [PracticePlanTask],
        verified: Bool,
        launchContext: PracticeLaunchContext?
    ) {
        reset(keepLastSetup: true)
        activeSessionID = launchContext?.sessionID ?? UUID()
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
        persistActivityIdentity()
    }

    /// Starts a standalone practice tool through the same timer, persistence,
    /// verification, and Dock runtime as Practice Studio. Contextual tools use
    /// `attachTool` instead so the parent session clock remains untouched.
    @discardableResult
    func beginFocusedTool(
        _ toolID: PracticeToolID,
        title: String? = nil,
        durationMinutes: Int = 10,
        verified: Bool = false,
        source: PracticeLaunchSource = .library,
        questID: String? = nil,
        smartCoachPlanID: String? = nil
    ) -> Bool {
        guard !hasActivePractice, activeToolID == nil else {
            reportToolError(
                "Another practice activity is already open. Finish it or attach this tool to that session."
            )
            return false
        }
        let sessionID = UUID()
        let toolContext = PracticeToolLaunchContext(
            toolID: toolID,
            source: source,
            parentSessionID: nil,
            questID: questID,
            smartCoachPlanID: smartCoachPlanID
        )
        preparePlan(
            piece: "Your instrument",
            tasks: [
                PracticePlanTask(
                    title: title ?? toolID.title,
                    minutes: max(1, durationMinutes)
                )
            ],
            verified: verified,
            launchContext: PracticeLaunchContext(
                source: source,
                toolID: toolID,
                questID: questID,
                smartCoachPlanID: smartCoachPlanID,
                sessionID: sessionID
            )
        )
        activeSessionID = sessionID
        activeToolID = toolID
        toolLaunchContext = toolContext
        latestToolResult = nil
        attachedToolResults = []
        nestedToolID = nil
        toolErrorMessage = nil
        toolActivityState = PracticeActivityState(
            sessionID: sessionID,
            kind: .focusedTool(toolID),
            phase: .ready,
            launchContext: toolContext
        )
        persistActivityIdentity()
        resume()
        PracticeAnalytics.record(.practiceStarted(source: source.rawValue))
        return true
    }

    @discardableResult
    func attachTool(
        _ toolID: PracticeToolID,
        source: PracticeLaunchSource = .activeSession,
        questID: String? = nil
    ) -> PracticeToolLaunchContext? {
        if let activeToolID {
            guard activeToolID == toolID else {
                reportToolError(
                    "\(activeToolID.title) is already active. Finish or close it before opening \(toolID.title)."
                )
                return nil
            }
            return toolLaunchContext
        }
        let context = PracticeToolLaunchContext(
            toolID: toolID,
            source: source,
            parentSessionID: activeSessionID,
            questID: questID,
            smartCoachPlanID: launchContext?.smartCoachPlanID
        )
        activeToolID = toolID
        toolLaunchContext = context
        latestToolResult = nil
        toolErrorMessage = nil
        toolActivityState = PracticeActivityState(
            sessionID: activeSessionID,
            kind: .focusedTool(toolID),
            phase: .ready,
            launchContext: context
        )
        persistActivityIdentity()
        return context
    }

    func startToolActivity(recoveryPayloadJSON: String? = nil) {
        guard let activeToolID else { return }
        var state = toolActivityState ?? PracticeActivityState(
            sessionID: activeSessionID,
            kind: .focusedTool(activeToolID),
            launchContext: toolLaunchContext
        )
        guard state.phase != .running else { return }
        state.phase = .running
        state.phaseStartedAt = .now
        if let recoveryPayloadJSON {
            state.recoveryPayloadJSON = recoveryPayloadJSON
        }
        toolActivityState = state
        persistActivityIdentity()
    }

    func pauseToolActivity(recoveryPayloadJSON: String? = nil) {
        guard var state = toolActivityState else { return }
        if state.phase == .running {
            state.accumulatedSeconds = state.elapsed()
        }
        state.phase = .paused
        state.phaseStartedAt = nil
        if let recoveryPayloadJSON {
            state.recoveryPayloadJSON = recoveryPayloadJSON
        }
        toolActivityState = state
        persistActivityIdentity()
    }

    func updateToolRecoveryPayload(_ payloadJSON: String?) {
        guard var state = toolActivityState else { return }
        state.recoveryPayloadJSON = payloadJSON
        toolActivityState = state
        persistActivityIdentity()
    }

    func completeTool(_ result: PracticeToolResult) {
        guard result.sessionID == activeSessionID else {
            toolErrorMessage = "This result belongs to a different practice session."
            return
        }
        latestToolResult = result
        if var state = toolActivityState {
            state.accumulatedSeconds = result.durationSeconds
            state.phase = .completed
            state.phaseStartedAt = nil
            toolActivityState = state
        }
        persistActivityIdentity()
    }

    /// Adds a contextual or nested tool result to the parent practice without
    /// replacing the parent tool's own result or ending its timer.
    func attachCompletedToolResult(_ result: PracticeToolResult) {
        guard result.sessionID == activeSessionID else {
            reportToolError("This result belongs to a different practice session.")
            return
        }
        attachedToolResults.removeAll { $0.id == result.id }
        attachedToolResults.append(result)
        persistActivityIdentity()
    }

    @discardableResult
    func beginNestedTool(_ toolID: PracticeToolID) -> PracticeToolLaunchContext? {
        guard activeToolID == .planExecuteReflect else {
            reportToolError("Nested tools are available while executing a guided plan.")
            return nil
        }
        guard nestedToolID == nil || nestedToolID == toolID else {
            reportToolError(
                "\(nestedToolID?.title ?? "Another tool") is already open. Close it before starting \(toolID.title)."
            )
            return nil
        }
        nestedToolID = toolID
        persistActivityIdentity()
        return PracticeToolLaunchContext(
            toolID: toolID,
            source: .activeSession,
            parentSessionID: activeSessionID,
            questID: toolLaunchContext?.questID,
            smartCoachPlanID: toolLaunchContext?.smartCoachPlanID
        )
    }

    func endNestedTool(_ toolID: PracticeToolID) {
        guard nestedToolID == toolID else { return }
        audioSession.releaseCurrentOwner()
        nestedToolID = nil
        persistActivityIdentity()
    }

    func detachTool() {
        audioSession.releaseCurrentOwner()
        activeToolID = nil
        toolLaunchContext = nil
        nestedToolID = nil
        toolErrorMessage = nil
        toolActivityState = nil
        persistActivityIdentity()
    }

    func reportToolError(_ message: String) {
        toolErrorMessage = message
    }

    /// Queues progression until the canonical practice session has committed.
    /// Tools must never award quest progress before `completeAfterSave`.
    func queueQuestCompletion(_ questID: String) {
        guard !questID.isEmpty else { return }
        pendingQuestIDs.insert(questID)
        persistActivityIdentity()
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
                    verificationStatusMessage = "Background time counted as unverified."
                }
                persistCounters()
            }
            queueTaskNotifications()
            updateLiveActivity()
        } else if isRunning {
            backgroundEnteredAt = Date()
            updateLiveActivity()
        }
    }

    func completeAfterSave(savedSessionID: UUID? = nil) {
        let completedContext = launchContext
        let completedDuration = elapsedSeconds
        var completedQuestIDs = pendingQuestIDs
        if let questID = completedContext?.questID, !questID.isEmpty {
            completedQuestIDs.insert(questID)
        }
        PracticeLiveActivityManager.shared.end()
        stopAllTools()
        for questID in completedQuestIDs.sorted() {
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

    #if DEBUG
    func resetForDeterministicQA() {
        PracticeLiveActivityManager.shared.end()
        stopAllTools()
        reset(keepLastSetup: true)
        reflectionPresented = false
        studioPresented = false
        momentPrompt = nil
    }

    /// Moves a focused tool clock to a deterministic elapsed value without
    /// making UI tests wait in real time. A standalone focused tool owns the
    /// canonical practice clock as well, so both clocks must move together;
    /// otherwise the tool panel and persistent Dock display contradictory
    /// durations. Contextual tools deliberately leave the parent clock alone.
    ///
    /// This is intentionally DEBUG-only so production timing always comes from
    /// real timestamps.
    func setToolElapsedForDeterministicQA(
        _ seconds: Int,
        phase: PracticeActivityPhase = .running
    ) {
        guard var state = toolActivityState else { return }
        let normalizedSeconds = max(0, seconds)
        state.accumulatedSeconds = normalizedSeconds
        state.phase = phase
        state.phaseStartedAt = phase == .running ? .now : nil
        toolActivityState = state

        if toolLaunchContext?.parentSessionID == nil {
            accumulatedSeconds = normalizedSeconds
            elapsedSeconds = normalizedSeconds
            lastAccountedElapsed = normalizedSeconds
            if phase == .running {
                isRunning = true
                startDate = .now
                startTicker()
            } else {
                isRunning = false
                startDate = nil
                stopTicker()
            }
            persistClock()
        }
        persistActivityIdentity()
    }
    #endif

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
        activeSessionID = UUID()
        activeToolID = nil
        toolLaunchContext = nil
        latestToolResult = nil
        attachedToolResults = []
        nestedToolID = nil
        toolErrorMessage = nil
        pendingQuestIDs = []
        toolActivityState = nil
        verificationStatusMessage = nil
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
        persistActivityIdentity()
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

        if verificationMechanismActive {
            verifiedSeconds += delta
        } else {
            unverifiedSeconds += delta
        }
        lastAccountedElapsed += delta
        persistCounters()
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
                verificationStatusMessage = appShield.statusLine
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
    }

    private func persistActivityIdentity() {
        defaults.set(activeSessionID.uuidString, forKey: Key.activeSessionID)
        if let activeToolID {
            defaults.set(activeToolID.rawValue, forKey: Key.activeToolID)
        } else {
            defaults.removeObject(forKey: Key.activeToolID)
        }
        if let toolLaunchContext,
           let data = try? JSONEncoder().encode(toolLaunchContext) {
            defaults.set(data, forKey: Key.toolLaunchContext)
        } else {
            defaults.removeObject(forKey: Key.toolLaunchContext)
        }
        if let latestToolResult,
           let data = try? JSONEncoder().encode(latestToolResult) {
            defaults.set(data, forKey: Key.latestToolResult)
        } else {
            defaults.removeObject(forKey: Key.latestToolResult)
        }
        if attachedToolResults.isEmpty {
            defaults.removeObject(forKey: Key.attachedToolResults)
        } else if let data = try? JSONEncoder().encode(attachedToolResults) {
            defaults.set(data, forKey: Key.attachedToolResults)
        }
        if let nestedToolID {
            defaults.set(nestedToolID.rawValue, forKey: Key.nestedToolID)
        } else {
            defaults.removeObject(forKey: Key.nestedToolID)
        }
        defaults.set(pendingQuestIDs.sorted(), forKey: Key.pendingQuestIDs)
        if let toolActivityState,
           let data = try? JSONEncoder().encode(toolActivityState) {
            defaults.set(data, forKey: Key.toolActivityState)
        } else {
            defaults.removeObject(forKey: Key.toolActivityState)
        }
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
        audioSession.releaseCurrentOwner()
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

    private func clearPendingNotifications() {
        sessionNotificationTask?.cancel()
        sessionNotificationTask = nil
        let center = UNUserNotificationCenter.current()
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
