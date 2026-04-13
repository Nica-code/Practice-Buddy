import SwiftUI
import UserNotifications

struct SettingsView: View {
    enum SettingsAnchor: String {
        case goals
        case appearance
        case notifications
    }

    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var purchaseManager: PurchaseManager
    @EnvironmentObject var adsManager: PBAdsManager
    @EnvironmentObject var firebase: FirebaseBootstrap
    @Environment(\.pbTheme) var theme
    @Environment(\.pbTypography) var type
    @Environment(\.colorScheme) var colorScheme

    @AppStorage("pb.settings.historyRetention") var historyRetention: Int = 0

    @AppStorage("pb.settings.dailyGoalMinutes") var goalMinutes: Int = 30
    @AppStorage("pb.settings.goalScope") var goalScopeRaw: String = GoalScope.today.rawValue
    @AppStorage("pb.notifications.buddies") var notifyBuddies: Bool = true
    @AppStorage("pb.notifications.duels") var notifyDuels: Bool = true
    @AppStorage("pb.notifications.messages") var notifyMessages: Bool = true
    @AppStorage("pb.notifications.goals") var notifyGoals: Bool = true
    @AppStorage("pb.notifications.friendRequests") var notifyFriendRequests: Bool = true
    @AppStorage("pb.settings.language") var appLanguageRaw: String = AppLanguage.english.rawValue
    @AppStorage("pb.onboarding.tutorial.forceReplayToken") var tutorialReplayToken: Int = 0
    @AppStorage("pb.tab.selection") var selectedTab: Int = 0

    @State var pendingRetentionTask: Task<Void, Never>?
    @State var pendingNotificationSyncTask: Task<Void, Never>?
    @State var animateHeader = false
    @State var scrollAnchorTarget: SettingsAnchor?
    @State var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @State var showSignOutConfirmation: Bool = false
    #if DEBUG
    @State var pushTestStatus: String?
    #endif

    var goalScopeBinding: Binding<GoalScope> {
        Binding(
            get: { GoalScope(rawValue: goalScopeRaw) ?? .today },
            set: { goalScopeRaw = $0.rawValue }
        )
    }

    var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: appLanguageRaw) ?? .english },
            set: { appLanguageRaw = $0.rawValue }
        )
    }

    var historyRetentionDisplay: String {
        historyRetention == 0 ? "Unlimited" : "\(historyRetention)"
    }

    var historyRetentionDisplayStyle: Color {
        historyRetention == 0 ? palette.textPrimary : palette.textSecondary
    }

    var canShowAdsDebugSection: Bool {
        AppInfo.isMasterAccount(
            uid: firebase.currentUserID,
            email: firebase.currentUserEmail
        )
    }
    
    func settingsSectionCard<Content: View>(
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

    var body: some View {
        VStack(spacing: 0) {
            settingsShortcutRow
            headerCard
            settingsForm
        }
        .background {
            PBBackdropView(palette: palette)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !animateHeader {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    animateHeader = true
                }
            }
        }
        .onChange(of: historyRetention) { _, _ in
            pendingRetentionTask?.cancel()
            pendingRetentionTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                store.retentionChanged()
            }
        }
        .task {
            queueNotificationPrefsSync()
            await refreshNotificationAuthorizationStatus()
        }
        .onChange(of: notifyBuddies) { _, _ in
            queueNotificationPrefsSync()
        }
        .onChange(of: notifyDuels) { _, _ in
            queueNotificationPrefsSync()
        }
        .onChange(of: notifyMessages) { _, _ in
            queueNotificationPrefsSync()
        }
        .onChange(of: notifyGoals) { _, _ in
            queueNotificationPrefsSync()
        }
        .onChange(of: notifyFriendRequests) { _, _ in
            queueNotificationPrefsSync()
        }
        .onDisappear {
            pendingRetentionTask?.cancel()
            pendingRetentionTask = nil
            pendingNotificationSyncTask?.cancel()
            pendingNotificationSyncTask = nil
        }
        .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                selectedTab = 0
                _ = firebase.signOutCurrentUser()
            }
        } message: {
            Text("You can sign back in anytime with Apple or Google.")
        }
    }

    var settingsShortcutItems: [PBShortcutItem] {
        [
            PBShortcutItem(
                id: "settings_goals",
                title: "Goals",
                systemImage: "target",
                action: { scrollAnchorTarget = .goals }
            ),
            PBShortcutItem(
                id: "settings_appearance",
                title: "Appearance",
                systemImage: "paintbrush.fill",
                action: { scrollAnchorTarget = .appearance }
            ),
            PBShortcutItem(
                id: "settings_notifications",
                title: "Notifications",
                systemImage: "bell.fill",
                action: { scrollAnchorTarget = .notifications }
            )
        ]
    }

    func syncNotificationPrefs() async {
        let anyCategoryEnabled =
            notifyDuels
            || notifyMessages
            || notifyGoals
            || notifyFriendRequests
            || notifyBuddies
        if anyCategoryEnabled {
            _ = await PBNotificationCenter.requestAuthorizationIfNeeded()
        }
        await PushTokenManager.shared.updateNotificationPreferences(
            duelsEnabled: notifyDuels,
            messagesEnabled: notifyMessages,
            goalsEnabled: notifyGoals,
            friendRequestsEnabled: notifyFriendRequests,
            studioInvitesEnabled: false,
            assignmentsEnabled: false,
            buddiesEnabled: notifyBuddies
        )
    }

    func refreshNotificationAuthorizationStatus() async {
        notificationAuthorizationStatus = await PBNotificationCenter.authorizationStatus()
    }

    func queueNotificationPrefsSync() {
        pendingNotificationSyncTask?.cancel()
        pendingNotificationSyncTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await syncNotificationPrefs()
        }
    }

    #if DEBUG
    func sendPushTestNotification() async {
        do {
            try await PushTokenManager.shared.sendTestPushNotification(route: "social_chat")
            pushTestStatus = "Test push sent. If notifications are enabled, it should arrive shortly."
        } catch {
            pushTestStatus = "Push test failed: \(error.localizedDescription)"
        }
    }
    #endif

}
