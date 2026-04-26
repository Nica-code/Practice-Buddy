import SwiftUI
import Combine

struct JourneyView: View {
    private enum JourneyScrollTarget: String {
        case seasonLadder
    }

    private enum JourneySection: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case rewards = "Rewards"

        var id: String { rawValue }
    }

    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var duelLeague: DuelLeagueManager
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var adsManager: PBAdsManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSection: JourneySection = .overview
    @State private var rewardsMessage: String?
    @State private var didLoadDuelTargets = false
    @State private var duelLeaderboardScope: DuelLeaderboardScope = .global
    @State private var animateHeader = false
    // Note: duelLeaderboardScope retained for .global/.friends; .studio removed
    @State private var expandedLadderUserID: String?
    @State private var profileTarget: LadderActionUser?
    @State private var journeyScrollTarget: JourneyScrollTarget?
    @State private var showShopSheet = false
    @State private var showInventorySheet = false
    @State private var showMatchHistorySheet = false
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
    @StateObject private var notificationStore = PBNotificationStore.shared
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PBAdBannerSlot(placement: .playBottomBanner)
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
            syncInAppNotifications()
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
            syncInAppNotifications()
        }
        .onChange(of: duelLeague.activeChallenges.map(\.id)) { _, _ in
            consumePendingOpenChallengeID()
        }
        .onChange(of: duelLeague.incomingInvites.map(\.id)) { _, _ in
            syncInAppNotifications()
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
        .sheet(isPresented: $showMatchHistorySheet) {
            NavigationStack {
                matchHistorySheet
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
                    Task {
                        await duelLeague.submitDerivedAttempt(
                            challengeID: challenge.id,
                            metrics: metrics,
                            requiredMinTempoBPM: challenge.requiredMinTempoBPM
                        )
                        await duelLeague.refreshSeasonLeaderboard(scope: duelLeaderboardScope, force: true)
                        duelRecordedMetricsByChallengeID[challenge.id] = nil
                        selectedDuelEntryChallenge = nil
                    }
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

    private func syncInAppNotifications() {
        notificationStore.syncDuelInvites(duelLeague.incomingInvites, cachedNames: duelLeague.userDisplayNames)
        notificationStore.syncFriendRequests(playBuddiesVM.incomingInvites)
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
                        await duelLeague.refreshSeasonLeaderboard(scope: .global, force: true)
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
                        .font(type.fontChoice.headlineFont(size: 12, weight: .semibold))
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

            let viewerUID = firebase.currentUserID ?? ""
            let hasPendingActiveForMe = duelLeague.activeChallenges.contains { challenge in
                challenge.myScore(for: viewerUID) == nil
            }
            let isQueuedForOpenDuel = duelLeague.myOpenChallenge != nil

            Button {
                PBHaptics.tap()
                Task {
                    if hasPendingActiveForMe {
                        return
                    }
                    if isQueuedForOpenDuel {
                        await duelLeague.cancelOpenChallenge()
                    } else {
                        await duelLeague.queueAsyncScaleDuel(octaves: duelLeague.activeLeagueRequirement.octaves)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: hasPendingActiveForMe ? "checkmark.circle.fill" : (isQueuedForOpenDuel ? "xmark.circle.fill" : "bolt.horizontal.circle.fill"))
                    Text(hasPendingActiveForMe ? "Duel Active" : (isQueuedForOpenDuel ? "Cancel Queue" : "Queue Duel"))
                        .font(type.button)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                PBActionButtonStyle(
                    variant: (isQueuedForOpenDuel || hasPendingActiveForMe) ? .secondary : .primary,
                    palette: palette
                )
            )
            .disabled(duelLeague.isLoading || duelLeague.isActionBusy || firebase.currentUserID == nil || firebase.isAnonymousUser || hasPendingActiveForMe)

            if hasPendingActiveForMe {
                statusBadge(
                    text: "Finish your active duel take before queuing another duel.",
                    style: .info
                )
            }

            VStack(spacing: 10) {
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
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                        Text("Invite Friend")
                            .font(type.button)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PBActionButtonStyle(variant: .secondary, palette: palette))
                .disabled(duelLeague.isActionBusy || firebase.currentUserID == nil || firebase.isAnonymousUser || hasPendingActiveForMe)

                Button {
                    showMatchHistorySheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Match History")
                            .font(type.button)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PBActionButtonStyle(variant: .secondary, palette: palette))
                .disabled(duelLeague.matchHistory.isEmpty)
            }

            if !duelLeague.outgoingInvites.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Outgoing Invites (\(duelLeague.outgoingInvites.count))")
                        .font(type.fontChoice.headlineFont(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(duelLeague.outgoingInvites) { challenge in
                            outgoingInviteRow(challenge)
                        }
                    }
                }
                .padding(10)
                .pbSurfaceCard(palette: palette)
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
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    expandedLadderUserID = (expandedLadderUserID == row.id) ? nil : row.id
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Text("#\(idx + 1)")
                                        .font(type.body.weight(.semibold))
                                        .foregroundStyle(rankColor(idx))
                                        .frame(width: 32, alignment: .leading)
                                        .monospacedDigit()

                                    PBAvatarView(
                                        avatarID: row.avatarID,
                                        displayName: row.displayName,
                                        profilePhotoURL: row.profilePhotoURL,
                                        size: 34
                                    )

                                    Text(row.displayName)
                                        .font(type.body.weight(.semibold))
                                        .foregroundStyle(palette.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.84)
                                        .allowsTightening(true)

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Rating")
                                            .font(type.footnote)
                                            .foregroundStyle(palette.textSecondary)
                                        Text("\(row.rating)")
                                            .font(type.body.weight(.semibold))
                                            .foregroundStyle(palette.textPrimary)
                                            .monospacedDigit()
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .pbSurfaceCard(palette: palette, cornerRadius: PBLayout.radiusControl)
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
                                            await duelLeague.inviteTargetedDuel(targetUID: row.id, source: .friend, octaves: duelLeague.activeLeagueRequirement.octaves)
                                        }
                                        expandedLadderUserID = nil
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(firebase.currentUserID == row.id || firebase.isAnonymousUser)
                                }
                                .font(type.footnote)
                                .padding(.leading, 42)
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

    private func miniStatChip(label: String) -> some View {
        Text(label)
            .font(type.footnote)
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(palette.surface)
            )
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: return Color.orange
        case 1: return Color.mint
        case 2: return Color.blue
        default: return palette.textSecondary
        }
    }

    @ViewBuilder
    private func duelChallengeRow(_ challenge: DuelChallenge) -> some View {
        let uid = firebase.currentUserID ?? ""
        let myScore = challenge.myScore(for: uid)
        let oppScore = challenge.opponentScore(for: uid)
        let other = duelOpponentName(for: challenge, viewerUID: uid)
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
                    if isSubmitting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Submitting...")
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                    } else {
                        Text("Tap Enter to record and submit your take.")
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
        let opponent = duelOpponentName(for: challenge, viewerUID: uid)
        let outcome = duelOutcome(for: challenge, viewerUID: uid)

        return sessionCardSkinContainer {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    statusBadge(text: outcome.label, style: outcome.badgeStyle)
                    Text(L10n.f("vs %@", opponent))
                        .font(type.footnote)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(delta >= 0 ? L10n.f("+%@", "\(delta)") : "\(delta)")
                        .font(type.number)
                        .foregroundStyle(delta >= 0 ? palette.accent : palette.textSecondary)
                        .monospacedDigit()
                }

                HStack {
                    Text(L10n.f("%@-%@", "\(myScore)", "\(oppScore)"))
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Spacer()
                    if let completedAt = challenge.completedAt {
                        Text(completedAt.formatted(.relative(presentation: .named)))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                if adsManager.shouldShowRewardedDuelButton(challengeID: challenge.id) {
                    Button {
                        PBHaptics.tap()
                        Task {
                            let didFinishAd = await adsManager.presentRewardedDuelAd(challengeID: challenge.id)
                            guard didFinishAd else {
                                rewardsMessage = "Rewarded ad unavailable right now."
                                return
                            }

                            if await journey.claimDuelAdReward(
                                challengeID: challenge.id,
                                rewardTokens: adsManager.duelRewardTokenBonus
                            ) {
                                adsManager.markDuelRewardClaimed(challengeID: challenge.id)
                                rewardsMessage = L10n.f("Claimed %@ tokens.", "\(adsManager.duelRewardTokenBonus)")
                                triggerRewardCelebration()
                            } else {
                                rewardsMessage = "Reward already claimed."
                            }
                        }
                    } label: {
                        Label(L10n.f("Watch Ad +%@", "\(adsManager.duelRewardTokenBonus)"), systemImage: "play.rectangle.fill")
                            .font(type.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(journey.isEconomyOperationInProgress)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var matchHistorySheet: some View {
        List {
            if duelLeague.matchHistory.isEmpty {
                Text("No completed duel matches yet.")
                    .font(type.body)
                    .foregroundStyle(palette.textSecondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(duelLeague.matchHistory) { challenge in
                    matchHistoryRow(challenge)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PBBackdropView(palette: palette))
        .navigationTitle("Match History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func matchHistoryRow(_ challenge: DuelChallenge) -> some View {
        let uid = firebase.currentUserID ?? ""
        let myScore = challenge.myScore(for: uid) ?? 0
        let oppScore = challenge.opponentScore(for: uid) ?? 0
        let delta = challenge.myRatingDelta(for: uid)
        let opponent = duelOpponentName(for: challenge, viewerUID: uid)
        let outcome = duelOutcome(for: challenge, viewerUID: uid)

        return sessionCardSkinContainer {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    statusBadge(text: outcome.label, style: outcome.badgeStyle)
                    Text(L10n.f("vs %@", opponent))
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(delta >= 0 ? L10n.f("+%@", "\(delta)") : "\(delta)")
                        .font(type.number)
                        .foregroundStyle(delta >= 0 ? palette.accent : palette.textSecondary)
                        .monospacedDigit()
                }
                HStack {
                    Text(L10n.f("%@-%@", "\(myScore)", "\(oppScore)"))
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Spacer()
                    if let completedAt = challenge.completedAt {
                        Text(completedAt.formatted(.relative(presentation: .named)))
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
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
        case danger
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
        case .danger:
            bg = Color.red.opacity(0.18)
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

    private struct DuelOutcomeBadge {
        let label: String
        let badgeStyle: DuelStatusBadgeStyle
    }

    private func duelOutcome(for challenge: DuelChallenge, viewerUID: String) -> DuelOutcomeBadge {
        let myScore = challenge.myScore(for: viewerUID) ?? 0
        let oppScore = challenge.opponentScore(for: viewerUID) ?? 0
        if myScore > oppScore {
            return DuelOutcomeBadge(label: "Win", badgeStyle: .success)
        }
        if myScore < oppScore {
            return DuelOutcomeBadge(label: "Loss", badgeStyle: .danger)
        }
        return DuelOutcomeBadge(label: "Draw", badgeStyle: .info)
    }

    private func duelOpponentName(for challenge: DuelChallenge, viewerUID: String) -> String {
        let opponentUID = challenge.otherParticipant(for: viewerUID) ?? ""
        if let displayName = duelLeague.userDisplayNames[opponentUID]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }
        return shortUserLabel(opponentUID)
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
                Button(hasSubmitted ? "Take Submitted" : "Record your take") {
                    selectedDuelEntryChallenge = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        duelRecordingChallenge = challenge
                    }
                }
                .buttonStyle(PBActionButtonStyle(variant: .secondary, palette: palette))
                .disabled(hasSubmitted)

                Button("Done") {
                    selectedDuelEntryChallenge = nil
                }
                .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
            }

            if !hasSubmitted {
                Text("Recording flow will submit automatically from the capture screen.")
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
        guard !uid.isEmpty else { return "Player" }
        return "Player"
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
                                .font(type.footnote)
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
