import SwiftUI
import os

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
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0

    @State private var searchText: String = ""
    @State private var scope: HistoryScope = .all

    @State private var showExportOptions: Bool = false
    @State private var exportURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var exportErrorMessage: String? = nil
    @State private var showExportError: Bool = false
    @State private var showProLockedAlert: Bool = false

    @State private var selectedSheetID: SelectedID? = nil

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        List {
            scopePickerSection
            analyticsSection

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
}
