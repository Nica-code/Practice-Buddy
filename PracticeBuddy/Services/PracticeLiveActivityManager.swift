import Foundation
import Combine
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class PracticeLiveActivityManager: ObservableObject {
    static let shared = PracticeLiveActivityManager()

    enum Mode {
        case timer(title: String, subtitle: String, elapsedSeconds: Int)
        case session(title: String, subtitle: String, elapsedSeconds: Int, remainingSeconds: Int, progress: Double)
    }

    private init() {}

#if canImport(ActivityKit)
    private var currentActivity: Activity<PracticeLiveActivityAttributes>?
#endif

    func ensureUpdated(isRunning: Bool, mode: Mode) {
#if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = makeState(isRunning: isRunning, mode: mode)
        if currentActivity == nil {
            currentActivity = Activity<PracticeLiveActivityAttributes>.activities.first
        }
        if let currentActivity {
            Task {
                await currentActivity.update(ActivityContent(state: state, staleDate: nil))
            }
            return
        }

        guard isRunning else { return }

        let attributes = PracticeLiveActivityAttributes(startedAt: Date())
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Graceful fallback when Live Activities are unavailable.
        }
#endif
    }

    func end() {
#if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        let active = Activity<PracticeLiveActivityAttributes>.activities
        guard !active.isEmpty || currentActivity != nil else { return }
        Task {
            for activity in active {
                let finalState = activity.content.state
                await activity.end(
                    ActivityContent(state: finalState, staleDate: Date()),
                    dismissalPolicy: .immediate
                )
            }
            if let currentActivity {
                let finalState = currentActivity.content.state
                await currentActivity.end(
                    ActivityContent(state: finalState, staleDate: Date()),
                    dismissalPolicy: .immediate
                )
            }
        }
        self.currentActivity = nil
#endif
    }

#if canImport(ActivityKit)
    @available(iOS 16.2, *)
    private func makeState(isRunning: Bool, mode: Mode) -> PracticeLiveActivityAttributes.ContentState {
        switch mode {
        case .timer(let title, let subtitle, let elapsedSeconds):
            return PracticeLiveActivityAttributes.ContentState(
                modeRaw: "timer",
                title: title,
                subtitle: subtitle,
                progress: 0,
                isRunning: isRunning,
                referenceStartDate: Date(),
                elapsedSeconds: max(0, elapsedSeconds),
                remainingSeconds: 0
            )
        case .session(let title, let subtitle, let elapsedSeconds, let remainingSeconds, let progress):
            return PracticeLiveActivityAttributes.ContentState(
                modeRaw: "session",
                title: title,
                subtitle: subtitle,
                progress: min(max(progress, 0), 1),
                isRunning: isRunning,
                referenceStartDate: Date(),
                elapsedSeconds: max(0, elapsedSeconds),
                remainingSeconds: max(0, remainingSeconds)
            )
        }
    }
#endif
}
