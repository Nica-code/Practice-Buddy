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
        case joinStudio(inviteCode: String)
        case addBuddy(friendCode: String)
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var adsManager: PBAdsManager

    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0
    @AppStorage("pb.studio.hub.section") private var socialSectionRawValue: String = "friends"
    @AppStorage("pb.social.jumpTarget") private var socialJumpTargetRaw: String = ""
    @AppStorage("pb.social.chat.openFriendUID") private var socialOpenFriendUID: String = ""
    @AppStorage("pb.social.chat.openThreadID") private var socialOpenThreadID: String = ""
    @AppStorage("pb.play.openChallengeID") private var playOpenChallengeID: String = ""
    @AppStorage("pb.onboarding.tutorial.forceReplayToken") private var tutorialReplayToken: Int = 0
    @AppStorage("pb.onboarding.tutorial.handledReplayToken") private var handledTutorialReplayToken: Int = 0
    @AppStorage(PBFontChoice.selectionKey) private var selectedFontID: String = PBFontChoice.systemDefault.id

    @StateObject private var themeManager = ThemeManager()
    @StateObject private var store = SessionStore()
    @StateObject private var journeyManager = JourneyProgressManager()
    @StateObject private var duelLeagueManager = DuelLeagueManager()
    @StateObject private var assignmentLinkManager = AssignmentLinkManager()
    @StateObject private var warmupOfWeekManager = WarmupOfWeekManager()
    @StateObject private var friendRequestBadgeManager = FriendRequestBadgeManager()
    @StateObject private var presenceManager = FirebasePresenceManager()
    @StateObject private var socialChatManager = StudioChatViewModel()

    @State private var didInit = false
    @State private var sessionsCancellable: AnyCancellable?
    @State private var inviteJoinAlert: InviteJoinAlert?
    @State private var lastPipelineSyncKey: String?
    @State private var lastPipelineSyncAt: Date = .distantPast
    @State private var showFirstRunTutorial: Bool = false
    private let studiosRepository = FirebaseStudiosRepository()
    private let buddiesRepository = FirebaseBuddiesRepository()

    var body: some View {
        let fontChoice = PBFontChoice.byID(selectedFontID)
        let typography = PBTypography.forTheme(themeManager.theme, fontChoice: fontChoice)

        rootContent
        .onAppear {
            migrateTabSelectionIfNeeded()

            guard !didInit else { return }
            didInit = true

            store.configure(context: modelContext)
            sessionsCancellable = store.$sessions
                .sink { sessions in
                    journeyManager.handleSessionSnapshot(sessions)
                }
            themeManager.refresh()
            PBTabBarStyle.apply(colorScheme: colorScheme, accent: UIColor(themeManager.theme.accent), fontChoice: fontChoice)
            adsManager.syncAdFreeStatus(purchaseManager.hasAdFree)
            refreshRuntimePipelines(forceUserPipeline: true, forceTutorialSync: true)
        }
        .onChange(of: colorScheme) {
            PBTabBarStyle.apply(colorScheme: colorScheme, accent: UIColor(themeManager.theme.accent), fontChoice: fontChoice)
        }
        .onChange(of: themeManager.theme.id) { _, _ in
            PBTabBarStyle.apply(colorScheme: colorScheme, accent: UIColor(themeManager.theme.accent), fontChoice: fontChoice)
        }
        .onChange(of: selectedFontID) { _, _ in
            let refreshedChoice = PBFontChoice.byID(selectedFontID)
            PBTabBarStyle.apply(
                colorScheme: colorScheme,
                accent: UIColor(themeManager.theme.accent),
                fontChoice: refreshedChoice
            )
        }
        .onChange(of: firebase.currentUserID) { _, newUID in
            _ = newUID
            refreshRuntimePipelines(forceUserPipeline: false, forceTutorialSync: true)
        }
        .onChange(of: firebase.isAnonymousUser) { _, _ in
            refreshRuntimePipelines(forceUserPipeline: false, forceTutorialSync: true)
        }
        .onChange(of: purchaseManager.hasAdFree) { _, _ in
            adsManager.syncAdFreeStatus(purchaseManager.hasAdFree)
            guard scenePhase == .active, canRunRealtimePipelines else { return }
            warmupOfWeekManager.start(
                uid: firebase.currentUserID,
                accountType: .student,
                isPro: purchaseManager.featuresUnlocked
            )
            Task { await assignmentLinkManager.flushPendingQueue() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshRuntimePipelines(forceUserPipeline: true, forceTutorialSync: false)
            } else {
                assignmentLinkManager.pauseRealtime()
                warmupOfWeekManager.pauseRealtime()
                duelLeagueManager.pauseRealtime()
                friendRequestBadgeManager.stop()
                presenceManager.stop()
                socialChatManager.stop()
            }
        }
        .onChange(of: friendRequestBadgeManager.incomingCount) { _, _ in
            updateAppIconBadge()
        }
        .onChange(of: socialChatManager.unreadCount) { _, _ in
            updateAppIconBadge()
        }
        .onChange(of: tutorialReplayToken) { _, _ in
            syncTutorialPresentation(force: true)
        }
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
        .overlay {
            if showFirstRunTutorial {
                FirstRunTutorialView(
                    steps: tutorialSteps,
                    onSelectTab: { tabIndex in
                        withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                            selectedTab = min(max(tabIndex, 0), 4)
                        }
                    },
                    onComplete: { _, dontShowAgain in
                        completeTutorial(dontShowAgain: dontShowAgain)
                    }
                )
                .zIndex(1000)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showFirstRunTutorial)
        .environmentObject(store)
        .environmentObject(journeyManager)
        .environmentObject(themeManager)
        .environmentObject(duelLeagueManager)
        .environmentObject(assignmentLinkManager)
        .environmentObject(warmupOfWeekManager)
        .environmentObject(socialChatManager)
        .pbTheme(themeManager.theme)
        .pbTypography(typography)
        .pbGlobalFontDesign(fontChoice)
        .tint(themeManager.theme.accent)
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
    }

    @ViewBuilder
    private var rootContent: some View {
        if !firebase.isReady {
            VStack(spacing: 14) {
                PBSkeletonCard(lines: 2)
                    .padding(PBLayout.padMD)
                    .pbModernCard(palette: theme.resolvedPalette(for: colorScheme))
                PBSkeletonCard(lines: 3)
                    .padding(PBLayout.padMD)
                    .pbModernCard(palette: theme.resolvedPalette(for: colorScheme))
                ProgressView()
                    .padding(.top, 6)
            }
            .padding(PBLayout.padLG)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PBBackdropView(palette: theme.resolvedPalette(for: colorScheme)))
        } else if needsAccountSetup {
            AccountSetupView()
        } else {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    PBLazyView(HomeView())
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

                NavigationStack {
                    PBLazyView(JourneyView())
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem { Label("Play", systemImage: "gamecontroller") }
                .tag(1)

                if let socialBadgeCount = socialTabBadgeCount {
                    NavigationStack {
                        PBLazyView(StudioHubView())
                            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tabItem { Label("Social", systemImage: "person.2") }
                    .badge(socialBadgeCount)
                    .tag(2)
                } else {
                    NavigationStack {
                        PBLazyView(StudioHubView())
                            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tabItem { Label("Social", systemImage: "person.2") }
                    .tag(2)
                }

                NavigationStack {
                    PBLazyView(ProfileTabView())
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(3)

                NavigationStack {
                    PBLazyView(SettingsView())
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
            }
        }
    }

    private var socialTabBadgeCount: Int? {
        let count = friendRequestBadgeManager.incomingCount + socialChatManager.unreadCount
        return count > 0 ? count : nil
    }

    private var needsAccountSetup: Bool {
        guard let uid = firebase.currentUserID, !uid.isEmpty else { return true }
        return firebase.isAnonymousUser
    }

    private var canRunRealtimePipelines: Bool {
        guard scenePhase == .active else { return false }
        guard let uid = firebase.currentUserID, !uid.isEmpty else { return false }
        guard !firebase.isAnonymousUser else { return false }
        guard !needsAccountSetup else { return false }
        return true
    }

    private var theme: PBTheme { themeManager.theme }
    private var tutorialSteps: [FirstRunTutorialStep] {
        [
            FirstRunTutorialStep(
                id: "home",
                tabIndex: 0,
                title: "Home: Start Practice",
                message: "Use Start Practice for quick sessions. Practice tools and Session Builder are on Dashboard."
            ),
            FirstRunTutorialStep(
                id: "play",
                tabIndex: 1,
                title: "Play: Duels and Quests",
                message: "Queue a duel, challenge friends, and complete daily or weekly quests for tokens."
            ),
            FirstRunTutorialStep(
                id: "social",
                tabIndex: 2,
                title: "Social: Friends and Chat",
                message: "Manage requests, open chats, and stay connected with your practice buddies."
            ),
            FirstRunTutorialStep(
                id: "profile",
                tabIndex: 3,
                title: "Profile: Track Progress",
                message: "Check your level, league, and streak progress in one place."
            ),
            FirstRunTutorialStep(
                id: "settings",
                tabIndex: 4,
                title: "Settings: Personalize App",
                message: "Adjust goals, appearance, and notifications. You can replay this tour anytime from Settings."
            )
        ]
    }

    private func resumeRealtimeManagers() {
        assignmentLinkManager.start(uid: firebase.currentUserID, accountType: .student)
        warmupOfWeekManager.start(uid: firebase.currentUserID, accountType: .student, isPro: purchaseManager.featuresUnlocked)
        Task { await assignmentLinkManager.flushPendingQueue() }
    }

    private func refreshRuntimePipelines(forceUserPipeline: Bool, forceTutorialSync: Bool) {
        syncUserPipelines(force: forceUserPipeline)
        syncFriendRequestBadge()
        syncPresence()
        syncSocialChatBadge()
        syncPushPipeline()
        updateAppIconBadge()
        syncTutorialPresentation(force: forceTutorialSync)
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
            purchaseManager.hasAdFree ? "adfree" : "ads",
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
            assignmentLinkManager.pauseRealtime()
            warmupOfWeekManager.pauseRealtime()
            duelLeagueManager.pauseRealtime()
            return
        }

        resumeRealtimeManagers()
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
                _ = await PBNotificationCenter.requestAuthorizationIfNeeded()
                defaults.set(true, forKey: promptKey)
            } else {
                await PushTokenManager.shared.registerForRemoteNotificationsIfAuthorized()
            }

            await PushTokenManager.shared.syncPendingTokenIfPossible()
            await PushTokenManager.shared.updateNotificationPreferences(
                duelsEnabled: defaults.object(forKey: PBNotificationPreferenceKey.duels) as? Bool ?? true,
                messagesEnabled: defaults.object(forKey: PBNotificationPreferenceKey.messages) as? Bool ?? true,
                goalsEnabled: defaults.object(forKey: PBNotificationPreferenceKey.goals) as? Bool ?? true,
                friendRequestsEnabled: defaults.object(forKey: PBNotificationPreferenceKey.friendRequests) as? Bool ?? true,
                studioInvitesEnabled: defaults.object(forKey: PBNotificationPreferenceKey.studioInvites) as? Bool ?? true,
                assignmentsEnabled: defaults.object(forKey: PBNotificationPreferenceKey.assignments) as? Bool ?? true,
                buddiesEnabled: defaults.object(forKey: PBNotificationPreferenceKey.buddies) as? Bool ?? true
            )
        }
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
        badgeCount = friendRequestBadgeManager.incomingCount + socialChatManager.unreadCount
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(badgeCount) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = badgeCount
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard let action = incomingLinkAction(from: url) else { return }

        guard let uid = firebase.currentUserID, !firebase.isAnonymousUser else {
            let itemName: String
            switch action {
            case .joinStudio:
                itemName = "studio invite"
            case .addBuddy:
                itemName = "buddy invite"
            }
            inviteJoinAlert = InviteJoinAlert(
                title: "Sign In Required",
                message: "Please sign in first, then open the \(itemName) link again."
            )
            return
        }

        switch action {
        case .joinStudio(let inviteCode):
            Task {
                do {
                    try await studiosRepository.joinStudio(studentUID: uid, rawInviteCode: inviteCode)
                    await MainActor.run {
                        inviteJoinAlert = InviteJoinAlert(
                            title: "Joined Studio",
                            message: "You have successfully joined the studio."
                        )
                    }
                } catch {
                    let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    await MainActor.run {
                        inviteJoinAlert = InviteJoinAlert(
                            title: "Could Not Join Studio",
                            message: msg
                        )
                    }
                }
            }
        case .addBuddy(let friendCode):
            Task {
                do {
                    let profile = try await buddiesRepository.ensureCurrentUserProfile()
                    _ = try await buddiesRepository.sendInvite(from: profile, friendCode: friendCode)
                    await MainActor.run {
                        PBGrowthMetrics.record(.buddyInviteAutoSent)
                        selectedTab = 2
                        socialSectionRawValue = "friends"
                        socialJumpTargetRaw = "pendingRequests:\(Date().timeIntervalSince1970)"
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
        if let inviteCode = studioInviteCode(from: url) {
            return .joinStudio(inviteCode: inviteCode)
        }
        if let friendCode = buddyInviteCode(from: url) {
            return .addBuddy(friendCode: friendCode)
        }
        return nil
    }

    private func studioInviteCode(from url: URL) -> String? {
        if let scheme = url.scheme?.lowercased(), scheme == "practicebuddy" {
            guard let host = url.host?.lowercased(), host == "join-studio" else {
                return nil
            }
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
               !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return code
            }
            let pathCode = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return pathCode.isEmpty ? nil : pathCode
        }

        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return nil }
        guard let host = url.host?.lowercased() else { return nil }
        let allowedHost = AppInfo.inviteLinkBaseURL?.host?.lowercased()
        guard host == allowedHost else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard path == "join-studio" else { return nil }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value,
           !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return code.uppercased()
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
            selectedTab = 0
        case .playDuel(let challengeID):
            selectedTab = 1
            if let challengeID, !challengeID.isEmpty {
                playOpenChallengeID = challengeID
            }
        case .socialFriendRequests:
            selectedTab = 2
            socialSectionRawValue = "friends"
            socialJumpTargetRaw = "pendingRequests:\(Date().timeIntervalSince1970)"
        case .socialChat(let friendUID, let threadID):
            selectedTab = 2
            socialSectionRawValue = "chat"
            if let threadID, !threadID.isEmpty {
                socialOpenThreadID = threadID
            }
            if let friendUID, !friendUID.isEmpty {
                socialOpenFriendUID = friendUID
            }
        case .socialStudioInvites(let studioID):
            selectedTab = 2
            socialSectionRawValue = "friends"
            if let studioID, !studioID.isEmpty {
                socialJumpTargetRaw = "pendingRequests:\(Date().timeIntervalSince1970)"
            }
        }
    }

    private func migrateTabSelectionIfNeeded() {
        let key = "pb.tab.selection.v2.migrated"
        let migrated = UserDefaults.standard.bool(forKey: key)
        guard !migrated else {
            if !(0...4).contains(selectedTab) { selectedTab = 0 }
            return
        }

        let legacyValue = selectedTab
        switch legacyValue {
        case 0: selectedTab = 0
        case 1: selectedTab = 0
        case 2: selectedTab = 2
        case 3: selectedTab = 4
        case 4, 5: selectedTab = 1
        default: selectedTab = 0
        }

        UserDefaults.standard.set(true, forKey: key)
    }

    private func syncTutorialPresentation(force: Bool = false) {
        guard let uid = firebase.currentUserID, !uid.isEmpty else {
            showFirstRunTutorial = false
            return
        }
        guard !firebase.isAnonymousUser, !needsAccountSetup else {
            showFirstRunTutorial = false
            return
        }

        if tutorialReplayToken != handledTutorialReplayToken {
            OnboardingTutorialState.reset(uid: uid)
            handledTutorialReplayToken = tutorialReplayToken
            showFirstRunTutorial = true
            selectedTab = 0
            return
        }

        guard !showFirstRunTutorial else { return }
        guard force || scenePhase == .active else { return }

        if !OnboardingTutorialState.isCompleted(uid: uid) {
            showFirstRunTutorial = true
            selectedTab = 0
        }
    }

    private func completeTutorial(dontShowAgain: Bool) {
        if dontShowAgain, let uid = firebase.currentUserID, !uid.isEmpty {
            OnboardingTutorialState.markCompleted(uid: uid)
        }
        showFirstRunTutorial = false
    }
}
