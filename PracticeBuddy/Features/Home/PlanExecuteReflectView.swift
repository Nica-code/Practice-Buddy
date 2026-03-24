import SwiftUI
import SwiftData
import Combine
import FirebaseFirestore

struct PlanExecuteReflectView: View {
    private enum Stage {
        case plan
        case execute
        case reflect
        case done
    }

    private enum Goal: String, CaseIterable, Identifiable {
        case intonation
        case rhythm
        case memory
        case bowControl
        case shifts
        case tone

        var id: String { rawValue }

        var title: String {
            switch self {
            case .intonation: return "Intonation"
            case .rhythm: return "Rhythm"
            case .memory: return "Memory"
            case .bowControl: return "Bow Control"
            case .shifts: return "Shifts"
            case .tone: return "Tone"
            }
        }
    }

    private enum Block: String, CaseIterable, Identifiable {
        case warmup
        case technique
        case repertoire
        case runThrough

        var id: String { rawValue }

        var title: String {
            switch self {
            case .warmup: return "Warm-up"
            case .technique: return "Technique"
            case .repertoire: return "Repertoire"
            case .runThrough: return "Run-through"
            }
        }
    }

    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var assignmentLinkManager: AssignmentLinkManager
    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0

    @StateObject private var templateBridge = StudioPlanTemplateBridge()
    @State private var stage: Stage = .plan
    @State private var targetMinutes: Int = 30
    @State private var selectedGoals: Set<String> = [Goal.intonation.rawValue, Goal.rhythm.rawValue]
    @State private var selectedBlocks: Set<String> = Set(Block.allCases.map(\.rawValue))

    @State private var blockOrder: [Block] = []
    @State private var blockDurations: [Block: Int] = [:]
    @State private var blockIndex: Int = 0
    @State private var blockRemainingSeconds: Int = 0
    @State private var totalElapsedSeconds: Int = 0
    @State private var isRunning: Bool = false
    @State private var timerCancellable: AnyCancellable?

    @State private var reflectionWins: String = ""
    @State private var reflectionFix: String = ""
    @State private var reflectionNext: String = ""
    @State private var selfRating: Int = 3
    @State private var saveToSessionHistory: Bool = true
    @State private var markLinkedAssignmentComplete: Bool = true
    @State private var linkedAssignmentNote: String = ""
    @State private var showSaveTemplateSheet: Bool = false
    @State private var templateNameInput: String = ""
    @State private var statusMessage: String?

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var currentBlock: Block? { blockOrder.indices.contains(blockIndex) ? blockOrder[blockIndex] : nil }

    var body: some View {
        Form {
            switch stage {
            case .plan:
                planSection
            case .execute:
                executeSection
            case .reflect:
                reflectSection
            case .done:
                doneSection
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
            templateBridge.start(
                uid: firebase.currentUserID,
                accountType: purchaseManager.accountType,
                isPro: purchaseManager.featuresUnlocked
            )
        }
        .onChange(of: firebase.currentUserID) { _, newUID in
            templateBridge.start(
                uid: newUID,
                accountType: purchaseManager.accountType,
                isPro: purchaseManager.featuresUnlocked
            )
        }
        .onChange(of: purchaseManager.accountType) { _, newType in
            templateBridge.start(
                uid: firebase.currentUserID,
                accountType: newType,
                isPro: purchaseManager.featuresUnlocked
            )
        }
        .onChange(of: purchaseManager.featuresUnlocked) { _, isPro in
            templateBridge.start(
                uid: firebase.currentUserID,
                accountType: purchaseManager.accountType,
                isPro: isPro
            )
        }
        .onDisappear {
            stopTimer()
            templateBridge.stop()
        }
        .sheet(isPresented: $showSaveTemplateSheet) {
            NavigationStack {
                Form {
                    Section("Template Name") {
                        TextField("Example: Scale + Repertoire", text: $templateNameInput)
                    }
                }
                .navigationTitle("Save Studio Template")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSaveTemplateSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                await saveTemplateToStudio()
                                showSaveTemplateSheet = false
                            }
                        }
                        .disabled(templateNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private var planSection: some View {
        Group {
            Section("Plan") {
                Stepper(L10n.f("Target time: %@ min", "\(targetMinutes)"), value: $targetMinutes, in: 10...180, step: 5)
                    .font(type.body)

                Text("Choose 2-4 goals")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Goal.allCases) { goal in
                        PlanExecuteReflectChipView(
                            title: goal.title,
                            isSelected: selectedGoals.contains(goal.rawValue),
                            palette: palette,
                            type: type
                        ) {
                            if selectedGoals.contains(goal.rawValue) {
                                selectedGoals.remove(goal.rawValue)
                            } else if selectedGoals.count < 4 {
                                selectedGoals.insert(goal.rawValue)
                            }
                        }
                    }
                }

                Text("Structure")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)

                ForEach(Block.allCases) { block in
                    Toggle(LocalizedStringKey(block.title), isOn: Binding(
                        get: { selectedBlocks.contains(block.rawValue) },
                        set: { enabled in
                            if enabled {
                                selectedBlocks.insert(block.rawValue)
                            } else {
                                selectedBlocks.remove(block.rawValue)
                            }
                        }
                    ))
                    .font(type.body)
                }
            }
            .listRowBackground(palette.surface)

            if purchaseManager.featuresUnlocked, purchaseManager.accountType == .teacher {
                Section("Teacher Tools") {
                    Button("Save As Studio Template") {
                        templateNameInput = ""
                        showSaveTemplateSheet = true
                    }
                    .font(type.button)
                    .buttonStyle(.bordered)
                }
                .listRowBackground(palette.surface)
            }

            if purchaseManager.featuresUnlocked, purchaseManager.accountType == .student {
                Section("Studio Templates") {
                    if templateBridge.templates.isEmpty {
                        Text("No studio templates yet.")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    } else {
                        ForEach(templateBridge.templates) { template in
                            Button {
                                applyStudioTemplate(template)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.title)
                                        .font(type.body)
                                        .foregroundStyle(palette.textPrimary)
                                    Text(
                                        L10n.f(
                                            "%@ min • %@",
                                            "\(template.targetMinutes)",
                                            template.goals.map { String(localized: String.LocalizationValue($0.capitalized)) }.joined(separator: ", ")
                                        )
                                    )
                                        .font(type.footnote)
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowBackground(palette.surface)
            }

            Section {
                Button("Start Execute") {
                    beginExecute()
                }
                .buttonStyle(.borderedProminent)
                .font(type.button)
                .disabled(!planIsValid)
            }
            .listRowBackground(palette.surface)
        }
    }

    private var executeSection: some View {
        Section("Execute") {
            HStack {
                Text("Current block")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(LocalizedStringKey(currentBlock?.title ?? "Done"))
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("Remaining")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(DurationFormatter.string(from: blockRemainingSeconds))
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("Elapsed")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(DurationFormatter.string(from: totalElapsedSeconds))
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Button(isRunning ? "Pause" : "Start") {
                    isRunning ? pauseExecute() : startExecute()
                }
                .buttonStyle(.borderedProminent)
                .font(type.button)

                Button("Next Block") {
                    skipToNextBlock()
                }
                .buttonStyle(.bordered)
                .font(type.button)
                .disabled(currentBlock == nil)
            }

            Divider().padding(.vertical, 6)

            Text("Launch tools")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

            NavigationLink {
                PBLazyView(PracticeToolsQuickPanelView())
            } label: {
                Label("Metronome + Tuner", systemImage: "metronome")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
            }

            NavigationLink {
                PBLazyView(SmartLoopTimerView())
            } label: {
                Label("Smart Loop Timer", systemImage: "repeat")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
            }

            NavigationLink {
                PBLazyView(RunThroughModeView())
            } label: {
                Label("Run-through Mode", systemImage: "record.circle")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
            }

            Button("Move To Reflect") {
                moveToReflect()
            }
            .buttonStyle(.bordered)
            .font(type.button)
        }
        .listRowBackground(palette.surface)
    }

    private var reflectSection: some View {
        Group {
            Section("Reflect") {
                TextField("What improved today?", text: $reflectionWins, axis: .vertical)
                    .lineLimit(2...5)
                    .font(type.body)
                TextField("What still needs work?", text: $reflectionFix, axis: .vertical)
                    .lineLimit(2...5)
                    .font(type.body)
                TextField("What is your next action?", text: $reflectionNext, axis: .vertical)
                    .lineLimit(2...5)
                    .font(type.body)

                Stepper(L10n.f("Self rating: %@/5", "\(selfRating)"), value: $selfRating, in: 1...5)
                    .font(type.body)
            }
            .listRowBackground(palette.surface)

            Section("Save") {
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
                        .lineLimit(2...5)
                        .font(type.body)
                }

                Button("Save Reflection") {
                    saveReflection()
                }
                .buttonStyle(.borderedProminent)
                .font(type.button)
            }
            .listRowBackground(palette.surface)
        }
    }

    private var doneSection: some View {
        Section {
            Text("Plan saved.")
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            Button("Start New Plan") {
                resetForNewPlan()
            }
            .buttonStyle(.borderedProminent)
            .font(type.button)
        }
        .listRowBackground(palette.surface)
    }

    private var planIsValid: Bool {
        selectedGoals.count >= 2 && selectedGoals.count <= 4 && !selectedBlocks.isEmpty
    }

    private func beginExecute() {
        let blocks = Block.allCases.filter { selectedBlocks.contains($0.rawValue) }
        guard !blocks.isEmpty else { return }
        blockOrder = blocks
        blockDurations = allocateDurations(totalMinutes: targetMinutes, blocks: blocks)
        blockIndex = 0
        blockRemainingSeconds = blockDurations[blocks[0]] ?? 0
        totalElapsedSeconds = 0
        isRunning = false
        stage = .execute
        statusMessage = nil
    }

    private func allocateDurations(totalMinutes: Int, blocks: [Block]) -> [Block: Int] {
        guard !blocks.isEmpty else { return [:] }
        let totalSeconds = max(1, totalMinutes) * 60
        let base = totalSeconds / blocks.count
        var remainder = totalSeconds % blocks.count
        var output: [Block: Int] = [:]
        for block in blocks {
            let extra = remainder > 0 ? 1 : 0
            output[block] = base + extra
            remainder = max(0, remainder - 1)
        }
        return output
    }

    private func startExecute() {
        guard currentBlock != nil else { return }
        stopTimer()
        isRunning = true
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                tickExecute()
            }
    }

    private func pauseExecute() {
        isRunning = false
        stopTimer()
    }

    private func tickExecute() {
        guard isRunning else { return }
        totalElapsedSeconds += 1
        blockRemainingSeconds -= 1
        if blockRemainingSeconds <= 0 {
            skipToNextBlock()
        }
    }

    private func skipToNextBlock() {
        guard currentBlock != nil else { return }
        if blockIndex + 1 >= blockOrder.count {
            moveToReflect()
            return
        }
        blockIndex += 1
        if let next = currentBlock {
            blockRemainingSeconds = blockDurations[next] ?? 0
        }
    }

    private func moveToReflect() {
        pauseExecute()
        stage = .reflect
    }

    private func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func saveReflection() {
        let goalsText = selectedGoals.sorted().joined(separator: ",")
        let blocksText = blockOrder.map(\.rawValue).joined(separator: ",")

        let log = PracticePlanLogModel(
            targetMinutes: targetMinutes,
            actualSeconds: totalElapsedSeconds,
            goalsRaw: goalsText,
            blocksRaw: blocksText,
            reflectionWins: reflectionWins.trimmingCharacters(in: .whitespacesAndNewlines),
            reflectionFix: reflectionFix.trimmingCharacters(in: .whitespacesAndNewlines),
            reflectionNext: reflectionNext.trimmingCharacters(in: .whitespacesAndNewlines),
            selfRating: selfRating
        )
        modelContext.insert(log)
        try? modelContext.save()

        if saveToSessionHistory {
            let notes = """
            Guided Practice
            Goals: \(selectedGoals.sorted().joined(separator: ", "))
            Blocks: \(blockOrder.map(\.title).joined(separator: " → "))
            Rating: \(selfRating)/5

            Improved:
            \(reflectionWins)

            Needs work:
            \(reflectionFix)

            Next action:
            \(reflectionNext)
            """
            store.addSession(
                date: Date(),
                durationSeconds: max(1, totalElapsedSeconds),
                notes: notes,
                noteTitle: "Guided Practice",
                noteFocus: selectedGoals.sorted().joined(separator: ", ")
            )
        }

        if assignmentLinkManager.linkedAssignment != nil {
            let note = linkedAssignmentNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Guided practice saved. Rating \(selfRating)/5."
                : linkedAssignmentNote.trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                await assignmentLinkManager.submitLinkedPracticeResult(
                    tool: "plan_execute_reflect",
                    note: note,
                    attachmentPath: nil,
                    markComplete: markLinkedAssignmentComplete
                )
            }
        }

        stage = .done
        statusMessage = "Guided practice saved."
    }

    private func resetForNewPlan() {
        stage = .plan
        selectedGoals = [Goal.intonation.rawValue, Goal.rhythm.rawValue]
        selectedBlocks = Set(Block.allCases.map(\.rawValue))
        targetMinutes = 30
        reflectionWins = ""
        reflectionFix = ""
        reflectionNext = ""
        selfRating = 3
        totalElapsedSeconds = 0
        blockOrder = []
        blockDurations = [:]
        blockIndex = 0
        blockRemainingSeconds = 0
        isRunning = false
        statusMessage = nil
    }

    private func saveTemplateToStudio() async {
        guard purchaseManager.featuresUnlocked, purchaseManager.accountType == .teacher else { return }
        let title = templateNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let goals = selectedGoals.sorted()
        let blocks = Block.allCases
            .filter { selectedBlocks.contains($0.rawValue) }
            .map(\.rawValue)
        await templateBridge.saveTemplate(
            title: title,
            targetMinutes: targetMinutes,
            goals: goals,
            blocks: blocks
        )
        if let msg = templateBridge.statusMessage {
            statusMessage = msg
        }
    }

    private func applyStudioTemplate(_ template: StudioPlanTemplate) {
        targetMinutes = template.targetMinutes
        selectedGoals = Set(template.goals)
        selectedBlocks = Set(template.blocks)
        statusMessage = "Template applied."
    }

}

private struct PracticeToolsQuickPanelView: View {
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var metronome = MetronomeEngine()
    @StateObject private var tuner = TunerEngine()
    @State private var bpm: Int = 80
    @State private var referenceHz: Int = 440

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        Form {
            Section("Metronome") {
                Stepper(L10n.f("Tempo: %@ BPM", "\(bpm)"), value: $bpm, in: 40...220)
                    .font(type.body)
                HStack(spacing: 10) {
                    Button("Start") {
                        metronome.setBPM(bpm)
                        metronome.start(beatsPerBar: 4, subdivision: .none, soundStyle: (MetronomeEngine.SoundStyle(rawValue: JourneyProgressManager.preferredMetronomeSoundStyleRaw() ?? "click") ?? .click))
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Stop") {
                        metronome.stop()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .listRowBackground(palette.surface)

            Section("Tuner") {
                Picker("Reference", selection: $referenceHz) {
                    Text("A=440").tag(440)
                    Text("A=442").tag(442)
                    Text("A=415").tag(415)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Button(tuner.isReferenceTonePlaying ? "Stop A Tone" : "Play A Tone") {
                        tuner.toggleReferenceTone(frequency: Double(referenceHz))
                    }
                    .buttonStyle(.bordered)

                    Button(tuner.isListening ? "Stop Tuner" : "Start Tuner") {
                        tuner.toggleListening()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .listRowBackground(palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            metronome.stop()
            tuner.stopListening()
            tuner.stopReferenceTone()
        }
    }
}

@MainActor
private final class StudioPlanTemplateBridge: ObservableObject {
    @Published private(set) var templates: [StudioPlanTemplate] = []
    @Published private(set) var statusMessage: String?

    private let repository = FirebaseStudiosRepository()
    private var userListener: ListenerRegistration?
    private var templatesListener: ListenerRegistration?
    private var uid: String?
    private var studioID: String?
    private var accountType: PBAccountType = .student
    private var isPro = false

    func start(uid: String?, accountType: PBAccountType, isPro: Bool) {
        guard self.uid != uid || self.accountType != accountType || self.isPro != isPro else { return }
        stop()
        self.uid = uid
        self.accountType = accountType
        self.isPro = isPro
        guard let uid, isPro else { return }

        userListener = repository.listenToUserDocument(uid: uid) { [weak self] data in
            guard let self else { return }
            let key = accountType == .teacher ? "teacherStudioId" : "studentStudioId"
            let sid = (data?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let studioID = (sid?.isEmpty == false) ? sid : nil
            self.attachTemplateListener(studioID: studioID)
        }
    }

    func stop() {
        userListener?.remove()
        templatesListener?.remove()
        userListener = nil
        templatesListener = nil
        templates = []
        studioID = nil
        statusMessage = nil
    }

    func saveTemplate(title: String, targetMinutes: Int, goals: [String], blocks: [String]) async {
        guard let uid, let studioID, isPro, accountType == .teacher else {
            statusMessage = "Template save is available for Teacher studio accounts."
            return
        }
        do {
            try await repository.savePlanTemplate(
                studioID: studioID,
                teacherUID: uid,
                title: title,
                targetMinutes: targetMinutes,
                goals: goals,
                blocks: blocks
            )
            statusMessage = "Studio template saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func attachTemplateListener(studioID: String?) {
        templatesListener?.remove()
        templatesListener = nil
        templates = []
        self.studioID = studioID
        guard let studioID else { return }
        templatesListener = repository.listenToPlanTemplates(studioID: studioID) { [weak self] rows in
            self?.templates = rows
        }
    }
}
