import Foundation

enum PracticeToolID: String, CaseIterable, Codable, Hashable, Identifiable {
    case metronome
    case tuner
    case smartLoop
    case warmUp
    case planExecuteReflect
    case rhythm
    case intonation
    case runThrough
    case smartCoach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metronome: "Metronome"
        case .tuner: "Tuner"
        case .smartLoop: "Smart Loop"
        case .warmUp: "Warm-up Generator"
        case .planExecuteReflect: "Plan · Execute · Reflect"
        case .rhythm: "Rhythm Accuracy"
        case .intonation: "Intonation"
        case .runThrough: "Run-through"
        case .smartCoach: "Smart Coach"
        }
    }
}

struct PracticeToolCapability: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let timed = PracticeToolCapability(rawValue: 1 << 0)
    static let microphone = PracticeToolCapability(rawValue: 1 << 1)
    static let recording = PracticeToolCapability(rawValue: 1 << 2)
    static let playback = PracticeToolCapability(rawValue: 1 << 3)
    static let producesResult = PracticeToolCapability(rawValue: 1 << 4)
    static let supportsActiveSession = PracticeToolCapability(rawValue: 1 << 5)
    static let supportsRecovery = PracticeToolCapability(rawValue: 1 << 6)
}

enum PracticeLaunchSource: String, Codable, Hashable {
    case dock
    case setup
    case library
    case activeSession
    case quest
    case smartCoach
    case savedPlan
    case todaySuggestion
    case qa
    case legacy

    init(legacyValue: String) {
        switch legacyValue {
        case "dock", "dock_resume": self = .dock
        case "setup": self = .setup
        case "library": self = .library
        case "active_session": self = .activeSession
        case "quest": self = .quest
        case "smart_coach": self = .smartCoach
        case "saved_plan": self = .savedPlan
        case "today_suggestion": self = .todaySuggestion
        case "qa": self = .qa
        default: self = .legacy
        }
    }
}

struct PracticeToolLaunchContext: Codable, Hashable {
    let toolID: PracticeToolID
    let source: PracticeLaunchSource
    let parentSessionID: UUID?
    let questID: String?
    let smartCoachPlanID: String?

    init(
        toolID: PracticeToolID,
        source: PracticeLaunchSource,
        parentSessionID: UUID? = nil,
        questID: String? = nil,
        smartCoachPlanID: String? = nil
    ) {
        self.toolID = toolID
        self.source = source
        self.parentSessionID = parentSessionID
        self.questID = questID
        self.smartCoachPlanID = smartCoachPlanID
    }
}

enum PracticeActivityKind: Codable, Hashable {
    case standard
    case focusedTool(PracticeToolID)
}

enum PracticeActivityPhase: String, Codable, Hashable {
    case idle
    case preparing
    case ready
    case running
    case paused
    case finishing
    case completed
    case failed
}

struct PracticeActivityState: Codable, Hashable {
    var sessionID: UUID
    var kind: PracticeActivityKind
    var phase: PracticeActivityPhase
    var phaseStartedAt: Date?
    var accumulatedSeconds: Int
    var launchContext: PracticeToolLaunchContext?
    var recoveryPayloadJSON: String?

    init(
        sessionID: UUID = UUID(),
        kind: PracticeActivityKind,
        phase: PracticeActivityPhase = .idle,
        phaseStartedAt: Date? = nil,
        accumulatedSeconds: Int = 0,
        launchContext: PracticeToolLaunchContext? = nil,
        recoveryPayloadJSON: String? = nil
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.phase = phase
        self.phaseStartedAt = phaseStartedAt
        self.accumulatedSeconds = max(0, accumulatedSeconds)
        self.launchContext = launchContext
        self.recoveryPayloadJSON = recoveryPayloadJSON
    }

    func elapsed(at date: Date = .now) -> Int {
        guard phase == .running, let phaseStartedAt else {
            return accumulatedSeconds
        }
        return accumulatedSeconds + max(0, Int(date.timeIntervalSince(phaseStartedAt)))
    }
}

struct PracticeToolResult: Codable, Hashable {
    let id: UUID
    let toolID: PracticeToolID
    let sessionID: UUID
    let completedAt: Date
    let durationSeconds: Int
    let metrics: [String: Double]
    let payloadJSON: String

    init(
        id: UUID = UUID(),
        toolID: PracticeToolID,
        sessionID: UUID,
        completedAt: Date = .now,
        durationSeconds: Int,
        metrics: [String: Double] = [:],
        payloadJSON: String = ""
    ) {
        self.id = id
        self.toolID = toolID
        self.sessionID = sessionID
        self.completedAt = completedAt
        self.durationSeconds = max(0, durationSeconds)
        self.metrics = metrics
        self.payloadJSON = payloadJSON
    }
}

struct PracticeSavePayload {
    let sessionID: UUID
    let date: Date
    let snapshot: PracticeSessionSnapshot
    let notes: String
    let noteTitle: String
    let noteFocus: String
    let noteMoodRaw: String
    let noteStructuredJSON: String
    let toolResult: PracticeToolResult?
    let attachedToolResults: [PracticeToolResult]

    init(
        sessionID: UUID,
        date: Date = .now,
        snapshot: PracticeSessionSnapshot,
        notes: String = "",
        noteTitle: String = "",
        noteFocus: String = "",
        noteMoodRaw: String = "",
        noteStructuredJSON: String = "",
        toolResult: PracticeToolResult? = nil,
        attachedToolResults: [PracticeToolResult] = []
    ) {
        self.sessionID = sessionID
        self.date = date
        self.snapshot = snapshot
        self.notes = notes
        self.noteTitle = noteTitle
        self.noteFocus = noteFocus
        self.noteMoodRaw = noteMoodRaw
        self.noteStructuredJSON = noteStructuredJSON
        self.toolResult = toolResult
        self.attachedToolResults = attachedToolResults
    }
}

struct PracticePlanTask: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var minutes: Int

    init(id: String = UUID().uuidString, title: String, minutes: Int) {
        self.id = id
        self.title = title
        self.minutes = max(1, minutes)
    }
}

struct PracticeTaskProgress: Identifiable, Equatable {
    let id: String
    let title: String
    let minutes: Int
    let progress: Double
    let remainingSeconds: Int
    let isCurrent: Bool
    let isComplete: Bool
}

enum PracticeCheckInInterval: String, CaseIterable, Identifiable, Codable {
    case focused
    case standard
    case relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focused: "10–20 min"
        case .standard: "20–35 min"
        case .relaxed: "30–50 min"
        }
    }

    var rangeSeconds: ClosedRange<Int> {
        switch self {
        case .focused: 600...1_200
        case .standard: 1_200...2_100
        case .relaxed: 1_800...3_000
        }
    }
}

struct PracticeSessionSnapshot: Equatable {
    let durationSeconds: Int
    let verifiedSeconds: Int
    let unverifiedSeconds: Int
    let checkInCount: Int
    let missedCheckInCount: Int
    let checkInLogJSON: String
    let piece: String
    let tasks: [PracticePlanTask]
    let launchContext: PracticeLaunchContext?
}
