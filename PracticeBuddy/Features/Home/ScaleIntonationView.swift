import SwiftUI
import SwiftData
import Combine

struct ScaleIntonationView: View {
    private enum ExerciseType: String, CaseIterable, Identifiable {
        case oneOctaveScale
        case twoOctaveScale
        case arpeggio

        var id: String { rawValue }

        var title: String {
            switch self {
            case .oneOctaveScale: return "One-octave Scale"
            case .twoOctaveScale: return "Two-octave Scale"
            case .arpeggio: return "Arpeggio"
            }
        }
    }

    private enum ScaleMode: String, CaseIterable, Identifiable {
        case major
        case minor

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    private enum KeyRoot: String, CaseIterable, Identifiable {
        case c = "C"
        case g = "G"
        case d = "D"
        case a = "A"
        case e = "E"
        case b = "B"
        case fSharp = "F#"
        case bb = "Bb"
        case f = "F"
        case eb = "Eb"

        var id: String { rawValue }

        var semitoneFromC: Int {
            switch self {
            case .c: return 0
            case .g: return 7
            case .d: return 2
            case .a: return 9
            case .e: return 4
            case .b: return 11
            case .fSharp: return 6
            case .bb: return 10
            case .f: return 5
            case .eb: return 3
            }
        }
    }

    private enum OctavePreset: Int, CaseIterable, Identifiable {
        case low = 3
        case middle = 4

        var id: Int { rawValue }
        var title: String { self == .low ? "Low register" : "Middle register" }
    }

    private struct TargetNote: Identifiable {
        let id = UUID()
        let name: String
        let degree: Int
        let frequency: Double
    }

    private struct SamplePoint {
        let cents: Double
        let timeInNote: Double
    }

    private struct NoteScore: Identifiable {
        let id = UUID()
        let noteName: String
        let degree: Int
        let meanOffset: Double
        let centering: Double
        let stability: Double
        let samples: Int
    }

    private struct TakeResult {
        let overallScore: Int
        let centeringScore: Double
        let stabilityScore: Double
        let consistencyScore: Double
        let meanOffset: Double
        let noteScores: [NoteScore]
        let suggestions: [String]
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("pb.tools.tuner.referenceHz") private var savedReferenceHz: Int = 440

    @StateObject private var tuner = TunerEngine()

    @State private var exerciseType: ExerciseType = .oneOctaveScale
    @State private var scaleMode: ScaleMode = .major
    @State private var keyRoot: KeyRoot = .g
    @State private var octavePreset: OctavePreset = .middle
    @State private var useTempoTarget: Bool = true
    @State private var tempoBPM: Int = 72
    @State private var referenceHz: Int = 440

    @State private var isRunning = false
    @State private var startedAt: Date?
    @State private var activeTargets: [TargetNote] = []
    @State private var noteDuration: TimeInterval = 0.9
    @State private var currentNoteIndex: Int = 0
    @State private var noteSamples: [[SamplePoint]] = []
    @State private var result: TakeResult?
    @State private var statusMessage: String?

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    private var computedTargets: [TargetNote] {
        buildTargets(
            exercise: exerciseType,
            key: keyRoot,
            mode: scaleMode,
            baseOctave: octavePreset.rawValue,
            referenceHz: referenceHz
        )
    }

    private var progress: Double {
        guard isRunning, let startedAt, !activeTargets.isEmpty else { return 0 }
        let elapsed = Date().timeIntervalSince(startedAt)
        let total = noteDuration * Double(activeTargets.count)
        if total <= 0 { return 0 }
        return min(1, elapsed / total)
    }

    var body: some View {
        List {
            setupSection
            liveSection
            resultSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            referenceHz = min(max(savedReferenceHz, 415), 442)
        }
        .onChange(of: referenceHz) { _, newValue in
            savedReferenceHz = newValue
            if tuner.isReferenceTonePlaying {
                tuner.startReferenceTone(frequency: Double(newValue))
            }
        }
        .onReceive(tick) { _ in
            guard isRunning else { return }
            tickCapture()
        }
        .onDisappear {
            stopTake(resetOnly: true)
            tuner.stopListening()
            tuner.stopReferenceTone()
        }
    }

    private var setupSection: some View {
        Section("Scale Intonation Score") {
            Picker("Exercise", selection: $exerciseType) {
                ForEach(ExerciseType.allCases) { item in
                    Text(LocalizedStringKey(item.title)).tag(item)
                }
            }

            Picker("Mode", selection: $scaleMode) {
                ForEach(ScaleMode.allCases) { item in
                    Text(LocalizedStringKey(item.title)).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Picker("Key", selection: $keyRoot) {
                ForEach(KeyRoot.allCases) { root in
                    Text(root.rawValue).tag(root)
                }
            }
            .pickerStyle(.menu)

            Picker("Range", selection: $octavePreset) {
                ForEach(OctavePreset.allCases) { preset in
                    Text(LocalizedStringKey(preset.title)).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Use tempo target", isOn: $useTempoTarget)
            if useTempoTarget {
                Stepper(L10n.f("Tempo: %@ BPM", "\(tempoBPM)"), value: $tempoBPM, in: 40...180, step: 2)
            }

            Picker("Tuning", selection: $referenceHz) {
                Text("A=415").tag(415)
                Text("A=440").tag(440)
                Text("A=442").tag(442)
            }
            .pickerStyle(.segmented)

            HStack {
                Button(isRunning ? "Stop Take" : "Start Take") {
                    isRunning ? finishTake() : startTake()
                }
                .buttonStyle(.borderedProminent)

                Button(tuner.isReferenceTonePlaying ? "Stop A" : "Play A") {
                    tuner.toggleReferenceTone(frequency: Double(referenceHz))
                }
                .buttonStyle(.bordered)
            }

            if let statusMessage, !statusMessage.isEmpty {
                Text(LocalizedStringKey(statusMessage))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }

            Text("MVP: guided note windows score centering, stability, and consistency.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .listRowBackground(palette.surface)
    }

    private var liveSection: some View {
        Section("Live") {
            ProgressView(value: progress)

            HStack {
                Text("Signal")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(String(format: "%.0f%%", min(max(tuner.inputLevel * 1000, 0), 100)))
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("Detected")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(tuner.detectedNoteName)
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
            }

            if isRunning, !activeTargets.isEmpty {
                let index = min(max(currentNoteIndex, 0), activeTargets.count - 1)
                let target = activeTargets[index]
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.f("Target note %@/%@", "\(index + 1)", "\(activeTargets.count)"))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Text(L10n.f("%@ (degree %@)", target.name, "\(target.degree)"))
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)
                }
            } else {
                Text("Press Start Take to begin a guided pass.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var resultSection: some View {
        Section("Result") {
            if let result {
                HStack {
                    Text("Overall score")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(result.overallScore)")
                        .font(type.timer)
                        .foregroundStyle(palette.accent)
                        .monospacedDigit()
                }

                metricRow("Centering", value: result.centeringScore, suffix: "%")
                metricRow("Stability", value: result.stabilityScore, suffix: "%")
                metricRow("Consistency", value: result.consistencyScore, suffix: "%")
                metricRow("Mean offset", value: result.meanOffset, suffix: "c")

                if !result.suggestions.isEmpty {
                    Text("Top fixes")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    ForEach(result.suggestions, id: \.self) { item in
                        Text("• \(item)")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Per-note breakdown")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    ForEach(result.noteScores.prefix(20)) { note in
                        HStack {
                            Text(L10n.f("%@ (d%@)", note.noteName, "\(note.degree)"))
                                .font(type.footnote)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(String(format: "%+.1fc", note.meanOffset))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }
                    }
                }
            } else {
                Text("Run a take to see your score and note-by-note feedback.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .listRowBackground(palette.surface)
    }

    @ViewBuilder
    private func metricRow(_ title: String, value: Double, suffix: String) -> some View {
        HStack {
            Text(title)
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text(String(format: suffix == "c" ? "%+.1f\(suffix)" : "%.0f\(suffix)", value))
                .font(type.number)
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
        }
    }

    private func startTake() {
        activeTargets = computedTargets
        guard !activeTargets.isEmpty else {
            statusMessage = "No target notes generated."
            return
        }

        noteDuration = useTempoTarget ? max(0.45, 60.0 / Double(tempoBPM)) : 1.2
        currentNoteIndex = 0
        noteSamples = Array(repeating: [], count: activeTargets.count)
        result = nil
        statusMessage = "Listening and scoring…"
        startedAt = Date()
        isRunning = true
        tuner.requestMicPermissionAndStart()
    }

    private func stopTake(resetOnly: Bool) {
        isRunning = false
        startedAt = nil
        currentNoteIndex = 0
        if resetOnly {
            activeTargets = []
            noteSamples = []
        }
    }

    private func tickCapture() {
        guard isRunning, let startedAt, !activeTargets.isEmpty else { return }

        let elapsed = Date().timeIntervalSince(startedAt)
        let total = noteDuration * Double(activeTargets.count)
        let index = min(max(Int(elapsed / noteDuration), 0), activeTargets.count - 1)
        currentNoteIndex = index

        if let detected = tuner.detectedFrequency, tuner.inputLevel > 0.002 {
            let noteStart = Double(index) * noteDuration
            let timeInNote = max(0, elapsed - noteStart)
            let target = activeTargets[index].frequency
            let cents = 1200.0 * log2(detected / target)
            if abs(cents) <= 200 {
                noteSamples[index].append(.init(cents: cents, timeInNote: timeInNote))
            }
        }

        if elapsed >= total {
            finishTake()
        }
    }

    private func finishTake() {
        guard isRunning else { return }
        isRunning = false
        startedAt = nil

        let computed = computeResult(targets: activeTargets, samples: noteSamples)
        result = computed
        saveResult(computed)
    }

    private func computeResult(targets: [TargetNote], samples: [[SamplePoint]]) -> TakeResult {
        guard !targets.isEmpty else {
            return TakeResult(
                overallScore: 0,
                centeringScore: 0,
                stabilityScore: 0,
                consistencyScore: 0,
                meanOffset: 0,
                noteScores: [],
                suggestions: [String(localized: "No notes were analyzed.")]
            )
        }

        var noteScores: [NoteScore] = []
        var centeredTotals: [Double] = []
        var stabilityTotals: [Double] = []
        var meanOffsets: [Double] = []
        var degreeMeans: [Int: [Double]] = [:]

        for (idx, target) in targets.enumerated() {
            let raw = idx < samples.count ? samples[idx] : []
            let settled = raw.filter { $0.timeInNote >= 0.20 }
            let usable = settled.count >= 3 ? settled : raw
            let values = usable.map(\.cents)

            guard !values.isEmpty else {
                noteScores.append(
                    NoteScore(
                        noteName: target.name,
                        degree: target.degree,
                        meanOffset: 0,
                        centering: 0,
                        stability: 0,
                        samples: 0
                    )
                )
                continue
            }

            let mean = values.reduce(0, +) / Double(values.count)
            let centered = values.filter { abs($0) <= 10.0 }.count
            let centering = (Double(centered) / Double(values.count)) * 100.0

            let residuals = values.map { $0 - mean }
            let residualsForStability = residuals.filter { abs($0) <= 35.0 }
            let stabilityBase = residualsForStability.isEmpty ? residuals : residualsForStability
            let jitter = standardDeviation(stabilityBase)
            let stability = max(0, 100 - jitter * 2.2)

            noteScores.append(
                NoteScore(
                    noteName: target.name,
                    degree: target.degree,
                    meanOffset: mean,
                    centering: centering,
                    stability: stability,
                    samples: values.count
                )
            )

            centeredTotals.append(centering)
            stabilityTotals.append(stability)
            meanOffsets.append(mean)
            degreeMeans[target.degree, default: []].append(mean)
        }

        let centeringScore = centeredTotals.isEmpty ? 0 : centeredTotals.reduce(0, +) / Double(centeredTotals.count)
        let stabilityScore = stabilityTotals.isEmpty ? 0 : stabilityTotals.reduce(0, +) / Double(stabilityTotals.count)
        let meanOffset = meanOffsets.isEmpty ? 0 : meanOffsets.reduce(0, +) / Double(meanOffsets.count)
        let accuracyScore = max(0, 100 - abs(meanOffset) * 2.5)

        let degreeStd = degreeMeans
            .values
            .filter { $0.count > 1 }
            .map(standardDeviation)
        let avgDegreeStd = degreeStd.isEmpty ? 8.0 : degreeStd.reduce(0, +) / Double(degreeStd.count)
        let consistencyScore = max(0, 100 - avgDegreeStd * 2.0)

        let overall = Int(
            (centeringScore * 0.40 + stabilityScore * 0.25 + accuracyScore * 0.20 + consistencyScore * 0.15)
                .rounded()
        )

        let suggestions = topSuggestions(from: noteScores)

        return TakeResult(
            overallScore: min(max(overall, 0), 100),
            centeringScore: centeringScore,
            stabilityScore: stabilityScore,
            consistencyScore: consistencyScore,
            meanOffset: meanOffset,
            noteScores: noteScores,
            suggestions: suggestions
        )
    }

    private func topSuggestions(from notes: [NoteScore]) -> [String] {
        let ranked = notes
            .filter { $0.samples > 0 }
            .sorted { abs($0.meanOffset) > abs($1.meanOffset) }
            .prefix(2)

        var output: [String] = []
        for item in ranked {
            let direction = item.meanOffset >= 0 ? String(localized: "sharp") : String(localized: "flat")
            output.append(
                L10n.f(
                    "Degree %@ (%@) tends %@ %@.",
                    "\(item.degree)",
                    item.noteName,
                    direction,
                    String(format: "%+.1fc", item.meanOffset)
                )
            )
        }
        if output.isEmpty {
            output.append(String(localized: "Signal was limited. Try a quieter room and hold each note slightly longer."))
        }
        return output
    }

    private func saveResult(_ result: TakeResult) {
        let suggestionsRaw = result.suggestions.joined(separator: "|")
        let detailsRaw = result.noteScores.map { row in
            let m = String(format: "%.2f", row.meanOffset)
            let c = String(format: "%.1f", row.centering)
            let s = String(format: "%.1f", row.stability)
            return "\(row.degree),\(row.noteName),\(m),\(c),\(s),\(row.samples)"
        }.joined(separator: ";")

        let model = ScaleIntonationTakeModel(
            exerciseTypeRaw: exerciseType.rawValue,
            keyRaw: keyRoot.rawValue,
            modeRaw: scaleMode.rawValue,
            baseOctave: octavePreset.rawValue,
            referenceHz: referenceHz,
            tempoBPM: useTempoTarget ? tempoBPM : 0,
            noteCount: activeTargets.count,
            overallScore: result.overallScore,
            centeringScore: result.centeringScore,
            stabilityScore: result.stabilityScore,
            consistencyScore: result.consistencyScore,
            meanOffsetCents: result.meanOffset,
            suggestionsRaw: suggestionsRaw,
            perNoteJSON: detailsRaw
        )
        modelContext.insert(model)
        do {
            try modelContext.save()
            statusMessage = "Scale intonation take saved in History."
        } catch {
            statusMessage = L10n.f("Could not save take: %@", error.localizedDescription)
        }
    }

    private func buildTargets(
        exercise: ExerciseType,
        key: KeyRoot,
        mode: ScaleMode,
        baseOctave: Int,
        referenceHz: Int
    ) -> [TargetNote] {
        let intervalsUp: [Int]
        switch exercise {
        case .oneOctaveScale:
            intervalsUp = mode == .major
                ? [0, 2, 4, 5, 7, 9, 11, 12]
                : [0, 2, 3, 5, 7, 8, 10, 12]
        case .twoOctaveScale:
            intervalsUp = mode == .major
                ? [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24]
                : [0, 2, 3, 5, 7, 8, 10, 12, 14, 15, 17, 19, 20, 22, 24]
        case .arpeggio:
            intervalsUp = mode == .major ? [0, 4, 7, 12] : [0, 3, 7, 12]
        }

        var intervals = intervalsUp
        let descending = intervalsUp.dropLast().reversed()
        intervals.append(contentsOf: descending)

        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let rootMidi = 12 * (baseOctave + 1) + key.semitoneFromC
        let reference = Double(referenceHz)

        return intervals.enumerated().map { index, offset in
            let midi = rootMidi + offset
            let freq = reference * pow(2.0, Double(midi - 69) / 12.0)
            let noteIndex = (midi % 12 + 12) % 12
            let octave = midi / 12 - 1
            let degree = (index % 7) + 1
            return TargetNote(
                name: "\(noteNames[noteIndex])\(octave)",
                degree: degree,
                frequency: freq
            )
        }
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { acc, v in
            let d = v - mean
            return acc + d * d
        } / Double(values.count)
        return sqrt(max(0, variance))
    }
}
