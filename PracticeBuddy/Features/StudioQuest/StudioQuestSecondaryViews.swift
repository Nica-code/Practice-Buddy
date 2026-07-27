import SwiftUI
import SwiftData
import StoreKit
import PhotosUI
import UserNotifications
import Combine

// MARK: - Goals and saved plans

@MainActor
private final class SavedPracticePlanStore: ObservableObject {
    @Published private(set) var plans: [PracticePreset] = []

    private let defaults = UserDefaults.standard
    private let key = "practiquest.savedPlans.v2"

    init() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PracticePreset].self, from: data) else { return }
        plans = decoded
    }

    func add(_ plan: PracticePreset, unlimited: Bool) -> Bool {
        guard unlimited || plans.count < 3 else { return false }
        plans.append(plan)
        persist()
        return true
    }

    func remove(at offsets: IndexSet) {
        plans.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        defaults.set(data, forKey: key)
    }
}

struct StudioQuestGoalsView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("pb.settings.dailyGoalMinutes") private var dailyMinutes = 30
    @AppStorage("practiquest.goals.weeklyMinutes") private var weeklyMinutes = 150
    @AppStorage("practiquest.goals.reminderEnabled") private var reminderEnabled = false
    @AppStorage("practiquest.goals.reminderHour") private var reminderHour = 18
    @AppStorage("practiquest.goals.preferredDays") private var preferredDaysRaw = "2,3,4,5,6"
    @StateObject private var savedPlans = SavedPracticePlanStore()
    @State private var planName = ""
    @State private var planMinutes = 30
    @State private var statusMessage: String?
    @State private var showPro = false

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "Goals", subtitle: "Clear targets, without streak pressure.")
                progressOverview
                goalControl(
                    title: "Daily practice",
                    value: $dailyMinutes,
                    options: [15, 20, 30, 45, 60],
                    completed: store.totalTodaySeconds / 60
                )
                goalControl(
                    title: "Weekly practice",
                    value: $weeklyMinutes,
                    options: [60, 90, 150, 210, 300],
                    completed: store.totalThisWeekSeconds / 60
                )
                practiceDays
                reminderSection
                savedPlanSection
                if let statusMessage {
                    StudioQuestInlineStatus(
                        title: statusMessage,
                        systemImage: "checkmark.circle.fill",
                        tint: StudioQuestTokens.ColorRole.mint
                    )
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .sheet(isPresented: $showPro) { NavigationStack { StudioQuestProView() } }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var progressOverview: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { goalMetrics }
            VStack(spacing: 12) { goalMetrics }
        }
    }

    @ViewBuilder
    private var goalMetrics: some View {
        goalMetric(
            value: "\(store.totalTodaySeconds / 60)m",
            title: "Today",
            progress: Double(store.totalTodaySeconds) / Double(max(1, dailyMinutes * 60)),
            color: StudioQuestTokens.ColorRole.cobalt
        )
        goalMetric(
            value: "\(store.totalThisWeekSeconds / 60)m",
            title: "This week",
            progress: Double(store.totalThisWeekSeconds) / Double(max(1, weeklyMinutes * 60)),
            color: StudioQuestTokens.ColorRole.violet
        )
    }

    private func goalMetric(value: String, title: String, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(StudioQuestTokens.Typography.measurement)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: min(max(progress, 0), 1))
                .tint(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            StudioQuestTokens.ColorRole.surface(colorScheme),
            in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface)
        )
    }

    private func goalControl(
        title: LocalizedStringKey,
        value: Binding<Int>,
        options: [Int],
        completed: Int
    ) -> some View {
        StudioQuestSection {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title).font(StudioQuestTokens.Typography.cardTitle)
                    Spacer()
                    Text("\(completed) / \(value.wrappedValue) min")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(
                    value: Double(min(max(completed, 0), max(value.wrappedValue, 1))),
                    total: Double(max(value.wrappedValue, 1))
                )
                    .tint(StudioQuestTokens.ColorRole.cobalt)
                if dynamicTypeSize.isAccessibilitySize {
                    Picker(title, selection: value) {
                        ForEach(options, id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Picker(title, selection: value) {
                        ForEach(options, id: \.self) { minutes in
                            Text("\(minutes)m").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var practiceDays: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preferred days")
                .font(StudioQuestTokens.Typography.sectionTitle)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible()),
                    count: dynamicTypeSize.isAccessibilitySize ? 4 : 7
                ),
                spacing: 7
            ) {
                ForEach(2...8, id: \.self) { weekday in
                    let selected = preferredDays.contains(weekday)
                    Button {
                        var next = preferredDays
                        if selected { next.remove(weekday) } else { next.insert(weekday) }
                        preferredDaysRaw = next.sorted().map(String.init).joined(separator: ",")
                    } label: {
                        Text(dayTitle(weekday))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(
                                selected ? StudioQuestTokens.ColorRole.cobalt : StudioQuestTokens.ColorRole.surface(colorScheme),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dayAccessibilityTitle(weekday))
                    .accessibilityValue(selected ? "Selected" : "Not selected")
                }
            }
        }
    }

    private var preferredDays: Set<Int> {
        Set(preferredDaysRaw.split(separator: ",").compactMap { Int($0) })
    }

    private func dayTitle(_ weekday: Int) -> String {
        let index = (weekday - 1) % 7
        return Calendar.current.veryShortWeekdaySymbols[index]
    }

    private func dayAccessibilityTitle(_ weekday: Int) -> String {
        let index = (weekday - 1) % 7
        return Calendar.current.weekdaySymbols[index]
    }

    private var reminderSection: some View {
        StudioQuestSection {
            VStack(spacing: 14) {
                Toggle("Practice reminder", isOn: $reminderEnabled)
                    .tint(StudioQuestTokens.ColorRole.cobalt)
                if reminderEnabled {
                    Stepper("At \(reminderHour.formatted(.number.precision(.integerLength(2)))):00", value: $reminderHour, in: 6...22)
                        .font(.subheadline)
                }
            }
        }
        .onChange(of: reminderEnabled) { _, _ in scheduleReminder() }
        .onChange(of: reminderHour) { _, _ in scheduleReminder() }
    }

    private var savedPlanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved plans")
                    .font(StudioQuestTokens.Typography.sectionTitle)
                Spacer()
                if !purchaseManager.isPro {
                    Button("Pro") { showPro = true }
                        .font(.caption.weight(.bold))
                }
            }

            StudioQuestSection {
                VStack(spacing: 12) {
                    TextField("Plan name", text: $planName)
                        .textFieldStyle(.plain)
                    Stepper("\(planMinutes) minutes", value: $planMinutes, in: 5...120, step: 5)
                    Button("Save this plan") {
                        let name = planName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else {
                            statusMessage = "Give the plan a name first."
                            return
                        }
                        let plan = PracticePreset(
                            piece: "",
                            task: name,
                            durationMinutes: planMinutes,
                            verified: true,
                            launchContext: PracticeLaunchContext(source: "saved_plan", questID: nil)
                        )
                        if savedPlans.add(plan, unlimited: purchaseManager.isPro) {
                            planName = ""
                            statusMessage = "Plan saved."
                        } else {
                            showPro = true
                        }
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                }
            }

            ForEach(Array(savedPlans.plans.enumerated()), id: \.offset) { index, plan in
                NavigationLink(value: AppRoute.practiceSetup(preset: plan)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.task).font(.headline)
                            Text("\(plan.durationMinutes) min · \(plan.verified ? "Verified" : "Standard")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                    }
                    .foregroundStyle(.primary)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        savedPlans.remove(at: IndexSet(integer: index))
                    }
                }
            }
        }
    }

    private func scheduleReminder() {
        let identifier = "practiquest.daily.practice.reminder"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard reminderEnabled else { return }
        Task {
            let granted = await PBNotificationCenter.requestAuthorizationIfNeeded()
            guard granted else {
                await MainActor.run { statusMessage = "Allow notifications in Settings to use reminders." }
                return
            }
            var date = DateComponents()
            date.hour = reminderHour
            let content = UNMutableNotificationContent()
            content.title = "Your practice space is ready"
            content.body = "A focused session is one tap away."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            )
            try? await center.add(request)
        }
    }
}

// MARK: - History

struct StudioQuestHistoryView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "Week"
        case month = "Month"
        case all = "All"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: [SortDescriptor(\LoopPracticeLogModel.date, order: .reverse)]) private var loopLogs: [LoopPracticeLogModel]
    @Query(sort: [SortDescriptor(\PracticePlanLogModel.date, order: .reverse)]) private var planLogs: [PracticePlanLogModel]
    @Query(sort: [SortDescriptor(\RhythmAccuracyTakeModel.date, order: .reverse)]) private var rhythmTakes: [RhythmAccuracyTakeModel]
    @Query(sort: [SortDescriptor(\ScaleIntonationTakeModel.date, order: .reverse)]) private var intonationTakes: [ScaleIntonationTakeModel]
    @Query(sort: [SortDescriptor(\RunThroughModel.date, order: .reverse)]) private var runThroughs: [RunThroughModel]
    @State private var scope: Scope = .week
    @State private var searchText = ""
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var showExportOptions = false
    @State private var showPro = false
    @State private var statusMessage: String?

    var body: some View {
        StudioQuestScrollPage(showsIndicators: true) {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                header
                historyRangePicker
                searchField
                insightMetrics
                weekChart
                skillSummary
                sessionTimeline
                if let statusMessage {
                    StudioQuestInlineStatus(
                        title: statusMessage,
                        systemImage: "exclamationmark.circle",
                        tint: StudioQuestTokens.ColorRole.coral
                    )
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .confirmationDialog("Export history", isPresented: $showExportOptions, titleVisibility: .visible) {
            Button("CSV") { export(.csv) }
            Button("JSON") { export(.json) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showShare) {
            if let exportURL {
                ActivityView(activityItems: [exportURL])
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showPro) { NavigationStack { StudioQuestProView() } }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var historyRangePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("History range", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        } else {
            Picker("History range", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                StudioQuestPageTitle(title: "History", subtitle: "Your practice, in context.")
                Spacer()
                exportButton
            }
            VStack(alignment: .leading, spacing: 12) {
                StudioQuestPageTitle(title: "History", subtitle: "Your practice, in context.")
                exportButton
            }
        }
    }

    private var exportButton: some View {
        Button {
            if purchaseManager.isPro { showExportOptions = true } else { showPro = true }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search titles, focus, or notes", text: $searchText)
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { searchText = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            StudioQuestTokens.ColorRole.surface(colorScheme),
            in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control)
        )
    }

    private var filteredSessions: [PracticeSessionModel] {
        store.sessions.filter { session in
            guard isInScope(session.date) else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return [session.noteTitle, session.noteFocus, session.notes]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(query)
        }
    }

    private func isInScope(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch scope {
        case .all: return true
        case .today: return calendar.isDateInToday(date)
        case .week: return calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
        case .month: return calendar.isDate(date, equalTo: Date(), toGranularity: .month)
        }
    }

    private var totalSeconds: Int { filteredSessions.reduce(0) { $0 + max(0, $1.durationSeconds) } }
    private var averageSeconds: Int { filteredSessions.isEmpty ? 0 : totalSeconds / filteredSessions.count }
    private var verifiedRatio: Int {
        guard totalSeconds > 0 else { return 0 }
        let verified = filteredSessions.reduce(0) { $0 + max(0, $1.verifiedSeconds) }
        return Int((Double(verified) / Double(totalSeconds) * 100).rounded())
    }

    private var insightMetrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { historyMetrics }
            VStack(alignment: .leading, spacing: 10) { historyMetrics }
        }
    }

    @ViewBuilder
    private var historyMetrics: some View {
        historyMetric("Total", DurationFormatter.string(from: totalSeconds))
        historyMetric("Average", DurationFormatter.string(from: averageSeconds))
        historyMetric("Verified", "\(verifiedRatio)%")
    }

    private func historyMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seven-day rhythm")
                .font(StudioQuestTokens.Typography.sectionTitle)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(weekDates, id: \.self) { date in
                    let seconds = store.totalSeconds(onDayContaining: date)
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(seconds > 0 ? StudioQuestTokens.ColorRole.cobalt : StudioQuestTokens.ColorRole.separator(colorScheme))
                            .frame(height: max(8, min(CGFloat(seconds) / 60, 72)))
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(DurationFormatter.string(from: seconds))
                }
            }
            .frame(height: 98, alignment: .bottom)
        }
    }

    private var weekDates: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0 - 6, to: Date()) }
    }

    private var skillSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Practice Library activity")
                .font(StudioQuestTokens.Typography.sectionTitle)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible()),
                    count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
                ),
                spacing: 10
            ) {
                skillMetric("Smart Loops", loopLogs.count, "repeat")
                skillMetric("Guided plans", planLogs.count, "list.bullet.clipboard")
                skillMetric("Rhythm takes", rhythmTakes.count, "metronome")
                skillMetric("Intonation", intonationTakes.count, "tuningfork")
                skillMetric("Run-throughs", runThroughs.count, "waveform")
            }
        }
    }

    private func skillMetric(_ title: String, _ count: Int, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)").font(.headline.monospacedDigit())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            StudioQuestTokens.ColorRole.surface(colorScheme),
            in: RoundedRectangle(cornerRadius: 15)
        )
    }

    private var sessionTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session timeline")
                    .font(StudioQuestTokens.Typography.sectionTitle)
                Spacer()
                Text("\(filteredSessions.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if filteredSessions.isEmpty {
                StudioQuestRowSurface {
                    ContentUnavailableView(
                        "No matching sessions",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Adjust the range or finish a practice session.")
                    )
                }
            } else {
                ForEach(filteredSessions) { session in
                    NavigationLink(value: AppRoute.sessionDetail(sessionID: session.id)) {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sessionRow(_ session: PracticeSessionModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(session.verifiedSeconds > 0 ? StudioQuestTokens.ColorRole.mint : StudioQuestTokens.ColorRole.cobalt)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.noteTitle.isEmpty ? "Practice session" : session.noteTitle)
                    .font(.headline)
                Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(DurationFormatter.string(from: session.durationSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !session.noteFocus.isEmpty {
                    Text(session.noteFocus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(14)
        .background(
            StudioQuestTokens.ColorRole.surface(colorScheme),
            in: RoundedRectangle(cornerRadius: 17)
        )
        .contentShape(RoundedRectangle(cornerRadius: 17))
    }

    private func export(_ format: SessionExportService.ExportFormat) {
        do {
            exportURL = try SessionExportService.export(sessions: filteredSessions, format: format)
            showShare = true
        } catch {
            statusMessage = "The export could not be created. Please try again."
        }
    }
}

struct StudioQuestSessionDetailView: View {
    let sessionID: UUID

    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var notes = ""
    @State private var showDelete = false
    @State private var saved = false

    private var session: PracticeSessionModel? {
        store.sessions.first(where: { $0.id == sessionID })
    }

    var body: some View {
        StudioQuestScrollPage {
            if let session {
                VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                    StudioQuestPageTitle(
                        title: LocalizedStringKey(session.noteTitle.isEmpty ? "Practice session" : session.noteTitle),
                        subtitle: LocalizedStringKey(session.date.formatted(date: .complete, time: .shortened))
                    )
                    HStack(spacing: 10) {
                        detailMetric("Duration", DurationFormatter.string(from: session.durationSeconds))
                        detailMetric("Verified", DurationFormatter.string(from: session.verifiedSeconds))
                        detailMetric("Check-ins", "\(session.checkInCount)")
                    }
                    if !session.noteFocus.isEmpty {
                        StudioQuestInlineStatus(
                            title: session.noteFocus,
                            systemImage: "scope",
                            tint: StudioQuestTokens.ColorRole.cobalt
                        )
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").font(StudioQuestTokens.Typography.sectionTitle)
                        TextEditor(text: $notes)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .padding(10)
                            .background(
                                StudioQuestTokens.ColorRole.surface(colorScheme),
                                in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface)
                            )
                    }
                    Button(saved ? "Notes saved" : "Save notes") {
                        store.updateNotes(for: sessionID, notes: notes)
                        saved = true
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    Button("Delete session", role: .destructive) { showDelete = true }
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, StudioQuestTokens.Spacing.lg)
            } else {
                ContentUnavailableView("Session unavailable", systemImage: "exclamationmark.circle")
            }
        }
        .onAppear { notes = session?.notes ?? "" }
        .confirmationDialog("Delete this session?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deleteSessions(withIDs: [sessionID])
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the session from your history and progress totals.")
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Profile

struct StudioQuestProfileView: View {
    let userID: String?

    @EnvironmentObject private var buddies: BuddiesViewModel
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var photoManager = ProfilePhotoManager()
    @State private var displayName = ""
    @State private var bio = ""
    @State private var instrument = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var localPhotoURL: String?
    @State private var statusMessage: String?
    @State private var isSaving = false

    init(userID: String? = nil) {
        self.userID = userID
    }

    var body: some View {
        if let userID, userID != firebase.currentUserID {
            StudioQuestPublicProfileView(userID: userID)
        } else {
            ownProfile
        }
    }

    private var ownProfile: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "Profile", subtitle: "How other musicians see you.")
                identityEditor
                profileFields
                publicPreview
                if let code = buddies.myProfile?.friendCode, !code.isEmpty {
                    if let inviteURL = AppInfo.buddyInviteURL(friendCode: code) {
                        ShareLink(
                            item: inviteURL,
                            subject: Text("Practice with me on PractiQuest"),
                            message: Text("Use my private friend invite to connect with me on PractiQuest.")
                        ) {
                            StudioQuestRowSurface {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Friend code").font(.caption).foregroundStyle(.secondary)
                                        Text(code).font(.headline.monospaced())
                                    }
                                    Spacer()
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Share friend invite \(code)")
                    }
                }
                if let statusMessage {
                    StudioQuestInlineStatus(
                        title: statusMessage,
                        systemImage: statusMessage == "Profile saved." ? "checkmark.circle.fill" : "exclamationmark.circle",
                        tint: statusMessage == "Profile saved." ? StudioQuestTokens.ColorRole.mint : StudioQuestTokens.ColorRole.coral
                    )
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .onAppear { loadProfile() }
        .onChange(of: buddies.myProfile) { _, _ in loadProfile() }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var identityEditor: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { avatarEditor; identityText }
            VStack(alignment: .leading, spacing: 16) { avatarEditor; identityText }
        }
    }

    private var avatarEditor: some View {
        ZStack(alignment: .bottomTrailing) {
            PBAvatarView(
                avatarID: buddies.myProfile?.avatarID ?? "avatar_note",
                displayName: displayName.isEmpty ? "Your studio" : displayName,
                profilePhotoURL: localPhotoURL,
                size: 88
            )
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(StudioQuestTokens.ColorRole.cobalt, in: Circle())
            }
            .accessibilityLabel("Choose profile photo")
        }
        .overlay {
            if photoManager.isUploading {
                ProgressView()
                    .frame(width: 88, height: 88)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(displayName.isEmpty ? "Your studio" : displayName)
                .font(.title2.weight(.bold))
            Text(firebase.isAnonymousUser ? "Guest profile" : "Public musician profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if localPhotoURL?.isEmpty == false {
                Button("Remove photo", role: .destructive) {
                    Task { await removePhoto() }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private var profileFields: some View {
        StudioQuestSection {
            VStack(alignment: .leading, spacing: 16) {
                profileField("Display name", text: $displayName)
                profileField("Instrument", text: $instrument)
                profileField("Bio", text: $bio, axis: .vertical)
                Button(isSaving ? "Saving…" : "Save profile") {
                    Task { await saveProfile() }
                }
                .buttonStyle(StudioQuestPrimaryButtonStyle())
                .disabled(isSaving)
            }
        }
    }

    private var publicPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Public preview")
                .font(StudioQuestTokens.Typography.sectionTitle)
            HStack(spacing: 13) {
                PBAvatarView(
                    avatarID: buddies.myProfile?.avatarID ?? "avatar_note",
                    displayName: displayName,
                    profilePhotoURL: localPhotoURL,
                    size: 58
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName.isEmpty ? "Your studio" : displayName).font(.headline)
                    Text(instrument.isEmpty ? "Musician" : instrument).font(.subheadline).foregroundStyle(.secondary)
                    if !bio.isEmpty { Text(bio).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer()
            }
            .padding(14)
            .background(
                StudioQuestTokens.ColorRole.surface(colorScheme),
                in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface)
            )
        }
    }

    private func profileField(_ title: LocalizedStringKey, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField(title, text: text, axis: axis)
                .textFieldStyle(.plain)
                .padding(12)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func loadProfile() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--qa-populated"),
           buddies.myProfile == nil {
            if displayName.isEmpty { displayName = "Ari Morgan" }
            if instrument.isEmpty { instrument = "Violin" }
            if bio.isEmpty { bio = "Building expressive, consistent practice one focused session at a time." }
        }
        #endif
        displayName = buddies.myProfile?.displayName ?? displayName
        bio = buddies.myProfile?.bio ?? bio
        instrument = buddies.myProfile?.instrument ?? instrument
        localPhotoURL = buddies.myProfile?.profilePhotoURL
    }

    private func upload(_ item: PhotosPickerItem) async {
        guard let uid = firebase.currentUserID,
              let data = try? await item.loadTransferable(type: Data.self) else {
            statusMessage = "That image could not be read."
            return
        }
        if let url = await photoManager.uploadProfilePhoto(uid: uid, imageData: data) {
            localPhotoURL = url
            await buddies.updateProfile(
                avatarID: buddies.myProfile?.avatarID ?? "avatar_note",
                profilePhotoURL: url,
                bio: bio,
                instrument: instrument
            )
            statusMessage = "Profile photo updated."
        } else {
            statusMessage = "The photo could not be uploaded."
        }
    }

    private func removePhoto() async {
        guard let uid = firebase.currentUserID else { return }
        await photoManager.deleteProfilePhoto(uid: uid)
        localPhotoURL = ""
        await buddies.updateProfile(
            avatarID: buddies.myProfile?.avatarID ?? "avatar_note",
            profilePhotoURL: "",
            bio: bio,
            instrument: instrument
        )
    }

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty, normalized != buddies.myProfile?.displayName {
            await buddies.saveDisplayName(normalized)
        }
        await buddies.updateProfile(
            avatarID: buddies.myProfile?.avatarID ?? "avatar_note",
            profilePhotoURL: localPhotoURL,
            bio: bio,
            instrument: instrument
        )
        statusMessage = buddies.statusMessage == "Profile updated." ? "Profile saved." : (buddies.statusMessage ?? "Profile saved.")
    }
}

// MARK: - Settings, support, and Pro

struct StudioQuestAchievementsView: View {
    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var store: SessionStore
    @Environment(\.colorScheme) private var colorScheme

    private var achievements: [(title: String, detail: String, isUnlocked: Bool, image: String)] {
        [
            ("First session", "Complete one saved practice session.", !store.sessions.isEmpty, "play.circle.fill"),
            ("Verified focus", "Record verified practice time.", store.sessions.contains { $0.verifiedSeconds > 0 }, "checkmark.shield.fill"),
            ("Quest climber", "Reach level 2 in your Journey.", journey.level >= 2, "mountain.2.fill"),
            ("Studio collector", "Unlock a room decoration.", journey.ownedRoomDecorationIDs.count > 1, "lamp.floor.fill")
        ]
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "Achievements", subtitle: "Quiet proof of the practice you keep showing up for.")
                StudioQuestSection {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Level \(journey.level)").font(StudioQuestTokens.Typography.sectionTitle)
                            Text("\(journey.xpToNextLevel) XP to your next milestone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "medal.fill")
                            .font(.title2)
                            .foregroundStyle(StudioQuestTokens.ColorRole.gold)
                    }
                }
                ForEach(achievements.indices, id: \.self) { index in
                    let achievement = achievements[index]
                    StudioQuestRowSurface {
                        HStack(spacing: 12) {
                            Image(systemName: achievement.image)
                                .font(.title3)
                                .foregroundStyle(achievement.isUnlocked ? StudioQuestTokens.ColorRole.gold : .secondary)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(achievement.title).font(.headline)
                                Text(achievement.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: achievement.isUnlocked ? "checkmark.seal.fill" : "lock.fill")
                                .foregroundStyle(achievement.isUnlocked ? StudioQuestTokens.ColorRole.mint : .secondary)
                        }
                    }
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StudioQuestSettingsView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var identity: IdentityUpgradeCoordinator
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("practiquest.appearance") private var appearance = "system"
    @AppStorage("practiquest.community.shareActivity") private var shareFriendActivity = true
    @AppStorage("pb.settings.historyRetention") private var historyRetention = 0
    @AppStorage("pb.settings.language") private var appLanguageRaw = AppLanguage.system.rawValue
    @AppStorage(PBNotificationPreferenceKey.messages) private var notifyMessages = true
    @AppStorage(PBNotificationPreferenceKey.friendRequests) private var notifyFriendRequests = true
    @AppStorage(PBNotificationPreferenceKey.duels) private var notifyDuels = true
    @AppStorage(PBNotificationPreferenceKey.goals) private var notifyGoals = true
    @AppStorage(PBNotificationPreferenceKey.buddies) private var notifyBuddies = true
    @AppStorage("pb.onboarding.tutorial.forceReplayToken") private var tutorialReplayToken = 0
    @AppStorage("practiquest.rewards.sound") private var rewardSoundEnabled = true
    @AppStorage("practiquest.haptics.enabled") private var hapticsEnabled = true
    @State private var socialPrivacy = ProfilePrivacy.default
    @State private var signInPresented = false
    @State private var signOutPresented = false
    @State private var deleteConfirmationPresented = false
    @State private var accountStatus: String?

    let initialSection: StudioQuestSettingsSection?

    init(initialSection: StudioQuestSettingsSection? = nil) {
        self.initialSection = initialSection
    }

    var body: some View {
        ScrollViewReader { reader in
            StudioQuestScrollPage {
                VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                    StudioQuestPageTitle(title: "Settings", subtitle: "One brand system, tuned to you.")
                    appearanceSection
                    languageSection
                    notificationsSection
                    privacySection
                    dataSection
                    proSection
                    supportSection
                    accountSection
                    if let accountStatus {
                        StudioQuestInlineStatus(
                            title: accountStatus,
                            systemImage: "exclamationmark.circle",
                            tint: StudioQuestTokens.ColorRole.coral
                        )
                    }
                }
                .padding(.top, StudioQuestTokens.Spacing.lg)
            }
            .task {
                guard let initialSection else { return }
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation { reader.scrollTo(initialSection, anchor: .top) }
            }
        }
        .sheet(isPresented: $signInPresented) { AccountSetupView() }
        .confirmationDialog("Sign out of PractiQuest?", isPresented: $signOutPresented, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                if !firebase.signOutCurrentUser() {
                    accountStatus = "We could not sign you out. Please try again."
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete your PractiQuest account?", isPresented: $deleteConfirmationPresented, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task {
                    if !firebase.isAnonymousUser {
                        let success = await firebase.deleteCurrentAccount()
                        if !success { accountStatus = "The account could not be deleted. Please try again or contact support." }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the account and cannot be undone.")
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let privacy = identity.profile?.privacy { socialPrivacy = privacy }
        }
    }

    private var appearanceSection: some View {
        settingsSection("Appearance", systemImage: "circle.lefthalf.filled") {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
        }
        .id(StudioQuestSettingsSection.appearance)
    }

    private var languageSection: some View {
        settingsSection("Language", systemImage: "globe") {
            Picker("Language", selection: $appLanguageRaw) {
                ForEach(AppLanguage.allCases) { language in
                    Text(LocalizedStringKey(language.titleKey)).tag(language.rawValue)
                }
            }
            .pickerStyle(.menu)
        }
        .id(StudioQuestSettingsSection.language)
    }

    private var notificationsSection: some View {
        settingsSection("Notifications", systemImage: "bell") {
            VStack(spacing: 12) {
                Toggle("Messages", isOn: $notifyMessages)
                Toggle("Friend requests", isOn: $notifyFriendRequests)
                Toggle("Duels", isOn: $notifyDuels)
                Toggle("Goal reminders", isOn: $notifyGoals)
                Toggle("Friend activity", isOn: $notifyBuddies)
                Button("Open system notification settings") {
                    PBNotificationCenter.openSystemNotificationSettings()
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(StudioQuestTokens.ColorRole.cobalt)
        }
        .id(StudioQuestSettingsSection.notifications)
        .onChange(of: notificationFingerprint) { _, _ in syncNotificationPreferences() }
    }

    private var notificationFingerprint: String {
        "\(notifyMessages)|\(notifyFriendRequests)|\(notifyDuels)|\(notifyGoals)|\(notifyBuddies)"
    }

    private var privacySection: some View {
        settingsSection("Privacy", systemImage: "hand.raised") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $shareFriendActivity) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Share friend activity")
                        Text("Shares only online status and the date you last practiced.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle("Private profile", isOn: $socialPrivacy.isPrivate)
                Toggle("Show instrument", isOn: $socialPrivacy.showInstrument)
                Toggle("Show bio", isOn: $socialPrivacy.showBio)
                Toggle("Show practice totals", isOn: $socialPrivacy.showPracticeTotals)
                Toggle("Allow Moments for followers", isOn: $socialPrivacy.showMomentsToFollowers)
            }
            .tint(StudioQuestTokens.ColorRole.mint)
        }
        .id(StudioQuestSettingsSection.privacy)
        .onChange(of: socialPrivacy) { _, privacy in
            guard !firebase.isAnonymousUser else { return }
            Task { _ = await identity.updatePrivacy(privacy) }
        }
    }

    private var dataSection: some View {
        settingsSection("Practice data", systemImage: "externaldrive") {
            VStack(spacing: 12) {
                Picker("History retention", selection: $historyRetention) {
                    Text("Unlimited").tag(0)
                    Text("30 sessions").tag(30)
                    Text("90 sessions").tag(90)
                    Text("180 sessions").tag(180)
                    Text("365 sessions").tag(365)
                }
                .pickerStyle(.menu)
                Button("Replay the app tour") {
                    tutorialReplayToken = Int(Date().timeIntervalSince1970)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                Toggle("Reward sounds", isOn: $rewardSoundEnabled)
                Toggle("Haptics", isOn: $hapticsEnabled)
            }
        }
        .id(StudioQuestSettingsSection.history)
        .onChange(of: historyRetention) { _, _ in store.retentionChanged() }
    }

    private var proSection: some View {
        settingsSection("PractiQuest Pro", systemImage: "sparkles") {
            NavigationLink {
                StudioQuestProView()
            } label: {
                settingsRow("Plans, insights, export, and premium collections", systemImage: "crown.fill")
            }
        }
        .id(StudioQuestSettingsSection.pro)
    }

    private var supportSection: some View {
        settingsSection("Support", systemImage: "questionmark.circle") {
            VStack(spacing: 0) {
                NavigationLink { StudioQuestHelpView() } label: {
                    settingsRow("Help", systemImage: "lifepreserver")
                }
                Divider().padding(.vertical, 8)
                NavigationLink { StudioQuestAboutView() } label: {
                    settingsRow("About PractiQuest", systemImage: "info.circle")
                }
                Divider().padding(.vertical, 8)
                Button("Privacy policy") {
                    openURL(URL(string: "https://alexmalaimare.com/privacy")!)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Terms of use") {
                    openURL(URL(string: "https://alexmalaimare.com/terms")!)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var accountSection: some View {
        settingsSection("Account", systemImage: "person.crop.circle") {
            Group {
                if firebase.isAnonymousUser {
                    Button("Secure and back up this account") { signInPresented = true }
                        .buttonStyle(StudioQuestPrimaryButtonStyle())
                } else {
                    VStack(spacing: 12) {
                        Button("Sign out") { signOutPresented = true }
                            .buttonStyle(StudioQuestSecondaryButtonStyle())
                        Button("Delete account", role: .destructive) { deleteConfirmationPresented = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .id(StudioQuestSettingsSection.account)
    }

    private func settingsSection<Content: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(StudioQuestTokens.Typography.sectionTitle)
                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            StudioQuestSection { content() }
        }
    }

    private func settingsRow(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func syncNotificationPreferences() {
        Task {
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
    }
}

struct StudioQuestProView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var buddies: BuddiesViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("practiquest.avatar.loadout") private var loadoutData = Data()
    @State private var isWorking = false

    private var product: Product? {
        purchaseManager.availableProducts.first(where: { $0.id == PurchaseManager.proMonthlyProductID })
            ?? purchaseManager.availableProducts.first(where: { PurchaseManager.adFreeSubscriptionProductIDs.contains($0.id) })
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "PractiQuest Pro", subtitle: "More depth. The same focused practice.")
                proHero
                StudioQuestSection {
                    VStack(alignment: .leading, spacing: 14) {
                        proFeature("Advanced insights and trends", "chart.xyaxis.line")
                        proFeature("CSV and JSON export", "square.and.arrow.up")
                        proFeature("Unlimited plans and tool presets", "slider.horizontal.3")
                        proFeature("Premium avatar and studio collections", "sparkles")
                        proFeature("Monthly cosmetic token allowance", "sparkles.rectangle.stack")
                    }
                }
                if let ends = purchaseManager.trialEndsAt, ends > Date() {
                    StudioQuestInlineStatus(
                        title: "Your Pro trial is active until \(ends.formatted(date: .abbreviated, time: .omitted)).",
                        systemImage: "checkmark.seal.fill",
                        tint: StudioQuestTokens.ColorRole.mint
                    )
                }
                Button(primaryTitle) {
                    Task {
                        isWorking = true
                        defer { isWorking = false }
                        if !purchaseManager.trialUsed, !purchaseManager.hasAdFree {
                            if await purchaseManager.startServerTrialIfEligible() { return }
                        }
                        if let product { await purchaseManager.buy(productID: product.id) }
                    }
                }
                .buttonStyle(StudioQuestPrimaryButtonStyle())
                .disabled(purchaseManager.hasAdFree || isWorking || (product == nil && purchaseManager.trialUsed))
                Button("Restore purchases") {
                    Task {
                        isWorking = true
                        await purchaseManager.restore()
                        isWorking = false
                    }
                }
                .buttonStyle(StudioQuestSecondaryButtonStyle())
                if let status = purchaseManager.syncStatus, !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Text("Existing Ad-Free subscribers and Pro Lifetime customers are automatically recognized as Pro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .task {
            if purchaseManager.availableProducts.isEmpty { await purchaseManager.loadProducts() }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var proHero: some View {
        ZStack(alignment: .bottomLeading) {
            StudioQuestAvatarScene(
                loadout: loadout,
                layout: loadout.layout(),
                displayName: buddies.myProfile?.displayName ?? "Your musician"
            )
            .frame(height: 190)
            LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Label("Studio Quest collection", systemImage: "crown.fill")
                    .font(.headline)
                Text("Premium identity, not pay-to-win progression.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var loadout: AvatarLoadout {
        (try? JSONDecoder().decode(AvatarLoadout.self, from: loadoutData))
            ?? .starter(for: buddies.myProfile?.avatarID)
    }

    private var primaryTitle: String {
        if purchaseManager.hasAdFree { return "Pro is active" }
        if !purchaseManager.trialUsed { return "Start free trial" }
        return product.map { "Join Pro · \($0.displayPrice)" } ?? "Pro unavailable"
    }

    private func proFeature(_ title: LocalizedStringKey, _ systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
    }
}

struct StudioQuestHelpView: View {
    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "Help", subtitle: "Get back to making music quickly.")
                helpSection("Start and finish practice", icon: "play.fill", body: "Use the Practice Dock from any tab. Quick Start uses your last setup; Set up a session lets you build tasks, verification, and check-ins. Finish opens a short reflection before anything is saved.")
                helpSection("Verified practice", icon: "checkmark.shield.fill", body: "Configure Screen Time protection in session setup. Verified time is counted while protection is active; background and unprotected time remain visible as unverified.")
                helpSection("Tools and Library", icon: "square.grid.2x2", body: "Metronome and tuner stay available during a session. Smart Loop, Warm-up, guided plans, rhythm, intonation, and run-through tools are all in the searchable Practice Library.")
                helpSection("Community and duels", icon: "person.2", body: "Sign in when you want friends, messages, requests, cloud inventory, or fair asynchronous duels. Core practice remains available as a guest.")
                helpSection("Privacy", icon: "hand.raised", body: "Friend activity shares only a coarse online state and last-practiced date. Notes, pieces, audio, duration, and messages are never included.")
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpSection(_ title: LocalizedStringKey, icon: String, body: LocalizedStringKey) -> some View {
        StudioQuestSection {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StudioQuestAboutView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var buddies: BuddiesViewModel
    @AppStorage("practiquest.avatar.loadout") private var loadoutData = Data()

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "About PractiQuest", subtitle: "A focused practice world for musicians.")
                StudioQuestAvatarScene(
                    loadout: loadout,
                    layout: loadout.layout(),
                    displayName: buddies.myProfile?.displayName ?? "Your musician"
                )
                StudioQuestSection {
                    VStack(spacing: 14) {
                        LabeledContent("Version", value: version)
                        Divider()
                        Button("Email support") {
                            openURL(URL(string: "mailto:contact@alexmalaimare.com")!)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Visit website") {
                            openURL(URL(string: "https://alexmalaimare.com")!)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("Practice capability, verification, fair duels, messaging, and core progression remain free.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var loadout: AvatarLoadout {
        (try? JSONDecoder().decode(AvatarLoadout.self, from: loadoutData))
            ?? .starter(for: buddies.myProfile?.avatarID)
    }
}

// MARK: - Notifications

struct StudioQuestNotificationsView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var duelLeague: DuelLeagueManager
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var notifications = PBNotificationStore.shared

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                HStack(alignment: .top) {
                    StudioQuestPageTitle(title: "Notifications", subtitle: "Requests and updates that need your attention.")
                    Spacer()
                    if !notifications.items.isEmpty {
                        Button("Read all") { notifications.markAllRead() }
                            .font(.caption.weight(.semibold))
                    }
                }
                if notifications.items.isEmpty {
                    StudioQuestRowSurface {
                        ContentUnavailableView(
                            "All caught up",
                            systemImage: "bell.slash",
                            description: Text("Duel invitations, messages, and friend requests appear here.")
                        )
                    }
                } else {
                    ForEach(notifications.items) { notification in
                        notificationRow(notification)
                    }
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .onAppear { notifications.markAllRead() }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func notificationRow(_ notification: PBInAppNotification) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                open(notification)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: notificationIcon(notification.kind))
                        .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                        .frame(width: 38, height: 38)
                        .background(StudioQuestTokens.ColorRole.cobalt.opacity(0.10), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(notification.title).font(.headline)
                        Text(notification.message).font(.subheadline).foregroundStyle(.secondary)
                        Text(notification.createdAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if notification.kind == .duelInvite,
               let id = notification.challengeID,
               duelLeague.incomingInvites.contains(where: { $0.id == id }) {
                HStack {
                    Button("Decline") {
                        Task {
                            await duelLeague.declineInvite(challengeID: id)
                            notifications.remove(id: notification.id)
                        }
                    }
                    .buttonStyle(.bordered)
                    Button("Accept") {
                        Task {
                            await duelLeague.acceptInvite(challengeID: id)
                            notifications.remove(id: notification.id)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioQuestTokens.ColorRole.cobalt)
                }
            }
        }
        .padding(14)
        .background(
            StudioQuestTokens.ColorRole.surface(colorScheme),
            in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface)
        )
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive) {
                notifications.remove(id: notification.id)
            }
        }
    }

    private func notificationIcon(_ kind: PBInAppNotification.Kind) -> String {
        switch kind {
        case .duelInvite: "figure.fencing"
        case .friendRequest: "person.badge.plus"
        case .chatMessage: "message.fill"
        }
    }

    private func open(_ notification: PBInAppNotification) {
        notifications.markRead(id: notification.id)
        switch notification.kind {
        case .duelInvite:
            router.navigate(to: .duelArena(challengeID: notification.challengeID), in: .quest)
        case .friendRequest:
            router.navigate(to: .communityRequests, in: .community)
        case .chatMessage:
            router.navigate(
                to: .communityMessages(friendUID: notification.friendUID, threadID: notification.threadID),
                in: .community
            )
        }
    }
}

// MARK: - Duel Arena

struct StudioQuestDuelArenaView: View {
    private enum ArenaSection: String, CaseIterable, Identifiable {
        case arena = "Arena"
        case leaderboard = "Leaderboard"
        case history = "History"
        var id: String { rawValue }
    }

    let challengeID: String?

    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var duel: DuelLeagueManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var section: ArenaSection = .arena
    @State private var selectedChallenge: DuelChallenge?
    @State private var recordingChallenge: DuelChallenge?
    @State private var leaderboardScope: DuelLeaderboardScope = .friends
    @State private var showSignIn = false

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "Duel Arena", subtitle: "Focused matches. Fair progression.")
                leagueHeader
                Picker("Arena section", selection: $section) {
                    ForEach(ArenaSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch section {
                case .arena: arenaContent
                case .leaderboard: leaderboardContent
                case .history: historyContent
                }
                if let message = duel.statusMessage, !message.isEmpty {
                    StudioQuestInlineStatus(
                        title: message,
                        systemImage: "info.circle",
                        tint: StudioQuestTokens.ColorRole.cobalt
                    )
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .sheet(isPresented: $showSignIn) { AccountSetupView() }
        .sheet(item: $selectedChallenge) { challenge in
            NavigationStack { challengeDetail(challenge) }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $recordingChallenge) { challenge in
            NavigationStack {
                DuelRecordingCaptureView(challenge: challenge) { metrics in
                    Task {
                        await duel.submitDerivedAttempt(
                            challengeID: challenge.id,
                            metrics: metrics,
                            requiredMinTempoBPM: challenge.requiredMinTempoBPM
                        )
                        recordingChallenge = nil
                    }
                }
            }
        }
        .task {
            duel.start(uid: firebase.isAnonymousUser ? nil : firebase.currentUserID)
            #if DEBUG
            if challengeID == "__qa_recording__" {
                recordingChallenge = Self.qaRecordingChallenge
                return
            }
            #endif
            if let challengeID {
                selectedChallenge = allChallenges.first(where: { $0.id == challengeID })
            }
            await duel.refreshSeasonLeaderboard(scope: leaderboardScope)
        }
        .onChange(of: leaderboardScope) { _, scope in
            Task { await duel.refreshSeasonLeaderboard(scope: scope) }
        }
        .onAppear {
            PracticeAnalytics.record(.duelEntered)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var leagueHeader: some View {
        StudioQuestSection {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(duel.leagueTier.title)
                        .font(.title2.weight(.bold))
                    Text("\(duel.duelRating) rating · \(duel.duelWins)W \(duel.duelLosses)L \(duel.duelDraws)D")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(StudioQuestTokens.ColorRole.gold)
            }
        }
    }

    @ViewBuilder
    private var arenaContent: some View {
        if firebase.isAnonymousUser {
            StudioQuestSection {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sign in to enter fair duels").font(.headline)
                    Text("Your core practice tools remain available as a guest.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Continue to sign in") { showSignIn = true }
                        .buttonStyle(StudioQuestPrimaryButtonStyle())
                }
            }
        } else {
            queueCard
            challengeGroup("Invitations", challenges: duel.incomingInvites)
            challengeGroup("Active matches", challenges: duel.activeChallenges)
            outgoingInvites
        }
    }

    private var queueCard: some View {
        StudioQuestSection {
            VStack(alignment: .leading, spacing: 12) {
                Text(duel.myOpenChallenge == nil ? "Find a performance match" : "Searching for a fair match")
                    .font(.headline)
                Text(duel.activeLeagueRequirement.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if duel.myOpenChallenge == nil {
                    Button("Join duel queue") {
                        Task { await duel.queueAsyncScaleDuel() }
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    .disabled(duel.isLoading)
                } else {
                    Button("Cancel queue", role: .destructive) {
                        Task { await duel.cancelOpenChallenge() }
                    }
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func challengeGroup(_ title: String, challenges: [DuelChallenge]) -> some View {
        if !challenges.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(StudioQuestTokens.Typography.sectionTitle)
                ForEach(challenges) { challenge in
                    Button { selectedChallenge = challenge } label: {
                        duelRow(challenge)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var outgoingInvites: some View {
        if !duel.outgoingInvites.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sent invitations").font(StudioQuestTokens.Typography.sectionTitle)
                ForEach(duel.outgoingInvites) { challenge in
                    HStack {
                        duelIdentity(challenge)
                        Spacer()
                        Button("Cancel") { Task { await duel.cancelInvite(challengeID: challenge.id) } }
                            .buttonStyle(.bordered)
                    }
                    .padding(14)
                    .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: RoundedRectangle(cornerRadius: 17))
                }
            }
        }
    }

    private func duelRow(_ challenge: DuelChallenge) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.badge.mic")
                .foregroundStyle(StudioQuestTokens.ColorRole.coral)
                .frame(width: 42, height: 42)
                .background(StudioQuestTokens.ColorRole.coral.opacity(0.10), in: Circle())
            duelIdentity(challenge)
            Spacer()
            Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(14)
        .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: RoundedRectangle(cornerRadius: 17))
        .contentShape(RoundedRectangle(cornerRadius: 17))
    }

    private func duelIdentity(_ challenge: DuelChallenge) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(challenge.objective).font(.headline)
            Text("\(challenge.octaveCount) octave\(challenge.octaveCount == 1 ? "" : "s") · \(challenge.status.rawValue.capitalized)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var leaderboardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Leaderboard scope", selection: $leaderboardScope) {
                ForEach(DuelLeaderboardScope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if duel.leaderboardRows.isEmpty {
                ContentUnavailableView("No standings yet", systemImage: "trophy")
            } else {
                ForEach(Array(duel.leaderboardRows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.headline.monospacedDigit()).frame(width: 24)
                        PBAvatarView(
                            avatarID: row.avatarID,
                            displayName: row.displayName,
                            profilePhotoURL: row.profilePhotoURL,
                            size: 42
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayName).font(.headline)
                            Text("\(row.rating) rating · \(row.wins) wins")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(row.points) pts").font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if duel.matchHistory.isEmpty && duel.recentCompleted.isEmpty {
                ContentUnavailableView("No duel history", systemImage: "clock.arrow.circlepath")
            } else {
                ForEach(duel.matchHistory.isEmpty ? duel.recentCompleted : duel.matchHistory) { challenge in
                    Button { selectedChallenge = challenge } label: { duelRow(challenge) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var allChallenges: [DuelChallenge] {
        duel.incomingInvites + duel.outgoingInvites + duel.activeChallenges + duel.recentCompleted + duel.matchHistory
    }

    #if DEBUG
    private static let qaRecordingChallenge = DuelChallenge(
        id: "__qa_recording__",
        createdByUID: "qa-musician",
        opponentUID: "qa-friend",
        participants: ["qa-musician", "qa-friend"],
        status: .active,
        queueType: .friend,
        objective: "C major · clean pulse",
        scaleName: "C major",
        octaveCount: 2,
        requiredLeague: "silver",
        requiredMinTempoBPM: 72,
        creatorAccepted: true,
        opponentAccepted: true,
        opponentRequestedOctaves: nil,
        createdAt: .now.addingTimeInterval(-3_600),
        acceptByAt: nil,
        startedAt: .now.addingTimeInterval(-900),
        submissionDeadlineAt: .now.addingTimeInterval(86_400),
        completedAt: nil,
        creatorScore: nil,
        opponentScore: nil,
        winnerUID: nil,
        creatorRatingDelta: 0,
        opponentRatingDelta: 0
    )
    #endif

    private func challengeDetail(_ challenge: DuelChallenge) -> some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(
                    title: LocalizedStringKey(challenge.objective),
                    subtitle: LocalizedStringKey("\(challenge.octaveCount) octave challenge")
                )
                StudioQuestSection {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Status", value: challenge.status.rawValue.capitalized)
                        LabeledContent("Minimum tempo", value: "\(challenge.requiredMinTempoBPM) BPM")
                        if let deadline = challenge.submissionDeadlineAt {
                            LabeledContent("Submit by", value: deadline.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
                if duel.incomingInvites.contains(where: { $0.id == challenge.id }) {
                    Button("Accept invitation") {
                        Task {
                            await duel.acceptInvite(challengeID: challenge.id)
                            selectedChallenge = nil
                        }
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    Button("Decline", role: .destructive) {
                        Task {
                            await duel.declineInvite(challengeID: challenge.id)
                            selectedChallenge = nil
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else if challenge.status == .active,
                          let uid = firebase.currentUserID,
                          challenge.myScore(for: uid) == nil {
                    Button("Record performance") {
                        selectedChallenge = nil
                        recordingChallenge = challenge
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                } else if challenge.status == .completed, let uid = firebase.currentUserID {
                    StudioQuestInlineStatus(
                        title: "Score \(challenge.myScore(for: uid) ?? 0) · Rating \(challenge.myRatingDelta(for: uid) >= 0 ? "+" : "")\(challenge.myRatingDelta(for: uid))",
                        systemImage: challenge.winnerUID == uid ? "trophy.fill" : "waveform",
                        tint: challenge.winnerUID == uid ? StudioQuestTokens.ColorRole.gold : StudioQuestTokens.ColorRole.cobalt
                    )
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Avatar Studio and economy

private struct StudioQuestLoadoutOption: Identifiable {
    let id: String
    let title: String
    let systemImage: String
}

struct StudioQuestAvatarStudioView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var buddies: BuddiesViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("practiquest.avatar.loadout") private var loadoutData = Data()
    @State private var section: AvatarStudioSection
    @State private var selectedAvatarID = "avatar_note"
    @State private var loadout = AvatarLoadout.starter(for: nil)
    @State private var selectedCategory: JourneyRewardCategory = .cosmetics
    @State private var statusMessage: String?
    @State private var showPro = false

    init(initialSection: AvatarStudioSection = .customize) {
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "Avatar Studio", subtitle: "Build the musician and room you earn.")
                tokenHeader
                studioPreview
                Picker("Studio section", selection: $section) {
                    Text("Customize").tag(AvatarStudioSection.customize)
                    Text("Collection").tag(AvatarStudioSection.collection)
                }
                .pickerStyle(.segmented)
                switch section {
                case .customize: avatarChoices
                case .collection: collection
                }
                if let statusMessage {
                    StudioQuestInlineStatus(
                        title: statusMessage,
                        systemImage: "checkmark.circle.fill",
                        tint: StudioQuestTokens.ColorRole.mint
                    )
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .onAppear {
            loadout = decodedLoadout
            selectedAvatarID = buddies.myProfile?.avatarID ?? loadout.baseID
        }
        .sheet(isPresented: $showPro) { NavigationStack { StudioQuestProView() } }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tokenHeader: some View {
        HStack {
            Label("\(journey.tokenBalance) tokens", systemImage: "diamond.fill")
                .font(.headline)
                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            Spacer()
            Button("Get Pro") { showPro = true }
                .font(.caption.weight(.bold))
                .opacity(purchaseManager.isPro ? 0 : 1)
                .disabled(purchaseManager.isPro)
        }
    }

    private var studioPreview: some View {
        StudioQuestAvatarScene(
            loadout: loadout,
            layout: loadout.layout(),
            displayName: buddies.myProfile?.displayName ?? "Your musician"
        )
        .overlay(alignment: .bottomTrailing) {
            Button {
                router.roomEditorPresented = true
            } label: {
                Label("Edit studio", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }

    private var avatarChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Musician identity")
                .font(StudioQuestTokens.Typography.sectionTitle)
            LazyVGrid(columns: avatarGridColumns, spacing: 12) {
                ForEach(PBAvatarStyle.all) { style in
                    Button {
                        Task { await select(style) }
                    } label: {
                        VStack(spacing: 8) {
                            PBAvatarView(avatarID: style.id, displayName: style.title, size: 72)
                            Text(style.title).font(.headline)
                            Text(style.isFree || journey.isAvatarUnlocked(id: style.id) ? "Available" : style.availability.label)
                                .font(.caption).foregroundStyle(.secondary)
                            if selectedAvatarID == style.id {
                                Label("Equipped", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(StudioQuestTokens.ColorRole.mint)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(
                            StudioQuestTokens.ColorRole.surface(colorScheme),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(selectedAvatarID == style.id ? StudioQuestTokens.ColorRole.cobalt : .clear, lineWidth: 2)
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Loadout")
                .font(StudioQuestTokens.Typography.sectionTitle)
                .padding(.top, 8)
            Text("Fine-tune the versioned layers that travel with your musician identity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            loadoutMenu(
                title: "Skin tone",
                selectedID: loadout.skinToneID,
                options: skinToneOptions
            ) { newID in setLoadout { $0.skinToneID = newID } }
            loadoutMenu(
                title: "Hair",
                selectedID: loadout.hairID,
                options: hairOptions
            ) { newID in setLoadout { $0.hairID = newID } }
            loadoutMenu(
                title: "Outfit",
                selectedID: loadout.outfitID,
                options: outfitOptions
            ) { newID in setLoadout { $0.outfitID = newID } }
            loadoutMenu(
                title: "Instrument",
                selectedID: loadout.instrumentID,
                options: instrumentOptions
            ) { newID in setLoadout { $0.instrumentID = newID } }
            loadoutMenu(
                title: "Accessory",
                selectedID: loadout.accessoryID ?? "accessory_none",
                options: accessoryOptions
            ) { newID in
                setLoadout {
                    $0.accessoryID = newID == "accessory_none" ? nil : newID
                }
            }
            loadoutMenu(
                title: "Pose",
                selectedID: loadout.poseID,
                options: poseOptions
            ) { newID in setLoadout { $0.poseID = newID } }
            loadoutMenu(
                title: "Studio room",
                selectedID: loadout.roomID,
                options: roomOptions
            ) { newID in setLoadout { $0.roomID = newID } }
        }
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Collection category", selection: $selectedCategory) {
                ForEach(JourneyRewardCategory.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            let items = journey.ownedRewards(in: selectedCategory)
            if items.isEmpty {
                ContentUnavailableView("No unlocked items", systemImage: "shippingbox")
            } else {
                ForEach(items) { item in
                    rewardItem(item, shopMode: false)
                }
            }
        }
    }



    private func rewardItem(_ item: JourneyRewardItem, shopMode: Bool) -> some View {
        StudioQuestRowSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.headline)
                        Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.isEquipped {
                        Label("Equipped", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(StudioQuestTokens.ColorRole.mint)
                    }
                }
                if item.isOwned {
                    Button(item.isEquipped ? "Unequip" : "Equip") {
                        Task {
                            let success = item.isEquipped
                                ? await journey.unequipReward(slot: item.slot)
                                : await journey.equipRewardItem(id: item.id)
                            if success { statusMessage = item.isEquipped ? "Item unequipped." : "Item equipped." }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(journey.isEconomyOperationInProgress)
                } else if shopMode {
                    Button("Unlock · \(item.costTokens) tokens") {
                        Task {
                            if await journey.claimRewardItem(id: item.id) {
                                statusMessage = "\(item.title) added to your collection."
                            } else {
                                statusMessage = "You need more tokens for this item."
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StudioQuestTokens.ColorRole.cobalt)
                    .disabled(journey.isEconomyOperationInProgress)
                }
            }
        }
    }

    private var decodedLoadout: AvatarLoadout {
        (try? JSONDecoder().decode(AvatarLoadout.self, from: loadoutData)) ?? .starter(for: buddies.myProfile?.avatarID)
    }

    private var avatarGridColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    @ViewBuilder
    private func loadoutMenu(
        title: String,
        selectedID: String,
        options: [StudioQuestLoadoutOption],
        onSelect: @escaping (String) -> Void
    ) -> some View {
        let selected = options.first(where: { $0.id == selectedID }) ?? options[0]
        StudioQuestRowSurface {
            Menu {
                ForEach(options) { option in
                    Button {
                        onSelect(option.id)
                    } label: {
                        Label(option.title, systemImage: option.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected.systemImage)
                        .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selected.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
        }
    }

    private var skinToneOptions: [StudioQuestLoadoutOption] {
        (1...8).map {
            .init(id: String(format: "skin_%02d", $0), title: "Tone \($0)", systemImage: "circle.fill")
        }
    }

    private var hairOptions: [StudioQuestLoadoutOption] {
        [
            ("hair_curl_01", "Soft curls"), ("hair_wave_01", "Natural waves"),
            ("hair_braid_01", "Braids"), ("hair_crop_01", "Close crop"),
            ("hair_bob_01", "Classic bob"), ("hair_loc_01", "Locs"),
            ("hair_coil_01", "Coils"), ("hair_silver_01", "Silver wave"),
            ("hair_long_01", "Long layers"), ("hair_part_01", "Side part"),
            ("hair_buzz_01", "Buzz cut"), ("hair_pony_01", "Ponytail")
        ].map { .init(id: $0.0, title: $0.1, systemImage: "person.crop.circle") }
    }

    private var outfitOptions: [StudioQuestLoadoutOption] {
        [
            ("outfit_contemporary_01", "Contemporary"), ("outfit_classical_01", "Classical"),
            ("outfit_jazz_01", "Jazz"), ("outfit_rock_01", "Rock"),
            ("outfit_casual_01", "Casual"), ("outfit_stage_01", "Stage"),
            ("outfit_studio_01", "Studio"), ("outfit_concert_01", "Concert")
        ].map { .init(id: $0.0, title: $0.1, systemImage: "tshirt") }
    }

    private var instrumentOptions: [StudioQuestLoadoutOption] {
        [
            ("instrument_piano", "Piano", "pianokeys"), ("instrument_violin", "Violin", "music.note"),
            ("instrument_cello", "Cello", "music.quarternote.3"), ("instrument_guitar", "Guitar", "guitars"),
            ("instrument_voice", "Voice", "mic.fill"), ("instrument_woodwind", "Woodwind", "wind"),
            ("instrument_brass", "Brass", "horn"), ("instrument_percussion", "Percussion", "metronome"),
            ("instrument_production", "Production", "slider.horizontal.3"), ("instrument_strings", "Strings", "music.note.list")
        ].map { .init(id: $0.0, title: $0.1, systemImage: $0.2) }
    }

    private var accessoryOptions: [StudioQuestLoadoutOption] {
        [
            ("accessory_none", "None", "nosign"), ("accessory_glasses", "Glasses", "eyeglasses"),
            ("accessory_headphones", "Headphones", "headphones"), ("accessory_earrings", "Earrings", "circle.hexagongrid"),
            ("accessory_watch", "Watch", "applewatch"), ("accessory_scarf", "Scarf", "wind"),
            ("accessory_pin", "Studio pin", "music.note"), ("accessory_case", "Instrument case", "shippingbox"),
            ("accessory_stand", "Music stand", "music.note.list")
        ].map { .init(id: $0.0, title: $0.1, systemImage: $0.2) }
    }

    private var poseOptions: [StudioQuestLoadoutOption] {
        [
            ("pose_idle", "Idle", "figure.stand"), ("pose_practicing", "Practicing", "music.note"),
            ("pose_victory", "Victory", "trophy.fill"), ("pose_focused", "Focused", "scope"),
            ("pose_celebration", "Celebration", "party.popper.fill")
        ].map { .init(id: $0.0, title: $0.1, systemImage: $0.2) }
    }

    private var roomOptions: [StudioQuestLoadoutOption] {
        StudioQuestAvatarRoom.catalog.map { room in
            let symbol: String
            switch room.id {
            case "room_midnight_stage": symbol = "moon.stars.fill"
            case "room_creative_loft": symbol = "sparkles"
            default: symbol = "sun.max.fill"
            }
            return .init(id: room.id, title: room.title, systemImage: symbol)
        }
    }

    private func setLoadout(_ mutation: (inout AvatarLoadout) -> Void) {
        var next = loadout
        mutation(&next)
        next.version = AvatarLoadout.currentVersion
        let editedRoom = next.roomLayouts != loadout.roomLayouts
        loadout = next
        if let data = try? JSONEncoder().encode(next) {
            loadoutData = data
        }
        Task {
            await buddies.updateAvatarLoadout(next)
        }
        if editedRoom {
            PracticeAnalytics.record(.avatarRoomEdited)
        }
    }

    private func placeDecoration(_ decoration: StudioQuestRoomDecoration) {
        var layout = loadout.layout()
        let count = layout.placements.count
        let seed = Double(count % 3) * 0.07
        let defaultPoint = decoration.zone.clamped(.init(
            x: 0.27 + seed,
            y: decoration.zone == .wall ? 0.34 : 0.76
        ))
        layout.placements.append(
            .init(
                decorationID: decoration.id,
                position: defaultPoint,
                depth: decoration.zone == .floor ? -1 : 1
            )
        )
        layout.updatedAt = .now
        setLoadout { $0.setLayout(layout) }
        statusMessage = "Placed \(decoration.title). Drag it anywhere in its valid zone."
    }

    private func movePlacement(_ placement: StudioQuestRoomPlacement, to point: StudioQuestRoomPoint) {
        guard let decoration = StudioQuestRoomDecoration.decoration(for: placement.decorationID) else { return }
        var layout = loadout.layout()
        guard let index = layout.placements.firstIndex(where: { $0.id == placement.id }) else { return }
        layout.placements[index].position = decoration.zone.clamped(point)
        layout.updatedAt = .now
        setLoadout { $0.setLayout(layout) }
    }

    private func removePlacement(_ placement: StudioQuestRoomPlacement) {
        var layout = loadout.layout()
        layout.placements.removeAll { $0.id == placement.id }
        layout.updatedAt = .now
        setLoadout { $0.setLayout(layout) }
        statusMessage = "Removed decoration. It remains in your collection."
    }

    private func select(_ style: PBAvatarStyle) async {
        if !style.isFree, !journey.isAvatarUnlocked(id: style.id) {
            guard await journey.unlockAvatar(id: style.id) else {
                statusMessage = "You need more tokens to unlock \(style.title)."
                return
            }
        }
        selectedAvatarID = style.id
        setLoadout {
            $0.baseID = style.id
            $0.poseID = "pose_idle"
        }
        await buddies.updateProfile(
            avatarID: style.id,
            profilePhotoURL: buddies.myProfile?.profilePhotoURL,
            bio: buddies.myProfile?.bio ?? "",
            instrument: buddies.myProfile?.instrument ?? ""
        )
        statusMessage = "\(style.title) is now your musician avatar."
    }
}
