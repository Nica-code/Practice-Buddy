import SwiftUI
import Combine

struct PlanExecuteReflectView: View {
    private enum ScreenPhase {
        case plan
        case execute
        case reflect
        case done
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.studioQuestQAToolState) private var qaToolState
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @EnvironmentObject private var store: SessionStore

    @State private var selectedGoals: Set<GuidedPracticeGoal> = [.intonation, .rhythm]
    @State private var blocks: [GuidedPracticeBlock] = [
        GuidedPracticeBlock(kind: .warmUp, durationSeconds: 5 * 60),
        GuidedPracticeBlock(kind: .technique, durationSeconds: 10 * 60),
        GuidedPracticeBlock(kind: .repertoire, durationSeconds: 10 * 60),
        GuidedPracticeBlock(kind: .runThrough, durationSeconds: 5 * 60)
    ]
    @State private var enabledBlockIDs: Set<UUID> = []
    @State private var runState: GuidedPracticeRunState?
    @State private var reflectionWins = ""
    @State private var reflectionFix = ""
    @State private var reflectionNext = ""
    @State private var selfRating = 3
    @State private var statusMessage: String?
    @State private var statusKind = StudioQuestInlineStatus.Kind.information
    @State private var saveFailed = false
    @State private var didFinish = false
    @State private var didApplyQAState = false
    @State private var now = Date()
    @State private var replaceAudioConfirmationPresented = false
    @State private var requestedAudioOwner: PracticeAudioOwner?

    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var screenPhase: ScreenPhase {
        if didFinish { return .done }
        switch runState?.phase {
        case .running, .paused: return .execute
        case .reflect: return .reflect
        case .completed: return .done
        case .plan, .none: return .plan
        }
    }

    private var selectedBlocks: [GuidedPracticeBlock] {
        blocks.filter { enabledBlockIDs.contains($0.id) }
    }

    private var targetMinutes: Int {
        max(1, selectedBlocks.reduce(0) { $0 + $1.durationSeconds } / 60)
    }

    private var isContextual: Bool {
        coordinator.toolLaunchContext?.parentSessionID != nil
    }

    private var planIsValid: Bool {
        (2...4).contains(selectedGoals.count) && !selectedBlocks.isEmpty
    }

    var body: some View {
        StudioQuestToolPage(
            title: "Plan · Execute · Reflect",
            subtitle: "Give each part of your practice a purpose, then leave with a clear next step.",
            systemImage: "checklist"
        ) {
            switch screenPhase {
            case .plan:
                planContent
            case .execute:
                executeContent
            case .reflect:
                reflectionContent
            case .done:
                doneContent
            }

            if let statusMessage {
                StudioQuestInlineStatus(text: statusMessage, kind: statusKind)
                    .accessibilityIdentifier("guided.status")
            }
        }
        .task {
            if enabledBlockIDs.isEmpty {
                enabledBlockIDs = Set(blocks.map(\.id))
            }
            restoreIfNeeded()
            applyQAStateIfNeeded()
        }
        .onReceive(refresh) { date in
            now = date
            advanceExecution(to: date)
        }
        .onChange(of: scenePhase) { _, next in
            if next == .active {
                advanceExecution(to: .now)
            } else {
                persistRecovery()
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
            Button("Replace") {
                guard let requestedAudioOwner else { return }
                Task { await toggleAudio(requestedAudioOwner, replacing: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("PractiQuest allows one audio utility at a time so timing and recordings stay reliable.")
        }
    }

    private var planContent: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            StudioQuestToolSetupPanel(title: "Intention") {
                Text("Choose 2–4 goals")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                StudioQuestFlowLayout {
                    ForEach(GuidedPracticeGoal.allCases) { goal in
                        StudioQuestChoiceChip(
                            title: LocalizedStringKey(goal.title),
                            isSelected: selectedGoals.contains(goal)
                        ) {
                            toggleGoal(goal)
                        }
                    }
                }
            }

            StudioQuestToolSetupPanel(title: "Practice blocks") {
                Text("\(targetMinutes) min planned")
                    .font(StudioQuestTokens.Typography.cardTitle)
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                    .monospacedDigit()

                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    blockSetupRow(block, index: index)
                }
            }

            Button {
                beginExecution()
            } label: {
                Label("Start guided practice", systemImage: "play.fill")
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())
            .disabled(!planIsValid)
            .accessibilityIdentifier("guided.start")
        }
    }

    private func blockSetupRow(
        _ block: GuidedPracticeBlock,
        index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.sm) {
            HStack(spacing: StudioQuestTokens.Spacing.sm) {
                Toggle(
                    isOn: Binding(
                        get: { enabledBlockIDs.contains(block.id) },
                        set: { enabled in
                            if enabled {
                                enabledBlockIDs.insert(block.id)
                            } else {
                                enabledBlockIDs.remove(block.id)
                            }
                        }
                    )
                ) {
                    Label(block.kind.title, systemImage: block.kind.systemImage)
                        .font(.subheadline.weight(.semibold))
                }

                HStack(spacing: 2) {
                    Button {
                        moveBlock(from: index, offset: -1)
                    } label: {
                        Image(systemName: "arrow.up")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    .accessibilityLabel("Move \(block.kind.title) earlier")

                    Button {
                        moveBlock(from: index, offset: 1)
                    } label: {
                        Image(systemName: "arrow.down")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == blocks.count - 1)
                    .accessibilityLabel("Move \(block.kind.title) later")
                }
            }

            if enabledBlockIDs.contains(block.id) {
                HStack {
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(block.durationSeconds / 60) min")
                        .font(.caption.monospacedDigit().weight(.semibold))
                    Stepper(
                        "",
                        value: Binding(
                            get: { blocks[index].durationSeconds / 60 },
                            set: { blocks[index].durationSeconds = max(1, $0) * 60 }
                        ),
                        in: 1...60,
                        step: 1
                    )
                    .labelsHidden()
                    .accessibilityLabel("\(block.kind.title) duration")
                    .accessibilityValue("\(block.durationSeconds / 60) minutes")
                }
            }
        }
        .padding(.vertical, StudioQuestTokens.Spacing.xs)
    }

    private var executeContent: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            if let state = runState {
                StudioQuestToolLivePanel(
                    eyebrow: state.phase == .paused ? "Paused" : "Now"
                ) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(state.currentBlock?.kind.title ?? "Ready to reflect")
                            .font(StudioQuestTokens.Typography.sectionTitle)
                        Spacer()
                        Text(DurationFormatter.string(from: state.currentBlockRemainingSeconds(at: now)))
                            .font(StudioQuestTokens.Typography.timer)
                            .monospacedDigit()
                    }

                    StudioQuestProgressVisualization(
                        progress: state.progress(at: now),
                        accessibilityLabel: "Guided practice progress"
                    )

                    HStack(spacing: StudioQuestTokens.Spacing.md) {
                        StudioQuestMetric(
                            title: "Elapsed",
                            value: DurationFormatter.string(from: state.totalElapsedSeconds(at: now))
                        )
                        StudioQuestMetric(
                            title: "Block",
                            value: "\(min(state.currentBlockIndex + 1, state.blocks.count)) / \(state.blocks.count)",
                            tint: StudioQuestTokens.ColorRole.violet
                        )
                    }

                    HStack(spacing: StudioQuestTokens.Spacing.sm) {
                        Button {
                            toggleExecution()
                        } label: {
                            Label(
                                state.phase == .running ? "Pause" : "Resume",
                                systemImage: state.phase == .running ? "pause.fill" : "play.fill"
                            )
                        }
                        .buttonStyle(StudioQuestSecondaryButtonStyle())
                        .accessibilityIdentifier("guided.pause")

                        Button {
                            skipBlock()
                        } label: {
                            Label("Next block", systemImage: "forward.end.fill")
                        }
                        .buttonStyle(StudioQuestPrimaryButtonStyle())
                        .accessibilityIdentifier("guided.next")
                    }
                }

                executionMap(state)
                contextualTools

                Button {
                    moveToReflection()
                } label: {
                    Label("Reflect now", systemImage: "text.bubble")
                }
                .buttonStyle(StudioQuestSecondaryButtonStyle())
                .disabled(!state.hasMeaningfulExecution)
                .accessibilityIdentifier("guided.reflect")
            }
        }
    }

    private func executionMap(_ state: GuidedPracticeRunState) -> some View {
        StudioQuestToolSetupPanel(title: "Session map") {
            ForEach(Array(state.blocks.enumerated()), id: \.element.id) { index, block in
                HStack(spacing: StudioQuestTokens.Spacing.sm) {
                    Image(
                        systemName: index < state.currentBlockIndex
                            ? "checkmark.circle.fill"
                            : (index == state.currentBlockIndex ? "circle.inset.filled" : "circle")
                    )
                    .foregroundStyle(
                        index <= state.currentBlockIndex
                            ? StudioQuestTokens.ColorRole.cobalt
                            : Color.secondary
                    )
                    Text(block.kind.title)
                        .font(.subheadline)
                    Spacer()
                    Text("\(block.durationSeconds / 60) min")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var contextualTools: some View {
        StudioQuestToolSetupPanel(title: "Practice tools") {
            Text("These tools share this session—no second timer starts.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: StudioQuestTokens.Spacing.sm) {
                Button {
                    requestAudio(.metronome)
                } label: {
                    Label(
                        coordinator.metronome.isRunning ? "Stop click" : "Metronome",
                        systemImage: "metronome"
                    )
                }
                .buttonStyle(StudioQuestSecondaryButtonStyle())

                Button {
                    requestAudio(.tuner)
                } label: {
                    Label(
                        coordinator.tuner.isListening ? "Stop tuner" : "Tuner",
                        systemImage: "tuningfork"
                    )
                }
                .buttonStyle(StudioQuestSecondaryButtonStyle())
            }

            NavigationLink {
                SmartLoopTimerView(nestedWithinPlan: true)
            } label: {
                HStack(spacing: StudioQuestTokens.Spacing.sm) {
                    Image(systemName: "repeat")
                        .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Loop")
                            .font(.subheadline.weight(.semibold))
                        Text("Add loop analytics to this plan")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var reflectionContent: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            StudioQuestToolResultPanel {
                Text("Turn the session into a useful next step.")
                    .font(StudioQuestTokens.Typography.sectionTitle)

                reflectionField(
                    title: "What improved?",
                    placeholder: "Name the clearest win",
                    text: $reflectionWins
                )
                reflectionField(
                    title: "What still needs work?",
                    placeholder: "Be specific and kind",
                    text: $reflectionFix
                )
                reflectionField(
                    title: "What comes next?",
                    placeholder: "Choose one concrete action",
                    text: $reflectionNext
                )

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
                saveReflection()
            } label: {
                Label(saveFailed ? "Try saving again" : "Save guided practice", systemImage: "checkmark")
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())
            .accessibilityIdentifier("guided.save")
        }
    }

    private func reflectionField(
        title: LocalizedStringKey,
        placeholder: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .padding(StudioQuestTokens.Spacing.sm)
                .background(
                    StudioQuestTokens.ColorRole.raisedSurface(colorScheme),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
    }

    private var doneContent: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            StudioQuestToolResultPanel {
                Label("Guided practice saved", systemImage: "checkmark.seal.fill")
                    .font(StudioQuestTokens.Typography.sectionTitle)
                    .foregroundStyle(StudioQuestTokens.ColorRole.mint)
                if let state = runState {
                    HStack(spacing: StudioQuestTokens.Spacing.md) {
                        StudioQuestMetric(
                            title: "Practiced",
                            value: DurationFormatter.string(from: state.totalElapsedSeconds(at: now))
                        )
                        StudioQuestMetric(
                            title: "Rating",
                            value: "\(selfRating) / 5",
                            tint: StudioQuestTokens.ColorRole.violet
                        )
                    }
                }
            }

            Button("Create another plan") {
                resetForNewPlan()
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())
            .accessibilityIdentifier("guided.done")
        }
    }

    private func toggleGoal(_ goal: GuidedPracticeGoal) {
        if selectedGoals.contains(goal) {
            guard selectedGoals.count > 2 else {
                showStatus("Choose at least two goals.", kind: .warning)
                return
            }
            selectedGoals.remove(goal)
        } else if selectedGoals.count < 4 {
            selectedGoals.insert(goal)
        } else {
            showStatus("Choose up to four goals.", kind: .warning)
        }
    }

    private func moveBlock(from index: Int, offset: Int) {
        let destination = index + offset
        guard blocks.indices.contains(index), blocks.indices.contains(destination) else { return }
        blocks.swapAt(index, destination)
    }

    private func beginExecution() {
        guard planIsValid else { return }
        if let active = coordinator.activeToolID, active != .planExecuteReflect {
            showStatus(
                "Finish or close \(active.title) before starting a guided plan.",
                kind: .warning
            )
            return
        }

        if coordinator.activeToolID != .planExecuteReflect {
            if coordinator.hasActivePractice {
                guard coordinator.attachTool(.planExecuteReflect) != nil else { return }
            } else {
                guard coordinator.beginFocusedTool(
                    .planExecuteReflect,
                    title: "Guided practice",
                    durationMinutes: targetMinutes,
                    source: .library
                ) else { return }
            }
        }

        var state = GuidedPracticeRunState(
            goals: Array(selectedGoals),
            blocks: selectedBlocks
        )
        _ = state.start()
        runState = state
        coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        if !coordinator.isRunning {
            coordinator.resume()
        }
        showStatus("Guided practice started.", kind: .information)
    }

    private func toggleExecution() {
        guard var state = runState else { return }
        if state.phase == .running {
            state.pause()
            runState = state
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            coordinator.pause()
            stopSharedAudio()
        } else if state.phase == .paused {
            _ = state.resume()
            runState = state
            coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            coordinator.resume()
        }
    }

    private func advanceExecution(to date: Date) {
        guard var state = runState, state.phase == .running else { return }
        let events = state.advance(to: date)
        runState = state
        guard !events.isEmpty else { return }
        coordinator.updateToolRecoveryPayload(recoveryJSON(state))
        if state.phase == .reflect {
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            coordinator.pause()
            stopSharedAudio()
        }
    }

    private func skipBlock() {
        guard var state = runState else { return }
        _ = state.skipCurrentBlock(at: .now)
        runState = state
        coordinator.updateToolRecoveryPayload(recoveryJSON(state))
        if state.phase == .reflect {
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            coordinator.pause()
            stopSharedAudio()
        }
    }

    private func moveToReflection() {
        guard var state = runState, state.hasMeaningfulExecution else {
            showStatus("Practice for at least 10 seconds before reflecting.", kind: .warning)
            return
        }
        state.moveToReflect()
        runState = state
        coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
        coordinator.pause()
        stopSharedAudio()
    }

    private func requestAudio(_ owner: PracticeAudioOwner) {
        if coordinator.audioSession.owner == owner {
            stopSharedAudio()
            return
        }
        if coordinator.audioSession.owner != nil {
            requestedAudioOwner = owner
            replaceAudioConfirmationPresented = true
        } else {
            Task { await toggleAudio(owner, replacing: false) }
        }
    }

    private func toggleAudio(
        _ owner: PracticeAudioOwner,
        replacing: Bool
    ) async {
        if replacing {
            stopSharedAudio()
        }
        do {
            try await coordinator.audioSession.claim(
                owner,
                requirements: owner == .tuner ? [.microphone] : [.playback]
            )
        } catch {
            showStatus("That audio tool is busy. Close it and try again.", kind: .warning)
            return
        }
        switch owner {
        case .metronome:
            coordinator.tuner.stopListening()
            coordinator.tuner.stopReferenceTone()
            coordinator.metronome.setBPM(80)
            coordinator.metronome.start(
                beatsPerBar: 4,
                subdivision: .none,
                soundStyle: .click
            )
        case .tuner:
            coordinator.metronome.stop()
            coordinator.tuner.startListening()
        default:
            coordinator.audioSession.release(owner)
        }
    }

    private func stopSharedAudio() {
        coordinator.metronome.stop()
        coordinator.tuner.stopListening()
        coordinator.tuner.stopReferenceTone()
        coordinator.audioSession.releaseCurrentOwner()
    }

    private func saveReflection() {
        guard let state = runState, state.hasMeaningfulExecution else {
            showStatus("Practice for at least 10 seconds before saving.", kind: .warning)
            return
        }

        let cleanWins = reflectionWins.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFix = reflectionFix.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNext = reflectionNext.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultPayload = GuidedPracticeResultPayload(
            completedAt: .now,
            targetMinutes: max(1, state.targetSeconds / 60),
            actualSeconds: state.totalElapsedSeconds(at: now),
            goals: state.goals,
            blocks: state.blocks,
            reflectionWins: cleanWins,
            reflectionFix: cleanFix,
            reflectionNext: cleanNext,
            selfRating: selfRating,
            parentSessionID: coordinator.toolLaunchContext?.parentSessionID,
            launchSource: coordinator.toolLaunchContext?.source ?? .legacy,
            toolVersion: 2
        )
        guard let data = try? JSONEncoder().encode(resultPayload),
              let json = String(data: data, encoding: .utf8) else {
            showStatus("The guided result could not be prepared. Please try again.", kind: .error)
            return
        }

        let result = PracticeToolResult(
            toolID: .planExecuteReflect,
            sessionID: coordinator.activeSessionID,
            durationSeconds: resultPayload.actualSeconds,
            metrics: [
                "blocks": Double(state.blocks.count),
                "rating": Double(selfRating),
                "targetMinutes": Double(resultPayload.targetMinutes)
            ],
            payloadJSON: json
        )

        if isContextual {
            coordinator.attachCompletedToolResult(result)
            coordinator.detachTool()
            didFinish = true
            saveFailed = false
            showStatus(
                "Guided reflection added to your active session.",
                kind: .success
            )
            return
        }

        coordinator.completeTool(result)
        let notes = [
            cleanWins.isEmpty ? nil : "### What improved\n\(cleanWins)",
            cleanFix.isEmpty ? nil : "### What needs work\n\(cleanFix)",
            cleanNext.isEmpty ? nil : "### Next action\n\(cleanNext)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")

        let didSave = store.savePracticeCompletion(
            PracticeSavePayload(
                sessionID: coordinator.activeSessionID,
                snapshot: coordinator.snapshot,
                notes: notes,
                noteTitle: "Guided Practice",
                noteFocus: state.goals.map(\.title).joined(separator: ", "),
                toolResult: result,
                attachedToolResults: coordinator.attachedToolResults
            )
        )

        if didSave {
            coordinator.completeAfterSave(savedSessionID: store.lastSavedSessionID)
            didFinish = true
            saveFailed = false
            showStatus("Guided practice saved.", kind: .success)
        } else {
            saveFailed = true
            showStatus(
                "The session could not be saved. Your reflection is still here—try again.",
                kind: .error
            )
        }
    }

    private func resetForNewPlan() {
        stopSharedAudio()
        selectedGoals = [.intonation, .rhythm]
        blocks = [
            GuidedPracticeBlock(kind: .warmUp, durationSeconds: 5 * 60),
            GuidedPracticeBlock(kind: .technique, durationSeconds: 10 * 60),
            GuidedPracticeBlock(kind: .repertoire, durationSeconds: 10 * 60),
            GuidedPracticeBlock(kind: .runThrough, durationSeconds: 5 * 60)
        ]
        enabledBlockIDs = Set(blocks.map(\.id))
        runState = nil
        reflectionWins = ""
        reflectionFix = ""
        reflectionNext = ""
        selfRating = 3
        saveFailed = false
        didFinish = false
        statusMessage = nil
    }

    private func restoreIfNeeded() {
        guard coordinator.activeToolID == .planExecuteReflect,
              let json = coordinator.toolActivityState?.recoveryPayloadJSON,
              let data = json.data(using: .utf8),
              let restored = try? JSONDecoder().decode(
                GuidedPracticeRunState.self,
                from: data
              ) else { return }
        runState = restored
        selectedGoals = Set(restored.goals)
        blocks = restored.blocks
        enabledBlockIDs = Set(restored.blocks.map(\.id))
        advanceExecution(to: .now)
        showStatus(
            restored.phase == .paused
                ? "Guided practice ready to resume."
                : "Guided practice restored.",
            kind: .information
        )
    }

    private func preserveOnExit() {
        guard !didFinish,
              coordinator.activeToolID == .planExecuteReflect,
              var state = runState else { return }
        if state.phase == .running {
            state.pause()
            runState = state
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(state))
            coordinator.pause()
        } else {
            coordinator.updateToolRecoveryPayload(recoveryJSON(state))
        }
        stopSharedAudio()
    }

    private func persistRecovery() {
        guard let state = runState else { return }
        coordinator.updateToolRecoveryPayload(recoveryJSON(state))
    }

    private func recoveryJSON(_ state: GuidedPracticeRunState) -> String? {
        guard let data = try? JSONEncoder().encode(state) else { return nil }
        return String(data: data, encoding: .utf8)
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

        blocks = [
            GuidedPracticeBlock(kind: .warmUp, durationSeconds: 15),
            GuidedPracticeBlock(kind: .technique, durationSeconds: 15)
        ]
        enabledBlockIDs = Set(blocks.map(\.id))
        if coordinator.activeToolID == nil {
            _ = coordinator.beginFocusedTool(
                .planExecuteReflect,
                title: "Guided practice",
                durationMinutes: 1,
                source: .qa
            )
        }
        var fixture = GuidedPracticeRunState(
            goals: [.intonation, .rhythm],
            blocks: blocks
        )
        _ = fixture.start(at: .now.addingTimeInterval(-12))

        switch qaToolState {
        case .running:
            break
        case .paused, .recovered:
            fixture.pause()
        case .completed, .saveError:
            fixture.moveToReflect()
            reflectionWins = "The opening stayed centered."
            reflectionNext = "Repeat at 76 BPM."
        case .permissionDenied:
            showStatus("No audio permission is needed for a guided plan.", kind: .information)
        case .setup:
            break
        }

        runState = fixture
        if fixture.phase == .running {
            coordinator.startToolActivity(recoveryPayloadJSON: recoveryJSON(fixture))
        } else {
            coordinator.pauseToolActivity(recoveryPayloadJSON: recoveryJSON(fixture))
            coordinator.pause()
        }
        if qaToolState == .saveError {
            saveFailed = true
            showStatus(
                "The session could not be saved. Your reflection is still here—try again.",
                kind: .error
            )
        } else if qaToolState == .recovered {
            showStatus("Guided practice ready to resume.", kind: .information)
        }
    }
    #else
    private func applyQAStateIfNeeded() {}
    #endif
}
