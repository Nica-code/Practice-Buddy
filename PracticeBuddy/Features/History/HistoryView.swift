import SwiftUI
import SwiftData
import os
import AVFoundation

struct HistoryView: View {
    private enum HistoryMode: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case sessions = "Sessions"
        case skills = "Skills"
        case runThroughs = "Run-throughs"

        var id: String { rawValue }
        var titleKey: String { rawValue }
    }

    private enum HistoryScope: String, CaseIterable, Identifiable {
        case all
        case today
        case week
        case month

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .all: return "All"
            case .today: return "Today"
            case .week: return "Week"
            case .month: return "Month"
            }
        }
    }

    private struct SelectedID: Identifiable, Hashable {
        let id: UUID
    }

    private struct HistorySkillCard: Identifiable {
        let id: String
        let title: String
        let value: String
        let meta: String
    }

    private enum ExportFormat {
        case csv
        case json

        var serviceFormat: SessionExportService.ExportFormat {
            switch self {
            case .csv: return .csv
            case .json: return .json
            }
        }
    }

    private let logger = Logger(subsystem: "PracticeBuddy", category: "history")

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0
    @Query(sort: [SortDescriptor(\LoopPracticeLogModel.date, order: .reverse)]) private var loopLogs: [LoopPracticeLogModel]
    @Query(sort: [SortDescriptor(\PracticePlanLogModel.date, order: .reverse)]) private var planLogs: [PracticePlanLogModel]
    @Query(sort: [SortDescriptor(\RhythmAccuracyTakeModel.date, order: .reverse)]) private var rhythmTakes: [RhythmAccuracyTakeModel]
    @Query(sort: [SortDescriptor(\ScaleIntonationTakeModel.date, order: .reverse)]) private var intonationTakes: [ScaleIntonationTakeModel]
    @Query(sort: [SortDescriptor(\RunThroughModel.date, order: .reverse)]) private var runThroughs: [RunThroughModel]

    @State private var searchText: String = ""
    @State private var mode: HistoryMode = .overview
    @State private var scope: HistoryScope = .all
    @State private var sessionVisibleLimit: Int = 20
    @State private var loopVisibleLimit: Int = 12
    @State private var planVisibleLimit: Int = 12
    @State private var rhythmVisibleLimit: Int = 12
    @State private var intonationVisibleLimit: Int = 12
    @State private var runThroughVisibleLimit: Int = 12
    @State private var expandThisWeekSessions: Bool = true
    @State private var expandEarlierSessions: Bool = false

    @State private var showExportOptions: Bool = false
    @State private var exportURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var exportErrorMessage: String? = nil
    @State private var showExportError: Bool = false
    @State private var showProLockedAlert: Bool = false

    @State private var selectedSheetID: SelectedID? = nil
    @State private var runThroughPlayer: AVAudioPlayer?
    @State private var playingRunThroughID: UUID?
    @State private var compareRunAID: UUID?
    @State private var compareRunBID: UUID?
    @State private var filteredSessionsCache: [PracticeSessionModel] = []
    @State private var filteredLoopLogsCache: [LoopPracticeLogModel] = []
    @State private var filteredPlanLogsCache: [PracticePlanLogModel] = []
    @State private var filteredRhythmTakesCache: [RhythmAccuracyTakeModel] = []
    @State private var filteredIntonationTakesCache: [ScaleIntonationTakeModel] = []
    @State private var filteredRunThroughsCache: [RunThroughModel] = []

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var recomputeToken: String {
        [
            scope.rawValue,
            searchText,
            "\(store.sessions.count)",
            "\(loopLogs.count)",
            "\(planLogs.count)",
            "\(rhythmTakes.count)",
            "\(intonationTakes.count)",
            "\(runThroughs.count)"
        ].joined(separator: "|")
    }

    var body: some View {
        historyList
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PBAdBannerSlot(placement: .playBottomBanner)
            }
            .scrollContentBackground(.hidden)
            .background(chrome.ignoresSafeArea())
            .toolbarBackground(chrome, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if purchaseManager.featuresUnlocked {
                            showExportOptions = true
                        } else {
                            showProLockedAlert = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(palette.accent)
                    }
                    .accessibilityLabel("Export")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search notes"
            )
            .task(id: recomputeToken) {
                recomputeFilteredCaches()
            }
            .onChange(of: scope) { _, _ in
                sessionVisibleLimit = 20
                loopVisibleLimit = 12
                planVisibleLimit = 12
                rhythmVisibleLimit = 12
                intonationVisibleLimit = 12
                runThroughVisibleLimit = 12
                expandThisWeekSessions = true
                expandEarlierSessions = false
            }
            .onChange(of: mode) { _, _ in
                expandThisWeekSessions = true
                expandEarlierSessions = false
            }
            .confirmationDialog("Export", isPresented: $showExportOptions, titleVisibility: .visible) {
                Button("Export CSV") { export(format: .csv) }
                Button("Export JSON") { export(format: .json) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Exports the currently shown (filtered) sessions.")
            }
            .alert("Export Failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "Unknown error.")
            }
            .alert("Feature Unavailable", isPresented: $showProLockedAlert) {
                Button("Not Now", role: .cancel) {}
                Button("Open Subscription") {
                    selectedTab = 4
                }
            } message: {
                Text("This feature is currently unavailable.")
            }
            .sheet(isPresented: $showShareSheet) {
                if let exportURL {
                    ActivityView(activityItems: [exportURL])
                        .presentationDetents([.medium, .large])
                } else {
                    Text("Nothing to share.")
                        .padding()
                }
            }
            .sheet(item: $selectedSheetID) { wrapper in
                SessionNoteView(sessionID: wrapper.id)
            }
    }

    private var historyList: AnyView {
        AnyView(
            List {
                modeScopeSection

                switch mode {
                case .overview:
                    overviewKPISection
                    overviewRecentSessionsSection
                    overviewRecentSkillsSection
                    overviewRecentRunThroughsSection
                case .sessions:
                    analyticsSection
                    sessionsBucketsSection
                case .skills:
                    planLogsSection
                    intonationSection
                case .runThroughs:
                    runThroughSection
                }
            }
        )
    }

    @ViewBuilder
    private var analyticsSection: some View {
        Section("Analytics") {
            if purchaseManager.featuresUnlocked {
                HStack {
                    Text("Total time")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(DurationFormatter.string(from: analyticsTotalSeconds))
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Average session")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(DurationFormatter.string(from: analyticsAverageSeconds))
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Longest session")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(DurationFormatter.string(from: analyticsLongestSeconds))
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }

            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Advanced analytics is currently unavailable.")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)
                    Button("Open Subscription") {
                        selectedTab = 4
                    }
                    .font(type.button)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var modeScopeSection: some View {
        Section {
            Picker("History Mode", selection: $mode) {
                ForEach(HistoryMode.allCases) { value in
                    Text(LocalizedStringKey(value.titleKey)).tag(value)
                }
            }
            .pickerStyle(.segmented)

            Picker("Scope", selection: $scope) {
                ForEach(HistoryScope.allCases) { s in
                    Text(LocalizedStringKey(s.titleKey)).tag(s)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Sessions")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(filteredSessions.count)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("Guided plans")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(filteredPlanLogs.count)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("Intonation takes")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(filteredIntonationTakes.count)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("Run-throughs")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(filteredRunThroughs.count)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .listRowBackground(palette.surface)
    }

    private var overviewKPISection: some View {
        Section("Overview") {
            HStack {
                HistoryStatCardView(title: "Total", value: DurationFormatter.string(from: analyticsTotalSeconds), subtitle: "in scope", palette: palette, type: type)
                HistoryStatCardView(title: "Average", value: DurationFormatter.string(from: analyticsAverageSeconds), subtitle: "session", palette: palette, type: type)
            }
            HStack {
                HistoryStatCardView(title: "Longest", value: DurationFormatter.string(from: analyticsLongestSeconds), subtitle: "session", palette: palette, type: type)
                HistoryStatCardView(title: "Count", value: "\(filteredSessions.count)", subtitle: "sessions", palette: palette, type: type)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var overviewRecentSessionsSection: some View {
        Section {
            HStack {
                Text("Recent Sessions")
                    .font(type.sectionTitle)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button("See all") { mode = .sessions }
                    .font(type.footnote)
            }

            if filteredSessions.isEmpty {
                Text("No sessions yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(filteredSessions.prefix(5)) { session in
                            Button {
                                selectedSheetID = SelectedID(id: session.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(type.footnote)
                                        .foregroundStyle(palette.textSecondary)
                                    Text(DurationFormatter.string(from: session.durationSeconds))
                                        .font(type.body)
                                        .foregroundStyle(palette.textPrimary)
                                    let xp = max(0, (session.hasVerificationData ? session.verifiedSeconds : session.durationSeconds) / 60)
                                    Text(L10n.f("+%@ XP", "\(xp)"))
                                        .font(type.footnote)
                                        .foregroundStyle(palette.accent)
                                        .monospacedDigit()
                                }
                                .frame(minWidth: 170, idealWidth: 190, maxWidth: 210, alignment: .leading)
                                .padding(10)
                                .background(palette.surfaceAlt)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var overviewRecentSkillsSection: some View {
        Section {
            HStack {
                Text("Recent Skills")
                    .font(type.sectionTitle)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button("See all") { mode = .skills }
                    .font(type.footnote)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recentSkillCards) { card in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(LocalizedStringKey(card.title))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Text(card.value)
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Text(LocalizedStringKey(card.meta))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                        }
                        .frame(minWidth: 180, idealWidth: 200, maxWidth: 220, alignment: .leading)
                        .padding(10)
                        .background(palette.surfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var overviewRecentRunThroughsSection: some View {
        Section {
            HStack {
                Text("Recent Run-throughs")
                    .font(type.sectionTitle)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button("See all") { mode = .runThroughs }
                    .font(type.footnote)
            }

            if filteredRunThroughs.isEmpty {
                Text("No run-through takes yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(filteredRunThroughs.prefix(5)) { take in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(take.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                                Text(DurationFormatter.string(from: take.durationSeconds))
                                    .font(type.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text(L10n.f("Rating %@/5", "\(take.selfRating)"))
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                                    .monospacedDigit()
                            }
                            .frame(minWidth: 170, idealWidth: 190, maxWidth: 210, alignment: .leading)
                            .padding(10)
                            .background(palette.surfaceAlt)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var sessionsBucketsSection: some View {
        let buckets = sessionBuckets
        return Section("Sessions") {
            if visibleSessions.isEmpty {
                HistoryEmptyStateRow(
                    title: "No sessions yet",
                    subtitle: "Start a timer on Home and save your first session.",
                    palette: palette,
                    type: type
                )
            } else {
                if !buckets.today.isEmpty {
                    Text("Today")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    ForEach(buckets.today) { session in
                        sessionListRow(session)
                    }
                    .onDelete { offsets in
                        delete(offsets: offsets, from: buckets.today)
                    }
                }

                if !buckets.thisWeek.isEmpty {
                    DisclosureGroup(isExpanded: $expandThisWeekSessions) {
                        ForEach(buckets.thisWeek) { session in
                            sessionListRow(session)
                        }
                        .onDelete { offsets in
                            delete(offsets: offsets, from: buckets.thisWeek)
                        }
                    } label: {
                        Text("This Week")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                if !buckets.earlier.isEmpty {
                    DisclosureGroup(isExpanded: $expandEarlierSessions) {
                        ForEach(buckets.earlier) { session in
                            sessionListRow(session)
                        }
                        .onDelete { offsets in
                            delete(offsets: offsets, from: buckets.earlier)
                        }
                    } label: {
                        Text("Earlier")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                if filteredSessions.count > visibleSessions.count {
                    Button("Load more sessions") {
                        sessionVisibleLimit += 20
                    }
                    .font(type.footnote)
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var loopLogsSection: some View {
        Section("Loop Sessions") {
            if visibleLoopLogs.isEmpty {
                Text("No loop logs in this scope yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(visibleLoopLogs) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(log.date.formatted(date: .abbreviated, time: .shortened))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(L10n.f("%@ loops", "\(log.loopsCompleted)"))
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text(L10n.f("Work: %@", DurationFormatter.string(from: log.totalWorkSeconds)))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            if log.tempoStartBPM > 0 || log.tempoEndBPM > 0 {
                                Text(L10n.f("Tempo: %@→%@", "\(log.tempoStartBPM)", "\(log.tempoEndBPM)"))
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                                    .monospacedDigit()
                            }
                        }

                        let tags = loopTags(from: log)
                        if !tags.isEmpty {
                            Text(tags.joined(separator: ", "))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    deleteLoopLogs(offsets: offsets, from: visibleLoopLogs)
                }

                if filteredLoopLogs.count > visibleLoopLogs.count {
                    Button("Load more loop sessions") {
                        loopVisibleLimit += 12
                    }
                    .font(type.footnote)
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var planLogsSection: some View {
        Section("Guided Practice") {
            if visiblePlanLogs.isEmpty {
                Text("No guided practice logs in this scope yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(visiblePlanLogs) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(log.date.formatted(date: .abbreviated, time: .shortened))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(L10n.f("%@/5", "\(log.selfRating)"))
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text(L10n.f("Time: %@ / %@m target", DurationFormatter.string(from: log.actualSeconds), "\(log.targetMinutes)"))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                        }

                        let goals = parseCSV(log.goalsRaw)
                        if !goals.isEmpty {
                            Text(L10n.f("Goals: %@", goals.joined(separator: ", ")))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    deletePlanLogs(offsets: offsets, from: visiblePlanLogs)
                }

                if filteredPlanLogs.count > visiblePlanLogs.count {
                    Button("Load more guided plans") {
                        planVisibleLimit += 12
                    }
                    .font(type.footnote)
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var rhythmLogsSection: some View {
        Section("Rhythm Accuracy") {
            if visibleRhythmTakes.isEmpty {
                Text("No rhythm takes in this scope yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(visibleRhythmTakes) { take in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(take.date.formatted(date: .abbreviated, time: .shortened))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(L10n.f("Score %@", "\(take.grooveScore)"))
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text(L10n.f("BPM %@ • %@ beats", "\(take.bpm)", "\(take.beatsAnalyzed)"))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            Text(String(format: "%+.1f ms", take.averageOffsetMs))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        if purchaseManager.featuresUnlocked, !take.detailJSON.isEmpty {
                            let rows = take.detailJSON
                                .split(separator: "|")
                                .map { String($0) }
                            if let first = rows.first {
                                Text(L10n.f("Window 1: %@", first))
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    deleteRhythmTakes(offsets: offsets, from: visibleRhythmTakes)
                }

                if filteredRhythmTakes.count > visibleRhythmTakes.count {
                    Button("Load more rhythm takes") {
                        rhythmVisibleLimit += 12
                    }
                    .font(type.footnote)
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var runThroughSection: some View {
        Section("Run-throughs") {
            if visibleRunThroughRows.isEmpty {
                Text("No run-through takes in this scope yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                if purchaseManager.featuresUnlocked, let compareText = runThroughCompareSummaryText {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A/B Compare")
                            .font(type.footnote)
                            .foregroundStyle(palette.textPrimary)
                        Text(compareText)
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        HStack {
                            Text("A and B are selected below.")
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            Button("Clear") {
                                compareRunAID = nil
                                compareRunBID = nil
                            }
                            .buttonStyle(.bordered)
                            .font(type.footnote)
                        }
                    }
                }

                ForEach(visibleRunThroughRows) { take in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(take.date.formatted(date: .abbreviated, time: .shortened))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(L10n.f("%@/5", "\(take.selfRating)"))
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text(L10n.f("Duration: %@", DurationFormatter.string(from: take.durationSeconds)))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            if take.usedMetronome {
                                Text("Metronome")
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }

                        if !take.pieceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(L10n.f("Piece: %@", take.pieceName))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }

                        if !take.markers.isEmpty {
                            Text(L10n.f("Markers: %@ • %@", "\(take.markers.count)", take.markers.prefix(3).map(\.label).joined(separator: ", ")))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }

                        if !take.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(take.notes)
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: 10) {
                            Button(playingRunThroughID == take.id ? "Stop" : "Play") {
                                togglePlayback(for: take)
                            }
                            .buttonStyle(.bordered)
                            .font(type.footnote)

                            if purchaseManager.featuresUnlocked {
                                Button(compareButtonTitle(for: take.id)) {
                                    setCompareTarget(take.id)
                                }
                                .buttonStyle(.bordered)
                                .font(type.footnote)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    deleteRunThroughs(offsets: offsets, from: visibleRunThroughRows)
                }

                if !purchaseManager.featuresUnlocked, filteredRunThroughs.count > visibleRunThroughRows.count {
                    Text("Only the latest 3 run-through entries are shown right now.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }

                if purchaseManager.featuresUnlocked, filteredRunThroughs.count > visibleRunThroughRows.count {
                    Button("Load more run-throughs") {
                        runThroughVisibleLimit += 12
                    }
                    .font(type.footnote)
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var intonationSection: some View {
        Section("Scale Intonation") {
            if visibleIntonationTakes.isEmpty {
                Text("No intonation takes in this scope yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(visibleIntonationTakes) { take in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(take.date.formatted(date: .abbreviated, time: .shortened))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(L10n.f("Score %@", "\(take.overallScore)"))
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text(
                                L10n.f(
                                    "%@ %@ • %@",
                                    take.keyRaw,
                                    String(localized: String.LocalizationValue(take.modeRaw.capitalized)),
                                    String(localized: String.LocalizationValue(take.exerciseTypeRaw))
                                )
                            )
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            Text(L10n.f("A=%@", "\(take.referenceHz)"))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text(String(format: "Center %.0f%% • Stability %.0f%% • Consistency %.0f%%", take.centeringScore, take.stabilityScore, take.consistencyScore))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            Text(String(format: "%+.1fc", take.meanOffsetCents))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        let suggestions = parseSuggestions(take.suggestionsRaw)
                        if let first = suggestions.first {
                            Text(L10n.f("Fix: %@", first))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                        }

                        if purchaseManager.featuresUnlocked, let firstRow = parseIntonationRows(take.perNoteJSON).first {
                            Text(L10n.f("Detail: %@", firstRow))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    deleteIntonationTakes(offsets: offsets, from: visibleIntonationTakes)
                }

                if filteredIntonationTakes.count > visibleIntonationTakes.count {
                    Button("Load more intonation takes") {
                        intonationVisibleLimit += 12
                    }
                    .font(type.footnote)
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var analyticsTotalSeconds: Int {
        filteredSessions.reduce(0) { $0 + max(0, $1.durationSeconds) }
    }

    private var analyticsAverageSeconds: Int {
        guard !filteredSessions.isEmpty else { return 0 }
        return analyticsTotalSeconds / filteredSessions.count
    }

    private var analyticsLongestSeconds: Int {
        filteredSessions.map { max(0, $0.durationSeconds) }.max() ?? 0
    }

    private func sessionListRow(_ session: PracticeSessionModel) -> some View {
        sessionRow(session)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedSheetID = SelectedID(id: session.id)
            }
    }

    private func sessionRow(_ session: PracticeSessionModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                Text(DurationFormatter.string(from: session.durationSeconds))
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            let xpForRow = max(0, (session.hasVerificationData ? session.verifiedSeconds : session.durationSeconds) / 60)
            Text(L10n.f("+%@ XP", "\(xpForRow)"))
                .font(type.footnote)
                .foregroundStyle(palette.accent)
                .monospacedDigit()

            if !session.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(session.noteTitle)
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
            }

            if session.hasVerificationData {
                HStack(spacing: 8) {
                    Text(L10n.f("Verified %@", DurationFormatter.string(from: max(0, session.verifiedSeconds))))
                        .font(type.footnote)
                        .foregroundStyle(palette.accent)
                    Text("•")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Text(L10n.f("Missed %@", "\(session.missedCheckInCount)"))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
            }

            let preview = notePreview(for: session)
            if !preview.isEmpty {
                Text(preview)
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 6)
    }

    private var filteredSessions: [PracticeSessionModel] {
        filteredSessionsCache
    }

    private func sessionMatchesSearch(_ session: PracticeSessionModel, needle: String) -> Bool {
        let baseHaystack = [
            session.notes,
            session.noteTitle,
            session.noteFocus,
            session.noteMoodRaw
        ]
        .joined(separator: "\n")
        .lowercased()

        if baseHaystack.contains(needle) {
            return true
        }

        guard let journal = session.journal else { return false }
        let journalHaystack = (
            journal.reflection + "\n" +
            journal.pieces.map { [$0.title, $0.tempo, $0.wentWell, $0.needsWork, $0.nextAction].joined(separator: " ") }
                .joined(separator: "\n")
        ).lowercased()
        return journalHaystack.contains(needle)
    }

    private var filteredLoopLogs: [LoopPracticeLogModel] {
        filteredLoopLogsCache
    }

    private var filteredPlanLogs: [PracticePlanLogModel] {
        filteredPlanLogsCache
    }

    private var filteredRhythmTakes: [RhythmAccuracyTakeModel] {
        filteredRhythmTakesCache
    }

    private var filteredIntonationTakes: [ScaleIntonationTakeModel] {
        filteredIntonationTakesCache
    }

    private var filteredRunThroughs: [RunThroughModel] {
        filteredRunThroughsCache
    }

    private func recomputeFilteredCaches() {
        let needle = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        var sessionsRows = sessionsFilteredByScope(scope)
        if !needle.isEmpty {
            sessionsRows = sessionsRows.filter { sessionMatchesSearch($0, needle: needle) }
        }
        filteredSessionsCache = sessionsRows

        var loopRows = logsFilteredByScope(scope)
        if !needle.isEmpty {
            loopRows = loopRows.filter { $0.tagsRaw.lowercased().contains(needle) }
        }
        filteredLoopLogsCache = loopRows

        var planRows = planLogsFilteredByScope(scope)
        if !needle.isEmpty {
            planRows = planRows.filter { log in
                [
                    log.goalsRaw,
                    log.blocksRaw,
                    log.reflectionWins,
                    log.reflectionFix,
                    log.reflectionNext
                ]
                .joined(separator: "\n")
                .lowercased()
                .contains(needle)
            }
        }
        filteredPlanLogsCache = planRows

        var rhythmRows = rhythmTakesFilteredByScope(scope)
        if !needle.isEmpty {
            rhythmRows = rhythmRows.filter {
                "\($0.bpm) \($0.grooveScore) \($0.averageOffsetMs) \($0.detailJSON)"
                    .lowercased()
                    .contains(needle)
            }
        }
        filteredRhythmTakesCache = rhythmRows

        var intonationRows = intonationTakesFilteredByScope(scope)
        if !needle.isEmpty {
            intonationRows = intonationRows.filter { take in
                [
                    take.exerciseTypeRaw,
                    take.keyRaw,
                    take.modeRaw,
                    take.suggestionsRaw,
                    take.perNoteJSON
                ]
                .joined(separator: " ")
                .lowercased()
                .contains(needle)
            }
        }
        filteredIntonationTakesCache = intonationRows

        var runRows = runThroughsFilteredByScope(scope)
        if !needle.isEmpty {
            runRows = runRows.filter {
                "\($0.notes) \($0.durationSeconds) \($0.selfRating)"
                    .lowercased()
                    .contains(needle)
            }
        }
        filteredRunThroughsCache = runRows
    }

    private var visibleLoopLogs: [LoopPracticeLogModel] {
        Array(filteredLoopLogs.prefix(max(1, loopVisibleLimit)))
    }

    private var visiblePlanLogs: [PracticePlanLogModel] {
        Array(filteredPlanLogs.prefix(max(1, planVisibleLimit)))
    }

    private var visibleRhythmTakes: [RhythmAccuracyTakeModel] {
        Array(filteredRhythmTakes.prefix(max(1, rhythmVisibleLimit)))
    }

    private var visibleIntonationTakes: [ScaleIntonationTakeModel] {
        Array(filteredIntonationTakes.prefix(max(1, intonationVisibleLimit)))
    }

    private var visibleRunThroughRows: [RunThroughModel] {
        if purchaseManager.featuresUnlocked {
            return Array(filteredRunThroughs.prefix(max(1, runThroughVisibleLimit)))
        }
        return Array(filteredRunThroughs.prefix(3))
    }

    private var visibleSessions: [PracticeSessionModel] {
        Array(filteredSessions.prefix(max(1, sessionVisibleLimit)))
    }

    private var sessionBuckets: (today: [PracticeSessionModel], thisWeek: [PracticeSessionModel], earlier: [PracticeSessionModel]) {
        var today: [PracticeSessionModel] = []
        var thisWeek: [PracticeSessionModel] = []
        var earlier: [PracticeSessionModel] = []
        let cal = Calendar.current
        let now = Date()
        let dayInterval = cal.dateInterval(of: .day, for: now)
        let weekInterval = cal.dateInterval(of: .weekOfYear, for: now)

        for session in visibleSessions {
            if let dayInterval, session.date >= dayInterval.start && session.date < dayInterval.end {
                today.append(session)
            } else if let weekInterval, session.date >= weekInterval.start && session.date < weekInterval.end {
                thisWeek.append(session)
            } else {
                earlier.append(session)
            }
        }
        return (today, thisWeek, earlier)
    }

    private var recentSkillCards: [HistorySkillCard] {
        var cards: [HistorySkillCard] = []

        if let intonation = filteredIntonationTakes.first {
            cards.append(
                HistorySkillCard(
                    id: "intonation",
                    title: "Intonation",
                    value: "Score \(intonation.overallScore)",
                    meta: "\(intonation.keyRaw) \(intonation.modeRaw.capitalized)"
                )
            )
        }
        if let plan = filteredPlanLogs.first {
            cards.append(
                HistorySkillCard(
                    id: "plan",
                    title: "Guided Plan",
                    value: "\(DurationFormatter.string(from: plan.actualSeconds))",
                    meta: "Rating \(plan.selfRating)/5"
                )
            )
        }

        if cards.isEmpty {
            cards.append(
                HistorySkillCard(
                    id: "none",
                    title: "No skill logs",
                    value: "Start a Practice Lab take",
                    meta: "Your latest scores will appear here."
                )
            )
        }
        return cards
    }

    private var runThroughCompareSummaryText: String? {
        guard let aID = compareRunAID, let bID = compareRunBID,
              let a = runThroughs.first(where: { $0.id == aID }),
              let b = runThroughs.first(where: { $0.id == bID }) else {
            return nil
        }

        let durationDelta = b.durationSeconds - a.durationSeconds
        let ratingDelta = b.selfRating - a.selfRating
        let markerDelta = b.markers.count - a.markers.count

        let durationText = String(format: "%+d sec", durationDelta)
        let ratingText = String(format: "%+d", ratingDelta)
        let markerText = String(format: "%+d", markerDelta)
        return "Duration \(durationText) • Rating \(ratingText) • Markers \(markerText)"
    }

    private func compareButtonTitle(for id: UUID) -> String {
        if compareRunAID == id { return "A ✓" }
        if compareRunBID == id { return "B ✓" }
        return "Set A/B"
    }

    private func setCompareTarget(_ id: UUID) {
        if compareRunAID == nil {
            compareRunAID = id
            return
        }
        if compareRunAID == id {
            compareRunAID = nil
            return
        }
        if compareRunBID == nil {
            compareRunBID = id
            return
        }
        if compareRunBID == id {
            compareRunBID = nil
            return
        }
        compareRunAID = compareRunBID
        compareRunBID = id
    }

    private func notePreview(for session: PracticeSessionModel) -> String {
        if let journal = session.journal {
            if !journal.reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return journal.reflection
            }
            if let firstPiece = journal.pieces.first {
                if !firstPiece.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return firstPiece.title
                }
            }
        }

        if !session.noteFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Focus: \(session.noteFocus)"
        }

        return session.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sessionsFilteredByScope(_ scope: HistoryScope) -> [PracticeSessionModel] {
        let cal = Calendar.current
        let now = Date()

        switch scope {
        case .all:
            return store.sessions
        case .today:
            guard let interval = cal.dateInterval(of: .day, for: now) else { return [] }
            return store.sessions.filter { $0.date >= interval.start && $0.date < interval.end }
        case .week:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }
            return store.sessions.filter { $0.date >= interval.start && $0.date < interval.end }
        case .month:
            guard let interval = cal.dateInterval(of: .month, for: now) else { return [] }
            return store.sessions.filter { $0.date >= interval.start && $0.date < interval.end }
        }
    }

    private func logsFilteredByScope(_ scope: HistoryScope) -> [LoopPracticeLogModel] {
        let cal = Calendar.current
        let now = Date()

        switch scope {
        case .all:
            return loopLogs
        case .today:
            guard let interval = cal.dateInterval(of: .day, for: now) else { return [] }
            return loopLogs.filter { $0.date >= interval.start && $0.date < interval.end }
        case .week:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }
            return loopLogs.filter { $0.date >= interval.start && $0.date < interval.end }
        case .month:
            guard let interval = cal.dateInterval(of: .month, for: now) else { return [] }
            return loopLogs.filter { $0.date >= interval.start && $0.date < interval.end }
        }
    }

    private func planLogsFilteredByScope(_ scope: HistoryScope) -> [PracticePlanLogModel] {
        let cal = Calendar.current
        let now = Date()

        switch scope {
        case .all:
            return planLogs
        case .today:
            guard let interval = cal.dateInterval(of: .day, for: now) else { return [] }
            return planLogs.filter { $0.date >= interval.start && $0.date < interval.end }
        case .week:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }
            return planLogs.filter { $0.date >= interval.start && $0.date < interval.end }
        case .month:
            guard let interval = cal.dateInterval(of: .month, for: now) else { return [] }
            return planLogs.filter { $0.date >= interval.start && $0.date < interval.end }
        }
    }

    private func rhythmTakesFilteredByScope(_ scope: HistoryScope) -> [RhythmAccuracyTakeModel] {
        let cal = Calendar.current
        let now = Date()

        switch scope {
        case .all:
            return rhythmTakes
        case .today:
            guard let interval = cal.dateInterval(of: .day, for: now) else { return [] }
            return rhythmTakes.filter { $0.date >= interval.start && $0.date < interval.end }
        case .week:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }
            return rhythmTakes.filter { $0.date >= interval.start && $0.date < interval.end }
        case .month:
            guard let interval = cal.dateInterval(of: .month, for: now) else { return [] }
            return rhythmTakes.filter { $0.date >= interval.start && $0.date < interval.end }
        }
    }

    private func intonationTakesFilteredByScope(_ scope: HistoryScope) -> [ScaleIntonationTakeModel] {
        let cal = Calendar.current
        let now = Date()

        switch scope {
        case .all:
            return intonationTakes
        case .today:
            guard let interval = cal.dateInterval(of: .day, for: now) else { return [] }
            return intonationTakes.filter { $0.date >= interval.start && $0.date < interval.end }
        case .week:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }
            return intonationTakes.filter { $0.date >= interval.start && $0.date < interval.end }
        case .month:
            guard let interval = cal.dateInterval(of: .month, for: now) else { return [] }
            return intonationTakes.filter { $0.date >= interval.start && $0.date < interval.end }
        }
    }

    private func runThroughsFilteredByScope(_ scope: HistoryScope) -> [RunThroughModel] {
        let cal = Calendar.current
        let now = Date()

        switch scope {
        case .all:
            return runThroughs
        case .today:
            guard let interval = cal.dateInterval(of: .day, for: now) else { return [] }
            return runThroughs.filter { $0.date >= interval.start && $0.date < interval.end }
        case .week:
            guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }
            return runThroughs.filter { $0.date >= interval.start && $0.date < interval.end }
        case .month:
            guard let interval = cal.dateInterval(of: .month, for: now) else { return [] }
            return runThroughs.filter { $0.date >= interval.start && $0.date < interval.end }
        }
    }

    private func loopTags(from log: LoopPracticeLogModel) -> [String] {
        log.tagsRaw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseCSV(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseSuggestions(_ raw: String) -> [String] {
        raw
            .split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseIntonationRows(_ raw: String) -> [String] {
        raw
            .split(separator: ";")
            .compactMap { row in
                let parts = row.split(separator: ",").map(String.init)
                guard parts.count >= 6 else { return nil }
                let degree = parts[0]
                let name = parts[1]
                let mean = parts[2]
                let center = parts[3]
                let stability = parts[4]
                return "d\(degree) \(name) \(mean)c • C \(center)% • S \(stability)%"
            }
    }

    private func delete(offsets: IndexSet, from filtered: [PracticeSessionModel]) {
        let ids = offsets.map { filtered[$0].id }
        store.deleteSessions(withIDs: ids)
    }

    private func export(format: ExportFormat) {
        guard purchaseManager.featuresUnlocked else {
            showProLockedAlert = true
            return
        }

        do {
            let url = try SessionExportService.export(
                sessions: filteredSessions,
                format: format.serviceFormat
            )
            exportURL = url
            showShareSheet = true
        } catch {
            logger.error("Export failed: \(String(describing: error), privacy: .public)")
            exportErrorMessage = error.localizedDescription
            showExportError = true
        }
    }

    private func togglePlayback(for take: RunThroughModel) {
        if playingRunThroughID == take.id {
            runThroughPlayer?.stop()
            runThroughPlayer = nil
            playingRunThroughID = nil
            return
        }

        let url = URL(fileURLWithPath: take.audioFilePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            runThroughPlayer?.stop()
            runThroughPlayer = try AVAudioPlayer(contentsOf: url)
            runThroughPlayer?.prepareToPlay()
            runThroughPlayer?.play()
            playingRunThroughID = take.id
        } catch {
            runThroughPlayer = nil
            playingRunThroughID = nil
        }
    }

    private func deleteRunThroughs(offsets: IndexSet, from visible: [RunThroughModel]) {
        let toDelete = offsets.map { visible[$0] }
        for item in toDelete {
            if compareRunAID == item.id { compareRunAID = nil }
            if compareRunBID == item.id { compareRunBID = nil }
            if playingRunThroughID == item.id {
                runThroughPlayer?.stop()
                runThroughPlayer = nil
                playingRunThroughID = nil
            }
            let url = URL(fileURLWithPath: item.audioFilePath)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            PBLog.sessionStore.error("Delete save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteLoopLogs(offsets: IndexSet, from visible: [LoopPracticeLogModel]) {
        let toDelete = offsets.map { visible[$0] }
        for item in toDelete {
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            PBLog.sessionStore.error("Delete save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deletePlanLogs(offsets: IndexSet, from visible: [PracticePlanLogModel]) {
        let toDelete = offsets.map { visible[$0] }
        for item in toDelete {
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            PBLog.sessionStore.error("Delete save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteRhythmTakes(offsets: IndexSet, from visible: [RhythmAccuracyTakeModel]) {
        let toDelete = offsets.map { visible[$0] }
        for item in toDelete {
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            PBLog.sessionStore.error("Delete save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteIntonationTakes(offsets: IndexSet, from visible: [ScaleIntonationTakeModel]) {
        let toDelete = offsets.map { visible[$0] }
        for item in toDelete {
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            PBLog.sessionStore.error("Delete save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
