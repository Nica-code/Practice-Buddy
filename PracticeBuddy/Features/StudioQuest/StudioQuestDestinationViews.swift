import SwiftUI

struct StudioQuestQuestView: View {
    private enum QuestSection: String, CaseIterable, Identifiable {
        case journey = "Journey"
        case competition = "Duels & Leagues"
        var id: String { rawValue }
    }

    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorScheme) private var colorScheme
    @State private var section: QuestSection = .journey
    @State private var selectedQuest: QuestPresentation?
    @StateObject private var progressStore = PracticeQuestProgressStore.shared

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: 16) {
                header
                progressSummary
                sectionPicker
                if section == .journey {
                    questPath
                } else {
                    competitionSummary
                    duelArenaLink
                    liveQuests
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.sm)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedQuest) { quest in
            QuestDetailSheet(quest: quest)
                .environmentObject(router)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                questTitle
                Spacer(minLength: 12)
                tokenBalance
            }
            VStack(alignment: .leading, spacing: 10) {
                questTitle
                tokenBalance
            }
        }
    }

    private var questTitle: some View {
        StudioQuestPageTitle(title: "Quest", subtitle: "Your path. Your music.")
    }

    private var tokenBalance: some View {
        Label("\(journey.tokenBalance)", systemImage: "diamond.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Level \(journey.level)")
                    .font(.headline)
                Spacer()
                Text("\(journey.xpToNextLevel) XP to next level")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: levelProgress)
                .tint(StudioQuestTokens.ColorRole.cobalt)
        }
        .padding(.vertical, 8)
    }

    private var sectionPicker: some View {
        Picker("Quest section", selection: $section) {
            ForEach(QuestSection.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Quest section")
    }

    private var levelProgress: Double {
        let denominator = max(1, journey.xpToNextLevel + 250)
        return min(max(1 - Double(journey.xpToNextLevel) / Double(denominator), 0.06), 0.96)
    }

    private var questPath: some View {
        GeometryReader { proxy in
            ZStack {
                Image("StudioQuestQuestPath")
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .overlay {
                        if colorScheme == .dark {
                            Color(red: 0.02, green: 0.04, blue: 0.07)
                                .opacity(0.72)
                                .blendMode(.multiply)
                        }
                    }

                if let rewardQuest = firstClaimableFeaturedQuest {
                    RewardUnlockedView(
                        rewardTitle: rewardQuest.title,
                        rewardTokens: rewardQuest.rewardTokens
                    ) {
                        Task {
                            _ = await journey.claimFeaturedQuestReward(
                                questID: rewardQuest.id,
                                rewardTokens: rewardQuest.rewardTokens
                            )
                        }
                    }
                    .frame(width: 180)
                    .position(x: proxy.size.width * 0.70, y: proxy.size.height * 0.72)
                }

                ForEach(featuredQuests) { quest in
                    let point = nodePosition(for: quest.id)
                    Button {
                        selectedQuest = quest
                    } label: {
                        questNode(quest)
                    }
                    .buttonStyle(.plain)
                    .position(x: proxy.size.width * point.x, y: proxy.size.height * point.y)
                }
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(StudioQuestTokens.ColorRole.separator(colorScheme), lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quest path")
    }

    private func questNode(_ quest: QuestPresentation) -> some View {
        let color = nodeColor(for: quest.id)
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                Circle()
                    .stroke(color, lineWidth: 4)
                Image(systemName: quest.isComplete ? "checkmark" : quest.systemImage)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(color)
            }
            .frame(width: 58, height: 58)
            Text(quest.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(quest.title), \(quest.progress) of \(quest.target)")
    }

    private var featuredQuests: [QuestPresentation] {
        [
            QuestPresentation(
                id: "warm-up-warrior",
                title: "Warm-up warrior",
                subtitle: "Complete a focused warm-up routine.",
                progress: progressStore.count(for: "warm-up-warrior"),
                target: 1,
                rewardTokens: 15,
                systemImage: "figure.cooldown",
                period: .featured,
                action: .route(.warmUp)
            ),
            QuestPresentation(
                id: "rhythm-clarity",
                title: "Rhythm clarity",
                subtitle: "Capture one accurate rhythm take.",
                progress: progressStore.count(for: "rhythm-clarity"),
                target: 1,
                rewardTokens: 20,
                systemImage: "metronome",
                period: .featured,
                action: .route(.rhythm)
            ),
            QuestPresentation(
                id: "dynamic-control",
                title: "Dynamic control",
                subtitle: "Practice a deliberate dynamic arc for 20 minutes.",
                progress: progressStore.count(for: "dynamic-control"),
                target: 1,
                rewardTokens: 25,
                systemImage: "waveform",
                period: .featured,
                action: .practice(
                    PracticePreset(
                        piece: "",
                        task: "Shape a clear dynamic arc",
                        durationMinutes: 20,
                        verified: true,
                        launchContext: PracticeLaunchContext(source: "quest", questID: "dynamic-control")
                    )
                )
            ),
            QuestPresentation(
                id: "expression-mastery",
                title: "Expression mastery",
                subtitle: "Complete a distraction-free run-through.",
                progress: progressStore.count(for: "expression-mastery"),
                target: 1,
                rewardTokens: 30,
                systemImage: "sparkles",
                period: .featured,
                action: .route(.runThrough)
            )
        ]
    }

    private var firstClaimableFeaturedQuest: QuestPresentation? {
        featuredQuests.first {
            journey.featuredQuestRewardStatus(questID: $0.id, isComplete: $0.isComplete) == .claimable
        }
    }

    private func nodePosition(for id: String) -> CGPoint {
        switch id {
        case "warm-up-warrior": CGPoint(x: 0.30, y: 0.80)
        case "rhythm-clarity": CGPoint(x: 0.70, y: 0.58)
        case "dynamic-control": CGPoint(x: 0.35, y: 0.36)
        default: CGPoint(x: 0.72, y: 0.15)
        }
    }

    private func nodeColor(for id: String) -> Color {
        switch id {
        case "warm-up-warrior": StudioQuestTokens.ColorRole.cobalt
        case "rhythm-clarity": StudioQuestTokens.ColorRole.violet
        case "dynamic-control": StudioQuestTokens.ColorRole.gold
        default: StudioQuestTokens.ColorRole.violet
        }
    }

    private var duelArenaLink: some View {
        NavigationLink(value: AppRoute.duelArena(challengeID: nil)) {
            arenaLink(title: "Open Duels & Leagues", subtitle: "Fair matches and your league", systemImage: "figure.fencing")
        }
    }

    private var competitionSummary: some View {
        StudioQuestSection {
            VStack(alignment: .leading, spacing: 12) {
                Label("Season competition", systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(StudioQuestTokens.ColorRole.gold)
                Text("Complete fair, asynchronous performance duels and progress through your league.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        competitionMetrics
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        competitionMetrics
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var competitionMetrics: some View {
        competitionMetric(title: "Daily quests", value: "\(journey.dailyQuests.filter { $0.isCompleted }.count)/\(journey.dailyQuests.count)")
        competitionMetric(title: "Weekly quests", value: "\(journey.weeklyQuests.filter { $0.isCompleted }.count)/\(journey.weeklyQuests.count)")
    }

    private func competitionMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func arenaLink(title: LocalizedStringKey, subtitle: LocalizedStringKey, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            StudioQuestTokens.ColorRole.surface(colorScheme),
            in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface)
        )
        .foregroundStyle(.primary)
    }

    private var liveQuests: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily & weekly duels")
                .font(.headline)
            ForEach(journey.dailyQuests) { quest in
                liveQuestRow(quest, period: .daily)
            }
            ForEach(journey.weeklyQuests) { quest in
                liveQuestRow(quest, period: .weekly)
            }
        }
    }

    private func liveQuestRow(_ quest: JourneyQuestRow, period: JourneyQuestPeriod) -> some View {
        StudioQuestRowSurface {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(quest.title).font(.subheadline.weight(.semibold))
                    Text(quest.subtitle).font(.caption).foregroundStyle(.secondary)
                    ProgressView(
                        value: Double(min(max(quest.progress, 0), max(quest.target, 1))),
                        total: Double(max(quest.target, 1))
                    )
                        .tint(StudioQuestTokens.ColorRole.cobalt)
                }
                Spacer()
                if journey.questRewardStatus(for: quest, period: period) == .claimable {
                    Button("Collect") {
                        Task { _ = await journey.claimQuestReward(for: quest, period: period) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioQuestTokens.ColorRole.coral)
                } else if journey.questRewardStatus(for: quest, period: period) == .claimed {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(StudioQuestTokens.ColorRole.mint)
                        .accessibilityLabel("Reward collected")
                } else {
                    Text("\(quest.progress)/\(quest.target)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct QuestDetailSheet: View {
    let quest: QuestPresentation

    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var journey: JourneyProgressManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var claimMessage: String?

    private var rewardStatus: JourneyQuestRewardStatus {
        journey.featuredQuestRewardStatus(questID: quest.id, isComplete: quest.isComplete)
    }

    var body: some View {
        NavigationStack {
            StudioQuestScrollPage {
                VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                    Image(systemName: quest.isComplete ? "checkmark.seal.fill" : quest.systemImage)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(quest.isComplete ? StudioQuestTokens.ColorRole.mint : StudioQuestTokens.ColorRole.cobalt)
                        .frame(width: 74, height: 74)
                        .background(
                            StudioQuestTokens.ColorRole.raisedSurface(colorScheme),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(quest.title)
                            .font(.largeTitle.bold())
                        Text(quest.subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    StudioQuestSection {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Progress").font(.headline)
                                Spacer()
                                Text("\(quest.progress) / \(quest.target)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(
                                value: Double(min(max(quest.progress, 0), max(quest.target, 1))),
                                total: Double(max(quest.target, 1))
                            )
                                .tint(StudioQuestTokens.ColorRole.cobalt)
                            Label("\(quest.rewardTokens) tokens", systemImage: "diamond.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(StudioQuestTokens.ColorRole.gold)
                        }
                    }

                    if let claimMessage {
                        StudioQuestInlineStatus(
                            title: claimMessage,
                            systemImage: "checkmark.seal.fill",
                            tint: StudioQuestTokens.ColorRole.mint
                        )
                    }

                    Button(primaryActionTitle) {
                        if rewardStatus == .claimable {
                            Task {
                                if await journey.claimFeaturedQuestReward(
                                    questID: quest.id,
                                    rewardTokens: quest.rewardTokens
                                ) {
                                    claimMessage = "\(quest.rewardTokens) tokens added to your balance."
                                }
                            }
                        } else if rewardStatus != .claimed {
                            let action = quest.action
                            dismiss()
                            DispatchQueue.main.async {
                                switch action {
                                case .route(let route):
                                    router.navigate(to: route, in: .quest)
                                case .practice(let preset):
                                    router.navigate(to: .practiceSetup(preset: preset), in: .quest)
                                }
                            }
                        }
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    .disabled(rewardStatus == .claimed)
                }
                .padding(.top, StudioQuestTokens.Spacing.lg)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            PracticeAnalytics.record(.questEntered(quest.id))
        }
    }

    private var primaryActionTitle: LocalizedStringKey {
        switch rewardStatus {
        case .claimable: "Collect reward"
        case .claimed: "Reward collected"
        case .locked: "Start quest"
        }
    }
}

private struct RewardUnlockedView: View {
    let rewardTitle: String
    let rewardTokens: Int
    let collect: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .font(.title)
                .foregroundStyle(StudioQuestTokens.ColorRole.gold)
                .symbolEffect(.bounce, value: true)
            Text("Reward unlocked")
                .font(.caption.weight(.bold))
            Text("\(rewardTokens) tokens · \(rewardTitle)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Collect", action: collect)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(StudioQuestTokens.ColorRole.coral, in: Capsule())
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StudioQuestTokens.ColorRole.coral.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

struct StudioQuestCommunityView: View {
    enum Section: String, CaseIterable, Identifiable {
        case friends = "Friends"
        case messages = "Messages"
        case requests = "Requests"
        var id: String { rawValue }
    }

    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var chat: StudioChatViewModel
    @EnvironmentObject private var buddies: BuddiesViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var section: Section
    @State private var signInPresented = false
    @State private var addFriendPresented = false
    @State private var composePresented = false
    @State private var friendCode = ""
    let isStandalone: Bool

    init(initialSection: Section = .friends, isStandalone: Bool = false) {
        _section = State(initialValue: initialSection)
        self.isStandalone = isStandalone
    }

    private var usesDebugFixtures: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--qa-community-populated")
        #else
        false
        #endif
    }

    private var displayedBuddies: [BuddySummary] {
        guard usesDebugFixtures else { return buddies.buddies }
        return [
            BuddySummary(
                id: "fixture-aya",
                displayName: "Aya Chen",
                friendCode: "AYAC-2345",
                sinceAt: Date().addingTimeInterval(-86_400 * 90),
                avatarID: "avatar_note",
                profilePhotoURL: "",
                publicLevel: 18,
                lastPracticedAt: Date().addingTimeInterval(-1_800)
            ),
            BuddySummary(
                id: "fixture-mateo",
                displayName: "Mateo Silva",
                friendCode: "MATE-6789",
                sinceAt: Date().addingTimeInterval(-86_400 * 45),
                avatarID: "avatar_note",
                profilePhotoURL: "",
                publicLevel: 12,
                lastPracticedAt: Date().addingTimeInterval(-86_400 * 3)
            )
        ]
    }

    private var displayedThreads: [SocialChatThread] {
        guard usesDebugFixtures else { return chat.threads }
        let now = Date()
        return [
            SocialChatThread(
                id: "fixture-thread-aya",
                kind: .friend,
                title: "Aya Chen",
                subtitle: "Violin · Level 18",
                friendUID: "fixture-aya",
                lastMessageText: "That run-through sounded so much freer.",
                lastMessageAt: now.addingTimeInterval(-420),
                lastMessageSenderUID: "fixture-aya",
                unreadCount: 1
            ),
            SocialChatThread(
                id: "fixture-thread-mateo",
                kind: .friend,
                title: "Mateo Silva",
                subtitle: "Piano · Level 12",
                friendUID: "fixture-mateo",
                lastMessageText: "Practicing the middle section tonight.",
                lastMessageAt: now.addingTimeInterval(-7_200),
                lastMessageSenderUID: "fixture-me",
                unreadCount: 0
            )
        ]
    }

    var body: some View {
        ZStack {
            StudioQuestBackground()
            VStack(spacing: 0) {
                header
                sectionPicker
                content
            }
        }
        .toolbar(isStandalone ? .visible : .hidden, for: .navigationBar)
        .navigationTitle(isStandalone ? section.rawValue : "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $signInPresented) {
            AccountSetupView()
        }
        .sheet(isPresented: $addFriendPresented) {
            NavigationStack {
                StudioQuestScrollPage {
                    VStack(alignment: .leading, spacing: 18) {
                        StudioQuestPageTitle(title: "Add a friend", subtitle: "Enter their PractiQuest friend code.")
                        TextField("ABCD-2345", text: $friendCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.title3.monospaced())
                            .padding(14)
                            .background(
                                StudioQuestTokens.ColorRole.surface(colorScheme),
                                in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control)
                            )
                        Button("Send request") {
                            let code = friendCode
                            Task {
                                if await buddies.sendInvite(friendCode: code) != nil {
                                    friendCode = ""
                                    addFriendPresented = false
                                    section = .requests
                                }
                            }
                        }
                        .buttonStyle(StudioQuestPrimaryButtonStyle())
                    }
                    .padding(.top, 24)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") { addFriendPresented = false }
                    }
                }
            }
        }
        .sheet(isPresented: $composePresented) {
            NavigationStack {
                StudioQuestScrollPage {
                    VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
                        StudioQuestPageTitle(
                            title: "New message",
                            subtitle: "Choose a friend to start a conversation."
                        )

                        if displayedBuddies.isEmpty {
                            StudioQuestRowSurface {
                                ContentUnavailableView(
                                    "No friends yet",
                                    systemImage: "person.crop.circle.badge.plus",
                                    description: Text("Add a musician first, then start a conversation here.")
                                )
                            }
                        } else {
                            ForEach(displayedBuddies) { friend in
                                Button {
                                    composePresented = false
                                    DispatchQueue.main.async {
                                        router.navigate(
                                            to: .communityMessages(friendUID: friend.id, threadID: nil),
                                            in: .community
                                        )
                                    }
                                } label: {
                                    communityRow(
                                        avatarID: friend.avatarID,
                                        photoURL: friend.profilePhotoURL,
                                        title: friend.displayName,
                                        subtitle: activityLine(for: friend),
                                        badge: nil,
                                        isOnline: (usesDebugFixtures && friend.id == "fixture-aya")
                                            || buddies.isBuddyOnline(friend.id)
                                    )
                                    .padding(.horizontal, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        StudioQuestTokens.ColorRole.surface(colorScheme),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, StudioQuestTokens.Spacing.lg)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") { composePresented = false }
                    }
                }
            }
        }
        .onAppear {
            #if DEBUG
            if usesDebugFixtures {
                buddies.applyStudioQuestDebugFixtures()
            }
            #endif
        }
    }

    private var header: some View {
        HStack {
            Text("Community")
                .font(StudioQuestTokens.Typography.pageTitle)
                .tracking(-1)
            Spacer()
            Button {
                if firebase.isAnonymousUser {
                    signInPresented = true
                } else {
                    addFriendPresented = true
                }
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            Button {
                if firebase.isAnonymousUser {
                    signInPresented = true
                } else {
                    composePresented = true
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, StudioQuestTokens.Spacing.md)
        .padding(.top, StudioQuestTokens.Spacing.lg)
        .padding(.bottom, StudioQuestTokens.Spacing.lg)
    }

    @ViewBuilder
    private var sectionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                ForEach(Section.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        if section == item {
                            Label(item.rawValue, systemImage: "checkmark")
                        } else {
                            Text(item.rawValue)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(section.rawValue)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(
                    StudioQuestTokens.ColorRole.surface(colorScheme),
                    in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous)
                )
            }
            .padding(.horizontal, StudioQuestTokens.Spacing.md)
            .padding(.bottom, 12)
        } else {
            HStack(spacing: 0) {
                ForEach(Section.allCases) { item in
                    Button {
                        withAnimation(StudioQuestTokens.Motion.quick) {
                            section = item
                        }
                    } label: {
                        VStack(spacing: 7) {
                            Text(item.rawValue)
                                .font(.subheadline.weight(section == item ? .semibold : .regular))
                                .foregroundStyle(section == item ? .primary : .secondary)
                            Capsule()
                                .fill(section == item ? StudioQuestTokens.ColorRole.cobalt : .clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, StudioQuestTokens.Spacing.md)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var content: some View {
        if firebase.isAnonymousUser && !usesDebugFixtures {
            signInState
        } else {
            switch section {
            case .friends:
                friendRows
            case .messages:
                messageRows
            case .requests:
                requestsState
            }
        }
    }

    private var signInState: some View {
        ContentUnavailableView {
            Label("Your music community", systemImage: "person.2")
        } description: {
            Text("Keep practicing as a guest. Sign in only when you want friends, messages, duels, or cloud backup.")
        } actions: {
            Button("Continue to sign in") {
                signInPresented = true
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioQuestTokens.ColorRole.cobalt)
        }
        .frame(maxHeight: .infinity)
    }

    private var friendRows: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if displayedBuddies.isEmpty {
                    emptyCommunityRow(
                        title: "No friends yet",
                        subtitle: "Add a musician using their friend code.",
                        route: .communityFriends
                    )
                } else {
                    ForEach(displayedBuddies) { friend in
                        Button {
                            router.navigate(
                                to: .communityMessages(friendUID: friend.id, threadID: nil),
                                in: .community
                            )
                        } label: {
                            communityRow(
                                avatarID: friend.avatarID,
                                photoURL: friend.profilePhotoURL,
                                title: friend.displayName,
                                subtitle: activityLine(for: friend),
                                badge: nil,
                                isOnline: (usesDebugFixtures && friend.id == "fixture-aya") || buddies.isBuddyOnline(friend.id)
                            )
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                StudioQuestTokens.ColorRole.surface(colorScheme),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, StudioQuestTokens.Spacing.md)
            .padding(.top, 12)
            .padding(.bottom, 160)
        }
    }

    private var messageRows: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if displayedThreads.isEmpty {
                    emptyCommunityRow(
                        title: "No messages yet",
                        subtitle: "Start a conversation with a practice buddy.",
                        route: .communityMessages(friendUID: nil, threadID: nil)
                    )
                } else {
                    ForEach(displayedThreads) { thread in
                        Button {
                            router.navigate(
                                to: .communityMessages(friendUID: thread.friendUID, threadID: thread.id),
                                in: .community
                            )
                        } label: {
                            communityRow(
                                avatarID: "avatar_note",
                                photoURL: nil,
                                title: thread.title,
                                subtitle: thread.lastMessageText.isEmpty ? thread.subtitle : thread.lastMessageText,
                                badge: thread.unreadCount > 0 ? "\(thread.unreadCount)" : nil,
                                isOnline: thread.friendUID.map(buddies.isBuddyOnline) ?? false
                            )
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                StudioQuestTokens.ColorRole.surface(colorScheme),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contextMenu {
                            Button(thread.unreadCount > 0 ? "Mark read" : "Mark unread", systemImage: "envelope") {
                                chat.markThreadReadManually(thread.id)
                            }
                            Button("Pin or unpin", systemImage: "pin") {
                                chat.togglePin(threadID: thread.id)
                            }
                            Button("Mute or unmute", systemImage: "bell.slash") {
                                chat.toggleMute(threadID: thread.id)
                            }
                            Button("Hide conversation", systemImage: "eye.slash", role: .destructive) {
                                chat.hideThreadLocally(thread.id)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, StudioQuestTokens.Spacing.md)
            .padding(.top, 12)
            .padding(.bottom, 160)
        }
    }

    private var requestsState: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if buddies.incomingInvites.isEmpty && buddies.outgoingInvites.isEmpty {
                    emptyCommunityRow(
                        title: "No pending requests",
                        subtitle: "New requests will appear here.",
                        route: .communityRequests
                    )
                }
                if !buddies.incomingInvites.isEmpty {
                    Text("Incoming").font(.headline)
                    ForEach(buddies.incomingInvites) { invite in
                        requestRow(invite, incoming: true)
                    }
                }
                if !buddies.outgoingInvites.isEmpty {
                    Text("Sent").font(.headline)
                    ForEach(buddies.outgoingInvites) { invite in
                        requestRow(invite, incoming: false)
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 160)
        }
        .padding(.horizontal, StudioQuestTokens.Spacing.md)
    }

    private func communityRow(
        avatarID: String,
        photoURL: String?,
        title: String,
        subtitle: String,
        badge: String?,
        isOnline: Bool
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 13) {
                        communityAvatar(
                            avatarID: avatarID,
                            photoURL: photoURL,
                            title: title,
                            isOnline: isOnline
                        )
                        Text(title)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        communityBadge(badge)
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 13) {
                    communityAvatar(
                        avatarID: avatarID,
                        photoURL: photoURL,
                        title: title,
                        isOnline: isOnline
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    communityBadge(badge)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 13)
    }

    private func communityAvatar(
        avatarID: String,
        photoURL: String?,
        title: String,
        isOnline: Bool
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            PBAvatarView(
                avatarID: avatarID,
                displayName: title,
                profilePhotoURL: photoURL,
                size: 52
            )
            if isOnline {
                Circle()
                    .fill(StudioQuestTokens.ColorRole.mint)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(StudioQuestTokens.ColorRole.background(colorScheme), lineWidth: 2))
            }
        }
    }

    @ViewBuilder
    private func communityBadge(_ badge: String?) -> some View {
        if let badge {
            Text(badge)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(7)
                .background(StudioQuestTokens.ColorRole.cobalt, in: Circle())
        }
    }

    private func activityLine(for friend: BuddySummary) -> String {
        let online = (usesDebugFixtures && friend.id == "fixture-aya") || buddies.isBuddyOnline(friend.id)
        let status = online ? "Online" : "Offline"
        guard let date = friend.lastPracticedAt else { return status }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "\(status) · Practiced today" }
        let days = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 1)
        return "\(status) · Practiced \(days) \(days == 1 ? "day" : "days") ago"
    }

    private func requestRow(_ invite: BuddyInvite, incoming: Bool) -> some View {
        StudioQuestRowSurface {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    requestIdentity(invite, incoming: incoming)
                    Spacer()
                    requestActions(invite, incoming: incoming)
                }
                VStack(alignment: .leading, spacing: 12) {
                    requestIdentity(invite, incoming: incoming)
                    requestActions(invite, incoming: incoming)
                }
            }
        }
    }

    private func requestIdentity(_ invite: BuddyInvite, incoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(incoming ? invite.fromDisplayName : invite.toDisplayName)
                .font(.headline)
            Text(incoming ? "Wants to connect" : "Request sent")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func requestActions(_ invite: BuddyInvite, incoming: Bool) -> some View {
        HStack {
            if incoming {
                Button("Decline") { Task { await buddies.declineInvite(invite) } }
                    .buttonStyle(.bordered)
                Button("Accept") { Task { await buddies.acceptInvite(invite) } }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioQuestTokens.ColorRole.cobalt)
            } else {
                Button("Cancel") { Task { await buddies.cancelOutgoingInvite(invite) } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func emptyCommunityRow(title: LocalizedStringKey, subtitle: LocalizedStringKey, route: AppRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: "person.2")
                    .font(.title3)
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                    .frame(width: 48, height: 48)
                    .background(StudioQuestTokens.ColorRole.cobalt.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }
}

struct StudioQuestYouView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var buddies: BuddiesViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("practiquest.avatar.loadout") private var loadoutData = Data()

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                Text("You")
                    .font(StudioQuestTokens.Typography.pageTitle)
                    .tracking(-1)
                    .padding(.top, StudioQuestTokens.Spacing.sm)

                profileHero
                weeklyInsight
                activityTimeline
                secondaryLinks
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var profileHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                StudioQuestAvatarScene(
                    loadout: loadout,
                    layout: loadout.layout(),
                    displayName: displayName
                )

                NavigationLink(value: AppRoute.profile(userID: nil)) {
                    Image(systemName: "pencil")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .background(.regularMaterial, in: Circle())
                }
                .padding(12)
                .accessibilityLabel("Edit profile")
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.title2.bold())
                    Text("Level \(journey.level) musician")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                StudioQuestVerifiedLabel(isVerified: !firebase.isAnonymousUser)
            }
            .padding(.horizontal, 4)
        }
    }

    private var loadout: AvatarLoadout {
        (try? JSONDecoder().decode(AvatarLoadout.self, from: loadoutData))
            ?? .starter(for: buddies.myProfile?.avatarID)
    }

    private var displayName: String {
        let name = buddies.myProfile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Your studio" : name
    }

    private var weeklyInsight: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("This week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Consistency over intensity.")
                        .font(.headline)
                    Text("\(store.totalThisWeekSeconds / 60) minutes of practice")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(StudioQuestTokens.ColorRole.separator(colorScheme), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: min(Double(store.totalThisWeekSeconds) / (5 * 30 * 60), 1))
                        .stroke(StudioQuestTokens.ColorRole.cobalt, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(min(store.sessions.count, 99))")
                        .font(.headline.monospacedDigit())
                }
                .frame(width: 66, height: 66)
                .accessibilityLabel("\(store.sessions.count) recorded sessions")
            }
            weekBars
        }
        .padding(.vertical, 4)
    }

    private var weekBars: some View {
        HStack(alignment: .bottom, spacing: 14) {
            ForEach(weekDates, id: \.self) { date in
                let seconds = store.totalSeconds(onDayContaining: date)
                VStack(spacing: 6) {
                    Capsule()
                        .fill(seconds > 0 ? StudioQuestTokens.ColorRole.cobalt : StudioQuestTokens.ColorRole.separator(colorScheme))
                        .frame(width: 18, height: max(8, min(CGFloat(seconds) / 90, 54)))
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 78, alignment: .bottom)
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var activityTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent activity")
                .font(.headline)
            if store.sessions.isEmpty {
                Text("Complete a practice session to begin your timeline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(store.sessions.prefix(3), id: \.id) { session in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(StudioQuestTokens.ColorRole.mint)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.noteTitle.isEmpty ? "Practice session" : session.noteTitle)
                                .font(.subheadline.weight(.semibold))
                            Text("\(session.date.formatted(.relative(presentation: .named))) · \(DurationFormatter.string(from: session.durationSeconds))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var secondaryLinks: some View {
        VStack(spacing: 0) {
            profileLink("Activity", systemImage: "chart.bar.xaxis", route: .history)
            Divider()
            profileLink("Achievements", systemImage: "medal", route: .achievements)
            Divider()
            profileLink("Studio", systemImage: "lamp.floor.fill", route: .avatarStudio(section: .room))
            Divider()
            profileLink("Goals", systemImage: "scope", route: .goals)
            Divider()
            profileLink("History", systemImage: "clock.arrow.circlepath", route: .history)
            Divider()
            profileLink("PractiQuest Pro", systemImage: "sparkles", route: .pro(source: .you))
            Divider()
            profileLink("Settings", systemImage: "gearshape", route: .settings(section: nil))
        }
        .padding(.horizontal, 14)
        .background(
            StudioQuestTokens.ColorRole.surface(colorScheme),
            in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface)
        )
    }

    private func profileLink(_ title: LocalizedStringKey, systemImage: String, route: AppRoute) -> some View {
        NavigationLink(value: route) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                    .frame(width: 28)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}
