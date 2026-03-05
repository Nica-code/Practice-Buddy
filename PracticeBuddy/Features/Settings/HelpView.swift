import SwiftUI

struct HelpView: View {
    @Environment(\.pbTypography) private var type

    var body: some View {
        List {
            Section("Getting started") {
                bullet("On the Home screen, tap **Start Practice** to begin immediately.")
                bullet("The timer and controls appear right on the Home screen.")
            }

            Section("Practice timer") {
                bullet("Tap **Start Practice** to start the timer.")
                bullet("Tap **Pause** to freeze time (your progress is kept).")
                bullet("Tap **Resume** to continue.")
                bullet("Tap **Stop** to open **Save Session**.")
                bullet("On Save Session, add optional notes and tap **Save**, or tap **Discard** to throw it away.")
            }

            Section("Goals & streaks") {
                bullet("Go to **Settings → Daily goal** to set your goal minutes.")
                bullet("Home shows your **Today progress** and your **Streak**.")
                bullet("A streak counts consecutive days meeting the goal (if you miss today, streak shows **0**).")
            }

            Section("History & editing notes") {
                bullet("Go to **Home → History** to see saved sessions.")
                bullet("Tap a session to edit notes and hit **Save**.")
                bullet("Swipe left to delete, or use **Edit** for multi-delete.")
            }

            Section("How totals reset") {
                bullet("**Today** resets at midnight (your local time).")
                bullet("**This week** resets when a new week starts (based on your system settings).")
                bullet("**This month** resets on the 1st of each month.")
            }
        }
        .navigationTitle("How to use")
    }

    private func bullet(_ markdown: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(type.body)
                .padding(.top, 1)
            Text(.init(markdown))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }
}
