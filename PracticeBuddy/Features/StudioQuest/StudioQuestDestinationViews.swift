import SwiftUI
import Charts

struct StudioQuestQuestView: View {
    private enum QuestSection: String, CaseIterable, Identifiable {
        case journey = "Journey"
        case competition = "Duels & Leagues"
        var id: String { rawValue }
    }

    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var buddies: BuddiesViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("practiquest.avatar.loadout") private var loadoutData = Data()
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
                    }
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
        StudioQuestTokenChip()
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
        HStack(spacing: 24) {
            ForEach(QuestSection.allCases) { item in
                Button {
                    withAnimation(StudioQuestTokens.Motion.quick) {
                        section = item
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(item.rawValue)
                            .font(.subheadline.weight(section == item ? .semibold : .regular))
                            .foregroundStyle(section == item ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Capsule()
                            .fill(section == item ? StudioQuestTokens.ColorRole.cobalt : .clear)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
        }
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

                StudioQuestAvatarRenderer(
                    loadout: questAvatarLoadout,
                    displayName: questAvatarName,
                    size: min(proxy.size.width * 0.29, proxy.size.height * 0.19)
                )
                .position(
                    x: proxy.size.width * 0.39,
                    y: proxy.size.height * 0.57
                )
                .allowsHitTesting(false)

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

    private var questAvatarLoadout: AvatarLoadout {
        (try? JSONDecoder().decode(AvatarLoadout.self, from: loadoutData))
            ?? .starter(for: buddies.myProfile?.avatarID)
    }

    private var questAvatarName: String {
        let name = buddies.myProfile?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Your musician" : name
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
        StudioQuestCatalog.presentations { progressStore.count(for: $0) }
    }

    private var firstClaimableFeaturedQuest: QuestPresentation? {
        featuredQuests.first {
            journey.featuredQuestRewardStatus(questID: $0.id, isComplete: $0.isComplete) == .claimable
        }
    }

    private func nodePosition(for id: String) -> CGPoint {
        StudioQuestCatalog.definition(id: id)?.nodePosition ?? CGPoint(x: 0.72, y: 0.15)
    }

    private func nodeColor(for id: String) -> Color {
        StudioQuestCatalog.definition(id: id)?.nodeColor ?? StudioQuestTokens.ColorRole.violet
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // A claimable reward sits somewhere on a tall quest map, so it needs
            // to keep drawing the eye rather than animating once on appear —
            // `.symbolEffect(value: true)` never fired again after the first.
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(StudioQuestTokens.ColorRole.gold)
                .frame(width: 48, height: 48)
                .background(
                    StudioQuestTokens.ColorRole.gold.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .modifier(RewardPulse(isEnabled: !reduceMotion))

            VStack(alignment: .leading, spacing: 3) {
                Text("Reward unlocked")
                    .font(.subheadline.weight(.semibold))
                Text("\(rewardTokens) tokens · \(rewardTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button("Collect", action: collect)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(StudioQuestTokens.ColorRole.coral, in: Capsule())
        }
        .padding(StudioQuestTokens.Spacing.sm)
        .background(
            StudioQuestTokens.ColorRole.surface(colorScheme),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(StudioQuestTokens.ColorRole.coral.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct RewardPulse: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.phaseAnimator([false, true]) { view, lifted in
                view
                    .scaleEffect(lifted ? 1.12 : 1)
                    .rotationEffect(.degrees(lifted ? -5 : 0))
            } animation: { lifted in
                lifted
                    ? .spring(response: 0.34, dampingFraction: 0.5)
                    : .easeInOut(duration: 1.1)
            }
        } else {
            content
        }
    }
}

struct StudioQuestYouView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var buddies: BuddiesViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.studioQuestDockClearance) private var dockClearance
    @AppStorage("practiquest.avatar.loadout") private var loadoutData = Data()
    @AppStorage("pb.settings.dailyGoalMinutes") private var goalMinutes = 30

    var body: some View {
        GeometryReader { proxy in
            let heroHeight = min(max(proxy.size.height * 0.42, 300), 420)
            let margin = StudioQuestTokens.Spacing.pageMargin(for: proxy.size.width)

            ZStack(alignment: .top) {
                StudioQuestBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        parallaxHero(height: heroHeight, containerWidth: proxy.size.width)

                        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                            identityBlock
                            weeklyInsight
                            activityTimeline
                            secondaryLinks
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, margin)
                        .padding(.top, StudioQuestTokens.Spacing.md)
                        .padding(.bottom, dockClearance + StudioQuestTokens.Spacing.lg)
                        .background(
                            StudioQuestTokens.ColorRole.background(colorScheme)
                                // The body slides up over the artwork, so the
                                // seam needs a rounded lip rather than a cut.
                                .clipShape(
                                    UnevenRoundedRectangle(
                                        topLeadingRadius: 26,
                                        topTrailingRadius: 26,
                                        style: .continuous
                                    )
                                )
                        )
                        .offset(y: -26)
                    }
                }
                .coordinateSpace(.named(Self.scrollSpace))
                .ignoresSafeArea(edges: .top)

                heroControls
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private static let scrollSpace = "you.scroll"

    /// Stretches when pulled down and drifts at half speed when scrolled up.
    private func parallaxHero(height: CGFloat, containerWidth: CGFloat) -> some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named(Self.scrollSpace)).minY
            let stretch = max(0, minY)
            let parallax = reduceMotion ? 0 : min(0, minY) * 0.5

            StudioQuestAvatarScene(
                loadout: loadout,
                layout: loadout.layout(),
                displayName: displayName,
                presentation: .hero
            )
            .frame(width: containerWidth, height: height + stretch)
            .overlay(alignment: .top) {
                // Rooms range from a sunlit studio to a midnight stage, so the
                // status bar and title need their own scrim rather than relying
                // on the artwork happening to be dark up there.
                LinearGradient(
                    colors: [.black.opacity(0.22), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 130)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        .clear,
                        StudioQuestTokens.ColorRole.background(colorScheme).opacity(0.55),
                        StudioQuestTokens.ColorRole.background(colorScheme)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 150)
                .allowsHitTesting(false)
            }
            .offset(y: -stretch + parallax)
        }
        .frame(height: height)
    }

    /// Kept outside the ScrollView so it stays put while the artwork moves.
    ///
    /// There is deliberately no "You" title over the artwork: the tab bar
    /// already names the tab and the display name sits directly below the hero,
    /// so a third label was both redundant and unreadable against a sunlit room.
    private var heroControls: some View {
        HStack {
            Spacer()

            NavigationLink(value: AppRoute.profile(userID: nil)) {
                Image(systemName: "pencil")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Edit profile")
        }
        .padding(.horizontal, StudioQuestTokens.Spacing.md)
    }

    private var identityBlock: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(StudioQuestTokens.Typography.heroTitle)
                Text("Level \(journey.level) musician")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            StudioQuestVerifiedLabel(isVerified: !firebase.isAnonymousUser)
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

    /// Minutes practised this week against the weekly target.
    private var weeklyProgress: Double {
        let target = Double(goalMinutes * 5 * 60)
        guard target > 0 else { return 0 }
        return min(Double(store.totalThisWeekSeconds) / target, 1)
    }

    private var weeklyInsight: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    StudioQuestEyebrow("This week")
                    Text("\(store.totalThisWeekSeconds / 60) minutes practised")
                        .font(StudioQuestTokens.Typography.cardTitle)
                        .contentTransition(.numericText())
                    Text("\(store.sessions.count) session\(store.sessions.count == 1 ? "" : "s") recorded")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // The ring previously filled by weekly minutes but printed the
                // session count in the middle, so the number and the arc were
                // measuring two different things.
                ZStack {
                    Circle()
                        .stroke(StudioQuestTokens.ColorRole.separator(colorScheme), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: weeklyProgress)
                        .stroke(StudioQuestTokens.ColorRole.cobalt, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(StudioQuestTokens.Motion.gentle, value: weeklyProgress)
                    Text("\(Int(weeklyProgress * 100))%")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(width: 66, height: 66)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weekly practice goal")
                .accessibilityValue("\(Int(weeklyProgress * 100)) percent")
            }
            weekBars
        }
        .padding(StudioQuestTokens.Spacing.md)
        .studioQuestSurface()
    }

    /// Swift Charts rather than hand-stacked capsules: it gets axis handling,
    /// VoiceOver audio graphs and sensible scaling for free, and it no longer
    /// reserves 78pt of empty space on a week with no practice.
    private var weekBars: some View {
        let entries = weekDates.map { date in
            WeekEntry(date: date, minutes: store.totalSeconds(onDayContaining: date) / 60)
        }
        let peak = max(entries.map(\.minutes).max() ?? 0, goalMinutes)

        return Chart(entries) { entry in
            BarMark(
                x: .value("Day", entry.date, unit: .day),
                y: .value("Minutes", entry.minutes),
                width: .fixed(18)
            )
            .clipShape(Capsule())
            .foregroundStyle(
                entry.minutes >= goalMinutes
                    ? StudioQuestTokens.ColorRole.mint
                    : StudioQuestTokens.ColorRole.cobalt
            )
        }
        .chartYScale(domain: 0...max(peak, 1))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
                    .font(.caption2)
                    // Charts tints axis labels with the ambient accent, which
                    // made the weekday row read as interactive cobalt text.
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(height: entries.allSatisfy { $0.minutes == 0 } ? 52 : 92)
        .overlay {
            if entries.allSatisfy({ $0.minutes == 0 }) {
                Text("No practice logged this week yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 18)
            }
        }
        .accessibilityLabel("Practice minutes this week")
    }

    private struct WeekEntry: Identifiable {
        let date: Date
        let minutes: Int
        var id: Date { date }
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
            profileLink("Goals", systemImage: "scope", route: .goals)
            Divider()
            profileLink("History", systemImage: "clock.arrow.circlepath", route: .history)
            Divider()
            profileLink("Achievements", systemImage: "medal", route: .achievements)
            Divider()
            profileLink("Avatar Studio", systemImage: "lamp.floor.fill", route: .avatarStudio(section: .customize))
            Divider()
            profileLink("PractiQuest Pro", systemImage: "sparkles", route: .pro(source: .you))
            Divider()
            profileLink("Settings", systemImage: "gearshape", route: .settings(section: nil))
        }
        .padding(.horizontal, 14)
        .studioQuestSurface()
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
