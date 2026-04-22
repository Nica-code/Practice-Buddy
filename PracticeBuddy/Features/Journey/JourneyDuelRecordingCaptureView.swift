import SwiftUI
import Combine

struct DuelRecordingCaptureView: View {
    let challenge: DuelChallenge
    let onComplete: (DuelDerivedMetrics) -> Void

    private enum Phase {
        case ready
        case preRoll
        case recording
        case complete
    }

    private struct IntonationAggregate {
        var totalSamples: Int = 0
        var inScaleSamples: Int = 0
        var inScaleCents: [Double] = []
        var inScalePitchClasses: Set<Int> = []
    }

    private struct LayoutTuning {
        let verticalSpacing: CGFloat
        let horizontalPadding: CGFloat
        let topPadding: CGFloat
        let bottomPadding: CGFloat
        let cardPadding: CGFloat
        let overlayNumberSize: CGFloat
        let maxContentWidth: CGFloat?
        let compactMetrics: Bool
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
    @State private var recordingStartedAt: Date?
    @State private var aggregate = IntonationAggregate()
    @State private var intonationScore: Int = 0
    @State private var intonationConsistency: Int = 0
    @State private var rhythmBPM: Int = 72
    @State private var statusMessage: String?
    @State private var finalMetrics: DuelDerivedMetrics?

    private let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    private var takeDuration: TimeInterval {
        switch challenge.octaveCount {
        case 3: return 50
        case 2: return 36
        default: return 24
        }
    }

    private var rhythmTargetBeats: Int {
        switch challenge.octaveCount {
        case 3: return 32
        case 2: return 24
        default: return 16
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

    private var strictnessLabel: String {
        switch challengeLeagueTier.difficultyRank {
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

    var body: some View {
        GeometryReader { proxy in
            let layout = layoutTuning(for: proxy.size)
            ZStack {
                PBBackdropView(palette: palette)
                    .ignoresSafeArea()

                VStack(spacing: layout.verticalSpacing) {
                    objectiveCard(layout)
                    captureStatusCard(layout)
                    liveMetricsCard(layout)
                    Spacer(minLength: 0)
                    actionFooter
                }
                .frame(maxWidth: layout.maxContentWidth ?? .infinity)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, layout.topPadding)
                .padding(.bottom, layout.bottomPadding)

                if phase == .preRoll {
                    preRollOverlay(layout)
                        .transition(.opacity)
                }
            }
        }
        .navigationTitle("Record Duel Take")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { _ in
            captureTick()
        }
        .onDisappear {
            stopAllCapture()
        }
    }

    private func layoutTuning(for size: CGSize) -> LayoutTuning {
        let h = size.height
        let w = size.width
        if h < 700 {
            return LayoutTuning(
                verticalSpacing: 8,
                horizontalPadding: PBLayout.padSM,
                topPadding: 6,
                bottomPadding: 8,
                cardPadding: PBLayout.padSM,
                overlayNumberSize: 76,
                maxContentWidth: nil,
                compactMetrics: true
            )
        }
        if h > 900 || w >= 430 {
            return LayoutTuning(
                verticalSpacing: 12,
                horizontalPadding: PBLayout.padMD,
                topPadding: 12,
                bottomPadding: 12,
                cardPadding: PBLayout.padLG,
                overlayNumberSize: 108,
                maxContentWidth: 560,
                compactMetrics: false
            )
        }
        return LayoutTuning(
            verticalSpacing: 10,
            horizontalPadding: PBLayout.padSM,
            topPadding: 10,
            bottomPadding: 10,
            cardPadding: PBLayout.padMD,
            overlayNumberSize: 96,
            maxContentWidth: 520,
            compactMetrics: false
        )
    }

    private func objectiveCard(_ layout: LayoutTuning) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(challenge.objective)
                .font(type.body.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text("Scale: \(allowedPitchNamesText)")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
            Text("Mode: \(strictnessLabel) • Combined pitch + rhythm take")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(layout.cardPadding)
        .pbModernCard(palette: palette)
    }

    private func captureStatusCard(_ layout: LayoutTuning) -> some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tempo")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Text("\(rhythmBPM) BPM")
                        .font(type.number)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(phaseTitle)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Text(phaseValue)
                        .font(type.number)
                        .foregroundStyle(palette.accent)
                        .monospacedDigit()
                }
            }

            Stepper(L10n.f("Tempo: %@ BPM", "\(rhythmBPM)"), value: $rhythmBPM, in: minimumRhythmBPM...220)
                .font(type.body)
                .disabled(phase == .preRoll || phase == .recording)
        }
        .padding(layout.cardPadding)
        .pbModernCard(palette: palette)
    }

    private func liveMetricsCard(_ layout: LayoutTuning) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if layout.compactMetrics {
                VStack(spacing: 6) {
                    HStack {
                        metricChip(title: "Detected", value: tuner.detectedNoteName)
                        metricChip(title: "Samples", value: "\(aggregate.totalSamples)")
                    }
                    HStack {
                        metricChip(title: "In-scale", value: "\(Int((inScaleRatio * 100).rounded()))%")
                        metricChip(title: "Unique tones", value: "\(aggregate.inScalePitchClasses.count)")
                    }
                }
            } else {
                HStack {
                    metricChip(title: "Detected", value: tuner.detectedNoteName)
                    metricChip(title: "Samples", value: "\(aggregate.totalSamples)")
                }
                HStack {
                    metricChip(title: "In-scale", value: "\(Int((inScaleRatio * 100).rounded()))%")
                    metricChip(title: "Unique tones", value: "\(aggregate.inScalePitchClasses.count)")
                }
            }

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
            } else if phase == .recording {
                Text("Listening…")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }

            if let finalMetrics {
                Divider().overlay(palette.textSecondary.opacity(0.25))
                Text(
                    L10n.f(
                        "Derived %@ (I %@ • R %@ • C %@)",
                        "\(finalMetrics.derivedScore)",
                        "\(finalMetrics.intonationScore)",
                        "\(finalMetrics.rhythmScore)",
                        "\(finalMetrics.consistencyScore)"
                    )
                )
                .font(type.body.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            } else if phase == .complete && aggregate.totalSamples > 0 {
                Text("Intonation \(intonationScore) • Consistency \(intonationConsistency)")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(layout.cardPadding)
        .pbModernCard(palette: palette)
    }

    private var actionFooter: some View {
        VStack(spacing: 8) {
            if let finalMetrics {
                Button("Submit Take") {
                    onComplete(finalMetrics)
                    dismiss()
                }
                .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
            } else {
                Button(phase == .preRoll || phase == .recording ? "Stop Recording" : "Record") {
                    if phase == .preRoll || phase == .recording {
                        stopRecordingAndFinalize()
                    } else {
                        startCombinedRecordingWithPreRoll()
                    }
                }
                .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
                .disabled(!(phase == .ready || phase == .complete || phase == .preRoll || phase == .recording))
            }
        }
    }

    private func preRollOverlay(_ layout: LayoutTuning) -> some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                Text(preRollSeconds > 0 ? "\(preRollSeconds)" : "Start")
                    .font(.system(size: layout.overlayNumberSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("Get ready")
                    .font(type.body)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .ready: return "Status"
        case .preRoll: return "Countdown"
        case .recording: return "Remaining"
        case .complete: return "Status"
        }
    }

    private var phaseValue: String {
        switch phase {
        case .ready: return "Ready"
        case .preRoll: return preRollSeconds > 0 ? "\(preRollSeconds)" : "Start"
        case .recording:
            let remaining = max(0, Int((takeDuration - Date().timeIntervalSince(recordingStartedAt ?? .now)).rounded()))
            return "\(remaining)s"
        case .complete: return "Take Ready"
        }
    }

    private func metricChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
            Text(value)
                .font(type.body.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .pbSurfaceCard(palette: palette)
    }

    private func startCombinedRecordingWithPreRoll() {
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

    private func startCombinedCaptureNow() {
        preRollStartedAt = nil
        preRollSeconds = 0
        recordingStartedAt = Date()
        phase = .recording

        if rhythmBPM < minimumRhythmBPM {
            rhythmBPM = minimumRhythmBPM
        }

        rhythmEngine.stop(clear: true)
        metronome.setBPM(rhythmBPM)
        metronome.start(
            beatsPerBar: 4,
            subdivision: .none,
            soundStyle: (MetronomeEngine.SoundStyle(rawValue: JourneyProgressManager.preferredMetronomeSoundStyleRaw() ?? "click") ?? .click)
        )
        rhythmEngine.start(bpm: rhythmBPM, targetBeats: rhythmTargetBeats)
    }

    private func stopRecordingAndFinalize() {
        stopAllCapture()
        finalizeCombinedTake()
    }

    private func captureTick() {
        if phase == .preRoll, let started = preRollStartedAt {
            let elapsed = Date().timeIntervalSince(started)
            let remaining = max(0, Int(ceil(5.0 - elapsed)))
            preRollSeconds = remaining
            if elapsed >= 5.0 {
                startCombinedCaptureNow()
            }
            return
        }

        guard phase == .recording else { return }
        guard let started = recordingStartedAt else { return }

        if let frequency = tuner.detectedFrequency, tuner.inputLevel > 0.003 {
            registerFrequency(frequency)
        }

        if Date().timeIntervalSince(started) >= takeDuration {
            stopRecordingAndFinalize()
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

    private func finalizeCombinedTake() {
        guard aggregate.totalSamples > 0 else {
            statusMessage = "No usable signal captured. Try again."
            return
        }

        let cents = aggregate.inScaleCents
        let meanAbs: Double = {
            guard !cents.isEmpty else { return 100.0 }
            return cents.map { abs($0) }.reduce(0, +) / Double(cents.count)
        }()
        let std = cents.isEmpty ? 45.0 : standardDeviation(cents)

        let ratioScore = inScaleRatio * 100.0
        let tuningScore = max(0.0, 100.0 - meanAbs * 2.0)
        let coverageScore = (Double(aggregate.inScalePitchClasses.count) / Double(max(1, allowedPitchClasses.count))) * 100.0

        intonationScore = clampScore(Int((ratioScore * 0.45 + tuningScore * 0.40 + coverageScore * 0.15).rounded()))
        intonationConsistency = clampScore(Int((100.0 - std * 1.8).rounded()))

        let rhythmSummary = rhythmEngine.summary
        let averageOffsetMs = abs(rhythmSummary?.averageOffsetMs ?? 0)
        let rawRhythmScore = clampScore(rhythmSummary?.grooveScore ?? 70)
        let beatsAnalyzed = max(1, rhythmSummary?.beatsAnalyzed ?? Int((takeDuration / 60.0) * Double(max(rhythmBPM, 40)) * 0.25))
        let beatCoverage = min(1.0, Double(beatsAnalyzed) / Double(max(1, rhythmTargetBeats)))

        let rhythmScore = adjustedRhythmScore(
            rawScore: rawRhythmScore,
            averageOffsetMs: averageOffsetMs,
            beatCoverage: beatCoverage
        )
        let timingConsistency = adjustedTimingConsistencyScore(
            averageOffsetMs: averageOffsetMs,
            beatCoverage: beatCoverage
        )
        let combinedConsistency = clampScore(Int((Double(intonationConsistency) * 0.6 + Double(timingConsistency) * 0.4).rounded()))
        let noteCount = max(1, aggregate.inScaleSamples > 0 ? aggregate.inScaleSamples : aggregate.totalSamples)

        finalMetrics = DuelDerivedMetrics(
            intonationScore: intonationScore,
            rhythmScore: rhythmScore,
            consistencyScore: combinedConsistency,
            noteCount: noteCount,
            beatsAnalyzed: beatsAnalyzed,
            tempoBPM: rhythmBPM
        )
        phase = .complete
        statusMessage = "Duel take ready. Submit Take when ready."
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
        preRollStartedAt = nil
        preRollSeconds = 0
        recordingStartedAt = nil
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

    private func adjustedRhythmScore(rawScore: Int, averageOffsetMs: Double, beatCoverage: Double) -> Int {
        let normalizedScore = normalizedRhythmScore(for: averageOffsetMs, tier: challengeLeagueTier)
        let blend = rhythmBlend(for: challengeLeagueTier)
        var score = Int((Double(rawScore) * blend.raw + Double(normalizedScore) * blend.normalized).rounded())
        score += rhythmCoverageAdjustment(for: beatCoverage, tier: challengeLeagueTier)

        if beatCoverage >= 0.65 {
            score = max(score, beginnerRhythmFloor(for: challengeLeagueTier))
        }
        if beatCoverage < 0.45 {
            score = min(score, challengeLeagueTier.difficultyRank >= DuelLeagueTier.diamond.difficultyRank ? 52 : 58)
        }
        return clampScore(score)
    }

    private func adjustedTimingConsistencyScore(averageOffsetMs: Double, beatCoverage: Double) -> Int {
        let windowMs = timingConsistencyWindowMs(for: challengeLeagueTier)
        var score = Int((100.0 - min(100.0, (averageOffsetMs / windowMs) * 100.0)).rounded())
        if beatCoverage < 0.45 {
            score -= challengeLeagueTier.difficultyRank >= DuelLeagueTier.diamond.difficultyRank ? 16 : 10
        } else if beatCoverage < 0.60 {
            score -= 6
        }
        return clampScore(score)
    }

    private func normalizedRhythmScore(for averageOffsetMs: Double, tier: DuelLeagueTier) -> Int {
        let windowMs = rhythmWindowMs(for: tier)
        let score = Int((100.0 - min(100.0, (averageOffsetMs / windowMs) * 100.0)).rounded())
        return clampScore(score)
    }

    private func rhythmWindowMs(for tier: DuelLeagueTier) -> Double {
        switch tier {
        case .bronze: return 120
        case .silver: return 110
        case .gold: return 100
        case .platinum: return 90
        case .emerald: return 82
        case .diamond: return 76
        case .master: return 72
        case .grandmaster: return 68
        }
    }

    private func timingConsistencyWindowMs(for tier: DuelLeagueTier) -> Double {
        switch tier {
        case .bronze: return 155
        case .silver: return 145
        case .gold: return 135
        case .platinum: return 125
        case .emerald: return 115
        case .diamond: return 105
        case .master: return 98
        case .grandmaster: return 92
        }
    }

    private func rhythmBlend(for tier: DuelLeagueTier) -> (raw: Double, normalized: Double) {
        switch tier {
        case .bronze: return (0.45, 0.55)
        case .silver: return (0.50, 0.50)
        case .gold: return (0.56, 0.44)
        case .platinum: return (0.62, 0.38)
        case .emerald: return (0.68, 0.32)
        case .diamond: return (0.72, 0.28)
        case .master: return (0.75, 0.25)
        case .grandmaster: return (0.78, 0.22)
        }
    }

    private func rhythmCoverageAdjustment(for beatCoverage: Double, tier: DuelLeagueTier) -> Int {
        let base: Int
        switch beatCoverage {
        case 0.90...:
            base = 3
        case 0.75..<0.90:
            base = 1
        case 0.60..<0.75:
            base = 0
        case 0.45..<0.60:
            base = -6
        default:
            base = -12
        }
        if tier.difficultyRank >= DuelLeagueTier.diamond.difficultyRank, beatCoverage < 0.60 {
            return base - 4
        }
        return base
    }

    private func beginnerRhythmFloor(for tier: DuelLeagueTier) -> Int {
        switch tier {
        case .bronze: return 34
        case .silver: return 30
        default: return 0
        }
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }
}
