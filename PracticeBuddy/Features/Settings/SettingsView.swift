import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("pb.settings.historyRetention") private var historyRetention: Int = 0

    @AppStorage("pb.settings.dailyGoalMinutes") private var goalMinutes: Int = 30
    @AppStorage("pb.settings.goalScope") private var goalScopeRaw: String = GoalScope.today.rawValue
    @AppStorage("pb.notifications.assignments") private var notifyAssignments: Bool = true
    @AppStorage("pb.notifications.buddies") private var notifyBuddies: Bool = true
    @AppStorage("pb.practice.checkins.enabled") private var practiceCheckInsEnabled: Bool = true
    @AppStorage("pb.settings.language") private var appLanguageRaw: String = AppLanguage.system.rawValue

    @State private var pendingRetentionTask: Task<Void, Never>?
    @State private var animateHeader = false

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
            headerCard

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

                Section("Store") {
                    NavigationLink { PBLazyView(StoreView()) } label: {
                        settingsLabel(
                            purchaseManager.isPro ? "Practice Buddy Pro (Unlocked)" : "Practice Buddy Pro",
                            systemImage: purchaseManager.isPro ? "sparkles" : "bag"
                        )
                    }

                    Text("One-time unlock. Includes core Pro tools plus account-type extras for Teacher or Student.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(palette.surface)

                Section("Notifications") {
                    Toggle("Assignments", isOn: $notifyAssignments)
                        .font(type.body)
                    Toggle("Buddies", isOn: $notifyBuddies)
                        .font(type.body)

                    Text("Controls push notifications for assignment and buddy activity updates.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(palette.surface)

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
            .scrollContentBackground(.hidden)
            .background(.clear)
        }
        .background {
            PBBackdropView(palette: palette)
        }
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
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
        }
        .onChange(of: notifyAssignments) { _, _ in
            Task { await syncNotificationPrefs() }
        }
        .onChange(of: notifyBuddies) { _, _ in
            Task { await syncNotificationPrefs() }
        }
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
        .padding(PBLayout.padLG)
        .pbModernCard(palette: palette)
        .padding(.horizontal, PBLayout.padSM)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .offset(y: animateHeader ? 0 : 12)
        .opacity(animateHeader ? 1 : 0)
    }

    private func syncNotificationPrefs() async {
        await PushTokenManager.shared.updateNotificationPreferences(
            assignmentsEnabled: notifyAssignments,
            buddiesEnabled: notifyBuddies
        )
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
