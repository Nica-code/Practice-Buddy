import SwiftUI
import SwiftData
import Combine
import AVFoundation
import UIKit
import UserNotifications
#if canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
import ManagedSettings
#endif

struct HomeView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var purchaseManager: PurchaseManager
@Environment(\.modelContext) private var modelContext
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0

    // Timer persisted state
    @AppStorage("pb.practice.accumulatedSeconds") private var accumulatedSeconds: Int = 0
    @AppStorage("pb.practice.startEpoch") private var startEpoch: Double = 0
    @AppStorage("pb.practice.isRunning") private var isRunning: Bool = false
    @AppStorage("pb.practice.distractionBlockEnabled") private var distractionBlockEnabled: Bool = false
    @AppStorage("pb.practice.verifiedMode.enabled") private var verifiedModeEnabled: Bool = true
    @AppStorage("pb.practice.checkins.enabled") private var checkInsEnabled: Bool = true
    @AppStorage("pb.practice.checkins.intervalPreset") private var checkInIntervalPresetRaw: String = CheckInIntervalPreset.relaxed.rawValue
    @AppStorage("pb.practice.checkins.notifications") private var checkInNotificationsEnabled: Bool = true
    @AppStorage("pb.practice.verifiedSeconds") private var verifiedSeconds: Int = 0
    @AppStorage("pb.practice.unverifiedSeconds") private var unverifiedSeconds: Int = 0
    @AppStorage("pb.practice.checkinCount") private var checkInCountSaved: Int = 0
    @AppStorage("pb.practice.missedCheckInCount") private var missedCheckInCountSaved: Int = 0
    @AppStorage("pb.practice.checkinEventsJSON") private var checkInEventsJSON: String = ""

    // Goal settings
    @AppStorage("pb.settings.dailyGoalMinutes") private var goalMinutes: Int = 30
    @AppStorage("pb.settings.goalScope") private var goalScopeRaw: String = GoalScope.today.rawValue
    @AppStorage("pb.goal.lastCompletionKey") private var lastGoalCompletionKey: String = ""

    // Home display settings
    @AppStorage("pb.tools.metronome.bpm") private var metronomeBPM: Int = 80
    @AppStorage("pb.tools.metronome.beatsPerBar") private var metronomeBeatsPerBar: Int = 4
    @AppStorage("pb.tools.metronome.subdivision") private var metronomeSubdivisionRaw: String = MetronomeEngine.Subdivision.none.rawValue
    @AppStorage("pb.tools.metronome.soundStyle") private var metronomeSoundStyleRaw: String = MetronomeEngine.SoundStyle.click.rawValue
    @AppStorage("pb.tools.tuner.referenceHz") private var tunerReferenceHz: Int = 440

    // Live tick for the timer row
    @State private var now = Date()
    @State private var timerCancellable: AnyCancellable? = nil
    @StateObject private var metronome = MetronomeEngine()
    @StateObject private var tuner = TunerEngine()
    @StateObject private var social = LocalSocialProvider()
    @StateObject private var appShield = PracticeAppShieldManager()
    @StateObject private var checkInManager = PracticeCheckInManager()
    @State private var metronomePulseScale: CGFloat = 1.0
    @State private var metronomeTempoDraft: Double = 80
    @State private var isDraggingMetronomeTempo: Bool = false
    @State private var tapTempoMarks: [Date] = []
    @State private var selectedCheckInFocusTag: String = ""
    @State private var checkInStatusMessage: String?
    @State private var backgroundEnteredAt: Date?
    @State private var animateHeader: Bool = false
    @State private var didRunInitialHomeBootstrap: Bool = false

    private enum Constants {
        static let tickSeconds: TimeInterval = 1
        static let titleTopPadding: CGFloat = 18
        static let titleBottomPadding: CGFloat = 8
        static let checkInFocusTags: [String] = ["Intonation", "Rhythm", "Bow", "Shifts", "Vibrato", "Run-through"]
        static let sessionBuilderStorageKey = "pb.home.sessionBuilderTemplate.v1"
        static let legacyTemplatesStorageKey = "pb.home.editableSessionTemplates.v1"
    }

    private enum CheckInIntervalPreset: String, CaseIterable, Identifiable {
        case focused
        case standard
        case relaxed

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .focused: return "10–20 min"
            case .standard: return "20–35 min"
            case .relaxed: return "30–50 min"
            }
        }

        var rangeSeconds: ClosedRange<Int> {
            switch self {
            case .focused: return 600...1200
            case .standard: return 1200...2100
            case .relaxed: return 1800...3000
            }
        }
    }

    private enum PracticeToolSheet: String, Identifiable {
        case metronome
        case tuner

        var id: String { rawValue }
    }

    private struct LegacyEditableSessionTemplate: Codable {
        let id: String
        var name: String
        var warmupMinutes: Int
        var techniqueMinutes: Int
        var repertoireMinutes: Int
    }

    struct SessionBuilderTask: Identifiable, Codable, Equatable {
        let id: String
        var title: String
        var minutes: Int
    }

    struct SessionBuilderTemplate: Identifiable, Codable, Equatable {
        let id: String
        var name: String
        var tasks: [SessionBuilderTask]

        var normalizedTasks: [SessionBuilderTask] {
            tasks
                .map { task in
                    SessionBuilderTask(
                        id: task.id,
                        title: task.title.trimmingCharacters(in: .whitespacesAndNewlines),
                        minutes: max(0, task.minutes)
                    )
                }
                .filter { !$0.title.isEmpty && $0.minutes > 0 }
        }

        var totalMinutes: Int {
            normalizedTasks.reduce(0) { $0 + $1.minutes }
        }
    }

    struct ActiveSessionBuilderPlan: Identifiable, Equatable {
        let id: String
        let name: String
        let tasks: [SessionBuilderTask]

        var totalSeconds: Int {
            tasks.reduce(0) { $0 + max(0, $1.minutes) * 60 }
        }
    }

    private struct SessionTaskProgressRow: Identifiable, Equatable {
        let id: String
        let title: String
        let minutes: Int
        let progress: Double
        let isCurrent: Bool
        let isComplete: Bool
        let remainingSeconds: Int
    }

    private struct SessionSaveDraft {
        var noteTitle: String = ""
        var noteFocus: String = ""
        var noteMood: PracticeNoteMood = .good
        var pieces: [PracticeSessionJournalPiece] = []
        var reflection: String = ""
    }

    // Save flow
    @State private var showSaveSheet = false
    @State private var saveDraft = SessionSaveDraft()
    @State private var showSavedAlert = false
    @State private var lastSavedXP: Int = 0
    @State private var lastSaveMessage: String = "Your practice session was added to History."
    @State private var showDiscardConfirm = false
    @State private var isSavingSession = false
    @State private var pendingSessionResetAfterSave = false
    @State private var pendingSavedAlertAfterDismiss = false
    @State private var templatesLoaded = false
    @State private var sessionBuilderTemplate = SessionBuilderTemplate(
        id: "session_builder",
        name: "Practice Session",
        tasks: [
            SessionBuilderTask(id: "builder_task_warmup", title: "Warm-up", minutes: 10),
            SessionBuilderTask(id: "builder_task_technique", title: "Technique", minutes: 15),
            SessionBuilderTask(id: "builder_task_repertoire", title: "Repertoire", minutes: 20)
        ]
    )
    @State private var activeSessionBuilderPlan: ActiveSessionBuilderPlan?
    @State private var activePracticeToolSheet: PracticeToolSheet?
    @State private var showShopSheet = false
    @State private var showVerificationInfoSheet = false
    @State private var showGoalReachedBanner = false
    @State private var showSessionBuilder = true
    @State private var lastSessionNotificationSignature: String = ""
    @State private var sessionBuilderNotificationSyncTask: Task<Void, Never>?
    // Haptics
    private let impact = UIImpactFeedbackGenerator(style: .soft)
    private let notify = UINotificationFeedbackGenerator()

    // MARK: - Bindings

    private var goalScope: Binding<GoalScope> {
        Binding(
            get: { GoalScope(rawValue: goalScopeRaw) ?? .today },
            set: { goalScopeRaw = $0.rawValue }
        )
    }

    private var metronomeSubdivision: Binding<MetronomeEngine.Subdivision> {
        Binding(
            get: { MetronomeEngine.Subdivision(rawValue: metronomeSubdivisionRaw) ?? .none },
            set: { metronomeSubdivisionRaw = $0.rawValue }
        )
    }

    private var metronomeSoundStyle: Binding<MetronomeEngine.SoundStyle> {
        Binding(
            get: { MetronomeEngine.SoundStyle(rawValue: metronomeSoundStyleRaw) ?? .click },
            set: { metronomeSoundStyleRaw = $0.rawValue }
        )
    }

    private var checkInRandomPromptRange: ClosedRange<Int> { 30 * 60...50 * 60 }

    // MARK: - Timer derived

    private var startDate: Date? {
        startEpoch > 0 ? Date(timeIntervalSince1970: startEpoch) : nil
    }

    private var currentElapsedSeconds: Int {
        if isRunning, let startDate {
            let running = Int(Date().timeIntervalSince(startDate))
            return accumulatedSeconds + max(0, running)
        } else {
            return accumulatedSeconds
        }
    }

    private var hasAnyTime: Bool { currentElapsedSeconds > 0 }
    private var canStop: Bool { hasAnyTime || isRunning }
    private var verificationEnabledForSession: Bool { verifiedModeEnabled }
    private var verificationMechanismActive: Bool {
        verificationEnabledForSession
            && distractionBlockEnabled
            && appShield.isShieldingActive
            && appShield.isAuthorized
            && appShield.selectedAppsCount > 0
    }
    private var verificationStatusActive: Bool {
        verificationEnabledForSession
            && distractionBlockEnabled
            && appShield.isVerificationConfigured
    }
    private var checkInFlowEnabled: Bool {
        verificationMechanismActive && checkInsEnabled
    }
    private var effectiveVerifiedSeconds: Int {
        verificationEnabledForSession ? max(0, verifiedSeconds) : 0
    }
    private var effectiveUnverifiedSeconds: Int {
        verificationEnabledForSession ? max(0, unverifiedSeconds) : max(0, currentElapsedSeconds)
    }

    private var primaryButtonTitle: String {
        if isRunning { return "Pause" }
        if hasAnyTime { return "Resume" }
        return "Start"
    }

    // MARK: - Goal derived

    private var goalSeconds: Int { max(0, goalMinutes) * 60 }

    private var scopedSeconds: Int {
        switch GoalScope(rawValue: goalScopeRaw) ?? .today {
        case .today: return store.totalTodaySeconds
        case .week: return store.totalThisWeekSeconds
        case .month: return store.totalThisMonthSeconds
        }
    }

    private var goalProgress: Double {
        guard goalSeconds > 0 else { return 0 }
        return min(1.0, Double(scopedSeconds) / Double(goalSeconds))
    }

    private var goalReached: Bool {
        goalSeconds > 0 && scopedSeconds >= goalSeconds
    }

    private var goalCompletionEventKey: String {
        let calendar = Calendar.current
        let start: Date
        switch GoalScope(rawValue: goalScopeRaw) ?? .today {
        case .today:
            start = calendar.startOfDay(for: Date())
        case .week:
            start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        case .month:
            start = calendar.dateInterval(of: .month, for: Date())?.start ?? calendar.startOfDay(for: Date())
        }
        return "\(goalScopeRaw)|\(goalMinutes)|\(Int(start.timeIntervalSince1970))"
    }

    private var streakDays: Int {
        let scope = GoalScope(rawValue: goalScopeRaw) ?? .today
        guard scope == .today else { return 0 }
        return store.currentStreakDays(dailyGoalMinutes: goalMinutes)
    }

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        lifecycleScaffold
        .sheet(isPresented: $showSaveSheet, onDismiss: handleSaveSheetDismiss) {
            saveSheet
        }
        .sheet(item: $activePracticeToolSheet) { sheet in
            NavigationStack {
                switch sheet {
                case .metronome:
                    metronomeToolSheetContent
                case .tuner:
                    tunerToolSheetContent
                }
            }
        }
        .alert("Saved!", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(lastSaveMessage))
        }
        .overlay {
            if isRunning && checkInFlowEnabled && checkInManager.isAwaitingResponse {
                checkInOverlay
            }
        }
        .sheet(isPresented: $showShopSheet) {
            NavigationStack {
                ShopView()
            }
        }
        .sheet(isPresented: $showVerificationInfoSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Verified Mode")
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)
                    Text("XP, quests, and tokens are awarded from verified minutes only. Verification activates only while app blocking is actively running.")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                }
                .padding(PBLayout.padLG)
                .background(PBBackdropView(palette: palette))
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showVerificationInfoSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.height(220)])
        }
        .overlay(alignment: .top) {
            if showGoalReachedBanner {
                HStack(spacing: 10) {
                    Image(systemName: "flag.checkered.2.crossed")
                        .foregroundStyle(palette.accent)
                    Text("Daily goal reached.")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showGoalReachedBanner = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .pbFlatCard(palette: palette)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .onTapGesture { }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var mainScaffold: some View {
        VStack(spacing: 0) {
            homeShortcutRow
            homeHeader

            List {
                sessionControlSection
                goalSection
                practiceTimeSection
                recentHistorySection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
        }
        .background {
            PBBackdropView(palette: palette)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var homeShortcutRow: some View {
        PBShortcutBar(items: homeShortcutItems, palette: palette)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .offset(y: animateHeader ? 0 : 10)
            .opacity(animateHeader ? 1 : 0)
    }

    private var lifecycleScaffold: some View {
        mainScaffold
            .onAppear(perform: handleLifecycleAppear)
            .onChange(of: isRunning, handleIsRunningChange)
            .onChange(of: distractionBlockEnabled, handleDistractionBlockChange)
            .onChange(of: checkInsEnabled, handleCheckInsChange)
            .onChange(of: verifiedModeEnabled, handleVerifiedModeChange)
            .onChange(of: checkInIntervalPresetRaw, handleCheckInIntervalChange)
            .onChange(of: checkInNotificationsEnabled, handleCheckInNotificationsChange)
            .onDisappear(perform: handleLifecycleDisappear)
            .onChange(of: scenePhase, handleScenePhaseChange)
            .onChange(of: scopedSeconds) { _, _ in handleGoalReachedBannerIfNeeded() }
            .onChange(of: goalScopeRaw) { _, _ in handleGoalReachedBannerIfNeeded() }
            .onChange(of: goalMinutes) { _, _ in handleGoalReachedBannerIfNeeded() }
            .onChange(of: metronomeBPM, handleMetronomeBPMChange)
            .onChange(of: metronomeBeatsPerBar, handleMetronomeBeatsChange)
            .onChange(of: metronomeSubdivisionRaw) { _, _ in applyMetronomeConfiguration() }
            .onChange(of: metronomeSoundStyleRaw) { _, _ in applyMetronomeConfiguration() }
            .onChange(of: activeSessionBuilderPlan) { _, _ in
                queueSessionBuilderNotificationSync()
            }
            .onReceive(metronome.$pulseToken.dropFirst().removeDuplicates()) { token in
                guard token > 0 else { return }
                withAnimation(.easeOut(duration: 0.08)) {
                    metronomePulseScale = 1.3
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        metronomePulseScale = 1.0
                    }
                }
            }
            .onChange(of: tunerReferenceHz) { _, newValue in
                if tuner.isReferenceTonePlaying {
                    tuner.startReferenceTone(frequency: Double(newValue))
                }
            }
            .onReceive(store.$sessions.dropFirst().map(\.count).removeDuplicates()) { _ in
                social.refresh()
            }
    }

    private func handleLifecycleAppear() {
        if !animateHeader {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                animateHeader = true
            }
        }
        impact.prepare()
        notify.prepare()
        sanitizeMetronomeSettings()
        metronome.setBPM(metronomeBPM)
        syncMetronomeTempoDraft(force: true)
        applyMetronomeConfiguration()
        if verifiedModeEnabled {
            distractionBlockEnabled = true
            checkInsEnabled = true
            checkInNotificationsEnabled = true
        }

        if isRunning {
            startTicker()
        }
        if !didRunInitialHomeBootstrap {
            didRunInitialHomeBootstrap = true
            if !templatesLoaded {
                templatesLoaded = true
                loadSessionBuilderTemplate()
            }
            Task { @MainActor in
                await Task.yield()
                social.configure(modelContext: modelContext)
                social.refresh()
                if distractionBlockEnabled {
                    appShield.refreshState()
                }
                restorePersistedCheckInState()
                updateCheckInPromptConfiguration()
            }
        } else {
            updateCheckInPromptConfiguration()
        }
        handleGoalReachedBannerIfNeeded()
    }

    private func handleLifecycleDisappear() {
        stopTicker()
        tuner.stopListening()
        tuner.stopReferenceTone()
        appShield.stopShielding()
        sessionBuilderNotificationSyncTask?.cancel()
        sessionBuilderNotificationSyncTask = nil
    }

    private func handleIsRunningChange(_: Bool, running: Bool) {
        if running {
            now = Date()
            startTicker()
        } else {
            stopTicker()
        }
    }

    private func handleDistractionBlockChange(_: Bool, enabled: Bool) {
        if !enabled {
            appShield.stopShielding()
        } else if isRunning {
            Task { await appShield.startShieldingIfPossible() }
        }
    }

    private func handleCheckInsChange(_: Bool, enabled: Bool) {
        if !enabled {
            checkInStatusMessage = nil
            checkInManager.reset()
            checkInEventsJSON = ""
            clearPendingCheckInNotifications()
        } else if hasAnyTime && verificationEnabledForSession {
            restorePersistedCheckInState()
            updateCheckInPromptConfiguration()
            if scenePhase != .active && checkInFlowEnabled {
                scheduleBackgroundCheckInNotification()
            }
        }
    }

    private func handleVerifiedModeChange(_: Bool, enabled: Bool) {
        if enabled {
            distractionBlockEnabled = true
            checkInsEnabled = true
            checkInNotificationsEnabled = true
            checkInIntervalPresetRaw = CheckInIntervalPreset.relaxed.rawValue
            appShield.refreshState()
            Task {
                await appShield.configureAutoVerificationDefaults()
                if isRunning {
                    await appShield.startShieldingIfPossible()
                }
            }
        } else {
            distractionBlockEnabled = false
            checkInsEnabled = false
            checkInNotificationsEnabled = false
            checkInStatusMessage = nil
            clearPendingCheckInNotifications()
        }

        if enabled && isRunning && checkInFlowEnabled && scenePhase != .active {
            scheduleBackgroundCheckInNotification()
        }
    }

    private func handleCheckInIntervalChange(_: String, _: String) {
        updateCheckInPromptConfiguration()
        if scenePhase != .active, isRunning, checkInFlowEnabled {
            scheduleBackgroundCheckInNotification()
        }
    }

    private func handleCheckInNotificationsChange(_: Bool, enabled: Bool) {
        if !enabled {
            clearPendingCheckInNotifications()
        } else if scenePhase != .active, isRunning, checkInFlowEnabled {
            scheduleBackgroundCheckInNotification()
        }
    }

    private func handleScenePhaseChange(_: ScenePhase, phase: ScenePhase) {
        if phase == .active {
            applyBackgroundElapsedCatchUp()
            clearPendingCheckInNotifications()
            if isRunning, activeSessionBuilderPlan != nil {
                queueSessionBuilderNotificationSync(force: true)
            }
        } else if isRunning {
            if backgroundEnteredAt == nil {
                backgroundEnteredAt = Date()
            }
            if checkInFlowEnabled {
                scheduleBackgroundCheckInNotification()
            }
        }
    }

    private func handleMetronomeBPMChange(_: Int, newBPM: Int) {
        let clamped = min(max(newBPM, 40), 220)
        if clamped != metronomeBPM {
            metronomeBPM = clamped
            return
        }
        syncMetronomeTempoDraft()
        metronome.setBPM(clamped)
        applyMetronomeConfiguration()
    }

    private func handleMetronomeBeatsChange(_: Int, newBeats: Int) {
        let clamped = MetronomeEngine.clampBeatsPerBar(newBeats)
        if clamped != metronomeBeatsPerBar {
            metronomeBeatsPerBar = clamped
            return
        }
        applyMetronomeConfiguration()
    }

    private func applyMetronomeConfiguration() {
        let effectiveSoundRaw = JourneyProgressManager.preferredMetronomeSoundStyleRaw() ?? metronomeSoundStyleRaw
        metronome.applyUpdatedConfiguration(
            beatsPerBar: metronomeBeatsPerBar,
            subdivision: MetronomeEngine.Subdivision(rawValue: metronomeSubdivisionRaw) ?? .none,
            soundStyle: MetronomeEngine.SoundStyle(rawValue: effectiveSoundRaw) ?? .click
        )
    }

    // MARK: - Ticker control

    private func startTicker() {
        guard timerCancellable == nil else { return }
        timerCancellable = Timer.publish(every: Constants.tickSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                now = Date()
                handlePracticeTick()
            }
    }

    private func stopTicker() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func handlePracticeTick() {
        guard isRunning else { return }

        if verificationEnabledForSession {
            if checkInFlowEnabled {
                switch checkInManager.tick(now: Date(), enabled: true) {
                case .none:
                    break
                case .triggered:
                    checkInStatusMessage = "Check-in required."
                    selectedCheckInFocusTag = ""
                case .missed:
                    checkInStatusMessage = "Missed check-in. Session paused."
                    accumulatedSeconds = currentElapsedSeconds
                    isRunning = false
                    startEpoch = 0
                    backgroundEnteredAt = nil
                    if distractionBlockEnabled {
                        appShield.stopShielding()
                    }
                    clearPendingCheckInNotifications()
                }
            } else if !verificationMechanismActive {
                checkInStatusMessage = nil
            }

            if checkInFlowEnabled && checkInManager.isAwaitingResponse {
                unverifiedSeconds += 1
            } else if verificationMechanismActive {
                verifiedSeconds += 1
            } else {
                unverifiedSeconds += 1
            }
            checkInCountSaved = checkInManager.checkInCount
            missedCheckInCountSaved = checkInManager.missedCheckInCount
            checkInEventsJSON = checkInManager.eventsJSON()
        } else {
            unverifiedSeconds += 1
            checkInStatusMessage = nil
        }
    }

    private func applyBackgroundElapsedCatchUp() {
        guard let started = backgroundEnteredAt else { return }
        backgroundEnteredAt = nil

        guard isRunning else { return }
        let delta = max(0, Int(Date().timeIntervalSince(started)))
        guard delta > 0 else { return }

        unverifiedSeconds += delta
        if verificationMechanismActive {
            checkInStatusMessage = "Background time counted as unverified."
        }
    }

    private func restorePersistedCheckInState() {
        checkInManager.restoreCounters(
            checkInCount: checkInCountSaved,
            missedCheckInCount: missedCheckInCountSaved,
            events: decodedCheckInEvents(from: checkInEventsJSON)
        )
    }

    private func updateCheckInPromptConfiguration() {
        checkInManager.updateConfiguration(
            promptRange: checkInRandomPromptRange
        )
    }

    private func scheduleBackgroundCheckInNotification() {
        guard checkInNotificationsEnabled, checkInFlowEnabled, isRunning else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["pb.practice.checkin.prompt"])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Practice Check-in")
        content.body = String(localized: "Still practicing? Open Practice Buddy to confirm.")
        content.sound = .default

        let interval = TimeInterval(max(10, checkInManager.secondsUntilPrompt))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pb.practice.checkin.prompt",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    private func clearPendingCheckInNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["pb.practice.checkin.prompt"])
    }

    private func handleGoalReachedBannerIfNeeded() {
        guard goalReached else { return }
        let key = goalCompletionEventKey
        guard key != lastGoalCompletionKey else { return }
        lastGoalCompletionKey = key
        if scenePhase != .active {
            PBNotificationCenter.maybeScheduleGoalReachedNotification(eventKey: key)
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            showGoalReachedBanner = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation(.easeOut(duration: 0.24)) {
                showGoalReachedBanner = false
            }
        }
    }

    private var metronomeToolSheetContent: some View {
        Form {
            Section {
                HStack {
                    Text("Tempo")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(L10n.f("%@ BPM", "\(Int(metronomeTempoDraft.rounded()))"))
                        .font(type.timer)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                HStack(spacing: 10) {
                    tempoNudgeButton(label: "-5", delta: -5)
                    tempoNudgeButton(label: "-1", delta: -1)
                    tempoNudgeButton(label: "+1", delta: 1)
                    tempoNudgeButton(label: "+5", delta: 5)
                }

                Slider(
                    value: $metronomeTempoDraft,
                    in: 40...220,
                    step: 1,
                    onEditingChanged: { editing in
                        isDraggingMetronomeTempo = editing
                        if !editing {
                            commitMetronomeTempoDraft()
                        }
                    }
                )

                HStack(spacing: 8) {
                    ForEach([60, 72, 80, 96, 120], id: \.self) { value in
                        Button("\(value)") {
                            hapticSoftTap()
                            setMetronomeTempo(value)
                        }
                        .font(type.footnote)
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button("Tap Tempo") {
                        hapticSoftTap()
                        registerTapTempo()
                    }
                    .font(type.footnote)
                    .buttonStyle(.borderedProminent)
                }

                Picker("Time Signature", selection: $metronomeBeatsPerBar) {
                    Text("2/4").tag(2)
                    Text("3/4").tag(3)
                    Text("4/4").tag(4)
                    Text("6/8").tag(6)
                }
                .pickerStyle(.segmented)

                Picker("Subdivision", selection: metronomeSubdivision) {
                    ForEach(MetronomeEngine.Subdivision.allCases) { value in
                        Text(LocalizedStringKey(value.title)).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Sound", selection: metronomeSoundStyle) {
                    ForEach(MetronomeEngine.SoundStyle.allCases) { style in
                        Text(LocalizedStringKey(style.title)).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(palette.accent.opacity(metronome.isRunning ? 0.35 : 0.18))
                            .frame(width: 14, height: 14)
                            .scaleEffect(metronomePulseScale)
                        Text(metronomeStatusText)
                            .font(type.body)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    metronomeControlButton
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .navigationTitle("Metronome")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { activePracticeToolSheet = nil }
            }
        }
    }

    private var tunerToolSheetContent: some View {
        Form {
            Section {
                HStack {
                    Text("Frequency")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    if let freq = tuner.detectedFrequency {
                        Text("\(freq, specifier: "%.1f") Hz")
                            .font(type.number)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    } else {
                        Text("-- Hz")
                            .font(type.number)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }
                }

                Picker("Reference A", selection: $tunerReferenceHz) {
                    Text("A=440").tag(440)
                    Text("A=442").tag(442)
                    Text("A=415").tag(415)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Button(tuner.isReferenceTonePlaying ? "Stop A Tone" : "Play A Tone") {
                        hapticSoftTap()
                        tuner.toggleReferenceTone(frequency: Double(tunerReferenceHz))
                    }
                    .font(type.button)
                    .buttonStyle(.bordered)

                    Button(tuner.isListening ? "Stop Tuner" : "Start Tuner") {
                        hapticSoftTap()
                        tuner.toggleListening()
                    }
                    .font(type.button)
                    .buttonStyle(.borderedProminent)
                }

                HStack {
                    Text(L10n.f("Detected: %@", tuner.detectedNoteName))
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(centsLabel)
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                TunerNeedleGauge(cents: tuner.detectedFrequency == nil ? nil : tuner.detectedCents, accent: palette.accent)
                    .frame(height: 84)

                if tuner.permissionState == .denied {
                    Text("Microphone access denied. Enable it in Settings to use tuner input.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                } else if let status = tuner.statusMessage {
                    Text(LocalizedStringKey(status))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .navigationTitle("Tuner")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { activePracticeToolSheet = nil }
            }
        }
    }

    private var checkInOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Still practicing?")
                    .font(type.sectionTitle)
                    .foregroundStyle(palette.textPrimary)

                Text(L10n.f("Please confirm in %@s", "\(checkInManager.secondsUntilDeadline)"))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(Constants.checkInFocusTags, id: \.self) { tag in
                        Button {
                            selectedCheckInFocusTag = tag
                        } label: {
                            Text(LocalizedStringKey(tag))
                                .font(type.footnote)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedCheckInFocusTag == tag ? palette.accent : palette.textSecondary.opacity(0.8))
                    }
                }

                Button {
                    let focus = selectedCheckInFocusTag
                    checkInManager.respond(focusTag: focus, now: Date())
                    checkInCountSaved = checkInManager.checkInCount
                    missedCheckInCountSaved = checkInManager.missedCheckInCount
                    checkInEventsJSON = checkInManager.eventsJSON()
                    checkInStatusMessage = "Check-in confirmed."
                    selectedCheckInFocusTag = ""
                } label: {
                    Text("I’m Here")
                        .font(type.button)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
            }
            .padding(16)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
        }
    }

    private var sharePeriodForCurrentMode: SocialPeriod {
        .week
    }

    private var homeHeader: some View {
        VStack(spacing: 12) {
            Text("Let’s Practice!")
                .font(type.appTitle)
                .tracking(type.heroTracking)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Constants.titleTopPadding)
                .padding(.bottom, 2)
                .foregroundStyle(palette.textPrimary)

            HStack(spacing: 8) {
                levelChip
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, Constants.titleBottomPadding)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .pbFlatCard(palette: palette)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .offset(y: animateHeader ? 0 : 12)
        .opacity(animateHeader ? 1 : 0)
    }

    private var homeShortcutItems: [PBShortcutItem] {
        [
            PBShortcutItem(
                id: "home_timer",
                title: isRunning ? "Pause Timer" : (hasAnyTime ? "Resume Timer" : "Start Timer"),
                systemImage: isRunning ? "pause.circle.fill" : "play.circle.fill",
                action: {
                    hapticSoftTap()
                    toggleStartPauseOrStart()
                }
            ),
            PBShortcutItem(
                id: "home_save",
                title: "Save Session",
                systemImage: "square.and.arrow.down.fill",
                isDisabled: !hasAnyTime,
                action: {
                    if hasAnyTime { showSaveSheet = true }
                }
            ),
            PBShortcutItem(
                id: "home_store",
                title: "Shop",
                systemImage: "bag.fill",
                action: { showShopSheet = true }
            )
        ]
    }

    private var levelChip: some View {
        Button {
            selectedTab = 1
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(L10n.f("Lv %@", "\(journey.level)"))
                    .font(type.footnote)
                    .foregroundStyle(palette.textPrimary)
                Text("•")
                    .foregroundStyle(palette.textSecondary)
                Text(L10n.f("%@ XP to next level", "\(journey.xpToNextLevel)"))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(palette.surfaceAlt)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func decodedCheckInEvents(from raw: String) -> [PracticeCheckInEvent] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let events = try? JSONDecoder().decode([PracticeCheckInEvent].self, from: data) else {
            return []
        }
        return events
    }

    private func homeSectionCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
        .listRowInsets(
            EdgeInsets(
                top: 4,
                leading: 0,
                bottom: 4,
                trailing: 0
            )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var sessionControlSection: some View {
        Section {
            homeSectionCard {
                HStack(alignment: .center, spacing: 12) {
                    Text(DurationFormatter.string(from: currentElapsedSeconds))
                        .font(type.timer)
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button(primaryButtonTitle) {
                        hapticSoftTap()
                        toggleStartPauseOrStart()
                    }
                    .font(type.button)
                    .buttonStyle(.borderedProminent)
                    Button("Stop") {
                        hapticSoftTap()
                        stopTapped()
                    }
                    .font(type.button)
                    .buttonStyle(.bordered)
                    .disabled(!canStop)
                }

                HStack(spacing: 10) {
                    Toggle(isOn: $verifiedModeEnabled) {
                        Text("Verified Mode")
                            .font(type.footnote)
                            .foregroundStyle(palette.textPrimary)
                    }
                    .toggleStyle(.switch)
                    Button {
                        showVerificationInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                if verificationEnabledForSession {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(verificationStatusActive ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(verificationStatusActive ? "Verification active" : "Verification inactive")
                            .font(type.footnote)
                            .foregroundStyle(verificationStatusActive ? Color.green : Color.orange)
                    }
                }

                DisclosureGroup {
                    HStack {
                        Text("Verified")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text(DurationFormatter.string(from: effectiveVerifiedSeconds))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Unverified")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text(DurationFormatter.string(from: effectiveUnverifiedSeconds))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }

                    if verificationEnabledForSession {
                        Text(LocalizedStringKey(appShield.statusLine))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                } label: {
                    Text("Verification details")
                        .font(type.footnote)
                        .foregroundStyle(palette.textPrimary)
                }

                Divider()
                    .padding(.vertical, 4)

                DisclosureGroup(isExpanded: $showSessionBuilder) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($sessionBuilderTemplate.tasks) { $task in
                            SessionBuilderTaskEditorRow(
                                title: $task.title,
                                minutes: $task.minutes,
                                canDelete: sessionBuilderTemplate.tasks.count > 1,
                                onDelete: { removeSessionTask(id: task.id) },
                                onHapticTap: hapticSoftTap,
                                palette: palette,
                                type: type
                            )
                        }

                        HStack {
                            Button {
                                hapticSoftTap()
                                addSessionTask()
                            } label: {
                                Label("Add Task", systemImage: "plus.circle")
                                    .font(type.footnote)
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }

                        HStack {
                            Text(L10n.f("%@ min total", "\(sessionBuilderTemplate.totalMinutes)"))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                            Spacer()
                            Button("Start Session") {
                                hapticSoftTap()
                                startSessionFromBuilder()
                            }
                            .buttonStyle(.borderedProminent)
                            .font(type.button)
                            .disabled(sessionBuilderTemplate.normalizedTasks.isEmpty)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text("Practice Session Builder")
                            .font(type.footnote)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(L10n.f("%@ min", "\(sessionBuilderTemplate.totalMinutes)"))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }
                }
                .onChange(of: sessionBuilderTemplate) { _, _ in
                    persistSessionBuilderTemplate()
                }

                if let plan = activeSessionBuilderPlan {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Session Progress")
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            Button("End") {
                                hapticSoftTap()
                                activeSessionBuilderPlan = nil
                            }
                            .buttonStyle(.bordered)
                            .font(type.footnote)
                        }

                        let rows = sessionTaskProgressRows(for: plan, elapsedSeconds: currentElapsedSeconds)
                        ForEach(rows) { row in
                            SessionBuilderProgressItemRow(
                                title: row.title,
                                progress: row.progress,
                                isCurrent: row.isCurrent,
                                isComplete: row.isComplete,
                                remainingLabel: L10n.f("%@ left", mmss(row.remainingSeconds)),
                                palette: palette,
                                type: type
                            )
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Practice Tools")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)

                    HStack(spacing: 10) {
                        HomeQuickToolButton(
                            title: "Metronome",
                            subtitle: L10n.f("%@ BPM", "\(metronomeBPM)"),
                            icon: "metronome",
                            palette: palette,
                            type: type,
                            action: { activePracticeToolSheet = .metronome }
                        )
                        HomeQuickToolButton(
                            title: "Tuner",
                            subtitle: L10n.f("A=%@", "\(tunerReferenceHz)"),
                            icon: "tuningfork",
                            palette: palette,
                            type: type,
                            action: { activePracticeToolSheet = .tuner }
                        )
                    }
                }
            }
        }
        header: {
            PBSectionHeaderLabel(title: "Practice Timer")
        }
    }

    private var practiceTimeSection: some View {
        Section {
            homeSectionCard {
                HStack(spacing: 10) {
                    CompactTimeStatView(title: "Today", seconds: store.totalTodaySeconds, palette: palette, type: type)
                    CompactTimeStatView(title: "Week", seconds: store.totalThisWeekSeconds, palette: palette, type: type)
                    CompactTimeStatView(title: "Month", seconds: store.totalThisMonthSeconds, palette: palette, type: type)
                }
                .padding(.vertical, 2)

                ShareLink(item: social.shareText(for: sharePeriodForCurrentMode)) {
                    Label("Share Practice Time", systemImage: "square.and.arrow.up")
                        .font(type.body)
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.bordered)
                .tint(palette.accent)
            }
        } header: {
            PBSectionHeaderLabel(title: "Practice Time")
        }
    }

    private var goalSection: some View {
        Section {
            homeSectionCard {
                Picker("Period", selection: goalScope) {
                    ForEach(GoalScope.allCases) { scope in
                        Text(LocalizedStringKey(scope.title)).tag(scope)
                    }
                }
                .pickerStyle(.menu)

                if goalMinutes == 0 {
                    Text("Goal is off. Turn it on in Settings.")
                        .foregroundStyle(palette.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            let scopeTitleKey =
                                (GoalScope(rawValue: goalScopeRaw) ?? .today) == .today ? "Today" :
                                (GoalScope(rawValue: goalScopeRaw) ?? .today) == .week ? "This week" : "This month"
                            Text(LocalizedStringKey(scopeTitleKey))
                                .foregroundStyle(palette.textPrimary)

                            Spacer()

                            Text(L10n.f("%@ / %@ min", DurationFormatter.string(from: scopedSeconds), "\(goalMinutes)"))
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        ProgressView(value: goalProgress)

                        if (GoalScope(rawValue: goalScopeRaw) ?? .today) == .today {
                            HStack {
                                Text("Streak")
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text(
                                    L10n.f(
                                        streakDays == 1 ? "%@ day" : "%@ days",
                                        "\(streakDays)"
                                    )
                                )
                                    .font(type.number)
                                    .foregroundStyle(palette.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Goal")
        }
    }

    private var recentHistorySection: some View {
        Section {
            homeSectionCard {
                if store.sessions.isEmpty {
                    Text("No sessions yet.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(store.sessions.prefix(5)), id: \.id) { session in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(session.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .font(type.footnote)
                                        .foregroundStyle(palette.textSecondary)
                                    Text(DurationFormatter.string(from: max(0, session.durationSeconds)))
                                        .font(type.number)
                                        .foregroundStyle(palette.textPrimary)
                                        .monospacedDigit()
                                    let xp = max(0, (session.hasVerificationData ? session.verifiedSeconds : session.durationSeconds) / 60)
                                    Text(L10n.f("+%@ XP", "\(xp)"))
                                        .font(type.footnote)
                                        .foregroundStyle(palette.accent)
                                }
                                .frame(minWidth: 170, idealWidth: 190, maxWidth: 210, alignment: .leading)
                                .padding(10)
                                .pbSurfaceCard(palette: palette, cornerRadius: 12)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                NavigationLink {
                    PBLazyView(HistoryView())
                } label: {
                    Text("View Full History")
                        .font(type.body)
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Recent History")
        }
    }

    private var centsLabel: String {
        guard tuner.detectedFrequency != nil else { return "-- cents" }
        return String(format: "%+.1f cents", tuner.detectedCents)
    }

    private var metronomeStatusText: String {
        if metronome.isRunning {
            if metronome.currentSubdivision > 1 {
                return L10n.f("Beat %@.%@", "\(metronome.currentBeat)", "\(metronome.currentSubdivision)")
            }
            return L10n.f("Beat %@/%@", "\(metronome.currentBeat)", "\(metronomeBeatsPerBar)")
        }
        return String(localized: "Stopped")
    }

    @ViewBuilder
    private var metronomeControlButton: some View {
        if metronome.isRunning {
            Button("Stop") {
                hapticSoftTap()
                toggleMetronome()
            }
            .font(type.button)
            .buttonStyle(.bordered)
        } else {
            Button("Start") {
                hapticSoftTap()
                toggleMetronome()
            }
            .font(type.button)
            .buttonStyle(.borderedProminent)
        }
    }

    private func toggleStartPauseOrStart() {
        if isRunning {
            pauseActiveTimerSession()
        } else {
            if !hasAnyTime {
                resetTrackedPracticeCounters()
            }
            startEpoch = Date().timeIntervalSince1970
            isRunning = true
            backgroundEnteredAt = nil
            if !verificationEnabledForSession {
                checkInStatusMessage = nil
            }
            if distractionBlockEnabled {
                Task { await appShield.startShieldingIfPossible() }
            }
            if scenePhase != .active, verificationEnabledForSession {
                scheduleBackgroundCheckInNotification()
            }
        }
        queueSessionBuilderNotificationSync()
    }

    private func stopTapped() {
        if isRunning {
            pauseActiveTimerSession()
        }
        if saveDraft.pieces.isEmpty {
            saveDraft.pieces = [makeEmptyPiece()]
        }
        queueSessionBuilderNotificationSync()
        showSaveSheet = true
    }

    private func resetSession() {
        accumulatedSeconds = 0
        startEpoch = 0
        isRunning = false
        backgroundEnteredAt = nil
        verifiedSeconds = 0
        unverifiedSeconds = 0
        checkInCountSaved = 0
        missedCheckInCountSaved = 0
        checkInEventsJSON = ""
        checkInManager.reset()
        selectedCheckInFocusTag = ""
        checkInStatusMessage = nil
        if distractionBlockEnabled {
            appShield.stopShielding()
        }
        clearPendingCheckInNotifications()
        saveDraft = SessionSaveDraft(
            noteTitle: "",
            noteFocus: "",
            noteMood: .good,
            pieces: [makeEmptyPiece()],
            reflection: ""
        )
        activeSessionBuilderPlan = nil
        lastSessionNotificationSignature = ""
        queueSessionBuilderNotificationSync()
        isSavingSession = false
    }

    private func handleSaveSheetDismiss() {
        if pendingSessionResetAfterSave {
            pendingSessionResetAfterSave = false
            resetSession()
        }
        if pendingSavedAlertAfterDismiss {
            pendingSavedAlertAfterDismiss = false
            showSavedAlert = true
        }
    }

    private var saveSheet: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    Text(L10n.f("Duration: %@", DurationFormatter.string(from: currentElapsedSeconds)))
                        .font(type.number)
                        .foregroundStyle(palette.textPrimary)

                    if verificationEnabledForSession {
                        Text(L10n.f("Verified: %@", DurationFormatter.string(from: effectiveVerifiedSeconds)))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        Text(L10n.f("Unverified: %@", DurationFormatter.string(from: effectiveUnverifiedSeconds)))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        Text(L10n.f("Check-ins: %@ total • %@ missed", "\(checkInManager.checkInCount)", "\(checkInManager.missedCheckInCount)"))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                Section("Journal Header") {
                    TextField("Session title", text: $saveDraft.noteTitle)
                        .font(type.body)

                    TextField("Overall focus", text: $saveDraft.noteFocus)
                        .font(type.body)

                    Picker("Mood", selection: $saveDraft.noteMood) {
                        ForEach(PracticeNoteMood.allCases) { mood in
                            Text(LocalizedStringKey(mood.title)).tag(mood)
                        }
                    }
                }

                Section("Pieces") {
                    if saveDraft.pieces.isEmpty {
                        Text("No pieces yet.")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }

                    ForEach(saveDraft.pieces) { piece in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Piece title", text: pieceBinding(piece.id, \.title))
                                .font(type.body)

                            TextField("Tempo worked on (optional)", text: pieceBinding(piece.id, \.tempo))
                                .font(type.body)

                            TextField("What went well", text: pieceBinding(piece.id, \.wentWell), axis: .vertical)
                                .font(type.body)
                                .lineLimit(2...4)

                            TextField("Needs work", text: pieceBinding(piece.id, \.needsWork), axis: .vertical)
                                .font(type.body)
                                .lineLimit(2...4)

                            TextField("Next action for tomorrow", text: pieceBinding(piece.id, \.nextAction), axis: .vertical)
                                .font(type.body)
                                .lineLimit(2...4)

                            HStack {
                                Spacer()
                                Button("Remove Piece", role: .destructive) {
                                    saveDraft.pieces.removeAll { $0.id == piece.id }
                                }
                                .font(type.footnote)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        saveDraft.pieces.append(makeEmptyPiece())
                    } label: {
                        Label("Add Piece", systemImage: "plus")
                    }
                    .font(type.button)
                }

                Section("Reflection") {
                    TextField("How did the session feel? What to remember for next time?", text: $saveDraft.reflection, axis: .vertical)
                        .font(type.body)
                        .lineLimit(4...8)

                    Text("Markdown supported: # heading, - bullets, **bold**, _italic_.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        hapticSoftTap()
                        showDiscardConfirm = true
                    }
                    .font(type.button)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !isSavingSession else { return }
                        isSavingSession = true
                        hapticSuccess()
                        let cleanedTitle = saveDraft.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanedFocus = saveDraft.noteFocus.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanedReflection = saveDraft.reflection.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanedPieces = cleanedJournalPieces(from: saveDraft.pieces)
                        let journal = PracticeSessionJournal(pieces: cleanedPieces, reflection: cleanedReflection)
                        let structuredJSON = journalJSONIfNeeded(journal)
                        let verifiedToSave = effectiveVerifiedSeconds
                        let unverifiedToSave = effectiveUnverifiedSeconds
                        lastSavedXP = max(0, verifiedToSave / 60)
                        let baseNotes = legacyNotesFallback(
                            title: cleanedTitle,
                            focus: cleanedFocus,
                            mood: saveDraft.noteMood,
                            journal: journal
                        )
                        let notesToSave = purchaseManager.featuresUnlocked
                            ? appendProSessionSummary(
                                to: baseNotes,
                                totalSeconds: currentElapsedSeconds,
                                verifiedSeconds: verifiedToSave,
                                unverifiedSeconds: unverifiedToSave,
                                checkInCount: checkInManager.checkInCount,
                                missedCheckInCount: checkInManager.missedCheckInCount,
                                metronomeRunning: metronome.isRunning,
                                tunerListening: tuner.isListening
                            )
                            : baseNotes
                        if verificationEnabledForSession && verifiedToSave > 0 {
                            lastSaveMessage = "Your practice session was added to History. Verified \(DurationFormatter.string(from: verifiedToSave)) / \(DurationFormatter.string(from: currentElapsedSeconds)). +\(lastSavedXP) XP"
                        } else if lastSavedXP > 0 {
                            lastSaveMessage = "Your practice session was added to History. +\(lastSavedXP) XP"
                        } else {
                            lastSaveMessage = "Your practice session was added to History."
                        }

                        let didSave = store.addSession(
                            date: Date(),
                            durationSeconds: currentElapsedSeconds,
                            verifiedSeconds: verifiedToSave,
                            unverifiedSeconds: unverifiedToSave,
                            checkInCount: checkInManager.checkInCount,
                            missedCheckInCount: checkInManager.missedCheckInCount,
                            checkInLogJSON: checkInManager.eventsJSON(),
                            notes: notesToSave,
                            noteTitle: cleanedTitle,
                            noteFocus: cleanedFocus,
                            noteMoodRaw: saveDraft.noteMood.rawValue,
                            noteStructuredJSON: structuredJSON
                        )
                        guard didSave else {
                            isSavingSession = false
                            return
                        }

                        // Dismiss first; reset only after sheet dismissal callback.
                        showSaveSheet = false
                        pendingSessionResetAfterSave = true
                        pendingSavedAlertAfterDismiss = true
                    }
                    .font(type.button)
                    .disabled(currentElapsedSeconds == 0 || isSavingSession)
                }
            }
            .alert("Discard Session?", isPresented: $showDiscardConfirm) {
                Button("Keep Editing", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    resetSession()
                    showSaveSheet = false
                }
            } message: {
                Text("Your current practice time and notes will be lost.")
            }
        }
    }

    private func makeEmptyPiece() -> PracticeSessionJournalPiece {
        PracticeSessionJournalPiece(
            title: "",
            tempo: "",
            wentWell: "",
            needsWork: "",
            nextAction: ""
        )
    }

    private func cleanedJournalPieces(from pieces: [PracticeSessionJournalPiece]) -> [PracticeSessionJournalPiece] {
        pieces
            .map { piece in
                PracticeSessionJournalPiece(
                    id: piece.id,
                    title: piece.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    tempo: piece.tempo.trimmingCharacters(in: .whitespacesAndNewlines),
                    wentWell: piece.wentWell.trimmingCharacters(in: .whitespacesAndNewlines),
                    needsWork: piece.needsWork.trimmingCharacters(in: .whitespacesAndNewlines),
                    nextAction: piece.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { piece in
                !(piece.title.isEmpty &&
                  piece.tempo.isEmpty &&
                  piece.wentWell.isEmpty &&
                  piece.needsWork.isEmpty &&
                  piece.nextAction.isEmpty)
            }
    }

    private func pieceBinding(
        _ pieceID: UUID,
        _ keyPath: WritableKeyPath<PracticeSessionJournalPiece, String>
    ) -> Binding<String> {
        Binding(
            get: {
                saveDraft.pieces.first(where: { $0.id == pieceID })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let idx = saveDraft.pieces.firstIndex(where: { $0.id == pieceID }) else { return }
                saveDraft.pieces[idx][keyPath: keyPath] = newValue
            }
        )
    }

    private func journalJSONIfNeeded(_ journal: PracticeSessionJournal) -> String {
        if journal.pieces.isEmpty && journal.reflection.isEmpty { return "" }
        guard let data = try? JSONEncoder().encode(journal),
              let raw = String(data: data, encoding: .utf8) else {
            return ""
        }
        return raw
    }

    private func legacyNotesFallback(
        title: String,
        focus: String,
        mood: PracticeNoteMood,
        journal: PracticeSessionJournal
    ) -> String {
        var lines: [String] = []
        if !title.isEmpty { lines.append("# \(title)") }
        if !focus.isEmpty { lines.append("Focus: \(focus)") }
        lines.append("Mood: \(mood.title)")

        for piece in journal.pieces {
            lines.append("")
            lines.append("## \(piece.title.isEmpty ? "Piece" : piece.title)")
            if !piece.tempo.isEmpty { lines.append("Tempo: \(piece.tempo)") }
            if !piece.wentWell.isEmpty {
                lines.append("- Went well: \(piece.wentWell)")
            }
            if !piece.needsWork.isEmpty {
                lines.append("- Needs work: \(piece.needsWork)")
            }
            if !piece.nextAction.isEmpty {
                lines.append("- Next action: \(piece.nextAction)")
            }
        }

        if !journal.reflection.isEmpty {
            lines.append("")
            lines.append("### Reflection")
            lines.append(journal.reflection)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendProSessionSummary(
        to baseNotes: String,
        totalSeconds: Int,
        verifiedSeconds: Int,
        unverifiedSeconds: Int,
        checkInCount: Int,
        missedCheckInCount: Int,
        metronomeRunning: Bool,
        tunerListening: Bool
    ) -> String {
        let toolFlags: [String] = [
            metronomeRunning ? "Metronome active" : nil,
            tunerListening ? "Tuner active" : nil,
            verificationEnabledForSession ? "Verification enabled" : "Verification off"
        ].compactMap { $0 }

        let summaryLines = [
            "### Session Summary",
            "Total: \(DurationFormatter.string(from: totalSeconds))",
            "Verified: \(DurationFormatter.string(from: verifiedSeconds))",
            "Unverified: \(DurationFormatter.string(from: unverifiedSeconds))",
            "Check-ins: \(checkInCount) total • \(missedCheckInCount) missed",
            "XP awarded: +\(max(0, verifiedSeconds / 60))",
            "Tools: \(toolFlags.isEmpty ? "none" : toolFlags.joined(separator: ", "))"
        ]
        let summary = summaryLines.joined(separator: "\n")
        if baseNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        return "\(baseNotes)\n\n\(summary)"
    }

    private func hapticSoftTap() {
        impact.impactOccurred()
        impact.prepare()
    }

    private func hapticSuccess() {
        notify.notificationOccurred(.success)
        notify.prepare()
    }

    private func toggleMetronome() {
        if metronome.isRunning {
            metronome.stop()
        } else {
            commitMetronomeTempoDraft()
            let effectiveSoundRaw = JourneyProgressManager.preferredMetronomeSoundStyleRaw() ?? metronomeSoundStyleRaw
            metronome.start(
                beatsPerBar: metronomeBeatsPerBar,
                subdivision: MetronomeEngine.Subdivision(rawValue: metronomeSubdivisionRaw) ?? .none,
                soundStyle: MetronomeEngine.SoundStyle(rawValue: effectiveSoundRaw) ?? .click
            )
        }
    }

    private func sanitizeMetronomeSettings() {
        metronomeBPM = min(max(metronomeBPM, 40), 220)
        metronomeBeatsPerBar = MetronomeEngine.clampBeatsPerBar(metronomeBeatsPerBar)
        metronomeSubdivisionRaw = (MetronomeEngine.Subdivision(rawValue: metronomeSubdivisionRaw) ?? .none).rawValue
        let preferred = JourneyProgressManager.preferredMetronomeSoundStyleRaw() ?? metronomeSoundStyleRaw
        metronomeSoundStyleRaw = (MetronomeEngine.SoundStyle(rawValue: preferred) ?? .click).rawValue
        syncMetronomeTempoDraft(force: true)
    }

    private func tempoNudgeButton(label: String, delta: Int) -> some View {
        Button(label) {
            hapticSoftTap()
            setMetronomeTempo(Int(metronomeTempoDraft.rounded()) + delta)
        }
        .font(type.footnote)
        .buttonStyle(.bordered)
    }

    private func setMetronomeTempo(_ newTempo: Int) {
        let clamped = min(max(newTempo, 40), 220)
        metronomeTempoDraft = Double(clamped)
        isDraggingMetronomeTempo = false
        if metronomeBPM != clamped {
            metronomeBPM = clamped
        } else {
            metronome.setBPM(clamped)
            applyMetronomeConfiguration()
        }
    }

    private func commitMetronomeTempoDraft() {
        setMetronomeTempo(Int(metronomeTempoDraft.rounded()))
    }

    private func syncMetronomeTempoDraft(force: Bool = false) {
        guard force || !isDraggingMetronomeTempo else { return }
        metronomeTempoDraft = Double(min(max(metronomeBPM, 40), 220))
    }

    private func registerTapTempo() {
        let now = Date()
        tapTempoMarks.append(now)
        tapTempoMarks = tapTempoMarks.filter { now.timeIntervalSince($0) <= 3.0 }
        guard tapTempoMarks.count >= 2 else { return }

        let recent = Array(tapTempoMarks.suffix(5))
        let intervals = zip(recent.dropFirst(), recent).map { $0.timeIntervalSince($1) }
        guard !intervals.isEmpty else { return }

        let average = intervals.reduce(0, +) / Double(intervals.count)
        guard average > 0 else { return }
        let bpm = Int((60.0 / average).rounded())
        setMetronomeTempo(bpm)
    }

    private var defaultSessionBuilderTemplate: SessionBuilderTemplate {
        SessionBuilderTemplate(
            id: "session_builder",
            name: String(localized: "Practice Session"),
            tasks: [
                SessionBuilderTask(id: "builder_task_warmup", title: String(localized: "Warm-up"), minutes: 10),
                SessionBuilderTask(id: "builder_task_technique", title: String(localized: "Technique"), minutes: 15),
                SessionBuilderTask(id: "builder_task_repertoire", title: String(localized: "Repertoire"), minutes: 20)
            ]
        )
    }

    private func loadSessionBuilderTemplate() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: Constants.sessionBuilderStorageKey),
           let decoded = try? JSONDecoder().decode(SessionBuilderTemplate.self, from: data) {
            let sanitized = SessionBuilderTemplate(
                id: "session_builder",
                name: String(localized: "Practice Session"),
                tasks: decoded.tasks.isEmpty ? defaultSessionBuilderTemplate.tasks : decoded.tasks
            )
            sessionBuilderTemplate = sanitized
            persistSessionBuilderTemplate()
            return
        }

        if let legacyData = defaults.data(forKey: Constants.legacyTemplatesStorageKey),
           let legacyDecoded = try? JSONDecoder().decode([LegacyEditableSessionTemplate].self, from: legacyData),
           let firstLegacyTemplate = legacyDecoded.first {
            sessionBuilderTemplate = SessionBuilderTemplate(
                id: "session_builder",
                name: String(localized: "Practice Session"),
                tasks: [
                    SessionBuilderTask(id: UUID().uuidString, title: String(localized: "Warm-up"), minutes: firstLegacyTemplate.warmupMinutes),
                    SessionBuilderTask(id: UUID().uuidString, title: String(localized: "Technique"), minutes: firstLegacyTemplate.techniqueMinutes),
                    SessionBuilderTask(id: UUID().uuidString, title: String(localized: "Repertoire"), minutes: firstLegacyTemplate.repertoireMinutes)
                ]
            )
            persistSessionBuilderTemplate()
            return
        }

        sessionBuilderTemplate = defaultSessionBuilderTemplate
        persistSessionBuilderTemplate()
    }

    private func persistSessionBuilderTemplate() {
        guard let data = try? JSONEncoder().encode(sessionBuilderTemplate) else { return }
        UserDefaults.standard.set(data, forKey: Constants.sessionBuilderStorageKey)
    }

    private func addSessionTask() {
        let nextIndex = sessionBuilderTemplate.tasks.count + 1
        sessionBuilderTemplate.tasks.append(
            SessionBuilderTask(
                id: UUID().uuidString,
                title: L10n.f("Task %@", "\(nextIndex)"),
                minutes: 10
            )
        )
    }

    private func removeSessionTask(id: String) {
        guard sessionBuilderTemplate.tasks.count > 1 else { return }
        sessionBuilderTemplate.tasks.removeAll { $0.id == id }
    }

    private func startSessionFromBuilder() {
        let tasks = sessionBuilderTemplate.normalizedTasks
        guard !tasks.isEmpty else { return }
        let sessionName = String(localized: "Practice Session")
        let focus = tasks
            .map(\.title)
            .joined(separator: " • ")

        saveDraft = SessionSaveDraft(
            noteTitle: sessionName,
            noteFocus: focus,
            noteMood: .good,
            pieces: tasks.map { task in
                PracticeSessionJournalPiece(
                    title: task.title,
                    tempo: "\(task.minutes) min",
                    wentWell: "",
                    needsWork: "",
                    nextAction: ""
                )
            },
            reflection: ""
        )

        accumulatedSeconds = 0
        resetTrackedPracticeCounters()
        startEpoch = Date().timeIntervalSince1970
        isRunning = true
        activeSessionBuilderPlan = ActiveSessionBuilderPlan(
            id: UUID().uuidString,
            name: sessionName,
            tasks: tasks
        )
        queueSessionBuilderNotificationSync()
    }

    private func sessionTaskProgressRows(
        for plan: ActiveSessionBuilderPlan,
        elapsedSeconds: Int
    ) -> [SessionTaskProgressRow] {
        let elapsed = max(0, elapsedSeconds)
        var cursor = 0
        return plan.tasks.map { task in
            let blockSeconds = max(0, task.minutes) * 60
            let start = cursor
            let end = cursor + blockSeconds
            cursor = end

            let isComplete = elapsed >= end
            let isCurrent = !isComplete && elapsed >= start && elapsed < end
            let into = max(0, min(blockSeconds, elapsed - start))
            let progress = blockSeconds > 0 ? min(1.0, Double(into) / Double(blockSeconds)) : 1.0
            let remaining = isComplete ? 0 : max(0, end - elapsed)

            return SessionTaskProgressRow(
                id: task.id,
                title: task.title,
                minutes: task.minutes,
                progress: isComplete ? 1.0 : progress,
                isCurrent: isCurrent,
                isComplete: isComplete,
                remainingSeconds: remaining
            )
        }
    }

    private func syncSessionBuilderNotifications(force: Bool = false) async {
        guard !Task.isCancelled else { return }
        let center = UNUserNotificationCenter.current()
        let prefix = "pb.practice.session.task."

        guard isRunning, let plan = activeSessionBuilderPlan else {
            lastSessionNotificationSignature = ""
            let existing = await center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            guard !Task.isCancelled else { return }
            if !existing.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: existing)
            }
            return
        }

        let status = await center.notificationSettings().authorizationStatus
        guard !Task.isCancelled else { return }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let elapsed = max(0, currentElapsedSeconds)
        var boundarySeconds: [Int] = []
        var running = 0
        for task in plan.tasks {
            running += max(0, task.minutes) * 60
            if running > elapsed {
                boundarySeconds.append(running)
            }
        }
        let signature = boundarySeconds.map(String.init).joined(separator: "|")
        guard force || signature != lastSessionNotificationSignature else { return }
        lastSessionNotificationSignature = signature

        let existing = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        guard !Task.isCancelled else { return }
        if !existing.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: existing)
        }

        var cursor = 0
        for (index, task) in plan.tasks.enumerated() {
            let blockSeconds = max(0, task.minutes) * 60
            cursor += blockSeconds
            let remainingFromNow = cursor - elapsed
            guard remainingFromNow > 0 else { continue }

            let content = UNMutableNotificationContent()
            let isLast = index == plan.tasks.count - 1
            content.title = isLast ? "Session complete" : L10n.f("Next: %@", task.title)
            content.body = isLast
                ? "Your Practice Session Builder plan is complete."
                : L10n.f("%@ starts now.", task.title)
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(remainingFromNow), repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(prefix)\(index)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
            guard !Task.isCancelled else { return }
        }
    }

    private func queueSessionBuilderNotificationSync(force: Bool = false) {
        sessionBuilderNotificationSyncTask?.cancel()
        sessionBuilderNotificationSyncTask = Task {
            await syncSessionBuilderNotifications(force: force)
        }
    }

    private func mmss(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func pauseActiveTimerSession() {
        accumulatedSeconds = currentElapsedSeconds
        isRunning = false
        startEpoch = 0
        backgroundEnteredAt = nil
        if distractionBlockEnabled {
            appShield.stopShielding()
        }
        clearPendingCheckInNotifications()
    }

    private func resetTrackedPracticeCounters() {
        verifiedSeconds = 0
        unverifiedSeconds = 0
        checkInCountSaved = 0
        missedCheckInCountSaved = 0
        checkInEventsJSON = ""
        checkInManager.reset()
    }
}
