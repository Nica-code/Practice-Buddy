import Foundation

enum RhythmPulseMode: String, Codable, CaseIterable, Equatable {
    case visualHaptic
    case audibleHeadphones
}

struct RhythmAccuracySettings: Codable, Equatable {
    var bpm: Int
    var targetBeats: Int
    var pulseMode: RhythmPulseMode

    init(
        bpm: Int,
        targetBeats: Int,
        pulseMode: RhythmPulseMode
    ) {
        self.bpm = min(max(bpm, 40), 220)
        self.targetBeats = min(max(targetBeats, 8), 128)
        self.pulseMode = pulseMode
    }

    var beatInterval: TimeInterval {
        60 / Double(bpm)
    }
}

enum RhythmTakePhase: String, Codable, Equatable {
    case idle
    case calibrating
    case countIn
    case listening
    case paused
    case result
    case insufficientInput
    case failed
}

enum RhythmTimingTendency: String, Codable, Equatable {
    case centered
    case early
    case late
    case mixed
}

struct RhythmWindowStat: Codable, Equatable, Identifiable {
    let index: Int
    let averageOffsetMs: Double
    let averageAbsoluteOffsetMs: Double
    let sampleCount: Int

    var id: Int { index }
}

struct RhythmAccuracySummary: Codable, Equatable {
    let beatsAnalyzed: Int
    let averageOffsetMs: Double
    let averageAbsoluteOffsetMs: Double
    let standardDeviationMs: Double
    let grooveScore: Int
    let earlyCount: Int
    let centeredCount: Int
    let lateCount: Int
    let tendency: RhythmTimingTendency
    let windowStats: [RhythmWindowStat]
}

struct RhythmAccuracyRunState: Codable, Equatable {
    var settings: RhythmAccuracySettings
    var phase: RhythmTakePhase
    var phaseStartedAt: Date?
    var accumulatedSeconds: Int
    var offsetsMs: [Double]
    var latestOffsetMs: Double?
    var summary: RhythmAccuracySummary?
    var failureMessage: String?

    init(settings: RhythmAccuracySettings) {
        self.settings = settings
        phase = .idle
        phaseStartedAt = nil
        accumulatedSeconds = 0
        offsetsMs = []
        latestOffsetMs = nil
        summary = nil
        failureMessage = nil
    }

    var beatsAnalyzed: Int {
        offsetsMs.count
    }

    var progress: Double {
        guard settings.targetBeats > 0 else { return 0 }
        return min(1, Double(beatsAnalyzed) / Double(settings.targetBeats))
    }

    func elapsedSeconds(at date: Date = .now) -> Int {
        guard phase == .listening, let phaseStartedAt else {
            return accumulatedSeconds
        }
        return accumulatedSeconds
            + max(0, Int(date.timeIntervalSince(phaseStartedAt)))
    }

    mutating func beginCalibration() {
        phase = .calibrating
        phaseStartedAt = nil
        accumulatedSeconds = 0
        offsetsMs = []
        latestOffsetMs = nil
        summary = nil
        failureMessage = nil
    }

    mutating func beginCountIn() {
        phase = .countIn
        phaseStartedAt = nil
    }

    mutating func beginResumeCalibration() {
        phase = .calibrating
        phaseStartedAt = nil
        failureMessage = nil
    }

    mutating func beginListening(at date: Date = .now) {
        phase = .listening
        phaseStartedAt = date
        failureMessage = nil
    }

    mutating func pause(at date: Date = .now) {
        guard phase == .listening else { return }
        accumulatedSeconds = elapsedSeconds(at: date)
        phaseStartedAt = nil
        phase = .paused
    }

    mutating func register(offsetMilliseconds: Double) {
        guard phase == .listening else { return }
        let clamped = min(max(offsetMilliseconds, -500), 500)
        offsetsMs.append(clamped)
        latestOffsetMs = clamped
        if offsetsMs.count >= settings.targetBeats {
            finish()
        }
    }

    mutating func finish(at date: Date = .now) {
        if phase == .listening {
            accumulatedSeconds = elapsedSeconds(at: date)
        }
        phaseStartedAt = nil
        guard offsetsMs.count >= RhythmAccuracyScorer.minimumMeaningfulOnsets else {
            phase = .insufficientInput
            summary = nil
            return
        }
        summary = RhythmAccuracyScorer.summary(for: offsetsMs)
        phase = .result
    }

    mutating func fail(_ message: String, at date: Date = .now) {
        if phase == .listening {
            accumulatedSeconds = elapsedSeconds(at: date)
        }
        phaseStartedAt = nil
        failureMessage = message
        phase = .failed
    }
}

enum RhythmAccuracyScorer {
    static let minimumMeaningfulOnsets = 4
    static let centeredToleranceMs = 30.0

    static func offsetMilliseconds(
        onsetHostSeconds: TimeInterval,
        gridAnchorHostSeconds: TimeInterval,
        beatInterval: TimeInterval
    ) -> Double? {
        guard beatInterval > 0 else { return nil }
        let elapsed = onsetHostSeconds - gridAnchorHostSeconds
        guard elapsed >= 0 else { return nil }
        let nearestBeat = round(elapsed / beatInterval)
        let expected = nearestBeat * beatInterval
        return (elapsed - expected) * 1_000
    }

    static func summary(for offsets: [Double]) -> RhythmAccuracySummary {
        guard !offsets.isEmpty else {
            return RhythmAccuracySummary(
                beatsAnalyzed: 0,
                averageOffsetMs: 0,
                averageAbsoluteOffsetMs: 0,
                standardDeviationMs: 0,
                grooveScore: 0,
                earlyCount: 0,
                centeredCount: 0,
                lateCount: 0,
                tendency: .mixed,
                windowStats: []
            )
        }

        let count = Double(offsets.count)
        let average = offsets.reduce(0, +) / count
        let averageAbsolute = offsets.map(abs).reduce(0, +) / count
        let variance = offsets
            .map { pow($0 - average, 2) }
            .reduce(0, +) / count
        let deviation = sqrt(variance)
        let early = offsets.filter { $0 < -centeredToleranceMs }.count
        let late = offsets.filter { $0 > centeredToleranceMs }.count
        let centered = offsets.count - early - late

        let tendency: RhythmTimingTendency
        if abs(average) <= centeredToleranceMs / 2, centered >= max(1, offsets.count / 2) {
            tendency = .centered
        } else if average < -centeredToleranceMs / 2, early > late {
            tendency = .early
        } else if average > centeredToleranceMs / 2, late > early {
            tendency = .late
        } else {
            tendency = .mixed
        }

        let accuracyPenalty = min(70, averageAbsolute * 0.72)
        let stabilityPenalty = min(30, deviation * 0.30)
        let score = Int(round(max(0, 100 - accuracyPenalty - stabilityPenalty)))

        var windows: [RhythmWindowStat] = []
        for start in stride(from: 0, to: offsets.count, by: 8) {
            let end = min(start + 8, offsets.count)
            let values = Array(offsets[start..<end])
            let valueCount = Double(values.count)
            windows.append(
                RhythmWindowStat(
                    index: windows.count,
                    averageOffsetMs: values.reduce(0, +) / valueCount,
                    averageAbsoluteOffsetMs: values.map(abs).reduce(0, +) / valueCount,
                    sampleCount: values.count
                )
            )
        }

        return RhythmAccuracySummary(
            beatsAnalyzed: offsets.count,
            averageOffsetMs: average,
            averageAbsoluteOffsetMs: averageAbsolute,
            standardDeviationMs: deviation,
            grooveScore: score,
            earlyCount: early,
            centeredCount: centered,
            lateCount: late,
            tendency: tendency,
            windowStats: windows
        )
    }
}

struct RhythmOnsetDetector: Equatable {
    var threshold: Float
    var refractorySeconds: TimeInterval
    private(set) var wasAboveThreshold = false
    private(set) var lastOnsetTime = -TimeInterval.greatestFiniteMagnitude

    init(
        threshold: Float = 0.02,
        refractorySeconds: TimeInterval = 0.08
    ) {
        self.threshold = max(0.001, threshold)
        self.refractorySeconds = max(0.02, refractorySeconds)
    }

    mutating func detectOnset(
        samples: [Float],
        at hostSeconds: TimeInterval
    ) -> Bool {
        let peak = samples.reduce(Float.zero) { max($0, abs($1)) }
        let isAbove = peak >= threshold
        let mayTrigger = hostSeconds - lastOnsetTime >= refractorySeconds
        let detected = isAbove && !wasAboveThreshold && mayTrigger
        if detected {
            lastOnsetTime = hostSeconds
        }
        wasAboveThreshold = isAbove
        return detected
    }
}

enum RhythmCalibrationThreshold {
    static func value(from peaks: [Float]) -> Float {
        guard !peaks.isEmpty else { return 0.02 }
        let sorted = peaks.sorted()
        let percentileIndex = min(
            sorted.count - 1,
            Int(Double(sorted.count - 1) * 0.8)
        )
        return min(0.25, max(0.012, sorted[percentileIndex] * 2.5))
    }
}

struct RhythmAccuracyResultPayload: Codable, Equatable {
    let completedAt: Date
    let durationSeconds: Int
    let settings: RhythmAccuracySettings
    let summary: RhythmAccuracySummary
    let parentSessionID: UUID?
    let launchSource: PracticeLaunchSource
    let toolVersion: Int
}
