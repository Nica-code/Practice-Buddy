import Foundation
import Combine

enum PracticeCheckInTickResult {
    case none
    case triggered
    case missed
}

@MainActor
final class PracticeCheckInManager: ObservableObject {
    @Published private(set) var isAwaitingResponse: Bool = false
    @Published private(set) var secondsUntilPrompt: Int = 0
    @Published private(set) var secondsUntilDeadline: Int = 0
    @Published private(set) var checkInCount: Int = 0
    @Published private(set) var missedCheckInCount: Int = 0
    @Published private(set) var events: [PracticeCheckInEvent] = []

    private var awaitingStartedAt: Date?
    private var promptRange: ClosedRange<Int>
    private var responseWindow: Int

    init(promptRange: ClosedRange<Int> = 180...420, responseWindow: Int = 30) {
        self.promptRange = promptRange
        self.responseWindow = responseWindow
        secondsUntilPrompt = Int.random(in: promptRange)
    }

    func reset() {
        isAwaitingResponse = false
        secondsUntilPrompt = Int.random(in: promptRange)
        secondsUntilDeadline = 0
        checkInCount = 0
        missedCheckInCount = 0
        events = []
        awaitingStartedAt = nil
    }

    func updateConfiguration(promptRange: ClosedRange<Int>, responseWindow: Int = 30) {
        self.promptRange = promptRange
        self.responseWindow = max(10, responseWindow)
        if !isAwaitingResponse {
            secondsUntilPrompt = Int.random(in: self.promptRange)
        } else {
            secondsUntilDeadline = min(secondsUntilDeadline, self.responseWindow)
        }
    }

    func restoreCounters(
        checkInCount: Int,
        missedCheckInCount: Int,
        events: [PracticeCheckInEvent]
    ) {
        self.checkInCount = max(0, checkInCount)
        self.missedCheckInCount = max(0, missedCheckInCount)
        self.events = events
        isAwaitingResponse = false
        secondsUntilDeadline = 0
        secondsUntilPrompt = Int.random(in: promptRange)
        awaitingStartedAt = nil
    }

    func tick(now: Date = Date(), enabled: Bool) -> PracticeCheckInTickResult {
        guard enabled else { return .none }

        if isAwaitingResponse {
            secondsUntilDeadline = max(0, secondsUntilDeadline - 1)
            if secondsUntilDeadline == 0 {
                isAwaitingResponse = false
                awaitingStartedAt = nil
                missedCheckInCount += 1
                events.append(
                    PracticeCheckInEvent(
                        timestamp: now,
                        responded: false,
                        responseSeconds: responseWindow,
                        focusTag: ""
                    )
                )
                secondsUntilPrompt = Int.random(in: promptRange)
                return .missed
            }
            return .none
        }

        secondsUntilPrompt = max(0, secondsUntilPrompt - 1)
        if secondsUntilPrompt == 0 {
            isAwaitingResponse = true
            secondsUntilDeadline = responseWindow
            awaitingStartedAt = now
            checkInCount += 1
            return .triggered
        }

        return .none
    }

    func respond(focusTag: String = "", now: Date = Date()) {
        guard isAwaitingResponse else { return }
        let responseSeconds: Int
        if let started = awaitingStartedAt {
            responseSeconds = max(0, Int(now.timeIntervalSince(started)))
        } else {
            responseSeconds = 0
        }

        events.append(
            PracticeCheckInEvent(
                timestamp: now,
                responded: true,
                responseSeconds: responseSeconds,
                focusTag: focusTag
            )
        )

        isAwaitingResponse = false
        awaitingStartedAt = nil
        secondsUntilDeadline = 0
        secondsUntilPrompt = Int.random(in: promptRange)
    }

    func eventsJSON() -> String {
        guard !events.isEmpty,
              let data = try? JSONEncoder().encode(events),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}
