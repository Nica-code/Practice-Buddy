import SwiftUI
import AVFoundation
import Combine
import Darwin

struct PulseRhythmAccuracyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.studioQuestQAToolState) private var qaToolState
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @EnvironmentObject private var store: SessionStore

    @AppStorage("pb.rhythm.bpm") private var bpm = 80
    @AppStorage("pb.rhythm.targetBeats") private var targetBeats = 16
    @AppStorage("pb.rhythm.pulseMode") private var pulseModeRaw =
        RhythmPulseMode.visualHaptic.rawValue

    @StateObject private var onsetEngine = RhythmOnsetEngine()
    @State private var runState: RhythmAccuracyRunState?
    @State private var now = Date()
    @State private var countInBeat = 3
    @State private var pulseSequence = 0
    @State private var gridAnchorHostSeconds: TimeInterval?
    @State private var statusMessage: String?
    @State private var statusKind = StudioQuestInlineStatus.Kind.information
    @State private var replaceAudioConfirmationPresented = false
    @State private var permissionDenied = false
    @State private var stageTask: Task<Void, Never>?
    @State private var pulseTask: Task<Void, Never>?
    @State private var startedStandalone = false
    @State private var didFinish = false
    @State private var saveFailed = false
    @State private var didApplyQAState = false

    private let refresh = Timer.publish(every: 0.25, on: .main, in: .common)
        .autoconnect()

    private var pulseMode: RhythmPulseMode {
        get {
            RhythmPulseMode(rawValue: pulseModeRaw) ?? .visualHaptic
        }
        nonmutating set {
            pulseModeRaw = newValue.rawValue
        }
    }

    private var settings: RhythmAccuracySettings {
        RhythmAccuracySettings(
            bpm: bpm,
            targetBeats: targetBeats,
            pulseMode: pulseMode == .audibleHeadphones
                && coordinator.audioSession.hasHeadphones
                ? .audibleHeadphones
                : .visualHaptic
        )
    }

    private var isContextual: Bool {
        coordinator.toolLaunchContext?.parentSessionID != nil
    }

    var body: some View {
        StudioQuestToolPage(
            title: "Rhythm Accuracy",
            subtitle: "Measure how your attacks sit around the pulse without letting a speaker click distort the result.",
            systemImage: "metronome"
        ) {
            if permissionDenied {
                StudioQuestPermissionState(
                    title: "Microphone access is off",
                    message: "Rhythm Accuracy listens only for attack timing. Enable microphone access in Settings, then try again.",
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
                    .accessibilityIdentifier("rhythm.status")
            }
        }
        .task {
            restoreIfNeeded()
            applyQAStateIfNeeded()
        }
        .onReceive(refresh) { date in
            now = date
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                interruptTake(
                    "The take paused while PractiQuest was in the background. Resume with a fresh count-in."
                )
            }
        }
        .onChange(of: coordinator.audioSession.lastEvent) { _, event in
            handleAudioEvent(event)
        }
        .onChange(of: coordinator.audioSession.hasHeadphones) { _, hasHeadphones in
            if !hasHeadphones, pulseMode == .audibleHeadphones {
                pulseMode = .visualHaptic
            }
        }
        .onDisappear {
            preserveOnExit()
        }
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
            Text("PractiQuest allows one microphone or audio utility at a time so rhythm scoring stays reliable.")
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch runState?.phase {
        case .calibrating:
            calibrationPanel
        case .countIn:
            countInPanel
        case .listening, .paused:
            livePanel
        case .result:
            resultPanel
        case .insufficientInput:
            insufficientInputPanel
        case .failed:
            failedPanel
        case .idle, .none:
            setupPanel
        }
    }

    private var setupPanel: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            StudioQuestToolSetupPanel {
                settingStepper(
                    title: "Tempo",
                    value: $bpm,
                    range: 40...220,
                    step: 1,
                    formattedValue: "\(bpm) BPM"
                )
                settingStepper(
                    title: "Take length",
                    value: $targetBeats,
                    range: 8...128,
                    step: 8,
                    formattedValue: "\(targetBeats) beats"
                )

                Divider()

                Toggle(
                    "Audible click in headphones",
                    isOn: Binding(
                        get: { pulseMode == .audibleHeadphones },
                        set: { pulseMode = $0 ? .audibleHeadphones : .visualHaptic }
                    )
                )
                .disabled(!coordinator.audioSession.hasHeadphones)
                .accessibilityHint(
                    coordinator.audioSession.hasHeadphones
                        ? "Uses a headphone click while scoring."
                        : "Connect headphones to make the audible click available."
                )

                Label(
                    coordinator.audioSession.hasHeadphones
                        ? "Visual and haptic pulse is the quiet default."
                        : "Speaker click stays off so it cannot be scored as your attack.",
                    systemImage: coordinator.audioSession.hasHeadphones
                        ? "waveform.path"
                        : "speaker.slash.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                requestStart()
            } label: {
                Label(
                    coordinator.hasActivePractice
                        ? "Measure in current session"
                        : "Start rhythm take",
                    systemImage: "waveform.and.mic"
                )
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())
            .accessibilityIdentifier("rhythm.start")
        }
    }

    private var calibrationPanel: some View {
        StudioQuestToolLivePanel(eyebrow: "Calibrating") {
            VStack(spacing: StudioQuestTokens.Spacing.md) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                Text("Hold your instrument naturally")
                    .font(StudioQuestTokens.Typography.sectionTitle)
                Text("PractiQuest is measuring the room floor so quiet background sound is not mistaken for an attack.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private var countInPanel: some View {
        StudioQuestToolLivePanel(eyebrow: "Count in") {
            VStack(spacing: StudioQuestTokens.Spacing.md) {
                pulseIndicator(size: 150)
                Text("\(countInBeat)")
                    .font(StudioQuestTokens.Typography.timer)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Count in")
                    .accessibilityValue("\(countInBeat)")
                Text("Begin on the next pulse.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Cancel") {
                    discardTake()
                }
                .buttonStyle(StudioQuestSecondaryButtonStyle())
                .accessibilityIdentifier("rhythm.cancel")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var livePanel: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            if let state = runState {
                StudioQuestToolLivePanel(
                    eyebrow: state.phase == .paused ? "Paused" : "Listening"
                ) {
                    HStack(alignment: .center, spacing: StudioQuestTokens.Spacing.lg) {
                        pulseIndicator(size: 108)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(liveFeel(for: state.latestOffsetMs))
                                .font(StudioQuestTokens.Typography.heroTitle)
                                .tracking(-0.5)
                            Text(formattedOffset(state.latestOffsetMs))
                                .font(StudioQuestTokens.Typography.timer)
                                .monospacedDigit()
                                .foregroundStyle(tint(for: state.latestOffsetMs))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Live timing")
                    .accessibilityValue(
                        "\(liveFeel(for: state.latestOffsetMs)), \(formattedOffset(state.latestOffsetMs))"
                    )

                    StudioQuestProgressVisualization(
                        progress: state.progress,
                        accessibilityLabel: "Rhythm take progress"
                    )

                    HStack(spacing: StudioQuestTokens.Spacing.sm) {
                        StudioQuestMetric(
                            title: "Beats",
                            value: "\(state.beatsAnalyzed) / \(state.settings.targetBeats)"
                        )
                        StudioQuestMetric(
                            title: "Tempo",
                            value: "\(state.settings.bpm)",
                            detail: "BPM",
                            tint: StudioQuestTokens.ColorRole.violet
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
                        .accessibilityIdentifier("rhythm.pause")

                        Button {
                            finishTake()
                        } label: {
                            Label("Finish", systemImage: "stop.fill")
                        }
                        .buttonStyle(StudioQuestPrimaryButtonStyle())
                        .accessibilityIdentifier("rhythm.finish")
                    }
                }

                if !state.offsetsMs.isEmpty {
                    distributionPanel(offsets: state.offsetsMs)
                }
            }
        }
    }

    @ViewBuilder
    private var resultPanel: some View {
        if let state = runState, let summary = state.summary {
            if didFinish {
                StudioQuestToolResultPanel {
                    Label("Rhythm take saved", systemImage: "checkmark.seal.fill")
                        .font(StudioQuestTokens.Typography.sectionTitle)
                        .foregroundStyle(StudioQuestTokens.ColorRole.mint)
                    Text("The complete timing distribution is available in History.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    resultMetrics(summary)
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    .accessibilityIdentifier("rhythm.done")
                }
            } else {
                StudioQuestToolResultPanel {
                    Label("Take complete", systemImage: "waveform.badge.checkmark")
                        .font(StudioQuestTokens.Typography.sectionTitle)
                        .foregroundStyle(StudioQuestTokens.ColorRole.mint)

                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Groove score")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(summary.grooveScore)")
                                .font(StudioQuestTokens.Typography.timer)
                                .monospacedDigit()
                                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                        }
                        Spacer()
                        Text(tendencyTitle(summary.tendency))
                            .font(StudioQuestTokens.Typography.cardTitle)
                    }

                    resultMetrics(summary)
                    distributionPanel(offsets: state.offsetsMs)

                    Text(recommendation(for: summary))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !summary.windowStats.isEmpty {
                        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.sm) {
                            StudioQuestEyebrow("Timing windows")
                            ForEach(summary.windowStats) { window in
                                HStack {
                                    Text("Beats \(window.index * 8 + 1)–\(window.index * 8 + window.sampleCount)")
                                    Spacer()
                                    Text(String(format: "%+.0f ms", window.averageOffsetMs))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }

                    Button {
                        saveTake(state: state, summary: summary)
                    } label: {
                        Label(
                            saveFailed
                                ? "Try saving again"
                                : (isContextual ? "Add to active session" : "Save rhythm take"),
                            systemImage: "checkmark"
                        )
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    .accessibilityIdentifier("rhythm.save")

                    Button("Discard take", role: .destructive) {
                        discardTake()
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                    .accessibilityIdentifier("rhythm.discard")
                }
            }
        }
    }

    private var insufficientInputPanel: some View {
        StudioQuestPermissionState(
            title: "Not enough attacks detected",
            message: "This is different from inaccurate timing. Play with a clearer attack or move the device closer, then start a fresh take.",
            systemImage: "waveform.slash",
            actionTitle: "Try another take"
        ) {
            discardTake(resetToSetup: true)
        }
    }

    private var failedPanel: some View {
        StudioQuestPermissionState(
            title: "Take interrupted",
            message: "The audio route changed or the microphone stopped. This take was not scored, so the result cannot be misleading.",
            systemImage: "exclamationmark.waveform",
            actionTitle: "Start a fresh take"
        ) {
            discardTake(resetToSetup: true)
        }
    }

    private func distributionPanel(offsets: [Double]) -> some View {
        let summary = RhythmAccuracyScorer.summary(for: offsets)
        let total = max(1, summary.beatsAnalyzed)
        return VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.sm) {
            StudioQuestEyebrow("Timing distribution")
            GeometryReader { proxy in
                let spacing = CGFloat(4)
                let nonEmptySegments = [
                    summary.earlyCount,
                    summary.centeredCount,
                    summary.lateCount
                ].filter { $0 > 0 }.count
                let availableWidth = max(
                    0,
                    proxy.size.width - spacing * CGFloat(max(0, nonEmptySegments - 1))
                )

                HStack(spacing: spacing) {
                    distributionSegment(
                        count: summary.earlyCount,
                        total: total,
                        availableWidth: availableWidth,
                        color: StudioQuestTokens.ColorRole.gold
                    )
                    distributionSegment(
                        count: summary.centeredCount,
                        total: total,
                        availableWidth: availableWidth,
                        color: StudioQuestTokens.ColorRole.mint
                    )
                    distributionSegment(
                        count: summary.lateCount,
                        total: total,
                        availableWidth: availableWidth,
                        color: StudioQuestTokens.ColorRole.violet
                    )
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            HStack {
                distributionLabel("Early", count: summary.earlyCount)
                Spacer()
                distributionLabel("Centered", count: summary.centeredCount)
                Spacer()
                distributionLabel("Late", count: summary.lateCount)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timing distribution")
        .accessibilityValue(
            "\(summary.earlyCount) early, \(summary.centeredCount) centered, \(summary.lateCount) late"
        )
    }

    private func distributionSegment(
        count: Int,
        total: Int,
        availableWidth: CGFloat,
        color: Color
    ) -> some View {
        color
            .frame(
                width: count == 0
                    ? 0
                    : availableWidth * CGFloat(count) / CGFloat(total)
            )
    }

    private func distributionLabel(
        _ title: LocalizedStringKey,
        count: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption.monospacedDigit())
        }
    }

    private func resultMetrics(_ summary: RhythmAccuracySummary) -> some View {
        HStack(spacing: StudioQuestTokens.Spacing.sm) {
            StudioQuestMetric(
                title: "Average",
                value: String(format: "%+.0f", summary.averageOffsetMs),
                detail: "ms"
            )
            StudioQuestMetric(
                title: "Accuracy",
                value: String(format: "%.0f", summary.averageAbsoluteOffsetMs),
                detail: "avg |ms|",
                tint: StudioQuestTokens.ColorRole.violet
            )
            StudioQuestMetric(
                title: "Stability",
                value: String(format: "%.0f", summary.standardDeviationMs),
                detail: "deviation",
                tint: StudioQuestTokens.ColorRole.mint
            )
        }
    }

    private func pulseIndicator(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(StudioQuestTokens.ColorRole.cobalt.opacity(0.16), lineWidth: 12)
            Circle()
                .fill(StudioQuestTokens.ColorRole.cobalt.opacity(0.12))
                .padding(size * 0.18)
            Circle()
                .fill(StudioQuestTokens.ColorRole.cobalt)
                .padding(size * 0.34)
        }
        .frame(width: size, height: size)
        .scaleEffect(reduceMotion ? 1 : (pulseSequence.isMultiple(of: 2) ? 0.92 : 1))
        .animation(
            reduceMotion ? .linear(duration: 0.12) : .snappy(duration: 0.2),
            value: pulseSequence
        )
        .accessibilityHidden(true)
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
        if let active = coordinator.activeToolID, active != .rhythm {
            showStatus(
                "Finish or close \(active.title) before starting Rhythm Accuracy.",
                kind: .warning
            )
            return
        }
        if let owner = coordinator.audioSession.owner, owner != .rhythm {
            replaceAudioConfirmationPresented = true
            return
        }
        Task { await startTake(replacingAudio: false) }
    }

    private func startTake(replacingAudio: Bool) async {
        if replacingAudio {
            guard stopReplaceableAudioOwner() else { return }
        }
        guard await claimAudio() else { return }

        if coordinator.activeToolID != .rhythm {
            if coordinator.hasActivePractice {
                guard coordinator.attachTool(.rhythm) != nil else {
                    coordinator.audioSession.release(.rhythm)
                    return
                }
                startedStandalone = false
            } else {
                let estimatedSeconds = Int(
                    ceil(Double(targetBeats + 4) * settings.beatInterval)
                )
                guard coordinator.beginFocusedTool(
                    .rhythm,
                    title: "Rhythm Accuracy",
                    durationMinutes: max(1, Int(ceil(Double(estimatedSeconds) / 60))),
                    source: .library
                ) else {
                    coordinator.audioSession.release(.rhythm)
                    return
                }
                startedStandalone = true
            }
        }

        var state = RhythmAccuracyRunState(settings: settings)
        state.beginCalibration()
        runState = state
        permissionDenied = false
        didFinish = false
        saveFailed = false
        statusMessage = nil

        do {
            try onsetEngine.startCalibration { onsetHostSeconds in
                registerOnset(at: onsetHostSeconds)
            }
        } catch {
            state.fail("Microphone input could not start.")
            runState = state
            cleanupAfterFailedStart()
            showStatus("Microphone input could not start. No take was kept.", kind: .error)
            return
        }
        persistRecovery()
        scheduleCalibrationAndCountIn(isResume: false)
    }

    private func scheduleCalibrationAndCountIn(isResume: Bool) {
        stageTask?.cancel()
        stageTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, var state = runState else { return }
            _ = onsetEngine.finishCalibration()
            state.beginCountIn()
            runState = state
            persistRecovery()

            if state.settings.pulseMode == .audibleHeadphones {
                startAudiblePulse(for: state.settings)
            }

            for beat in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                countInBeat = beat
                triggerPulse()
                try? await Task.sleep(
                    for: .seconds(state.settings.beatInterval)
                )
            }
            guard !Task.isCancelled else { return }
            beginListeningAfterCountIn(isResume: isResume)
        }
    }

    private func beginListeningAfterCountIn(isResume: Bool) {
        guard var state = runState else { return }
        gridAnchorHostSeconds = onsetEngine.currentHostSeconds()
        onsetEngine.beginCapture()
        state.beginListening()
        runState = state
        if !isContextual, isResume {
            coordinator.resume()
        }
        coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        startVisualPulseLoop(interval: state.settings.beatInterval)
        showStatus("Listening for your attacks.", kind: .information)
    }

    private func registerOnset(at onsetHostSeconds: TimeInterval) {
        guard var state = runState,
              state.phase == .listening,
              let gridAnchorHostSeconds,
              let offset = RhythmAccuracyScorer.offsetMilliseconds(
                onsetHostSeconds: onsetHostSeconds,
                gridAnchorHostSeconds: gridAnchorHostSeconds,
                beatInterval: state.settings.beatInterval
              ) else { return }

        state.register(offsetMilliseconds: offset)
        runState = state
        persistRecovery()
        if state.phase == .result {
            stopCaptureForReview(state)
            PBHaptics.success()
        }
    }

    private func togglePause() {
        guard var state = runState else { return }
        if state.phase == .listening {
            state.pause()
            runState = state
            stopAudioCapture()
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            if !isContextual {
                coordinator.pause()
            }
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
            if !isContextual {
                coordinator.resume()
            }
            coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            return
        }
        #endif

        guard await claimAudio() else { return }
        state.beginResumeCalibration()
        runState = state
        do {
            try onsetEngine.startCalibration { onsetHostSeconds in
                registerOnset(at: onsetHostSeconds)
            }
        } catch {
            state.fail("Microphone input could not resume.")
            runState = state
            coordinator.audioSession.release(.rhythm)
            showStatus("Microphone input could not resume.", kind: .error)
            return
        }
        scheduleCalibrationAndCountIn(isResume: true)
    }

    private func finishTake() {
        guard var state = runState else { return }
        state.finish(at: now)
        runState = state
        stopCaptureForReview(state)
        if state.phase == .insufficientInput {
            showStatus(
                "The microphone heard too few clear attacks to score this take.",
                kind: .warning
            )
        }
    }

    private func stopCaptureForReview(_ state: RhythmAccuracyRunState) {
        stopAudioCapture()
        coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        if !isContextual {
            coordinator.pause()
        }
    }

    private func interruptTake(_ message: String) {
        guard var state = runState,
              [.calibrating, .countIn, .listening].contains(state.phase) else {
            return
        }
        if state.phase == .listening {
            state.pause()
        } else {
            state.phase = .paused
        }
        runState = state
        stopAudioCapture()
        coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        if !isContextual {
            coordinator.pause()
        }
        showStatus(message, kind: .warning)
    }

    private func invalidateTake(_ message: String) {
        guard var state = runState,
              [.calibrating, .countIn, .listening, .paused].contains(state.phase) else {
            return
        }
        state.fail(message)
        runState = state
        stopAudioCapture()
        coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        if !isContextual {
            coordinator.pause()
        }
        showStatus(message, kind: .error)
    }

    private func saveTake(
        state: RhythmAccuracyRunState,
        summary: RhythmAccuracySummary
    ) {
        let payload = RhythmAccuracyResultPayload(
            completedAt: .now,
            durationSeconds: state.elapsedSeconds(at: now),
            settings: state.settings,
            summary: summary,
            parentSessionID: isContextual ? coordinator.activeSessionID : nil,
            launchSource: isContextual
                ? .activeSession
                : (coordinator.toolLaunchContext?.source ?? .legacy),
            toolVersion: 2
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            showStatus("The rhythm result could not be prepared.", kind: .error)
            return
        }
        let result = PracticeToolResult(
            toolID: .rhythm,
            sessionID: coordinator.activeSessionID,
            durationSeconds: payload.durationSeconds,
            metrics: [
                "beats": Double(summary.beatsAnalyzed),
                "grooveScore": Double(summary.grooveScore),
                "averageOffsetMs": summary.averageOffsetMs,
                "averageAbsoluteOffsetMs": summary.averageAbsoluteOffsetMs
            ],
            payloadJSON: json
        )
        coordinator.queueQuestCompletion("rhythm-clarity")

        if isContextual {
            coordinator.attachCompletedToolResult(result)
            coordinator.detachTool()
            didFinish = true
            saveFailed = false
            dismiss()
            return
        }

        coordinator.completeTool(result)
        let notes = """
        Rhythm Accuracy
        Groove score: \(summary.grooveScore)
        Average offset: \(String(format: "%+.1f ms", summary.averageOffsetMs))
        Average absolute offset: \(String(format: "%.1f ms", summary.averageAbsoluteOffsetMs))
        """
        let didSave = store.savePracticeCompletion(
            PracticeSavePayload(
                sessionID: coordinator.activeSessionID,
                snapshot: coordinator.snapshot,
                notes: notes,
                noteTitle: "Rhythm Accuracy",
                noteFocus: tendencyTitle(summary.tendency),
                toolResult: result,
                attachedToolResults: coordinator.attachedToolResults
            )
        )
        if didSave {
            coordinator.completeAfterSave(savedSessionID: store.lastSavedSessionID)
            didFinish = true
            saveFailed = false
            showStatus("Rhythm take saved in History.", kind: .success)
        } else {
            saveFailed = true
            showStatus(
                "The take could not be saved. Your result is still here—try again.",
                kind: .error
            )
        }
    }

    private func discardTake(resetToSetup: Bool = false) {
        stopAudioCapture()
        if startedStandalone {
            coordinator.discard()
        } else if coordinator.activeToolID == .rhythm {
            coordinator.detachTool()
        }
        runState = nil
        permissionDenied = false
        statusMessage = nil
        didFinish = false
        saveFailed = false
        startedStandalone = false
        if !resetToSetup {
            dismiss()
        }
    }

    private func preserveOnExit() {
        stageTask?.cancel()
        pulseTask?.cancel()
        guard !didFinish, var state = runState else {
            stopAudioCapture()
            return
        }
        if isContextual {
            stopAudioCapture()
            coordinator.detachTool()
            return
        }
        if [.calibrating, .countIn, .listening].contains(state.phase) {
            if state.phase == .listening {
                state.pause()
            } else {
                state.phase = .paused
            }
            runState = state
            stopAudioCapture()
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            coordinator.pause()
        }
    }

    private func restoreIfNeeded() {
        guard coordinator.activeToolID == .rhythm,
              let json = coordinator.toolActivityState?.recoveryPayloadJSON,
              let data = json.data(using: .utf8),
              var restored = try? JSONDecoder().decode(
                RhythmAccuracyRunState.self,
                from: data
              ) else { return }

        if [.calibrating, .countIn, .listening].contains(restored.phase) {
            if restored.phase == .listening {
                restored.pause()
            } else {
                restored.phase = .paused
            }
        }
        apply(restored.settings)
        runState = restored
        startedStandalone = coordinator.toolLaunchContext?.parentSessionID == nil
        showStatus(
            restored.phase == .result
                ? "Recovered rhythm result ready to save."
                : "Recovered rhythm take ready for a fresh count-in.",
            kind: .information
        )
    }

    private func claimAudio() async -> Bool {
        var requirements: PracticeAudioRequirement = [.microphone]
        if settings.pulseMode == .audibleHeadphones {
            requirements.insert(.playback)
        }
        do {
            try await coordinator.audioSession.claim(
                .rhythm,
                requirements: requirements
            )
            return true
        } catch PracticeAudioSessionError.microphoneDenied {
            permissionDenied = true
            showStatus("Microphone access is required before a take can begin.", kind: .error)
            return false
        } catch {
            showStatus(
                (error as? LocalizedError)?.errorDescription
                    ?? "Audio could not be started.",
                kind: .error
            )
            return false
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
        case .none, .rhythm:
            return true
        default:
            showStatus(
                "That audio activity cannot be replaced safely. Close it first.",
                kind: .warning
            )
            return false
        }
        coordinator.audioSession.releaseCurrentOwner()
        return true
    }

    private func startAudiblePulse(for settings: RhythmAccuracySettings) {
        guard settings.pulseMode == .audibleHeadphones,
              coordinator.audioSession.hasHeadphones else { return }
        coordinator.metronome.setBPM(settings.bpm)
        coordinator.metronome.start(
            beatsPerBar: 4,
            subdivision: .none,
            soundStyle: .click
        )
    }

    private func startVisualPulseLoop(interval: TimeInterval) {
        pulseTask?.cancel()
        pulseTask = Task { @MainActor in
            while !Task.isCancelled, runState?.phase == .listening {
                triggerPulse()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func triggerPulse() {
        pulseSequence &+= 1
        PBHaptics.tap()
    }

    private func stopAudioCapture() {
        stageTask?.cancel()
        pulseTask?.cancel()
        onsetEngine.stop()
        coordinator.metronome.stop()
        coordinator.audioSession.release(.rhythm)
        gridAnchorHostSeconds = nil
    }

    private func cleanupAfterFailedStart() {
        stopAudioCapture()
        if startedStandalone {
            coordinator.discard()
        } else if coordinator.activeToolID == .rhythm {
            coordinator.detachTool()
        }
    }

    private func persistRecovery() {
        guard let state = runState else { return }
        coordinator.updateToolRecoveryPayload(recoveryJSON(state))
    }

    private func recoveryJSON(_ state: RhythmAccuracyRunState) -> String? {
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func handleAudioEvent(_ event: PracticeAudioEvent?) {
        guard let event else { return }
        switch event {
        case .interrupted(.rhythm):
            invalidateTake("Audio was interrupted, so this take was not scored.")
        case .routeChanged:
            if [.countIn, .listening].contains(runState?.phase) {
                invalidateTake("The audio route changed, so this take was not scored.")
            }
        default:
            break
        }
    }

    private func apply(_ settings: RhythmAccuracySettings) {
        bpm = settings.bpm
        targetBeats = settings.targetBeats
        pulseModeRaw = settings.pulseMode.rawValue
    }

    private func liveFeel(for offset: Double?) -> String {
        guard let offset else { return "Waiting" }
        if abs(offset) <= RhythmAccuracyScorer.centeredToleranceMs {
            return "Centered"
        }
        return offset < 0 ? "Early" : "Late"
    }

    private func formattedOffset(_ offset: Double?) -> String {
        guard let offset else { return "— ms" }
        return String(format: "%+.0f ms", offset)
    }

    private func tint(for offset: Double?) -> Color {
        guard let offset else { return StudioQuestTokens.ColorRole.cobalt }
        if abs(offset) <= RhythmAccuracyScorer.centeredToleranceMs {
            return StudioQuestTokens.ColorRole.mint
        }
        return offset < 0
            ? StudioQuestTokens.ColorRole.gold
            : StudioQuestTokens.ColorRole.violet
    }

    private func tendencyTitle(_ tendency: RhythmTimingTendency) -> String {
        switch tendency {
        case .centered: "Centered pulse"
        case .early: "Leaning early"
        case .late: "Leaning late"
        case .mixed: "Mixed tendency"
        }
    }

    private func recommendation(for summary: RhythmAccuracySummary) -> String {
        switch summary.tendency {
        case .centered:
            "Your attacks cluster around the pulse. Keep the same physical preparation as the tempo changes."
        case .early:
            "Your attacks tend to arrive early. Release tension before the pulse and let the preparation finish closer to the beat."
        case .late:
            "Your attacks tend to arrive late. Prepare the motion earlier while keeping the sound itself aligned with the pulse."
        case .mixed:
            "The direction changes across the take. Use a shorter passage and stabilize one repeated motion before increasing tempo."
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
                .rhythm,
                title: "Rhythm Accuracy",
                durationMinutes: 2,
                source: .qa
            )
            startedStandalone = true
        }
        var fixture = RhythmAccuracyRunState(
            settings: RhythmAccuracySettings(
                bpm: 84,
                targetBeats: 16,
                pulseMode: .visualHaptic
            )
        )
        fixture.beginListening(at: .now.addingTimeInterval(-18))
        for offset in [-18, 12, 22, -36, 8, 42, 16, -11, 28, 35, -24, 6] {
            fixture.register(offsetMilliseconds: Double(offset))
        }

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
            showStatus(
                "Recovered rhythm take ready for a fresh count-in.",
                kind: .information
            )
        }
    }
    #else
    private func applyQAStateIfNeeded() {}
    #endif
}

@MainActor
final class RhythmOnsetEngine: ObservableObject {
    enum EngineError: Error {
        case unavailableInput
        case couldNotStart
    }

    @Published private(set) var isListeningReady = false
    @Published private(set) var calibratedThreshold: Float = 0.02

    private let engine = AVAudioEngine()
    private let processingQueue = DispatchQueue(
        label: "com.practiquest.rhythm-onset-processing",
        qos: .userInitiated
    )
    private var tapInstalled = false
    private var onsetHandler: ((TimeInterval) -> Void)?
    private var detector = RhythmOnsetDetector()
    private var calibrationPeaks: [Float] = []
    private var isCalibrating = false
    private var acceptsOnsets = false

    func startCalibration(
        onsetHandler: @escaping (TimeInterval) -> Void
    ) throws {
        stop()
        self.onsetHandler = onsetHandler
        processingQueue.sync {
            calibrationPeaks = []
            isCalibrating = true
            acceptsOnsets = false
            detector = RhythmOnsetDetector()
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw EngineError.unavailableInput
        }
        input.installTap(
            onBus: 0,
            bufferSize: 512,
            format: format
        ) { [weak self] buffer, time in
            guard let self,
                  let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(
                UnsafeBufferPointer(
                    start: channel,
                    count: Int(buffer.frameLength)
                )
            )
            let hostSeconds = AVAudioTime.seconds(forHostTime: time.hostTime)
            processingQueue.async { [weak self] in
                Task { @MainActor [weak self] in
                    self?.process(samples: samples, hostSeconds: hostSeconds)
                }
            }
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
            isListeningReady = true
        } catch {
            stop()
            throw EngineError.couldNotStart
        }
    }

    @discardableResult
    func finishCalibration() -> Float {
        let threshold = processingQueue.sync {
            let value = RhythmCalibrationThreshold.value(from: calibrationPeaks)
            calibratedThreshold = value
            detector = RhythmOnsetDetector(threshold: value)
            isCalibrating = false
            return value
        }
        return threshold
    }

    func beginCapture() {
        processingQueue.sync {
            detector = RhythmOnsetDetector(threshold: calibratedThreshold)
            acceptsOnsets = true
            isCalibrating = false
        }
    }

    func currentHostSeconds() -> TimeInterval {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }

    func stop() {
        processingQueue.sync {
            isCalibrating = false
            acceptsOnsets = false
            calibrationPeaks = []
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        onsetHandler = nil
        isListeningReady = false
    }

    private func process(
        samples: [Float],
        hostSeconds: TimeInterval
    ) {
        let peak = samples.reduce(Float.zero) { max($0, abs($1)) }
        if isCalibrating {
            calibrationPeaks.append(peak)
            if calibrationPeaks.count > 256 {
                calibrationPeaks.removeFirst(calibrationPeaks.count - 256)
            }
            return
        }
        guard acceptsOnsets,
              detector.detectOnset(samples: samples, at: hostSeconds) else {
            return
        }
        Task { @MainActor [weak self] in
            self?.onsetHandler?(hostSeconds)
        }
    }
}
