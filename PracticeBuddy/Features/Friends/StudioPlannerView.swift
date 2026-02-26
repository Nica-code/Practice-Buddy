import SwiftUI
import FirebaseFirestore
import EventKit
import Combine

@MainActor
final class StudioPlannerViewModel: ObservableObject {
    @Published private(set) var studio: StudioInfo?
    @Published private(set) var members: [StudioMemberSummary] = []
    @Published private(set) var events: [StudioPlannerEvent] = []
    @Published private(set) var lessonTemplates: [StudioLessonTemplate] = []
    @Published private(set) var isLoading: Bool = false
    @Published var statusMessage: String?

    private let repository: FirebaseStudiosRepository
    private var studioListener: ListenerRegistration?
    private var membersListener: ListenerRegistration?
    private var eventsListener: ListenerRegistration?
    private var templatesListener: ListenerRegistration?
    private var currentUID: String?

    init(repository: FirebaseStudiosRepository? = nil) {
        self.repository = repository ?? FirebaseStudiosRepository()
    }

    deinit {
        studioListener?.remove()
        membersListener?.remove()
        eventsListener?.remove()
        templatesListener?.remove()
    }

    func start(for uid: String) {
        if currentUID == uid { return }
        stop()
        currentUID = uid
        isLoading = true

        studioListener = repository.listenToOwnedStudio(ownerUID: uid) { [weak self] studio in
            guard let self else { return }
            self.studio = studio
            self.isLoading = false
            self.attachMembersListener(studioID: studio?.id)
            self.attachEventsListener(studioID: studio?.id)
            self.attachTemplatesListener(studioID: studio?.id)
        }
    }

    func stop() {
        studioListener?.remove()
        membersListener?.remove()
        eventsListener?.remove()
        templatesListener?.remove()
        studioListener = nil
        membersListener = nil
        eventsListener = nil
        templatesListener = nil
        currentUID = nil
        studio = nil
        members = []
        events = []
        lessonTemplates = []
        isLoading = false
    }

    var studentMembers: [StudioMemberSummary] {
        members.filter { $0.role == .student }
    }

    func createEvent(
        type: StudioPlannerEventType,
        title: String,
        notes: String,
        location: String,
        startAt: Date,
        endAt: Date,
        participants: [StudioPlannerParticipant],
        syncToCalendar: Bool
    ) async -> StudioPlannerEvent? {
        guard let uid = currentUID else {
            statusMessage = "No active account."
            return nil
        }
        guard let studioID = studio?.id else {
            statusMessage = "Create a studio first in Studio Manager."
            return nil
        }
        do {
            let created = try await repository.createPlannerEvent(
                studioID: studioID,
                teacherUID: uid,
                type: type,
                rawTitle: title,
                rawNotes: notes,
                rawLocation: location,
                startAt: startAt,
                endAt: endAt,
                participants: participants,
                calendarSyncEnabled: syncToCalendar,
                calendarProvider: syncToCalendar ? "apple_calendar" : nil,
                externalEventID: nil
            )
            statusMessage = "Event created."
            return created
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func attachExternalCalendarEventID(_ externalID: String?, eventID: String) async {
        guard let studioID = studio?.id else { return }
        do {
            try await repository.updatePlannerEventExternalID(
                studioID: studioID,
                eventID: eventID,
                externalEventID: externalID
            )
        } catch {
            statusMessage = "Calendar link save failed: \(error.localizedDescription)"
        }
    }

    func deleteEvent(_ eventID: String) async {
        guard let studioID = studio?.id else { return }
        do {
            try await repository.deletePlannerEvent(studioID: studioID, eventID: eventID)
            statusMessage = "Event deleted."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateEvent(
        eventID: String,
        type: StudioPlannerEventType,
        title: String,
        notes: String,
        location: String,
        startAt: Date,
        endAt: Date,
        participants: [StudioPlannerParticipant],
        calendarSyncEnabled: Bool
    ) async {
        guard let studioID = studio?.id else { return }
        do {
            try await repository.updatePlannerEvent(
                studioID: studioID,
                eventID: eventID,
                type: type,
                rawTitle: title,
                rawNotes: notes,
                rawLocation: location,
                startAt: startAt,
                endAt: endAt,
                participants: participants,
                calendarSyncEnabled: calendarSyncEnabled
            )
            statusMessage = "Event updated."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createLessonTemplate(
        title: String,
        notes: String,
        location: String,
        weekday: Int,
        startHour: Int,
        startMinute: Int,
        durationMinutes: Int,
        participants: [StudioPlannerParticipant]
    ) async {
        guard let uid = currentUID else { return }
        guard let studioID = studio?.id else { return }
        do {
            try await repository.createLessonTemplate(
                studioID: studioID,
                teacherUID: uid,
                rawTitle: title,
                rawNotes: notes,
                rawLocation: location,
                weekday: weekday,
                startHour: startHour,
                startMinute: startMinute,
                durationMinutes: durationMinutes,
                participants: participants
            )
            statusMessage = "Lesson template saved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteLessonTemplate(_ templateID: String) async {
        guard let studioID = studio?.id else { return }
        do {
            try await repository.deleteLessonTemplate(studioID: studioID, templateID: templateID)
            statusMessage = "Lesson template deleted."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func attachMembersListener(studioID: String?) {
        membersListener?.remove()
        membersListener = nil
        members = []
        guard let studioID else { return }
        membersListener = repository.listenToMembers(studioID: studioID) { [weak self] rows in
            self?.members = rows
        }
    }

    private func attachEventsListener(studioID: String?) {
        eventsListener?.remove()
        eventsListener = nil
        events = []
        guard let studioID else { return }
        eventsListener = repository.listenToPlannerEvents(studioID: studioID) { [weak self] rows in
            self?.events = rows
        }
    }

    private func attachTemplatesListener(studioID: String?) {
        templatesListener?.remove()
        templatesListener = nil
        lessonTemplates = []
        guard let studioID else { return }
        templatesListener = repository.listenToLessonTemplates(studioID: studioID) { [weak self] rows in
            self?.lessonTemplates = rows
        }
    }
}

enum StudioPlannerCalendarError: LocalizedError {
    case permissionDenied
    case noCalendar

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Calendar permission denied."
        case .noCalendar: return "No writable calendar available."
        }
    }
}

final class StudioPlannerCalendarSync {
    static let shared = StudioPlannerCalendarSync()
    private let store = EKEventStore()

    private init() {}

    func addToCalendar(_ event: StudioPlannerEvent) async throws -> String {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(to: .event) { ok, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ok)
                    }
                }
            }
        }
        guard granted else { throw StudioPlannerCalendarError.permissionDenied }

        let calendarEvent = EKEvent(eventStore: store)
        calendarEvent.title = event.title
        calendarEvent.startDate = event.startAt
        calendarEvent.endDate = event.endAt
        calendarEvent.location = event.location

        var noteParts: [String] = []
        if !event.notes.isEmpty {
            noteParts.append(event.notes)
        }
        if !event.participants.isEmpty {
            let names = event.participants.map { $0.displayName }.joined(separator: ", ")
            noteParts.append("Students: \(names)")
        }
        calendarEvent.notes = noteParts.joined(separator: "\n\n")

        guard let calendar = store.defaultCalendarForNewEvents else {
            throw StudioPlannerCalendarError.noCalendar
        }
        calendarEvent.calendar = calendar
        try store.save(calendarEvent, span: .thisEvent)
        return calendarEvent.eventIdentifier ?? ""
    }
}

struct StudioPlannerView: View {
    private enum EventTypeFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case lesson = "Lesson"
        case studioClass = "Studio Class"
        case recital = "Recital"
        var id: String { rawValue }
    }

    private enum EventDateFilter: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming"
        case next7Days = "Next 7 Days"
        case thisMonth = "This Month"
        case all = "All Dates"
        var id: String { rawValue }
    }

    @EnvironmentObject private var firebase: FirebaseBootstrap
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = StudioPlannerViewModel()

    @State private var eventType: StudioPlannerEventType = .lesson
    @State private var titleInput: String = ""
    @State private var notesInput: String = ""
    @State private var locationInput: String = ""
    @State private var startAt: Date = Date().addingTimeInterval(3600)
    @State private var endAt: Date = Date().addingTimeInterval(5400)
    @State private var selectedStudentIDs: Set<String> = []
    @State private var pieceByStudent: [String: String] = [:]
    @State private var durationByStudent: [String: Int] = [:]
    @State private var syncToCalendar: Bool = true
    @State private var showComposer = false
    @State private var typeFilter: EventTypeFilter = .all
    @State private var dateFilter: EventDateFilter = .upcoming
    @State private var editingEvent: StudioPlannerEvent?
    @State private var templateWeekday: Int = Calendar.current.component(.weekday, from: Date())

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard

                if viewModel.isLoading {
                    ProgressView("Loading planner…")
                } else if viewModel.studio == nil {
                    emptyStateCard
                } else {
                    composerCard
                    templatesCard
                    filtersCard
                    eventsCard
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, PBLayout.padXL)
        }
        .background(theme.background.ignoresSafeArea())
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: firebase.currentUserID) {
            guard let uid = firebase.currentUserID else { return }
            viewModel.start(for: uid)
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: viewModel.studentMembers.map(\.id)) { _, ids in
            selectedStudentIDs = selectedStudentIDs.filter { ids.contains($0) }
        }
        .sheet(item: $editingEvent) { event in
            NavigationStack {
                plannerEditSheet(for: event)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Studio Planner")
                .font(type.sectionTitle)
                .foregroundStyle(theme.textPrimary)
            Text("Plan lessons, studio classes, and recitals. Assign students and sync events to Calendar.")
                .font(type.body)
                .foregroundStyle(theme.textSecondary)
            if let msg = viewModel.statusMessage, !msg.isEmpty {
                Text(LocalizedStringKey(msg))
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No studio found.")
                .font(type.body)
                .foregroundStyle(theme.textPrimary)
            Text("Create your studio first in Studio Manager, then come back to schedule events.")
                .font(type.footnote)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                    showComposer.toggle()
                }
            } label: {
                Label(showComposer ? "Hide Event Composer" : "New Event", systemImage: "plus.circle")
                    .font(type.body)
                    .foregroundStyle(theme.textPrimary)
            }
            .buttonStyle(.plain)

            if showComposer {
                Picker("Type", selection: $eventType) {
                    ForEach(StudioPlannerEventType.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Event title", text: $titleInput)
                    .font(type.body)
                    .padding(10)
                    .pbSurfaceCard(palette: palette)

                TextField("Notes (optional)", text: $notesInput, axis: .vertical)
                    .font(type.body)
                    .lineLimit(2...4)
                    .padding(10)
                    .pbSurfaceCard(palette: palette)

                TextField("Location (optional)", text: $locationInput)
                    .font(type.body)
                    .padding(10)
                    .pbSurfaceCard(palette: palette)

                DatePicker("Start", selection: $startAt)
                    .font(type.body)
                DatePicker("End", selection: $endAt)
                    .font(type.body)

                if !viewModel.studentMembers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Assign Students")
                            .font(type.footnote)
                            .foregroundStyle(theme.textSecondary)

                        ForEach(viewModel.studentMembers) { student in
                            let isSelected = selectedStudentIDs.contains(student.id)
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    if isSelected {
                                        selectedStudentIDs.remove(student.id)
                                    } else {
                                        selectedStudentIDs.insert(student.id)
                                    }
                                } label: {
                                    HStack {
                                        Text(student.displayName)
                                            .font(type.body)
                                            .foregroundStyle(theme.textPrimary)
                                        Spacer()
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                if isSelected {
                                    TextField("Piece (optional)", text: Binding(
                                        get: { pieceByStudent[student.id, default: ""] },
                                        set: { pieceByStudent[student.id] = $0 }
                                    ))
                                    .font(type.footnote)
                                    Stepper(value: Binding(
                                        get: { durationByStudent[student.id, default: 0] },
                                        set: { durationByStudent[student.id] = $0 }
                                    ), in: 0...60, step: 1) {
                                        Text(L10n.f("Duration: %@ min", "\(durationByStudent[student.id, default: 0])"))
                                            .font(type.footnote)
                                            .foregroundStyle(theme.textSecondary)
                                    }
                                }
                            }
                            .padding(10)
                            .pbSurfaceCard(palette: palette)
                        }
                    }
                }

                Toggle("Sync to Apple Calendar", isOn: $syncToCalendar)
                    .font(type.body)

                HStack(spacing: 8) {
                    Button("Create Event") {
                        Task { await saveEvent() }
                    }
                    .buttonStyle(.borderedProminent)

                    if eventType == .lesson {
                        Button("Save Recurring Template") {
                            templateWeekday = Calendar.current.component(.weekday, from: startAt)
                            Task { await saveLessonTemplateFromComposer() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
    }

    private var templatesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recurring Lesson Templates")
                .font(type.body)
                .foregroundStyle(theme.textPrimary)

            if viewModel.lessonTemplates.isEmpty {
                Text("No recurring templates yet.")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pbSurfaceCard(palette: palette)
            } else {
                ForEach(viewModel.lessonTemplates) { template in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(template.title)
                                .font(type.body)
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Text(weekdayTitle(template.weekday))
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Text(
                            L10n.f(
                                "%@ • %@ min",
                                String(format: "%02d:%02d", template.startHour, template.startMinute),
                                "\(template.durationMinutes)"
                            )
                        )
                        .font(type.footnote)
                        .foregroundStyle(theme.textSecondary)
                        HStack(spacing: 8) {
                            Button("Use") {
                                applyTemplate(template)
                            }
                            .buttonStyle(.bordered)
                            .font(type.footnote)
                            Button("Schedule Next") {
                                Task { await scheduleNextFromTemplate(template) }
                            }
                            .buttonStyle(.borderedProminent)
                            .font(type.footnote)
                            Spacer()
                            Button("Delete", role: .destructive) {
                                Task { await viewModel.deleteLessonTemplate(template.id) }
                            }
                            .buttonStyle(.bordered)
                            .font(type.footnote)
                        }
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
    }

    private var filtersCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Event Filters")
                .font(type.body)
                .foregroundStyle(theme.textPrimary)

            Picker("Type", selection: $typeFilter) {
                ForEach(EventTypeFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Picker("Date", selection: $dateFilter) {
                ForEach(EventDateFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
    }

    private var eventsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upcoming Events")
                .font(type.body)
                .foregroundStyle(theme.textPrimary)

            if filteredEvents.isEmpty {
                Text("No upcoming events.")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pbSurfaceCard(palette: palette)
            } else {
                ForEach(filteredEvents) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(event.title)
                                .font(type.body)
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Text(event.type.title)
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Text(L10n.f("%@ - %@", event.startAt.formatted(date: .abbreviated, time: .shortened), event.endAt.formatted(date: .omitted, time: .shortened)))
                            .font(type.footnote)
                            .foregroundStyle(theme.textSecondary)
                        if !event.location.isEmpty {
                            Text(event.location)
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                        if !event.participants.isEmpty {
                            Text(L10n.f("Students: %@", event.participants.map { $0.displayName }.joined(separator: ", ")))
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                        HStack(spacing: 8) {
                            Button("Edit") {
                                editingEvent = event
                            }
                            .buttonStyle(.bordered)
                            .font(type.footnote)
                            if event.externalEventID == nil {
                                Button("Add to Calendar") {
                                    Task { await addEventToCalendar(event) }
                                }
                                .buttonStyle(.bordered)
                                .font(type.footnote)
                            } else {
                                Text("Synced to Calendar")
                                    .font(type.footnote)
                                    .foregroundStyle(theme.accent)
                            }
                            Spacer()
                            Button("Delete", role: .destructive) {
                                Task { await viewModel.deleteEvent(event.id) }
                            }
                            .buttonStyle(.bordered)
                            .font(type.footnote)
                        }
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
    }

    private var filteredEvents: [StudioPlannerEvent] {
        viewModel.events.filter { event in
            let typeMatches: Bool = {
                switch typeFilter {
                case .all: return true
                case .lesson: return event.type == .lesson
                case .studioClass: return event.type == .studioClass
                case .recital: return event.type == .recital
                }
            }()
            let dateMatches: Bool = {
                let now = Date()
                switch dateFilter {
                case .all: return true
                case .upcoming: return event.endAt >= now
                case .next7Days:
                    let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
                    return event.startAt >= now && event.startAt <= end
                case .thisMonth:
                    let cal = Calendar.current
                    let month = cal.component(.month, from: now)
                    let year = cal.component(.year, from: now)
                    return cal.component(.month, from: event.startAt) == month &&
                        cal.component(.year, from: event.startAt) == year
                }
            }()
            return typeMatches && dateMatches
        }
    }

    @ViewBuilder
    private func plannerEditSheet(for event: StudioPlannerEvent) -> some View {
        Form {
            Section("Event") {
                Picker("Type", selection: Binding(
                    get: { eventType },
                    set: { eventType = $0 }
                )) {
                    ForEach(StudioPlannerEventType.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                TextField("Event title", text: $titleInput)
                TextField("Notes (optional)", text: $notesInput, axis: .vertical)
                TextField("Location (optional)", text: $locationInput)
                DatePicker("Start", selection: $startAt)
                DatePicker("End", selection: $endAt)
                Toggle("Sync to Apple Calendar", isOn: $syncToCalendar)
            }
        }
        .navigationTitle("Edit Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    editingEvent = nil
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        let participants = viewModel.studentMembers
                            .filter { selectedStudentIDs.contains($0.id) }
                            .map {
                                StudioPlannerParticipant(
                                    id: $0.id,
                                    displayName: $0.displayName,
                                    pieceTitle: pieceByStudent[$0.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines),
                                    durationMinutes: max(0, durationByStudent[$0.id, default: 0])
                                )
                            }
                        await viewModel.updateEvent(
                            eventID: event.id,
                            type: eventType,
                            title: titleInput,
                            notes: notesInput,
                            location: locationInput,
                            startAt: startAt,
                            endAt: endAt,
                            participants: participants,
                            calendarSyncEnabled: syncToCalendar
                        )
                        editingEvent = nil
                    }
                }
            }
        }
        .onAppear {
            eventType = event.type
            titleInput = event.title
            notesInput = event.notes
            locationInput = event.location
            startAt = event.startAt
            endAt = event.endAt
            syncToCalendar = event.calendarSyncEnabled
            selectedStudentIDs = Set(event.participants.map(\.id))
            pieceByStudent = Dictionary(uniqueKeysWithValues: event.participants.map { ($0.id, $0.pieceTitle) })
            durationByStudent = Dictionary(uniqueKeysWithValues: event.participants.map { ($0.id, $0.durationMinutes) })
        }
    }

    private func weekdayTitle(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let idx = max(1, min(7, weekday)) - 1
        return symbols[idx]
    }

    private func nextDate(
        forWeekday weekday: Int,
        hour: Int,
        minute: Int
    ) -> Date {
        let cal = Calendar.current
        var comp = DateComponents()
        comp.weekday = weekday
        comp.hour = hour
        comp.minute = minute
        let now = Date()
        let next = cal.nextDate(after: now, matching: comp, matchingPolicy: .nextTimePreservingSmallerComponents) ?? now
        return next
    }

    private func applyTemplate(_ template: StudioLessonTemplate) {
        eventType = .lesson
        titleInput = template.title
        notesInput = template.notes
        locationInput = template.location
        startAt = nextDate(forWeekday: template.weekday, hour: template.startHour, minute: template.startMinute)
        endAt = startAt.addingTimeInterval(TimeInterval(template.durationMinutes * 60))
        selectedStudentIDs = Set(template.participants.map(\.id))
        pieceByStudent = Dictionary(uniqueKeysWithValues: template.participants.map { ($0.id, $0.pieceTitle) })
        durationByStudent = Dictionary(uniqueKeysWithValues: template.participants.map { ($0.id, $0.durationMinutes) })
        showComposer = true
        viewModel.statusMessage = "Template loaded."
    }

    private func scheduleNextFromTemplate(_ template: StudioLessonTemplate) async {
        let start = nextDate(forWeekday: template.weekday, hour: template.startHour, minute: template.startMinute)
        let end = start.addingTimeInterval(TimeInterval(template.durationMinutes * 60))
        guard let created = await viewModel.createEvent(
            type: .lesson,
            title: template.title,
            notes: template.notes,
            location: template.location,
            startAt: start,
            endAt: end,
            participants: template.participants,
            syncToCalendar: true
        ) else { return }
        do {
            let externalID = try await StudioPlannerCalendarSync.shared.addToCalendar(created)
            await viewModel.attachExternalCalendarEventID(externalID, eventID: created.id)
            viewModel.statusMessage = "Next lesson scheduled and synced."
        } catch {
            viewModel.statusMessage = "Lesson scheduled, calendar sync failed: \(error.localizedDescription)"
        }
    }

    private func saveLessonTemplateFromComposer() async {
        let participants: [StudioPlannerParticipant] = viewModel.studentMembers
            .filter { selectedStudentIDs.contains($0.id) }
            .map {
                StudioPlannerParticipant(
                    id: $0.id,
                    displayName: $0.displayName,
                    pieceTitle: pieceByStudent[$0.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines),
                    durationMinutes: max(0, durationByStudent[$0.id, default: 0])
                )
            }
        let duration = max(1, Int(endAt.timeIntervalSince(startAt) / 60))
        await viewModel.createLessonTemplate(
            title: titleInput,
            notes: notesInput,
            location: locationInput,
            weekday: templateWeekday,
            startHour: Calendar.current.component(.hour, from: startAt),
            startMinute: Calendar.current.component(.minute, from: startAt),
            durationMinutes: duration,
            participants: participants
        )
    }

    private func saveEvent() async {
        let participants: [StudioPlannerParticipant] = viewModel.studentMembers
            .filter { selectedStudentIDs.contains($0.id) }
            .map {
                StudioPlannerParticipant(
                    id: $0.id,
                    displayName: $0.displayName,
                    pieceTitle: pieceByStudent[$0.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines),
                    durationMinutes: max(0, durationByStudent[$0.id, default: 0])
                )
            }

        guard let created = await viewModel.createEvent(
            type: eventType,
            title: titleInput,
            notes: notesInput,
            location: locationInput,
            startAt: startAt,
            endAt: endAt,
            participants: participants,
            syncToCalendar: syncToCalendar
        ) else { return }

        if syncToCalendar {
            do {
                let externalID = try await StudioPlannerCalendarSync.shared.addToCalendar(created)
                await viewModel.attachExternalCalendarEventID(externalID, eventID: created.id)
                viewModel.statusMessage = "Event created and synced to Calendar."
            } catch {
                viewModel.statusMessage = "Event created, but calendar sync failed: \(error.localizedDescription)"
            }
        }

        titleInput = ""
        notesInput = ""
        locationInput = ""
        selectedStudentIDs = []
        pieceByStudent = [:]
        durationByStudent = [:]
        showComposer = false
    }

    private func addEventToCalendar(_ event: StudioPlannerEvent) async {
        do {
            let externalID = try await StudioPlannerCalendarSync.shared.addToCalendar(event)
            await viewModel.attachExternalCalendarEventID(externalID, eventID: event.id)
            viewModel.statusMessage = "Event synced to Calendar."
        } catch {
            viewModel.statusMessage = "Calendar sync failed: \(error.localizedDescription)"
        }
    }
}
