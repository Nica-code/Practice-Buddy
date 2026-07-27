import SwiftUI
import SwiftData
import Combine
import os
import FirebaseAuth
import UIKit
import UserNotifications

struct ContentView: View {
    private struct InviteJoinAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum IncomingLinkAction {
        case addBuddy(friendCode: String)
        case openPracticeStudio
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var featureFlags: StudioQuestFeatureFlags
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @AppStorage("practiquest.v2.destination") private var selectedTab: Int = AppDestination.today.rawValue
    @AppStorage("practiquest.v2.onboarding.completed") private var v2OnboardingCompleted: Bool = false
    #if DEBUG
    @AppStorage("practiquest.qa.openStudio") private var qaOpenStudio: Bool = false
    @State private var qaState: String?
    #endif
    @AppStorage("practiquest.community.shareActivity") private var shareFriendActivity = true
    @AppStorage("practiquest.appearance") private var studioQuestAppearance = "system"

    @StateObject private var store = SessionStore()
    @StateObject private var journeyManager = JourneyProgressManager()
    @StateObject private var duelLeagueManager = DuelLeagueManager()
    @StateObject private var friendRequestBadgeManager = FriendRequestBadgeManager()
    @StateObject private var presenceManager = FirebasePresenceManager()
    @StateObject private var socialChatManager = StudioChatViewModel()
    @StateObject private var notificationStore = PBNotificationStore.shared
    @StateObject private var versionGate: AppVersionGateManager
    @StateObject private var practiceCoordinator = PracticeSessionCoordinator()
    @StateObject private var appRouter = AppRouter()
    @StateObject private var buddiesManager = BuddiesViewModel()
    @StateObject private var friendActivityPublisher = FriendActivityPublisher()
    @StateObject private var identityUpgrade = IdentityUpgradeCoordinator()

    @State private var didInit = false
    @State private var sessionsCancellable: AnyCancellable?
    @State private var inviteJoinAlert: InviteJoinAlert?
    @State private var lastPipelineSyncKey: String?
    @State private var lastPipelineSyncAt: Date = .distantPast
    @State private var showNotificationPrimer: Bool = false
    @State private var didHandleQALaunch = false
    private let buddiesRepository = FirebaseBuddiesRepository()
    private let launchConfiguration: AppLaunchConfiguration

    init() {
        self.init(launchConfiguration: .current())
    }

    init(launchConfiguration: AppLaunchConfiguration) {
        self.launchConfiguration = launchConfiguration
        let versionGateState: AppVersionGateManager.State
        switch launchConfiguration.versionGateFixture {
        case .checking:
            versionGateState = .checking
        case .updateRequired:
            versionGateState = .updateRequired(
                latestVersion: "2.1.0",
                storeURL: URL(string: "https://apps.apple.com/app/id\(AppInfo.appStoreAppleID)")!
            )
        case nil:
            versionGateState = .idle
        }
        _versionGate = StateObject(
            wrappedValue: AppVersionGateManager(initialState: versionGateState)
        )
        _appRouter = StateObject(
            wrappedValue: AppRouter(
                selectedDestination: launchConfiguration.initialDestination,
                initialRoute: launchConfiguration.initialRoute,
                roomEditorPresented: launchConfiguration.roomEditorPresented
            )
        )
        #if DEBUG
        _qaState = State(initialValue: launchConfiguration.qaState)
        #endif
    }

    var body: some View {
        ZStack {
            rootContent
            #if DEBUG
            if let qaState {
                StudioQuestQAStateOverlay(state: qaState)
                    .zIndex(1500)
            }
            #endif
            if versionGate.shouldBlockLaunch {
                versionGateView
                    .zIndex(2000)
            }
        }
        .environment(\.studioQuestQAToolState, launchConfiguration.toolState)
        .onAppear {
            if !firebase.isAnonymousUser, firebase.currentUserID != nil {
                v2OnboardingCompleted = true
            }
            Task {
                await identityUpgrade.configure(
                    uid: firebase.currentUserID,
                    isAnonymous: firebase.isAnonymousUser,
                    upgradeRequired: featureFlags.snapshot.identityUpgradeRequired
                )
            }
            #if DEBUG
            if launchConfiguration.skipOnboarding {
                v2OnboardingCompleted = true
            }
            #endif

            guard !didInit else { return }
            didInit = true

            store.configure(context: modelContext)
            #if DEBUG
            if launchConfiguration.fixtureSet.includesPracticeHistory {
                store.applyStudioQuestFixture()
                PracticeQuestProgressStore.shared.applyStudioQuestFixture()
            }
            applyInitialPracticeStateIfNeeded()
            #endif
            sessionsCancellable = store.$sessions
                .sink { sessions in
                    journeyManager.handleSessionSnapshot(sessions)
                    friendActivityPublisher.update(
                        currentUserID: firebase.currentUserID,
                        isAnonymous: firebase.isAnonymousUser,
                        buddyIDs: buddiesManager.buddies.map(\.id),
                        latestSessionDate: sessions.first?.date,
                        sharingEnabled: UserDefaults.standard.object(forKey: "practiquest.community.shareActivity") as? Bool ?? true
                    )
                }
            PBTabBarStyle.apply(
                colorScheme: colorScheme,
                accent: UIColor(StudioQuestTokens.ColorRole.cobalt)
            )
            if purchaseManager.isPro {
                Task { _ = await journeyManager.claimProDailyCosmeticAllowance() }
            }
            if shouldCheckVersionGate {
                versionGate.checkIfNeeded()
            }
            refreshRuntimePipelines(forceUserPipeline: true)
            #if DEBUG
            // BuddiesViewModel.applyStudioQuestDebugFixtures() existed but was
            // never called from anywhere, so the friend fixtures could never
            // appear. It has to run *after* refreshRuntimePipelines, because
            // syncBuddies() stops the manager for an anonymous QA session and
            // that would clear the fixtures again.
            if launchConfiguration.fixtureSet.includesCommunity {
                buddiesManager.applyStudioQuestDebugFixtures()
            }
            #endif
        }
        .onChange(of: appRouter.selectedDestination) { _, destination in
            selectedTab = destination.rawValue
        }
        .onChange(of: colorScheme) {
            PBTabBarStyle.apply(
                colorScheme: colorScheme,
                accent: UIColor(StudioQuestTokens.ColorRole.cobalt)
            )
        }
        .onChange(of: firebase.currentUserID) { _, newUID in
            _ = newUID
            refreshRuntimePipelines(forceUserPipeline: false)
            Task {
                await identityUpgrade.configure(
                    uid: firebase.currentUserID,
                    isAnonymous: firebase.isAnonymousUser,
                    upgradeRequired: featureFlags.snapshot.identityUpgradeRequired
                )
            }
        }
        .onChange(of: firebase.isAnonymousUser) { _, _ in
            refreshRuntimePipelines(forceUserPipeline: false)
            Task {
                await identityUpgrade.configure(
                    uid: firebase.currentUserID,
                    isAnonymous: firebase.isAnonymousUser,
                    upgradeRequired: featureFlags.snapshot.identityUpgradeRequired
                )
            }
        }
        .onChange(of: purchaseManager.hasAdFree) { _, _ in
            if purchaseManager.isPro {
                Task { _ = await journeyManager.claimProDailyCosmeticAllowance() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if shouldCheckVersionGate {
                    versionGate.checkIfNeeded()
                }
                refreshRuntimePipelines(forceUserPipeline: true)
                Task {
                    await identityUpgrade.configure(
                        uid: firebase.currentUserID,
                        isAnonymous: firebase.isAnonymousUser,
                        upgradeRequired: featureFlags.snapshot.identityUpgradeRequired
                    )
                }
            } else {
                duelLeagueManager.pauseRealtime()
                friendRequestBadgeManager.stop()
                presenceManager.stop()
                socialChatManager.stop()
                buddiesManager.stop()
            }
        }
        .onChange(of: friendRequestBadgeManager.incomingCount) { _, _ in
            syncInAppNotificationStore()
            updateAppIconBadge()
        }
        .onChange(of: socialChatManager.unreadCount) { _, _ in
            syncInAppNotificationStore()
            updateAppIconBadge()
        }
        .onReceive(duelLeagueManager.$incomingInvites) { _ in
            syncInAppNotificationStore()
            updateAppIconBadge()
        }
        .onReceive(duelLeagueManager.$userDisplayNames) { _ in
            syncInAppNotificationStore()
        }
        .onReceive(notificationStore.$items) { _ in
            updateAppIconBadge()
        }
        .modifier(
            FriendActivitySyncModifier(
                buddies: buddiesManager,
                store: store,
                firebase: firebase,
                publisher: friendActivityPublisher,
                presence: presenceManager
            )
        )
        .onOpenURL { url in
            if Auth.auth().canHandle(url) {
                return
            }
            handleIncomingURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pbNotificationRouteRequested)) { notification in
            guard let route = notification.object as? PBNotificationRoute else { return }
            applyNotificationRoute(route)
        }
        .task {
            await MainActor.run {
                if let route = PBNotificationCenter.consumePendingRoute() {
                    applyNotificationRoute(route)
                }
            }
        }
        .environmentObject(store)
        .environmentObject(journeyManager)
        .environmentObject(duelLeagueManager)
        .environmentObject(socialChatManager)
        .environmentObject(practiceCoordinator)
        .environmentObject(appRouter)
        .environmentObject(buddiesManager)
        .environmentObject(identityUpgrade)
        .tint(StudioQuestTokens.ColorRole.cobalt)
        .alert(item: $store.lastAppError) { err in
            Alert(
                title: Text(LocalizedStringKey(err.title)),
                message: Text(LocalizedStringKey(err.message)),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: $inviteJoinAlert) { state in
            Alert(
                title: Text(LocalizedStringKey(state.title)),
                message: Text(LocalizedStringKey(state.message)),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showNotificationPrimer) {
            PBNotificationPrimerView(
                onEnable: handleNotificationPrimerEnable,
                onSkip: handleNotificationPrimerSkip
            )
        }
        .preferredColorScheme(preferredStudioQuestColorScheme)
    }

    #if DEBUG
    private func applyInitialPracticeStateIfNeeded() {
        guard !didHandleQALaunch else { return }
        didHandleQALaunch = true
        if launchConfiguration.isQA {
            practiceCoordinator.resetForDeterministicQA()
        }

        switch launchConfiguration.practiceState {
        case .idle:
            if qaOpenStudio {
                DispatchQueue.main.async {
                    practiceCoordinator.quickStart()
                }
            }
        case .planned:
            practiceCoordinator.preparePlan(
                piece: "Bach: Partita No. 2",
                tasks: [
                    PracticePlanTask(title: "Warm-up", minutes: 5),
                    PracticePlanTask(title: "Focused passage", minutes: 15)
                ],
                verified: true,
                launchContext: PracticeLaunchContext(source: "qa")
            )
        case .running:
            DispatchQueue.main.async {
                practiceCoordinator.quickStart()
            }
        case .paused:
            DispatchQueue.main.async {
                practiceCoordinator.quickStart()
                practiceCoordinator.pause()
            }
        }
    }
    #endif

    private var shouldCheckVersionGate: Bool {
        #if DEBUG
        !launchConfiguration.skipVersionGate
        #else
        true
        #endif
    }

    private var preferredStudioQuestColorScheme: ColorScheme? {
        #if DEBUG
        if let appearance = launchConfiguration.appearance {
            switch appearance {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
        #endif
        switch studioQuestAppearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if !firebase.isReady {
            ZStack {
                StudioQuestBackground()
                StudioQuestLoadingState(title: "Preparing your practice world…")
                    .padding(StudioQuestTokens.Spacing.lg)
                    .frame(maxWidth: 420)
                    .studioQuestSurface(.resting)
                    .padding(StudioQuestTokens.Spacing.lg)
                    .accessibilityIdentifier("launch.firebase.loading")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !v2OnboardingCompleted {
            PracticeFirstOnboardingView {
                v2OnboardingCompleted = true
            }
        } else if identityUpgrade.state == .required {
            StudioQuestProfileUpgradeView()
        } else if identityUpgrade.state == .offlineRestricted {
            StudioQuestOfflineProfileUpgradeView()
        } else {
            StudioQuestShell(
                socialBadgeCount: socialTabBadgeCount
            )
        }
    }


    @ViewBuilder
    private var versionGateView: some View {
        ZStack {
            StudioQuestBackground()

            VStack(spacing: StudioQuestTokens.Spacing.md) {
                switch versionGate.state {
                case .checking, .idle:
                    StudioQuestLoadingState(title: "Checking for updates…")
                        .accessibilityIdentifier("versionGate.checking")
                case .updateRequired(let latestVersion, _):
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                        .accessibilityHidden(true)
                    Text("Update Required")
                        .font(StudioQuestTokens.Typography.heroTitle)
                        .multilineTextAlignment(.center)
                    Text("A newer version (\(latestVersion)) is available. Please update to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: StudioQuestTokens.Spacing.sm) {
                        Button("Update") {
                            versionGate.openUpdate()
                        }
                        .buttonStyle(StudioQuestPrimaryButtonStyle())
                        .accessibilityIdentifier("versionGate.update")

                        Button("I Updated, Check Again") {
                            versionGate.recheckNow()
                        }
                        .buttonStyle(StudioQuestSecondaryButtonStyle())
                        .accessibilityIdentifier("versionGate.recheck")
                    }
                case .upToDate:
                    EmptyView()
                }
            }
            .padding(StudioQuestTokens.Spacing.lg)
            .frame(maxWidth: 420)
            .studioQuestSurface(.lifted)
            .padding(StudioQuestTokens.Spacing.lg)
        }
        .allowsHitTesting(true)
    }

    private var socialTabBadgeCount: Int? {
        let count = friendRequestBadgeManager.incomingCount + socialChatManager.unreadCount
        return count > 0 ? count : nil
    }

    private var needsAccountSetup: Bool {
        guard let uid = firebase.currentUserID, !uid.isEmpty else { return true }
        return false
    }

    private var canRunRealtimePipelines: Bool {
        guard scenePhase == .active else { return false }
        guard let uid = firebase.currentUserID, !uid.isEmpty else { return false }
        guard !firebase.isAnonymousUser else { return false }
        guard !needsAccountSetup else { return false }
        return true
    }

    private func refreshRuntimePipelines(forceUserPipeline: Bool) {
        syncUserPipelines(force: forceUserPipeline)
        syncFriendRequestBadge()
        syncPresence()
        syncSocialChatBadge()
        syncBuddies()
        syncPushPipeline()
        syncInAppNotificationStore()
        updateAppIconBadge()
    }

    private func syncUserPipelines(force: Bool = false) {
        let linkUID: String? = {
            guard let uid = firebase.currentUserID, !uid.isEmpty, !firebase.isAnonymousUser else { return nil }
            return uid
        }()

        let syncKey = [
            scenePhase == .active ? "active" : "inactive",
            firebase.currentUserID ?? "nil",
            firebase.isAnonymousUser ? "anon" : "auth",
            purchaseManager.isPro ? "pro" : "free",
            needsAccountSetup ? "setup" : "ready"
        ].joined(separator: "|")

        let now = Date()
        if !force,
           syncKey == lastPipelineSyncKey,
           now.timeIntervalSince(lastPipelineSyncAt) < 15 {
            return
        }
        lastPipelineSyncKey = syncKey
        lastPipelineSyncAt = now

        purchaseManager.linkToUser(uid: linkUID, email: firebase.currentUserEmail)
        journeyManager.linkToUser(uid: linkUID)

        guard canRunRealtimePipelines else {
            duelLeagueManager.pauseRealtime()
            return
        }

        duelLeagueManager.start(uid: firebase.currentUserID)
    }

    private func syncFriendRequestBadge() {
        guard scenePhase == .active else {
            friendRequestBadgeManager.stop()
            return
        }
        guard let uid = firebase.currentUserID, !uid.isEmpty else {
            friendRequestBadgeManager.stop()
            return
        }
        guard !firebase.isAnonymousUser else {
            friendRequestBadgeManager.stop()
            return
        }
        friendRequestBadgeManager.start(uid: uid)
    }

    private func syncPresence() {
        guard scenePhase == .active else {
            presenceManager.stop()
            return
        }
        guard shareFriendActivity else {
            presenceManager.stop()
            return
        }
        guard let uid = firebase.currentUserID, !uid.isEmpty else {
            presenceManager.stop()
            return
        }
        guard !firebase.isAnonymousUser else {
            presenceManager.stop()
            return
        }
        presenceManager.start(uid: uid)
    }

    private func syncBuddies() {
        guard scenePhase == .active,
              let uid = firebase.currentUserID,
              !uid.isEmpty,
              !firebase.isAnonymousUser else {
            buddiesManager.stop()
            return
        }
        Task {
            await buddiesManager.start(for: uid)
        }
    }

    private func publishFriendActivity(buddyIDs: [String]) {
        friendActivityPublisher.update(
            currentUserID: firebase.currentUserID,
            isAnonymous: firebase.isAnonymousUser,
            buddyIDs: buddyIDs,
            latestSessionDate: store.sessions.first?.date,
            sharingEnabled: shareFriendActivity
        )
    }

    private func syncSocialChatBadge() {
        guard scenePhase == .active else {
            socialChatManager.stop()
            return
        }
        guard let uid = firebase.currentUserID, !uid.isEmpty else {
            socialChatManager.stop()
            return
        }
        guard !firebase.isAnonymousUser else {
            socialChatManager.stop()
            return
        }
        socialChatManager.start(uid: uid)
    }

    private func syncPushPipeline() {
        guard scenePhase == .active else { return }
        guard let uid = firebase.currentUserID, !uid.isEmpty else { return }
        guard !firebase.isAnonymousUser else { return }

        Task { @MainActor in
            let defaults = UserDefaults.standard
            let promptKey = "pb.notifications.prompted.\(uid)"
            let hasPrompted = defaults.bool(forKey: promptKey)

            if !hasPrompted {
                // Show a soft pre-prompt before the one-shot OS dialog when the user
                // hasn't decided yet. If they already resolved it at the OS level
                // (e.g. a reinstall), skip the primer and proceed normally.
                let status = await PBNotificationCenter.authorizationStatus()
                if status == .notDetermined {
                    showNotificationPrimer = true
                    return
                }
                defaults.set(true, forKey: promptKey)
                await PushTokenManager.shared.registerForRemoteNotificationsIfAuthorized()
            } else {
                await PushTokenManager.shared.registerForRemoteNotificationsIfAuthorized()
            }

            await PushTokenManager.shared.syncPendingTokenIfPossible()
            await PushTokenManager.shared.updateNotificationPreferences(
                duelsEnabled: defaults.object(forKey: PBNotificationPreferenceKey.duels) as? Bool ?? true,
                messagesEnabled: defaults.object(forKey: PBNotificationPreferenceKey.messages) as? Bool ?? true,
                goalsEnabled: defaults.object(forKey: PBNotificationPreferenceKey.goals) as? Bool ?? true,
                friendRequestsEnabled: defaults.object(forKey: PBNotificationPreferenceKey.friendRequests) as? Bool ?? true,
                studioInvitesEnabled: false,
                assignmentsEnabled: false,
                buddiesEnabled: defaults.object(forKey: PBNotificationPreferenceKey.buddies) as? Bool ?? true
            )
        }
    }

    private func handleNotificationPrimerEnable() {
        showNotificationPrimer = false
        guard let uid = firebase.currentUserID, !uid.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: "pb.notifications.prompted.\(uid)")
        Task { @MainActor in
            // Triggers the one-shot OS permission dialog, then runs the rest of the
            // push pipeline (token sync + preference upload) now that prompted=true.
            _ = await PBNotificationCenter.requestAuthorizationIfNeeded()
            syncPushPipeline()
        }
    }

    private func handleNotificationPrimerSkip() {
        showNotificationPrimer = false
        guard let uid = firebase.currentUserID, !uid.isEmpty else { return }
        // Record that we primed so we don't nag on every launch. Users can still
        // enable later from Settings, which routes to the system settings page.
        UserDefaults.standard.set(true, forKey: "pb.notifications.prompted.\(uid)")
    }

    private func updateAppIconBadge() {
        guard scenePhase == .active else { return }
        let badgeCount: Int
        guard !firebase.isAnonymousUser, firebase.currentUserID != nil else {
            badgeCount = 0
            if #available(iOS 17.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(badgeCount) { _ in }
            } else {
                UIApplication.shared.applicationIconBadgeNumber = badgeCount
            }
            return
        }
        badgeCount = notificationStore.unreadCount
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(badgeCount) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = badgeCount
        }
        Task { @MainActor in
            await PushTokenManager.shared.updateServerBadgeCount(badgeCount)
        }
    }

    private func syncInAppNotificationStore() {
        notificationStore.syncFriendRequests(friendRequestBadgeManager.pendingInvites)
        notificationStore.syncChatThreads(socialChatManager.threads)
        notificationStore.syncDuelInvites(
            duelLeagueManager.incomingInvites,
            cachedNames: duelLeagueManager.userDisplayNames
        )
    }

    private func handleIncomingURL(_ url: URL) {
        guard let action = incomingLinkAction(from: url) else { return }

        guard !firebase.isAnonymousUser, firebase.currentUserID != nil else {
            inviteJoinAlert = InviteJoinAlert(
                title: "Sign In Required",
                message: "Please sign in first, then open the buddy invite link again."
            )
            return
        }

        switch action {
        case .openPracticeStudio:
            practiceCoordinator.quickStart()
        case .addBuddy(let friendCode):
            Task {
                do {
                    let profile = try await buddiesRepository.ensureCurrentUserProfile()
                    _ = try await buddiesRepository.sendInvite(from: profile, friendCode: friendCode)
                    await MainActor.run {
                        PBGrowthMetrics.record(.buddyInviteAutoSent)
                        appRouter.replacePath(with: .communityFriends, in: .community)
                        inviteJoinAlert = InviteJoinAlert(
                            title: "Friend Request Sent",
                            message: "Your buddy request is now pending."
                        )
                    }
                } catch {
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    await MainActor.run {
                        inviteJoinAlert = InviteJoinAlert(
                            title: "Could Not Send Request",
                            message: msg
                        )
                    }
                }
            }
        }
    }

    private func incomingLinkAction(from url: URL) -> IncomingLinkAction? {
        if url.scheme?.lowercased() == "practicebuddy",
           url.host?.lowercased() == "practice" {
            return .openPracticeStudio
        }
        if let friendCode = buddyInviteCode(from: url) {
            return .addBuddy(friendCode: friendCode)
        }
        return nil
    }

    private func buddyInviteCode(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "practicebuddy" else { return nil }
        guard let host = url.host?.lowercased(), host == "add-buddy" else { return nil }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value,
           !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return code.uppercased()
        }
        let pathCode = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return pathCode.isEmpty ? nil : pathCode.uppercased()
    }

    private func applyNotificationRoute(_ route: PBNotificationRoute) {
        PBLog.firebase.info("Applying notification route: \(String(describing: route), privacy: .public)")
        switch route {
        case .homeGoals:
            appRouter.replacePath(with: .goals, in: .today)
        case .playDuel(let challengeID):
            appRouter.replacePath(with: .duelArena(challengeID: challengeID), in: .quest)
        case .socialFriendRequests:
            appRouter.replacePath(with: .communityRequests, in: .community)
        case .socialChat(let friendUID, let threadID):
            appRouter.replacePath(
                with: .communityMessages(friendUID: friendUID, threadID: threadID),
                in: .community
            )
        case .practiceMoment(let momentID):
            appRouter.replacePath(with: .practiceMoment(momentID: momentID), in: .community)
        case .publicProfile(let userID):
            appRouter.replacePath(with: .publicProfile(userID: userID), in: .community)
        }
    }
}

private struct FriendActivitySyncModifier: ViewModifier {
    @ObservedObject var buddies: BuddiesViewModel
    @ObservedObject var store: SessionStore
    @ObservedObject var firebase: FirebaseBootstrap
    @ObservedObject var publisher: FriendActivityPublisher
    @ObservedObject var presence: FirebasePresenceManager
    @AppStorage("practiquest.community.shareActivity") private var sharingEnabled = true

    func body(content: Content) -> some View {
        content
            .onReceive(buddies.$buddies) { rows in
                publish(buddyIDs: rows.map(\.id))
            }
            .onChange(of: sharingEnabled) { _, enabled in
                publish(buddyIDs: buddies.buddies.map(\.id))
                if !enabled {
                    presence.stop()
                } else if let uid = firebase.currentUserID,
                          !uid.isEmpty,
                          !firebase.isAnonymousUser {
                    presence.start(uid: uid)
                }
            }
    }

    private func publish(buddyIDs: [String]) {
        publisher.update(
            currentUserID: firebase.currentUserID,
            isAnonymous: firebase.isAnonymousUser,
            buddyIDs: buddyIDs,
            latestSessionDate: store.sessions.first?.date,
            sharingEnabled: sharingEnabled
        )
    }
}
