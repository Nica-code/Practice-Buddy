import Foundation

enum IntonationExerciseType: String, Codable, CaseIterable, Identifiable {
    case oneOctaveScale
    case twoOctaveScale
    case arpeggio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneOctaveScale: "One-octave scale"
        case .twoOctaveScale: "Two-octave scale"
        case .arpeggio: "Arpeggio"
        }
    }
}

enum IntonationScaleMode: String, Codable, CaseIterable, Identifiable {
    case major
    case minor

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum IntonationKeyRoot: String, Codable, CaseIterable, Identifiable {
    case c = "C"
    case g = "G"
    case d = "D"
    case a = "A"
    case e = "E"
    case b = "B"
    case fSharp = "F#"
    case bFlat = "Bb"
    case f = "F"
    case eFlat = "Eb"

    var id: String { rawValue }

    var semitoneFromC: Int {
        switch self {
        case .c: 0
        case .g: 7
        case .d: 2
        case .a: 9
        case .e: 4
        case .b: 11
        case .fSharp: 6
        case .bFlat: 10
        case .f: 5
        case .eFlat: 3
        }
    }
}

enum IntonationOctavePreset: Int, Codable, CaseIterable, Identifiable {
    case low = 3
    case middle = 4

    var id: Int { rawValue }
    var title: String { self == .low ? "Low register" : "Middle register" }
}

struct IntonationSettings: Codable, Equatable {
    var exercise: IntonationExerciseType
    var mode: IntonationScaleMode
    var key: IntonationKeyRoot
    var octave: IntonationOctavePreset
    var tempoBPM: Int
    var referenceHz: Int

    init(
        exercise: IntonationExerciseType,
        mode: IntonationScaleMode,
        key: IntonationKeyRoot,
        octave: IntonationOctavePreset,
        tempoBPM: Int,
        referenceHz: Int
    ) {
        self.exercise = exercise
        self.mode = mode
        self.key = key
        self.octave = octave
        self.tempoBPM = min(max(tempoBPM, 40), 180)
        self.referenceHz = min(max(referenceHz, 415), 442)
    }

    var noteDuration: TimeInterval {
        max(0.6, 60 / Double(tempoBPM))
    }
}

struct IntonationTargetNote: Codable, Equatable, Identifiable {
    let index: Int
    let name: String
    let degree: Int
    let frequency: Double
    let isDescending: Bool

    var id: Int { index }
}

struct IntonationPitchSample: Codable, Equatable {
    let cents: Double
    let timeInNote: TimeInterval
}

struct IntonationNoteScore: Codable, Equatable, Identifiable {
    let index: Int
    let noteName: String
    let degree: Int
    let meanOffsetCents: Double
    let centeringScore: Double
    let stabilityScore: Double
    let sampleCount: Int

    var id: Int { index }
}

struct IntonationTakeResult: Codable, Equatable {
    let overallScore: Int
    let centeringScore: Double
    let stabilityScore: Double
    let consistencyScore: Double
    let meanOffsetCents: Double
    let signalCoverage: Double
    let noteScores: [IntonationNoteScore]
    let recommendations: [String]
}

enum IntonationPhase: String, Codable, Equatable {
    case setup
    case countIn
    case listening
    case paused
    case result
    case insufficientSignal
    case failed
}

struct IntonationRunState: Codable, Equatable {
    var settings: IntonationSettings
    var targets: [IntonationTargetNote]
    var phase: IntonationPhase = .setup
    var phaseStartedAt: Date?
    var accumulatedDuration: TimeInterval = 0
    var currentNoteIndex = 0
    var samples: [[IntonationPitchSample]]
    var result: IntonationTakeResult?
    var failureMessage: String?

    init(settings: IntonationSettings) {
        self.settings = settings
        targets = IntonationTargetBuilder.targets(for: settings)
        samples = Array(repeating: [], count: targets.count)
    }

    var progress: Double {
        guard !targets.isEmpty else { return 0 }
        return min(1, Double(currentNoteIndex) / Double(targets.count))
    }

    func elapsedSeconds(at date: Date = .now) -> Int {
        Int(elapsedDuration(at: date))
    }

    func elapsedDuration(at date: Date = .now) -> TimeInterval {
        guard phase == .listening, let phaseStartedAt else {
            return accumulatedDuration
        }
        return accumulatedDuration + max(0, date.timeIntervalSince(phaseStartedAt))
    }

    mutating func beginCountIn() {
        phase = .countIn
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
        accumulatedDuration = elapsedDuration(at: date)
        phaseStartedAt = nil
        phase = .paused
    }

    mutating func register(
        frequency: Double,
        inputLevel: Double,
        at date: Date = .now
    ) {
        guard phase == .listening,
              inputLevel > 0.002,
              targets.indices.contains(currentNoteIndex),
              frequency > 0,
              let phaseStartedAt else { return }
        let target = targets[currentNoteIndex]
        let cents = 1_200 * log2(frequency / target.frequency)
        guard abs(cents) <= 200 else { return }
        let time = max(0, date.timeIntervalSince(phaseStartedAt))
        samples[currentNoteIndex].append(
            IntonationPitchSample(cents: cents, timeInNote: time)
        )
    }

    mutating func advanceNote(at date: Date = .now) {
        guard phase == .listening, let phaseStartedAt else { return }
        if currentNoteIndex + 1 < targets.count {
            accumulatedDuration += max(0, date.timeIntervalSince(phaseStartedAt))
            currentNoteIndex += 1
            self.phaseStartedAt = date
        } else {
            finish(at: date)
        }
    }

    mutating func finish(at date: Date = .now) {
        if phase == .listening {
            accumulatedDuration = elapsedDuration(at: date)
        }
        phaseStartedAt = nil
        let scored = IntonationScorer.score(targets: targets, samples: samples)
        result = scored
        phase = scored.signalCoverage >= IntonationScorer.minimumSignalCoverage
            ? .result
            : .insufficientSignal
    }

    mutating func fail(_ message: String, at date: Date = .now) {
        if phase == .listening {
            accumulatedDuration = elapsedDuration(at: date)
        }
        phaseStartedAt = nil
        failureMessage = message
        phase = .failed
    }
}

enum IntonationTargetBuilder {
    static func targets(for settings: IntonationSettings) -> [IntonationTargetNote] {
        let ascending: [(offset: Int, degree: Int)]
        switch settings.exercise {
        case .oneOctaveScale:
            let offsets = settings.mode == .major
                ? [0, 2, 4, 5, 7, 9, 11, 12]
                : [0, 2, 3, 5, 7, 8, 10, 12]
            ascending = zip(offsets, [1, 2, 3, 4, 5, 6, 7, 1]).map { ($0, $1) }
        case .twoOctaveScale:
            let offsets = settings.mode == .major
                ? [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24]
                : [0, 2, 3, 5, 7, 8, 10, 12, 14, 15, 17, 19, 20, 22, 24]
            let degrees = [1, 2, 3, 4, 5, 6, 7, 1, 2, 3, 4, 5, 6, 7, 1]
            ascending = zip(offsets, degrees).map { ($0, $1) }
        case .arpeggio:
            let offsets = settings.mode == .major
                ? [0, 4, 7, 12]
                : [0, 3, 7, 12]
            ascending = zip(offsets, [1, 3, 5, 1]).map { ($0, $1) }
        }

        let sequence = ascending.enumerated().map {
            (offset: $0.element.offset, degree: $0.element.degree, descending: false)
        } + ascending.dropLast().reversed().map {
            (offset: $0.offset, degree: $0.degree, descending: true)
        }
        let rootMIDI = 12 * (settings.octave.rawValue + 1)
            + settings.key.semitoneFromC
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

        return sequence.enumerated().map { index, item in
            let midi = rootMIDI + item.offset
            let noteIndex = (midi % 12 + 12) % 12
            let octave = midi / 12 - 1
            let frequency = Double(settings.referenceHz)
                * pow(2, Double(midi - 69) / 12)
            return IntonationTargetNote(
                index: index,
                name: "\(names[noteIndex])\(octave)",
                degree: item.degree,
                frequency: frequency,
                isDescending: item.descending
            )
        }
    }
}

enum IntonationScorer {
    static let minimumSignalCoverage = 0.4

    static func score(
        targets: [IntonationTargetNote],
        samples: [[IntonationPitchSample]]
    ) -> IntonationTakeResult {
        var notes: [IntonationNoteScore] = []
        for (index, target) in targets.enumerated() {
            let raw = samples.indices.contains(index) ? samples[index] : []
            let settled = raw.filter { $0.timeInNote >= 0.18 }
            let usable = settled.count >= 3 ? settled : raw
            let values = usable.map(\.cents)
            guard !values.isEmpty else {
                notes.append(
                    IntonationNoteScore(
                        index: index,
                        noteName: target.name,
                        degree: target.degree,
                        meanOffsetCents: 0,
                        centeringScore: 0,
                        stabilityScore: 0,
                        sampleCount: 0
                    )
                )
                continue
            }
            let mean = values.reduce(0, +) / Double(values.count)
            let centered = Double(values.filter { abs($0) <= 10 }.count)
                / Double(values.count) * 100
            let stability = max(0, 100 - standardDeviation(values) * 2.2)
            notes.append(
                IntonationNoteScore(
                    index: index,
                    noteName: target.name,
                    degree: target.degree,
                    meanOffsetCents: mean,
                    centeringScore: centered,
                    stabilityScore: stability,
                    sampleCount: values.count
                )
            )
        }

        let heard = notes.filter { $0.sampleCount > 0 }
        let coverage = targets.isEmpty ? 0 : Double(heard.count) / Double(targets.count)
        let centering = average(heard.map(\.centeringScore))
        let stability = average(heard.map(\.stabilityScore))
        let meanOffset = average(heard.map(\.meanOffsetCents))
        let degreeGroups = Dictionary(grouping: heard, by: \.degree)
        let repeatedDegreeDeviation = degreeGroups.values
            .filter { $0.count > 1 }
            .map { standardDeviation($0.map(\.meanOffsetCents)) }
        let consistency: Double
        if repeatedDegreeDeviation.isEmpty {
            consistency = heard.count > 1 ? 80 : 0
        } else {
            consistency = max(0, 100 - average(repeatedDegreeDeviation) * 2)
        }
        let accuracy = max(0, 100 - abs(meanOffset) * 2.5)
        let overall = Int(
            (centering * 0.4 + stability * 0.25 + accuracy * 0.2 + consistency * 0.15)
                .rounded()
        )

        let recommendations = heard
            .sorted { abs($0.meanOffsetCents) > abs($1.meanOffsetCents) }
            .prefix(2)
            .map { note in
                "\(note.noteName) (degree \(note.degree)) trends \(note.meanOffsetCents >= 0 ? "sharp" : "flat"). Prepare the pitch before increasing the tempo."
            }

        return IntonationTakeResult(
            overallScore: min(max(overall, 0), 100),
            centeringScore: centering,
            stabilityScore: stability,
            consistencyScore: consistency,
            meanOffsetCents: meanOffset,
            signalCoverage: coverage,
            noteScores: notes,
            recommendations: recommendations.isEmpty
                ? ["No stable pitch signal was captured. Move closer and sustain each note."]
                : recommendations
        )
    }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = average(values)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) }
            / Double(values.count)
        return sqrt(variance)
    }
}

struct IntonationResultPayload: Codable, Equatable {
    let completedAt: Date
    let durationSeconds: Int
    let settings: IntonationSettings
    let result: IntonationTakeResult
    let parentSessionID: UUID?
    let launchSource: PracticeLaunchSource
    let toolVersion: Int
}
