import SwiftUI
import UserNotifications

struct SettingsView: View {
    private enum SettingsAnchor: String {
        case goals
        case appearance
        case notifications
    }

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("pb.settings.historyRetention") private var historyRetention: Int = 0

    @AppStorage("pb.settings.dailyGoalMinutes") private var goalMinutes: Int = 30
    @AppStorage("pb.settings.goalScope") private var goalScopeRaw: String = GoalScope.today.rawValue
    @AppStorage("pb.notifications.assignments") private var notifyAssignments: Bool = true
    @AppStorage("pb.notifications.buddies") private var notifyBuddies: Bool = true
    @AppStorage("pb.notifications.duels") private var notifyDuels: Bool = true
    @AppStorage("pb.notifications.messages") private var notifyMessages: Bool = true
    @AppStorage("pb.notifications.goals") private var notifyGoals: Bool = true
    @AppStorage("pb.notifications.friendRequests") private var notifyFriendRequests: Bool = true
    @AppStorage("pb.notifications.studioInvites") private var notifyStudioInvites: Bool = true
    @AppStorage("pb.practice.checkins.enabled") private var practiceCheckInsEnabled: Bool = true
    @AppStorage("pb.settings.language") private var appLanguageRaw: String = AppLanguage.system.rawValue

    @State private var pendingRetentionTask: Task<Void, Never>?
    @State private var animateHeader = false
    @State private var scrollAnchorTarget: SettingsAnchor?
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    private var goalScopeBinding: Binding<GoalScope> {
        Binding(
            get: { GoalScope(rawValue: goalScopeRaw) ?? .today },
            set: { goalScopeRaw = $0.rawValue }
        )
    }

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: appLanguageRaw) ?? .system },
            set: { appLanguageRaw = $0.rawValue }
        )
    }

    private var historyRetentionDisplay: String {
        historyRetention == 0 ? "Unlimited" : "\(historyRetention)"
    }

    private var historyRetentionDisplayStyle: Color {
        historyRetention == 0 ? palette.textPrimary : palette.textSecondary
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsShortcutRow
            headerCard

            ScrollViewReader { proxy in
                Form {
                    Section("Goals") {
                    Picker("Goal period", selection: goalScopeBinding) {
                        ForEach(GoalScope.allCases) { scope in
                            Text(LocalizedStringKey(scope.title)).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $goalMinutes, in: 0...600, step: 5) {
                        HStack {
                            Text("Goal")
                                .font(type.body)
                            Spacer()
                            if goalMinutes == 0 {
                                Text("Off")
                                    .font(type.body)
                                    .foregroundStyle(palette.textSecondary)
                            } else {
                                let scope = GoalScope(rawValue: goalScopeRaw) ?? .today
                                Text(
                                    L10n.f(
                                        "%@ min / %@",
                                        "\(goalMinutes)",
                                        String(localized: String.LocalizationValue(scope.title))
                                    )
                                )
                                    .font(type.body)
                                    .foregroundStyle(palette.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                    }

                    Text(goalMinutes == 0 ? "Turn this on to track progress." : "Progress is tracked for the selected period.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    }
                    .listRowBackground(palette.surface)
                    .id(SettingsAnchor.goals)

                    Section("Appearance") {
                    NavigationLink { PBLazyView(ThemePickerView()) } label: {
                        settingsLabel("Themes", systemImage: "paintpalette")
                    }

                    NavigationLink { PBLazyView(FontPickerView()) } label: {
                        settingsLabel("Fonts", systemImage: "textformat")
                    }

                    NavigationLink { PBLazyView(AppIconPickerView()) } label: {
                        settingsLabel("App Icon", systemImage: "app.badge")
                    }

                    Picker("Language", selection: appLanguageBinding) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(LocalizedStringKey(lang.titleKey)).tag(lang)
                        }
                    }
                    }
                    .listRowBackground(palette.surface)
                    .id(SettingsAnchor.appearance)

                    Section("Tool Access") {
                    Picker("Primary focus", selection: Binding(
                        get: { purchaseManager.primaryFocus },
                        set: { purchaseManager.setPrimaryFocus($0) }
                    )) {
                        ForEach(PBPrimaryFocus.allCases) { focus in
                            Text(LocalizedStringKey(focus.title)).tag(focus)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Student Tools", isOn: Binding(
                        get: { purchaseManager.canAccessStudentTools },
                        set: { purchaseManager.setShowStudentTools($0) }
                    ))
                    .font(type.body)

                    Toggle("Teacher Tools", isOn: Binding(
                        get: { purchaseManager.canAccessTeacherTools },
                        set: { purchaseManager.setShowTeacherTools($0) }
                    ))
                    .font(type.body)

                    Text("Studio Manager is a Pro feature under Teacher Tools.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    }
                    .listRowBackground(palette.surface)

                    if isMasterAccount {
                        Section("Launch Tools") {
                            NavigationLink {
                                PBLazyView(LaunchPrepView())
                            } label: {
                                settingsLabel("Launch Prep", systemImage: "rocket")
                            }
                            Text("Master-only checklist for pre-launch reset and entitlement rollout.")
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                        .listRowBackground(palette.surface)
                    }

                    Section("Notifications") {
                    if notificationAuthorizationStatus != .authorized && notificationAuthorizationStatus != .provisional && notificationAuthorizationStatus != .ephemeral {
                        Button("Enable iOS Notifications") {
                            Task {
                                _ = await PBNotificationCenter.requestAuthorizationIfNeeded()
                                await refreshNotificationAuthorizationStatus()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Group {
                        Toggle("Duel challenges", isOn: $notifyDuels)
                            .font(type.body)
                        Toggle("Messages", isOn: $notifyMessages)
                            .font(type.body)
                        Toggle("Goal reached", isOn: $notifyGoals)
                            .font(type.body)
                        Toggle("Friend requests", isOn: $notifyFriendRequests)
                            .font(type.body)
                        Toggle("Studio invites", isOn: $notifyStudioInvites)
                            .font(type.body)
                    }

                    Toggle("Assignments", isOn: $notifyAssignments)
                        .font(type.body)
                    Toggle("Buddies", isOn: $notifyBuddies)
                        .font(type.body)

                    Text("Use iPhone Settings to control lock-screen/banner style. In-app toggles choose which categories you receive.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)

                    Button("Open iOS Notification Settings") {
                        PBNotificationCenter.openSystemNotificationSettings()
                    }
                    .buttonStyle(.bordered)
                    }
                    .listRowBackground(palette.surface)
                    .id(SettingsAnchor.notifications)

                    Section("Practice Verification") {
                    Toggle("Practice Check-ins (Gentle Mode)", isOn: $practiceCheckInsEnabled)
                        .font(type.body)

                    Text(practiceCheckInsEnabled
                         ? "During active sessions, random check-ins verify presence. Missed check-ins pause the timer."
                         : "Practice check-ins are off. All active timer minutes count as verified.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    }
                    .listRowBackground(palette.surface)

                    Section("History") {
                    NavigationLink {
                        PBLazyView(HistoryRetentionPickerView(selection: $historyRetention))
                    } label: {
                        HStack {
                            Text("Keep history")
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)

                            Spacer()

                            Text(LocalizedStringKey(historyRetentionDisplay))
                                .font(type.body)
                                .foregroundStyle(historyRetentionDisplayStyle)
                                .monospacedDigit()
                        }
                    }

                    Text(historyRetention == 0
                         ? "Your practice history is kept indefinitely."
                         : "Older sessions are automatically deleted after you exceed \(historyRetention) sessions.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    }
                    .listRowBackground(palette.surface)

                    AboutSectionView()
                        .listRowBackground(palette.surface)
                }
                .onChange(of: scrollAnchorTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.clear)
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
            await syncNotificationPrefs()
            await refreshNotificationAuthorizationStatus()
        }
        .onChange(of: notifyAssignments) { _, _ in
            Task { await syncNotificationPrefs() }
        }
        .onChange(of: notifyBuddies) { _, _ in
            Task { await syncNotificationPrefs() }
        }
        .onChange(of: notifyDuels) { _, _ in
            Task { await syncNotificationPrefs() }
        }
        .onChange(of: notifyMessages) { _, _ in
            Task { await syncNotificationPrefs() }
        }
        .onChange(of: notifyGoals) { _, _ in
            Task { await syncNotificationPrefs() }
        }
        .onChange(of: notifyFriendRequests) { _, _ in
            Task { await syncNotificationPrefs() }
        }
        .onChange(of: notifyStudioInvites) { _, _ in
            Task { await syncNotificationPrefs() }
        }
    }

    private var settingsShortcutRow: some View {
        PBShortcutBar(items: settingsShortcutItems, palette: palette)
            .padding(.horizontal, PBLayout.padSM)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .offset(y: animateHeader ? 0 : 10)
            .opacity(animateHeader ? 1 : 0)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(type.appTitle)
                .tracking(type.heroTracking)
                .foregroundStyle(palette.textPrimary)

            Text("Personalize your practice flow, notifications, and app experience.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padLG)
        .pbModernCard(palette: palette)
        .padding(.horizontal, PBLayout.padSM)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .offset(y: animateHeader ? 0 : 12)
        .opacity(animateHeader ? 1 : 0)
    }

    private var settingsShortcutItems: [PBShortcutItem] {
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

    private func syncNotificationPrefs() async {
        let anyCategoryEnabled =
            notifyDuels
            || notifyMessages
            || notifyGoals
            || notifyFriendRequests
            || notifyStudioInvites
            || notifyAssignments
            || notifyBuddies
        if anyCategoryEnabled {
            _ = await PBNotificationCenter.requestAuthorizationIfNeeded()
        }
        await PushTokenManager.shared.updateNotificationPreferences(
            duelsEnabled: notifyDuels,
            messagesEnabled: notifyMessages,
            goalsEnabled: notifyGoals,
            friendRequestsEnabled: notifyFriendRequests,
            studioInvitesEnabled: notifyStudioInvites,
            assignmentsEnabled: notifyAssignments,
            buddiesEnabled: notifyBuddies
        )
    }

    private func refreshNotificationAuthorizationStatus() async {
        notificationAuthorizationStatus = await PBNotificationCenter.authorizationStatus()
    }

    private var isMasterAccount: Bool {
        AppInfo.isMasterAccount(uid: firebase.currentUserID, email: firebase.currentUserEmail)
    }

    @ViewBuilder
    private func settingsLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(palette.accent)
            Text(LocalizedStringKey(title))
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
        }
    }
}
