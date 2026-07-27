import Foundation

enum GuidedPracticeGoal: String, CaseIterable, Codable, Hashable, Identifiable {
    case intonation
    case rhythm
    case memory
    case bowControl
    case shifts
    case tone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .intonation: "Intonation"
        case .rhythm: "Rhythm"
        case .memory: "Memory"
        case .bowControl: "Bow control"
        case .shifts: "Shifts"
        case .tone: "Tone"
        }
    }
}

enum GuidedPracticeBlockKind: String, CaseIterable, Codable, Hashable, Identifiable {
    case warmUp
    case technique
    case repertoire
    case runThrough

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmUp: "Warm-up"
        case .technique: "Technique"
        case .repertoire: "Repertoire"
        case .runThrough: "Run-through"
        }
    }

    var systemImage: String {
        switch self {
        case .warmUp: "figure.cooldown"
        case .technique: "scope"
        case .repertoire: "music.note.list"
        case .runThrough: "record.circle"
        }
    }
}

struct GuidedPracticeBlock: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: GuidedPracticeBlockKind
    var durationSeconds: Int

    init(
        id: UUID = UUID(),
        kind: GuidedPracticeBlockKind,
        durationSeconds: Int
    ) {
        self.id = id
        self.kind = kind
        self.durationSeconds = min(max(durationSeconds, 60), 3_600)
    }
}

enum GuidedPracticePhase: String, Codable, Hashable {
    case plan
    case running
    case paused
    case reflect
    case completed
}

enum GuidedPracticeEvent: Equatable {
    case blockCompleted(GuidedPracticeBlockKind)
    case blockChanged(GuidedPracticeBlockKind)
    case readyToReflect
}

struct GuidedPracticeRunState: Codable, Equatable {
    var goals: [GuidedPracticeGoal]
    var blocks: [GuidedPracticeBlock]
    var phase: GuidedPracticePhase
    var currentBlockIndex: Int
    var completedSeconds: Int
    var currentBlockAccumulatedSeconds: Int
    var phaseStartedAt: Date?

    init(
        goals: [GuidedPracticeGoal],
        blocks: [GuidedPracticeBlock]
    ) {
        self.goals = Array(Set(goals)).sorted { $0.rawValue < $1.rawValue }
        self.blocks = blocks
        phase = .plan
        currentBlockIndex = 0
        completedSeconds = 0
        currentBlockAccumulatedSeconds = 0
        phaseStartedAt = nil
    }

    var currentBlock: GuidedPracticeBlock? {
        blocks.indices.contains(currentBlockIndex) ? blocks[currentBlockIndex] : nil
    }

    var targetSeconds: Int {
        blocks.reduce(0) { $0 + $1.durationSeconds }
    }

    var hasMeaningfulExecution: Bool {
        totalElapsedSeconds() >= 10
    }

    func currentBlockElapsedSeconds(at date: Date = .now) -> Int {
        min(currentBlockRawElapsedSeconds(at: date), currentBlock?.durationSeconds ?? 0)
    }

    private func currentBlockRawElapsedSeconds(at date: Date) -> Int {
        let runningDelta: Int
        if phase == .running, let phaseStartedAt {
            runningDelta = max(0, Int(date.timeIntervalSince(phaseStartedAt)))
        } else {
            runningDelta = 0
        }
        return max(0, currentBlockAccumulatedSeconds + runningDelta)
    }

    func currentBlockRemainingSeconds(at date: Date = .now) -> Int {
        max(
            0,
            (currentBlock?.durationSeconds ?? 0) - currentBlockElapsedSeconds(at: date)
        )
    }

    func totalElapsedSeconds(at date: Date = .now) -> Int {
        completedSeconds + currentBlockElapsedSeconds(at: date)
    }

    func progress(at date: Date = .now) -> Double {
        guard targetSeconds > 0 else { return 0 }
        return min(
            1,
            Double(totalElapsedSeconds(at: date)) / Double(targetSeconds)
        )
    }

    mutating func start(at date: Date = .now) -> [GuidedPracticeEvent] {
        guard !blocks.isEmpty else {
            phase = .plan
            return []
        }
        if phase == .paused {
            return resume(at: date)
        }
        phase = .running
        currentBlockIndex = min(max(currentBlockIndex, 0), blocks.count - 1)
        phaseStartedAt = date
        return currentBlock.map { [.blockChanged($0.kind)] } ?? []
    }

    mutating func pause(at date: Date = .now) {
        guard phase == .running else { return }
        currentBlockAccumulatedSeconds = currentBlockElapsedSeconds(at: date)
        phaseStartedAt = nil
        phase = .paused
    }

    mutating func resume(at date: Date = .now) -> [GuidedPracticeEvent] {
        guard phase == .paused, currentBlock != nil else { return [] }
        phase = .running
        phaseStartedAt = date
        return currentBlock.map { [.blockChanged($0.kind)] } ?? []
    }

    /// Advances through every completed block boundary using timestamps. A
    /// long background interval therefore cannot lose execution time.
    mutating func advance(to date: Date = .now) -> [GuidedPracticeEvent] {
        guard phase == .running else { return [] }
        var events: [GuidedPracticeEvent] = []

        while let block = currentBlock {
            let elapsed = currentBlockRawElapsedSeconds(at: date)
            guard elapsed >= block.durationSeconds else { break }

            let overflow = max(0, elapsed - block.durationSeconds)
            completedSeconds += block.durationSeconds
            events.append(.blockCompleted(block.kind))
            currentBlockIndex += 1
            currentBlockAccumulatedSeconds = 0

            guard let next = currentBlock else {
                phase = .reflect
                phaseStartedAt = nil
                events.append(.readyToReflect)
                break
            }

            phaseStartedAt = date.addingTimeInterval(-TimeInterval(overflow))
            events.append(.blockChanged(next.kind))
        }
        return events
    }

    mutating func skipCurrentBlock(at date: Date = .now) -> [GuidedPracticeEvent] {
        guard let block = currentBlock,
              phase == .running || phase == .paused else { return [] }
        let elapsed = currentBlockElapsedSeconds(at: date)
        completedSeconds += elapsed
        var events: [GuidedPracticeEvent] = [.blockCompleted(block.kind)]
        currentBlockIndex += 1
        currentBlockAccumulatedSeconds = 0

        guard let next = currentBlock else {
            phase = .reflect
            phaseStartedAt = nil
            events.append(.readyToReflect)
            return events
        }

        phaseStartedAt = phase == .running ? date : nil
        events.append(.blockChanged(next.kind))
        return events
    }

    mutating func moveToReflect(at date: Date = .now) {
        if phase == .running {
            currentBlockAccumulatedSeconds = currentBlockElapsedSeconds(at: date)
        }
        phaseStartedAt = nil
        phase = .reflect
    }
}

struct GuidedPracticeResultPayload: Codable, Equatable {
    let completedAt: Date
    let targetMinutes: Int
    let actualSeconds: Int
    let goals: [GuidedPracticeGoal]
    let blocks: [GuidedPracticeBlock]
    let reflectionWins: String
    let reflectionFix: String
    let reflectionNext: String
    let selfRating: Int
    let parentSessionID: UUID?
    let launchSource: PracticeLaunchSource
    let toolVersion: Int
}
