import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    pageOne.tag(0)
                    pageTwo.tag(1)
                    pageThree.tag(2)
                    pageFour.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Divider()

                HStack(spacing: 12) {
                    Button("Skip") {
                        onFinish()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(page == 3 ? "Get Started" : "Next") {
                        if page < 3 {
                            withAnimation { page += 1 }
                        } else {
                            onFinish()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onFinish() }
                }
            }
        }
    }

    private var pageOne: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Practice Buddy")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text("Start a timer, save notes, and build a streak—right from Home.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding()
    }

    private var pageTwo: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Practice timer", systemImage: "timer")
            bullet("On Home, tap **Start Practice** to begin instantly.")
            bullet("Controls appear on Home: **Pause/Resume** and **Stop**.")
            bullet("Tap **Stop** to open **Save Session** (notes optional).")
            Spacer()
        }
        .padding()
    }

    private var pageThree: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Goals & streaks", systemImage: "flame")
            bullet("Set your daily goal in **Settings → Daily goal**.")
            bullet("Home shows progress for today and your current streak.")
            bullet("Streak = consecutive days meeting the goal.")
            Spacer()
        }
        .padding()
    }

    private var pageFour: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("History & notes", systemImage: "note.text")
            bullet("Open **History** to view your sessions.")
            bullet("Tap a session to edit notes and hit **Save**.")
            bullet("Swipe to delete or use **Edit** for multi-delete.")
            Spacer()
        }
        .padding()
    }

    private func header(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.title3.bold())
        }
        .padding(.bottom, 6)
    }

    private func bullet(_ markdown: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("•")
                .font(.headline)
                .padding(.top, 1)
            Text(.init(markdown))
        }
    }
}
