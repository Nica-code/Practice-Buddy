import ActivityKit
import WidgetKit
import SwiftUI

struct PracticeTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PracticeLiveActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .activityBackgroundTint(Color.black.opacity(0.12))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if context.state.modeRaw == "session" {
                            ProgressView(value: min(max(context.state.progress, 0), 1))
                                .progressViewStyle(.linear)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                Text(shortTime(context.state))
                    .monospacedDigit()
                    .font(.caption2)
            } minimal: {
                Image(systemName: "timer")
            }
            .keylineTint(.blue)
        }
    }

    private func shortTime(_ state: PracticeLiveActivityAttributes.ContentState) -> String {
        let seconds = max(0, state.remainingSeconds > 0 ? state.remainingSeconds : state.elapsedSeconds)
        let minutes = seconds / 60
        let rem = seconds % 60
        return String(format: "%d:%02d", minutes, rem)
    }
}

private struct LockScreenView: View {
    let state: PracticeLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.modeRaw == "session" ? "checklist" : "timer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(state.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if state.modeRaw == "session" {
                    ProgressView(value: min(max(state.progress, 0), 1))
                        .progressViewStyle(.linear)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(timeLabel(state))
                    .font(.headline.monospacedDigit())
                Text(state.isRunning ? "Running" : "Paused")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeLabel(_ state: PracticeLiveActivityAttributes.ContentState) -> String {
        let target = max(0, state.remainingSeconds > 0 ? state.remainingSeconds : state.elapsedSeconds)
        let minutes = target / 60
        let seconds = target % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

