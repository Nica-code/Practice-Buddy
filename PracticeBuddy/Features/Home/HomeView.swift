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
        case today = "Today"
        case practice = "Practice"
        case studio = "Studio"

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

    private struct GuidedTemplateSessionPlan: Identifiable {
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
    @State private var selectedHomeArea: HomeArea = .today
    @State private var activePracticeToolSheet: PracticeToolSheet?

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

    private var checkInIntervalPreset: Binding<CheckInIntervalPreset> {
        Binding(
            get: { CheckInIntervalPreset(rawValue: checkInIntervalPresetRaw) ?? .relaxed },
            set: { checkInIntervalPresetRaw = $0.rawValue }
        )
    }

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
    private var verificationEnabledForSession: Bool { checkInsEnabled }
    private var effectiveVerifiedSeconds: Int {
        verificationEnabledForSession ? max(0, verifiedSeconds) : max(0, currentElapsedSeconds)
    }
    private var effectiveUnverifiedSeconds: Int {
        verificationEnabledForSession ? max(0, unverifiedSeconds) : 0
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
                guidedTemplateSessionSheet(for: plan)
            }
        }
        .practiceAppShieldPicker(isPresented: $showAppSelectionPicker, selection: appShield.selectionBinding)
        .overlay {
            if isRunning && verificationEnabledForSession && checkInManager.isAwaitingResponse {
                checkInOverlay
            }
        }
    }

    private var mainScaffold: some View {
        VStack(spacing: 0) {
            homeHeader

            List {
                switch selectedHomeArea {
                case .today:
                    sessionControlSection
                    goalSection
                    practiceTimeSection
                    recentHistorySection
                case .practice:
                    templatesSection
                    practiceToolsSection
                    practiceLabSection
                case .studio:
                    teacherToolsSection
                    linkedAssignmentsSection
                    warmupOfWeekSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .animation(.snappy(duration: 0.28, extraBounce: 0.03), value: selectedHomeArea)
        }
        .background {
            PBBackdropView(palette: palette)
        }
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lifecycleScaffold: some View {
        mainScaffold
            .onAppear {
                if !animateHeader {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                        animateHeader = true
                    }
                }
                impact.prepare()
                notify.prepare()
                sanitizeMetronomeSettings()
                metronome.setBPM(metronomeBPM)
                metronome.applyUpdatedConfiguration(
                    beatsPerBar: metronomeBeatsPerBar,
                    subdivision: MetronomeEngine.Subdivision(rawValue: metronomeSubdivisionRaw) ?? .none,
                    soundStyle: MetronomeEngine.SoundStyle(rawValue: metronomeSoundStyleRaw) ?? .click
                )

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
                        // Let tab transition complete before heavy setup runs.
                        await Task.yield()
                        social.configure(modelContext: modelContext)
                        social.refresh()
                        // Refresh shield state lazily unless user has the feature enabled.
                        if distractionBlockEnabled {
                            appShield.refreshState()
                        }
                        checkInManager.restoreCounters(
                            checkInCount: checkInCountSaved,
                            missedCheckInCount: missedCheckInCountSaved,
                            events: decodedCheckInEvents(from: checkInEventsJSON)
                        )
                        checkInManager.updateConfiguration(
                            promptRange: (CheckInIntervalPreset(rawValue: checkInIntervalPresetRaw) ?? .relaxed).rangeSeconds
                        )
                    }
                } else {
                    checkInManager.updateConfiguration(
                        promptRange: (CheckInIntervalPreset(rawValue: checkInIntervalPresetRaw) ?? .relaxed).rangeSeconds
                    )
                }
            }
            .onChange(of: isRunning) { _, running in
                if running {
                    now = Date()
                    startTicker()
                } else {
                    stopTicker()
                }
            }
            .onChange(of: distractionBlockEnabled) { _, enabled in
                if !enabled {
                    appShield.stopShielding()
                } else if isRunning {
                    Task { await appShield.startShieldingIfPossible() }
                }
            }
            .onChange(of: checkInsEnabled) { _, enabled in
                if !enabled {
                    checkInStatusMessage = nil
                    unverifiedSeconds = 0
                    checkInManager.reset()
                    checkInEventsJSON = ""
                    clearPendingCheckInNotifications()
                } else if hasAnyTime {
                    checkInManager.restoreCounters(
                        checkInCount: checkInCountSaved,
                        missedCheckInCount: missedCheckInCountSaved,
                        events: decodedCheckInEvents(from: checkInEventsJSON)
                    )
                    checkInManager.updateConfiguration(
                        promptRange: (CheckInIntervalPreset(rawValue: checkInIntervalPresetRaw) ?? .relaxed).rangeSeconds
                    )
                    if scenePhase != .active {
                        scheduleBackgroundCheckInNotification()
                    }
                }
            }
            .onChange(of: checkInIntervalPresetRaw) { _, _ in
                checkInManager.updateConfiguration(
                    promptRange: (CheckInIntervalPreset(rawValue: checkInIntervalPresetRaw) ?? .relaxed).rangeSeconds
                )
                if scenePhase != .active, isRunning, verificationEnabledForSession {
                    scheduleBackgroundCheckInNotification()
                }
            }
            .onChange(of: checkInNotificationsEnabled) { _, enabled in
                if !enabled {
                    clearPendingCheckInNotifications()
                } else if scenePhase != .active, isRunning, verificationEnabledForSession {
                    scheduleBackgroundCheckInNotification()
                }
            }
            .onDisappear {
                stopTicker()
                // Keep metronome running across app/tab transitions.
                // This allows continued playback when screen locks/backgrounds.
                tuner.stopListening()
                tuner.stopReferenceTone()
                appShield.stopShielding()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    applyBackgroundElapsedCatchUp()
                    clearPendingCheckInNotifications()
                } else if isRunning {
                    if backgroundEnteredAt == nil {
                        backgroundEnteredAt = Date()
                    }
                    if verificationEnabledForSession {
                        scheduleBackgroundCheckInNotification()
                    }
                }
            }
            .onChange(of: metronomeBPM) { _, newBPM in
                let clamped = min(max(newBPM, 40), 220)
                if clamped != metronomeBPM {
                    metronomeBPM = clamped
                    return
                }
                metronome.setBPM(clamped)
                metronome.applyUpdatedConfiguration(
                    beatsPerBar: metronomeBeatsPerBar,
                    subdivision: MetronomeEngine.Subdivision(rawValue: metronomeSubdivisionRaw) ?? .none,
                    soundStyle: MetronomeEngine.SoundStyle(rawValue: metronomeSoundStyleRaw) ?? .click
                )
            }
            .onChange(of: metronomeBeatsPerBar) { _, newBeats in
                let clamped = MetronomeEngine.clampBeatsPerBar(newBeats)
                if clamped != metronomeBeatsPerBar {
                    metronomeBeatsPerBar = clamped
                    return
                }
                metronome.applyUpdatedConfiguration(
                    beatsPerBar: clamped,
                    subdivision: MetronomeEngine.Subdivision(rawValue: metronomeSubdivisionRaw) ?? .none,
                    soundStyle: MetronomeEngine.SoundStyle(rawValue: metronomeSoundStyleRaw) ?? .click
                )
            }
            .onChange(of: metronomeSubdivisionRaw) { _, _ in
                metronome.applyUpdatedConfiguration(
                    beatsPerBar: metronomeBeatsPerBar,
                    subdivision: MetronomeEngine.Subdivision(rawValue: metronomeSubdivisionRaw) ?? .none,
                    soundStyle: MetronomeEngine.SoundStyle(rawValue: metronomeSoundStyleRaw) ?? .click
                )
            }
            .onChange(of: metronomeSoundStyleRaw) { _, _ in
                metronome.applyUpdatedConfiguration(
                    beatsPerBar: metronomeBeatsPerBar,
                    subdivision: MetronomeEngine.Subdivision(rawValue: metronomeSubdivisionRaw) ?? .none,
                    soundStyle: MetronomeEngine.SoundStyle(rawValue: metronomeSoundStyleRaw) ?? .click
                )
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

            if checkInManager.isAwaitingResponse {
                unverifiedSeconds += 1
            } else {
                verifiedSeconds += 1
            }
            checkInCountSaved = checkInManager.checkInCount
            missedCheckInCountSaved = checkInManager.missedCheckInCount
            checkInEventsJSON = checkInManager.eventsJSON()
        } else {
            verifiedSeconds += 1
            unverifiedSeconds = 0
            checkInStatusMessage = nil
        }
    }

    private func applyBackgroundElapsedCatchUp() {
        guard let started = backgroundEnteredAt else { return }
        backgroundEnteredAt = nil

        guard isRunning else { return }
        let delta = max(0, Int(Date().timeIntervalSince(started)))
        guard delta > 0 else { return }

        if verificationEnabledForSession {
            unverifiedSeconds += delta
            checkInStatusMessage = "Background time counted as unverified."
        } else {
            verifiedSeconds += delta
        }
    }

    private func scheduleBackgroundCheckInNotification() {
        guard checkInNotificationsEnabled, verificationEnabledForSession, isRunning else { return }

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

    private func compactTimeStat(title: String, seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
            Text(DurationFormatter.string(from: seconds))
                .font(type.number)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .pbSurfaceCard(palette: palette, cornerRadius: 12)
    }

    private func practiceLabCard(title: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.accent)

            Text(LocalizedStringKey(title))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(LocalizedStringKey(subtitle))
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .frame(width: 220, height: 140, alignment: .topLeading)
        .padding(12)
        .pbSurfaceCard(palette: palette, cornerRadius: 14)
    }

    private func practiceToolCard(title: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.accent)

            Text(LocalizedStringKey(title))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)

            Text(LocalizedStringKey(subtitle))
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .frame(width: 220, height: 102, alignment: .topLeading)
        .padding(12)
        .pbSurfaceCard(palette: palette, cornerRadius: 14)
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
        .pbModernCard(palette: palette)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .offset(y: animateHeader ? 0 : 12)
        .opacity(animateHeader ? 1 : 0)
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

    private var sessionControlSection: some View {
        Section("Practice Timer") {
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

            if verificationEnabledForSession {
                Text("XP, quests, and tokens are awarded from verified minutes only.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
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
            } else {
                Text("Verification is OFF. This session will not award XP, quests, or tokens.")
                    .font(type.footnote)
                    .foregroundStyle(.orange)
            }

            DisclosureGroup("Verification & Focus Settings") {
                if verificationEnabledForSession {
                    HStack {
                        Text("Check-ins")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                        Text(
                            L10n.f(
                                "%@ responded • %@ missed",
                                "\(max(0, checkInManager.checkInCount - checkInManager.missedCheckInCount))",
                                "\(checkInManager.missedCheckInCount)"
                            )
                        )
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                    }
                    Picker("Check-in interval", selection: checkInIntervalPreset) {
                        ForEach(CheckInIntervalPreset.allCases) { preset in
                            Text(LocalizedStringKey(preset.titleKey)).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(type.footnote)
                    Toggle("Lock-screen check-in alerts", isOn: $checkInNotificationsEnabled)
                        .font(type.footnote)
                }

                Toggle("Block Distracting Apps (Screen Time)", isOn: $distractionBlockEnabled)
                    .font(type.body)

                if distractionBlockEnabled {
                    HStack(spacing: 10) {
                        Button("Select Apps") {
                            showAppSelectionPicker = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appShield.isAvailable)
                        Button("Authorize") {
                            Task { await appShield.requestAuthorization() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appShield.isAvailable)
                    }
                    Text(LocalizedStringKey(appShield.statusLine))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var practiceTimeSection: some View {
        Section("Practice Time") {
            HStack(spacing: 10) {
                compactTimeStat(title: "Today", seconds: store.totalTodaySeconds)
                compactTimeStat(title: "Week", seconds: store.totalThisWeekSeconds)
                compactTimeStat(title: "Month", seconds: store.totalThisMonthSeconds)
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
        .listRowBackground(palette.surface)
    }

    private var goalSection: some View {
        Section("Goal") {
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
        .listRowBackground(palette.surface)
    }

    private var recentHistorySection: some View {
        Section("Recent History") {
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
        .listRowBackground(palette.surface)
    }

    private var practiceToolsSection: some View {
        Section("Practice Tools") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    Button {
                        activePracticeToolSheet = .metronome
                    } label: {
                        practiceToolCard(
                            title: "Metronome",
                            subtitle: L10n.f("%@ BPM • %@", "\(metronomeBPM)", metronome.isRunning ? "Running" : "Tap to start"),
                            icon: "metronome"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        activePracticeToolSheet = .tuner
                    } label: {
                        practiceToolCard(
                            title: "Tuner",
                            subtitle: L10n.f(
                                "A=%@ • %@",
                                "\(tunerReferenceHz)",
                                tuner.isListening ? "Listening" : "Tap to tune"
                            ),
                            icon: "tuningfork"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var teacherToolsSection: some View {
        Section("Teacher Tools") {
            if purchaseManager.isPro {
                NavigationLink {
                    PBLazyView(StudioManagerView())
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
        .listRowBackground(palette.surface)
    }

    private var practiceLabSection: some View {
        Section("Practice Lab") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    NavigationLink {
                        PBLazyView(PlanExecuteReflectView())
                    } label: {
                        practiceLabCard(
                            title: "Plan → Execute → Reflect",
                            subtitle: "Build goals, run timed blocks, and save reflection notes.",
                            icon: "list.bullet.clipboard"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        PBLazyView(WarmUpGeneratorView())
                    } label: {
                        practiceLabCard(
                            title: "Warm-up Generator",
                            subtitle: "Create a warm-up plan.",
                            icon: "figure.run"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        PBLazyView(ScaleIntonationView())
                    } label: {
                        practiceLabCard(
                            title: "Scale Intonation Score",
                            subtitle: "Play scales and get note-by-note pitch feedback.",
                            icon: "tuningfork"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        PBLazyView(RunThroughModeView())
                    } label: {
                        practiceLabCard(
                            title: "Run-through Mode",
                            subtitle: "Record one-take performances with quick self-review.",
                            icon: "record.circle"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var warmupOfWeekSection: some View {
        Section("Warm-up of the Week") {
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
        .listRowBackground(palette.surface)
    }

    private var linkedAssignmentsSection: some View {
        Section("Today’s Assignments") {
            if assignmentLinkManager.todayAssignments.isEmpty {
                Text("No assignments due today.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(assignmentLinkManager.todayAssignments) { item in
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
                }
            }

            if let msg = assignmentLinkManager.statusMessage, !msg.isEmpty {
                Text(LocalizedStringKey(msg))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .listRowBackground(palette.surface)
    }

    @ViewBuilder
    private var templatesSection: some View {
        Section("Session Templates") {
            if purchaseManager.isPro {
                ForEach($editableTemplates) { $template in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Template name", text: $template.name)
                            .font(type.body)

                        VStack(spacing: 8) {
                            stepperMinutes("Warm-up", value: $template.warmupMinutes)
                            stepperMinutes("Technique", value: $template.techniqueMinutes)
                            stepperMinutes("Repertoire", value: $template.repertoireMinutes)
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
        .listRowBackground(palette.surface)
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
                        if verificationEnabledForSession {
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
            metronome.start(
                beatsPerBar: metronomeBeatsPerBar,
                subdivision: MetronomeEngine.Subdivision(rawValue: metronomeSubdivisionRaw) ?? .none,
                soundStyle: MetronomeEngine.SoundStyle(rawValue: metronomeSoundStyleRaw) ?? .click
            )
        }
    }

    private func sanitizeMetronomeSettings() {
        metronomeBPM = min(max(metronomeBPM, 40), 220)
        metronomeBeatsPerBar = MetronomeEngine.clampBeatsPerBar(metronomeBeatsPerBar)
        metronomeSubdivisionRaw = (MetronomeEngine.Subdivision(rawValue: metronomeSubdivisionRaw) ?? .none).rawValue
        metronomeSoundStyleRaw = (MetronomeEngine.SoundStyle(rawValue: metronomeSoundStyleRaw) ?? .click).rawValue
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

    private func stepperMinutes(_ title: String, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Button {
                value.wrappedValue = max(0, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.textSecondary)

            Text(L10n.f("%@ min", "\(value.wrappedValue)"))
                .font(type.number)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .center)

            Button {
                value.wrappedValue = min(90, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .pbSurfaceCard(palette: palette, cornerRadius: 12)
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

    private func guidedTemplateSessionSheet(for plan: GuidedTemplateSessionPlan) -> some View {
        let guidance = templateGuidance(for: plan, elapsedSeconds: currentElapsedSeconds)
        return Form {
            Section("Session") {
                HStack {
                    Text(plan.name)
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(DurationFormatter.string(from: currentElapsedSeconds))
                        .font(type.number)
                        .foregroundStyle(palette.accent)
                        .monospacedDigit()
                }

                HStack {
                    Text("Current")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(guidance.currentBlockTitle)
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                }

                HStack {
                    Text(guidance.nextLabel)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(mmss(guidance.secondsToNext))
                        .font(type.number)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                }
            }

            Section("Blocks") {
                templateSessionRow("Warm-up", minutes: plan.warmupMinutes, isActive: guidance.currentBlockTitle == "Warm-up")
                templateSessionRow("Technique", minutes: plan.techniqueMinutes, isActive: guidance.currentBlockTitle == "Technique")
                templateSessionRow("Repertoire", minutes: plan.repertoireMinutes, isActive: guidance.currentBlockTitle == "Repertoire")
            }
        }
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .navigationTitle("Template Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    activeTemplateSessionPlan = nil
                }
            }
        }
    }

    private func templateSessionRow(_ title: String, minutes: Int, isActive: Bool) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(L10n.f("%@ min", "\(minutes)"))
                .font(type.number)
                .foregroundStyle(isActive ? palette.accent : palette.textSecondary)
                .monospacedDigit()
        }
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

private struct TunerNeedleGauge: View {
    let cents: Double?
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let centerX = width / 2
            let clamped = max(-50.0, min(50.0, cents ?? 0))
            let x = centerX + CGFloat(clamped / 50.0) * (width * 0.42)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)

                Rectangle()
                    .fill(accent.opacity(0.25))
                    .frame(width: width * 0.04)
                    .position(x: centerX, y: geo.size.height * 0.5)

                Rectangle()
                    .fill(.secondary.opacity(0.3))
                    .frame(width: 1, height: geo.size.height * 0.7)
                    .position(x: centerX, y: geo.size.height * 0.5)

                Rectangle()
                    .fill(cents == nil ? .secondary : accent)
                    .frame(width: 2, height: geo.size.height * 0.86)
                    .position(x: x, y: geo.size.height * 0.5)
                    .animation(.easeOut(duration: 0.12), value: x)

                HStack {
                    Text("Flat")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("In Tune")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Sharp")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .position(x: centerX, y: geo.size.height - 10)
            }
        }
    }
}

@MainActor
final class MetronomeEngine: ObservableObject {
    enum Subdivision: String, CaseIterable, Identifiable {
        case none
        case eighths
        case triplets
        case sixteenths

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "1/4"
            case .eighths: return "8th"
            case .triplets: return "Triplet"
            case .sixteenths: return "16th"
            }
        }

        var stepFactor: Int {
            switch self {
            case .none: return 1
            case .eighths: return 2
            case .triplets: return 3
            case .sixteenths: return 4
            }
        }
    }

    enum SoundStyle: String, CaseIterable, Identifiable {
        case click
        case wood
        case beep

        var id: String { rawValue }

        var title: String {
            switch self {
            case .click: return "Click"
            case .wood: return "Wood"
            case .beep: return "Beep"
            }
        }
    }

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var currentBeat: Int = 0
    @Published private(set) var currentSubdivision: Int = 0
    @Published private(set) var pulseToken: Int = 0

    private(set) var bpm: Int = 80

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private var tickBuffer: AVAudioPCMBuffer?
    private var accentBuffer: AVAudioPCMBuffer?
    private var subdivisionBuffer: AVAudioPCMBuffer?
    private var renderFormat: AVAudioFormat?
    private var timerCancellable: AnyCancellable?
    private var stepIndex: Int = 0
    private var didSetupAudio = false
    private var beatsPerBar: Int = 4
    private var subdivision: Subdivision = .none
    private var soundStyle: SoundStyle = .click

    static func clampBeatsPerBar(_ value: Int) -> Int {
        [2, 3, 4, 6].contains(value) ? value : 4
    }

    func setBPM(_ newBPM: Int) {
        bpm = min(max(newBPM, 40), 220)
    }

    func start(beatsPerBar: Int, subdivision: Subdivision, soundStyle: SoundStyle) {
        self.beatsPerBar = Self.clampBeatsPerBar(beatsPerBar)
        self.subdivision = subdivision
        self.soundStyle = soundStyle

        setAudioSessionIfNeeded()
        setupAudioIfNeeded()
        rebuildBuffersIfPossible()

        stepIndex = 0
        isRunning = true
        playTick(isAccent: true)
        currentBeat = 1
        currentSubdivision = 1
        pulseToken += 1

        startTicker()
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        isRunning = false
        currentBeat = 0
        currentSubdivision = 0
        stepIndex = 0
    }

    func applyUpdatedConfiguration(beatsPerBar: Int, subdivision: Subdivision, soundStyle: SoundStyle) {
        self.beatsPerBar = Self.clampBeatsPerBar(beatsPerBar)
        self.subdivision = subdivision

        if self.soundStyle != soundStyle {
            self.soundStyle = soundStyle
            rebuildBuffersIfPossible()
        }

        guard isRunning else { return }
        startTicker()
    }

    private func startTicker() {
        timerCancellable?.cancel()
        let factor = max(1, subdivision.stepFactor)
        let interval = 60.0 / (Double(max(40, bpm)) * Double(factor))

        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.advanceStep()
            }
    }

    private func advanceStep() {
        let factor = max(1, subdivision.stepFactor)
        let totalSteps = max(1, beatsPerBar * factor)
        stepIndex = (stepIndex + 1) % totalSteps

        let stepInBeat = stepIndex % factor
        let beatIndex = stepIndex / factor

        let isDownbeat = (stepIndex == 0)
        let isBeatBoundary = (stepInBeat == 0)

        if isDownbeat {
            playTick(isAccent: true)
            pulseToken += 1
        } else if isBeatBoundary {
            playTick(isAccent: false)
            pulseToken += 1
        } else {
            playSubdivisionTick()
        }

        currentBeat = beatIndex + 1
        currentSubdivision = stepInBeat + 1
    }

    private func setAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal; metronome will just be silent if audio session fails.
        }
    }

    private func setupAudioIfNeeded() {
        guard !didSetupAudio else { return }
        didSetupAudio = true

        engine.attach(player)
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let playerFormat = AVAudioFormat(
            standardFormatWithSampleRate: mixerFormat.sampleRate,
            channels: mixerFormat.channelCount
        )
        renderFormat = playerFormat
        engine.connect(player, to: engine.mainMixerNode, format: playerFormat)

        do {
            try engine.start()
            player.play()
        } catch {
            // Non-fatal; metronome UI can still operate.
        }
    }

    private func rebuildBuffersIfPossible() {
        guard let format = renderFormat else { return }

        switch soundStyle {
        case .click:
            accentBuffer = makeClickBuffer(format: format, frequency: 1900, milliseconds: 20, amplitude: 0.70)
            tickBuffer = makeClickBuffer(format: format, frequency: 1500, milliseconds: 18, amplitude: 0.52)
            subdivisionBuffer = makeClickBuffer(format: format, frequency: 1200, milliseconds: 14, amplitude: 0.32)
        case .wood:
            accentBuffer = makeClickBuffer(format: format, frequency: 720, milliseconds: 26, amplitude: 0.80)
            tickBuffer = makeClickBuffer(format: format, frequency: 520, milliseconds: 22, amplitude: 0.58)
            subdivisionBuffer = makeClickBuffer(format: format, frequency: 360, milliseconds: 16, amplitude: 0.34)
        case .beep:
            accentBuffer = makeClickBuffer(format: format, frequency: 1120, milliseconds: 40, amplitude: 0.62)
            tickBuffer = makeClickBuffer(format: format, frequency: 860, milliseconds: 34, amplitude: 0.48)
            subdivisionBuffer = makeClickBuffer(format: format, frequency: 700, milliseconds: 24, amplitude: 0.28)
        }
    }

    private func playTick(isAccent: Bool) {
        guard let buffer = isAccent ? accentBuffer : tickBuffer else { return }

        if !engine.isRunning {
            try? engine.start()
        }
        if !player.isPlaying {
            player.play()
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    private func playSubdivisionTick() {
        guard subdivision != .none else { return }
        guard let buffer = subdivisionBuffer else { return }

        if !engine.isRunning {
            try? engine.start()
        }
        if !player.isPlaying {
            player.play()
        }

        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    private func makeClickBuffer(
        format: AVAudioFormat,
        frequency: Double,
        milliseconds: Double,
        amplitude: Float
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(max(1, Int((milliseconds / 1000.0) * sampleRate)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        guard let channels = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount)

        for channelIndex in 0..<channelCount {
            let channel = channels[channelIndex]
            for i in 0..<Int(frameCount) {
                let t = Double(i) / sampleRate
                let decay = exp(-28.0 * t)
                let sample = sin(2.0 * .pi * frequency * t) * decay
                channel[i] = Float(sample) * amplitude
            }
        }

        return buffer
    }
}

@MainActor
final class PracticeAppShieldManager: ObservableObject {
    private let defaults = UserDefaults.standard
    private let selectionDataKey = "pb.practice.screenTime.selection.v1"

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var selectedAppsCount: Int = 0
    @Published var statusMessage: String?
    private var hasFamilyControlsEntitlement: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "PBEnableFamilyControls") as? Bool) == true
    }

#if canImport(FamilyControls) && canImport(ManagedSettings)
    @Published var selection = FamilyActivitySelection() {
        didSet {
            selectedAppsCount = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
            persistSelection()
        }
    }
    private var managedStore: ManagedSettingsStore?
#endif

    init() {
        refreshState()
    }

    var statusLine: String {
        if let statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }
        if !isAvailable {
            return "Screen Time app blocking is unavailable on this device/configuration."
        }
        if !isAuthorized {
            return "Authorization needed. Tap Authorize, then choose apps to block."
        }
        if selectedAppsCount == 0 {
            return "No apps/categories selected yet. Tap Select Apps."
        }
        return "\(selectedAppsCount) target(s) selected for blocking during practice."
    }

    func refreshState() {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        guard hasFamilyControlsEntitlement else {
            isAvailable = false
            isAuthorized = false
            selectedAppsCount = 0
            return
        }
        if #available(iOS 16.0, *) {
            isAvailable = true
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            loadSelection()
        } else {
            isAvailable = false
            isAuthorized = false
            selectedAppsCount = 0
        }
#else
        isAvailable = false
        isAuthorized = false
        selectedAppsCount = 0
#endif
    }

    func requestAuthorization() async {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        guard hasFamilyControlsEntitlement else {
            isAvailable = false
            isAuthorized = false
            statusMessage = "Screen Time blocking isn't available in this build."
            return
        }
        guard #available(iOS 16.0, *), isAvailable else {
            statusMessage = "Screen Time blocking isn't available here."
            return
        }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            statusMessage = isAuthorized ? "Screen Time authorization granted." : "Screen Time authorization not granted."
        } catch {
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
            statusMessage = L10n.f("Screen Time authorization failed: %@", error.localizedDescription)
        }
#else
        statusMessage = "Screen Time blocking requires FamilyControls support."
#endif
    }

    func startShieldingIfPossible() async {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        guard hasFamilyControlsEntitlement else {
            isAvailable = false
            isAuthorized = false
            statusMessage = "Screen Time blocking isn't available in this build."
            return
        }
        guard #available(iOS 16.0, *), isAvailable else {
            statusMessage = "Screen Time blocking isn't available here."
            return
        }

        if !isAuthorized {
            await requestAuthorization()
        }
        guard isAuthorized else { return }

        guard selectedAppsCount > 0 else {
            statusMessage = "Pick apps or categories first with Select Apps."
            return
        }

        let store = managedStore ?? ManagedSettingsStore()
        managedStore = store
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        statusMessage = "Distracting apps/categories are blocked while practice is running."
#else
        statusMessage = "Screen Time blocking requires FamilyControls support."
#endif
    }

    func stopShielding() {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        guard let store = managedStore else { return }
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
#endif
    }

#if canImport(FamilyControls) && canImport(ManagedSettings)
    var selectionBinding: Binding<FamilyActivitySelection>? {
        guard #available(iOS 16.0, *), hasFamilyControlsEntitlement else { return nil }
        return Binding(
            get: { self.selection },
            set: {
                self.selection = $0
                self.statusMessage = nil
            }
        )
    }

    private func persistSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: selectionDataKey)
    }

    private func loadSelection() {
        guard let data = defaults.data(forKey: selectionDataKey),
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            selectedAppsCount = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
            return
        }
        selection = decoded
        selectedAppsCount = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }
#else
    var selectionBinding: Binding<Never>? { nil }
#endif

}

private struct PracticeAppShieldPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
#if canImport(FamilyControls) && canImport(ManagedSettings)
    let selection: Binding<FamilyActivitySelection>?
#else
    let selection: Binding<Never>?
#endif

    func body(content: Content) -> some View {
#if canImport(FamilyControls) && canImport(ManagedSettings)
        if #available(iOS 16.0, *) {
            if let selection {
                content.familyActivityPicker(isPresented: $isPresented, selection: selection)
            } else {
                content
            }
        } else {
            content
        }
#else
        content
#endif
    }
}

private extension View {
#if canImport(FamilyControls) && canImport(ManagedSettings)
    func practiceAppShieldPicker(
        isPresented: Binding<Bool>,
        selection: Binding<FamilyActivitySelection>?
    ) -> some View {
        modifier(PracticeAppShieldPickerModifier(isPresented: isPresented, selection: selection))
    }
#else
    func practiceAppShieldPicker(
        isPresented: Binding<Bool>,
        selection: Binding<Never>?
    ) -> some View {
        modifier(PracticeAppShieldPickerModifier(isPresented: isPresented, selection: selection))
    }
#endif
}
