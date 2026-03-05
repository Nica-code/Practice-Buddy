import SwiftUI
import SwiftData
import Combine

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

    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0
    @AppStorage("pb.studio.hub.section") private var socialSectionRawValue: String = "friends"
    @AppStorage("pb.social.jumpTarget") private var socialJumpTargetRaw: String = ""
    @AppStorage("pb.social.chat.openFriendUID") private var socialOpenFriendUID: String = ""
    @AppStorage("pb.social.chat.openThreadID") private var socialOpenThreadID: String = ""
    @AppStorage("pb.play.openChallengeID") private var playOpenChallengeID: String = ""
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
            syncUserPipelines(force: true)
            syncFriendRequestBadge()
            syncPresence()
            syncSocialChatBadge()
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
            syncUserPipelines()
            syncFriendRequestBadge()
            syncPresence()
            syncSocialChatBadge()
        }
        .onChange(of: firebase.isAnonymousUser) { _, _ in
            syncUserPipelines()
            syncFriendRequestBadge()
            syncPresence()
            syncSocialChatBadge()
        }
        .onChange(of: purchaseManager.isPro) { _, isPro in
            guard scenePhase == .active, canRunRealtimePipelines else { return }
            warmupOfWeekManager.start(
                uid: firebase.currentUserID,
                accountType: .student,
                isPro: isPro
            )
            Task { await assignmentLinkManager.flushPendingQueue() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                syncUserPipelines(force: true)
                syncFriendRequestBadge()
                syncPresence()
                syncSocialChatBadge()
            } else {
                assignmentLinkManager.pauseRealtime()
                warmupOfWeekManager.pauseRealtime()
                duelLeagueManager.pauseRealtime()
                friendRequestBadgeManager.stop()
                presenceManager.stop()
                socialChatManager.stop()
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pbNotificationRouteRequested)) { notification in
            guard let route = notification.object as? PBNotificationRoute else { return }
            applyNotificationRoute(route)
        }
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

    private func resumeRealtimeManagers() {
        assignmentLinkManager.start(uid: firebase.currentUserID, accountType: .student)
        warmupOfWeekManager.start(uid: firebase.currentUserID, accountType: .student, isPro: purchaseManager.isPro)
        Task { await assignmentLinkManager.flushPendingQueue() }
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
}
