import SwiftUI
import SwiftData

struct SmartPracticePlanGeneratorView: View {
    private enum TimePreset: Int, CaseIterable, Identifiable {
        case ten = 10
        case twenty = 20
        case fortyFive = 45

        var id: Int { rawValue }
        var title: String { "\(rawValue) min" }
    }

    private enum GoalType: String, CaseIterable, Identifiable {
        case audition
        case jury
        case recital

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    private enum DifficultyFeedback: String, CaseIterable, Identifiable {
        case tooEasy
        case justRight
        case tooHard

        var id: String { rawValue }
        var title: String {
            switch self {
            case .tooEasy: return "Too easy"
            case .justRight: return "Just right"
            case .tooHard: return "Too hard"
            }
        }
    }

    private enum MainIssueFeedback: String, CaseIterable, Identifiable {
        case intonation
        case rhythm
        case endurance
        case focus
        case none

        var id: String { rawValue }
        var title: String {
            switch self {
            case .intonation: return "Intonation"
            case .rhythm: return "Rhythm"
            case .endurance: return "Endurance"
            case .focus: return "Focus"
            case .none: return "None"
            }
        }
    }

    private enum Weakness: String, CaseIterable {
        case intonation
        case rhythm
        case endurance
        case consistency
        case focus

        var title: String { rawValue.capitalized }
    }

    private struct PlanBlock: Identifiable {
        let id = UUID()
        let title: String
        let minutes: Int
        let details: String
    }

    private struct GeneratedPlan {
        let id = UUID()
        let summary: String
        let blocks: [PlanBlock]
        let suggestedTempoStart: Int
        let suggestedTempoEnd: Int
        let loopCount: Int
        let weaknesses: [Weakness]
    }

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: [SortDescriptor(\LoopPracticeLogModel.date, order: .reverse)]) private var loopLogs: [LoopPracticeLogModel]
    @Query(sort: [SortDescriptor(\RhythmAccuracyTakeModel.date, order: .reverse)]) private var rhythmTakes: [RhythmAccuracyTakeModel]
    @Query(sort: [SortDescriptor(\RunThroughModel.date, order: .reverse)]) private var runThroughs: [RunThroughModel]
    @Query(sort: [SortDescriptor(\ScaleIntonationTakeModel.date, order: .reverse)]) private var intonationTakes: [ScaleIntonationTakeModel]

    @AppStorage("pb.smartcoach.lastDifficulty") private var lastDifficultyRaw: String = DifficultyFeedback.justRight.rawValue
    @AppStorage("pb.smartcoach.lastIssue") private var lastIssueRaw: String = MainIssueFeedback.none.rawValue
    @AppStorage("pb.smartcoach.lastWindowDays") private var lastWindowDays: Int = 14

    @State private var selectedTime: TimePreset = .twenty
    @State private var selectedGoal: GoalType = .audition
    @State private var dataWindowDays: Int = 14
    @State private var generatedPlan: GeneratedPlan?
    @State private var statusMessage: String?
    @State private var difficultyFeedback: DifficultyFeedback = .justRight
    @State private var mainIssueFeedback: MainIssueFeedback = .none
    @State private var previewUsed = false
    @State private var showPro = false

    private var previewDefaultsKey: String {
        "practiquest.smartCoach.previewUsed.\(firebase.currentUserID ?? "anonymous")"
    }

    private var canGenerate: Bool {
        purchaseManager.isPro || !previewUsed
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(
                    title: "Smart Coach",
                    subtitle: "A plan shaped by your private practice history."
                )
                if firebase.isAnonymousUser {
                    StudioQuestSection {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Save this for your musician profile", systemImage: "lock.shield")
                                .font(.headline)
                            Text("Create a permanent account to unlock your one complete Smart Coach preview and keep the plan with you.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Set up your profile") {
                                router.navigate(to: .profileUpgrade)
                            }
                            .buttonStyle(StudioQuestPrimaryButtonStyle())
                        }
                    }
                } else {
                setupSection
                planSection
                feedbackSection
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .sheet(isPresented: $showPro) { NavigationStack { StudioQuestProView() } }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            dataWindowDays = lastWindowDays == 7 ? 7 : 14
            difficultyFeedback = DifficultyFeedback(rawValue: lastDifficultyRaw) ?? .justRight
            mainIssueFeedback = MainIssueFeedback(rawValue: lastIssueRaw) ?? .none
            previewUsed = UserDefaults.standard.bool(forKey: previewDefaultsKey)
            if generatedPlan == nil, purchaseManager.isPro {
                generatePlan()
            }
        }
    }

    private var setupSection: some View {
        StudioQuestSection {
            VStack(alignment: .leading, spacing: 16) {
                Text("Shape your next session")
                    .font(StudioQuestTokens.Typography.sectionTitle)
            Picker("Available time", selection: $selectedTime) {
                ForEach(TimePreset.allCases) { item in
                    Text(LocalizedStringKey(item.title)).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Picker("Goal", selection: $selectedGoal) {
                ForEach(GoalType.allCases) { item in
                    Text(LocalizedStringKey(item.title)).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Picker("Use history window", selection: $dataWindowDays) {
                Text("7 days").tag(7)
                Text("14 days").tag(14)
            }
            .pickerStyle(.segmented)

            Button(canGenerate ? "Generate plan" : "Continue with Pro") {
                if !canGenerate {
                    showPro = true
                    return
                }
                generatePlan()
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())

            if let statusMessage, !statusMessage.isEmpty {
                Text(LocalizedStringKey(statusMessage))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !purchaseManager.isPro {
                Text(previewUsed
                    ? "Your included Smart Coach preview is complete. Pro unlocks ongoing adaptation, saved plans, and presets."
                    : "Your permanent account includes one complete Smart Coach preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your plan")
                .font(StudioQuestTokens.Typography.sectionTitle)
            if let generatedPlan {
                StudioQuestSection {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(generatedPlan.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                HStack {
                    Text("Weaknesses detected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(generatedPlan.weaknesses.map { String(localized: String.LocalizationValue($0.title)) }.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Tempo ramp")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(L10n.f("%@ → %@ BPM", "\(generatedPlan.suggestedTempoStart)", "\(generatedPlan.suggestedTempoEnd)"))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Loop target")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(L10n.f("%@ loops", "\(generatedPlan.loopCount)"))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                ForEach(generatedPlan.blocks) { block in
                    SmartPracticePlanBlockRow(
                        title: block.title,
                        minutes: block.minutes,
                        details: block.details,
                        colorScheme: colorScheme
                    )
                }
                    Button("Start this plan") {
                        startGeneratedPlan(generatedPlan)
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    }
                }
            } else {
                StudioQuestEmptyState(
                    title: "Your next plan is ready to shape",
                    message: "Choose your time and focus, then let Smart Coach use your local history.",
                    systemImage: "sparkles",
                    action: { generatePlan() }
                )
            }
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("For your next plan")
                .font(StudioQuestTokens.Typography.sectionTitle)
            StudioQuestSection {
                VStack(alignment: .leading, spacing: 16) {
            Picker("How did this feel?", selection: $difficultyFeedback) {
                ForEach(DifficultyFeedback.allCases) { item in
                    Text(LocalizedStringKey(item.title)).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Picker("Main issue today", selection: $mainIssueFeedback) {
                ForEach(MainIssueFeedback.allCases) { item in
                    Text(LocalizedStringKey(item.title)).tag(item)
                }
            }
            .pickerStyle(.menu)

            Button("Save Feedback for Next Plan") {
                saveFeedback()
            }
            .buttonStyle(StudioQuestSecondaryButtonStyle())

            Text("The next generated plan adjusts tempo, loop count, and focus blocks based on this feedback.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func saveFeedback() {
        lastDifficultyRaw = difficultyFeedback.rawValue
        lastIssueRaw = mainIssueFeedback.rawValue
        lastWindowDays = dataWindowDays
        statusMessage = "Feedback saved. Generate again for an updated plan."
    }

    private func generatePlan() {
        lastWindowDays = dataWindowDays
        let now = Date()
        let windowStart = Calendar.current.date(byAdding: .day, value: -dataWindowDays, to: now) ?? now

        let recentSessions = store.sessions.filter { $0.date >= windowStart }
        let recentLoops = loopLogs.filter { $0.date >= windowStart }
        let recentRhythm = rhythmTakes.filter { $0.date >= windowStart }
        let recentRunThroughs = runThroughs.filter { $0.date >= windowStart }
        let recentIntonation = intonationTakes.filter { $0.date >= windowStart }

        var weaknessScores: [Weakness: Double] = [:]

        if !recentRhythm.isEmpty {
            let avgGroove = recentRhythm.map { Double($0.grooveScore) }.reduce(0, +) / Double(recentRhythm.count)
            weaknessScores[.rhythm] = max(0, min(1, 1 - (avgGroove / 100.0)))
        } else {
            weaknessScores[.rhythm] = 0.35
        }

        if !recentIntonation.isEmpty {
            let avgIntScore = recentIntonation.map { Double($0.overallScore) }.reduce(0, +) / Double(recentIntonation.count)
            let avgOffset = recentIntonation.map { abs($0.meanOffsetCents) }.reduce(0, +) / Double(recentIntonation.count)
            let intonationScore = max(0, min(1, 1 - (avgIntScore / 100.0)))
            let offsetPenalty = max(0, min(1, avgOffset / 30.0))
            weaknessScores[.intonation] = max(intonationScore, offsetPenalty)
        } else {
            weaknessScores[.intonation] = 0.35
        }

        if !recentRunThroughs.isEmpty {
            let avgRating = recentRunThroughs.map { Double($0.selfRating) }.reduce(0, +) / Double(recentRunThroughs.count)
            weaknessScores[.consistency] = max(0, min(1, 1 - (avgRating / 5.0)))
        } else {
            weaknessScores[.consistency] = 0.30
        }

        let avgSessionMinutes = recentSessions.isEmpty
            ? 0
            : Double(recentSessions.map(\.durationSeconds).reduce(0, +)) / 60.0 / Double(recentSessions.count)
        let targetMinutes = Double(selectedTime.rawValue)
        let enduranceGap = max(0, min(1, (targetMinutes - avgSessionMinutes) / max(targetMinutes, 1)))
        weaknessScores[.endurance] = enduranceGap

        var focusBase = 0.30
        if difficultyFeedback == .tooHard { focusBase += 0.15 }
        if mainIssueFeedback == .focus { focusBase += 0.25 }
        weaknessScores[.focus] = max(0, min(1, focusBase))

        if mainIssueFeedback == .intonation { weaknessScores[.intonation, default: 0.3] += 0.20 }
        if mainIssueFeedback == .rhythm { weaknessScores[.rhythm, default: 0.3] += 0.20 }
        if mainIssueFeedback == .endurance { weaknessScores[.endurance, default: 0.3] += 0.20 }

        let rankedWeaknesses = weaknessScores
            .map { ($0.key, min(max($0.value, 0), 1)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let topWeaknesses = Array(rankedWeaknesses.prefix(2))

        let recentTempoValues = recentLoops
            .flatMap { [$0.tempoStartBPM, $0.tempoEndBPM] }
            .filter { $0 > 0 }
        let baseTempo = recentTempoValues.isEmpty ? 72 : Int(Double(recentTempoValues.reduce(0, +)) / Double(recentTempoValues.count))

        var tempoStart = max(50, baseTempo - 8)
        var tempoEnd = min(180, tempoStart + 12)
        if difficultyFeedback == .tooEasy {
            tempoStart = min(180, tempoStart + 6)
            tempoEnd = min(200, tempoEnd + 8)
        } else if difficultyFeedback == .tooHard {
            tempoStart = max(40, tempoStart - 6)
            tempoEnd = max(tempoStart + 4, tempoEnd - 6)
        }

        let baseLoopCount = max(3, Int(round(Double(selectedTime.rawValue) * 0.45)))
        var loopCount = baseLoopCount
        if difficultyFeedback == .tooEasy { loopCount += 2 }
        if difficultyFeedback == .tooHard { loopCount = max(3, loopCount - 2) }

        let blocks = buildBlocks(
            minutes: selectedTime.rawValue,
            goal: selectedGoal,
            weaknesses: topWeaknesses,
            tempoStart: tempoStart,
            tempoEnd: tempoEnd,
            loopCount: loopCount
        )

        let summary = "Adaptive coach built this from your last \(dataWindowDays) days (\(recentSessions.count) sessions, \(recentLoops.count) loop logs)."
        generatedPlan = GeneratedPlan(
            summary: summary,
            blocks: blocks,
            suggestedTempoStart: tempoStart,
            suggestedTempoEnd: tempoEnd,
            loopCount: loopCount,
            weaknesses: topWeaknesses
        )
        if !purchaseManager.isPro, !previewUsed {
            previewUsed = true
            UserDefaults.standard.set(true, forKey: previewDefaultsKey)
            PracticeAnalytics.record(.smartCoachPreview)
        }
        statusMessage = "Plan generated."
    }

    private func startGeneratedPlan(_ plan: GeneratedPlan) {
        let tasks = plan.blocks.map {
            PracticePlanTask(title: $0.title, minutes: $0.minutes)
        }
        let preset = PracticePreset(
            piece: "",
            task: plan.blocks.first?.title ?? "Smart Coach practice",
            durationMinutes: selectedTime.rawValue,
            verified: true,
            launchContext: PracticeLaunchContext(
                source: "smart_coach",
                smartCoachPlanID: plan.id.uuidString
            ),
            tasks: tasks
        )
        router.navigate(to: .practiceSetup(preset: preset), in: .today)
    }

    private func buildBlocks(
        minutes: Int,
        goal: GoalType,
        weaknesses: [Weakness],
        tempoStart: Int,
        tempoEnd: Int,
        loopCount: Int
    ) -> [PlanBlock] {
        let warmupMinutes = max(2, Int(round(Double(minutes) * 0.20)))
        let techniqueMinutes = max(4, Int(round(Double(minutes) * 0.35)))
        let repertoireMinutes = max(3, Int(round(Double(minutes) * 0.25)))
        let runThroughMinutes = max(2, minutes - warmupMinutes - techniqueMinutes - repertoireMinutes)

        let primary = weaknesses.first ?? .intonation
        let secondary = weaknesses.dropFirst().first ?? .rhythm

        let goalNote: String
        switch goal {
        case .audition:
            goalNote = "Prioritize reliability under pressure and clean entries."
        case .jury:
            goalNote = "Prioritize consistent tone and examiner-ready precision."
        case .recital:
            goalNote = "Prioritize musical flow and endurance for full takes."
        }

        return [
            PlanBlock(
                title: "Warm-up",
                minutes: warmupMinutes,
                details: "Open strings + slow scales. \(goalNote)"
            ),
            PlanBlock(
                title: "Technique Focus: \(primary.title)",
                minutes: techniqueMinutes,
                details: "Tempo ramp \(tempoStart)→\(tempoEnd) BPM, \(loopCount) loops (45s work / 15s rest)."
            ),
            PlanBlock(
                title: "Technique Focus: \(secondary.title)",
                minutes: max(3, techniqueMinutes / 2),
                details: "Target weak passages with micro-loops and clean releases."
            ),
            PlanBlock(
                title: "Repertoire",
                minutes: repertoireMinutes,
                details: "Apply technique work to performance excerpts."
            ),
            PlanBlock(
                title: "Run-through",
                minutes: runThroughMinutes,
                details: "One full run-through at end. No pause, capture confidence rating."
            )
        ]
    }
}
