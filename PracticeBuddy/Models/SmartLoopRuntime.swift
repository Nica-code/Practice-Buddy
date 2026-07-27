import Foundation

struct SmartLoopSettings: Codable, Equatable {
    var loopDurationSeconds: Int
    var restDurationSeconds: Int
    var targetLoops: Int
    var runsUntilStopped: Bool
    var metronomeEnabled: Bool
    var startingTempoBPM: Int
    var autoIncreaseEnabled: Bool
    var autoIncreaseEvery: Int
    var tempoIncreaseBPM: Int
    var tempoLadderEnabled: Bool
    var cleanLoopsRequired: Int

    init(
        loopDurationSeconds: Int,
        restDurationSeconds: Int,
        targetLoops: Int,
        runsUntilStopped: Bool,
        metronomeEnabled: Bool,
        startingTempoBPM: Int,
        autoIncreaseEnabled: Bool,
        autoIncreaseEvery: Int,
        tempoIncreaseBPM: Int,
        tempoLadderEnabled: Bool,
        cleanLoopsRequired: Int
    ) {
        self.loopDurationSeconds = min(max(loopDurationSeconds, 10), 600)
        self.restDurationSeconds = min(max(restDurationSeconds, 0), 180)
        self.targetLoops = min(max(targetLoops, 1), 200)
        self.runsUntilStopped = runsUntilStopped
        self.metronomeEnabled = metronomeEnabled
        self.startingTempoBPM = min(max(startingTempoBPM, 40), 220)
        self.autoIncreaseEnabled = autoIncreaseEnabled
        self.autoIncreaseEvery = min(max(autoIncreaseEvery, 1), 20)
        self.tempoIncreaseBPM = min(max(tempoIncreaseBPM, 1), 10)
        self.tempoLadderEnabled = tempoLadderEnabled
        self.cleanLoopsRequired = min(max(cleanLoopsRequired, 1), 10)
    }
}

enum SmartLoopPhase: String, Codable, Equatable {
    case idle
    case work
    case rest
    case pausedWork
    case pausedRest
    case finished

    var isRunning: Bool {
        self == .work || self == .rest
    }

    var isPaused: Bool {
        self == .pausedWork || self == .pausedRest
    }
}

enum SmartLoopEvent: Equatable {
    case enteredWork
    case enteredRest
    case completedLoop(Int)
    case tempoChanged(Int)
    case finished
}

struct SmartLoopRunState: Codable, Equatable {
    var settings: SmartLoopSettings
    var phase: SmartLoopPhase
    var phaseStartedAt: Date?
    var pausedPhaseElapsed: Int
    var loopsCompleted: Int
    var completedWorkSeconds: Int
    var currentTempoBPM: Int
    var cleanLoopsAtCurrentTempo: Int
    var workCycleIndex: Int
    var markableCompletedCycle: Int?
    var markedCycleIndices: Set<Int>

    init(settings: SmartLoopSettings) {
        self.settings = settings
        phase = .idle
        phaseStartedAt = nil
        pausedPhaseElapsed = 0
        loopsCompleted = 0
        completedWorkSeconds = 0
        currentTempoBPM = settings.startingTempoBPM
        cleanLoopsAtCurrentTempo = 0
        workCycleIndex = 0
        markableCompletedCycle = nil
        markedCycleIndices = []
    }

    var hasMeaningfulResult: Bool {
        loopsCompleted > 0 || completedWorkSeconds >= 10
    }

    func phaseDurationSeconds() -> Int {
        switch phase {
        case .work, .pausedWork:
            settings.loopDurationSeconds
        case .rest, .pausedRest:
            settings.restDurationSeconds
        case .idle, .finished:
            0
        }
    }

    func phaseElapsed(at date: Date = .now) -> Int {
        if phase.isPaused {
            return min(max(0, pausedPhaseElapsed), phaseDurationSeconds())
        }
        guard phase.isRunning, let phaseStartedAt else { return 0 }
        return min(
            max(0, Int(date.timeIntervalSince(phaseStartedAt))),
            phaseDurationSeconds()
        )
    }

    func remainingSeconds(at date: Date = .now) -> Int {
        max(0, phaseDurationSeconds() - phaseElapsed(at: date))
    }

    func totalWorkSeconds(at date: Date = .now) -> Int {
        let current = phase == .work || phase == .pausedWork
            ? phaseElapsed(at: date)
            : 0
        return completedWorkSeconds + current
    }

    mutating func start(at date: Date = .now) -> [SmartLoopEvent] {
        phase = .work
        phaseStartedAt = date
        pausedPhaseElapsed = 0
        loopsCompleted = 0
        completedWorkSeconds = 0
        currentTempoBPM = settings.startingTempoBPM
        cleanLoopsAtCurrentTempo = 0
        workCycleIndex = 1
        markableCompletedCycle = nil
        markedCycleIndices = []
        return [.enteredWork]
    }

    mutating func pause(at date: Date = .now) {
        guard phase.isRunning else { return }
        pausedPhaseElapsed = phaseElapsed(at: date)
        phase = phase == .work ? .pausedWork : .pausedRest
        phaseStartedAt = nil
    }

    mutating func resume(at date: Date = .now) -> [SmartLoopEvent] {
        guard phase.isPaused else { return [] }
        phase = phase == .pausedWork ? .work : .rest
        phaseStartedAt = date.addingTimeInterval(-TimeInterval(pausedPhaseElapsed))
        return phase == .work ? [.enteredWork] : [.enteredRest]
    }

    mutating func stop(at date: Date = .now) -> [SmartLoopEvent] {
        guard phase != .idle, phase != .finished else { return [] }
        if phase == .work || phase == .pausedWork {
            completedWorkSeconds += phaseElapsed(at: date)
        }
        phase = hasMeaningfulResult ? .finished : .idle
        phaseStartedAt = nil
        pausedPhaseElapsed = 0
        return phase == .finished ? [.finished] : []
    }

    /// Advances across every timestamp boundary, including several work/rest
    /// intervals after a long background suspension. No elapsed time is lost
    /// to delayed UI frames.
    mutating func advance(to date: Date = .now) -> [SmartLoopEvent] {
        guard phase.isRunning, let initialStart = phaseStartedAt else { return [] }
        var events: [SmartLoopEvent] = []
        var boundary = initialStart.addingTimeInterval(
            TimeInterval(phaseDurationSeconds())
        )

        while phase.isRunning, date >= boundary {
            switch phase {
            case .work:
                completedWorkSeconds += settings.loopDurationSeconds
                loopsCompleted += 1
                markableCompletedCycle = workCycleIndex
                events.append(.completedLoop(loopsCompleted))

                if !settings.tempoLadderEnabled,
                   settings.autoIncreaseEnabled,
                   loopsCompleted.isMultiple(of: settings.autoIncreaseEvery) {
                    let nextTempo = min(
                        220,
                        currentTempoBPM + settings.tempoIncreaseBPM
                    )
                    if nextTempo != currentTempoBPM {
                        currentTempoBPM = nextTempo
                        events.append(.tempoChanged(nextTempo))
                    }
                }

                if !settings.runsUntilStopped,
                   loopsCompleted >= settings.targetLoops {
                    phase = .finished
                    phaseStartedAt = nil
                    pausedPhaseElapsed = 0
                    events.append(.finished)
                    break
                }

                if settings.restDurationSeconds > 0 {
                    phase = .rest
                    phaseStartedAt = boundary
                    pausedPhaseElapsed = 0
                    events.append(.enteredRest)
                } else {
                    workCycleIndex += 1
                    phaseStartedAt = boundary
                    events.append(.enteredWork)
                }

            case .rest:
                workCycleIndex += 1
                phase = .work
                phaseStartedAt = boundary
                pausedPhaseElapsed = 0
                events.append(.enteredWork)

            default:
                break
            }

            guard phase.isRunning, let nextStart = phaseStartedAt else { break }
            boundary = nextStart.addingTimeInterval(
                TimeInterval(phaseDurationSeconds())
            )
        }
        return events
    }

    /// Marks the most recently completed work interval once. Repeated taps
    /// during the next interval cannot inflate ladder progress.
    mutating func markLastCompletedLoopClean() -> [SmartLoopEvent] {
        guard settings.metronomeEnabled,
              settings.tempoLadderEnabled,
              let cycle = markableCompletedCycle,
              !markedCycleIndices.contains(cycle) else {
            return []
        }

        markedCycleIndices.insert(cycle)
        markableCompletedCycle = nil
        cleanLoopsAtCurrentTempo += 1
        guard cleanLoopsAtCurrentTempo >= settings.cleanLoopsRequired else {
            return []
        }

        cleanLoopsAtCurrentTempo = 0
        let nextTempo = min(
            220,
            currentTempoBPM + settings.tempoIncreaseBPM
        )
        guard nextTempo != currentTempoBPM else { return [] }
        currentTempoBPM = nextTempo
        return [.tempoChanged(nextTempo)]
    }
}

struct SmartLoopResultPayload: Codable, Equatable {
    let completedAt: Date
    let loopsCompleted: Int
    let totalWorkSeconds: Int
    let settings: SmartLoopSettings
    let endingTempoBPM: Int
    let tags: [String]
    let parentSessionID: UUID?
    let launchSource: PracticeLaunchSource
    let toolVersion: Int
}
