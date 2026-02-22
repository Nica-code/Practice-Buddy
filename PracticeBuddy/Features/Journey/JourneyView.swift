import SwiftUI

struct JourneyView: View {
    @EnvironmentObject private var journey: JourneyProgressManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var levelProgress: Double {
        guard journey.xpForNextLevel > 0 else { return 0 }
        return min(1.0, max(0, Double(journey.xpIntoLevel) / Double(journey.xpForNextLevel)))
    }

    var body: some View {
        List {
            levelSection
            dailyQuestsSection
            weeklyQuestsSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var levelSection: some View {
        Section("Journey Level") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Level \(journey.level)")
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(journey.totalXP) XP")
                        .font(type.number)
                        .foregroundStyle(palette.accent)
                        .monospacedDigit()
                }

                ProgressView(value: levelProgress)

                HStack {
                    Text("\(journey.xpIntoLevel) / \(journey.xpForNextLevel) XP")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                    Spacer()
                    Text("\(journey.xpToNextLevel) to next level")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                Text("Today: +\(journey.todayXP) XP")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(palette.surface)
    }

    private var dailyQuestsSection: some View {
        Section("Daily Quests") {
            ForEach(journey.dailyQuests) { quest in
                questRow(quest)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var weeklyQuestsSection: some View {
        Section("Weekly Quests") {
            ForEach(journey.weeklyQuests) { quest in
                questRow(quest)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var aboutSection: some View {
        Section("How XP Works") {
            Text("1 minute practiced = 1 XP. XP is awarded when a session is completed and saved.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

            Text("Quest rewards are tokens for future rewards and cosmetics.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .listRowBackground(palette.surface)
    }

    @ViewBuilder
    private func questRow(_ quest: JourneyQuestRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(quest.title)
                    .font(type.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if quest.isCompleted {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(type.footnote)
                        .foregroundStyle(palette.accent)
                } else {
                    Text("+\(quest.rewardTokens) tokens")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }

            Text(quest.subtitle)
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

            HStack {
                ProgressView(value: min(1.0, Double(quest.progress) / Double(max(quest.target, 1))))
                Text("\(quest.progress)/\(quest.target)")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}
