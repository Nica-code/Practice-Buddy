import SwiftUI
import SwiftData
import Combine

struct SmartLoopTimerView: View {
    private enum Phase: String {
        case idle
        case work
        case rest
        case pausedWork
        case pausedRest
        case finished
    }

    private enum LoopTag: String, CaseIterable, Identifiable {
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
    }

    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var assignmentLinkManager: AssignmentLinkManager
    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0

    @AppStorage("pb.loop.duration") private var loopDuration: Int = 45
    @AppStorage("pb.loop.rest") private var restDuration: Int = 20
    @AppStorage("pb.loop.targetLoops") private var targetLoops: Int = 8
    @AppStorage("pb.loop.untilStop") private var untilStop: Bool = false
    @AppStorage("pb.loop.metroEnabled") private var metronomeEnabled: Bool = true
    @AppStorage("pb.loop.metroStartBPM") private var tempoStartBPM: Int = 72
    @AppStorage("pb.loop.metroAutoEnabled") private var autoIncreaseEnabled: Bool = false
    @AppStorage("pb.loop.metroAutoEvery") private var autoIncreaseEvery: Int = 2
    @AppStorage("pb.loop.metroAutoBy") private var autoIncreaseBy: Int = 2
    @AppStorage("pb.loop.tempoLadderEnabled") private var tempoLadderEnabled: Bool = false
    @AppStorage("pb.loop.tempoLadderCleanLoops") private var tempoLadderCleanLoops: Int = 3
    @AppStorage("pb.loop.presets.json") private var presetsRaw: String = ""

    @State private var selectedTags: Set<String> = []
    @State private var phase: Phase = .idle
    @State private var remainingSeconds: Int = 0
    @State private var loopsCompleted: Int = 0
    @State private var totalWorkSeconds: Int = 0
    @State private var currentTempoBPM: Int = 72
    @State private var runFinishedAt: Date?
    @State private var showSavedPresetSheet: Bool = false
    @State private var newPresetName: String = ""
    @State private var statusMessage: String?
    @State private var saveToSessionHistory: Bool = true
    @State private var markLinkedAssignmentComplete: Bool = true
    @State private var linkedAssignmentNote: String = ""
    @State private var cleanLoopsAtCurrentTempo: Int = 0
    @State private var timerCancellable: AnyCancellable?
    @StateObject private var metronome = MetronomeEngine()

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var hasResult: Bool { phase == .finished && loopsCompleted > 0 }
    private var targetLoopValue: Int { max(1, targetLoops) }

    private var decodedPresets: [LoopPreset] {
        guard let data = presetsRaw.data(using: .utf8),
              let presets = try? JSONDecoder().decode([LoopPreset].self, from: data) else {
            return []
        }
        return presets
    }

    var body: some View {
        Form {
            Section("Loop Setup") {
                Stepper(L10n.f("Loop duration: %@ sec", "\(loopDuration)"), value: $loopDuration, in: 10...600, step: 5)
                    .font(type.body)
                Stepper(L10n.f("Rest: %@ sec", "\(restDuration)"), value: $restDuration, in: 0...180, step: 5)
                    .font(type.body)

                Toggle("Run until stop", isOn: $untilStop)
                    .font(type.body)
                if !untilStop {
                    Stepper(L10n.f("Target loops: %@", "\(targetLoopValue)"), value: $targetLoops, in: 1...200)
                        .font(type.body)
                }
            }
            .listRowBackground(palette.surface)

            Section("Metronome Integration") {
                Toggle("Use metronome during work", isOn: $metronomeEnabled)
                    .font(type.body)

                if metronomeEnabled {
                    Stepper(L10n.f("Start tempo: %@ BPM", "\(tempoStartBPM)"), value: $tempoStartBPM, in: 40...220)
                        .font(type.body)

                    Toggle("Auto increase tempo", isOn: $autoIncreaseEnabled)
                        .font(type.body)

                    if autoIncreaseEnabled {
                        Stepper(L10n.f("Every %@ loop(s)", "\(autoIncreaseEvery)"), value: $autoIncreaseEvery, in: 1...20)
                            .font(type.body)
                        Stepper(L10n.f("Increase by %@ BPM", "\(autoIncreaseBy)"), value: $autoIncreaseBy, in: 1...10)
                            .font(type.body)
                    }

                    Toggle("Tempo Ladder (clean loops)", isOn: $tempoLadderEnabled)
                        .font(type.body)
                    if tempoLadderEnabled {
                        Stepper(L10n.f("Clean loops to climb: %@", "\(tempoLadderCleanLoops)"), value: $tempoLadderCleanLoops, in: 1...10)
                            .font(type.body)
                        Text(L10n.f("Tap “Mark Loop Clean” during run-through. Tempo increases after %@ clean loops.", "\(tempoLadderCleanLoops)"))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .listRowBackground(palette.surface)

            Section("Quick Tags") {
                FlowRow(spacing: 8) {
                    ForEach(LoopTag.allCases) { tag in
                        tagChip(tag)
                    }
                }
            }
            .listRowBackground(palette.surface)

            Section("Presets") {
                if purchaseManager.isPro {
                    Button("Save Current As Preset") {
                        newPresetName = ""
                        showSavedPresetSheet = true
                    }
                    .font(type.button)

                    if decodedPresets.isEmpty {
                        Text("No saved presets yet.")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        ForEach(decodedPresets) { preset in
                            Button {
                                applyPreset(preset)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .font(type.body)
                                        .foregroundStyle(palette.textPrimary)
                                    Text(L10n.f("%@s loop • %@s rest • %@ loops", "\(preset.loopDuration)", "\(preset.restDuration)", "\(preset.targetLoops)"))
                                        .font(type.footnote)
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Text("Saving/loading loop presets is part of Practice Buddy Pro.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Button("Unlock Pro") { selectedTab = 4 }
                        .font(type.button)
                        .buttonStyle(.borderedProminent)
                }
            }
            .listRowBackground(palette.surface)

            Section("Run") {
                HStack {
                    Text("Phase")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(LocalizedStringKey(phaseTitle))
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Remaining")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(DurationFormatter.string(from: max(0, remainingSeconds)))
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Loops completed")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(loopsCompleted)")
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Work time")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(DurationFormatter.string(from: totalWorkSeconds))
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                if metronomeEnabled {
                    HStack {
                        Text("Current tempo")
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(L10n.f("%@ BPM", "\(currentTempoBPM)"))
                            .font(type.number)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }
                    if tempoLadderEnabled {
                        HStack {
                            Text("Clean loops")
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(L10n.f("%@/%@", "\(cleanLoopsAtCurrentTempo)", "\(tempoLadderCleanLoops)"))
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button(String(localized: String.LocalizationValue(primaryActionTitle))) {
                        primaryAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .font(type.button)

                    Button("Stop") {
                        stopRun()
                    }
                    .buttonStyle(.bordered)
                    .font(type.button)
                    .disabled(phase == .idle)
                }

                if phase == .work && metronomeEnabled && tempoLadderEnabled {
                    Button("Mark Loop Clean") {
                        markCleanLoop()
                    }
                    .buttonStyle(.bordered)
                    .font(type.button)
                }
            }
            .listRowBackground(palette.surface)

            if hasResult {
                Section("Summary") {
                    Text(summaryText)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)

                    Toggle("Also save into session history", isOn: $saveToSessionHistory)
                        .font(type.body)

                    if let linked = assignmentLinkManager.linkedAssignment {
                        Divider().padding(.vertical, 4)
                        Text(L10n.f("Linked assignment: %@", linked.title))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        Toggle("Mark linked assignment complete", isOn: $markLinkedAssignmentComplete)
                            .font(type.body)
                        TextField("Assignment note (optional)", text: $linkedAssignmentNote, axis: .vertical)
                            .font(type.body)
                            .lineLimit(2...5)
                    }

                    Button("Save Loop Log") {
                        saveResult()
                    }
                    .font(type.button)
                    .buttonStyle(.borderedProminent)
                }
                .listRowBackground(palette.surface)
            }

            if let statusMessage, !statusMessage.isEmpty {
                Section {
                    Text(LocalizedStringKey(statusMessage))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            currentTempoBPM = tempoStartBPM
            sanitizeInputs()
        }
        .onDisappear {
            stopTicker()
            metronome.stop()
        }
        .sheet(isPresented: $showSavedPresetSheet) {
            NavigationStack {
                Form {
                    Section("Preset Name") {
                        TextField("Example: Shift Ladder", text: $newPresetName)
                    }
                }
                .navigationTitle("Save Preset")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSavedPresetSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            savePreset()
                            showSavedPresetSheet = false
                        }
                        .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tagChip(_ tag: LoopTag) -> some View {
        let isSelected = selectedTags.contains(tag.rawValue)
        Button {
            if isSelected {
                selectedTags.remove(tag.rawValue)
            } else {
                selectedTags.insert(tag.rawValue)
            }
        } label: {
            Text(LocalizedStringKey(tag.title))
                .font(type.footnote)
                .foregroundStyle(isSelected ? palette.accent : palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background((isSelected ? palette.accent.opacity(0.18) : palette.surfaceAlt))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var phaseTitle: String {
        switch phase {
        case .idle: return "Ready"
        case .work: return "Work"
        case .rest: return "Rest"
        case .pausedWork, .pausedRest: return "Paused"
        case .finished: return "Finished"
        }
    }

    private var primaryActionTitle: String {
        switch phase {
        case .idle, .finished:
            return "Start"
        case .work, .rest:
            return "Pause"
        case .pausedWork, .pausedRest:
            return "Resume"
        }
    }

    private var summaryText: String {
        let tags = selectedTags.sorted().joined(separator: ", ")
        let tempo = metronomeEnabled ? L10n.f("%@→%@ BPM", "\(tempoStartBPM)", "\(currentTempoBPM)") : String(localized: "Metronome off")
        let ladder = tempoLadderEnabled ? L10n.f("Tempo ladder on (%@ clean loops)", "\(tempoLadderCleanLoops)") : String(localized: "Tempo ladder off")
        return L10n.f(
            "Loops: %@, Work: %@, Tempo: %@, %@, Tags: %@",
            "\(loopsCompleted)",
            DurationFormatter.string(from: totalWorkSeconds),
            tempo,
            ladder,
            tags.isEmpty ? String(localized: "none") : tags
        )
    }

    private func primaryAction() {
        switch phase {
        case .idle, .finished:
            startRun()
        case .work, .rest:
            pauseRun()
        case .pausedWork, .pausedRest:
            resumeRun()
        }
    }

    private func sanitizeInputs() {
        loopDuration = min(max(loopDuration, 10), 600)
        restDuration = min(max(restDuration, 0), 180)
        targetLoops = min(max(targetLoops, 1), 200)
        tempoStartBPM = min(max(tempoStartBPM, 40), 220)
        autoIncreaseEvery = min(max(autoIncreaseEvery, 1), 20)
        autoIncreaseBy = min(max(autoIncreaseBy, 1), 10)
        tempoLadderCleanLoops = min(max(tempoLadderCleanLoops, 1), 10)
    }

    private func startRun() {
        sanitizeInputs()
        statusMessage = nil
        loopsCompleted = 0
        totalWorkSeconds = 0
        runFinishedAt = nil
        currentTempoBPM = tempoStartBPM
        cleanLoopsAtCurrentTempo = 0
        startWorkPhase()
    }

    private func startWorkPhase() {
        phase = .work
        remainingSeconds = loopDuration
        if metronomeEnabled {
            metronome.setBPM(currentTempoBPM)
            metronome.start(beatsPerBar: 4, subdivision: .none, soundStyle: .click)
        }
        startTicker()
    }

    private func startRestPhase() {
        metronome.stop()
        if restDuration == 0 {
            startWorkPhase()
            return
        }
        phase = .rest
        remainingSeconds = restDuration
        startTicker()
    }

    private func pauseRun() {
        stopTicker()
        metronome.stop()
        if phase == .work {
            phase = .pausedWork
        } else if phase == .rest {
            phase = .pausedRest
        }
    }

    private func resumeRun() {
        if phase == .pausedWork {
            phase = .work
            if metronomeEnabled {
                metronome.setBPM(currentTempoBPM)
                metronome.start(beatsPerBar: 4, subdivision: .none, soundStyle: .click)
            }
            startTicker()
        } else if phase == .pausedRest {
            phase = .rest
            startTicker()
        }
    }

    private func stopRun() {
        stopTicker()
        metronome.stop()
        if loopsCompleted > 0 || totalWorkSeconds > 0 {
            phase = .finished
            runFinishedAt = Date()
        } else {
            phase = .idle
        }
    }

    private func startTicker() {
        stopTicker()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                tick()
            }
    }

    private func stopTicker() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func tick() {
        switch phase {
        case .work:
            totalWorkSeconds += 1
            remainingSeconds -= 1
            if remainingSeconds <= 0 {
                loopsCompleted += 1
                if !tempoLadderEnabled && autoIncreaseEnabled && metronomeEnabled && loopsCompleted > 0 && loopsCompleted % autoIncreaseEvery == 0 {
                    currentTempoBPM = min(220, currentTempoBPM + autoIncreaseBy)
                }
                if !untilStop && loopsCompleted >= targetLoopValue {
                    stopRun()
                } else {
                    startRestPhase()
                }
            }
        case .rest:
            remainingSeconds -= 1
            if remainingSeconds <= 0 {
                startWorkPhase()
            }
        default:
            break
        }
    }

    private func saveResult() {
        guard hasResult else { return }
        let tags = selectedTags.sorted().joined(separator: ",")
        let log = LoopPracticeLogModel(
            date: runFinishedAt ?? Date(),
            loopsCompleted: loopsCompleted,
            totalWorkSeconds: totalWorkSeconds,
            loopDurationSeconds: loopDuration,
            restSeconds: restDuration,
            tempoStartBPM: metronomeEnabled ? tempoStartBPM : 0,
            tempoEndBPM: metronomeEnabled ? currentTempoBPM : 0,
            targetLoops: untilStop ? 0 : targetLoopValue,
            tagsRaw: tags,
            tempoLadderEnabled: tempoLadderEnabled,
            ladderCleanLoopsRequired: tempoLadderEnabled ? tempoLadderCleanLoops : 0
        )
        modelContext.insert(log)
        try? modelContext.save()

        if saveToSessionHistory {
            let tagText = selectedTags.sorted().joined(separator: ", ")
            let notes = """
            Loop Session
            Loops completed: \(loopsCompleted)
            Work time: \(DurationFormatter.string(from: totalWorkSeconds))
            Tempo: \(metronomeEnabled ? "\(tempoStartBPM)→\(currentTempoBPM) BPM" : "Metronome off")
            Tags: \(tagText.isEmpty ? "none" : tagText)
            """
            store.addSession(
                date: runFinishedAt ?? Date(),
                durationSeconds: totalWorkSeconds,
                notes: notes,
                noteTitle: "Loop Session",
                noteFocus: tagText
            )
        }

        if assignmentLinkManager.linkedAssignment != nil {
            let trimmed = linkedAssignmentNote.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = trimmed.isEmpty ? summaryText : trimmed
            Task {
                await assignmentLinkManager.submitLinkedPracticeResult(
                    tool: "smart_loop",
                    note: note,
                    attachmentPath: nil,
                    markComplete: markLinkedAssignmentComplete
                )
            }
        }

        statusMessage = "Loop log saved."
        phase = .idle
    }

    private func markCleanLoop() {
        guard tempoLadderEnabled, metronomeEnabled, phase == .work else { return }
        cleanLoopsAtCurrentTempo += 1
        if cleanLoopsAtCurrentTempo >= tempoLadderCleanLoops {
            cleanLoopsAtCurrentTempo = 0
            currentTempoBPM = min(220, currentTempoBPM + max(1, autoIncreaseBy))
            metronome.setBPM(currentTempoBPM)
            metronome.applyUpdatedConfiguration(
                beatsPerBar: 4,
                subdivision: .none,
                soundStyle: .click
            )
            statusMessage = L10n.f("Tempo ladder advanced to %@ BPM.", "\(currentTempoBPM)")
        }
    }

    private func savePreset() {
        guard purchaseManager.isPro else { return }
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        var presets = decodedPresets
        let preset = LoopPreset(
            id: UUID(),
            name: name,
            loopDuration: loopDuration,
            restDuration: restDuration,
            targetLoops: targetLoopValue,
            metronomeEnabled: metronomeEnabled,
            tempoStart: tempoStartBPM,
            autoIncreaseEnabled: autoIncreaseEnabled,
            autoIncreaseEvery: autoIncreaseEvery,
            autoIncreaseBy: autoIncreaseBy,
            tempoLadderEnabled: tempoLadderEnabled,
            tempoLadderCleanLoops: tempoLadderCleanLoops,
            tags: selectedTags.sorted()
        )
        presets.insert(preset, at: 0)
        if presets.count > 30 {
            presets = Array(presets.prefix(30))
        }
        if let data = try? JSONEncoder().encode(presets),
           let raw = String(data: data, encoding: .utf8) {
            presetsRaw = raw
            statusMessage = "Preset saved."
        }
    }

    private func applyPreset(_ preset: LoopPreset) {
        loopDuration = preset.loopDuration
        restDuration = preset.restDuration
        targetLoops = max(1, preset.targetLoops)
        untilStop = false
        metronomeEnabled = preset.metronomeEnabled
        tempoStartBPM = preset.tempoStart
        autoIncreaseEnabled = preset.autoIncreaseEnabled
        autoIncreaseEvery = preset.autoIncreaseEvery
        autoIncreaseBy = preset.autoIncreaseBy
        tempoLadderEnabled = preset.tempoLadderEnabled ?? false
        tempoLadderCleanLoops = preset.tempoLadderCleanLoops ?? 3
        selectedTags = Set(preset.tags)
        statusMessage = "Preset loaded."
    }
}

private struct FlowRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
    }
}
