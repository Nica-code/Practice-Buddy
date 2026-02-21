import SwiftUI
import SwiftData
import os
import AVFoundation

struct HistoryView: View {

    private enum HistoryScope: String, CaseIterable, Identifiable {
        case all
        case today
        case week
        case month

        var id: String { rawValue }

        var title: String {
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
    @Query(sort: [SortDescriptor(\RunThroughModel.date, order: .reverse)]) private var runThroughs: [RunThroughModel]

    @State private var searchText: String = ""
    @State private var scope: HistoryScope = .all

    @State private var showExportOptions: Bool = false
    @State private var exportURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var exportErrorMessage: String? = nil
    @State private var showExportError: Bool = false
    @State private var showProLockedAlert: Bool = false

    @State private var selectedSheetID: SelectedID? = nil
    @State private var runThroughPlayer: AVAudioPlayer?
    @State private var playingRunThroughID: UUID?

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        List {
            scopePickerSection
            analyticsSection
            loopLogsSection
            planLogsSection
            rhythmLogsSection
            runThroughSection

            if filteredSessions.isEmpty {
                emptyStateRow
                    .listRowBackground(palette.surface)
            } else {
                Section {
                    ForEach(filteredSessions) { session in
                        sessionRow(session)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSheetID = SelectedID(id: session.id)
                            }
                            .listRowBackground(palette.surface)
                    }
                    .onDelete { offsets in
                        delete(offsets: offsets, from: filteredSessions)
                    }
                }
            }
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
                    if purchaseManager.isPro {
                        showExportOptions = true
                    } else {
                        showProLockedAlert = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
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
        .alert("PracticeBuddy Pro", isPresented: $showProLockedAlert) {
            Button("Not Now", role: .cancel) {}
            Button("Open Pro") {
                selectedTab = 3
            }
        } message: {
            Text("Export and advanced analytics are part of Pro.")
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

    @ViewBuilder
    private var analyticsSection: some View {
        Section("Analytics") {
            if purchaseManager.isPro {
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

                if let trend = loopTempoTrendText {
                    HStack {
                        Text("Loop tempo trend")
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(trend)
                            .font(type.number)
                            .foregroundStyle(palette.textSecondary)
                            .monospacedDigit()
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Advanced analytics is part of PracticeBuddy Pro.")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)
                    Button("Unlock Pro") {
                        selectedTab = 3
                    }
                    .font(type.button)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(palette.surface)
    }

    private var scopePickerSection: some View {
        Section {
            Picker("Scope", selection: $scope) {
                ForEach(HistoryScope.allCases) { s in
                    Text(s.title).tag(s)
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
                Text("Loop logs")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(filteredLoopLogs.count)")
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
                Text("Rhythm takes")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(filteredRhythmTakes.count)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            HStack {
                Text("Run-throughs")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(visibleRunThroughs.count)")
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
        }
        .listRowBackground(palette.surface)
    }

    private var loopLogsSection: some View {
        Section("Loop Sessions") {
            if filteredLoopLogs.isEmpty {
                Text("No loop logs in this scope yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(filteredLoopLogs.prefix(25)) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(log.date.formatted(date: .abbreviated, time: .shortened))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text("\(log.loopsCompleted) loops")
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("Work: \(DurationFormatter.string(from: log.totalWorkSeconds))")
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            if log.tempoStartBPM > 0 || log.tempoEndBPM > 0 {
                                Text("Tempo: \(log.tempoStartBPM)→\(log.tempoEndBPM)")
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
                    deleteLoopLogs(offsets: offsets, from: Array(filteredLoopLogs.prefix(25)))
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var planLogsSection: some View {
        Section("Guided Practice") {
            if filteredPlanLogs.isEmpty {
                Text("No guided practice logs in this scope yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(filteredPlanLogs.prefix(25)) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(log.date.formatted(date: .abbreviated, time: .shortened))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text("\(log.selfRating)/5")
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("Time: \(DurationFormatter.string(from: log.actualSeconds)) / \(log.targetMinutes)m target")
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                        }

                        let goals = parseCSV(log.goalsRaw)
                        if !goals.isEmpty {
                            Text("Goals: \(goals.joined(separator: ", "))")
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    deletePlanLogs(offsets: offsets, from: Array(filteredPlanLogs.prefix(25)))
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var rhythmLogsSection: some View {
        Section("Rhythm Accuracy") {
            if filteredRhythmTakes.isEmpty {
                Text("No rhythm takes in this scope yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(filteredRhythmTakes.prefix(25)) { take in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(take.date.formatted(date: .abbreviated, time: .shortened))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text("Score \(take.grooveScore)")
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("BPM \(take.bpm) • \(take.beatsAnalyzed) beats")
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            Text(String(format: "%+.1f ms", take.averageOffsetMs))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        if purchaseManager.isPro, !take.detailJSON.isEmpty {
                            let rows = take.detailJSON
                                .split(separator: "|")
                                .map { String($0) }
                            if let first = rows.first {
                                Text("Window 1: \(first)")
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    deleteRhythmTakes(offsets: offsets, from: Array(filteredRhythmTakes.prefix(25)))
                }
            }
        }
        .listRowBackground(palette.surface)
    }

    private var runThroughSection: some View {
        Section("Run-throughs") {
            if visibleRunThroughs.isEmpty {
                Text("No run-through takes in this scope yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(visibleRunThroughs) { take in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(take.date.formatted(date: .abbreviated, time: .shortened))
                                .font(type.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text("\(take.selfRating)/5")
                                .font(type.number)
                                .foregroundStyle(palette.textSecondary)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("Duration: \(DurationFormatter.string(from: take.durationSeconds))")
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            if take.usedMetronome {
                                Text("Metronome")
                                    .font(type.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
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
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    deleteRunThroughs(offsets: offsets, from: visibleRunThroughs)
                }

                if !purchaseManager.isPro, filteredRunThroughs.count > visibleRunThroughs.count {
                    Text("Free keeps only latest 3 run-through entries. Unlock Pro for full history.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
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

    private var emptyStateRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No sessions yet")
                .font(type.sectionTitle)
                .foregroundStyle(palette.textPrimary)

            Text("Start a timer on Home and save your first session.")
                .font(type.body)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.vertical, 10)
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

            if !session.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(session.noteTitle)
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
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
        var base = sessionsFilteredByScope(scope)

        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return base }

        let lowered = needle.lowercased()
        base = base.filter { session in
            let haystack = [
                session.notes,
                session.noteTitle,
                session.noteFocus,
                session.noteMoodRaw,
                session.noteStructuredJSON
            ]
            .joined(separator: "\n")
            .lowercased()

            return haystack.contains(lowered)
        }
        return base
    }

    private var filteredLoopLogs: [LoopPracticeLogModel] {
        let base = logsFilteredByScope(scope)
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return base }
        let lowered = needle.lowercased()
        return base.filter { log in
            log.tagsRaw.lowercased().contains(lowered)
        }
    }

    private var filteredPlanLogs: [PracticePlanLogModel] {
        let base = planLogsFilteredByScope(scope)
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return base }
        let lowered = needle.lowercased()
        return base.filter { log in
            [
                log.goalsRaw,
                log.blocksRaw,
                log.reflectionWins,
                log.reflectionFix,
                log.reflectionNext
            ]
            .joined(separator: "\n")
            .lowercased()
            .contains(lowered)
        }
    }

    private var filteredRhythmTakes: [RhythmAccuracyTakeModel] {
        let base = rhythmTakesFilteredByScope(scope)
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return base }
        let lowered = needle.lowercased()
        return base.filter { take in
            "\(take.bpm) \(take.grooveScore) \(take.averageOffsetMs) \(take.detailJSON)".lowercased().contains(lowered)
        }
    }

    private var filteredRunThroughs: [RunThroughModel] {
        let base = runThroughsFilteredByScope(scope)
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return base }
        let lowered = needle.lowercased()
        return base.filter { take in
            "\(take.notes) \(take.durationSeconds) \(take.selfRating)".lowercased().contains(lowered)
        }
    }

    private var visibleRunThroughs: [RunThroughModel] {
        if purchaseManager.isPro {
            return Array(filteredRunThroughs.prefix(25))
        }
        return Array(filteredRunThroughs.prefix(3))
    }

    private var loopTempoTrendText: String? {
        let logs = filteredLoopLogs.filter { $0.tempoStartBPM > 0 || $0.tempoEndBPM > 0 }
        guard logs.count >= 2 else { return nil }
        guard let newest = logs.first, let oldest = logs.last else { return nil }
        return "\(oldest.tempoStartBPM) → \(newest.tempoEndBPM) BPM"
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

    private func delete(offsets: IndexSet, from filtered: [PracticeSessionModel]) {
        let ids = offsets.map { filtered[$0].id }
        store.deleteSessions(withIDs: ids)
    }

    private func export(format: ExportFormat) {
        guard purchaseManager.isPro else {
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
        try? modelContext.save()
    }

    private func deleteLoopLogs(offsets: IndexSet, from visible: [LoopPracticeLogModel]) {
        let toDelete = offsets.map { visible[$0] }
        for item in toDelete {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    private func deletePlanLogs(offsets: IndexSet, from visible: [PracticePlanLogModel]) {
        let toDelete = offsets.map { visible[$0] }
        for item in toDelete {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    private func deleteRhythmTakes(offsets: IndexSet, from visible: [RhythmAccuracyTakeModel]) {
        let toDelete = offsets.map { visible[$0] }
        for item in toDelete {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}
