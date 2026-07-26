import Foundation

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
