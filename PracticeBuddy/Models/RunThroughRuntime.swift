import Foundation

enum RunThroughPhase: String, Codable, Equatable {
    case idle
    case countIn
    case recording
    case paused
    case review
    case failed
}

struct RunThroughSettings: Codable, Equatable {
    var noPauseMode: Bool
    var useMetronome: Bool
    var metronomeBPM: Int

    init(
        noPauseMode: Bool,
        useMetronome: Bool,
        metronomeBPM: Int
    ) {
        self.noPauseMode = noPauseMode
        self.useMetronome = useMetronome
        self.metronomeBPM = min(max(metronomeBPM, 40), 220)
    }
}

struct RunThroughRunState: Codable, Equatable {
    var settings: RunThroughSettings
    var phase: RunThroughPhase
    var countInStartedAt: Date?
    var recordingStartedAt: Date?
    var accumulatedRecordingSeconds: Int
    var markers: [RunThroughMarker]
    var audioFilePath: String?

    init(settings: RunThroughSettings) {
        self.settings = settings
        phase = .idle
        countInStartedAt = nil
        recordingStartedAt = nil
        accumulatedRecordingSeconds = 0
        markers = []
        audioFilePath = nil
    }

    func countInBeat(at date: Date = .now) -> Int? {
        guard phase == .countIn, let countInStartedAt else { return nil }
        let elapsed = max(0, Int(date.timeIntervalSince(countInStartedAt)))
        guard elapsed < 3 else { return nil }
        return 3 - elapsed
    }

    func elapsedSeconds(at date: Date = .now) -> Int {
        guard phase == .recording, let recordingStartedAt else {
            return accumulatedRecordingSeconds
        }
        return accumulatedRecordingSeconds
            + max(0, Int(date.timeIntervalSince(recordingStartedAt)))
    }

    func hasMeaningfulRecording(at date: Date = .now) -> Bool {
        elapsedSeconds(at: date) >= 3
            && (audioFilePath.map { !$0.isEmpty } ?? false)
    }

    mutating func beginCountIn(at date: Date = .now) {
        phase = .countIn
        countInStartedAt = date
        recordingStartedAt = nil
        accumulatedRecordingSeconds = 0
        markers = []
        audioFilePath = nil
    }

    mutating func beginRecording(
        filePath: String,
        at date: Date = .now
    ) {
        phase = .recording
        countInStartedAt = nil
        recordingStartedAt = date
        audioFilePath = filePath
    }

    mutating func pause(at date: Date = .now) {
        guard phase == .recording else { return }
        accumulatedRecordingSeconds = elapsedSeconds(at: date)
        recordingStartedAt = nil
        phase = .paused
    }

    mutating func resume(at date: Date = .now) {
        guard phase == .paused else { return }
        recordingStartedAt = date
        phase = .recording
    }

    mutating func finish(at date: Date = .now) {
        if phase == .recording {
            accumulatedRecordingSeconds = elapsedSeconds(at: date)
        }
        recordingStartedAt = nil
        countInStartedAt = nil
        phase = .review
    }

    mutating func addMarker(_ label: String, at date: Date = .now) {
        guard phase == .recording || phase == .paused else { return }
        markers.append(
            RunThroughMarker(
                second: elapsedSeconds(at: date),
                label: label
            )
        )
    }
}

struct RunThroughResultPayload: Codable, Equatable {
    let completedAt: Date
    let durationSeconds: Int
    let audioFilePath: String
    let notes: String
    let selfRating: Int
    let settings: RunThroughSettings
    let markers: [RunThroughMarker]
    let pieceName: String
    let parentSessionID: UUID?
    let launchSource: PracticeLaunchSource
    let toolVersion: Int
}

enum RunThroughFileLifecycle {
    static func removeIfPresent(
        at url: URL?,
        fileManager: FileManager = .default
    ) {
        guard let url, fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }
}
