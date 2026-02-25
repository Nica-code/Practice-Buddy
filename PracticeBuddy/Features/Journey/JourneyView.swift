import SwiftUI
import SwiftData

struct JourneyView: View {
    private enum JourneySection: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case rewards = "Rewards"

        var id: String { rawValue }
    }

    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var duelLeague: DuelLeagueManager
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: [SortDescriptor(\RhythmAccuracyTakeModel.date, order: .reverse)]) private var rhythmTakes: [RhythmAccuracyTakeModel]
    @Query(sort: [SortDescriptor(\ScaleIntonationTakeModel.date, order: .reverse)]) private var intonationTakes: [ScaleIntonationTakeModel]
    @State private var selectedSection: JourneySection = .overview
    @State private var rewardsMessage: String?
    @State private var didLoadDuelTargets = false
    @State private var duelLeaderboardScope: DuelLeaderboardScope = .global
    @State private var animateHeader = false

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var levelProgress: Double {
        guard journey.xpForNextLevel > 0 else { return 0 }
        return min(1.0, max(0, Double(journey.xpIntoLevel) / Double(journey.xpForNextLevel)))
    }

    var body: some View {
        VStack(spacing: 0) {
            topSection

            List {
                if selectedSection == .overview {
                    levelSection
                    duelLeagueSection
                    questsSection
                    aboutSection
                } else {
                    rewardsBalanceSection
                    rewardsCatalogSection
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: selectedSection)
        }
        .background {
            PBBackdropView(palette: palette)
        }
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Progress", isPresented: Binding(
            get: { rewardsMessage != nil },
            set: { if !$0 { rewardsMessage = nil } }
        )) {
            Button("OK", role: .cancel) { rewardsMessage = nil }
        } message: {
            Text(rewardsMessage ?? "")
        }
        .onAppear {
            if !animateHeader {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                    animateHeader = true
                }
            }
            guard !didLoadDuelTargets else { return }
            didLoadDuelTargets = true
            Task {
                await duelLeague.refreshTargetCandidates(force: true)
                await duelLeague.refreshSeasonLeaderboard(scope: duelLeaderboardScope, force: true)
            }
        }
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Play")
                .font(type.appTitle)
                .tracking(type.heroTracking)
                .foregroundStyle(palette.textPrimary)

            Text(
                selectedSection == .overview
                ? "Track level, duels, quests, and piece progress."
                : "Spend tokens and unlock cosmetics."
            )
            .font(type.footnote)
            .foregroundStyle(palette.textSecondary)

            Picker("Play Section", selection: $selectedSection) {
                ForEach(JourneySection.allCases) { section in
                    Text(LocalizedStringKey(section.rawValue)).tag(section)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(PBLayout.padLG)
        .pbModernCard(palette: palette)
        .padding(.horizontal, PBLayout.padSM)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .offset(y: animateHeader ? 0 : 12)
        .opacity(animateHeader ? 1 : 0)
    }

    private var levelSection: some View {
        Section("Progress Level") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.f("Level %@", "\(journey.level)"))
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(L10n.f("%@ XP", "\(journey.totalXP)"))
                        .font(type.number)
                        .foregroundStyle(palette.accent)
                        .monospacedDigit()
                }

                ProgressView(value: levelProgress)

                HStack {
                    Text(L10n.f("%@ / %@ XP", "\(journey.xpIntoLevel)", "\(journey.xpForNextLevel)"))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                    Spacer()
                    Text(L10n.f("%@ to next level", "\(journey.xpToNextLevel)"))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                Text(L10n.f("Today: +%@ XP", "\(journey.todayXP)"))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(palette.surface)
    }

    private var duelLeagueSection: some View {
        Section("Duels & League") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("League")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(duelLeague.leagueTier.title)
                        .font(type.number)
                        .foregroundStyle(palette.accent)
                }

                HStack {
                    Text(L10n.f("Rating %@", "\(duelLeague.duelRating)"))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                    Spacer()
                    Text(L10n.f("W %@ • L %@ • D %@", "\(duelLeague.duelWins)", "\(duelLeague.duelLosses)", "\(duelLeague.duelDraws)"))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                if let next = duelLeague.leagueTier.next {
                    let needed = max(0, next.minRating - duelLeague.duelRating)
                    Text(L10n.f("%@ rating to %@", "\(needed)", next.title))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                } else {
                    Text("Top league reached.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.vertical, 4)

            if let open = duelLeague.myOpenChallenge {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You are queued for a duel")
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)
                        Text(open.objective)
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    ProgressView()
                        .controlSize(.small)
                }
                .padding(10)
                .background(palette.accent.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
            }

            let isQueuedForOpenDuel = duelLeague.myOpenChallenge != nil
            Button {
                Task {
                    if isQueuedForOpenDuel {
                        await duelLeague.cancelOpenChallenge()
                    } else {
                        await duelLeague.queueAsyncScaleDuel()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isQueuedForOpenDuel ? "xmark.circle.fill" : "bolt.horizontal.circle.fill")
                    Text(isQueuedForOpenDuel ? "Cancel Queue" : "Queue Async Scale Duel")
                        .font(type.button)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                PBActionButtonStyle(
                    variant: isQueuedForOpenDuel ? .secondary : .primary,
                    palette: palette
                )
            )
            .disabled(duelLeague.isLoading || firebase.currentUserID == nil || firebase.isAnonymousUser)

            HStack {
                Menu {
                    if duelLeague.friendCandidates.isEmpty {
                        Text("No friend targets")
                    } else {
                        ForEach(duelLeague.friendCandidates) { candidate in
                            Button(candidate.displayName) {
                                Task { await duelLeague.inviteTargetedDuel(targetUID: candidate.id, source: .friend) }
                            }
                        }
                    }
                } label: {
                    Label("Invite Friend", systemImage: "person.badge.plus")
                }
                .buttonStyle(PBActionButtonStyle(variant: .secondary, palette: palette))

                Menu {
                    if duelLeague.studioCandidates.isEmpty {
                        Text("No studio targets")
                    } else {
                        ForEach(duelLeague.studioCandidates) { candidate in
                            Button(candidate.displayName) {
                                Task { await duelLeague.inviteTargetedDuel(targetUID: candidate.id, source: .studio) }
                            }
                        }
                    }
                } label: {
                    Label("Invite Studio", systemImage: "person.3")
                }
                .buttonStyle(PBActionButtonStyle(variant: .secondary, palette: palette))

                Spacer()
                Button {
                    Task { await duelLeague.refreshTargetCandidates(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh duel targets")
            }

            if !duelLeague.incomingInvites.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Incoming Invites")
                        .font(type.footnote)
                        .foregroundStyle(palette.textPrimary)
                    ForEach(duelLeague.incomingInvites) { challenge in
                        incomingInviteRow(challenge)
                    }
                }
            }

            if !duelLeague.outgoingInvites.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Outgoing Invites")
                        .font(type.footnote)
                        .foregroundStyle(palette.textPrimary)
                    ForEach(duelLeague.outgoingInvites) { challenge in
                        outgoingInviteRow(challenge)
                    }
                }
            }

            if !duelLeague.activeChallenges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Duels")
                        .font(type.footnote)
                        .foregroundStyle(palette.textPrimary)
                    ForEach(duelLeague.activeChallenges) { challenge in
                        duelChallengeRow(challenge)
                    }
                }
            }

            if !duelLeague.recentCompleted.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Results")
                        .font(type.footnote)
                        .foregroundStyle(palette.textPrimary)
                    ForEach(duelLeague.recentCompleted.prefix(3)) { challenge in
                        duelCompletedRow(challenge)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Season Ladder")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                Picker("Ladder Scope", selection: $duelLeaderboardScope) {
                    ForEach(DuelLeaderboardScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: duelLeaderboardScope) { _, newValue in
                    Task { await duelLeague.refreshSeasonLeaderboard(scope: newValue, force: true) }
                }

                if duelLeague.leaderboardRows.isEmpty {
                    Text("No ladder data yet for this scope.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(Array(duelLeague.leaderboardRows.enumerated()), id: \.element.id) { idx, row in
                        HStack {
                            Text("#\(idx + 1)")
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 30, alignment: .leading)
                                .monospacedDigit()
                            Text(row.displayName)
                                .font(type.footnote)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(L10n.f("%@ pts", "\(row.points)"))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            if let status = duelLeague.statusMessage, !status.isEmpty {
                Text(LocalizedStringKey(status))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .listRowBackground(palette.surface)
    }

    @ViewBuilder
    private func duelChallengeRow(_ challenge: DuelChallenge) -> some View {
        let uid = firebase.currentUserID ?? ""
        let myScore = challenge.myScore(for: uid)
        let oppScore = challenge.opponentScore(for: uid)
        let otherRaw = challenge.otherParticipant(for: uid) ?? "pending"
        let other = otherRaw.count > 6 ? "\(otherRaw.prefix(6))..." : otherRaw
        let latest = latestDuelMetricsCandidate

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.f("vs %@", other))
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(challenge.objective)
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }

            if let myScore {
                Text(L10n.f("Your score: %@", "\(myScore)"))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
                if let oppScore {
                    Text(L10n.f("Opponent score: %@", "\(oppScore)"))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                } else {
                    Text("Waiting for opponent submission.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                if let latest {
                    Text(
                        L10n.f(
                            "Derived score %@ (I %@ • R %@ • C %@)",
                            "\(latest.derivedScore)",
                            "\(latest.intonationScore)",
                            "\(latest.rhythmScore)",
                            "\(latest.consistencyScore)"
                        )
                    )
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()

                    Button("Submit Latest Analysis") {
                        Task {
                            await duelLeague.submitDerivedAttempt(challengeID: challenge.id, metrics: latest)
                            await duelLeague.refreshSeasonLeaderboard(scope: duelLeaderboardScope, force: true)
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(type.footnote)
                } else {
                    Text("Complete one Rhythm + one Intonation take to submit an app-derived duel attempt.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func duelCompletedRow(_ challenge: DuelChallenge) -> some View {
        let uid = firebase.currentUserID ?? ""
        let myScore = challenge.myScore(for: uid) ?? 0
        let oppScore = challenge.opponentScore(for: uid) ?? 0
        let delta = challenge.myRatingDelta(for: uid)

        return HStack {
            Text(L10n.f("%@-%@", "\(myScore)", "\(oppScore)"))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Spacer()
            Text(delta >= 0 ? L10n.f("+%@", "\(delta)") : "\(delta)")
                .font(type.number)
                .foregroundStyle(delta >= 0 ? palette.accent : palette.textSecondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func incomingInviteRow(_ challenge: DuelChallenge) -> some View {
        let uid = firebase.currentUserID ?? ""
        let other = challenge.otherParticipant(for: uid) ?? "Unknown"
        let queueLabel = challenge.queueType == .friend ? "Friend duel" : "Studio duel"
        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.f("%@ invite", queueLabel))
                .font(type.footnote)
                .foregroundStyle(palette.textPrimary)
            Text(L10n.f("From %@", other))
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
            HStack {
                Button("Accept") {
                    Task { await duelLeague.acceptInvite(challengeID: challenge.id) }
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)

                Button("Decline", role: .destructive) {
                    Task { await duelLeague.declineInvite(challengeID: challenge.id) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 2)
    }

    private func outgoingInviteRow(_ challenge: DuelChallenge) -> some View {
        let uid = firebase.currentUserID ?? ""
        let other = challenge.otherParticipant(for: uid) ?? "Unknown"
        let queueLabel = challenge.queueType == .friend ? "Friend duel" : "Studio duel"
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.f("%@ invite", queueLabel))
                    .font(type.footnote)
                    .foregroundStyle(palette.textPrimary)
                Text(L10n.f("To %@", other))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button("Cancel", role: .destructive) {
                Task { await duelLeague.cancelInvite(challengeID: challenge.id) }
            }
            .buttonStyle(.bordered)
            .font(type.footnote)
        }
        .padding(.vertical, 2)
    }

    private var latestDuelMetricsCandidate: DuelDerivedMetrics? {
        guard let intonation = intonationTakes.first, let rhythm = rhythmTakes.first else { return nil }
        let ageA = abs(intonation.date.timeIntervalSinceNow)
        let ageB = abs(rhythm.date.timeIntervalSinceNow)
        guard ageA <= 60 * 60 * 24 * 7, ageB <= 60 * 60 * 24 * 7 else { return nil }

        let consistency = Int(((intonation.centeringScore + intonation.stabilityScore + intonation.consistencyScore) / 3).rounded())
        return DuelDerivedMetrics(
            intonationScore: min(max(intonation.overallScore, 0), 100),
            rhythmScore: min(max(rhythm.grooveScore, 0), 100),
            consistencyScore: min(max(consistency, 0), 100),
            noteCount: max(0, intonation.noteCount),
            beatsAnalyzed: max(0, rhythm.beatsAnalyzed)
        )
    }

    private var questsSection: some View {
        Section("Quests") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Daily Quests")
                    .font(type.footnote)
                    .foregroundStyle(palette.textPrimary)
                ForEach(journey.dailyQuests) { quest in
                    questRow(quest, period: .daily)
                }
            }

            Divider()
                .overlay(palette.textSecondary.opacity(0.45))
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Weekly Quests")
                    .font(type.footnote)
                    .foregroundStyle(palette.textPrimary)
                ForEach(journey.weeklyQuests) { quest in
                    questRow(quest, period: .weekly)
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var rewardsBalanceSection: some View {
        Section("Token Balance") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Available")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(L10n.f("%@ tokens", "\(journey.tokenBalance)"))
                        .font(type.number)
                        .foregroundStyle(palette.accent)
                        .monospacedDigit()
                }

                Text("Complete quests in Overview and claim rewards to build your token balance.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(palette.surface)
    }

    private var rewardsCatalogSection: some View {
        Section("Reward Catalog") {
            ForEach(journey.rewards) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey(item.title))
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        if item.isOwned {
                            Label("Owned", systemImage: "checkmark.circle.fill")
                                .font(type.footnote)
                                .foregroundStyle(palette.accent)
                        } else {
                            Text(L10n.f("%@ tokens", "\(item.costTokens)"))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }
                    }

                    Text(LocalizedStringKey(item.subtitle))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)

                    if !item.isOwned {
                        Button {
                            if journey.claimRewardItem(id: item.id) {
                                rewardsMessage = "Reward unlocked."
                            } else {
                                rewardsMessage = "Not enough tokens yet."
                            }
                        } label: {
                            Text("Claim Reward")
                                .font(type.button)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var aboutSection: some View {
        Section("How XP Works") {
            Text("1 verified minute = 1 XP. XP is awarded when a session is completed and saved.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

            Text("Quest rewards are tokens for future rewards and cosmetics.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .listRowBackground(palette.surface)
    }

    @ViewBuilder
    private func questRow(_ quest: JourneyQuestRow, period: JourneyQuestPeriod) -> some View {
        let status = journey.questRewardStatus(for: quest, period: period)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LocalizedStringKey(quest.title))
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                switch status {
                case .claimed:
                    Label("Reward Claimed", systemImage: "checkmark.circle.fill")
                        .font(type.footnote)
                        .foregroundStyle(palette.accent)
                case .claimable:
                    Button {
                        if journey.claimQuestReward(for: quest, period: period) {
                            rewardsMessage = L10n.f("Claimed %@ tokens.", "\(quest.rewardTokens)")
                        }
                    } label: {
                        Text(L10n.f("Claim +%@", "\(quest.rewardTokens)"))
                    }
                    .font(type.footnote)
                    .buttonStyle(.bordered)
                    .tint(palette.accent)
                case .locked:
                    Text(L10n.f("+%@ tokens", "\(quest.rewardTokens)"))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }

            Text(LocalizedStringKey(quest.subtitle))
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

            HStack {
                ProgressView(value: min(1.0, Double(quest.progress) / Double(max(quest.target, 1))))
                Text(L10n.f("%@/%@", "\(quest.progress)", "\(quest.target)"))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }

}
