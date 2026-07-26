import SwiftUI

struct StudioQuestShell: View {
    @Binding var selectedTab: Int
    let socialBadgeCount: Int?

    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var dockHeight: CGFloat = 58

    var body: some View {
        TabView(selection: $router.selectedDestination) {
            destinationStack(StudioQuestTodayView(), destination: .today)
                .tabItem { Label(AppDestination.today.title, systemImage: AppDestination.today.systemImage) }
                .tag(AppDestination.today)

            destinationStack(StudioQuestQuestView(), destination: .quest)
                .tabItem { Label(AppDestination.quest.title, systemImage: AppDestination.quest.systemImage) }
                .tag(AppDestination.quest)

            destinationStack(StudioQuestCommunityFeedView(), destination: .community)
                .tabItem { Label(AppDestination.community.title, systemImage: AppDestination.community.systemImage) }
                .badge(socialBadgeCount ?? 0)
                .tag(AppDestination.community)

            destinationStack(StudioQuestYouView(), destination: .you)
                .tabItem { Label(AppDestination.you.title, systemImage: AppDestination.you.systemImage) }
                .tag(AppDestination.you)
        }
        .tint(StudioQuestTokens.ColorRole.cobalt)
        .tabViewBottomAccessory {
            StudioQuestPracticeDock()
                .padding(.horizontal, StudioQuestTokens.Spacing.md)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { measuredHeight in
                    dockHeight = measuredHeight
                }
        }
        .environmentObject(router)
        .environment(\.studioQuestDockClearance, max(92, dockHeight + 26))
        .fullScreenCover(isPresented: $router.roomEditorPresented) {
            StudioQuestRoomEditorView()
        }
        .fullScreenCover(isPresented: $coordinator.studioPresented) {
            NavigationStack {
                PracticeStudioView()
            }
            .environmentObject(router)
        }
        .sheet(item: $coordinator.momentPrompt) { prompt in
            StudioQuestPracticeMomentComposer(prompt: prompt)
        }
        .onAppear {
            router.selectedDestination = AppDestination(rawValue: selectedTab) ?? .today
        }
        .onChange(of: router.selectedDestination) { _, destination in
            selectedTab = destination.rawValue
        }
        .onChange(of: selectedTab) { _, value in
            guard let destination = AppDestination(rawValue: value),
                  destination != router.selectedDestination else { return }
            router.selectedDestination = destination
        }
        .onChange(of: scenePhase) { _, phase in
            coordinator.handleScenePhase(isActive: phase == .active)
        }
    }

    private func destinationStack<Root: View>(_ root: Root, destination: AppDestination) -> some View {
        NavigationStack(path: router.pathBinding(for: destination)) {
            root
                .navigationDestination(for: AppRoute.self) { route in
                    StudioQuestRouteView(route: route)
                }
        }
    }
}

struct StudioQuestRouteView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .practiceStudio:
            PracticeStudioView()
        case .practiceSetup(let preset):
            PracticeSetupView(preset: preset)
        case .practiceLibrary:
            PracticeLibraryView()
        case .metronome:
            StudioQuestMetronomeToolView()
        case .tuner:
            StudioQuestTunerToolView()
        case .smartLoop:
            SmartLoopTimerView()
        case .warmUp:
            WarmUpGeneratorView()
        case .planExecuteReflect:
            PlanExecuteReflectView()
        case .rhythm:
            PulseRhythmAccuracyView()
        case .intonation:
            ScaleIntonationView()
        case .runThrough:
            RunThroughModeView()
        case .history:
            StudioQuestHistoryView()
        case .achievements:
            StudioQuestAchievementsView()
        case .sessionDetail(let sessionID):
            StudioQuestSessionDetailView(sessionID: sessionID)
        case .goals:
            StudioQuestGoalsView()
        case .notifications:
            StudioQuestNotificationsView()
        case .settings(let section):
            StudioQuestSettingsView(initialSection: section)
        case .profile(let userID):
            StudioQuestProfileView(userID: userID)
        case .publicProfile(let userID):
            StudioQuestPublicProfileView(userID: userID)
        case .profileUpgrade:
            StudioQuestProfileUpgradeView()
        case .pro:
            StudioQuestProView()
        case .avatarStudio(let section):
            StudioQuestAvatarStudioView(initialSection: section)
        case .shop:
            StudioQuestShopView()
        case .inventory:
            StudioQuestAvatarStudioView(initialSection: .collection)
        case .duelArena(let challengeID):
            StudioQuestDuelArenaView(challengeID: challengeID)
        case .questDetail(let quest):
            QuestDetailSheet(quest: quest)
        case .smartCoach:
            SmartPracticePlanGeneratorView()
        case .communityFeed:
            StudioQuestCommunityFeedView()
        case .communityConnections(let section):
            StudioQuestConnectionsView(initialSection: section)
        case .peopleSearch(let query):
            StudioQuestPeopleSearchView(initialQuery: query)
        case .practiceMoment(let momentID):
            StudioQuestMomentDetailView(momentID: momentID)
        case .practiceMomentComposer(let sessionID):
            StudioQuestPracticeMomentComposer(
                prompt: PracticeMomentPrompt(sessionID: sessionID, eligibleAt: .now)
            )
        case .shareCard(let sessionID):
            StudioQuestShareCardView(sessionID: sessionID)
        case .communityFriends:
            StudioQuestConnectionsView(initialSection: .friends)
        case .communityRequests:
            StudioQuestConnectionsView(initialSection: .requests)
        case .communityMessages(let friendUID, let threadID):
            StudioQuestConversationRouteView(friendUID: friendUID, threadID: threadID)
        }
    }
}

private struct StudioQuestConversationRouteView: View {
    let friendUID: String?
    let threadID: String?

    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var chat: StudioChatViewModel

    private var resolvedThreadID: String? {
        if let threadID, !threadID.isEmpty { return threadID }
        guard let friendUID, !friendUID.isEmpty,
              let uid = firebase.currentUserID else { return nil }
        let raw = FirebaseBuddiesRepository().friendThreadID(uidA: uid, uidB: friendUID)
        return "friend:\(raw)"
    }

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--qa-community-populated"),
               let friendUID,
               friendUID.hasPrefix("fixture-") {
                StudioQuestFixtureConversationView(
                    friendUID: friendUID,
                    title: friendUID == "fixture-aya" ? "Aya Chen" : "Mateo Silva"
                )
            } else if let resolvedThreadID {
                SocialChatThreadView(threadID: resolvedThreadID)
                    .task {
                        guard let uid = firebase.currentUserID else { return }
                        chat.start(uid: uid)
                        if let friendUID, !friendUID.isEmpty {
                            chat.openFriendThread(friendUID: friendUID)
                        } else {
                            chat.openThread(threadID: resolvedThreadID)
                        }
                    }
            } else {
                StudioQuestMessagesView()
            }
            #else
            if let resolvedThreadID {
                SocialChatThreadView(threadID: resolvedThreadID)
                    .task {
                        guard let uid = firebase.currentUserID else { return }
                        chat.start(uid: uid)
                        if let friendUID, !friendUID.isEmpty {
                            chat.openFriendThread(friendUID: friendUID)
                        } else {
                            chat.openThread(threadID: resolvedThreadID)
                        }
                    }
            } else {
                StudioQuestMessagesView()
            }
            #endif
        }
    }
}

#if DEBUG
private struct StudioQuestFixtureConversationView: View {
    let friendUID: String
    let title: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var draft = ""
    @State private var sentMessages: [String] = []
    @FocusState private var composerFocused: Bool

    private struct FixtureMessage: Identifiable {
        let id: String
        let text: String
        let isCurrentUser: Bool
        let time: String
    }

    private var messages: [FixtureMessage] {
        [
            FixtureMessage(
                id: "fixture-message-1",
                text: "Your phrasing in the second section is really landing.",
                isCurrentUser: false,
                time: "5:18 PM"
            ),
            FixtureMessage(
                id: "fixture-message-2",
                text: "Thank you! I slowed the transition down and used Smart Loop.",
                isCurrentUser: true,
                time: "5:22 PM"
            ),
            FixtureMessage(
                id: "fixture-message-3",
                text: "That run-through sounded so much freer.",
                isCurrentUser: false,
                time: "5:35 PM"
            )
        ] + sentMessages.enumerated().map { index, text in
            FixtureMessage(
                id: "fixture-sent-\(index)",
                text: text,
                isCurrentUser: true,
                time: "Now"
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    VStack(spacing: 8) {
                        PBAvatarView(
                            avatarID: "avatar_note",
                            displayName: title,
                            profilePhotoURL: nil,
                            size: 58
                        )
                        Text("Online · Practiced today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                    ForEach(messages) { message in
                        HStack {
                            if message.isCurrentUser {
                                Spacer(minLength: 62)
                            }
                            VStack(
                                alignment: message.isCurrentUser ? .trailing : .leading,
                                spacing: 4
                            ) {
                                Text(message.text)
                                    .font(.body)
                                    .foregroundStyle(message.isCurrentUser ? .white : .primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        message.isCurrentUser
                                            ? StudioQuestTokens.ColorRole.cobalt
                                            : StudioQuestTokens.ColorRole.surface(colorScheme),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    )
                                Text(message.time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if !message.isCurrentUser {
                                Spacer(minLength: 62)
                            }
                        }
                    }
                }
                .padding(.horizontal, StudioQuestTokens.Spacing.md)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                composerFocused = false
            }

            HStack(spacing: 8) {
                TextField("Write a message…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        StudioQuestTokens.ColorRole.raisedSurface(colorScheme),
                        in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous)
                    )

                Button {
                    let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !message.isEmpty else { return }
                    sentMessages.append(message)
                    draft = ""
                    composerFocused = false
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(StudioQuestTokens.ColorRole.cobalt, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, StudioQuestTokens.Spacing.md)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(StudioQuestTokens.ColorRole.surface(colorScheme))
            .overlay(alignment: .top) {
                Divider()
            }
        }
        .background(StudioQuestTokens.ColorRole.background(colorScheme).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(StudioQuestTokens.ColorRole.background(colorScheme), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .accessibilityIdentifier("studioquest.fixture.chat.\(friendUID)")
    }
}
#endif

struct StudioQuestPracticeDock: View {
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            PracticeAnalytics.record(.dockOpened(state: analyticsState))
            if coordinator.elapsedSeconds > 0 {
                coordinator.studioPresented = true
            } else {
                coordinator.quickStart()
            }
        } label: {
            HStack(spacing: 10) {
                dockIcon

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if case .running = coordinator.state {
                    Image(systemName: coordinator.isVerified ? "checkmark.shield.fill" : "shield")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(coordinator.isVerified ? StudioQuestTokens.ColorRole.mint : .secondary)
                        .accessibilityLabel(coordinator.isVerified ? "Verified" : "Standard")
                }

                Image(systemName: actionImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(StudioQuestTokens.ColorRole.cobalt, in: Circle())
            }
            .padding(.horizontal, 10)
            .frame(height: 58)
            .modifier(StudioQuestDockMaterial())
            .overlay {
                RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.dock, style: .continuous)
                    .stroke(StudioQuestTokens.ColorRole.separator(colorScheme), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityHint(coordinator.elapsedSeconds > 0 ? "Opens Practice Studio" : "Starts practice")
    }

    @ViewBuilder
    private var dockIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(StudioQuestTokens.ColorRole.cobalt)
            Image(systemName: "music.note")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
    }

    private var title: String {
        switch coordinator.state {
        case .idle: "Start practice"
        case .planned(let title, _): title
        case .running(_, let task, _): task
        case .paused(_, let task): task
        }
    }

    private var subtitle: String {
        switch coordinator.state {
        case .idle: "Quick start with your last setup"
        case .planned(_, let durationMinutes): "\(durationMinutes) min plan"
        case .running(let elapsedSeconds, _, _): "\(DurationFormatter.string(from: elapsedSeconds)) · Practicing"
        case .paused(let elapsedSeconds, _): "\(DurationFormatter.string(from: elapsedSeconds)) · Paused"
        }
    }

    private var actionImage: String {
        switch coordinator.state {
        case .running, .paused: "arrow.up.right"
        case .idle, .planned: "play.fill"
        }
    }

    private var analyticsState: String {
        switch coordinator.state {
        case .idle: "idle"
        case .planned: "planned"
        case .running: "running"
        case .paused: "paused"
        }
    }
}

struct StudioQuestTodayView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var buddies: BuddiesViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pb.settings.dailyGoalMinutes") private var goalMinutes = 30
    @StateObject private var questProgress = PracticeQuestProgressStore.shared

    private var progress: Double {
        guard goalMinutes > 0 else { return 0 }
        return min(Double(store.totalTodaySeconds) / Double(goalMinutes * 60), 1)
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                header
                goalHero
                suggestedSession
                nextQuest
                recentSession
                communityPulse
            }
            .padding(.top, StudioQuestTokens.Spacing.sm)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Today")
                    .font(StudioQuestTokens.Typography.pageTitle)
                    .tracking(-1)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                StudioQuestTokenChip()
                NavigationLink(value: AppRoute.notifications) {
                    Image(systemName: "bell")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Notifications")
            }
        }
    }

    private var goalHero: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(StudioQuestTokens.ColorRole.separator(colorScheme), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        StudioQuestTokens.ColorRole.cobalt,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("Daily goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(store.totalTodaySeconds / 60)")
                        .font(.system(size: 48, weight: .medium, design: .monospaced))
                        .contentTransition(.numericText())
                    Text("/ \(goalMinutes) min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 144, height: 144)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Daily practice goal")
            .accessibilityValue("\(store.totalTodaySeconds / 60) of \(goalMinutes) minutes")

            Button {
                coordinator.quickStart()
            } label: {
                Label(coordinator.elapsedSeconds > 0 ? "Resume practice" : "Start practice", systemImage: "play.fill")
            }
            .buttonStyle(StudioQuestPrimaryButtonStyle())

            NavigationLink(value: AppRoute.practiceSetup(preset: suggestedPreset)) {
                Text("Set up a session")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            }
        }
        .padding(.vertical, 6)
    }

    private var suggestedSession: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Suggested for you")
            NavigationLink(value: AppRoute.practiceSetup(preset: nil)) {
                HStack(spacing: 12) {
                    Image(systemName: "pianokeys")
                        .font(.title3)
                        .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                        .frame(width: 44, height: 44)
                        .background(StudioQuestTokens.ColorRole.cobalt.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestedPreset.task)
                            .font(.headline)
                        Text("\(suggestedPreset.durationMinutes) min · \(suggestedPreset.verified ? "Verification on" : "Standard timing")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    private var suggestedPreset: PracticePreset {
        PracticePreset(
            piece: coordinator.currentPiece == "Your instrument" ? "" : coordinator.currentPiece,
            task: coordinator.currentTask == "Open practice" ? "Focused technique" : coordinator.currentTask,
            durationMinutes: max(10, coordinator.plannedMinutes),
            verified: coordinator.isVerified,
            launchContext: PracticeLaunchContext(source: "today_suggestion", questID: nil),
            tasks: coordinator.tasks
        )
    }

    private var nextQuest: some View {
        Button {
            router.navigate(to: .questDetail(dynamicControlQuest))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Next quest")
                HStack(spacing: 14) {
                    Image(systemName: "music.note.list")
                        .font(.title2)
                        .foregroundStyle(StudioQuestTokens.ColorRole.gold)
                        .frame(width: 48, height: 48)
                        .background(StudioQuestTokens.ColorRole.gold.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(dynamicControlQuest.title)
                            .font(.headline)
                        Text(dynamicControlQuest.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Text("\(dynamicControlQuest.rewardTokens) tokens")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(StudioQuestTokens.ColorRole.violet)
                }
                .padding(.vertical, 10)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    private var dynamicControlQuest: QuestPresentation {
        QuestPresentation(
            id: "dynamic-control",
            title: "Dynamic control",
            subtitle: "Shape one phrase across three dynamics",
            progress: questProgress.count(for: "dynamic-control"),
            target: 1,
            rewardTokens: 25,
            systemImage: "waveform",
            period: .featured,
            action: .practice(
                PracticePreset(
                    piece: "",
                    task: "Dynamic control: shape one phrase across three dynamics",
                    durationMinutes: 20,
                    verified: true,
                    launchContext: PracticeLaunchContext(source: "quest", questID: "dynamic-control")
                )
            )
        )
    }

    private var recentSession: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Recent session")
            if let session = store.sessions.first {
                NavigationLink(value: AppRoute.sessionDetail(sessionID: session.id)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.noteTitle.isEmpty ? "Practice session" : session.noteTitle)
                                .font(.headline)
                            Text("\(DurationFormatter.string(from: session.durationSeconds)) · \(session.date.formatted(.relative(presentation: .named)))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: session.verifiedSeconds > 0 ? "checkmark.shield.fill" : "clock")
                            .foregroundStyle(session.verifiedSeconds > 0 ? StudioQuestTokens.ColorRole.mint : .secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            } else {
                Text("Your first completed session will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            }
        }
    }

    private var communityPulse: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Community pulse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Your practice can inspire a friend today.")
                    .font(.subheadline.weight(.medium))
            }
            Spacer()
            HStack(spacing: -7) {
                ForEach(Array(buddies.buddies.prefix(3))) { buddy in
                    PBAvatarView(
                        avatarID: buddy.avatarID,
                        displayName: buddy.displayName,
                        profilePhotoURL: buddy.profilePhotoURL,
                        size: 30
                    )
                        .overlay(Circle().stroke(StudioQuestTokens.ColorRole.background(colorScheme), lineWidth: 2))
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        StudioQuestEyebrow(text)
    }
}
