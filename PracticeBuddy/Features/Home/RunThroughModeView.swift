import SwiftUI
import AVFoundation
import Combine

struct RunThroughModeView: View {
    let nestedWithinPlan: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.studioQuestQAToolState) private var qaToolState
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @EnvironmentObject private var store: SessionStore

    @AppStorage("pb.runthrough.noPauseMode") private var noPauseMode = false
    @AppStorage("pb.runthrough.useMetronome") private var useMetronome = false
    @AppStorage("pb.runthrough.metronomeBPM") private var metronomeBPM = 72

    @StateObject private var recorder = RunThroughRecorder()
    @State private var runState: RunThroughRunState?
    @State private var now = Date()
    @State private var pieceName = ""
    @State private var notes = ""
    @State private var selfRating = 3
    @State private var selectedMarker = "shift"
    @State private var statusMessage: String?
    @State private var statusKind = StudioQuestInlineStatus.Kind.information
    @State private var replaceAudioConfirmationPresented = false
    @State private var permissionDenied = false
    @State private var countInTask: Task<Void, Never>?
    @State private var didFinish = false
    @State private var saveFailed = false
    @State private var startedStandalone = false
    @State private var didApplyQAState = false

    private let markerOptions = [
        "shift", "rhythm", "intonation", "bow", "memory", "other"
    ]
    private let refresh = Timer.publish(every: 0.25, on: .main, in: .common)
        .autoconnect()

    init(nestedWithinPlan: Bool = false) {
        self.nestedWithinPlan = nestedWithinPlan
    }

    private var settings: RunThroughSettings {
        RunThroughSettings(
            noPauseMode: noPauseMode,
            useMetronome: useMetronome,
            metronomeBPM: metronomeBPM
        )
    }

    private var isContextual: Bool {
        nestedWithinPlan || coordinator.toolLaunchContext?.parentSessionID != nil
    }

    var body: some View {
        StudioQuestToolPage(
            title: "Run-through",
            subtitle: "Capture a complete performance, mark moments without stopping, and review the whole arc.",
            systemImage: "record.circle"
        ) {
            if permissionDenied {
                StudioQuestPermissionState(
                    title: "Microphone access is off",
                    message: "Run-through needs the microphone to create a recording. You can enable access in Settings and try again.",
                    systemImage: "mic.slash.fill",
                    actionTitle: "Try again"
                ) {
                    permissionDenied = false
                    requestStart()
                }
            } else {
                switch runState?.phase {
                case .countIn:
                    countInPanel
                case .recording, .paused:
                    livePanel
                case .review:
                    reviewPanel
                case .failed:
                    StudioQuestPermissionState(
                        title: "Recording could not start",
                        message: "Check your microphone and audio route, then try again.",
                        systemImage: "exclamationmark.waveform",
                        actionTitle: "Try again",
                        action: requestStart
                    )
                case .idle, .none:
                    setupPanel
                }
            }

            if let statusMessage, runState?.phase != .failed {
                StudioQuestInlineStatus(text: statusMessage, kind: statusKind)
                    .accessibilityIdentifier("runthrough.status")
            }
        }
        .task {
            restoreIfNeeded()
            applyQAStateIfNeeded()
        }
        .onReceive(refresh) { date in
            now = date
        }
        .onChange(of: scenePhase) { _, next in
            if next != .active {
                preserveActiveRecording()
            }
        }
        .onChange(of: coordinator.audioSession.lastEvent) { _, event in
            handleAudioEvent(event)
        }
        .onDisappear {
            countInTask?.cancel()
            coordinator.metronome.stop()
            if nestedWithinPlan, !didFinish {
                cancelAndDiscard()
            } else {
                preserveActiveRecording()
            }
        }
        .confirmationDialog(
            "Replace \(coordinator.audioSession.owner?.displayName ?? "the current audio tool")?",
            isPresented: $replaceAudioConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Replace and record") {
                Task { await startRun(replacingAudio: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current audio tool will stop before Run-through claims the microphone.")
        }
    }

    private var setupPanel: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            StudioQuestToolSetupPanel {
                Toggle("No-pause performance", isOn: $noPauseMode)
                Toggle("Metronome click", isOn: $useMetronome)
                if useMetronome {
                    HStack {
                        Text("Tempo")
                            .font(.subheadline)
                        Spacer()
                        Text("\(metronomeBPM) BPM")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        Stepper(
                            "",
                            value: $metronomeBPM,
                            in: 40...220
                        )
                        .labelsHidden()
                        .accessibilityLabel("Metronome tempo")
                        .accessibilityValue("\(metronomeBPM) beats per minute")
                    }
                    .frame(minHeight: 44)
                }
            }

            Button {
                requestStart()
            } label: {
                Label(
                    coordinator.hasActivePractice
                        ? "Record in current session"
                        : "Start run-through",
                    systemImage: "record.circle"
                )
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())
            .accessibilityIdentifier("runthrough.start")
        }
    }

    private var countInPanel: some View {
        StudioQuestToolLivePanel(eyebrow: "Get ready") {
            VStack(spacing: StudioQuestTokens.Spacing.md) {
                Text("\(runState?.countInBeat(at: now) ?? 1)")
                    .font(StudioQuestTokens.Typography.timer)
                    .monospacedDigit()
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Count in")
                    .accessibilityValue("\(runState?.countInBeat(at: now) ?? 1)")
                Text("Recording begins after the count-in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Cancel") {
                    cancelAndDiscard()
                }
                .buttonStyle(StudioQuestSecondaryButtonStyle())
                .accessibilityIdentifier("runthrough.cancel")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var livePanel: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            if let state = runState {
                StudioQuestToolLivePanel(
                    eyebrow: state.phase == .paused ? "Paused" : "Recording"
                ) {
                    HStack(alignment: .firstTextBaseline) {
                        Label(
                            state.phase == .paused ? "Performance paused" : "Performance in progress",
                            systemImage: state.phase == .paused ? "pause.circle.fill" : "record.circle.fill"
                        )
                        .font(StudioQuestTokens.Typography.sectionTitle)
                        .foregroundStyle(
                            state.phase == .paused
                                ? StudioQuestTokens.ColorRole.gold
                                : StudioQuestTokens.ColorRole.coral
                        )
                        Spacer()
                        Text(DurationFormatter.string(from: state.elapsedSeconds(at: now)))
                            .font(StudioQuestTokens.Typography.timer)
                            .monospacedDigit()
                    }

                    Text("Input ready · \(state.settings.useMetronome ? "\(state.settings.metronomeBPM) BPM click" : "silent count")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            state.settings.useMetronome
                                ? "Microphone ready. Metronome \(state.settings.metronomeBPM) beats per minute."
                                : "Microphone ready. Metronome off."
                        )

                    StudioQuestFlowLayout {
                        ForEach(markerOptions, id: \.self) { marker in
                            StudioQuestChoiceChip(
                                title: LocalizedStringKey(marker.capitalized),
                                isSelected: selectedMarker == marker
                            ) {
                                selectedMarker = marker
                            }
                        }
                    }

                    Button {
                        addMarker()
                    } label: {
                        Label("Mark \(selectedMarker)", systemImage: "flag.fill")
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                    .accessibilityIdentifier("runthrough.marker")

                    HStack(spacing: StudioQuestTokens.Spacing.sm) {
                        if !state.settings.noPauseMode {
                            Button {
                                togglePause()
                            } label: {
                                Label(
                                    state.phase == .paused ? "Resume" : "Pause",
                                    systemImage: state.phase == .paused ? "play.fill" : "pause.fill"
                                )
                            }
                            .buttonStyle(StudioQuestSecondaryButtonStyle())
                            .accessibilityIdentifier("runthrough.pause")
                        }

                        Button {
                            finishRecording()
                        } label: {
                            Label("Finish", systemImage: "stop.fill")
                        }
                        .buttonStyle(StudioQuestPrimaryButtonStyle())
                        .accessibilityIdentifier("runthrough.finish")
                    }
                }

                if !state.markers.isEmpty {
                    StudioQuestToolSetupPanel(title: "Markers") {
                        ForEach(state.markers.suffix(5)) { marker in
                            HStack {
                                Text(DurationFormatter.string(from: marker.second))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                                Text(marker.label.capitalized)
                                    .font(.subheadline)
                                Spacer()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private var reviewPanel: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            if let state = runState {
                if didFinish {
                    savedPanel(state)
                } else {
                    editableReviewPanel(state)
                }
            }
        }
    }

    @ViewBuilder
    private func editableReviewPanel(_ state: RunThroughRunState) -> some View {
        StudioQuestToolResultPanel {
            Label("Performance captured", systemImage: "waveform.badge.checkmark")
                .font(StudioQuestTokens.Typography.sectionTitle)
                .foregroundStyle(StudioQuestTokens.ColorRole.mint)

            HStack(spacing: StudioQuestTokens.Spacing.md) {
                StudioQuestMetric(
                    title: "Duration",
                    value: DurationFormatter.string(from: state.elapsedSeconds(at: now))
                )
                StudioQuestMetric(
                    title: "Markers",
                    value: "\(state.markers.count)",
                    tint: StudioQuestTokens.ColorRole.violet
                )
            }

            TextField("Piece or passage", text: $pieceName)
                .textFieldStyle(.plain)
                .padding(StudioQuestTokens.Spacing.sm)
                .studioQuestSurface(.flat)

            TextField("Private notes", text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.plain)
                .padding(StudioQuestTokens.Spacing.sm)
                .studioQuestSurface(.flat)

            StudioQuestEyebrow("Self rating")
            HStack(spacing: StudioQuestTokens.Spacing.xs) {
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        selfRating = rating
                    } label: {
                        Text("\(rating)")
                            .font(.headline.monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selfRating == rating ? .white : .primary)
                            .background(
                                selfRating == rating
                                    ? StudioQuestTokens.ColorRole.cobalt
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(rating) out of 5")
                    .accessibilityAddTraits(selfRating == rating ? .isSelected : [])
                }
            }
        }

        Button {
            saveRunThrough()
        } label: {
            Label(
                saveFailed ? "Try saving again" : (isContextual ? "Add to active session" : "Save run-through"),
                systemImage: "checkmark"
            )
        }
        .buttonStyle(StudioQuestPrimaryButtonStyle())
        .accessibilityIdentifier("runthrough.save")

        Button("Discard recording", role: .destructive) {
            cancelAndDiscard()
        }
        .buttonStyle(StudioQuestSecondaryButtonStyle())
        .accessibilityIdentifier("runthrough.discard")
    }

    @ViewBuilder
    private func savedPanel(_ state: RunThroughRunState) -> some View {
        StudioQuestToolResultPanel {
            Label("Run-through saved", systemImage: "checkmark.seal.fill")
                .font(StudioQuestTokens.Typography.sectionTitle)
                .foregroundStyle(StudioQuestTokens.ColorRole.mint)

            Text("The recording and its markers are available in History.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: StudioQuestTokens.Spacing.md) {
                StudioQuestMetric(
                    title: "Duration",
                    value: DurationFormatter.string(from: state.elapsedSeconds(at: now))
                )
                StudioQuestMetric(
                    title: "Markers",
                    value: "\(state.markers.count)",
                    tint: StudioQuestTokens.ColorRole.violet
                )
            }
        }

        Button("Done") {
            dismiss()
        }
        .buttonStyle(StudioQuestPrimaryButtonStyle())
        .accessibilityIdentifier("runthrough.done")
    }

    /*
     The editable review and saved confirmation intentionally live in separate
     render paths. A committed standalone recording must never expose the Save
     action again, which prevents duplicate History entries after the shared
     coordinator has reset its canonical session identity.
     */

    private func requestStart() {
        if let active = coordinator.activeToolID,
           active != .runThrough,
           !(nestedWithinPlan && active == .planExecuteReflect) {
            showStatus(
                "Finish or close \(active.title) before starting Run-through.",
                kind: .warning
            )
            return
        }
        if let owner = coordinator.audioSession.owner, owner != .runThrough {
            replaceAudioConfirmationPresented = true
            return
        }
        Task { await startRun(replacingAudio: false) }
    }

    private func startRun(replacingAudio: Bool) async {
        if replacingAudio {
            stopCurrentAudioOwner()
        }

        do {
            var requirements: PracticeAudioRequirement = [.microphone, .recording]
            if useMetronome {
                requirements.insert(.playback)
            }
            try await coordinator.audioSession.claim(
                .runThrough,
                requirements: requirements
            )
        } catch PracticeAudioSessionError.microphoneDenied {
            permissionDenied = true
            showStatus(
                "Microphone access is required before recording can begin.",
                kind: .error
            )
            return
        } catch {
            showStatus(
                "Audio could not be started. Check your route and try again.",
                kind: .error
            )
            return
        }

        if nestedWithinPlan {
            guard coordinator.beginNestedTool(.runThrough) != nil else {
                coordinator.audioSession.release(.runThrough)
                showStatus(
                    coordinator.toolErrorMessage ?? "Run-through could not attach to this plan.",
                    kind: .warning
                )
                return
            }
            startedStandalone = false
        } else if coordinator.activeToolID != .runThrough {
            if coordinator.hasActivePractice {
                guard coordinator.attachTool(.runThrough) != nil else {
                    coordinator.audioSession.release(.runThrough)
                    return
                }
                startedStandalone = false
            } else {
                guard coordinator.beginFocusedTool(
                    .runThrough,
                    title: "Run-through",
                    durationMinutes: 10,
                    source: .library
                ) else {
                    coordinator.audioSession.release(.runThrough)
                    return
                }
                startedStandalone = true
            }
        }

        pieceName = ""
        notes = ""
        selfRating = 3
        selectedMarker = "shift"
        didFinish = false
        saveFailed = false
        permissionDenied = false

        var state = RunThroughRunState(settings: settings)
        state.beginCountIn()
        runState = state
        persistRecovery()

        if useMetronome {
            coordinator.metronome.setBPM(settings.metronomeBPM)
            coordinator.metronome.start(
                beatsPerBar: 4,
                subdivision: .none,
                soundStyle: .click
            )
        }

        countInTask?.cancel()
        countInTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            beginRecorderAfterCountIn()
        }
    }

    private func beginRecorderAfterCountIn() {
        guard var state = runState, state.phase == .countIn else { return }
        do {
            let outputURL = try recorder.startRecording()
            state.beginRecording(filePath: outputURL.path)
            runState = state
            if !nestedWithinPlan {
                coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            }
            showStatus("Recording started.", kind: .information)
        } catch {
            coordinator.metronome.stop()
            coordinator.audioSession.release(.runThrough)
            state.phase = .failed
            runState = state
            cleanupRuntimeAfterFailure()
            showStatus(
                "Recording could not start. No audio file was kept.",
                kind: .error
            )
        }
    }

    private func togglePause() {
        guard var state = runState, !state.settings.noPauseMode else { return }
        if state.phase == .recording {
            recorder.pause()
            state.pause()
            runState = state
            coordinator.metronome.stop()
            if !nestedWithinPlan {
                coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            }
            if startedStandalone {
                coordinator.pause()
            }
        } else if state.phase == .paused {
            guard recorder.resume() else {
                showStatus("Recording could not resume. Finish and review the captured audio.", kind: .error)
                finishRecording()
                return
            }
            state.resume()
            runState = state
            if state.settings.useMetronome {
                coordinator.metronome.start(
                    beatsPerBar: 4,
                    subdivision: .none,
                    soundStyle: .click
                )
            }
            if !nestedWithinPlan {
                coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            }
            if startedStandalone {
                coordinator.resume()
            }
        }
    }

    private func addMarker() {
        guard var state = runState else { return }
        state.addMarker(selectedMarker, at: now)
        runState = state
        persistRecovery()
    }

    private func finishRecording() {
        countInTask?.cancel()
        guard var state = runState else { return }
        if state.phase == .countIn {
            cancelAndDiscard()
            return
        }
        recorder.stopRecording()
        coordinator.metronome.stop()
        coordinator.audioSession.release(.runThrough)
        state.finish(at: now)
        runState = state
        if !nestedWithinPlan {
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        }
        if startedStandalone {
            coordinator.pause()
        }
        showStatus("Performance captured. Add a private note or save it now.", kind: .success)
    }

    private func saveRunThrough() {
        guard let state = runState,
              state.phase == .review,
              state.hasMeaningfulRecording(at: now),
              let audioPath = state.audioFilePath,
              FileManager.default.fileExists(atPath: audioPath) else {
            showStatus(
                "No usable recording was found. Record at least three seconds and try again.",
                kind: .error
            )
            return
        }

        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPiece = pieceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = RunThroughResultPayload(
            completedAt: .now,
            durationSeconds: state.elapsedSeconds(at: now),
            audioFilePath: audioPath,
            notes: cleanNotes,
            selfRating: selfRating,
            settings: state.settings,
            markers: state.markers,
            pieceName: cleanPiece,
            parentSessionID: isContextual ? coordinator.activeSessionID : nil,
            launchSource: isContextual
                ? .activeSession
                : (coordinator.toolLaunchContext?.source ?? .legacy),
            toolVersion: 2
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            showStatus("The run-through result could not be prepared.", kind: .error)
            return
        }

        let result = PracticeToolResult(
            toolID: .runThrough,
            sessionID: coordinator.activeSessionID,
            durationSeconds: payload.durationSeconds,
            metrics: [
                "markers": Double(payload.markers.count),
                "rating": Double(payload.selfRating),
                "tempo": Double(payload.settings.useMetronome ? payload.settings.metronomeBPM : 0)
            ],
            payloadJSON: json
        )
        coordinator.queueQuestCompletion("expression-mastery")

        if isContextual {
            coordinator.attachCompletedToolResult(result)
            finishContextualTool()
            didFinish = true
            saveFailed = false
            showStatus("Run-through added to your active session.", kind: .success)
            dismiss()
            return
        }

        coordinator.completeTool(result)
        let didSave = store.savePracticeCompletion(
            PracticeSavePayload(
                sessionID: coordinator.activeSessionID,
                snapshot: coordinator.snapshot,
                notes: cleanNotes,
                noteTitle: cleanPiece.isEmpty ? "Run-through" : cleanPiece,
                noteFocus: "Complete performance",
                toolResult: result,
                attachedToolResults: coordinator.attachedToolResults
            )
        )
        if didSave {
            coordinator.completeAfterSave(savedSessionID: store.lastSavedSessionID)
            didFinish = true
            saveFailed = false
            showStatus("Run-through saved in History.", kind: .success)
        } else {
            saveFailed = true
            showStatus(
                "The run-through could not be saved. Your recording is still here—try again.",
                kind: .error
            )
        }
    }

    private func cancelAndDiscard() {
        countInTask?.cancel()
        recorder.discardRecording()
        if let path = runState?.audioFilePath {
            RunThroughFileLifecycle.removeIfPresent(at: URL(fileURLWithPath: path))
        }
        coordinator.metronome.stop()
        coordinator.audioSession.release(.runThrough)
        cleanupRuntimeAfterFailure()
        runState = nil
        statusMessage = nil
        permissionDenied = false
        didFinish = false
        saveFailed = false
    }

    private func cleanupRuntimeAfterFailure() {
        if nestedWithinPlan {
            coordinator.endNestedTool(.runThrough)
        } else if startedStandalone {
            coordinator.discard()
        } else if coordinator.activeToolID == .runThrough {
            coordinator.detachTool()
        }
    }

    private func finishContextualTool() {
        if nestedWithinPlan {
            coordinator.endNestedTool(.runThrough)
        } else {
            coordinator.detachTool()
        }
    }

    private func preserveActiveRecording() {
        guard !didFinish, var state = runState else { return }
        if state.phase == .countIn {
            cancelAndDiscard()
            return
        }
        if state.phase == .recording {
            recorder.pause()
            state.pause(at: .now)
            runState = state
            coordinator.metronome.stop()
            if !nestedWithinPlan {
                coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            }
            if startedStandalone {
                coordinator.pause()
            }
        }
        persistRecovery()
    }

    private func restoreIfNeeded() {
        guard !nestedWithinPlan,
              coordinator.activeToolID == .runThrough,
              let json = coordinator.toolActivityState?.recoveryPayloadJSON,
              let data = json.data(using: .utf8),
              var restored = try? JSONDecoder().decode(
                RunThroughRunState.self,
                from: data
              ) else { return }

        guard let path = restored.audioFilePath,
              FileManager.default.fileExists(atPath: path) else {
            coordinator.detachTool()
            return
        }

        // An AVAudioRecorder cannot safely resume across process death. Keep
        // the partial file and move to review instead of pretending it is live.
        restored.finish()
        runState = restored
        startedStandalone = coordinator.toolLaunchContext?.parentSessionID == nil
        showStatus(
            "A recovered partial recording is ready to review or discard.",
            kind: .information
        )
    }

    private func persistRecovery() {
        guard !nestedWithinPlan, let state = runState else { return }
        coordinator.updateToolRecoveryPayload(recoveryJSON(state))
    }

    private func recoveryJSON(_ state: RunThroughRunState) -> String? {
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func handleAudioEvent(_ event: PracticeAudioEvent?) {
        guard let event else { return }
        switch event {
        case .interrupted(.runThrough):
            preserveActiveRecording()
            showStatus("Recording paused because audio was interrupted.", kind: .warning)
        case .routeChanged:
            if runState?.phase == .recording {
                preserveActiveRecording()
                showStatus("Audio route changed. Review the take or resume when ready.", kind: .warning)
            }
        default:
            break
        }
    }

    private func stopCurrentAudioOwner() {
        switch coordinator.audioSession.owner {
        case .metronome:
            coordinator.metronome.stop()
        case .tuner:
            coordinator.tuner.stopListening()
            coordinator.tuner.stopReferenceTone()
        case .smartLoop:
            coordinator.metronome.stop()
        default:
            break
        }
        coordinator.audioSession.releaseCurrentOwner()
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
                .runThrough,
                title: "Run-through",
                durationMinutes: 2,
                source: .qa
            )
            startedStandalone = true
        }
        var fixture = RunThroughRunState(settings: settings)
        fixture.beginCountIn(at: .now.addingTimeInterval(-4))
        fixture.beginRecording(
            filePath: qaRecordingFixtureURL().path,
            at: .now.addingTimeInterval(-24)
        )
        fixture.addMarker("rhythm", at: .now.addingTimeInterval(-12))
        fixture.addMarker("intonation", at: .now.addingTimeInterval(-4))

        switch qaToolState {
        case .running:
            break
        case .paused, .recovered:
            fixture.pause()
        case .completed, .saveError:
            fixture.finish()
            pieceName = "Bach: Allemande"
            notes = "Keep the phrase moving through the shift."
        case .permissionDenied, .setup:
            break
        }

        runState = fixture
        if !nestedWithinPlan {
            if fixture.phase == .recording {
                coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(fixture))
            } else {
                coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(fixture))
                coordinator.pause()
            }
        }
        if qaToolState == .saveError {
            saveFailed = true
            showStatus(
                "The run-through could not be saved. Your recording is still here—try again.",
                kind: .error
            )
        } else if qaToolState == .recovered {
            showStatus("Recovered recording ready to review.", kind: .information)
        }
    }

    private func qaRecordingFixtureURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qa-runthrough-\(ProcessInfo.processInfo.processIdentifier).m4a")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data("PractiQuest QA recording fixture".utf8).write(
                to: url,
                options: .atomic
            )
        }
        return url
    }
    #else
    private func applyQAStateIfNeeded() {}
    #endif
}

@MainActor
final class RunThroughRecorder: ObservableObject {
    enum RecorderError: LocalizedError {
        case couldNotCreateFolder
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .couldNotCreateFolder:
                "The recording folder could not be created."
            case .couldNotStart:
                "The microphone recorder could not start."
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var lastOutputURL: URL?

    private var recorder: AVAudioRecorder?

    func startRecording() throws -> URL {
        discardRecording()
        let url = try makeOutputURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else {
            RunThroughFileLifecycle.removeIfPresent(at: url)
            throw RecorderError.couldNotStart
        }
        self.recorder = recorder
        lastOutputURL = url
        isRecording = true
        isPaused = false
        return url
    }

    func pause() {
        guard let recorder, recorder.isRecording else { return }
        recorder.pause()
        isRecording = false
        isPaused = true
    }

    @discardableResult
    func resume() -> Bool {
        guard let recorder, isPaused, recorder.record() else { return false }
        isRecording = true
        isPaused = false
        return true
    }

    func stopRecording() {
        recorder?.stop()
        isRecording = false
        isPaused = false
    }

    func discardRecording() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        isPaused = false
        RunThroughFileLifecycle.removeIfPresent(at: lastOutputURL)
        lastOutputURL = nil
    }

    private func makeOutputURL() throws -> URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let folder = documents.appendingPathComponent("RunThrough", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
        } catch {
            throw RecorderError.couldNotCreateFolder
        }
        return folder.appendingPathComponent(
            "runthrough-\(UUID().uuidString).m4a"
        )
    }
}
