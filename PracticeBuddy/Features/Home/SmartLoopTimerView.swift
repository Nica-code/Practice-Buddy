import SwiftUI

struct SmartLoopTimerView: View {
    let nestedWithinPlan: Bool

    init(nestedWithinPlan: Bool = false) {
        self.nestedWithinPlan = nestedWithinPlan
    }

    enum LoopTag: String, CaseIterable, Identifiable {
        case intonation
        case rhythm
        case bowing
        case shifts

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    private struct LoopPreset: Codable, Identifiable {
        let id: UUID
        let name: String
        let settings: SmartLoopSettings
        let tags: [String]
    }

    private struct LegacyLoopPreset: Codable {
        let id: UUID
        let name: String
        let loopDuration: Int
        let restDuration: Int
        let targetLoops: Int
        let metronomeEnabled: Bool
        let tempoStart: Int
        let autoIncreaseEnabled: Bool
        let autoIncreaseEvery: Int
        let autoIncreaseBy: Int
        let tempoLadderEnabled: Bool?
        let tempoLadderCleanLoops: Int?
        let tags: [String]

        var migrated: LoopPreset {
            LoopPreset(
                id: id,
                name: name,
                settings: SmartLoopSettings(
                    loopDurationSeconds: loopDuration,
                    restDurationSeconds: restDuration,
                    targetLoops: targetLoops,
                    runsUntilStopped: false,
                    metronomeEnabled: metronomeEnabled,
                    startingTempoBPM: tempoStart,
                    autoIncreaseEnabled: autoIncreaseEnabled,
                    autoIncreaseEvery: autoIncreaseEvery,
                    tempoIncreaseBPM: autoIncreaseBy,
                    tempoLadderEnabled: tempoLadderEnabled ?? false,
                    cleanLoopsRequired: tempoLadderCleanLoops ?? 3
                ),
                tags: tags
            )
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.studioQuestQAToolState) private var qaToolState
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @AppStorage("pb.loop.duration") private var loopDuration = 45
    @AppStorage("pb.loop.rest") private var restDuration = 20
    @AppStorage("pb.loop.targetLoops") private var targetLoops = 8
    @AppStorage("pb.loop.untilStop") private var untilStop = false
    @AppStorage("pb.loop.metroEnabled") private var metronomeEnabled = true
    @AppStorage("pb.loop.metroStartBPM") private var tempoStartBPM = 72
    @AppStorage("pb.loop.metroAutoEnabled") private var autoIncreaseEnabled = false
    @AppStorage("pb.loop.metroAutoEvery") private var autoIncreaseEvery = 2
    @AppStorage("pb.loop.metroAutoBy") private var autoIncreaseBy = 2
    @AppStorage("pb.loop.tempoLadderEnabled") private var tempoLadderEnabled = false
    @AppStorage("pb.loop.tempoLadderCleanLoops") private var tempoLadderCleanLoops = 3
    @AppStorage("pb.loop.presets.json") private var presetsRaw = ""

    @State private var selectedTags: Set<String> = []
    @State private var runState: SmartLoopRunState?
    @State private var statusMessage: String?
    @State private var statusKind: StudioQuestInlineStatus.Kind = .information
    @State private var replaceAudioConfirmationPresented = false
    @State private var presetNamePromptPresented = false
    @State private var proPresented = false
    @State private var newPresetName = ""
    @State private var pendingResult: PracticeToolResult?
    @State private var completedRun: SmartLoopRunState?
    @State private var didFinish = false
    @State private var didApplyQAState = false

    private var settings: SmartLoopSettings {
        SmartLoopSettings(
            loopDurationSeconds: loopDuration,
            restDurationSeconds: restDuration,
            targetLoops: targetLoops,
            runsUntilStopped: untilStop,
            metronomeEnabled: metronomeEnabled,
            startingTempoBPM: tempoStartBPM,
            autoIncreaseEnabled: autoIncreaseEnabled,
            autoIncreaseEvery: autoIncreaseEvery,
            tempoIncreaseBPM: autoIncreaseBy,
            tempoLadderEnabled: tempoLadderEnabled,
            cleanLoopsRequired: tempoLadderCleanLoops
        )
    }

    private var ownsRuntime: Bool {
        coordinator.activeToolID == .smartLoop
            || (nestedWithinPlan && coordinator.nestedToolID == .smartLoop)
    }

    private var isContextual: Bool {
        nestedWithinPlan || coordinator.toolLaunchContext?.parentSessionID != nil
    }

    private var decodedPresets: [LoopPreset] {
        guard let data = presetsRaw.data(using: .utf8) else {
            return []
        }
        if let value = try? JSONDecoder().decode([LoopPreset].self, from: data) {
            return value
        }
        return (try? JSONDecoder().decode([LegacyLoopPreset].self, from: data))?
            .map(\.migrated)
            ?? []
    }

    private var visibleState: SmartLoopRunState? {
        runState ?? completedRun
    }

    var body: some View {
        StudioQuestToolPage(
            title: "Smart Loop",
            subtitle: "Alternate focused repetitions and deliberate rests, with a tempo ladder that rewards clean work.",
            systemImage: "repeat"
        ) {
            if let runState, runState.phase != .idle, runState.phase != .finished {
                livePanel(runState)
            } else if let result = completedRun ?? runState,
                      result.phase == .finished {
                resultPanel(result)
            } else {
                setupPanel
                tagsPanel
                presetsPanel
            }

            if let statusMessage {
                StudioQuestInlineStatus(text: statusMessage, kind: statusKind)
                    .accessibilityIdentifier("smartloop.status")
            }
        }
        .task {
            apply(settings)
            restoreIfNeeded()
            applyQAStateIfNeeded()
        }
        .onChange(of: coordinator.elapsedSeconds) {
            advanceRun()
        }
        .onDisappear {
            preserveOnExit()
        }
        .confirmationDialog(
            "Replace \(coordinator.audioSession.owner?.displayName ?? "the current audio tool")?",
            isPresented: $replaceAudioConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Replace and start") {
                Task { await startRun(replacingAudio: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PractiQuest allows one audio utility at a time so timing and recordings stay reliable.")
        }
        .alert("Save loop preset", isPresented: $presetNamePromptPresented) {
            TextField("Preset name", text: $newPresetName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                savePreset()
            }
            .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Keep this loop, rest, tempo, and tag setup for another session.")
        }
        .sheet(isPresented: $proPresented) {
            NavigationStack {
                StudioQuestProView()
            }
        }
    }

    private var setupPanel: some View {
        StudioQuestToolSetupPanel {
            settingStepper(
                title: "Loop",
                value: $loopDuration,
                range: 10...600,
                step: 5,
                formattedValue: "\(loopDuration) sec"
            )
            settingStepper(
                title: "Rest",
                value: $restDuration,
                range: 0...180,
                step: 5,
                formattedValue: "\(restDuration) sec"
            )

            Toggle("Run until I stop", isOn: $untilStop)
            if !untilStop {
                settingStepper(
                    title: "Target",
                    value: $targetLoops,
                    range: 1...200,
                    step: 1,
                    formattedValue: "\(targetLoops) loops"
                )
            }

            Divider()

            Toggle("Metronome during work", isOn: $metronomeEnabled)
            if metronomeEnabled {
                settingStepper(
                    title: "Starting tempo",
                    value: $tempoStartBPM,
                    range: 40...220,
                    step: 1,
                    formattedValue: "\(tempoStartBPM) BPM"
                )

                DisclosureGroup("Tempo progression") {
                    VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
                        Toggle("Increase automatically", isOn: $autoIncreaseEnabled)
                            .onChange(of: autoIncreaseEnabled) { _, enabled in
                                if enabled { tempoLadderEnabled = false }
                            }
                        if autoIncreaseEnabled {
                            settingStepper(
                                title: "Advance every",
                                value: $autoIncreaseEvery,
                                range: 1...20,
                                step: 1,
                                formattedValue: "\(autoIncreaseEvery) loops"
                            )
                        }

                        Toggle("Advance after clean loops", isOn: $tempoLadderEnabled)
                            .onChange(of: tempoLadderEnabled) { _, enabled in
                                if enabled { autoIncreaseEnabled = false }
                            }
                        if tempoLadderEnabled {
                            settingStepper(
                                title: "Clean loops needed",
                                value: $tempoLadderCleanLoops,
                                range: 1...10,
                                step: 1,
                                formattedValue: "\(tempoLadderCleanLoops)"
                            )
                        }

                        settingStepper(
                            title: "Tempo increase",
                            value: $autoIncreaseBy,
                            range: 1...10,
                            step: 1,
                            formattedValue: "+\(autoIncreaseBy) BPM"
                        )
                    }
                    .padding(.top, StudioQuestTokens.Spacing.sm)
                }
            }

            Button {
                requestStart()
            } label: {
                Label(
                    coordinator.hasActivePractice ? "Start in current session" : "Start Smart Loop",
                    systemImage: "play.fill"
                )
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())
            .accessibilityIdentifier("smartloop.start")
        }
    }

    private var tagsPanel: some View {
        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
            StudioQuestEyebrow("Focus tags")
            StudioQuestFlowLayout {
                ForEach(LoopTag.allCases) { tag in
                    StudioQuestChoiceChip(
                        title: LocalizedStringKey(tag.title),
                        isSelected: selectedTags.contains(tag.rawValue)
                    ) {
                        if selectedTags.contains(tag.rawValue) {
                            selectedTags.remove(tag.rawValue)
                        } else {
                            selectedTags.insert(tag.rawValue)
                        }
                    }
                    .accessibilityIdentifier("smartloop.tag.\(tag.rawValue)")
                }
            }
        }
        .padding(StudioQuestTokens.Spacing.md)
        .studioQuestSurface()
    }

    private var presetsPanel: some View {
        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
            HStack {
                StudioQuestEyebrow("Presets")
                Spacer()
                Button {
                    requestPresetSave()
                } label: {
                    Label("Save preset", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            }

            if decodedPresets.isEmpty {
                Text("No saved presets yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(decodedPresets) { preset in
                    StudioQuestInteractiveSurface {
                        applyPreset(preset)
                    } content: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.name)
                                    .font(StudioQuestTokens.Typography.cardTitle)
                                Text(
                                    "\(preset.settings.loopDurationSeconds)s loop · \(preset.settings.restDurationSeconds)s rest"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                        }
                        .padding(StudioQuestTokens.Spacing.md)
                        .studioQuestSurface(.flat)
                    }
                }
            }
        }
        .padding(StudioQuestTokens.Spacing.md)
        .studioQuestSurface()
    }

    private func livePanel(_ state: SmartLoopRunState) -> some View {
        StudioQuestToolLivePanel(
            eyebrow: state.phase.isPaused ? "Paused" : "Now"
        ) {
            HStack(alignment: .firstTextBaseline) {
                Text(phaseTitle(state.phase))
                    .font(StudioQuestTokens.Typography.heroTitle)
                    .tracking(-0.5)
                Spacer()
                Text(DurationFormatter.string(from: state.remainingSeconds()))
                    .font(StudioQuestTokens.Typography.timer)
                    .monospacedDigit()
                    .minimumScaleFactor(0.62)
            }

            StudioQuestProgressVisualization(
                progress: state.settings.runsUntilStopped
                    ? 0
                    : Double(state.loopsCompleted) / Double(state.settings.targetLoops),
                accessibilityLabel: "Loop target progress"
            )

            HStack(spacing: StudioQuestTokens.Spacing.sm) {
                StudioQuestMetric(
                    title: "Loops",
                    value: state.settings.runsUntilStopped
                        ? "\(state.loopsCompleted)"
                        : "\(state.loopsCompleted) / \(state.settings.targetLoops)"
                )
                StudioQuestMetric(
                    title: "Work time",
                    value: DurationFormatter.string(from: state.totalWorkSeconds()),
                    tint: StudioQuestTokens.ColorRole.violet
                )
                if state.settings.metronomeEnabled {
                    StudioQuestMetric(
                        title: "Tempo",
                        value: "\(state.currentTempoBPM)",
                        detail: "BPM",
                        tint: StudioQuestTokens.ColorRole.mint
                    )
                }
            }

            if state.settings.tempoLadderEnabled {
                VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.sm) {
                    HStack {
                        Text("Clean-loop ladder")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(
                            "\(state.cleanLoopsAtCurrentTempo) / \(state.settings.cleanLoopsRequired)"
                        )
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }

                    Button {
                        markLastLoopClean()
                    } label: {
                        Label("Mark last completed loop clean", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                    .disabled(state.markableCompletedCycle == nil)
                    .accessibilityIdentifier("smartloop.clean")
                }
            }

            HStack(spacing: StudioQuestTokens.Spacing.sm) {
                Button {
                    togglePause()
                } label: {
                    Label(
                        state.phase.isRunning ? "Pause" : "Resume",
                        systemImage: state.phase.isRunning ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(StudioQuestSecondaryButtonStyle())
                .accessibilityIdentifier("smartloop.pause")

                Button {
                    finishRun()
                } label: {
                    Label("Finish", systemImage: "stop.fill")
                }
                .buttonStyle(StudioQuestPrimaryButtonStyle())
                .accessibilityIdentifier("smartloop.finish")
            }
        }
    }

    private func resultPanel(_ state: SmartLoopRunState) -> some View {
        StudioQuestToolResultPanel {
            Label("Loop work complete", systemImage: "checkmark.seal.fill")
                .font(StudioQuestTokens.Typography.sectionTitle)
                .foregroundStyle(StudioQuestTokens.ColorRole.mint)

            HStack(spacing: StudioQuestTokens.Spacing.sm) {
                StudioQuestMetric(title: "Loops", value: "\(state.loopsCompleted)")
                StudioQuestMetric(
                    title: "Work",
                    value: DurationFormatter.string(from: state.totalWorkSeconds()),
                    tint: StudioQuestTokens.ColorRole.violet
                )
                if state.settings.metronomeEnabled {
                    StudioQuestMetric(
                        title: "Tempo",
                        value: "\(state.settings.startingTempoBPM)–\(state.currentTempoBPM)",
                        detail: "BPM",
                        tint: StudioQuestTokens.ColorRole.mint
                    )
                }
            }

            Text(summaryText(state))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if didFinish {
                Button("Done") {
                    if nestedWithinPlan {
                        coordinator.endNestedTool(.smartLoop)
                    } else {
                        coordinator.detachTool()
                    }
                    dismiss()
                }
                .buttonStyle(StudioQuestPrimaryButtonStyle())
                .accessibilityIdentifier("smartloop.done")
            } else {
                Button {
                    saveResult(state)
                } label: {
                    Label(
                        isContextual ? "Add to active session" : "Save loop session",
                        systemImage: "checkmark"
                    )
                }
                .buttonStyle(StudioQuestPrimaryButtonStyle())
                .accessibilityIdentifier("smartloop.save")
            }
        }
    }

    private func settingStepper(
        title: LocalizedStringKey,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        formattedValue: String
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(formattedValue)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityValue(formattedValue)
        }
        .frame(minHeight: 44)
    }

    private func requestStart() {
        if let activeTool = coordinator.activeToolID,
           activeTool != .smartLoop,
           !(nestedWithinPlan && activeTool == .planExecuteReflect) {
            showStatus(
                "Finish or close \(activeTool.title) before starting Smart Loop.",
                kind: .warning
            )
            return
        }
        if metronomeEnabled,
           let owner = coordinator.audioSession.owner,
           owner != .smartLoop {
            replaceAudioConfirmationPresented = true
            return
        }
        Task { await startRun(replacingAudio: false) }
    }

    private func startRun(replacingAudio: Bool) async {
        if metronomeEnabled {
            guard await claimAudio(replacing: replacingAudio) else { return }
        }

        if !ownsRuntime {
            if nestedWithinPlan {
                guard coordinator.beginNestedTool(.smartLoop) != nil else {
                    showStatus(
                        coordinator.toolErrorMessage ?? "Smart Loop could not attach to this plan.",
                        kind: .warning
                    )
                    return
                }
            } else if coordinator.hasActivePractice {
                coordinator.attachTool(.smartLoop)
                if !coordinator.isRunning {
                    coordinator.resume()
                }
            } else {
                let expectedSeconds = untilStop
                    ? max(60, loopDuration)
                    : (loopDuration + restDuration) * max(1, targetLoops)
                coordinator.beginFocusedTool(
                    .smartLoop,
                    title: "Smart Loop",
                    durationMinutes: max(1, Int(ceil(Double(expectedSeconds) / 60))),
                    source: .library
                )
            }
        }

        var state = SmartLoopRunState(settings: settings)
        let events = state.start()
        runState = state
        completedRun = nil
        pendingResult = nil
        didFinish = false
        if !nestedWithinPlan {
            coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        }
        handle(events, state: state)
        showStatus("Smart Loop started.", kind: .information)
    }

    private func togglePause() {
        guard var state = runState else { return }
        if state.phase.isRunning {
            state.pause()
            runState = state
            stopMetronome()
            if !nestedWithinPlan {
                coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            }
            if !isContextual {
                coordinator.pause()
            }
        } else if state.phase.isPaused {
            Task {
                if state.phase == .pausedWork, state.settings.metronomeEnabled {
                    guard await claimAudio(replacing: false) else { return }
                }
                var resumed = state
                let events = resumed.resume()
                runState = resumed
                if !isContextual {
                    coordinator.resume()
                }
                if !nestedWithinPlan {
                    coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(resumed))
                }
                handle(events, state: resumed)
            }
        }
    }

    private func advanceRun() {
        guard var state = runState, state.phase.isRunning else { return }
        let events = state.advance()
        guard state != runState else { return }
        runState = state
        if !nestedWithinPlan {
            coordinator.updateToolRecoveryPayload(recoveryJSON(state))
        }
        handle(events, state: state)
        if state.phase == .finished {
            completeRun(state)
        }
    }

    private func finishRun() {
        guard var state = runState else { return }
        let events = state.stop()
        runState = state
        stopMetronome()
        if !nestedWithinPlan {
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        }
        if !isContextual {
            coordinator.pause()
        }
        handle(events, state: state)
        if state.phase == .finished {
            completeRun(state)
        } else {
            runState = nil
            if nestedWithinPlan {
                coordinator.endNestedTool(.smartLoop)
            } else {
                coordinator.detachTool()
            }
            showStatus("No loop result was created.", kind: .warning)
        }
    }

    private func completeRun(_ state: SmartLoopRunState) {
        stopMetronome()
        completedRun = state
        runState = state
        if !nestedWithinPlan {
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        }
        if !isContextual {
            coordinator.pause()
        }
    }

    private func markLastLoopClean() {
        guard var state = runState else { return }
        let events = state.markLastCompletedLoopClean()
        guard state != runState else {
            showStatus("That completed loop has already been marked.", kind: .warning)
            return
        }
        runState = state
        if !nestedWithinPlan {
            coordinator.updateToolRecoveryPayload(recoveryJSON(state))
        }
        handle(events, state: state)
    }

    private func handle(_ events: [SmartLoopEvent], state: SmartLoopRunState) {
        for event in events {
            switch event {
            case .enteredWork:
                if state.settings.metronomeEnabled {
                    ensureMetronome(tempo: state.currentTempoBPM)
                }
            case .enteredRest, .finished:
                stopMetronome()
            case .tempoChanged(let tempo):
                if state.phase == .work {
                    ensureMetronome(tempo: tempo)
                }
                showStatus("Tempo advanced to \(tempo) BPM.", kind: .success)
            case .completedLoop:
                break
            }
        }
    }

    private func saveResult(_ state: SmartLoopRunState) {
        let resultPayload = SmartLoopResultPayload(
            completedAt: .now,
            loopsCompleted: state.loopsCompleted,
            totalWorkSeconds: state.totalWorkSeconds(),
            settings: state.settings,
            endingTempoBPM: state.currentTempoBPM,
            tags: selectedTags.sorted(),
            parentSessionID: nestedWithinPlan
                ? coordinator.activeSessionID
                : coordinator.toolLaunchContext?.parentSessionID,
            launchSource: nestedWithinPlan
                ? .activeSession
                : (coordinator.toolLaunchContext?.source ?? .legacy),
            toolVersion: 2
        )
        guard let data = try? JSONEncoder().encode(resultPayload),
              let json = String(data: data, encoding: .utf8) else {
            showStatus("The loop result could not be prepared. Please try again.", kind: .error)
            return
        }
        let result = PracticeToolResult(
            toolID: .smartLoop,
            sessionID: coordinator.activeSessionID,
            durationSeconds: state.totalWorkSeconds(),
            metrics: [
                "loops": Double(state.loopsCompleted),
                "startingTempo": Double(state.settings.startingTempoBPM),
                "endingTempo": Double(state.currentTempoBPM)
            ],
            payloadJSON: json
        )
        if isContextual {
            coordinator.attachCompletedToolResult(result)
        } else {
            coordinator.completeTool(result)
        }
        pendingResult = result

        if isContextual {
            didFinish = true
            showStatus(
                "Loop analytics added to your active session. They will save with your reflection.",
                kind: .success
            )
            return
        }

        let notes = """
        Smart Loop
        Loops completed: \(state.loopsCompleted)
        Work time: \(DurationFormatter.string(from: state.totalWorkSeconds()))
        Tempo: \(state.settings.metronomeEnabled ? "\(state.settings.startingTempoBPM)–\(state.currentTempoBPM) BPM" : "Metronome off")
        Tags: \(selectedTags.sorted().joined(separator: ", "))
        """
        let payload = PracticeSavePayload(
            sessionID: coordinator.activeSessionID,
            snapshot: coordinator.snapshot,
            notes: notes,
            noteTitle: "Smart Loop",
            noteFocus: selectedTags.sorted().joined(separator: ", "),
            toolResult: result
        )
        if store.savePracticeCompletion(payload) {
            let savedID = coordinator.activeSessionID
            coordinator.completeAfterSave(savedSessionID: savedID)
            pendingResult = nil
            didFinish = true
            showStatus("Loop session saved.", kind: .success)
        } else {
            showStatus(
                "The loop session could not be saved. Your result is still here—try again.",
                kind: .error
            )
        }
    }

    private func claimAudio(replacing: Bool) async -> Bool {
        if let owner = coordinator.audioSession.owner, owner != .smartLoop {
            guard replacing else {
                replaceAudioConfirmationPresented = true
                return false
            }
            switch owner {
            case .metronome:
                coordinator.metronome.stop()
            case .tuner:
                coordinator.tuner.stopListening()
                coordinator.tuner.stopReferenceTone()
            default:
                showStatus(
                    "\(owner.displayName) cannot be replaced safely. Close it first.",
                    kind: .warning
                )
                return false
            }
            coordinator.audioSession.release(owner)
        }

        do {
            try await coordinator.audioSession.claim(
                .smartLoop,
                requirements: .playback
            )
            return true
        } catch {
            showStatus(
                (error as? LocalizedError)?.errorDescription
                    ?? "Audio could not be started.",
                kind: .error
            )
            return false
        }
    }

    private func startMetronome(tempo: Int) {
        coordinator.metronome.setBPM(tempo)
        coordinator.metronome.start(
            beatsPerBar: 4,
            subdivision: .none,
            soundStyle: MetronomeEngine.SoundStyle(
                rawValue: JourneyProgressManager.preferredMetronomeSoundStyleRaw()
                    ?? "click"
            ) ?? .click
        )
    }

    private func ensureMetronome(tempo: Int) {
        if coordinator.audioSession.owner == .smartLoop {
            startMetronome(tempo: tempo)
            return
        }
        Task {
            guard await claimAudio(replacing: false) else {
                if var state = runState, state.phase.isRunning {
                    state.pause()
                    runState = state
                    if !nestedWithinPlan {
                        coordinator.pauseToolActivity(
                            recoveryPayloadJSON: recoveryJSON(state)
                        )
                    }
                    if !isContextual {
                        coordinator.pause()
                    }
                }
                return
            }
            startMetronome(tempo: tempo)
        }
    }

    private func stopMetronome() {
        coordinator.metronome.stop()
        coordinator.audioSession.release(.smartLoop)
    }

    private func restoreIfNeeded() {
        guard !nestedWithinPlan else { return }
        guard coordinator.activeToolID == .smartLoop,
              let json = coordinator.toolActivityState?.recoveryPayloadJSON,
              let data = json.data(using: .utf8),
              let restored = try? JSONDecoder().decode(
                SmartLoopRunState.self,
                from: data
              ) else {
            return
        }
        apply(restored.settings)
        runState = restored
        if let result = coordinator.latestToolResult,
           result.toolID == .smartLoop {
            pendingResult = result
            completedRun = restored
            didFinish = coordinator.toolLaunchContext?.parentSessionID != nil
        }
        advanceRun()
        if let current = runState,
           current.phase == .work,
           current.settings.metronomeEnabled {
            ensureMetronome(tempo: current.currentTempoBPM)
        }
        showStatus(
            restored.phase.isPaused
                ? "Smart Loop ready to resume."
                : "Smart Loop restored.",
            kind: .information
        )
    }

    private func preserveOnExit() {
        if nestedWithinPlan {
            stopMetronome()
            coordinator.endNestedTool(.smartLoop)
            return
        }
        guard !didFinish,
              coordinator.activeToolID == .smartLoop,
              var state = runState,
              state.phase.isRunning else { return }
        state.pause()
        runState = state
        stopMetronome()
        coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        if !isContextual {
            coordinator.pause()
        }
    }

    #if DEBUG
    private func applyQAStateIfNeeded() {
        guard !didApplyQAState, let qaToolState else { return }
        didApplyQAState = true
        guard qaToolState != .setup else { return }
        if qaToolState == .permissionDenied {
            showStatus(
                "Audio permission is unavailable in this preview state.",
                kind: .error
            )
            return
        }

        metronomeEnabled = false
        loopDuration = 10
        restDuration = 5
        targetLoops = 2
        let fixtureSettings = settings
        if !coordinator.hasActivePractice {
            coordinator.beginFocusedTool(
                .smartLoop,
                title: "Smart Loop",
                durationMinutes: 2,
                source: .qa
            )
        } else if coordinator.activeToolID == nil {
            coordinator.attachTool(.smartLoop, source: .qa)
        }

        var fixture = SmartLoopRunState(settings: fixtureSettings)
        _ = fixture.start(at: .now.addingTimeInterval(-12))
        _ = fixture.advance()
        if qaToolState == .paused || qaToolState == .recovered {
            fixture.pause()
        } else if qaToolState == .completed || qaToolState == .saveError {
            _ = fixture.advance(to: .now.addingTimeInterval(20))
            if fixture.phase != .finished {
                _ = fixture.stop()
            }
            completedRun = fixture
        }
        runState = fixture
        if fixture.phase.isRunning {
            coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(fixture))
        } else {
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(fixture))
            coordinator.pause()
        }
        if qaToolState == .saveError {
            showStatus(
                "The loop session could not be saved. Your result is still here—try again.",
                kind: .error
            )
        } else if qaToolState == .recovered {
            showStatus("Smart Loop ready to resume.", kind: .information)
        }
    }
    #else
    private func applyQAStateIfNeeded() {}
    #endif

    private func requestPresetSave() {
        guard purchaseManager.featuresUnlocked else {
            showStatus(
                "Saved presets are included with PractiQuest Pro. Your current loop can still be used and completed.",
                kind: .information
            )
            proPresented = true
            return
        }
        newPresetName = ""
        presetNamePromptPresented = true
    }

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var values = decodedPresets
        values.insert(
            LoopPreset(
                id: UUID(),
                name: name,
                settings: settings,
                tags: selectedTags.sorted()
            ),
            at: 0
        )
        values = Array(values.prefix(30))
        if let data = try? JSONEncoder().encode(values),
           let raw = String(data: data, encoding: .utf8) {
            presetsRaw = raw
            showStatus("Preset saved.", kind: .success)
        }
    }

    private func applyPreset(_ preset: LoopPreset) {
        apply(preset.settings)
        selectedTags = Set(preset.tags)
        showStatus("Preset loaded.", kind: .success)
    }

    private func apply(_ value: SmartLoopSettings) {
        loopDuration = value.loopDurationSeconds
        restDuration = value.restDurationSeconds
        targetLoops = value.targetLoops
        untilStop = value.runsUntilStopped
        metronomeEnabled = value.metronomeEnabled
        tempoStartBPM = value.startingTempoBPM
        autoIncreaseEnabled = value.autoIncreaseEnabled
        autoIncreaseEvery = value.autoIncreaseEvery
        autoIncreaseBy = value.tempoIncreaseBPM
        tempoLadderEnabled = value.tempoLadderEnabled
        tempoLadderCleanLoops = value.cleanLoopsRequired
    }

    private func recoveryJSON(_ state: SmartLoopRunState) -> String? {
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func phaseTitle(_ phase: SmartLoopPhase) -> LocalizedStringKey {
        switch phase {
        case .work: "Focused loop"
        case .rest: "Reset"
        case .pausedWork, .pausedRest: "Paused"
        case .idle: "Ready"
        case .finished: "Finished"
        }
    }

    private func summaryText(_ state: SmartLoopRunState) -> String {
        let tagText = selectedTags.isEmpty
            ? "No focus tags"
            : selectedTags.sorted().map(\.capitalized).joined(separator: ", ")
        let progression: String
        if state.settings.tempoLadderEnabled {
            progression = "clean-loop ladder"
        } else if state.settings.autoIncreaseEnabled {
            progression = "automatic tempo progression"
        } else {
            progression = "steady tempo"
        }
        return "\(tagText) · \(progression)"
    }

    private func showStatus(
        _ message: String,
        kind: StudioQuestInlineStatus.Kind
    ) {
        statusMessage = message
        statusKind = kind
    }
}
