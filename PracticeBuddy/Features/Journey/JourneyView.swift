import SwiftUI
import Combine

struct JourneyView: View {
    private enum JourneyScrollTarget: String {
        case seasonLadder
    }

    private struct LadderActionUser: Identifiable, Equatable, Hashable {
        let id: String
        let displayName: String
    }

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
    @State private var selectedSection: JourneySection = .overview
    @State private var rewardsMessage: String?
    @State private var didLoadDuelTargets = false
    @State private var duelLeaderboardScope: DuelLeaderboardScope = .global
    @State private var animateHeader = false
    @State private var expandedLadderUserID: String?
    @State private var profileTarget: LadderActionUser?
    @State private var journeyScrollTarget: JourneyScrollTarget?
    @State private var showShopSheet = false
    @State private var showInventorySheet = false
    @State private var showRewardCelebration = false
    @State private var rewardCelebrationToken = 0
    @State private var showDuelFinisherCelebration = false
    @State private var duelFinisherToken = 0
    @State private var didSeedCompletedChallengeIDs = false
    @State private var seenCompletedChallengeIDs: Set<String> = []
    @State private var selectedDuelEntryChallenge: DuelChallenge?
    @State private var duelEntryParticipantCards: [String: DuelParticipantCard] = [:]
    @State private var showDuelReadyAlert = false
    @State private var duelRecordingChallenge: DuelChallenge?
    @State private var duelRecordedMetricsByChallengeID: [String: DuelDerivedMetrics] = [:]
    @StateObject private var playBuddiesVM = BuddiesViewModel()
    @State private var dismissedPlayInviteIDs: Set<String> = []
    @AppStorage("pb.play.openChallengeID") private var openChallengeID: String = ""

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var levelProgress: Double {
        guard journey.xpForNextLevel > 0 else { return 0 }
        return min(1.0, max(0, Double(journey.xpIntoLevel) / Double(journey.xpForNextLevel)))
    }

    private func journeySectionCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
        .listRowInsets(
            EdgeInsets(
                top: 4,
                leading: 0,
                bottom: 4,
                trailing: 0
            )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var playContent: some View {
        VStack(spacing: 0) {
            playShortcutRow
            topSection

            ScrollViewReader { proxy in
                List {
                    if selectedSection == .overview {
                        if !visiblePlayFriendInvites.isEmpty {
                            playFriendRequestBannerSection
                        }
                        levelSection
                        duelLeagueSection
                        questsSection
                        aboutSection
                    } else {
                        rewardsBalanceSection
                        rewardsCatalogSection
                    }
                }
                .onChange(of: journeyScrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                        proxy.scrollTo(target.rawValue, anchor: .top)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: selectedSection)
        }
    }

    private var visualContent: some View {
        playContent
            .background {
                PBBackdropView(palette: palette)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
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
            .alert("Duel Ready", isPresented: $showDuelReadyAlert) {
                Button("Enter") {
                    guard let readyID = duelLeague.readyChallengeID,
                          let challenge = duelLeague.activeChallenges.first(where: { $0.id == readyID }) else {
                        duelLeague.clearReadyChallenge()
                        return
                    }
                    selectedDuelEntryChallenge = challenge
                    duelLeague.clearReadyChallenge()
                }
                Button("Later", role: .cancel) {
                    duelLeague.clearReadyChallenge()
                }
            } message: {
                Text("A duel was accepted. Enter when you are ready to record your take.")
            }
    }

    private var interactiveContent: some View {
        visualContent
        .overlay {
            if showRewardCelebration {
                PBRewardConfettiOverlay(
                    styleID: JourneyProgressManager.activeConfettiStyleID(),
                    token: rewardCelebrationToken
                )
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            if showDuelFinisherCelebration, let finisherStyle = journey.equippedRewardID(for: .duelFinisherFX) {
                PBDuelFinisherOverlay(styleID: finisherStyle, token: duelFinisherToken)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if !animateHeader {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                    animateHeader = true
                }
            }
            if !didSeedCompletedChallengeIDs {
                seenCompletedChallengeIDs = Set(duelLeague.recentCompleted.map(\.id))
                didSeedCompletedChallengeIDs = true
            }
            syncJourneyDuelSnapshot()
            guard !didLoadDuelTargets else { return }
            didLoadDuelTargets = true
            Task {
                await duelLeague.refreshTargetCandidates(force: true)
                await duelLeague.refreshSeasonLeaderboard(scope: duelLeaderboardScope)
                if let uid = firebase.currentUserID {
                    await playBuddiesVM.start(for: uid)
                }
            }
        }
        .task(id: firebase.currentUserID) {
            guard let uid = firebase.currentUserID else { return }
            await playBuddiesVM.start(for: uid)
            consumePendingOpenChallengeID()
        }
        .onChange(of: openChallengeID) { _, _ in
            consumePendingOpenChallengeID()
        }
        .onChange(of: playBuddiesVM.incomingInvites.map(\.id)) { _, ids in
            dismissedPlayInviteIDs.formIntersection(Set(ids))
        }
        .onChange(of: duelLeague.activeChallenges.map(\.id)) { _, _ in
            consumePendingOpenChallengeID()
        }
        .onChange(of: duelLeague.recentCompleted.map(\.id)) { _, ids in
            let current = Set(ids)
            if !didSeedCompletedChallengeIDs {
                seenCompletedChallengeIDs = current
                didSeedCompletedChallengeIDs = true
                return
            }
            let newlyCompleted = current.subtracting(seenCompletedChallengeIDs)
            seenCompletedChallengeIDs = current
            if !newlyCompleted.isEmpty {
                triggerDuelFinisherCelebrationIfNeeded()
            }
        }
        .onChange(of: duelLeague.readyChallengeID) { _, newValue in
            guard newValue != nil else { return }
            showDuelReadyAlert = true
        }
        .onChange(of: duelLeague.duelRating) { _, _ in
            syncJourneyDuelSnapshot()
        }
        .onChange(of: duelLeague.duelWins) { _, _ in
            syncJourneyDuelSnapshot()
        }
        .onChange(of: duelLeague.duelLosses) { _, _ in
            syncJourneyDuelSnapshot()
        }
        .onChange(of: duelLeague.duelDraws) { _, _ in
            syncJourneyDuelSnapshot()
        }
        .navigationDestination(item: $profileTarget) { target in
            PublicUserProfileView(
                userID: target.id,
                fallbackDisplayName: target.displayName
            )
        }
        .sheet(isPresented: $showShopSheet) {
            NavigationStack {
                ShopView()
            }
        }
        .sheet(isPresented: $showInventorySheet) {
            NavigationStack {
                InventoryView()
            }
        }
        .sheet(item: $selectedDuelEntryChallenge) { challenge in
            NavigationStack {
                duelEntrySheet(challenge: challenge)
            }
            .presentationDetents([.medium, .large])
            .task(id: challenge.id) {
                duelEntryParticipantCards = await duelLeague.fetchParticipantCards(for: challenge)
            }
        }
        .sheet(item: $duelRecordingChallenge) { challenge in
            NavigationStack {
                DuelRecordingCaptureView(challenge: challenge) { metrics in
                    duelRecordedMetricsByChallengeID[challenge.id] = metrics
                }
            }
        }
    }

    var body: some View {
        interactiveContent
    }

    private func triggerRewardCelebration() {
        rewardCelebrationToken += 1
        withAnimation(.easeOut(duration: 0.18)) {
            showRewardCelebration = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            withAnimation(.easeIn(duration: 0.18)) {
                showRewardCelebration = false
            }
        }
    }

    private func triggerDuelFinisherCelebrationIfNeeded() {
        guard journey.equippedRewardID(for: .duelFinisherFX) != nil else { return }
        duelFinisherToken += 1
        withAnimation(.easeOut(duration: 0.18)) {
            showDuelFinisherCelebration = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation(.easeIn(duration: 0.18)) {
                showDuelFinisherCelebration = false
            }
        }
    }

    private var visiblePlayFriendInvites: [BuddyInvite] {
        playBuddiesVM.incomingInvites.filter { !dismissedPlayInviteIDs.contains($0.id) }
    }

    private func consumePendingOpenChallengeID() {
        let targetID = openChallengeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetID.isEmpty else { return }
        guard let challenge = duelLeague.activeChallenges.first(where: { $0.id == targetID }) else { return }
        openChallengeID = ""
        selectedDuelEntryChallenge = challenge
    }

    private func syncJourneyDuelSnapshot() {
        journey.handleDuelSnapshot(
            rating: duelLeague.duelRating,
            wins: duelLeague.duelWins,
            losses: duelLeague.duelLosses,
            draws: duelLeague.duelDraws
        )
    }

    private var playFriendRequestBannerSection: some View {
        Section {
            journeySectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visiblePlayFriendInvites) { invite in
                        HStack(spacing: 10) {
                            Image(systemName: "person.badge.plus")
                                .foregroundStyle(palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(invite.fromDisplayName) sent a friend request")
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textPrimary)
                                Text(invite.fromFriendCode)
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            Button("Accept") {
                                Task {
                                    await playBuddiesVM.acceptInvite(invite)
                                    dismissedPlayInviteIDs.insert(invite.id)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(palette.accent)
                            .font(type.footnote)
                            Button("Decline", role: .destructive) {
                                Task {
                                    await playBuddiesVM.declineInvite(invite)
                                    dismissedPlayInviteIDs.insert(invite.id)
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(type.footnote)
                        }
                        .padding(10)
                        .pbSurfaceCard(palette: palette)
                    }
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Pending Friend Requests")
        }
    }

    private var playShortcutRow: some View {
        PBShortcutBar(items: playShortcutItems, palette: palette)
            .padding(.horizontal, PBLayout.padSM)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .offset(y: animateHeader ? 0 : 10)
            .opacity(animateHeader ? 1 : 0)
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
        .pbFlatCard(palette: palette)
        .padding(.horizontal, PBLayout.padSM)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .offset(y: animateHeader ? 0 : 12)
        .opacity(animateHeader ? 1 : 0)
    }

    private var playShortcutItems: [PBShortcutItem] {
        let isQueuedForOpenDuel = duelLeague.myOpenChallenge != nil
        return [
            PBShortcutItem(
                id: "play_queue",
                title: isQueuedForOpenDuel ? "Cancel Queue" : "Queue Duel",
                systemImage: isQueuedForOpenDuel ? "xmark.circle.fill" : "bolt.horizontal.circle.fill",
                isDisabled: duelLeague.isLoading || firebase.currentUserID == nil || firebase.isAnonymousUser,
                action: {
                    Task {
                        if isQueuedForOpenDuel {
                            await duelLeague.cancelOpenChallenge()
                        } else {
                            await duelLeague.queueAsyncScaleDuel(octaves: duelLeague.activeLeagueRequirement.octaves)
                        }
                    }
                }
            ),
            PBShortcutItem(
                id: "play_ladder",
                title: "Leaderboard",
                systemImage: "list.number",
                action: {
                    selectedSection = .overview
                    duelLeaderboardScope = .global
                    journeyScrollTarget = .seasonLadder
                    Task {
                        await duelLeague.refreshSeasonLeaderboard(scope: .global)
                    }
                }
            ),
            PBShortcutItem(
                id: "play_store",
                title: "Shop",
                systemImage: "bag.fill",
                action: { showShopSheet = true }
            )
        ]
    }

    private var levelSection: some View {
        Section {
            journeySectionCard {
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
            }
        } header: {
            PBSectionHeaderLabel(title: "Progress Level")
        }
    }

    private var duelLeagueSection: some View {
        Section {
            journeySectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("League")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(duelLeague.leagueTier.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(leagueChipTextColor(for: duelLeague.leagueTier))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(leagueChipColor(for: duelLeague.leagueTier).opacity(0.2))
                        .clipShape(Capsule())
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

                Text("League requirement: \(duelLeague.activeLeagueRequirement.summary)")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
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
                PBHaptics.tap()
                Task {
                    if isQueuedForOpenDuel {
                        await duelLeague.cancelOpenChallenge()
                    } else {
                        await duelLeague.queueAsyncScaleDuel(octaves: duelLeague.activeLeagueRequirement.octaves)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isQueuedForOpenDuel ? "xmark.circle.fill" : "bolt.horizontal.circle.fill")
                    Text(isQueuedForOpenDuel ? "Cancel Queue" : "Queue Duel")
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
            .disabled(duelLeague.isLoading || duelLeague.isActionBusy || firebase.currentUserID == nil || firebase.isAnonymousUser)

            HStack {
                Menu {
                    if duelLeague.friendCandidates.isEmpty {
                        Text("No friend targets")
                    } else {
                        ForEach(duelLeague.friendCandidates) { candidate in
                            Button(candidate.displayName) {
                                PBHaptics.tap()
                                Task { await duelLeague.inviteTargetedDuel(targetUID: candidate.id, source: .friend, octaves: duelLeague.activeLeagueRequirement.octaves) }
                            }
                        }
                    }
                } label: {
                    Label("Invite Friend", systemImage: "person.badge.plus")
                }
                .buttonStyle(PBActionButtonStyle(variant: .secondary, palette: palette))
                .disabled(duelLeague.isActionBusy || firebase.currentUserID == nil || firebase.isAnonymousUser)

                Menu {
                    if duelLeague.studioCandidates.isEmpty {
                        Text("No studio targets")
                    } else {
                        ForEach(duelLeague.studioCandidates) { candidate in
                            Button(candidate.displayName) {
                                PBHaptics.tap()
                                Task { await duelLeague.inviteTargetedDuel(targetUID: candidate.id, source: .studio, octaves: duelLeague.activeLeagueRequirement.octaves) }
                            }
                        }
                    }
                } label: {
                    Label("Invite Studio", systemImage: "person.3")
                }
                .buttonStyle(PBActionButtonStyle(variant: .secondary, palette: palette))
                .disabled(duelLeague.isActionBusy || firebase.currentUserID == nil || firebase.isAnonymousUser)
            }

            if !duelLeague.incomingInvites.isEmpty {
                DisclosureGroup("Incoming Invites (\(duelLeague.incomingInvites.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(duelLeague.incomingInvites) { challenge in
                            incomingInviteRow(challenge)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(type.footnote)
                .foregroundStyle(palette.textPrimary)
            }

            if !duelLeague.outgoingInvites.isEmpty {
                DisclosureGroup("Outgoing Invites (\(duelLeague.outgoingInvites.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(duelLeague.outgoingInvites) { challenge in
                            outgoingInviteRow(challenge)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(type.footnote)
                .foregroundStyle(palette.textPrimary)
            }

            if !duelLeague.activeChallenges.isEmpty {
                DisclosureGroup("Active Duels (\(duelLeague.activeChallenges.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(duelLeague.activeChallenges) { challenge in
                            duelChallengeRow(challenge)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(type.footnote)
                .foregroundStyle(palette.textPrimary)
            }

            if !duelLeague.recentCompleted.isEmpty {
                DisclosureGroup("Recent Results") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(duelLeague.recentCompleted.prefix(3)) { challenge in
                            duelCompletedRow(challenge)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(type.footnote)
                .foregroundStyle(palette.textPrimary)
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
                    Task { await duelLeague.refreshSeasonLeaderboard(scope: newValue) }
                }

                if duelLeague.isLoading {
                    VStack(spacing: 8) {
                        PBSkeletonCard(lines: 2)
                        PBSkeletonCard(lines: 2)
                        PBSkeletonCard(lines: 2)
                    }
                    .padding(.vertical, 2)
                } else if duelLeague.leaderboardRows.isEmpty {
                    Text("No ladder data yet for this scope.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(Array(duelLeague.leaderboardRows.enumerated()), id: \.element.id) { idx, row in
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    expandedLadderUserID = (expandedLadderUserID == row.id) ? nil : row.id
                                }
                            } label: {
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
                                    Text(L10n.f("Rating %@", "\(row.rating)"))
                                        .font(type.footnote)
                                        .foregroundStyle(palette.textSecondary)
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)

                            if expandedLadderUserID == row.id {
                                HStack(spacing: 8) {
                                    Button("Go to Profile") {
                                        profileTarget = LadderActionUser(id: row.id, displayName: row.displayName)
                                        expandedLadderUserID = nil
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Duel Challenge") {
                                        Task {
                                            duelLeague.rememberDisplayName(uid: row.id, name: row.displayName)
                                            let source: DuelInviteSource = duelLeaderboardScope == .studio ? .studio : .friend
                                            await duelLeague.inviteTargetedDuel(targetUID: row.id, source: source, octaves: duelLeague.activeLeagueRequirement.octaves)
                                        }
                                        expandedLadderUserID = nil
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(firebase.currentUserID == row.id || firebase.isAnonymousUser)
                                }
                                .font(type.footnote)
                            }
                        }
                    }
                }
            }
            .id(JourneyScrollTarget.seasonLadder.rawValue)

            if let status = duelLeague.statusMessage, !status.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(palette.accent)
                    Text(LocalizedStringKey(status))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, 4)
            }

            if let recoverable = duelLeague.recoverableActionError {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.trianglehead.clockwise")
                        .foregroundStyle(palette.accent)
                    Text(LocalizedStringKey(recoverable.message))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Button(recoverable.retryTitle) {
                        Task { await duelLeague.retryRecoverableAction() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .disabled(duelLeague.isActionBusy)

                    Button("Dismiss") {
                        duelLeague.clearRecoverableActionError()
                    }
                    .buttonStyle(.bordered)
                    .disabled(duelLeague.isActionBusy)
                }
                .padding(.top, 4)
            }
            }
        } header: {
            PBSectionHeaderLabel(title: "Duels & League")
        }
    }

    @ViewBuilder
    private func duelChallengeRow(_ challenge: DuelChallenge) -> some View {
        let uid = firebase.currentUserID ?? ""
        let myScore = challenge.myScore(for: uid)
        let oppScore = challenge.opponentScore(for: uid)
        let otherRaw = challenge.otherParticipant(for: uid) ?? "pending"
        let other = otherRaw.count > 6 ? "\(otherRaw.prefix(6))..." : otherRaw
        let recorded = duelRecordedMetricsByChallengeID[challenge.id]
        let submitActionKey = "submitAttempt:\(challenge.id)"
        let isSubmitting = duelLeague.isActionInFlight(for: submitActionKey)

        sessionCardSkinContainer {
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

                statusBadge(
                    text: duelStateLabel(for: challenge, viewerUID: uid),
                    style: .info
                )

                Button("Enter") {
                    selectedDuelEntryChallenge = challenge
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .disabled(duelLeague.isActionBusy)

                if let deadline = challenge.submissionDeadlineAt {
                    statusBadge(
                        text: "Submission deadline: \(relativeTimeString(until: deadline))",
                        style: .warning
                    )
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
                    if let recorded {
                        Text(
                            L10n.f(
                                "Derived score %@ (I %@ • R %@ • C %@)",
                                "\(recorded.derivedScore)",
                                "\(recorded.intonationScore)",
                                "\(recorded.rhythmScore)",
                                "\(recorded.consistencyScore)"
                            )
                        )
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()

                        Button("Submit Recorded Take") {
                            Task {
                                await duelLeague.submitDerivedAttempt(
                                    challengeID: challenge.id,
                                    metrics: recorded,
                                    requiredMinTempoBPM: challenge.requiredMinTempoBPM
                                )
                                await duelLeague.refreshSeasonLeaderboard(scope: duelLeaderboardScope)
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(type.footnote)
                        .disabled(isSubmitting || duelLeague.isActionBusy)
                        if isSubmitting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Submitting...")
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    } else {
                        Text("Record a dedicated duel take to submit.")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
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

        return sessionCardSkinContainer {
            HStack {
                Text(L10n.f("%@-%@", "\(myScore)", "\(oppScore)"))
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Spacer()
                Text(delta >= 0 ? L10n.f("+%@", "\(delta)") : "\(delta)")
                    .font(type.number)
                    .foregroundStyle(delta >= 0 ? palette.accent : palette.textSecondary)
                    .monospacedDigit()
                statusBadge(text: "Settled", style: .success)
            }
            .padding(.vertical, 2)
        }
    }

    private func incomingInviteRow(_ challenge: DuelChallenge) -> some View {
        let uid = firebase.currentUserID ?? ""
        let otherUID = challenge.otherParticipant(for: uid) ?? ""
        let other = duelLeague.userDisplayNames[otherUID] ?? shortUserLabel(otherUID)
        let queueLabel = challenge.queueType == .friend ? "Friend duel" : "Studio duel"
        return sessionCardSkinContainer {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.f("%@ invite", queueLabel))
                    .font(type.footnote)
                    .foregroundStyle(palette.textPrimary)
                Text(L10n.f("From %@", other))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                statusBadge(
                    text: "Pending",
                    style: .info
                )
                HStack {
                    Button("Accept") {
                        PBHaptics.tap()
                        Task { await duelLeague.acceptInvite(challengeID: challenge.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .disabled(duelLeague.isActionInFlight(for: "acceptInvite:\(challenge.id)") || duelLeague.isActionBusy)

                    Button("Decline", role: .destructive) {
                        PBHaptics.tap()
                        Task { await duelLeague.declineInvite(challengeID: challenge.id) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(duelLeague.isActionInFlight(for: "declineInvite:\(challenge.id)") || duelLeague.isActionBusy)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func outgoingInviteRow(_ challenge: DuelChallenge) -> some View {
        let uid = firebase.currentUserID ?? ""
        let otherUID = challenge.otherParticipant(for: uid) ?? ""
        let other = duelLeague.userDisplayNames[otherUID] ?? shortUserLabel(otherUID)
        let queueLabel = challenge.queueType == .friend ? "Friend duel" : "Studio duel"
        return sessionCardSkinContainer {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.circle.fill")
                        .foregroundStyle(palette.accent)
                        .font(.system(size: 17, weight: .semibold))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.f("%@ invite", queueLabel))
                            .font(type.footnote)
                            .foregroundStyle(palette.textPrimary)
                        Text(L10n.f("To %@", other))
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)
                    }
                    Spacer()
                    statusBadge(
                        text: "Pending",
                        style: .info
                    )
                }
                HStack {
                    Button("Cancel Request", role: .destructive) {
                        PBHaptics.tap()
                        Task { await duelLeague.cancelInvite(challengeID: challenge.id) }
                    }
                    .buttonStyle(.bordered)
                    .font(type.footnote)
                    .disabled(duelLeague.isActionInFlight(for: "cancelInvite:\(challenge.id)") || duelLeague.isActionBusy)
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(10)
            .background(palette.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
        }
    }

    private enum DuelStatusBadgeStyle {
        case info
        case warning
        case success
    }

    private func statusBadge(text: String, style: DuelStatusBadgeStyle) -> some View {
        let bg: Color
        let fg: Color
        switch style {
        case .info:
            bg = palette.accent.opacity(0.14)
            fg = palette.textPrimary
        case .warning:
            bg = Color.orange.opacity(0.18)
            fg = palette.textPrimary
        case .success:
            bg = Color.green.opacity(0.18)
            fg = palette.textPrimary
        }

        return Text(text)
            .font(type.footnote)
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .clipShape(Capsule())
    }

    private func duelStateLabel(for challenge: DuelChallenge, viewerUID: String) -> String {
        switch challenge.status {
        case .open, .invited:
            return "Pending"
        case .active:
            if challenge.myScore(for: viewerUID) != nil {
                return "Recording Submitted"
            }
            return "Accepted"
        case .completed:
            return "Settled"
        case .canceled:
            return "Settled"
        }
    }

    private func relativeTimeString(until date: Date) -> String {
        let delta = Int(date.timeIntervalSinceNow)
        if delta <= 0 { return "expired" }
        let hours = delta / 3600
        if hours >= 1 {
            let mins = (delta % 3600) / 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        let mins = max(1, delta / 60)
        return "\(mins)m"
    }

    @ViewBuilder
    private func duelEntryHeaderCard(challenge: DuelChallenge) -> some View {
        let introID = journey.equippedRewardID(for: .duelIntroCard)
        if introID == "reward_duel_intro_card_spotlight" {
            VStack(alignment: .leading, spacing: 4) {
                Text("Duel Match")
                    .font(type.sectionTitle)
                    .foregroundStyle(Color.white)
                Text(challenge.objective)
                    .font(type.footnote)
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.accent.opacity(0.88),
                                palette.accent.opacity(0.68),
                                palette.surfaceAlt.opacity(0.92)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Duel Match")
                    .font(type.sectionTitle)
                    .foregroundStyle(palette.textPrimary)
                Text(challenge.objective)
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(12)
            .pbSurfaceCard(palette: palette)
        }
    }

    @ViewBuilder
    private func sessionCardSkinContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if journey.equippedRewardID(for: .sessionCardSkin) == "reward_session_card_skin_aurora" {
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.accent.opacity(0.16),
                                    palette.surfaceAlt.opacity(0.94),
                                    palette.accent.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                                .stroke(palette.accent.opacity(0.22), lineWidth: 1)
                        )
                )
        } else {
            content()
        }
    }

    @ViewBuilder
    private func duelEntrySheet(challenge: DuelChallenge) -> some View {
        let uid = firebase.currentUserID ?? ""
        let opponentUID = challenge.otherParticipant(for: uid) ?? ""
        let userA = duelEntryParticipantCards[opponentUID]
        let userB = duelEntryParticipantCards[uid]
        let hasSubmitted = challenge.myScore(for: uid) != nil
        let recordedMetrics = duelRecordedMetricsByChallengeID[challenge.id]

        VStack(alignment: .leading, spacing: 14) {
            duelEntryHeaderCard(challenge: challenge)

            VStack(alignment: .leading, spacing: 8) {
                Text("User A")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                HStack {
                    Text(userA?.displayName ?? "Opponent")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("Lv \(userA?.publicLevel ?? 1) • Rating \(userA?.duelRating ?? 0)")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }
            .padding(10)
            .pbSurfaceCard(palette: palette)

            Text("vs")
                .font(type.body.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 8) {
                Text("User B")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                HStack {
                    Text(userB?.displayName ?? "You")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("Lv \(userB?.publicLevel ?? 1) • Rating \(userB?.duelRating ?? 0)")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }
            .padding(10)
            .pbSurfaceCard(palette: palette)

            HStack(spacing: 10) {
                Button("Record your take") {
                    duelRecordingChallenge = challenge
                }
                .buttonStyle(PBActionButtonStyle(variant: .secondary, palette: palette))

                Button(hasSubmitted ? "Done" : "Done (Submit Recorded Take)") {
                    Task {
                        if !hasSubmitted, let recordedMetrics {
                            await duelLeague.submitDerivedAttempt(
                                challengeID: challenge.id,
                                metrics: recordedMetrics,
                                requiredMinTempoBPM: challenge.requiredMinTempoBPM
                            )
                            await duelLeague.refreshSeasonLeaderboard(scope: duelLeaderboardScope)
                            duelRecordedMetricsByChallengeID[challenge.id] = nil
                        }
                        selectedDuelEntryChallenge = nil
                    }
                }
                .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
                .disabled(!hasSubmitted && recordedMetrics == nil)
            }

            if !hasSubmitted && recordedMetrics == nil {
                Text("After recording, Done will submit your dedicated duel take.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(PBLayout.padLG)
        .background(PBBackdropView(palette: palette))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func shortUserLabel(_ uid: String) -> String {
        guard !uid.isEmpty else { return "Unknown" }
        return uid.count > 8 ? "\(uid.prefix(8))…" : uid
    }

    private func leagueChipColor(for tier: DuelLeagueTier) -> Color {
        switch tier {
        case .gold:
            return .yellow
        case .silver:
            return .gray
        case .bronze:
            return .brown
        case .platinum:
            return .mint
        case .emerald:
            return .green
        case .diamond:
            return .cyan
        case .master:
            return .indigo
        case .grandmaster:
            return .orange
        }
    }

    private func leagueChipTextColor(for tier: DuelLeagueTier) -> Color {
        switch tier {
        case .gold:
            return .yellow
        case .silver:
            return .gray
        case .bronze:
            return .brown
        case .platinum:
            return .mint
        case .emerald:
            return .green
        case .diamond:
            return .cyan
        case .master:
            return .indigo
        case .grandmaster:
            return .orange
        }
    }

    private var questsSection: some View {
        Section {
            journeySectionCard {
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
        } header: {
            PBSectionHeaderLabel(title: "Quests")
        }
    }

    private var rewardsBalanceSection: some View {
        Section {
            journeySectionCard {
                sessionCardSkinContainer {
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

                        Button {
                            showInventorySheet = true
                        } label: {
                            Label("Open Inventory", systemImage: "shippingbox.fill")
                                .font(type.button)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Token Balance")
        }
    }

    private var rewardsCatalogSection: some View {
        Section {
            journeySectionCard {
                ForEach(Array(journey.rewards.enumerated()), id: \.element.id) { idx, item in
                    sessionCardSkinContainer {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(LocalizedStringKey(item.title))
                                    .font(type.body)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                if item.isOwned {
                                    Text(item.isEquipped ? "Equipped" : "Owned")
                                        .font(type.footnote)
                                        .foregroundStyle(item.isEquipped ? palette.accent : palette.textSecondary)
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

                            Text(item.category.title)
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)

                        if !item.isOwned {
                            Button {
                                Task {
                                    if await journey.claimRewardItem(id: item.id) {
                                        rewardsMessage = "Reward unlocked."
                                        triggerRewardCelebration()
                                    } else {
                                        rewardsMessage = "Not enough tokens yet."
                                    }
                                }
                            } label: {
                                Text("Claim Reward")
                                    .font(type.button)
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(palette.accent)
                                .disabled(journey.isEconomyOperationInProgress)
                            } else if !item.isEquipped {
                                Button {
                                    Task {
                                        if await journey.equipRewardItem(id: item.id) {
                                            rewardsMessage = "Item equipped."
                                        }
                                    }
                                } label: {
                                    Text("Equip")
                                        .font(type.button)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(journey.isEconomyOperationInProgress)
                            }

                            if journey.isEconomyOperationInProgress {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Updating...")
                                        .font(type.footnote)
                                }
                                .foregroundStyle(palette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if idx < journey.rewards.count - 1 {
                        Divider()
                    }
                }
            }
        } header: {
            PBSectionHeaderLabel(title: "Reward Catalog")
        }
    }

    private var aboutSection: some View {
        Section {
            journeySectionCard {
                Text("1 verified minute = 1 XP. XP is awarded when a session is completed and saved.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)

                Text("Quest rewards are tokens for future rewards and cosmetics.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        } header: {
            PBSectionHeaderLabel(title: "How XP Works")
        }
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
                        Task {
                            if await journey.claimQuestReward(for: quest, period: period) {
                                rewardsMessage = L10n.f("Claimed %@ tokens.", "\(quest.rewardTokens)")
                                triggerRewardCelebration()
                            }
                        }
                    } label: {
                        Text(L10n.f("Claim +%@", "\(quest.rewardTokens)"))
                    }
                    .font(type.footnote)
                    .buttonStyle(.bordered)
                    .tint(palette.accent)
                    .disabled(journey.isEconomyOperationInProgress)
                    if journey.isEconomyOperationInProgress {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.75)
                            Text("Updating...")
                                .font(type.footnote)
                        }
                        .foregroundStyle(palette.textSecondary)
                    }
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

private struct PBRewardConfettiOverlay: View {
    let styleID: String
    let token: Int

    @State private var animate = false

    private var colors: [Color] {
        if styleID == "reward_confetti_spark" {
            return [.yellow, .orange, .mint, .cyan, .pink]
        }
        return [.blue, .green, .orange, .purple, .red]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<16, id: \.self) { index in
                    let xSeed = Double((index * 37) % 100) / 100.0
                    let ySeed = Double((index * 53) % 100) / 100.0
                    Circle()
                        .fill(colors[index % colors.count].opacity(0.9))
                        .frame(width: 7, height: 7)
                        .position(
                            x: animate ? proxy.size.width * xSeed : proxy.size.width * 0.5,
                            y: animate ? proxy.size.height * (0.16 + ySeed * 0.42) : proxy.size.height * 0.1
                        )
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeOut(duration: 0.95).delay(Double(index) * 0.01),
                            value: animate
                        )
                }
            }
        }
        .onChange(of: token) { _, _ in
            animate = false
            DispatchQueue.main.async {
                animate = true
            }
        }
        .onAppear {
            animate = true
        }
    }
}

private struct PBDuelFinisherOverlay: View {
    let styleID: String
    let token: Int

    @State private var animate = false

    private var highlight: Color {
        if styleID == "reward_duel_finisher_fx_resonance" {
            return .mint
        }
        return .blue
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .stroke(highlight.opacity(0.55), lineWidth: 2)
                    .frame(width: animate ? proxy.size.width * 0.72 : 24, height: animate ? proxy.size.width * 0.72 : 24)
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: 1.05), value: animate)

                Circle()
                    .stroke(highlight.opacity(0.36), lineWidth: 2)
                    .frame(width: animate ? proxy.size.width * 0.52 : 20, height: animate ? proxy.size.width * 0.52 : 20)
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: 1.0).delay(0.07), value: animate)

                VStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(highlight)
                    Text("Duel Finalized")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.38))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(animate ? 1.0 : 0.82)
                .opacity(animate ? 0 : 1)
                .animation(.easeOut(duration: 1.0), value: animate)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            animate = false
            DispatchQueue.main.async {
                animate = true
            }
        }
        .onChange(of: token) { _, _ in
            animate = false
            DispatchQueue.main.async {
                animate = true
            }
        }
    }
}

private struct DuelRecordingCaptureView: View {
    let challenge: DuelChallenge
    let onComplete: (DuelDerivedMetrics) -> Void

    private enum Phase {
        case ready
        case preRoll
        case intonation
        case rhythm
        case complete
    }

    private struct IntonationAggregate {
        var totalSamples: Int = 0
        var inScaleSamples: Int = 0
        var inScaleCents: [Double] = []
        var inScalePitchClasses: Set<Int> = []
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var duelLeague: DuelLeagueManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var tuner = TunerEngine()
    @StateObject private var rhythmEngine = RhythmAccuracyEngine()
    @StateObject private var metronome = MetronomeEngine()

    @State private var phase: Phase = .ready
    @State private var preRollStartedAt: Date?
    @State private var preRollSeconds: Int = 5
    @State private var intonationRunning = false
    @State private var intonationStartedAt: Date?
    @State private var aggregate = IntonationAggregate()
    @State private var intonationScore: Int = 0
    @State private var intonationConsistency: Int = 0
    @State private var rhythmRunning = false
    @State private var rhythmBPM: Int = 72
    @State private var statusMessage: String?
    @State private var finalMetrics: DuelDerivedMetrics?

    private let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var intonationDuration: TimeInterval {
        switch challenge.octaveCount {
        case 3: return 50
        case 2: return 36
        default: return 24
        }
    }
    private var rhythmTargetBeats: Int {
        let base: Int
        switch challenge.octaveCount {
        case 3: base = 32
        case 2: base = 24
        default: base = 16
        }
        switch strictnessTier {
        case 7: return base + 12
        case 6: return base + 10
        case 5: return base + 8
        case 4: return base + 6
        case 3: return base + 4
        default: return base
        }
    }
    private var scaleDescriptor: String {
        let raw = challenge.scaleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty { return raw }
        return challenge.objective.split(separator: "•").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? "C major"
    }
    private var allowedPitchClasses: Set<Int> {
        scalePitchClasses(for: scaleDescriptor)
    }
    private var allowedPitchNamesText: String {
        let names = allowedPitchClasses.sorted().map(noteName(for:))
        return names.joined(separator: " - ")
    }
    private var inScaleRatio: Double {
        guard aggregate.totalSamples > 0 else { return 0 }
        return Double(aggregate.inScaleSamples) / Double(aggregate.totalSamples)
    }
    private var minimumRhythmBPM: Int {
        max(50, min(220, challenge.requiredMinTempoBPM > 0 ? challenge.requiredMinTempoBPM : 50))
    }
    private var challengeLeagueTier: DuelLeagueTier {
        if let raw = challenge.requiredLeague?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let tier = DuelLeagueTier(rawValue: raw) {
            return tier
        }
        return DuelLeagueTier.forRating(duelLeague.duelRating)
    }
    private var strictnessTier: Int {
        challengeLeagueTier.difficultyRank
    }
    private var strictnessLabel: String {
        switch strictnessTier {
        case 7: return "Grandmaster"
        case 6: return "Master"
        case 5: return "Diamond"
        case 4: return "Emerald"
        case 3: return "Platinum"
        case 2: return "Gold"
        case 1: return "Silver"
        default: return "Bronze"
        }
    }
    private var minIntonationSamples: Int {
        let base: Int
        switch challenge.octaveCount {
        case 3: base = 180
        case 2: base = 130
        default: base = 90
        }
        let multiplier = 0.80 + (Double(strictnessTier) * 0.07)
        return Int(Double(base) * multiplier)
    }
    private var minUniqueScaleTones: Int {
        let base: Int
        switch challenge.octaveCount {
        case 3: base = 6
        case 2: base = 5
        default: base = 4
        }
        return min(7, max(3, base - 1 + (strictnessTier / 2)))
    }
    private var minInScaleRatio: Double {
        min(0.82, 0.45 + (Double(strictnessTier) * 0.05))
    }
    private var intonationPassed: Bool {
        aggregate.totalSamples >= minIntonationSamples &&
            aggregate.inScaleSamples > 0 &&
            inScaleRatio >= minInScaleRatio &&
            aggregate.inScalePitchClasses.count >= minUniqueScaleTones
    }

    var body: some View {
        Form {
            Section("Duel Objective") {
                Text(challenge.objective)
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Text("Scale collection: \(allowedPitchNamesText)")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                Text("Analysis mode: \(strictnessLabel)")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                if challenge.requiredMinTempoBPM > 0 {
                    Text("Required tempo floor: \(challenge.requiredMinTempoBPM)+ BPM")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
                Text("Repeats are allowed. Scoring uses in-scale pitch collection match + tuning quality.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            .listRowBackground(Color.clear)

            intonationSection
            rhythmSection

            if let finalMetrics {
                Section("Ready to Submit") {
                    Text(
                        L10n.f(
                            "Derived %@ (I %@ • R %@ • C %@)",
                            "\(finalMetrics.derivedScore)",
                            "\(finalMetrics.intonationScore)",
                            "\(finalMetrics.rhythmScore)",
                            "\(finalMetrics.consistencyScore)"
                        )
                    )
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()

                    Button("Use This Take") {
                        onComplete(finalMetrics)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                }
                .listRowBackground(Color.clear)
            }

            if let statusMessage, !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PBBackdropView(palette: palette))
        .navigationTitle("Record Duel Take")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { _ in
            captureTick()
        }
        .onChange(of: rhythmEngine.summary?.beatsAnalyzed) { _, _ in
            guard let summary = rhythmEngine.summary else { return }
            rhythmRunning = false
            metronome.stop()
            buildFinalMetrics(rhythmSummary: summary)
        }
        .onDisappear {
            stopAllCapture()
        }
    }

    private var intonationSection: some View {
        Section("Step 1 • Intonation") {
            switch phase {
            case .preRoll:
                HStack {
                    Text("Starting in")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(preRollSeconds)")
                        .font(type.timer)
                        .foregroundStyle(palette.accent)
                        .monospacedDigit()
                }
            case .intonation:
                let remaining = max(0, Int((intonationDuration - Date().timeIntervalSince(intonationStartedAt ?? .now)).rounded()))
                HStack {
                    Text("Recording")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(remaining)s")
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            default:
                Text("Press Record. A 5s countdown starts, then capture begins.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }

            HStack {
                Text("Detected")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(tuner.detectedNoteName)
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
            }

            HStack {
                Text("Samples")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(aggregate.totalSamples)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("In-scale")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(aggregate.inScaleSamples) (\(Int((inScaleRatio * 100).rounded()))%)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("Unique scale tones hit")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(aggregate.inScalePitchClasses.count)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            if !intonationRunning && aggregate.totalSamples > 0 {
                Text("Score \(intonationScore) • Consistency \(intonationConsistency)")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            Button(phase == .preRoll || intonationRunning ? "Stop Intonation" : "Record Intonation") {
                if phase == .preRoll || intonationRunning {
                    stopIntonation()
                    finalizeIntonation()
                } else {
                    startIntonationWithPreRoll()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .disabled(!(phase == .ready || phase == .complete || phase == .preRoll || phase == .intonation))
        }
        .listRowBackground(Color.clear)
    }

    private var rhythmSection: some View {
        Section("Step 2 • Rhythm") {
            Text("Play with steady pulse. Target beats: \(rhythmTargetBeats).")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

            Stepper(L10n.f("Tempo: %@ BPM", "\(rhythmBPM)"), value: $rhythmBPM, in: minimumRhythmBPM...220)
                .font(type.body)
                .disabled(rhythmRunning)

            if let summary = rhythmEngine.summary {
                Text(
                    L10n.f(
                        "Groove %@ • Avg %@ ms • Beats %@",
                        "\(summary.grooveScore)",
                        String(format: "%+.1f", summary.averageOffsetMs),
                        "\(summary.beatsAnalyzed)"
                    )
                )
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
            } else if rhythmRunning {
                Text("Listening…")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }

            Button(rhythmRunning ? "Stop Rhythm" : "Start Rhythm") {
                if rhythmRunning {
                    stopRhythm()
                } else {
                    startRhythm()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .disabled((phase != .rhythm && phase != .complete) || !intonationPassed)
        }
        .listRowBackground(Color.clear)
    }

    private func startIntonationWithPreRoll() {
        stopAllCapture()
        finalMetrics = nil
        statusMessage = nil
        aggregate = IntonationAggregate()
        intonationScore = 0
        intonationConsistency = 0
        phase = .preRoll
        preRollSeconds = 5
        preRollStartedAt = Date()
        tuner.requestMicPermissionAndStart()
    }

    private func startIntonationCaptureNow() {
        preRollStartedAt = nil
        preRollSeconds = 0
        intonationStartedAt = Date()
        intonationRunning = true
        phase = .intonation
    }

    private func stopIntonation() {
        intonationRunning = false
        preRollStartedAt = nil
        preRollSeconds = 0
        intonationStartedAt = nil
        tuner.stopListening()
        if phase == .preRoll || phase == .intonation {
            phase = .ready
        }
    }

    private func captureTick() {
        if phase == .preRoll, let started = preRollStartedAt {
            let elapsed = Date().timeIntervalSince(started)
            let remaining = max(0, Int(ceil(5.0 - elapsed)))
            preRollSeconds = remaining
            if elapsed >= 5.0 {
                startIntonationCaptureNow()
            }
            return
        }

        guard intonationRunning, phase == .intonation else { return }
        guard let started = intonationStartedAt else { return }

        if let frequency = tuner.detectedFrequency, tuner.inputLevel > 0.003 {
            registerFrequency(frequency)
        }

        if Date().timeIntervalSince(started) >= intonationDuration {
            stopIntonation()
            finalizeIntonation()
        }
    }

    private func registerFrequency(_ frequency: Double) {
        let midi = 69.0 + 12.0 * log2(frequency / 440.0)
        let roundedMidi = Int(midi.rounded())
        let pitchClass = positiveModulo(roundedMidi, 12)

        aggregate.totalSamples += 1
        if allowedPitchClasses.contains(pitchClass) {
            let delta = nearestAllowedCentsDelta(for: midi)
            aggregate.inScaleSamples += 1
            aggregate.inScaleCents.append(delta)
            aggregate.inScalePitchClasses.insert(pitchClass)
        }
    }

    private func finalizeIntonation() {
        guard aggregate.totalSamples > 0 else {
            statusMessage = "No usable signal captured. Try again."
            return
        }
        guard aggregate.inScaleSamples > 0 else {
            statusMessage = "No in-scale notes detected. Try again."
            return
        }

        let meanAbs = aggregate.inScaleCents.map { abs($0) }.reduce(0, +) / Double(aggregate.inScaleCents.count)
        let std = standardDeviation(aggregate.inScaleCents)
        let ratioScore = inScaleRatio * 100.0
        let tuningScore = max(0.0, 100.0 - meanAbs * 2.0)
        let coverageScore = (Double(aggregate.inScalePitchClasses.count) / Double(max(1, allowedPitchClasses.count))) * 100.0

        intonationScore = clampScore(Int((ratioScore * 0.45 + tuningScore * 0.40 + coverageScore * 0.15).rounded()))
        intonationConsistency = clampScore(Int((100.0 - std * 1.8).rounded()))

        if !intonationPassed {
            statusMessage = L10n.f(
                "Need clearer scale capture: >=%@ samples, >=%@%% in-scale, >=%@ tones.",
                "\(minIntonationSamples)",
                "\(Int((minInScaleRatio * 100).rounded()))",
                "\(minUniqueScaleTones)"
            )
            phase = .ready
            return
        }

        phase = .rhythm
        statusMessage = "Intonation captured. Continue to rhythm."
    }

    private func startRhythm() {
        guard intonationPassed else {
            statusMessage = "Complete intonation first."
            return
        }
        if rhythmBPM < minimumRhythmBPM {
            rhythmBPM = minimumRhythmBPM
        }
        phase = .rhythm
        finalMetrics = nil
        rhythmRunning = true
        rhythmEngine.stop(clear: true)
        metronome.setBPM(rhythmBPM)
        metronome.start(beatsPerBar: 4, subdivision: .none, soundStyle: (MetronomeEngine.SoundStyle(rawValue: JourneyProgressManager.preferredMetronomeSoundStyleRaw() ?? "click") ?? .click))
        rhythmEngine.start(bpm: rhythmBPM, targetBeats: rhythmTargetBeats)
    }

    private func stopRhythm() {
        rhythmRunning = false
        metronome.stop()
        rhythmEngine.stop(clear: false)
        if let summary = rhythmEngine.summary {
            buildFinalMetrics(rhythmSummary: summary)
        } else {
            statusMessage = "Rhythm capture too short. Try again."
        }
    }

    private func buildFinalMetrics(rhythmSummary: RhythmAccuracySummary) {
        guard intonationPassed else { return }
        guard rhythmSummary.beatsAnalyzed > 0 else { return }

        let rhythmScore = clampScore(rhythmSummary.grooveScore)
        let timingConsistency = clampScore(Int((100.0 - min(100.0, abs(rhythmSummary.averageOffsetMs))).rounded()))
        let combinedConsistency = clampScore(Int((Double(intonationConsistency) * 0.6 + Double(timingConsistency) * 0.4).rounded()))

        finalMetrics = DuelDerivedMetrics(
            intonationScore: intonationScore,
            rhythmScore: rhythmScore,
            consistencyScore: combinedConsistency,
            noteCount: max(1, aggregate.inScaleSamples),
            beatsAnalyzed: max(1, rhythmSummary.beatsAnalyzed),
            tempoBPM: rhythmBPM
        )
        phase = .complete
        statusMessage = "Duel take ready. Use this take to submit."
    }

    private func scalePitchClasses(for descriptor: String) -> Set<Int> {
        let raw = descriptor.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        let isMelodicMinor = lower.contains("melodic minor")
        let rootToken = raw.split(separator: " ").first.map(String.init) ?? "C"
        guard let rootClass = pitchClass(for: rootToken) else {
            return [0, 2, 4, 5, 7, 9, 11]
        }
        let intervals = isMelodicMinor ? [0, 2, 3, 5, 7, 9, 11] : [0, 2, 4, 5, 7, 9, 11]
        return Set(intervals.map { positiveModulo(rootClass + $0, 12) })
    }

    private func pitchClass(for note: String) -> Int? {
        switch note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "c", "b#": return 0
        case "c#", "db": return 1
        case "d": return 2
        case "d#", "eb": return 3
        case "e", "fb": return 4
        case "f", "e#": return 5
        case "f#", "gb": return 6
        case "g": return 7
        case "g#", "ab": return 8
        case "a": return 9
        case "a#", "bb": return 10
        case "b", "cb": return 11
        default: return nil
        }
    }

    private func noteName(for pitchClass: Int) -> String {
        switch positiveModulo(pitchClass, 12) {
        case 0: return "C"
        case 1: return "C#/Db"
        case 2: return "D"
        case 3: return "D#/Eb"
        case 4: return "E"
        case 5: return "F"
        case 6: return "F#/Gb"
        case 7: return "G"
        case 8: return "G#/Ab"
        case 9: return "A"
        case 10: return "A#/Bb"
        default: return "B"
        }
    }

    private func nearestAllowedCentsDelta(for midi: Double) -> Double {
        let center = Int(midi.rounded())
        var best = Double.greatestFiniteMagnitude
        for candidate in (center - 24)...(center + 24) {
            let pc = positiveModulo(candidate, 12)
            guard allowedPitchClasses.contains(pc) else { continue }
            let delta = (midi - Double(candidate)) * 100.0
            if abs(delta) < abs(best) {
                best = delta
            }
        }
        if best.isFinite { return best }
        return 0
    }

    private func stopAllCapture() {
        intonationRunning = false
        rhythmRunning = false
        preRollStartedAt = nil
        preRollSeconds = 0
        intonationStartedAt = nil
        tuner.stopListening()
        rhythmEngine.stop(clear: false)
        metronome.stop()
    }

    private func positiveModulo(_ value: Int, _ modulo: Int) -> Int {
        let r = value % modulo
        return r >= 0 ? r : (r + modulo)
    }

    private func clampScore(_ value: Int) -> Int {
        min(100, max(0, value))
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }
}
