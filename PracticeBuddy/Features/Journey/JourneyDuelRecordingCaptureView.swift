import SwiftUI
import Combine

struct DuelRecordingCaptureView: View {
    let challenge: DuelChallenge
    let onComplete: (DuelDerivedMetrics) -> Void

    private enum Phase {
        case ready
        case preRoll
        case intonation
        case rhythm
        case complete
    }

    private struct IntonationAggregate {
        var totalSamples: Int = 0
        var inScaleSamples: Int = 0
        var inScaleCents: [Double] = []
        var inScalePitchClasses: Set<Int> = []
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var duelLeague: DuelLeagueManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var tuner = TunerEngine()
    @StateObject private var rhythmEngine = RhythmAccuracyEngine()
    @StateObject private var metronome = MetronomeEngine()

    @State private var phase: Phase = .ready
    @State private var preRollStartedAt: Date?
    @State private var preRollSeconds: Int = 5
    @State private var intonationRunning = false
    @State private var intonationStartedAt: Date?
    @State private var aggregate = IntonationAggregate()
    @State private var intonationScore: Int = 0
    @State private var intonationConsistency: Int = 0
    @State private var rhythmRunning = false
    @State private var rhythmBPM: Int = 72
    @State private var statusMessage: String?
    @State private var finalMetrics: DuelDerivedMetrics?

    private let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var intonationDuration: TimeInterval {
        switch challenge.octaveCount {
        case 3: return 50
        case 2: return 36
        default: return 24
        }
    }
    private var rhythmTargetBeats: Int {
        let base: Int
        switch challenge.octaveCount {
        case 3: base = 32
        case 2: base = 24
        default: base = 16
        }
        switch strictnessTier {
        case 7: return base + 12
        case 6: return base + 10
        case 5: return base + 8
        case 4: return base + 6
        case 3: return base + 4
        default: return base
        }
    }
    private var scaleDescriptor: String {
        let raw = challenge.scaleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty { return raw }
        return challenge.objective.split(separator: "•").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? "C major"
    }
    private var allowedPitchClasses: Set<Int> {
        scalePitchClasses(for: scaleDescriptor)
    }
    private var allowedPitchNamesText: String {
        let names = allowedPitchClasses.sorted().map(noteName(for:))
        return names.joined(separator: " - ")
    }
    private var inScaleRatio: Double {
        guard aggregate.totalSamples > 0 else { return 0 }
        return Double(aggregate.inScaleSamples) / Double(aggregate.totalSamples)
    }
    private var minimumRhythmBPM: Int {
        max(50, min(220, challenge.requiredMinTempoBPM > 0 ? challenge.requiredMinTempoBPM : 50))
    }
    private var challengeLeagueTier: DuelLeagueTier {
        if let raw = challenge.requiredLeague?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let tier = DuelLeagueTier(rawValue: raw) {
            return tier
        }
        return DuelLeagueTier.forRating(duelLeague.duelRating)
    }
    private var strictnessTier: Int {
        challengeLeagueTier.difficultyRank
    }
    private var strictnessLabel: String {
        switch strictnessTier {
        case 7: return "Grandmaster"
        case 6: return "Master"
        case 5: return "Diamond"
        case 4: return "Emerald"
        case 3: return "Platinum"
        case 2: return "Gold"
        case 1: return "Silver"
        default: return "Bronze"
        }
    }
    private var minIntonationSamples: Int {
        let base: Int
        switch challenge.octaveCount {
        case 3: base = 180
        case 2: base = 130
        default: base = 90
        }
        let multiplier = 0.80 + (Double(strictnessTier) * 0.07)
        return Int(Double(base) * multiplier)
    }
    private var minUniqueScaleTones: Int {
        let base: Int
        switch challenge.octaveCount {
        case 3: base = 6
        case 2: base = 5
        default: base = 4
        }
        return min(7, max(3, base - 1 + (strictnessTier / 2)))
    }
    private var minInScaleRatio: Double {
        min(0.82, 0.45 + (Double(strictnessTier) * 0.05))
    }
    private var intonationPassed: Bool {
        aggregate.totalSamples >= minIntonationSamples &&
            aggregate.inScaleSamples > 0 &&
            inScaleRatio >= minInScaleRatio &&
            aggregate.inScalePitchClasses.count >= minUniqueScaleTones
    }

    var body: some View {
        Form {
            Section("Duel Objective") {
                Text(challenge.objective)
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Text("Scale collection: \(allowedPitchNamesText)")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                Text("Analysis mode: \(strictnessLabel)")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                if challenge.requiredMinTempoBPM > 0 {
                    Text("Required tempo floor: \(challenge.requiredMinTempoBPM)+ BPM")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
                Text("Repeats are allowed. Scoring uses in-scale pitch collection match + tuning quality.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            .listRowBackground(Color.clear)

            intonationSection
            rhythmSection

            if let finalMetrics {
                Section("Ready to Submit") {
                    Text(
                        L10n.f(
                            "Derived %@ (I %@ • R %@ • C %@)",
                            "\(finalMetrics.derivedScore)",
                            "\(finalMetrics.intonationScore)",
                            "\(finalMetrics.rhythmScore)",
                            "\(finalMetrics.consistencyScore)"
                        )
                    )
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()

                    Button("Use This Take") {
                        onComplete(finalMetrics)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                }
                .listRowBackground(Color.clear)
            }

            if let statusMessage, !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PBBackdropView(palette: palette))
        .navigationTitle("Record Duel Take")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { _ in
            captureTick()
        }
        .onChange(of: rhythmEngine.summary?.beatsAnalyzed) { _, _ in
            guard let summary = rhythmEngine.summary else { return }
            rhythmRunning = false
            metronome.stop()
            buildFinalMetrics(rhythmSummary: summary)
        }
        .onDisappear {
            stopAllCapture()
        }
    }

    private var intonationSection: some View {
        Section("Step 1 • Intonation") {
            switch phase {
            case .preRoll:
                HStack {
                    Text("Starting in")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(preRollSeconds)")
                        .font(type.timer)
                        .foregroundStyle(palette.accent)
                        .monospacedDigit()
                }
            case .intonation:
                let remaining = max(0, Int((intonationDuration - Date().timeIntervalSince(intonationStartedAt ?? .now)).rounded()))
                HStack {
                    Text("Recording")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(remaining)s")
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            default:
                Text("Press Record. A 5s countdown starts, then capture begins.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
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

            HStack {
                Text("Samples")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(aggregate.totalSamples)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("In-scale")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(aggregate.inScaleSamples) (\(Int((inScaleRatio * 100).rounded()))%)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("Unique scale tones hit")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(aggregate.inScalePitchClasses.count)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            if !intonationRunning && aggregate.totalSamples > 0 {
                Text("Score \(intonationScore) • Consistency \(intonationConsistency)")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            Button(phase == .preRoll || intonationRunning ? "Stop Intonation" : "Record Intonation") {
                if phase == .preRoll || intonationRunning {
                    stopIntonation()
                    finalizeIntonation()
                } else {
                    startIntonationWithPreRoll()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .disabled(!(phase == .ready || phase == .complete || phase == .preRoll || phase == .intonation))
        }
        .listRowBackground(Color.clear)
    }

    private var rhythmSection: some View {
        Section("Step 2 • Rhythm") {
            Text("Play with steady pulse. Target beats: \(rhythmTargetBeats).")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

            Stepper(L10n.f("Tempo: %@ BPM", "\(rhythmBPM)"), value: $rhythmBPM, in: minimumRhythmBPM...220)
                .font(type.body)
                .disabled(rhythmRunning)

            if let summary = rhythmEngine.summary {
                Text(
                    L10n.f(
                        "Groove %@ • Avg %@ ms • Beats %@",
                        "\(summary.grooveScore)",
                        String(format: "%+.1f", summary.averageOffsetMs),
                        "\(summary.beatsAnalyzed)"
                    )
                )
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
            } else if rhythmRunning {
                Text("Listening…")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }

            Button(rhythmRunning ? "Stop Rhythm" : "Start Rhythm") {
                if rhythmRunning {
                    stopRhythm()
                } else {
                    startRhythm()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .disabled((phase != .rhythm && phase != .complete) || !intonationPassed)
        }
        .listRowBackground(Color.clear)
    }

    private func startIntonationWithPreRoll() {
        stopAllCapture()
        finalMetrics = nil
        statusMessage = nil
        aggregate = IntonationAggregate()
        intonationScore = 0
        intonationConsistency = 0
        phase = .preRoll
        preRollSeconds = 5
        preRollStartedAt = Date()
        tuner.requestMicPermissionAndStart()
    }

    private func startIntonationCaptureNow() {
        preRollStartedAt = nil
        preRollSeconds = 0
        intonationStartedAt = Date()
        intonationRunning = true
        phase = .intonation
    }

    private func stopIntonation() {
        intonationRunning = false
        preRollStartedAt = nil
        preRollSeconds = 0
        intonationStartedAt = nil
        tuner.stopListening()
        if phase == .preRoll || phase == .intonation {
            phase = .ready
        }
    }

    private func captureTick() {
        if phase == .preRoll, let started = preRollStartedAt {
            let elapsed = Date().timeIntervalSince(started)
            let remaining = max(0, Int(ceil(5.0 - elapsed)))
            preRollSeconds = remaining
            if elapsed >= 5.0 {
                startIntonationCaptureNow()
            }
            return
        }

        guard intonationRunning, phase == .intonation else { return }
        guard let started = intonationStartedAt else { return }

        if let frequency = tuner.detectedFrequency, tuner.inputLevel > 0.003 {
            registerFrequency(frequency)
        }

        if Date().timeIntervalSince(started) >= intonationDuration {
            stopIntonation()
            finalizeIntonation()
        }
    }

    private func registerFrequency(_ frequency: Double) {
        let midi = 69.0 + 12.0 * log2(frequency / 440.0)
        let roundedMidi = Int(midi.rounded())
        let pitchClass = positiveModulo(roundedMidi, 12)

        aggregate.totalSamples += 1
        if allowedPitchClasses.contains(pitchClass) {
            let delta = nearestAllowedCentsDelta(for: midi)
            aggregate.inScaleSamples += 1
            aggregate.inScaleCents.append(delta)
            aggregate.inScalePitchClasses.insert(pitchClass)
        }
    }

    private func finalizeIntonation() {
        guard aggregate.totalSamples > 0 else {
            statusMessage = "No usable signal captured. Try again."
            return
        }
        guard aggregate.inScaleSamples > 0 else {
            statusMessage = "No in-scale notes detected. Try again."
            return
        }

        let meanAbs = aggregate.inScaleCents.map { abs($0) }.reduce(0, +) / Double(aggregate.inScaleCents.count)
        let std = standardDeviation(aggregate.inScaleCents)
        let ratioScore = inScaleRatio * 100.0
        let tuningScore = max(0.0, 100.0 - meanAbs * 2.0)
        let coverageScore = (Double(aggregate.inScalePitchClasses.count) / Double(max(1, allowedPitchClasses.count))) * 100.0

        intonationScore = clampScore(Int((ratioScore * 0.45 + tuningScore * 0.40 + coverageScore * 0.15).rounded()))
        intonationConsistency = clampScore(Int((100.0 - std * 1.8).rounded()))

        if !intonationPassed {
            statusMessage = L10n.f(
                "Need clearer scale capture: >=%@ samples, >=%@%% in-scale, >=%@ tones.",
                "\(minIntonationSamples)",
                "\(Int((minInScaleRatio * 100).rounded()))",
                "\(minUniqueScaleTones)"
            )
            phase = .ready
            return
        }

        phase = .rhythm
        statusMessage = "Intonation captured. Continue to rhythm."
    }

    private func startRhythm() {
        guard intonationPassed else {
            statusMessage = "Complete intonation first."
            return
        }
        if rhythmBPM < minimumRhythmBPM {
            rhythmBPM = minimumRhythmBPM
        }
        phase = .rhythm
        finalMetrics = nil
        rhythmRunning = true
        rhythmEngine.stop(clear: true)
        metronome.setBPM(rhythmBPM)
        metronome.start(beatsPerBar: 4, subdivision: .none, soundStyle: (MetronomeEngine.SoundStyle(rawValue: JourneyProgressManager.preferredMetronomeSoundStyleRaw() ?? "click") ?? .click))
        rhythmEngine.start(bpm: rhythmBPM, targetBeats: rhythmTargetBeats)
    }

    private func stopRhythm() {
        rhythmRunning = false
        metronome.stop()
        rhythmEngine.stop(clear: false)
        if let summary = rhythmEngine.summary {
            buildFinalMetrics(rhythmSummary: summary)
        } else {
            statusMessage = "Rhythm capture too short. Try again."
        }
    }

    private func buildFinalMetrics(rhythmSummary: RhythmAccuracySummary) {
        guard intonationPassed else { return }
        guard rhythmSummary.beatsAnalyzed > 0 else { return }

        let rhythmScore = clampScore(rhythmSummary.grooveScore)
        let timingConsistency = clampScore(Int((100.0 - min(100.0, abs(rhythmSummary.averageOffsetMs))).rounded()))
        let combinedConsistency = clampScore(Int((Double(intonationConsistency) * 0.6 + Double(timingConsistency) * 0.4).rounded()))

        finalMetrics = DuelDerivedMetrics(
            intonationScore: intonationScore,
            rhythmScore: rhythmScore,
            consistencyScore: combinedConsistency,
            noteCount: max(1, aggregate.inScaleSamples),
            beatsAnalyzed: max(1, rhythmSummary.beatsAnalyzed),
            tempoBPM: rhythmBPM
        )
        phase = .complete
        statusMessage = "Duel take ready. Use this take to submit."
    }

    private func scalePitchClasses(for descriptor: String) -> Set<Int> {
        let raw = descriptor.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let isMelodicMinor = lower.contains("melodic minor")
        let rootToken = raw.split(separator: " ").first.map(String.init) ?? "C"
        guard let rootClass = pitchClass(for: rootToken) else {
            return [0, 2, 4, 5, 7, 9, 11]
        }
        let intervals = isMelodicMinor ? [0, 2, 3, 5, 7, 9, 11] : [0, 2, 4, 5, 7, 9, 11]
        return Set(intervals.map { positiveModulo(rootClass + $0, 12) })
    }

    private func pitchClass(for note: String) -> Int? {
        switch note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "c", "b#": return 0
        case "c#", "db": return 1
        case "d": return 2
        case "d#", "eb": return 3
        case "e", "fb": return 4
        case "f", "e#": return 5
        case "f#", "gb": return 6
        case "g": return 7
        case "g#", "ab": return 8
        case "a": return 9
        case "a#", "bb": return 10
        case "b", "cb": return 11
        default: return nil
        }
    }

    private func noteName(for pitchClass: Int) -> String {
        switch positiveModulo(pitchClass, 12) {
        case 0: return "C"
        case 1: return "C#/Db"
        case 2: return "D"
        case 3: return "D#/Eb"
        case 4: return "E"
        case 5: return "F"
        case 6: return "F#/Gb"
        case 7: return "G"
        case 8: return "G#/Ab"
        case 9: return "A"
        case 10: return "A#/Bb"
        default: return "B"
        }
    }

    private func nearestAllowedCentsDelta(for midi: Double) -> Double {
        let center = Int(midi.rounded())
        var best = Double.greatestFiniteMagnitude
        for candidate in (center - 24)...(center + 24) {
            let pc = positiveModulo(candidate, 12)
            guard allowedPitchClasses.contains(pc) else { continue }
            let delta = (midi - Double(candidate)) * 100.0
            if abs(delta) < abs(best) {
                best = delta
            }
        }
        if best.isFinite { return best }
        return 0
    }

    private func stopAllCapture() {
        intonationRunning = false
        rhythmRunning = false
        preRollStartedAt = nil
        preRollSeconds = 0
        intonationStartedAt = nil
        tuner.stopListening()
        rhythmEngine.stop(clear: false)
        metronome.stop()
    }

    private func positiveModulo(_ value: Int, _ modulo: Int) -> Int {
        let r = value % modulo
        return r >= 0 ? r : (r + modulo)
    }

    private func clampScore(_ value: Int) -> Int {
        min(100, max(0, value))
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }
}
