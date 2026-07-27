import SwiftUI

struct WarmUpGeneratorView: View {
    private enum Instrument: String, CaseIterable, Codable, Identifiable {
        case strings
        case piano
        case voice
        case woodwinds

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    private enum Focus: String, CaseIterable, Codable, Identifiable {
        case intonation
        case shifts
        case bowStrokes
        case rhythm
        case tone

        var id: String { rawValue }
        var title: String {
            switch self {
            case .bowStrokes: "Bow Strokes"
            default: rawValue.capitalized
            }
        }
    }

    private struct WarmupStep: Identifiable, Codable, Equatable {
        let id: String
        let title: String
        let seconds: Int

        init(id: String = UUID().uuidString, title: String, seconds: Int) {
            self.id = id
            self.title = title
            self.seconds = seconds
        }
    }

    private struct RecoveryState: Codable {
        let minutes: Int
        let instrument: Instrument
        let selectedFocus: Set<String>
        let generatedTitle: String
        let steps: [WarmupStep]
        let stepIndex: Int
        let stepStartedAtElapsed: Int
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @EnvironmentObject private var store: SessionStore

    @State private var minutes = 10
    @State private var instrument: Instrument = .strings
    @State private var selectedFocus: Set<String> = [
        Focus.intonation.rawValue,
        Focus.rhythm.rawValue
    ]
    @State private var generatedTitle = "Custom Warm-up"
    @State private var generatedSteps: [WarmupStep] = []
    @State private var stepIndex = 0
    @State private var stepStartedAtElapsed = 0
    @State private var statusMessage: String?
    @State private var statusKind: StudioQuestInlineStatus.Kind = .information
    @State private var pendingResult: PracticeToolResult?
    @State private var completedDuration = 0
    @State private var didFinish = false
    @State private var saveFailed = false

    private var ownsRuntime: Bool {
        coordinator.activeToolID == .warmUp
    }

    private var isContextual: Bool {
        coordinator.toolLaunchContext?.parentSessionID != nil
    }

    private var isRunning: Bool {
        ownsRuntime && coordinator.toolActivityState?.phase == .running
    }

    private var isPaused: Bool {
        ownsRuntime && coordinator.toolActivityState?.phase == .paused
    }

    private var elapsedSeconds: Int {
        ownsRuntime ? coordinator.toolElapsedSeconds : completedDuration
    }

    private var currentStep: WarmupStep? {
        generatedSteps.indices.contains(stepIndex) ? generatedSteps[stepIndex] : nil
    }

    private var currentStepElapsed: Int {
        max(0, elapsedSeconds - stepStartedAtElapsed)
    }

    private var stepRemainingSeconds: Int {
        max(0, (currentStep?.seconds ?? 0) - currentStepElapsed)
    }

    private var totalPlanSeconds: Int {
        max(1, generatedSteps.reduce(0) { $0 + $1.seconds })
    }

    private var progress: Double {
        min(Double(elapsedSeconds) / Double(totalPlanSeconds), 1)
    }

    var body: some View {
        StudioQuestToolPage(
            title: "Warm-up Generator",
            subtitle: "Build a focused sequence, then move through it without leaving your practice flow.",
            systemImage: "sparkles"
        ) {
            if !ownsRuntime && !didFinish {
                setupPanel
                planPanel
            } else if didFinish {
                resultPanel
            } else {
                livePanel
                planPanel
            }

            if let statusMessage {
                StudioQuestInlineStatus(text: statusMessage, kind: statusKind)
                    .accessibilityIdentifier("warmup.status")
            }
        }
        .task {
            restoreIfNeeded()
            if generatedSteps.isEmpty {
                generateWarmup(announce: false)
            }
        }
        .onChange(of: coordinator.elapsedSeconds) {
            advanceStepIfNeeded()
        }
        .onDisappear {
            preserveOnExit()
        }
    }

    private var setupPanel: some View {
        StudioQuestToolSetupPanel {
            setupLabel("Duration")
            StudioQuestFlowLayout {
                ForEach([5, 10, 20], id: \.self) { value in
                    StudioQuestChoiceChip(
                        title: LocalizedStringKey("\(value) min"),
                        isSelected: minutes == value
                    ) {
                        minutes = value
                        generateWarmup(announce: false)
                    }
                    .accessibilityIdentifier("warmup.duration.\(value)")
                }
            }

            setupLabel("Instrument")
            StudioQuestFlowLayout {
                ForEach(Instrument.allCases) { option in
                    StudioQuestChoiceChip(
                        title: LocalizedStringKey(option.title),
                        isSelected: instrument == option
                    ) {
                        instrument = option
                        generateWarmup(announce: false)
                    }
                    .accessibilityIdentifier("warmup.instrument.\(option.rawValue)")
                }
            }

            setupLabel("Focus")
            StudioQuestFlowLayout {
                ForEach(Focus.allCases) { focus in
                    StudioQuestChoiceChip(
                        title: LocalizedStringKey(focus.title),
                        isSelected: selectedFocus.contains(focus.rawValue)
                    ) {
                        toggle(focus)
                    }
                    .accessibilityIdentifier("warmup.focus.\(focus.rawValue)")
                }
            }

            Button {
                startWarmup()
            } label: {
                Label(
                    coordinator.hasActivePractice ? "Start in current session" : "Start warm-up",
                    systemImage: "play.fill"
                )
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())
            .accessibilityIdentifier("warmup.start")
        }
    }

    @ViewBuilder
    private var planPanel: some View {
        if !generatedSteps.isEmpty {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        StudioQuestEyebrow(ownsRuntime ? "Sequence" : "Your sequence")
                        Text(generatedTitle)
                            .font(StudioQuestTokens.Typography.sectionTitle)
                    }
                    Spacer(minLength: StudioQuestTokens.Spacing.sm)
                    Text(DurationFormatter.string(from: totalPlanSeconds))
                        .font(StudioQuestTokens.Typography.measurement)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                VStack(spacing: 0) {
                    ForEach(Array(generatedSteps.enumerated()), id: \.element.id) { index, step in
                        warmupStepRow(step, index: index)
                        if index < generatedSteps.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            .padding(StudioQuestTokens.Spacing.md)
            .studioQuestSurface()
        }
    }

    private var livePanel: some View {
        StudioQuestToolLivePanel(eyebrow: isPaused ? "Paused" : "Now") {
            if let currentStep {
                Text(currentStep.title)
                    .font(StudioQuestTokens.Typography.heroTitle)
                    .tracking(-0.5)
                    .fixedSize(horizontal: false, vertical: true)

                StudioQuestProgressVisualization(
                    progress: progress,
                    accessibilityLabel: "Warm-up progress"
                )

                HStack(spacing: StudioQuestTokens.Spacing.sm) {
                    StudioQuestMetric(
                        title: "Step remaining",
                        value: DurationFormatter.string(from: stepRemainingSeconds),
                        detail: LocalizedStringKey("Step \(stepIndex + 1) of \(generatedSteps.count)")
                    )
                    StudioQuestMetric(
                        title: "Warm-up time",
                        value: DurationFormatter.string(from: elapsedSeconds),
                        detail: isContextual ? "Attached to current practice" : "Focused session",
                        tint: StudioQuestTokens.ColorRole.violet
                    )
                }

                HStack(spacing: StudioQuestTokens.Spacing.sm) {
                    Button {
                        previousStep()
                    } label: {
                        Label("Previous", systemImage: "backward.end.fill")
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                    .disabled(stepIndex == 0)
                    .accessibilityIdentifier("warmup.previous")

                    Button {
                        nextStep()
                    } label: {
                        Label(
                            stepIndex == generatedSteps.count - 1 ? "Complete step" : "Next",
                            systemImage: "forward.end.fill"
                        )
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                    .accessibilityIdentifier("warmup.next")
                }

                HStack(spacing: StudioQuestTokens.Spacing.sm) {
                    Button {
                        togglePause()
                    } label: {
                        Label(
                            isRunning ? "Pause" : "Resume",
                            systemImage: isRunning ? "pause.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                    .accessibilityIdentifier("warmup.pause")

                    Button {
                        finishWarmup()
                    } label: {
                        Label("Finish", systemImage: "checkmark")
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    .disabled(elapsedSeconds < 10)
                    .accessibilityIdentifier("warmup.finish")
                }

                if elapsedSeconds < 10 {
                    Text("Practice for at least 10 seconds before finishing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var resultPanel: some View {
        StudioQuestToolResultPanel {
            Label("Warm-up complete", systemImage: "checkmark.seal.fill")
                .font(StudioQuestTokens.Typography.sectionTitle)
                .foregroundStyle(StudioQuestTokens.ColorRole.mint)

            HStack(spacing: StudioQuestTokens.Spacing.sm) {
                StudioQuestMetric(
                    title: "Time",
                    value: DurationFormatter.string(from: completedDuration)
                )
                StudioQuestMetric(
                    title: "Steps",
                    value: "\(generatedSteps.count)",
                    tint: StudioQuestTokens.ColorRole.violet
                )
            }

            Button(saveFailed ? "Try saving again" : "Done") {
                if saveFailed, let pendingResult {
                    saveStandaloneResult(pendingResult)
                } else {
                    coordinator.detachTool()
                    dismiss()
                }
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())
            .accessibilityIdentifier(saveFailed ? "warmup.retrySave" : "warmup.done")
        }
    }

    private func setupLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func warmupStepRow(_ step: WarmupStep, index: Int) -> some View {
        HStack(spacing: StudioQuestTokens.Spacing.sm) {
            Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(index == stepIndex && ownsRuntime ? .white : StudioQuestTokens.ColorRole.cobalt)
                .frame(width: 30, height: 30)
                .background(
                    index == stepIndex && ownsRuntime
                        ? StudioQuestTokens.ColorRole.cobalt
                        : StudioQuestTokens.ColorRole.cobalt.opacity(0.10),
                    in: Circle()
                )

            Text(step.title)
                .font(.subheadline)
                .foregroundStyle(index < stepIndex && ownsRuntime ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(DurationFormatter.string(from: step.seconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, StudioQuestTokens.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index + 1), \(step.title)")
        .accessibilityValue(DurationFormatter.string(from: step.seconds))
    }

    private func toggle(_ focus: Focus) {
        if selectedFocus.contains(focus.rawValue) {
            if selectedFocus.count == 1 {
                showStatus("Choose at least one focus.", kind: .warning)
                return
            }
            selectedFocus.remove(focus.rawValue)
        } else {
            selectedFocus.insert(focus.rawValue)
        }
        generateWarmup(announce: false)
    }

    private func generateWarmup(announce: Bool) {
        let focus = selectedFocus.isEmpty
            ? [Focus.intonation.rawValue]
            : selectedFocus.sorted()
        let totalSeconds = minutes * 60
        let openingSeconds = min(120, max(45, totalSeconds / 5))
        let remaining = max(0, totalSeconds - openingSeconds)
        let baseFocusSeconds = focus.isEmpty ? 0 : remaining / focus.count
        var remainder = focus.isEmpty ? 0 : remaining % focus.count

        var steps = [
            WarmupStep(
                title: openingTitle(for: instrument),
                seconds: openingSeconds
            )
        ]

        for item in focus {
            let bonus = remainder > 0 ? 1 : 0
            remainder = max(0, remainder - bonus)
            steps.append(
                WarmupStep(
                    title: title(for: item, instrument: instrument),
                    seconds: max(30, baseFocusSeconds + bonus)
                )
            )
        }

        generatedTitle = "\(minutes)-minute \(instrument.title) warm-up"
        generatedSteps = steps
        stepIndex = 0
        stepStartedAtElapsed = 0
        pendingResult = nil
        completedDuration = 0
        didFinish = false
        saveFailed = false
        if announce {
            showStatus("Your warm-up is ready.", kind: .success)
        }
    }

    private func startWarmup() {
        guard !generatedSteps.isEmpty else {
            generateWarmup(announce: false)
            return
        }
        if let activeTool = coordinator.activeToolID, activeTool != .warmUp {
            showStatus(
                "Finish or close \(activeTool.title) before starting this warm-up.",
                kind: .warning
            )
            return
        }

        if !ownsRuntime {
            if coordinator.hasActivePractice {
                coordinator.attachTool(.warmUp)
                if !coordinator.isRunning {
                    coordinator.resume()
                }
            } else {
                coordinator.beginFocusedTool(
                    .warmUp,
                    title: generatedTitle,
                    durationMinutes: minutes,
                    source: .library
                )
            }
        }

        stepIndex = min(stepIndex, max(0, generatedSteps.count - 1))
        coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON())
        showStatus("Warm-up started.", kind: .information)
    }

    private func togglePause() {
        if isRunning {
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON())
            if !isContextual {
                coordinator.pause()
            }
        } else {
            if !isContextual {
                coordinator.resume()
            }
            coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON())
        }
    }

    private func previousStep() {
        guard stepIndex > 0 else { return }
        stepIndex -= 1
        stepStartedAtElapsed = elapsedSeconds
        persistRecovery()
    }

    private func nextStep() {
        guard !generatedSteps.isEmpty else { return }
        if stepIndex + 1 < generatedSteps.count {
            stepIndex += 1
            stepStartedAtElapsed = elapsedSeconds
            persistRecovery()
        } else {
            finishWarmup()
        }
    }

    private func advanceStepIfNeeded() {
        guard isRunning else { return }
        while let step = currentStep, elapsedSeconds - stepStartedAtElapsed >= step.seconds {
            if stepIndex + 1 < generatedSteps.count {
                stepIndex += 1
                stepStartedAtElapsed += step.seconds
                persistRecovery()
            } else {
                finishWarmup()
                return
            }
        }
    }

    private func finishWarmup() {
        guard elapsedSeconds >= 10 else {
            showStatus("Practice for at least 10 seconds before finishing.", kind: .warning)
            return
        }

        coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON())
        let duration = coordinator.toolElapsedSeconds
        let result = PracticeToolResult(
            toolID: .warmUp,
            sessionID: coordinator.activeSessionID,
            durationSeconds: duration,
            metrics: [
                "steps": Double(generatedSteps.count),
                "plannedSeconds": Double(totalPlanSeconds)
            ],
            payloadJSON: recoveryJSON() ?? ""
        )
        coordinator.completeTool(result)
        coordinator.queueQuestCompletion("warm-up-warrior")
        pendingResult = result
        completedDuration = duration

        if isContextual {
            didFinish = true
            showStatus(
                "Warm-up added to your active session. It will save when the session is finished.",
                kind: .success
            )
            return
        }

        coordinator.pause()
        saveStandaloneResult(result)
    }

    private func saveStandaloneResult(_ result: PracticeToolResult) {
        let summary = """
        Warm-up Generator
        Title: \(generatedTitle)
        Duration: \(DurationFormatter.string(from: result.durationSeconds))
        Focus: \(selectedFocus.sorted().joined(separator: ", "))
        Steps: \(generatedSteps.map(\.title).joined(separator: " | "))
        """
        let payload = PracticeSavePayload(
            sessionID: coordinator.activeSessionID,
            snapshot: coordinator.snapshot,
            notes: summary,
            noteTitle: "Warm-up Generator",
            noteFocus: selectedFocus.sorted().joined(separator: ", "),
            toolResult: result
        )

        if store.savePracticeCompletion(payload) {
            let savedID = coordinator.activeSessionID
            coordinator.completeAfterSave(savedSessionID: savedID)
            pendingResult = nil
            didFinish = true
            saveFailed = false
            showStatus("Warm-up saved.", kind: .success)
        } else {
            didFinish = true
            saveFailed = true
            showStatus(
                "The warm-up could not be saved. Your result is still here—try again.",
                kind: .error
            )
        }
    }

    private func restoreIfNeeded() {
        guard coordinator.activeToolID == .warmUp,
              let data = coordinator.toolActivityState?.recoveryPayloadJSON?.data(using: .utf8),
              let state = try? JSONDecoder().decode(RecoveryState.self, from: data) else {
            return
        }
        minutes = state.minutes
        instrument = state.instrument
        selectedFocus = state.selectedFocus
        generatedTitle = state.generatedTitle
        generatedSteps = state.steps
        stepIndex = min(max(0, state.stepIndex), max(0, state.steps.count - 1))
        stepStartedAtElapsed = state.stepStartedAtElapsed
        if let result = coordinator.latestToolResult,
           result.toolID == .warmUp {
            pendingResult = result
            completedDuration = result.durationSeconds
            didFinish = true
            saveFailed = coordinator.toolLaunchContext?.parentSessionID == nil
        }
        showStatus(
            didFinish
                ? "Warm-up result ready to save."
                : coordinator.toolActivityState?.phase == .running
                ? "Warm-up restored."
                : "Warm-up ready to resume.",
            kind: .information
        )
    }

    private func preserveOnExit() {
        guard !didFinish, coordinator.activeToolID == .warmUp else { return }
        coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON())
        if !isContextual {
            coordinator.pause()
        }
    }

    private func persistRecovery() {
        coordinator.updateToolRecoveryPayload(recoveryJSON())
    }

    private func recoveryJSON() -> String? {
        let state = RecoveryState(
            minutes: minutes,
            instrument: instrument,
            selectedFocus: selectedFocus,
            generatedTitle: generatedTitle,
            steps: generatedSteps,
            stepIndex: stepIndex,
            stepStartedAtElapsed: stepStartedAtElapsed
        )
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func showStatus(_ message: String, kind: StudioQuestInlineStatus.Kind) {
        statusMessage = message
        statusKind = kind
    }

    private func openingTitle(for instrument: Instrument) -> String {
        switch instrument {
        case .strings: "Open strings and long tones"
        case .piano: "Relaxed five-finger patterns"
        case .voice: "Breath and gentle resonance"
        case .woodwinds: "Breath support and long tones"
        }
    }

    private func title(for focus: String, instrument: Instrument) -> String {
        switch focus {
        case Focus.intonation.rawValue:
            instrument == .piano ? "Slow scales with balanced voicing" : "Slow scales with intonation focus"
        case Focus.shifts.rawValue:
            instrument == .voice ? "Register transitions" : "Position and register shifts"
        case Focus.bowStrokes.rawValue:
            instrument == .strings ? "Bow-stroke patterns" : "Articulation patterns"
        case Focus.rhythm.rawValue:
            "Subdivision and rhythm patterns"
        case Focus.tone.rawValue:
            "Tone core and resonance"
        default:
            focus.capitalized
        }
    }
}
