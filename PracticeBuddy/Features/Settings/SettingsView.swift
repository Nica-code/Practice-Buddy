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

    @State private var pendingRetentionTask: Task<Void, Never>?

    private var goalScopeBinding: Binding<GoalScope> {
        Binding(
            get: { GoalScope(rawValue: goalScopeRaw) ?? .today },
            set: { goalScopeRaw = $0.rawValue }
        )
    }

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    private var historyRetentionDisplay: String {
        historyRetention == 0 ? "Unlimited" : "\(historyRetention)"
    }

    private var historyRetentionDisplayStyle: Color {
        historyRetention == 0 ? palette.textPrimary : palette.textSecondary
    }

    var body: some View {
        Form {
            Section("Goals") {
                Picker("Goal period", selection: goalScopeBinding) {
                    ForEach(GoalScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(value: $goalMinutes, in: 0...600, step: 5) {
                    HStack {
                        Text("Goal")
                            .font(type.body)
                        Spacer()
                        Text(goalMinutes == 0
                             ? "Off"
                             : "\(goalMinutes) min / \((GoalScope(rawValue: goalScopeRaw) ?? .today).title.lowercased())")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
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

            Section("History") {
                NavigationLink {
                    PBLazyView(HistoryRetentionPickerView(selection: $historyRetention))
                } label: {
                    HStack {
                        Text("Keep history")
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)

                        Spacer()

                        Text(historyRetentionDisplay)
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
        .background(chrome.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
            Text(title)
                .font(type.body)
                .foregroundStyle(palette.textPrimary)
        }
    }
}
