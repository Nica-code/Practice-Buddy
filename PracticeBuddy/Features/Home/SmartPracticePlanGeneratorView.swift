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
        let summary: String
        let blocks: [PlanBlock]
        let suggestedTempoStart: Int
        let suggestedTempoEnd: Int
        let loopCount: Int
        let weaknesses: [Weakness]
    }

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
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

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        List {
            if purchaseManager.accountType != .student || !purchaseManager.isPro {
                Section("Practice Lab Pro") {
                    Text("Smart Practice Plan Generator is a Pro Student feature.")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(palette.surface)
            } else {
                setupSection
                planSection
                feedbackSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            dataWindowDays = lastWindowDays == 7 ? 7 : 14
            difficultyFeedback = DifficultyFeedback(rawValue: lastDifficultyRaw) ?? .justRight
            mainIssueFeedback = MainIssueFeedback(rawValue: lastIssueRaw) ?? .none
            if generatedPlan == nil {
                generatePlan()
            }
        }
    }

    private var setupSection: some View {
        Section("Smart Practice Plan Generator") {
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

            Button("Generate Adaptive Plan") {
                generatePlan()
            }
            .buttonStyle(.borderedProminent)

            if let statusMessage, !statusMessage.isEmpty {
                Text(LocalizedStringKey(statusMessage))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var planSection: some View {
        Section("Plan") {
            if let generatedPlan {
                Text(generatedPlan.summary)
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)

                HStack {
                    Text("Weaknesses detected")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(generatedPlan.weaknesses.map { String(localized: String.LocalizationValue($0.title)) }.joined(separator: ", "))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }

                HStack {
                    Text("Tempo ramp")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(L10n.f("%@ → %@ BPM", "\(generatedPlan.suggestedTempoStart)", "\(generatedPlan.suggestedTempoEnd)"))
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Loop target")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(L10n.f("%@ loops", "\(generatedPlan.loopCount)"))
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                ForEach(generatedPlan.blocks) { block in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(LocalizedStringKey(block.title))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(L10n.f("%@ min", "\(block.minutes)"))
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }
                        Text(LocalizedStringKey(block.details))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(10)
                    .background(palette.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
                }
            } else {
                Text("Generate a plan to see adaptive coaching suggestions.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var feedbackSection: some View {
        Section("After Session Feedback") {
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
            .buttonStyle(.bordered)

            Text("The next generated plan adjusts tempo, loop count, and focus blocks based on this feedback.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .listRowBackground(palette.surface)
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
        statusMessage = "Plan generated."
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
