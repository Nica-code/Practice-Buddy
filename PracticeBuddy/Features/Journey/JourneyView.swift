import SwiftUI
import SwiftData
import AVFoundation

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
    @Query(sort: [SortDescriptor(\PracticeSessionModel.date, order: .reverse)]) private var sessions: [PracticeSessionModel]
    @Query(sort: [SortDescriptor(\RunThroughModel.date, order: .reverse)]) private var runThroughs: [RunThroughModel]
    @Query(sort: [SortDescriptor(\RhythmAccuracyTakeModel.date, order: .reverse)]) private var rhythmTakes: [RhythmAccuracyTakeModel]
    @Query(sort: [SortDescriptor(\ScaleIntonationTakeModel.date, order: .reverse)]) private var intonationTakes: [ScaleIntonationTakeModel]
    @Query(sort: [SortDescriptor(\LoopPracticeLogModel.date, order: .reverse)]) private var loopLogs: [LoopPracticeLogModel]
    @State private var selectedSection: JourneySection = .overview
    @State private var rewardsMessage: String?
    @State private var didLoadDuelTargets = false
    @State private var duelLeaderboardScope: DuelLeaderboardScope = .global

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var levelProgress: Double {
        guard journey.xpForNextLevel > 0 else { return 0 }
        return min(1.0, max(0, Double(journey.xpIntoLevel) / Double(journey.xpForNextLevel)))
    }

    var body: some View {
        List {
            topSection

            if selectedSection == .overview {
                levelSection
                duelLeagueSection
                pieceDashboardSection
                skillTrendsSection
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
        .background(chrome.ignoresSafeArea())
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
            guard !didLoadDuelTargets else { return }
            didLoadDuelTargets = true
            Task {
                await duelLeague.refreshTargetCandidates(force: true)
                await duelLeague.refreshSeasonLeaderboard(scope: duelLeaderboardScope, force: true)
            }
        }
    }

    private var topSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Play")
                    .font(type.sectionTitle)
                    .foregroundStyle(palette.textPrimary)
                Text(
                    selectedSection == .overview
                    ? "Track level, quests, and piece progress."
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
                .padding(.top, 2)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(palette.surface)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Waiting for match")
                        .font(type.footnote)
                        .foregroundStyle(palette.textPrimary)
                    Text(open.objective)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Button("Cancel Open Duel", role: .destructive) {
                        Task { await duelLeague.cancelOpenChallenge() }
                    }
                    .buttonStyle(.bordered)
                    .font(type.footnote)
                }
                .padding(.vertical, 2)
            } else {
                Button {
                    Task { await duelLeague.queueAsyncScaleDuel() }
                } label: {
                    Text("Queue Async Scale Duel")
                        .font(type.button)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(duelLeague.isLoading || firebase.currentUserID == nil || firebase.isAnonymousUser)
            }

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
                .buttonStyle(.bordered)

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
                .buttonStyle(.bordered)

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
                        .foregroundStyle(palette.textSecondary)
                    ForEach(duelLeague.incomingInvites) { challenge in
                        incomingInviteRow(challenge)
                    }
                }
            }

            if !duelLeague.outgoingInvites.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Outgoing Invites")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    ForEach(duelLeague.outgoingInvites) { challenge in
                        outgoingInviteRow(challenge)
                    }
                }
            }

            if !duelLeague.activeChallenges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Duels")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    ForEach(duelLeague.activeChallenges) { challenge in
                        duelChallengeRow(challenge)
                    }
                }
            }

            if !duelLeague.recentCompleted.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Results")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
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

    private var pieceDashboardSection: some View {
        Section("Piece Dashboard") {
            if pieceRows.isEmpty {
                Text("Save run-throughs with a piece name to build your dashboard.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(pieceRows) { row in
                    NavigationLink {
                        PieceDetailView(
                            pieceName: row.pieceName,
                            sessions: pieceSessions(named: row.pieceName),
                            runThroughs: pieceRunThroughs(named: row.pieceName),
                            latestTempo: row.latestTempo
                        )
                    } label: {
                        pieceRowSummary(row)
                    }
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private func pieceRowSummary(_ row: PieceDashboardRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.pieceName)
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if let rating = row.bestRating {
                    Text(L10n.f("Best %@/5", "\(rating)"))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }

            HStack {
                Text(L10n.f("%@m practice", "\(row.totalMinutes)"))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
                Spacer()
                Text(L10n.f("%@ run-throughs", "\(row.runThroughCount)"))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text(L10n.f("Last: %@", row.lastPracticed.formatted(date: .abbreviated, time: .omitted)))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if let tempo = row.latestTempo {
                    Text(L10n.f("Tempo %@ BPM", "\(tempo)"))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var skillTrendsSection: some View {
        Section("Skill Trends") {
            HStack {
                Text("Rhythm groove")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(rhythmTrendText)
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("Intonation score")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(intonationTrendText)
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("Loop tempo")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(loopTrendText)
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .listRowBackground(palette.surface)
    }

    private var questsSection: some View {
        Section("Quests") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Daily Quests")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                ForEach(journey.dailyQuests) { quest in
                    questRow(quest, period: .daily)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Weekly Quests")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
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

    private var rhythmTrendText: String {
        let rows = Array(rhythmTakes.prefix(10))
        guard !rows.isEmpty else { return String(localized: "No data") }
        if rows.count == 1 {
            return "\(rows[0].grooveScore)"
        }
        let recent = Double(rows.prefix(3).map(\.grooveScore).reduce(0, +)) / Double(min(3, rows.count))
        let baseline = Double(rows.suffix(3).map(\.grooveScore).reduce(0, +)) / Double(min(3, rows.count))
        let delta = Int((recent - baseline).rounded())
        return "\(Int(recent.rounded())) (\(delta >= 0 ? "+" : "")\(delta))"
    }

    private var intonationTrendText: String {
        let rows = Array(intonationTakes.prefix(10))
        guard !rows.isEmpty else { return String(localized: "No data") }
        if rows.count == 1 {
            return "\(rows[0].overallScore)"
        }
        let recent = Double(rows.prefix(3).map(\.overallScore).reduce(0, +)) / Double(min(3, rows.count))
        let baseline = Double(rows.suffix(3).map(\.overallScore).reduce(0, +)) / Double(min(3, rows.count))
        let delta = Int((recent - baseline).rounded())
        return "\(Int(recent.rounded())) (\(delta >= 0 ? "+" : "")\(delta))"
    }

    private var loopTrendText: String {
        let rows = loopLogs.filter { $0.tempoEndBPM > 0 }
        guard let newest = rows.first, let oldest = rows.dropFirst().last else {
            return rows.first.map { L10n.f("%@ BPM", "\($0.tempoEndBPM)") } ?? String(localized: "No data")
        }
        let delta = newest.tempoEndBPM - oldest.tempoEndBPM
        let prefix = delta >= 0 ? "+" : ""
        return L10n.f("%@ BPM (%@%@)", "\(newest.tempoEndBPM)", prefix, "\(delta)")
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

    private var pieceRows: [PieceDashboardRow] {
        var accumulator: [String: PieceAccumulator] = [:]

        for run in runThroughs {
            let key = normalizedPieceName(from: run.pieceName)
            guard !key.isEmpty else { continue }
            var current = accumulator[key] ?? PieceAccumulator(pieceName: key)
            current.lastPracticed = max(current.lastPracticed ?? .distantPast, run.date)
            current.runThroughCount += 1
            current.totalPracticeSeconds += run.durationSeconds
            current.latestTempo = inferTempo(from: run.notes) ?? current.latestTempo
            if let best = current.bestRating {
                current.bestRating = max(best, run.selfRating)
            } else {
                current.bestRating = run.selfRating
            }
            accumulator[key] = current
        }

        for session in sessions {
            let key = normalizedPieceName(from: session.noteTitle)
            guard !key.isEmpty else { continue }
            var current = accumulator[key] ?? PieceAccumulator(pieceName: key)
            current.lastPracticed = max(current.lastPracticed ?? .distantPast, session.date)
            current.totalPracticeSeconds += session.durationSeconds
            accumulator[key] = current
        }

        return accumulator.values
            .map { entry in
                PieceDashboardRow(
                    pieceName: entry.pieceName,
                    totalMinutes: max(0, entry.totalPracticeSeconds / 60),
                    runThroughCount: entry.runThroughCount,
                    bestRating: entry.bestRating,
                    latestTempo: entry.latestTempo,
                    lastPracticed: entry.lastPracticed ?? .distantPast
                )
            }
            .sorted { lhs, rhs in
                if lhs.lastPracticed == rhs.lastPracticed {
                    return lhs.pieceName.localizedCaseInsensitiveCompare(rhs.pieceName) == .orderedAscending
                }
                return lhs.lastPracticed > rhs.lastPracticed
            }
            .prefix(8)
            .map { $0 }
    }

    private func normalizedPieceName(from raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        let collapsed = value.replacingOccurrences(of: "  ", with: " ")
        if let splitIndex = collapsed.firstIndex(of: "-"), splitIndex > collapsed.startIndex {
            let lead = String(collapsed[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            return lead.isEmpty ? collapsed : lead
        }
        return collapsed
    }

    private func inferTempo(from notes: String) -> Int? {
        let words = notes
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "." || $0 == ":" || $0 == ";" })
            .map(String.init)

        for (index, token) in words.enumerated() {
            if token.lowercased().hasPrefix("tempo"), index + 1 < words.count {
                let raw = words[index + 1].filter(\.isNumber)
                if let bpm = Int(raw), (40...260).contains(bpm) {
                    return bpm
                }
            }
            if token.uppercased() == "BPM", index > 0 {
                let raw = words[index - 1].filter(\.isNumber)
                if let bpm = Int(raw), (40...260).contains(bpm) {
                    return bpm
                }
            }
        }
        return nil
    }

    private func pieceRunThroughs(named pieceName: String) -> [RunThroughModel] {
        let normalized = normalizedPieceName(from: pieceName).lowercased()
        guard !normalized.isEmpty else { return [] }
        return runThroughs.filter {
            normalizedPieceName(from: $0.pieceName).lowercased() == normalized
        }
    }

    private func pieceSessions(named pieceName: String) -> [PracticeSessionModel] {
        let normalized = normalizedPieceName(from: pieceName).lowercased()
        guard !normalized.isEmpty else { return [] }

        return sessions.filter { session in
            let titleMatch = normalizedPieceName(from: session.noteTitle).lowercased() == normalized
            if titleMatch { return true }
            guard let journal = session.journal else { return false }
            return journal.pieces.contains {
                normalizedPieceName(from: $0.title).lowercased() == normalized
            }
        }
    }
}

private struct PieceDashboardRow: Identifiable {
    let id: String
    let pieceName: String
    let totalMinutes: Int
    let runThroughCount: Int
    let bestRating: Int?
    let latestTempo: Int?
    let lastPracticed: Date

    init(
        pieceName: String,
        totalMinutes: Int,
        runThroughCount: Int,
        bestRating: Int?,
        latestTempo: Int?,
        lastPracticed: Date
    ) {
        self.id = pieceName.lowercased()
        self.pieceName = pieceName
        self.totalMinutes = totalMinutes
        self.runThroughCount = runThroughCount
        self.bestRating = bestRating
        self.latestTempo = latestTempo
        self.lastPracticed = lastPracticed
    }
}

private struct PieceAccumulator {
    let pieceName: String
    var totalPracticeSeconds: Int = 0
    var runThroughCount: Int = 0
    var bestRating: Int?
    var latestTempo: Int?
    var lastPracticed: Date?
}

private struct PieceDetailView: View {
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    let pieceName: String
    let sessions: [PracticeSessionModel]
    let runThroughs: [RunThroughModel]
    let latestTempo: Int?

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    private var totalMinutes: Int {
        let fromSessions = sessions.reduce(0) { $0 + max(0, $1.durationSeconds) }
        let fromRuns = runThroughs.reduce(0) { $0 + max(0, $1.durationSeconds) }
        return max(0, (fromSessions + fromRuns) / 60)
    }

    private var bestRating: Int? {
        runThroughs.map(\.selfRating).max()
    }

    private var latestPlayableRunThrough: RunThroughModel? {
        runThroughs.first(where: { !$0.audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private var timelineRows: [PieceTimelineRow] {
        var rows: [PieceTimelineRow] = []

        rows.append(contentsOf: sessions.map {
            PieceTimelineRow(
                date: $0.date,
                title: "Session",
                subtitle: DurationFormatter.string(from: max(0, $0.durationSeconds)),
                detail: $0.noteFocus.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        })

        rows.append(contentsOf: runThroughs.map {
            PieceTimelineRow(
                date: $0.date,
                title: "Run-through",
                subtitle: L10n.f("%@ • %@/5", DurationFormatter.string(from: max(0, $0.durationSeconds)), "\($0.selfRating)"),
                detail: $0.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        })

        return rows.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(pieceName)
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)

                    HStack {
                        Text(L10n.f("%@m total", "\(totalMinutes)"))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                        Spacer()
                        Text(L10n.f("%@ run-throughs", "\(runThroughs.count)"))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }

                    HStack {
                        if let bestRating {
                            Text(L10n.f("Best %@/5", "\(bestRating)"))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }
                        Spacer()
                        if let latestTempo {
                            Text(L10n.f("Tempo %@ BPM", "\(latestTempo)"))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }
                    }

                    if let run = latestPlayableRunThrough {
                        Button(isPlaying ? "Stop Playback" : "Play Latest Run-through") {
                            togglePlayback(for: run)
                        }
                        .buttonStyle(.bordered)
                        .font(type.button)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(palette.surface)

            Section("Timeline") {
                if timelineRows.isEmpty {
                    Text("No entries for this piece yet.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(timelineRows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.title)
                                    .font(type.body)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text(row.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Text(row.subtitle)
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            if !row.detail.isEmpty {
                                Text(row.detail)
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listRowBackground(palette.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(chrome.ignoresSafeArea())
        .navigationTitle("Piece Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            player?.stop()
            player = nil
            isPlaying = false
        }
    }

    private func togglePlayback(for run: RunThroughModel) {
        if isPlaying {
            player?.stop()
            player = nil
            isPlaying = false
            return
        }

        let path = run.audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let fresh = try AVAudioPlayer(contentsOf: url)
            fresh.prepareToPlay()
            fresh.play()
            player = fresh
            isPlaying = true
        } catch {
            player = nil
            isPlaying = false
        }
    }
}

private struct PieceTimelineRow: Identifiable {
    let id = UUID()
    let date: Date
    let title: String
    let subtitle: String
    let detail: String
}
