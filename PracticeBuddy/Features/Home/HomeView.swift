import SwiftUI
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
    @EnvironmentObject private var assignmentLinkManager: AssignmentLinkManager
    @EnvironmentObject private var warmupOfWeekManager: WarmupOfWeekManager
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
        static let templatesStorageKey = "pb.home.editableSessionTemplates.v1"
    }

    private enum HomeArea: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case practice = "Practice"
        case studio = "Studio"

        var id: String { rawValue }
    }

    private enum HomeNavigationTarget: String, Identifiable {
        case studioManagerTeacher
        case studioPlanner

        var id: String { rawValue }
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

    private struct PracticeTemplate: Identifiable {
        let id: String
        let name: String
        let focus: String
        let warmupMinutes: Int
        let etudeMinutes: Int
        let repertoireMinutes: Int
    }

    private struct EditableSessionTemplate: Identifiable, Codable, Equatable {
        let id: String
        var name: String
        var warmupMinutes: Int
        var techniqueMinutes: Int
        var repertoireMinutes: Int

        var totalMinutes: Int { warmupMinutes + techniqueMinutes + repertoireMinutes }

        var focusSummary: String {
            "Warm-up \(warmupMinutes) • Technique \(techniqueMinutes) • Repertoire \(repertoireMinutes)"
        }

        var asPracticeTemplate: PracticeTemplate {
            PracticeTemplate(
                id: id,
                name: name,
                focus: focusSummary,
                warmupMinutes: warmupMinutes,
                etudeMinutes: techniqueMinutes,
                repertoireMinutes: repertoireMinutes
            )
        }
    }

    struct GuidedTemplateSessionPlan: Identifiable {
        let id = UUID()
        let name: String
        let warmupMinutes: Int
        let techniqueMinutes: Int
        let repertoireMinutes: Int

        var totalSeconds: Int {
            max(0, warmupMinutes) * 60
            + max(0, techniqueMinutes) * 60
            + max(0, repertoireMinutes) * 60
        }
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
    @State private var editableTemplates: [EditableSessionTemplate] = []
    @State private var activeTemplateSessionPlan: GuidedTemplateSessionPlan?
    @State private var showAppSelectionPicker = false
    @State private var selectedHomeArea: HomeArea = .dashboard
    @State private var activePracticeToolSheet: PracticeToolSheet?
    @State private var showShopSheet = false
    @State private var showVerificationInfoSheet = false
    @State private var showGoalReachedBanner = false
    @State private var homeNavigationTarget: HomeNavigationTarget?

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

    private var metronomeBPMDouble: Binding<Double> {
        Binding(
            get: { Double(metronomeBPM) },
            set: { metronomeBPM = Int($0.rounded()) }
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
        .sheet(item: $activeTemplateSessionPlan) { plan in
            NavigationStack {
                GuidedTemplateSessionSheetView(
                    plan: plan,
                    guidance: templateGuidance(for: plan, elapsedSeconds: currentElapsedSeconds),
                    elapsedSeconds: currentElapsedSeconds,
                    palette: palette,
                    chrome: chrome,
                    type: type,
                    formatTime: mmss
                ) {
                    activeTemplateSessionPlan = nil
                }
            }
        }
        .practiceAppShieldPicker(isPresented: $showAppSelectionPicker, selection: appShield.selectionBinding)
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
                .onTapGesture {
                    selectedHomeArea = .dashboard
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .navigationDestination(item: $homeNavigationTarget) { target in
            switch target {
            case .studioManagerTeacher:
                PBLazyView(StudioManagerView(entryMode: .teacher))
            case .studioPlanner:
                PBLazyView(StudioPlannerView())
            }
        }
    }

    private var mainScaffold: some View {
        VStack(spacing: 0) {
            homeShortcutRow
            homeHeader

            List {
                switch selectedHomeArea {
                case .dashboard:
                    sessionControlSection
                    goalSection
                    practiceTimeSection
                    recentHistorySection
                case .practice:
                    templatesSection
                    practiceToolsSection
                    practiceLabSection
                case .studio:
                    if purchaseManager.canAccessTeacherTools {
                        teacherToolsSection
                    }
                    if purchaseManager.canAccessStudentTools {
                        linkedAssignmentsSection
                        warmupOfWeekSection
                        studentToolsSection
                    }
                    if !purchaseManager.canAccessTeacherTools && !purchaseManager.canAccessStudentTools {
                        studioToolsOffSection
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .animation(.snappy(duration: 0.28, extraBounce: 0.03), value: selectedHomeArea)
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
                loadEditableTemplates()
            }
            Task { @MainActor in
                await Task.yield()
                social.configure(modelContext: modelContext)
                social.refresh()
                if distractionBlockEnabled {
                    appShield.refreshState()
                }
                checkInManager.restoreCounters(
                    checkInCount: checkInCountSaved,
                    missedCheckInCount: missedCheckInCountSaved,
                    events: decodedCheckInEvents(from: checkInEventsJSON)
                )
                checkInManager.updateConfiguration(
                    promptRange: checkInRandomPromptRange
                )
            }
        } else {
            checkInManager.updateConfiguration(
                promptRange: checkInRandomPromptRange
            )
        }
        handleGoalReachedBannerIfNeeded()
    }

    private func handleLifecycleDisappear() {
        stopTicker()
        tuner.stopListening()
        tuner.stopReferenceTone()
        appShield.stopShielding()
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
            checkInManager.restoreCounters(
                checkInCount: checkInCountSaved,
                missedCheckInCount: missedCheckInCountSaved,
                events: decodedCheckInEvents(from: checkInEventsJSON)
            )
            checkInManager.updateConfiguration(
                promptRange: checkInRandomPromptRange
            )
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
            if isRunning {
                Task { await appShield.startShieldingIfPossible() }
            } else {
                appShield.refreshState()
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
        checkInManager.updateConfiguration(
            promptRange: checkInRandomPromptRange
        )
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

        if verificationMechanismActive {
            unverifiedSeconds += delta
            checkInStatusMessage = "Background time counted as unverified."
        } else {
            unverifiedSeconds += delta
        }
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
                    Text(L10n.f("%@ BPM", "\(metronomeBPM)"))
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                Slider(value: metronomeBPMDouble, in: 40...220, step: 1)

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

            Picker("Home Area", selection: $selectedHomeArea) {
                ForEach(HomeArea.allCases) { area in
                    Text(LocalizedStringKey(area.rawValue)).tag(area)
                }
            }
            .pickerStyle(.segmented)
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
                            .fill(verificationMechanismActive ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(verificationMechanismActive ? "Verification active" : "Verification inactive")
                            .font(type.footnote)
                            .foregroundStyle(verificationMechanismActive ? Color.green : Color.orange)
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
                        HStack(spacing: 10) {
                            Button("Select Apps") {
                                PBHaptics.tap()
                                showAppSelectionPicker = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(!appShield.isAvailable)
                            Button("Authorize") {
                                PBHaptics.tap()
                                Task { await appShield.requestAuthorization() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(!appShield.isAvailable)
                        }

                        Text(LocalizedStringKey(appShield.statusLine))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                } label: {
                    Text("Verification details")
                        .font(type.footnote)
                        .foregroundStyle(palette.textPrimary)
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
                                .frame(width: 170, alignment: .leading)
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

    private var practiceToolsSection: some View {
        Section {
            homeSectionCard {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button {
                            activePracticeToolSheet = .metronome
                        } label: {
                            PracticeToolCardView(
                                title: "Metronome",
                                subtitle: L10n.f("%@ BPM • %@", "\(metronomeBPM)", metronome.isRunning ? "Running" : "Tap to start"),
                                icon: "metronome",
                                palette: palette,
                                type: type
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            activePracticeToolSheet = .tuner
                        } label: {
                            PracticeToolCardView(
                                title: "Tuner",
                                subtitle: L10n.f(
                                    "A=%@ • %@",
                                    "\(tunerReferenceHz)",
                                    tuner.isListening ? "Listening" : "Tap to tune"
                                ),
                                icon: "tuningfork",
                                palette: palette,
                                type: type
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Practice Tools")
        }
    }

    private var teacherToolsSection: some View {
        Section {
            homeSectionCard {
                if purchaseManager.isPro {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            homeNavigationTarget = .studioManagerTeacher
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Studio Manager")
                                    .font(type.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text("Create your studio, manage roster, and publish assignments.")
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            homeNavigationTarget = .studioPlanner
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Studio Planner")
                                    .font(type.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text("Plan lessons, studio class, and recital events with calendar sync.")
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Teacher tools are part of Practice Buddy Pro.")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        Button("Open Practice Buddy Pro") {
                            selectedTab = 4
                        }
                        .buttonStyle(.bordered)
                        .font(type.footnote)
                    }
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Teacher Tools")
        }
    }

    private var studentToolsSection: some View {
        Section {
            homeSectionCard {
                if purchaseManager.isPro {
                    NavigationLink {
                        PBLazyView(StudioManagerView(entryMode: .student))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your Studio")
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Text("Join your teacher's studio, review roster, and track assignment progress.")
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Student studio tools are part of Practice Buddy Pro.")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        Button("Open Practice Buddy Pro") {
                            selectedTab = 4
                        }
                        .buttonStyle(.bordered)
                        .font(type.footnote)
                    }
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Student Tools")
        }
    }

    private var studioToolsOffSection: some View {
        Section {
            homeSectionCard {
                Text("No studio tools are enabled. Update Tool Access in Settings.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        } header: {
            PBSectionHeaderLabel(title: "Studio")
        }
    }

    private var practiceLabSection: some View {
        Section {
            homeSectionCard {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        NavigationLink {
                            PBLazyView(PlanExecuteReflectView())
                        } label: {
                            PracticeLabCardView(
                                title: "Plan → Execute → Reflect",
                                subtitle: "Build goals, run timed blocks, and save reflection notes.",
                                icon: "list.bullet.clipboard",
                                palette: palette,
                                type: type
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            PBLazyView(WarmUpGeneratorView())
                        } label: {
                            PracticeLabCardView(
                                title: "Warm-up Generator",
                                subtitle: "Create a warm-up plan.",
                                icon: "figure.run",
                                palette: palette,
                                type: type
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            PBLazyView(ScaleIntonationView())
                        } label: {
                            PracticeLabCardView(
                                title: "Scale Intonation Score",
                                subtitle: "Play scales and get note-by-note pitch feedback.",
                                icon: "tuningfork",
                                palette: palette,
                                type: type
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            PBLazyView(RunThroughModeView())
                        } label: {
                            PracticeLabCardView(
                                title: "Run-through Mode",
                                subtitle: "Record one-take performances with quick self-review.",
                                icon: "record.circle",
                                palette: palette,
                                type: type
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Practice Lab")
        }
    }

    private var warmupOfWeekSection: some View {
        Section {
            homeSectionCard {
                if let warmup = warmupOfWeekManager.warmup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(warmup.title)
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)
                        Text(L10n.f("%@ min • %@ • %@", "\(warmup.totalMinutes)", warmup.instrument, warmup.focus))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        NavigationLink {
                            PBLazyView(WarmUpGeneratorView())
                        } label: {
                            Text("Open Warm-up Generator")
                                .font(type.footnote)
                        }
                    }
                } else {
                    Text("No studio warm-up published.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Warm-up of the Week")
        }
    }

    private var linkedAssignmentsSection: some View {
        Section {
            homeSectionCard {
                if assignmentLinkManager.todayAssignments.isEmpty {
                    Text("No assignments due today.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(Array(assignmentLinkManager.todayAssignments.enumerated()), id: \.element.id) { idx, item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.title)
                                    .font(type.body)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Button {
                                    Task {
                                        await assignmentLinkManager.markAssignmentCompletion(item.id, completed: !item.completed)
                                    }
                                } label: {
                                    Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.completed ? palette.accent : palette.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 10) {
                                Button(assignmentLinkManager.isAssignmentLinked(item.id) ? "Unlink" : "Link") {
                                    assignmentLinkManager.linkAssignment(
                                        assignmentLinkManager.isAssignmentLinked(item.id) ? nil : item.id
                                    )
                                }
                                .buttonStyle(.bordered)
                                .font(type.footnote)

                                if assignmentLinkManager.isAssignmentLinked(item.id) {
                                    NavigationLink {
                                        PBLazyView(PlanExecuteReflectView())
                                    } label: {
                                        Text("Start Linked Plan")
                                            .font(type.footnote)
                                    }

                                    NavigationLink {
                                        PBLazyView(RunThroughModeView())
                                    } label: {
                                        Text("Start Linked Run-through")
                                            .font(type.footnote)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        if idx < assignmentLinkManager.todayAssignments.count - 1 {
                            Divider()
                        }
                    }
                }

                if let msg = assignmentLinkManager.statusMessage, !msg.isEmpty {
                    Text(LocalizedStringKey(msg))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Today’s Assignments")
        }
    }

    @ViewBuilder
    private var templatesSection: some View {
        Section {
            homeSectionCard {
                if purchaseManager.isPro {
                    ForEach(Array($editableTemplates.enumerated()), id: \.element.id) { idx, $template in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Template name", text: $template.name)
                                .font(type.body)

                            VStack(spacing: 8) {
                                StepperMinutesRow(title: "Warm-up", value: $template.warmupMinutes, palette: palette, type: type)
                                StepperMinutesRow(title: "Technique", value: $template.techniqueMinutes, palette: palette, type: type)
                                StepperMinutesRow(title: "Repertoire", value: $template.repertoireMinutes, palette: palette, type: type)
                            }

                            HStack {
                                Spacer()
                                Button("Start") {
                                    hapticSoftTap()
                                    applyTemplate(template.asPracticeTemplate)
                                }
                                .buttonStyle(.borderedProminent)
                                .font(type.button)
                            }
                        }
                        .padding(.vertical, 4)
                        if idx < editableTemplates.count - 1 {
                            Divider()
                        }
                    }
                    .onChange(of: editableTemplates) { _, _ in
                        persistEditableTemplates()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Template-based planning is a Pro feature.")
                            .font(type.body)
                            .foregroundStyle(palette.textSecondary)
                        Button("Unlock Pro") {
                            selectedTab = 4
                        }
                        .font(type.button)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Session Templates")
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
        return String(localized: "Ready")
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
            accumulatedSeconds = currentElapsedSeconds
            isRunning = false
            startEpoch = 0
            backgroundEnteredAt = nil
            if distractionBlockEnabled {
                appShield.stopShielding()
            }
            clearPendingCheckInNotifications()
        } else {
            if !hasAnyTime {
                accumulatedSeconds = 0
                verifiedSeconds = 0
                unverifiedSeconds = 0
                checkInCountSaved = 0
                missedCheckInCountSaved = 0
                checkInEventsJSON = ""
                checkInManager.reset()
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
    }

    private func stopTapped() {
        if isRunning {
            accumulatedSeconds = currentElapsedSeconds
            isRunning = false
            startEpoch = 0
            backgroundEnteredAt = nil
            if distractionBlockEnabled {
                appShield.stopShielding()
            }
            clearPendingCheckInNotifications()
        }
        if saveDraft.pieces.isEmpty {
            saveDraft.pieces = [makeEmptyPiece()]
        }
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
        activeTemplateSessionPlan = nil
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
                        let notesToSave = purchaseManager.isPro
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
            "### Pro Session Summary",
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
    }

    private var defaultEditableTemplates: [EditableSessionTemplate] {
        [
            EditableSessionTemplate(
                id: "template_quick_reset",
                name: String(localized: "Short Session"),
                warmupMinutes: 5,
                techniqueMinutes: 7,
                repertoireMinutes: 8
            ),
            EditableSessionTemplate(
                id: "template_balanced_session",
                name: String(localized: "Standard Session"),
                warmupMinutes: 10,
                techniqueMinutes: 15,
                repertoireMinutes: 20
            ),
            EditableSessionTemplate(
                id: "template_deep_work",
                name: String(localized: "Deep Focus"),
                warmupMinutes: 10,
                techniqueMinutes: 20,
                repertoireMinutes: 30
            )
        ]
    }

    private func loadEditableTemplates() {
        guard let data = UserDefaults.standard.data(forKey: Constants.templatesStorageKey),
              let decoded = try? JSONDecoder().decode([EditableSessionTemplate].self, from: data),
              !decoded.isEmpty else {
            editableTemplates = defaultEditableTemplates
            persistEditableTemplates()
            return
        }
        editableTemplates = decoded
    }

    private func persistEditableTemplates() {
        guard let data = try? JSONEncoder().encode(editableTemplates) else { return }
        UserDefaults.standard.set(data, forKey: Constants.templatesStorageKey)
    }

    private func applyTemplate(_ template: PracticeTemplate) {
        saveDraft = SessionSaveDraft(
            noteTitle: template.name,
            noteFocus: template.focus,
            noteMood: .good,
            pieces: [
            PracticeSessionJournalPiece(
                title: "Warm-up",
                tempo: "\(template.warmupMinutes) min",
                wentWell: "",
                needsWork: "",
                nextAction: ""
            ),
            PracticeSessionJournalPiece(
                title: "Technique",
                tempo: "\(template.etudeMinutes) min",
                wentWell: "",
                needsWork: "",
                nextAction: ""
            ),
            PracticeSessionJournalPiece(
                title: "Repertoire",
                tempo: "\(template.repertoireMinutes) min",
                wentWell: "",
                needsWork: "",
                nextAction: ""
            )
        ],
            reflection: ""
        )

        accumulatedSeconds = 0
        verifiedSeconds = 0
        unverifiedSeconds = 0
        checkInCountSaved = 0
        missedCheckInCountSaved = 0
        checkInEventsJSON = ""
        checkInManager.reset()
        startEpoch = Date().timeIntervalSince1970
        isRunning = true
        activeTemplateSessionPlan = GuidedTemplateSessionPlan(
            name: template.name,
            warmupMinutes: template.warmupMinutes,
            techniqueMinutes: template.etudeMinutes,
            repertoireMinutes: template.repertoireMinutes
        )
    }

    private func templateGuidance(for plan: GuidedTemplateSessionPlan, elapsedSeconds: Int) -> (
        currentBlockTitle: String,
        secondsToNext: Int,
        nextLabel: String,
        phaseProgress: Double,
        totalProgress: Double
    ) {
        let blocks: [(title: String, seconds: Int)] = [
            ("Warm-up", max(0, plan.warmupMinutes) * 60),
            ("Technique", max(0, plan.techniqueMinutes) * 60),
            ("Repertoire", max(0, plan.repertoireMinutes) * 60)
        ].filter { $0.seconds > 0 }

        guard !blocks.isEmpty else {
            return ("Complete", 0, "Time to next", 1.0, 1.0)
        }

        let total = max(1, blocks.reduce(0) { $0 + $1.seconds })
        let elapsed = max(0, elapsedSeconds)
        var running = 0

        for (index, block) in blocks.enumerated() {
            let start = running
            let end = running + block.seconds
            if elapsed < end {
                let into = max(0, elapsed - start)
                let remaining = max(0, end - elapsed)
                let nextLabel = index < blocks.count - 1
                    ? L10n.f("Time to %@", blocks[index + 1].title)
                    : String(localized: "Time remaining")
                return (
                    currentBlockTitle: block.title,
                    secondsToNext: remaining,
                    nextLabel: nextLabel,
                    phaseProgress: block.seconds > 0 ? min(1, Double(into) / Double(block.seconds)) : 1,
                    totalProgress: min(1, Double(elapsed) / Double(total))
                )
            }
            running = end
        }

        return ("Complete", 0, String(localized: "Session complete"), 1.0, 1.0)
    }

    private func mmss(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}
