import SwiftUI
import Combine

struct ScaleIntonationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.studioQuestQAToolState) private var qaToolState
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @EnvironmentObject private var store: SessionStore

    @AppStorage("pb.tools.tuner.referenceHz") private var referenceHz = 440
    @AppStorage("pb.intonation.tempo") private var tempoBPM = 72

    @StateObject private var tuner = TunerEngine(managesAudioSession: false)
    @State private var exercise = IntonationExerciseType.oneOctaveScale
    @State private var mode = IntonationScaleMode.major
    @State private var key = IntonationKeyRoot.g
    @State private var octave = IntonationOctavePreset.middle
    @State private var runState: IntonationRunState?
    @State private var countInBeat = 3
    @State private var now = Date()
    @State private var statusMessage: String?
    @State private var statusKind = StudioQuestInlineStatus.Kind.information
    @State private var permissionDenied = false
    @State private var replaceAudioConfirmationPresented = false
    @State private var stageTask: Task<Void, Never>?
    @State private var startedStandalone = false
    @State private var didFinish = false
    @State private var saveFailed = false
    @State private var didApplyQAState = false

    private let refresh = Timer.publish(every: 0.08, on: .main, in: .common)
        .autoconnect()

    private var settings: IntonationSettings {
        IntonationSettings(
            exercise: exercise,
            mode: mode,
            key: key,
            octave: octave,
            tempoBPM: tempoBPM,
            referenceHz: referenceHz
        )
    }

    private var isContextual: Bool {
        coordinator.toolLaunchContext?.parentSessionID != nil
    }

    var body: some View {
        StudioQuestToolPage(
            title: "Intonation",
            subtitle: "Follow a guided pitch path and see where centering, stability, and repeated scale degrees need attention.",
            systemImage: "tuningfork"
        ) {
            if permissionDenied {
                StudioQuestPermissionState(
                    title: "Microphone access is off",
                    message: "Intonation listens for pitch only while a take is active. Enable microphone access in Settings, then try again.",
                    systemImage: "mic.slash.fill",
                    actionTitle: "Try again"
                ) {
                    permissionDenied = false
                    requestStart()
                }
            } else {
                phaseContent
            }

            if let statusMessage {
                StudioQuestInlineStatus(text: statusMessage, kind: statusKind)
                    .accessibilityIdentifier("intonation.status")
            }
        }
        .task {
            restoreIfNeeded()
            applyQAStateIfNeeded()
        }
        .onReceive(refresh) { date in
            now = date
            captureAndAdvance(at: date)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                pauseForInterruption(
                    "The take paused while PractiQuest was in the background. Resume with a fresh count-in."
                )
            }
        }
        .onChange(of: coordinator.audioSession.lastEvent) { _, event in
            handleAudioEvent(event)
        }
        .onDisappear { preserveOnExit() }
        .confirmationDialog(
            "Replace \(coordinator.audioSession.owner?.displayName ?? "the current audio tool")?",
            isPresented: $replaceAudioConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Replace and listen") {
                Task { await startTake(replacingAudio: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PractiQuest allows one microphone or audio utility at a time so pitch analysis stays reliable.")
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch runState?.phase {
        case .countIn:
            countInPanel
        case .listening, .paused:
            livePanel
        case .result:
            resultPanel
        case .insufficientSignal:
            insufficientSignalPanel
        case .failed:
            failedPanel
        case .setup, .none:
            setupPanel
        }
    }

    private var setupPanel: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            StudioQuestToolSetupPanel {
                Picker("Exercise", selection: $exercise) {
                    ForEach(IntonationExerciseType.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.menu)

                Picker("Mode", selection: $mode) {
                    ForEach(IntonationScaleMode.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Picker("Key", selection: $key) {
                        ForEach(IntonationKeyRoot.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Picker("Range", selection: $octave) {
                        ForEach(IntonationOctavePreset.allCases) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                }

                settingStepper(
                    title: "Tempo",
                    value: $tempoBPM,
                    range: 40...180,
                    step: 2,
                    formattedValue: "\(tempoBPM) BPM"
                )

                Picker("Tuning", selection: $referenceHz) {
                    Text("A=415").tag(415)
                    Text("A=440").tag(440)
                    Text("A=442").tag(442)
                }
                .pickerStyle(.segmented)

                HStack {
                    Label(
                        "\(IntonationTargetBuilder.targets(for: settings).count) notes",
                        systemImage: "music.note.list"
                    )
                    Spacer()
                    Button(tuner.isReferenceTonePlaying ? "Stop A" : "Play A") {
                        Task { await toggleReferenceTone() }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("intonation.reference")
                }
                .font(.subheadline)
            }

            Button {
                requestStart()
            } label: {
                Label(
                    coordinator.hasActivePractice
                        ? "Measure in current session"
                        : "Start intonation take",
                    systemImage: "waveform.and.mic"
                )
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())
            .accessibilityIdentifier("intonation.start")
        }
    }

    private var countInPanel: some View {
        StudioQuestToolLivePanel(eyebrow: "Count in") {
            VStack(spacing: StudioQuestTokens.Spacing.md) {
                Text("\(countInBeat)")
                    .font(StudioQuestTokens.Typography.timer)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Prepare \(runState?.targets.first?.name ?? "the first note").")
                    .font(StudioQuestTokens.Typography.sectionTitle)
                Text("The clock begins only after the microphone is listening.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Cancel") { discardTake() }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                    .accessibilityIdentifier("intonation.cancel")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var livePanel: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            if let state = runState,
               state.targets.indices.contains(state.currentNoteIndex) {
                let target = state.targets[state.currentNoteIndex]
                StudioQuestToolLivePanel(
                    eyebrow: state.phase == .paused ? "Paused" : "Listening"
                ) {
                    VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(target.isDescending ? "Descending" : "Ascending")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(target.name)
                                    .font(StudioQuestTokens.Typography.heroTitle)
                                Text("Scale degree \(target.degree)")
                                    .font(StudioQuestTokens.Typography.cardTitle)
                                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Detected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(tuner.detectedNoteName == "--" ? "—" : tuner.detectedNoteName)
                                    .font(StudioQuestTokens.Typography.statValue)
                                    .monospacedDigit()
                                Text(formattedCents(for: target) == "—"
                                     ? "Waiting"
                                     : "\(formattedCents(for: target)) cents")
                                    .font(.subheadline)
                                    .foregroundStyle(centTint(for: target))
                            }
                        }

                        IntonationPitchGuide(
                            cents: tuner.detectedFrequency == nil
                                ? nil
                                : currentCents(for: target)
                        )

                        Text(tuner.detectedNoteName == "--"
                             ? "Sustain the target note so PractiQuest can settle on the pitch."
                             : "Keep the marker near the centre.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Target \(target.name), scale degree \(target.degree)")
                    .accessibilityValue(pitchAccessibilityValue(for: target))

                    StudioQuestProgressVisualization(
                        progress: state.progress,
                        accessibilityLabel: "Intonation take progress"
                    )

                    HStack(spacing: StudioQuestTokens.Spacing.sm) {
                        StudioQuestMetric(
                            title: "Note",
                            value: "\(state.currentNoteIndex + 1) / \(state.targets.count)"
                        )
                        StudioQuestMetric(
                            title: "Offset",
                            value: formattedCents(for: target),
                            detail: "cents",
                            tint: centTint(for: target)
                        )
                        StudioQuestMetric(
                            title: "Time",
                            value: DurationFormatter.string(from: state.elapsedSeconds(at: now)),
                            tint: StudioQuestTokens.ColorRole.mint
                        )
                    }

                    HStack(spacing: StudioQuestTokens.Spacing.sm) {
                        Button {
                            togglePause()
                        } label: {
                            Label(
                                state.phase == .paused ? "Resume" : "Pause",
                                systemImage: state.phase == .paused ? "play.fill" : "pause.fill"
                            )
                        }
                        .buttonStyle(StudioQuestSecondaryButtonStyle())
                        .accessibilityIdentifier("intonation.pause")

                        Button {
                            finishTake()
                        } label: {
                            Label("Finish", systemImage: "stop.fill")
                        }
                        .buttonStyle(StudioQuestPrimaryButtonStyle())
                        .accessibilityIdentifier("intonation.finish")
                    }
                }

                if state.phase == .listening {
                    Text("Sustain the note; PractiQuest will move forward automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let state = runState, let result = state.result {
            StudioQuestToolResultPanel {
                if didFinish {
                    Label("Intonation take saved", systemImage: "checkmark.seal.fill")
                        .font(StudioQuestTokens.Typography.sectionTitle)
                        .foregroundStyle(StudioQuestTokens.ColorRole.mint)
                    resultMetrics(result)
                    Button("Done") { dismiss() }
                        .buttonStyle(StudioQuestPrimaryButtonStyle())
                        .accessibilityIdentifier("intonation.done")
                } else {
                    Label("Pitch path complete", systemImage: "tuningfork")
                        .font(StudioQuestTokens.Typography.sectionTitle)
                        .foregroundStyle(StudioQuestTokens.ColorRole.mint)

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Overall score")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(result.overallScore)")
                                .font(StudioQuestTokens.Typography.timer)
                                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                        }
                        Spacer()
                        Text(resultTitle(result))
                            .font(StudioQuestTokens.Typography.cardTitle)
                    }

                    resultMetrics(result)

                    ForEach(result.recommendations, id: \.self) { recommendation in
                        Text(recommendation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    StudioQuestEyebrow("Note detail")
                    ForEach(result.noteScores.filter { $0.sampleCount > 0 }.prefix(8)) { note in
                        HStack {
                            Text("\(note.noteName) · degree \(note.degree)")
                            Spacer()
                            Text(String(format: "%+.0f c", note.meanOffsetCents))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }

                    Button {
                        saveTake(state: state, result: result)
                    } label: {
                        Label(
                            saveFailed
                                ? "Try saving again"
                                : (isContextual ? "Add to active session" : "Save intonation take"),
                            systemImage: "checkmark"
                        )
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    .accessibilityIdentifier("intonation.save")

                    Button("Discard take", role: .destructive) { discardTake() }
                        .buttonStyle(StudioQuestSecondaryButtonStyle())
                        .accessibilityIdentifier("intonation.discard")
                }
            }
        }
    }

    private var insufficientSignalPanel: some View {
        StudioQuestPermissionState(
            title: "Not enough stable pitch",
            message: "This is different from poor intonation. Too few target notes had a stable signal to score the take fairly.",
            systemImage: "waveform.slash",
            actionTitle: "Try another take"
        ) {
            discardTake(resetToSetup: true)
        }
    }

    private var failedPanel: some View {
        StudioQuestPermissionState(
            title: "Take interrupted",
            message: "The audio route changed or listening stopped. This take was not scored.",
            systemImage: "exclamationmark.waveform",
            actionTitle: "Start a fresh take"
        ) {
            discardTake(resetToSetup: true)
        }
    }

    private func resultMetrics(_ result: IntonationTakeResult) -> some View {
        HStack(spacing: StudioQuestTokens.Spacing.sm) {
            StudioQuestMetric(
                title: "Centering",
                value: String(format: "%.0f", result.centeringScore),
                detail: "%"
            )
            StudioQuestMetric(
                title: "Stability",
                value: String(format: "%.0f", result.stabilityScore),
                detail: "%",
                tint: StudioQuestTokens.ColorRole.violet
            )
            StudioQuestMetric(
                title: "Consistency",
                value: String(format: "%.0f", result.consistencyScore),
                detail: "%",
                tint: StudioQuestTokens.ColorRole.mint
            )
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
                Text(formattedValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    private func requestStart() {
        if let active = coordinator.activeToolID, active != .intonation {
            showStatus(
                "Finish \(active.title) before starting Intonation.",
                kind: .warning
            )
            return
        }
        if let owner = coordinator.audioSession.owner, owner != .intonation {
            replaceAudioConfirmationPresented = true
            return
        }
        Task { await startTake(replacingAudio: false) }
    }

    private func startTake(replacingAudio: Bool) async {
        if replacingAudio, !stopReplaceableAudioOwner() { return }
        tuner.stopReferenceTone()
        guard await claimAudio() else { return }

        if coordinator.activeToolID != .intonation {
            if coordinator.hasActivePractice {
                guard coordinator.attachTool(.intonation) != nil else {
                    coordinator.audioSession.release(.intonation)
                    return
                }
                startedStandalone = false
            } else {
                let estimatedSeconds = Int(
                    ceil(Double(IntonationTargetBuilder.targets(for: settings).count + 3)
                         * settings.noteDuration)
                )
                guard coordinator.beginFocusedTool(
                    .intonation,
                    title: "Intonation",
                    durationMinutes: max(1, Int(ceil(Double(estimatedSeconds) / 60))),
                    source: .library
                ) else {
                    coordinator.audioSession.release(.intonation)
                    return
                }
                startedStandalone = true
            }
        }

        tuner.startListening()
        guard tuner.isListening else {
            cleanupAfterFailedStart()
            showStatus("Microphone input could not start.", kind: .error)
            return
        }

        var state = IntonationRunState(settings: settings)
        state.beginCountIn()
        runState = state
        permissionDenied = false
        didFinish = false
        saveFailed = false
        statusMessage = nil
        persistRecovery()
        scheduleCountIn()
    }

    private func scheduleCountIn() {
        stageTask?.cancel()
        stageTask = Task { @MainActor in
            for beat in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                countInBeat = beat
                PBHaptics.tap()
                try? await Task.sleep(for: .seconds(settings.noteDuration))
            }
            guard !Task.isCancelled, tuner.isListening, var state = runState else { return }
            state.beginListening()
            runState = state
            if !isContextual { coordinator.resume() }
            coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            showStatus("Listening for \(state.targets.first?.name ?? "the first note").", kind: .information)
        }
    }

    private func captureAndAdvance(at date: Date) {
        guard var state = runState,
              state.phase == .listening,
              state.targets.indices.contains(state.currentNoteIndex) else { return }
        if let frequency = tuner.detectedFrequency {
            state.register(
                frequency: frequency,
                inputLevel: tuner.inputLevel,
                at: date
            )
        }
        if let started = state.phaseStartedAt,
           date.timeIntervalSince(started) >= state.settings.noteDuration {
            state.advanceNote(at: date)
            if state.phase == .result || state.phase == .insufficientSignal {
                stopCaptureForReview(state)
                PBHaptics.success()
            }
        }
        runState = state
        persistRecovery()
    }

    private func togglePause() {
        guard var state = runState else { return }
        if state.phase == .listening {
            state.pause()
            runState = state
            stopListening()
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            if !isContextual { coordinator.pause() }
            showStatus("Take paused. Resume with a fresh count-in.", kind: .information)
        } else if state.phase == .paused {
            Task { await resumeTake() }
        }
    }

    private func resumeTake() async {
        guard var state = runState, state.phase == .paused else { return }
        #if DEBUG
        if qaToolState != nil {
            state.beginListening()
            runState = state
            if !isContextual { coordinator.resume() }
            coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            return
        }
        #endif
        guard await claimAudio() else { return }
        tuner.startListening()
        guard tuner.isListening else {
            showStatus("Microphone input could not resume.", kind: .error)
            coordinator.audioSession.release(.intonation)
            return
        }
        state.beginCountIn()
        runState = state
        scheduleCountIn()
    }

    private func finishTake() {
        guard var state = runState else { return }
        state.finish(at: now)
        runState = state
        stopCaptureForReview(state)
        if state.phase == .insufficientSignal {
            showStatus("Too few notes had a stable pitch signal to score.", kind: .warning)
        }
    }

    private func stopCaptureForReview(_ state: IntonationRunState) {
        stopListening()
        coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        if !isContextual { coordinator.pause() }
    }

    private func pauseForInterruption(_ message: String) {
        guard var state = runState,
              [.countIn, .listening].contains(state.phase) else { return }
        if state.phase == .listening {
            state.pause()
        } else {
            state.phase = .paused
        }
        runState = state
        stopListening()
        coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        if !isContextual { coordinator.pause() }
        showStatus(message, kind: .warning)
    }

    private func invalidateTake(_ message: String) {
        guard var state = runState,
              [.countIn, .listening, .paused].contains(state.phase) else { return }
        state.fail(message)
        runState = state
        stopListening()
        coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        if !isContextual { coordinator.pause() }
        showStatus(message, kind: .error)
    }

    private func saveTake(
        state: IntonationRunState,
        result: IntonationTakeResult
    ) {
        let payload = IntonationResultPayload(
            completedAt: .now,
            durationSeconds: state.elapsedSeconds(at: now),
            settings: state.settings,
            result: result,
            parentSessionID: isContextual ? coordinator.activeSessionID : nil,
            launchSource: isContextual
                ? .activeSession
                : (coordinator.toolLaunchContext?.source ?? .legacy),
            toolVersion: 2
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            showStatus("The intonation result could not be prepared.", kind: .error)
            return
        }
        let toolResult = PracticeToolResult(
            toolID: .intonation,
            sessionID: coordinator.activeSessionID,
            durationSeconds: payload.durationSeconds,
            metrics: [
                "overallScore": Double(result.overallScore),
                "centeringScore": result.centeringScore,
                "stabilityScore": result.stabilityScore,
                "consistencyScore": result.consistencyScore
            ],
            payloadJSON: json
        )
        coordinator.queueQuestCompletion("intonation")

        if isContextual {
            coordinator.attachCompletedToolResult(toolResult)
            coordinator.detachTool()
            didFinish = true
            dismiss()
            return
        }

        coordinator.completeTool(toolResult)
        let didSave = store.savePracticeCompletion(
            PracticeSavePayload(
                sessionID: coordinator.activeSessionID,
                snapshot: coordinator.snapshot,
                notes: "Intonation score: \(result.overallScore)",
                noteTitle: "Intonation",
                noteFocus: resultTitle(result),
                toolResult: toolResult,
                attachedToolResults: coordinator.attachedToolResults
            )
        )
        if didSave {
            coordinator.completeAfterSave(savedSessionID: store.lastSavedSessionID)
            didFinish = true
            saveFailed = false
            showStatus("Intonation take saved in History.", kind: .success)
        } else {
            saveFailed = true
            showStatus(
                "The take could not be saved. Your result is still here—try again.",
                kind: .error
            )
        }
    }

    private func discardTake(resetToSetup: Bool = false) {
        stopListening()
        if startedStandalone {
            coordinator.discard()
        } else if coordinator.activeToolID == .intonation {
            coordinator.detachTool()
        }
        runState = nil
        statusMessage = nil
        permissionDenied = false
        didFinish = false
        saveFailed = false
        startedStandalone = false
        if !resetToSetup { dismiss() }
    }

    private func preserveOnExit() {
        stageTask?.cancel()
        guard !didFinish, var state = runState else {
            stopListening()
            return
        }
        if isContextual {
            stopListening()
            coordinator.detachTool()
            return
        }
        if [.countIn, .listening].contains(state.phase) {
            if state.phase == .listening { state.pause() }
            else { state.phase = .paused }
            runState = state
            stopListening()
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            coordinator.pause()
        }
    }

    private func restoreIfNeeded() {
        guard coordinator.activeToolID == .intonation,
              let json = coordinator.toolActivityState?.recoveryPayloadJSON,
              let data = json.data(using: .utf8),
              var restored = try? JSONDecoder().decode(IntonationRunState.self, from: data)
        else { return }
        if [.countIn, .listening].contains(restored.phase) {
            if restored.phase == .listening { restored.pause() }
            else { restored.phase = .paused }
        }
        apply(restored.settings)
        runState = restored
        startedStandalone = coordinator.toolLaunchContext?.parentSessionID == nil
        showStatus(
            restored.phase == .result
                ? "Recovered intonation result ready to save."
                : "Recovered intonation take ready for a fresh count-in.",
            kind: .information
        )
    }

    private func claimAudio() async -> Bool {
        do {
            try await coordinator.audioSession.claim(
                .intonation,
                requirements: .microphone
            )
            return true
        } catch PracticeAudioSessionError.microphoneDenied {
            permissionDenied = true
            showStatus("Microphone access is required before a take can begin.", kind: .error)
            return false
        } catch {
            showStatus(
                (error as? LocalizedError)?.errorDescription ?? "Audio could not be started.",
                kind: .error
            )
            return false
        }
    }

    private func toggleReferenceTone() async {
        if tuner.isReferenceTonePlaying {
            tuner.stopReferenceTone()
            coordinator.audioSession.release(.intonation)
            return
        }
        do {
            try await coordinator.audioSession.claim(
                .intonation,
                requirements: .playback
            )
            tuner.startReferenceTone(frequency: Double(referenceHz))
        } catch {
            showStatus(
                (error as? LocalizedError)?.errorDescription ?? "Reference tone could not start.",
                kind: .error
            )
        }
    }

    private func stopReplaceableAudioOwner() -> Bool {
        switch coordinator.audioSession.owner {
        case .metronome:
            coordinator.metronome.stop()
        case .tuner:
            coordinator.tuner.stopListening()
            coordinator.tuner.stopReferenceTone()
        case .smartLoop:
            coordinator.metronome.stop()
        case .none, .intonation:
            return true
        default:
            showStatus("That audio activity cannot be replaced safely. Close it first.", kind: .warning)
            return false
        }
        coordinator.audioSession.releaseCurrentOwner()
        return true
    }

    private func stopListening() {
        stageTask?.cancel()
        tuner.stopListening()
        tuner.stopReferenceTone()
        coordinator.audioSession.release(.intonation)
    }

    private func cleanupAfterFailedStart() {
        stopListening()
        if startedStandalone { coordinator.discard() }
        else if coordinator.activeToolID == .intonation { coordinator.detachTool() }
    }

    private func persistRecovery() {
        guard let runState else { return }
        coordinator.updateToolRecoveryPayload(recoveryJSON(runState))
    }

    private func recoveryJSON(_ state: IntonationRunState) -> String? {
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func apply(_ settings: IntonationSettings) {
        exercise = settings.exercise
        mode = settings.mode
        key = settings.key
        octave = settings.octave
        tempoBPM = settings.tempoBPM
        referenceHz = settings.referenceHz
    }

    private func currentCents(for target: IntonationTargetNote) -> Double {
        guard let frequency = tuner.detectedFrequency, frequency > 0 else { return 0 }
        return max(-50, min(50, 1_200 * log2(frequency / target.frequency)))
    }

    private func formattedCents(for target: IntonationTargetNote) -> String {
        tuner.detectedFrequency == nil
            ? "—"
            : String(format: "%+.0f", currentCents(for: target))
    }

    private func centTint(for target: IntonationTargetNote) -> Color {
        let cents = abs(currentCents(for: target))
        if tuner.detectedFrequency == nil { return StudioQuestTokens.ColorRole.cobalt }
        if cents <= 10 { return StudioQuestTokens.ColorRole.mint }
        if cents <= 25 { return StudioQuestTokens.ColorRole.gold }
        return StudioQuestTokens.ColorRole.coral
    }

    private func pitchAccessibilityValue(for target: IntonationTargetNote) -> String {
        guard tuner.detectedFrequency != nil else { return "Waiting for a stable pitch" }
        let cents = currentCents(for: target)
        let direction = abs(cents) <= 10 ? "centered" : (cents < 0 ? "flat" : "sharp")
        return "\(String(format: "%.0f", abs(cents))) cents \(direction)"
    }

    private func resultTitle(_ result: IntonationTakeResult) -> String {
        if result.centeringScore >= 80 && result.stabilityScore >= 80 {
            return "Centered and stable"
        }
        if result.centeringScore < result.stabilityScore {
            return "Center the pitch"
        }
        return "Stabilize the sound"
    }

    private func handleAudioEvent(_ event: PracticeAudioEvent?) {
        guard let event else { return }
        switch event {
        case .interrupted(.intonation):
            invalidateTake("Audio was interrupted, so this take was not scored.")
        case .routeChanged:
            if let phase = runState?.phase,
               [.countIn, .listening].contains(phase) {
                invalidateTake("The audio route changed, so this take was not scored.")
            }
        default:
            break
        }
    }

    private func showStatus(
        _ message: String,
        kind: StudioQuestInlineStatus.Kind
    ) {
        statusMessage = message
        statusKind = kind
    }

    #if DEBUG
    private func applyQAStateIfNeeded() {
        guard !didApplyQAState, let qaToolState else { return }
        didApplyQAState = true
        guard qaToolState != .setup else { return }
        if qaToolState == .permissionDenied {
            permissionDenied = true
            return
        }
        if coordinator.activeToolID == nil {
            _ = coordinator.beginFocusedTool(
                .intonation,
                title: "Intonation",
                durationMinutes: 2,
                source: .qa
            )
            startedStandalone = true
        }
        var fixture = IntonationRunState(settings: settings)
        fixture.beginListening(at: .now.addingTimeInterval(-16))
        for index in fixture.targets.indices {
            let target = fixture.targets[index]
            fixture.currentNoteIndex = index
            fixture.phaseStartedAt = .now.addingTimeInterval(-0.6)
            let cents = Double((index % 5) * 4 - 8)
            let frequency = target.frequency * pow(2, cents / 1_200)
            for sample in 0..<5 {
                fixture.register(
                    frequency: frequency,
                    inputLevel: 0.02,
                    at: .now.addingTimeInterval(Double(sample) * 0.05)
                )
            }
        }
        fixture.currentNoteIndex = min(4, fixture.targets.count - 1)
        fixture.phaseStartedAt = .now.addingTimeInterval(-2)

        switch qaToolState {
        case .running:
            break
        case .paused, .recovered:
            fixture.pause()
        case .completed, .saveError:
            fixture.finish()
        case .permissionDenied, .setup:
            break
        }
        runState = fixture
        if fixture.phase == .listening {
            coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(fixture))
        } else {
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(fixture))
            coordinator.pause()
        }
        if qaToolState == .saveError {
            saveFailed = true
            showStatus(
                "The take could not be saved. Your result is still here—try again.",
                kind: .error
            )
        } else if qaToolState == .recovered {
            showStatus("Recovered intonation take ready for a fresh count-in.", kind: .information)
        }
    }
    #else
    private func applyQAStateIfNeeded() {}
    #endif
}

private struct IntonationPitchGuide: View {
    let cents: Double?

    private var normalizedOffset: Double {
        guard let cents else { return 0.5 }
        return (min(max(cents, -50), 50) + 50) / 100
    }

    private var markerColor: Color {
        guard let cents else { return .secondary }
        return switch abs(cents) {
        case ...10:
            StudioQuestTokens.ColorRole.mint
        case ...25:
            StudioQuestTokens.ColorRole.gold
        default:
            StudioQuestTokens.ColorRole.coral
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(StudioQuestTokens.ColorRole.cobalt.opacity(0.10))
                    Capsule()
                        .fill(StudioQuestTokens.ColorRole.mint.opacity(0.24))
                        .frame(width: proxy.size.width * 0.2)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    Rectangle()
                        .fill(StudioQuestTokens.ColorRole.mint)
                        .frame(width: 2, height: 22)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    Circle()
                        .fill(markerColor)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(.background, lineWidth: 3))
                        .position(
                            x: 9 + (proxy.size.width - 18) * normalizedOffset,
                            y: proxy.size.height / 2
                        )
                        .opacity(cents == nil ? 0.45 : 1)
                }
            }
            .frame(height: 24)

            HStack {
                Text("Flat")
                Spacer()
                Text("In tune")
                Spacer()
                Text("Sharp")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}
