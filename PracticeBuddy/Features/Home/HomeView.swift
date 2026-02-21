import SwiftUI
import Combine
import AVFoundation

struct HomeView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0

    // Timer persisted state
    @AppStorage("pb.practice.accumulatedSeconds") private var accumulatedSeconds: Int = 0
    @AppStorage("pb.practice.startEpoch") private var startEpoch: Double = 0
    @AppStorage("pb.practice.isRunning") private var isRunning: Bool = false

    // Goal settings
    @AppStorage("pb.settings.dailyGoalMinutes") private var goalMinutes: Int = 30
    @AppStorage("pb.settings.goalScope") private var goalScopeRaw: String = GoalScope.today.rawValue

    // Home display settings
    @AppStorage("pb.home.practiceTimeMode") private var practiceTimeModeRaw: String = PracticeTimeDisplayMode.all.rawValue
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
    @State private var metronomePulseScale: CGFloat = 1.0

    private enum Constants {
        static let tickSeconds: TimeInterval = 1
        static let titleTopPadding: CGFloat = 18
        static let titleBottomPadding: CGFloat = 8
    }

    private struct PracticeTemplate: Identifiable {
        let id: String
        let name: String
        let focus: String
        let warmupMinutes: Int
        let etudeMinutes: Int
        let repertoireMinutes: Int
    }

    // Save flow
    @State private var showSaveSheet = false
    @State private var noteTitle: String = ""
    @State private var noteFocus: String = ""
    @State private var noteMood: PracticeNoteMood = .good
    @State private var journalPieces: [PracticeSessionJournalPiece] = []
    @State private var journalReflection: String = ""
    @State private var showSavedAlert = false
    @State private var showDiscardConfirm = false

    // Haptics
    private let impact = UIImpactFeedbackGenerator(style: .soft)
    private let notify = UINotificationFeedbackGenerator()

    // MARK: - Bindings

    private var practiceTimeMode: Binding<PracticeTimeDisplayMode> {
        Binding(
            get: { PracticeTimeDisplayMode(rawValue: practiceTimeModeRaw) ?? .all },
            set: { practiceTimeModeRaw = $0.rawValue }
        )
    }

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

    // MARK: - Timer derived

    private var startDate: Date? {
        startEpoch > 0 ? Date(timeIntervalSince1970: startEpoch) : nil
    }

    private var currentElapsedSeconds: Int {
        if isRunning, let startDate {
            let running = Int(now.timeIntervalSince(startDate))
            return accumulatedSeconds + max(0, running)
        } else {
            return accumulatedSeconds
        }
    }

    private var hasAnyTime: Bool { currentElapsedSeconds > 0 }
    private var canStop: Bool { hasAnyTime || isRunning }

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
        VStack(spacing: 0) {
            Text("Let’s Practice!")
                .font(type.appTitle)
                .tracking(type.heroTracking)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, Constants.titleTopPadding)
                .padding(.bottom, Constants.titleBottomPadding)
                .foregroundStyle(palette.textPrimary)

            List {
                Section {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isRunning ? "Practicing" : (hasAnyTime ? "Paused" : "Ready"))
                                .font(type.statusLabel)
                                .foregroundStyle(palette.textSecondary)

                            Text(DurationFormatter.string(from: currentElapsedSeconds))
                                .font(type.timer)
                                .monospacedDigit()
                                .foregroundStyle(palette.textPrimary)
                        }

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
                    .padding(.vertical, 4)
                }
                .listRowBackground(palette.surface)

                Section("Practice Time") {
                    Picker("View", selection: practiceTimeMode) {
                        ForEach(PracticeTimeDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch PracticeTimeDisplayMode(rawValue: practiceTimeModeRaw) ?? .all {
                    case .today:
                        row("Today", seconds: store.totalTodaySeconds)
                    case .week:
                        row("This week", seconds: store.totalThisWeekSeconds)
                    case .month:
                        row("This month", seconds: store.totalThisMonthSeconds)
                    case .all:
                        row("Today", seconds: store.totalTodaySeconds)
                        row("This week", seconds: store.totalThisWeekSeconds)
                        row("This month", seconds: store.totalThisMonthSeconds)
                    }

                    ShareLink(item: social.shareText(for: sharePeriodForCurrentMode)) {
                        Label("Share Practice Time", systemImage: "square.and.arrow.up")
                            .font(type.body)
                    }
                    .buttonStyle(.bordered)
                }
                .listRowBackground(palette.surface)

                templatesSection

                practiceToolsSection

                Section("Goal") {
                    Picker("Period", selection: goalScope) {
                        ForEach(GoalScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    if goalMinutes == 0 {
                        Text("Goal is off. Turn it on in Settings.")
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text((GoalScope(rawValue: goalScopeRaw) ?? .today) == .today ? "Today" :
                                     (GoalScope(rawValue: goalScopeRaw) ?? .today) == .week ? "This week" : "This month")
                                    .foregroundStyle(palette.textPrimary)

                                Spacer()

                                Text("\(DurationFormatter.string(from: scopedSeconds)) / \(goalMinutes) min")
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
                                    Text("\(streakDays) day\(streakDays == 1 ? "" : "s")")
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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .background(chrome.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
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

            social.configure(modelContext: modelContext)
            social.refresh()
        }
        .onChange(of: isRunning) { _, running in
            if running {
                now = Date()
                startTicker()
            } else {
                stopTicker()
            }
        }
        .onDisappear {
            stopTicker()
            // Keep metronome running across app/tab transitions.
            // This allows continued playback when screen locks/backgrounds.
            tuner.stopListening()
            tuner.stopReferenceTone()
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
        .onReceive(metronome.$pulseToken.removeDuplicates()) { token in
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
        .onReceive(store.$sessions) { _ in
            social.refresh()
        }
        .sheet(isPresented: $showSaveSheet) {
            saveSheet
        }
        .alert("Saved!", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your practice session was added to History.")
        }
    }

    // MARK: - Ticker control

    private func startTicker() {
        guard timerCancellable == nil else { return }
        timerCancellable = Timer.publish(every: Constants.tickSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                now = Date()
            }
    }

    private func stopTicker() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func row(_ title: String, seconds: Int) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(DurationFormatter.string(from: seconds))
                .font(type.number)
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
        }
    }

    private var sharePeriodForCurrentMode: SocialPeriod {
        switch PracticeTimeDisplayMode(rawValue: practiceTimeModeRaw) ?? .all {
        case .today:
            return .today
        case .week:
            return .week
        case .month:
            return .month
        case .all:
            return .week
        }
    }

    private var practiceToolsSection: some View {
        Section("Practice Tools") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Metronome")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(metronomeBPM) BPM")
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
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Sound", selection: metronomeSoundStyle) {
                    ForEach(MetronomeEngine.SoundStyle.allCases) { style in
                        Text(style.title).tag(style)
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

                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Tuner")
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
                        Text("Detected: \(tuner.detectedNoteName)")
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
                        Text(status)
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(palette.surface)
    }

    @ViewBuilder
    private var templatesSection: some View {
        Section("Session Templates") {
            if purchaseManager.isPro {
                ForEach(practiceTemplates) { template in
                    Button {
                        hapticSoftTap()
                        applyTemplate(template)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Text(template.focus)
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Template-based planning is a Pro feature.")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)
                    Button("Unlock Pro") {
                        selectedTab = 3
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
                return "Beat \(metronome.currentBeat).\(metronome.currentSubdivision)"
            }
            return "Beat \(metronome.currentBeat)/\(metronomeBeatsPerBar)"
        }
        return "Ready"
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
        } else {
            if !hasAnyTime {
                accumulatedSeconds = 0
            }
            startEpoch = Date().timeIntervalSince1970
            isRunning = true
        }
    }

    private func stopTapped() {
        if isRunning {
            accumulatedSeconds = currentElapsedSeconds
            isRunning = false
            startEpoch = 0
        }
        if journalPieces.isEmpty {
            journalPieces = [makeEmptyPiece()]
        }
        showSaveSheet = true
    }

    private func resetSession() {
        accumulatedSeconds = 0
        startEpoch = 0
        isRunning = false
        noteTitle = ""
        noteFocus = ""
        noteMood = .good
        journalPieces = [makeEmptyPiece()]
        journalReflection = ""
    }

    private var saveSheet: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    Text("Duration: \(DurationFormatter.string(from: currentElapsedSeconds))")
                        .font(type.number)
                        .foregroundStyle(palette.textPrimary)
                }

                Section("Journal Header") {
                    TextField("Session title", text: $noteTitle)
                        .font(type.body)

                    TextField("Overall focus", text: $noteFocus)
                        .font(type.body)

                    Picker("Mood", selection: $noteMood) {
                        ForEach(PracticeNoteMood.allCases) { mood in
                            Text(mood.title).tag(mood)
                        }
                    }
                }

                Section("Pieces") {
                    if journalPieces.isEmpty {
                        Text("No pieces yet.")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }

                    ForEach($journalPieces) { $piece in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Piece title", text: $piece.title)
                                .font(type.body)

                            TextField("Tempo worked on (optional)", text: $piece.tempo)
                                .font(type.body)

                            TextField("What went well", text: $piece.wentWell, axis: .vertical)
                                .font(type.body)
                                .lineLimit(2...4)

                            TextField("Needs work", text: $piece.needsWork, axis: .vertical)
                                .font(type.body)
                                .lineLimit(2...4)

                            TextField("Next action for tomorrow", text: $piece.nextAction, axis: .vertical)
                                .font(type.body)
                                .lineLimit(2...4)

                            HStack {
                                Spacer()
                                Button("Remove Piece", role: .destructive) {
                                    journalPieces.removeAll { $0.id == piece.id }
                                }
                                .font(type.footnote)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        journalPieces.append(makeEmptyPiece())
                    } label: {
                        Label("Add Piece", systemImage: "plus")
                    }
                    .font(type.button)
                }

                Section("Reflection") {
                    TextField("How did the session feel? What to remember for next time?", text: $journalReflection, axis: .vertical)
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
                        hapticSuccess()
                        let cleanedTitle = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanedFocus = noteFocus.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanedReflection = journalReflection.trimmingCharacters(in: .whitespacesAndNewlines)
                        let cleanedPieces = cleanedJournalPieces(from: journalPieces)
                        let journal = PracticeSessionJournal(pieces: cleanedPieces, reflection: cleanedReflection)
                        let structuredJSON = journalJSONIfNeeded(journal)

                        store.addSession(
                            date: Date(),
                            durationSeconds: currentElapsedSeconds,
                            notes: legacyNotesFallback(
                                title: cleanedTitle,
                                focus: cleanedFocus,
                                mood: noteMood,
                                journal: journal
                            ),
                            noteTitle: cleanedTitle,
                            noteFocus: cleanedFocus,
                            noteMoodRaw: noteMood.rawValue,
                            noteStructuredJSON: structuredJSON
                        )
                        resetSession()
                        showSaveSheet = false
                        showSavedAlert = true
                    }
                    .font(type.button)
                    .disabled(currentElapsedSeconds == 0)
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

    private var practiceTemplates: [PracticeTemplate] {
        [
            PracticeTemplate(
                id: "template_quick_reset",
                name: "Quick Reset (20m)",
                focus: "Warmup 5 • Etude 7 • Repertoire 8",
                warmupMinutes: 5,
                etudeMinutes: 7,
                repertoireMinutes: 8
            ),
            PracticeTemplate(
                id: "template_balanced_session",
                name: "Balanced Session (45m)",
                focus: "Warmup 10 • Etude 15 • Repertoire 20",
                warmupMinutes: 10,
                etudeMinutes: 15,
                repertoireMinutes: 20
            ),
            PracticeTemplate(
                id: "template_deep_work",
                name: "Deep Work (60m)",
                focus: "Warmup 10 • Etude 20 • Repertoire 30",
                warmupMinutes: 10,
                etudeMinutes: 20,
                repertoireMinutes: 30
            )
        ]
    }

    private func applyTemplate(_ template: PracticeTemplate) {
        noteTitle = template.name
        noteFocus = template.focus
        noteMood = .good
        journalReflection = ""
        journalPieces = [
            PracticeSessionJournalPiece(
                title: "Warmup",
                tempo: "\(template.warmupMinutes) min",
                wentWell: "",
                needsWork: "",
                nextAction: ""
            ),
            PracticeSessionJournalPiece(
                title: "Etude",
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
        ]

        accumulatedSeconds = 0
        startEpoch = Date().timeIntervalSince1970
        isRunning = true
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
            case .none: return "Quarter"
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
