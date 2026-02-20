import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("pb.settings.historyRetention") private var historyRetention: Int = 0
    @AppStorage("pb.settings.theme") private var themeRawValue: String = AppTheme.system.rawValue

    @AppStorage("pb.settings.dailyGoalMinutes") private var goalMinutes: Int = 30
    @AppStorage("pb.settings.goalScope") private var goalScopeRaw: String = GoalScope.today.rawValue

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
                Picker(
                    "Theme",
                    selection: Binding<AppTheme>(
                        get: { AppTheme(rawValue: themeRawValue) ?? .system },
                        set: { themeRawValue = $0.rawValue }
                    )
                ) {
                    ForEach(AppTheme.allCases) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                NavigationLink { PBLazyView(ThemePickerView()) } label: {
                    Label("Themes", systemImage: "paintpalette")
                        .font(type.body)
                }

                NavigationLink { PBLazyView(FontPickerView()) } label: {
                    Label("Fonts", systemImage: "textformat")
                        .font(type.body)
                }

                NavigationLink { PBLazyView(AppIconPickerView()) } label: {
                    Label("App Icon", systemImage: "app.badge")
                        .font(type.body)
                }
            }
            .listRowBackground(palette.surface)

            Section("Store") {
                NavigationLink { PBLazyView(StoreView()) } label: {
                    Label("Coming Soon", systemImage: "bag")
                        .font(type.body)
                }

                Text("Future feature unlocks will appear here.")
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
    }
}
