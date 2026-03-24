import SwiftUI
import UIKit

struct StudioManagerView: View {
    enum EntryMode {
        case teacher
        case student
    }

    private enum AssignmentQuickFilter: String, CaseIterable, Identifiable {
        case active = "Active"
        case dueSoon = "Due Soon"
        case overdue = "Overdue"
        case completed = "Completed"
        case all = "All"

        var id: String { rawValue }
        var titleKey: String { rawValue }
    }

    private enum TeacherPanel: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case assignments = "Assignments"
        case warmups = "Warm-ups"
        case roster = "Roster"

        var id: String { rawValue }
        var titleKey: String { rawValue }
    }

    private enum StudentPanel: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case assignments = "Assignments"
        case roster = "Roster"

        var id: String { rawValue }
        var titleKey: String { rawValue }
    }

    private enum StudioToolMode: String, CaseIterable, Identifiable {
        case teacher = "Teacher Tools"
        case student = "Student Tools"
        var id: String { rawValue }
    }

    private enum AssignmentAudience: String, CaseIterable, Identifiable {
        case studio
        case individual
        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .studio: return "Whole Studio"
            case .individual: return "Individual"
            }
        }
    }

    private enum WarmupAudience: String, CaseIterable, Identifiable {
        case studio
        case individual
        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .studio: return "Whole Studio"
            case .individual: return "Individual"
            }
        }
    }

    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel = StudioManagerViewModel()
    @State private var studioNameInput: String = ""
    @State private var inviteCodeInput: String = ""
    @State private var assignmentTitleInput: String = ""
    @State private var assignmentDetailsInput: String = ""
    @State private var assignmentDueAt: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var assignmentAudience: AssignmentAudience = .studio
    @State private var selectedStudentUID: String = ""
    @State private var warmupAudience: WarmupAudience = .studio
    @State private var warmupStudentUID: String = ""
    @State private var warmupTitleInput: String = ""
    @State private var warmupInstrumentInput: String = "Strings"
    @State private var warmupFocusInput: String = ""
    @State private var warmupMinutesInput: Int = 10
    @State private var warmupStepsInput: String = ""
    @State private var teacherAssignmentFilter: StudioManagerViewModel.AssignmentFilter = .all
    @State private var editingAssignment: StudioAssignment?
    @State private var showDeleteConfirm = false
    @State private var assignmentPendingDelete: StudioAssignment?

    @State private var editTitleInput: String = ""
    @State private var editDetailsInput: String = ""
    @State private var editDueAt: Date = Date()
    @State private var editAudience: AssignmentAudience = .studio
    @State private var editSelectedStudentUID: String = ""
    @State private var studioToolMode: StudioToolMode = .teacher
    @State private var teacherPanel: TeacherPanel = .overview
    @State private var studentPanel: StudentPanel = .overview
    @State private var showAssignmentComposer: Bool = false
    @State private var showWarmupComposer: Bool = false
    @State private var teacherAssignmentQuickFilter: AssignmentQuickFilter = .active
    @State private var studentAssignmentQuickFilter: AssignmentQuickFilter = .active
    @State private var showOlderTeacherAssignments: Bool = false
    @State private var showOlderStudentAssignments: Bool = false
    private let entryMode: EntryMode?

    init(entryMode: EntryMode? = nil) {
        self.entryMode = entryMode
        switch entryMode {
        case .student:
            _studioToolMode = State(initialValue: .student)
        case .teacher, .none:
            _studioToolMode = State(initialValue: .teacher)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                mainContent
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, PBLayout.padXL)
        }
        .background(theme.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: firebase.currentUserID) {
            guard let uid = firebase.currentUserID else { return }
            viewModel.start(for: uid, role: studioToolMode == .teacher ? .teacher : .student)
        }
        .onChange(of: studioToolMode) { _, newMode in
            guard let uid = firebase.currentUserID else { return }
            if newMode == .teacher {
                teacherPanel = .overview
            } else {
                studentPanel = .overview
            }
            viewModel.start(for: uid, role: newMode == .teacher ? .teacher : .student)
        }
        .onChange(of: viewModel.studentMembers.map(\.id)) { _, ids in
            if assignmentAudience == .individual, !ids.contains(selectedStudentUID) {
                selectedStudentUID = ids.first ?? ""
            }
            if warmupAudience == .individual, !ids.contains(warmupStudentUID) {
                warmupStudentUID = ids.first ?? ""
            }
        }
        .onDisappear {
            viewModel.stop()
        }
        .sheet(item: $editingAssignment) { assignment in
            assignmentEditSheet(for: assignment)
        }
        .alert("Delete Assignment?", isPresented: $showDeleteConfirm, presenting: assignmentPendingDelete) { assignment in
            Button("Cancel", role: .cancel) {
                assignmentPendingDelete = nil
            }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteAssignment(assignment.id)
                    assignmentPendingDelete = nil
                }
            }
        } message: { assignment in
            Text(L10n.f("Delete assignment \"%@\"?", assignment.title))
        }
    }

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var showsRoleModePicker: Bool { entryMode == nil }

    @ViewBuilder
    private var mainContent: some View {
        if !purchaseManager.featuresUnlocked {
            lockedCard
        } else {
            if showsRoleModePicker {
                roleModePicker
            }
            if studioToolMode == .teacher {
                teacherContentCard
            } else {
                studentContentCard
            }
        }
    }

    @ViewBuilder
    private var roleModePicker: some View {
        Picker("Studio Mode", selection: $studioToolMode) {
            ForEach(StudioToolMode.allCases) { mode in
                Text(LocalizedStringKey(mode.rawValue)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 2)
    }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Studio Manager")
                .font(type.sectionTitle)
                .foregroundStyle(theme.textPrimary)

            Text("Studio tools are currently unavailable for this account.")
                .font(type.body)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
    }

    private var teacherContentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Studio Manager")
                .font(type.sectionTitle)
                .foregroundStyle(theme.textPrimary)

            if viewModel.isLoading {
                Text("Loading studio…")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
            } else if let studio = viewModel.studio {
                studioHeader(studio)
                teacherPanelPicker
                teacherPanelContent
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create your studio to start inviting students.")
                        .font(type.body)
                        .foregroundStyle(theme.textSecondary)

                    TextField("Studio name", text: $studioNameInput)
                        .font(type.body)
                        .padding(10)
                        .pbSurfaceCard(palette: palette)

                    Button("Create Studio") {
                        Task { await viewModel.createStudio(name: studioNameInput) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

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

    private var studentContentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Studio")
                .font(type.sectionTitle)
                .foregroundStyle(theme.textPrimary)

            if viewModel.isLoading {
                Text("Loading studio…")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
            } else if let studio = viewModel.studio {
                studioHeader(studio)
                studentPanelPicker
                studentPanelContent
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Join your teacher's studio using an invite code.")
                        .font(type.body)
                        .foregroundStyle(theme.textSecondary)

                    TextField("Invite code (ABC-123)", text: $inviteCodeInput)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .font(type.body)
                        .padding(10)
                        .pbSurfaceCard(palette: palette)

                    Button("Join Studio") {
                        let code = inviteCodeInput
                        inviteCodeInput = ""
                        Task { await viewModel.joinStudio(inviteCode: code) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

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

    private var teacherPanelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TeacherPanel.allCases) { panel in
                    Button {
                        teacherPanel = panel
                    } label: {
                        Text(LocalizedStringKey(panel.titleKey))
                            .font(type.footnote)
                            .foregroundStyle(
                                teacherPanel == panel ? Color.black : theme.textPrimary
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(teacherPanel == panel ? theme.accent : theme.surfaceAlt)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var teacherPanelContent: some View {
        switch teacherPanel {
        case .overview:
            studioOverviewCards
        case .assignments:
            teacherAssignmentsSection
        case .warmups:
            teacherWarmupPublisherSection
        case .roster:
            memberList
        }
    }

    private var studentPanelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StudentPanel.allCases) { panel in
                    Button {
                        studentPanel = panel
                    } label: {
                        Text(LocalizedStringKey(panel.titleKey))
                            .font(type.footnote)
                            .foregroundStyle(
                                studentPanel == panel ? Color.black : theme.textPrimary
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(studentPanel == panel ? theme.accent : theme.surfaceAlt)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var studentPanelContent: some View {
        switch studentPanel {
        case .overview:
            studioOverviewCards
        case .assignments:
            studentAssignmentsSection
        case .roster:
            memberList
        }
    }

    private var studioOverviewCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(type.body)
                .foregroundStyle(theme.textPrimary)
            HStack(spacing: 8) {
                overviewCard(title: "Members", value: "\(viewModel.members.count)")
                overviewCard(title: "Assignments", value: "\(viewModel.visibleAssignmentsForCurrentRole.count)")
            }
            HStack(spacing: 8) {
                overviewCard(
                    title: "Completed",
                    value: "\(viewModel.myAssignmentCompletion.values.filter({ $0 }).count)"
                )
                overviewCard(
                    title: "Pending",
                    value: "\(max(0, viewModel.visibleAssignmentsForCurrentRole.count - viewModel.myAssignmentCompletion.values.filter({ $0 }).count))"
                )
            }
        }
    }

    private func overviewCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(type.footnote)
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(type.number)
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .pbSurfaceCard(palette: palette)
    }

    @ViewBuilder
    private func studioHeader(_ studio: StudioInfo) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(studio.name)
                    .font(type.body)
                    .foregroundStyle(theme.textPrimary)
                Text("Invite link ready")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
            if let inviteURL = inviteURL(for: studio.inviteCode) {
                ShareLink(item: inviteURL) {
                    Text("Share")
                        .font(type.footnote)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent)
            }
        }
        .padding(10)
        .pbSurfaceCard(palette: palette)
    }

    private func inviteURL(for code: String) -> URL? {
        if let base = AppInfo.inviteLinkBaseURL,
           var components = URLComponents(url: base, resolvingAgainstBaseURL: false) {
            var path = components.path
            if path.hasSuffix("/") {
                path.removeLast()
            }
            components.path = "\(path)/join-studio"
            components.queryItems = [URLQueryItem(name: "code", value: code)]
            if let url = components.url {
                return url
            }
        }

        var fallback = URLComponents()
        fallback.scheme = "practicebuddy"
        fallback.host = "join-studio"
        fallback.queryItems = [URLQueryItem(name: "code", value: code)]
        return fallback.url
    }

    private var memberList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Roster")
                .font(type.body)
                .foregroundStyle(theme.textPrimary)

            if viewModel.members.isEmpty {
                Text("No members yet.")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pbSurfaceCard(palette: palette)
            } else {
                ForEach(viewModel.members) { member in
                    HStack {
                        PBAvatarView(avatarID: member.avatarID, displayName: member.displayName, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                                .font(type.body)
                                .foregroundStyle(theme.textPrimary)
                            HStack(spacing: 6) {
                                Text(LocalizedStringKey(member.role.rawValue.capitalized))
                                    .font(type.footnote)
                                    .foregroundStyle(theme.textSecondary)
                                PBLevelBadgeView(level: member.publicLevel)
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }
            }
        }
    }


    private var teacherAssignmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Assignments")
                .font(type.body)
                .foregroundStyle(theme.textPrimary)

            Picker("Filter", selection: $teacherAssignmentFilter) {
                ForEach(StudioManagerViewModel.AssignmentFilter.allCases) { filter in
                    Text(LocalizedStringKey(filter.titleKey)).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            assignmentQuickFilterChips(
                selection: $teacherAssignmentQuickFilter,
                countFor: teacherQuickFilterCount(for:)
            )

            DisclosureGroup(isExpanded: $showAssignmentComposer) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Assignment title", text: $assignmentTitleInput)
                        .font(type.body)
                        .padding(10)
                        .pbSurfaceCard(palette: palette)

                    TextField("Details (optional)", text: $assignmentDetailsInput, axis: .vertical)
                        .font(type.body)
                        .lineLimit(2...4)
                        .padding(10)
                        .pbSurfaceCard(palette: palette)

                    DatePicker("Due", selection: $assignmentDueAt, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .font(type.body)
                        .foregroundStyle(theme.textPrimary)

                    Picker("Assign To", selection: $assignmentAudience) {
                        ForEach(AssignmentAudience.allCases) { mode in
                            Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if assignmentAudience == .individual {
                        if viewModel.studentMembers.isEmpty {
                            Text("No students in roster yet.")
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        } else {
                            studentSelectionList(selectedID: $selectedStudentUID)
                        }
                    }

                    Button("Create Assignment") {
                        let title = assignmentTitleInput
                        let details = assignmentDetailsInput
                        let due = assignmentDueAt
                        Task {
                            switch assignmentAudience {
                            case .studio:
                                await viewModel.createStudioWideAssignment(title: title, details: details, dueAt: due)
                            case .individual:
                                guard let student = viewModel.studentMembers.first(where: { $0.id == selectedStudentUID }) else {
                                    viewModel.statusMessage = "Select a student."
                                    return
                                }
                                await viewModel.createIndividualAssignment(
                                    title: title,
                                    details: details,
                                    dueAt: due,
                                    studentUID: student.id,
                                    studentName: student.displayName
                                )
                            }
                            assignmentTitleInput = ""
                            assignmentDetailsInput = ""
                            showAssignmentComposer = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            } label: {
                Label(showAssignmentComposer ? "Hide Assignment Composer" : "New Assignment", systemImage: "plus.circle")
                    .font(type.body)
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(10)
            .pbSurfaceCard(palette: palette)

            let filtered = filteredTeacherAssignments
            let recent = Array(filtered.prefix(8))
            let older = Array(filtered.dropFirst(8))
            if filtered.isEmpty {
                Text("No assignments yet.")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pbSurfaceCard(palette: palette)
            } else {
                ForEach(recent) { assignment in
                    teacherAssignmentRow(assignment)
                }

                if !older.isEmpty {
                    DisclosureGroup(isExpanded: $showOlderTeacherAssignments) {
                        VStack(spacing: 8) {
                            ForEach(older) { assignment in
                                teacherAssignmentRow(assignment)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text(L10n.f("Older assignments (%@)", "\(older.count)"))
                            .font(type.footnote)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }
            }
        }
    }

    private var teacherWarmupPublisherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Studio Warm-up Publisher")
                .font(type.body)
                .foregroundStyle(theme.textPrimary)

            DisclosureGroup(isExpanded: $showWarmupComposer) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Warm-up title", text: $warmupTitleInput)
                        .font(type.body)
                        .padding(10)
                        .pbSurfaceCard(palette: palette)

                    TextField("Instrument (e.g. Strings)", text: $warmupInstrumentInput)
                        .font(type.body)
                        .padding(10)
                        .pbSurfaceCard(palette: palette)

                    TextField("Focus (e.g. Intonation, shifts)", text: $warmupFocusInput)
                        .font(type.body)
                        .padding(10)
                        .pbSurfaceCard(palette: palette)

                    Stepper(value: $warmupMinutesInput, in: 5...60, step: 5) {
                        HStack {
                            Text("Total time")
                                .font(type.body)
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            Text(L10n.f("%@ min", "\(warmupMinutesInput)"))
                                .font(type.number)
                                .foregroundStyle(theme.textSecondary)
                                .monospacedDigit()
                        }
                    }

                    Picker("Assign To", selection: $warmupAudience) {
                        ForEach(WarmupAudience.allCases) { mode in
                            Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if warmupAudience == .individual {
                        if viewModel.studentMembers.isEmpty {
                            Text("No students in roster yet.")
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        } else {
                            studentSelectionList(selectedID: $warmupStudentUID)
                        }
                    }

                    TextField("Steps (one step per line)", text: $warmupStepsInput, axis: .vertical)
                        .font(type.body)
                        .lineLimit(4...8)
                        .padding(10)
                        .pbSurfaceCard(palette: palette)

                    Button("Publish Warm-up") {
                        let title = warmupTitleInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let instrument = warmupInstrumentInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let focus = warmupFocusInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let steps = warmupStepsInput
                            .split(whereSeparator: \.isNewline)
                            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }

                        guard !title.isEmpty else {
                            viewModel.statusMessage = "Enter a warm-up title."
                            return
                        }
                        guard !steps.isEmpty else {
                            viewModel.statusMessage = "Add at least one warm-up step."
                            return
                        }

                        Task {
                            let target: StudioWarmupOfWeek.Target = (warmupAudience == .studio) ? .studio : .individual
                            let student = viewModel.studentMembers.first(where: { $0.id == warmupStudentUID })
                            await viewModel.publishStudioWarmup(
                                title: title,
                                instrument: instrument.isEmpty ? "Strings" : instrument,
                                focus: focus,
                                totalMinutes: warmupMinutesInput,
                                steps: steps,
                                target: target,
                                targetStudentUID: target == .individual ? student?.id : nil,
                                targetStudentName: target == .individual ? student?.displayName : nil
                            )

                            warmupTitleInput = ""
                            warmupFocusInput = ""
                            warmupStepsInput = ""
                            warmupMinutesInput = 10
                            showWarmupComposer = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            } label: {
                Label(showWarmupComposer ? "Hide Warm-up Composer" : "New Warm-up", systemImage: "plus.circle")
                    .font(type.body)
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(10)
            .pbSurfaceCard(palette: palette)
        }
    }

    private var studentAssignmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assignments")
                .font(type.body)
                .foregroundStyle(theme.textPrimary)

            assignmentQuickFilterChips(
                selection: $studentAssignmentQuickFilter,
                countFor: studentQuickFilterCount(for:)
            )

            let filtered = filteredStudentAssignments
            let recent = Array(filtered.prefix(8))
            let older = Array(filtered.dropFirst(8))

            if filtered.isEmpty {
                Text("No assignments yet.")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pbSurfaceCard(palette: palette)
            } else {
                ForEach(recent) { assignment in
                    let isCompleted = viewModel.myAssignmentCompletion[assignment.id] ?? false
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button {
                                Task {
                                    await viewModel.setMyAssignmentCompletion(
                                        assignmentID: assignment.id,
                                        completed: !isCompleted
                                    )
                                }
                            } label: {
                                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isCompleted ? theme.accent : theme.textSecondary)
                            }
                            .buttonStyle(.plain)

                            Text(assignment.title)
                                .font(type.body)
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                        }
                        if !assignment.details.isEmpty {
                            Text(assignment.details)
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                        if assignment.target == .studio {
                            Text("Whole Studio")
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        } else {
                            Text("Assigned to you")
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Text(L10n.f("Due %@", assignment.dueAt.formatted(date: .abbreviated, time: .omitted)))
                            .font(type.footnote)
                            .foregroundStyle(theme.textSecondary)
                        dueBadge(for: assignment, isCompleted: isCompleted)
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }

                if !older.isEmpty {
                    DisclosureGroup(isExpanded: $showOlderStudentAssignments) {
                        VStack(spacing: 8) {
                            ForEach(older) { assignment in
                                let isCompleted = viewModel.myAssignmentCompletion[assignment.id] ?? false
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Button {
                                            Task {
                                                await viewModel.setMyAssignmentCompletion(
                                                    assignmentID: assignment.id,
                                                    completed: !isCompleted
                                                )
                                            }
                                        } label: {
                                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(isCompleted ? theme.accent : theme.textSecondary)
                                        }
                                        .buttonStyle(.plain)

                                        Text(assignment.title)
                                            .font(type.body)
                                            .foregroundStyle(theme.textPrimary)
                                        Spacer()
                                    }
                                    if !assignment.details.isEmpty {
                                        Text(assignment.details)
                                            .font(type.footnote)
                                            .foregroundStyle(theme.textSecondary)
                                    }
                                    if assignment.target == .studio {
                                        Text("Whole Studio")
                                            .font(type.footnote)
                                            .foregroundStyle(theme.textSecondary)
                                    } else {
                                        Text("Assigned to you")
                                            .font(type.footnote)
                                            .foregroundStyle(theme.textSecondary)
                                    }
                                    Text(L10n.f("Due %@", assignment.dueAt.formatted(date: .abbreviated, time: .omitted)))
                                        .font(type.footnote)
                                        .foregroundStyle(theme.textSecondary)
                                    dueBadge(for: assignment, isCompleted: isCompleted)
                                }
                                .padding(10)
                                .pbSurfaceCard(palette: palette)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text(L10n.f("Older assignments (%@)", "\(older.count)"))
                            .font(type.footnote)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }
            }
        }
    }

    @ViewBuilder
    private func studentSelectionList(selectedID: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Select Student")
                .font(type.footnote)
                .foregroundStyle(theme.textSecondary)

            ForEach(viewModel.studentMembers) { student in
                let isSelected = selectedID.wrappedValue == student.id
                Button {
                    selectedID.wrappedValue = student.id
                } label: {
                    HStack {
                        Text(student.displayName)
                            .font(type.body)
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? theme.accent : theme.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .pbSurfaceCard(palette: palette)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func dueBadge(for assignment: StudioAssignment, isCompleted: Bool) -> some View {
        if isCompleted {
            EmptyView()
        } else {
            let dueStart = Calendar.current.startOfDay(for: assignment.dueAt)
            let todayStart = Calendar.current.startOfDay(for: Date())
            if dueStart < todayStart {
                Text("Overdue")
                    .font(type.footnote)
                    .foregroundStyle(.red)
            } else if dueStart == todayStart {
                Text("Due Today")
                    .font(type.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var filteredTeacherAssignments: [StudioAssignment] {
        teacherAssignmentsBase
            .filter { assignment in
                matchesQuickFilter(
                    assignment,
                    completed: teacherAssignmentCompleted(assignment),
                    filter: teacherAssignmentQuickFilter
                )
            }
    }

    private var teacherAssignmentsBase: [StudioAssignment] {
        viewModel.filteredAssignments(teacherAssignmentFilter)
    }

    private func teacherQuickFilterCount(for filter: AssignmentQuickFilter) -> Int {
        teacherAssignmentsBase.filter {
            matchesQuickFilter($0, completed: teacherAssignmentCompleted($0), filter: filter)
        }.count
    }

    private var filteredStudentAssignments: [StudioAssignment] {
        studentAssignmentsBase
            .filter { assignment in
                matchesQuickFilter(
                    assignment,
                    completed: viewModel.myAssignmentCompletion[assignment.id] ?? false,
                    filter: studentAssignmentQuickFilter
                )
            }
    }

    private var studentAssignmentsBase: [StudioAssignment] {
        viewModel.visibleAssignmentsForCurrentRole
    }

    private func studentQuickFilterCount(for filter: AssignmentQuickFilter) -> Int {
        studentAssignmentsBase.filter {
            matchesQuickFilter($0, completed: viewModel.myAssignmentCompletion[$0.id] ?? false, filter: filter)
        }.count
    }

    private func teacherAssignmentCompleted(_ assignment: StudioAssignment) -> Bool {
        let completed = viewModel.assignmentCompletedCounts[assignment.id] ?? 0
        if assignment.target == .individual {
            return completed >= 1
        }
        let denominator = max(1, viewModel.studentMembers.count)
        return completed >= denominator
    }

    private func matchesQuickFilter(
        _ assignment: StudioAssignment,
        completed: Bool,
        filter: AssignmentQuickFilter
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .completed:
            return completed
        case .overdue:
            return !completed && assignmentDueState(for: assignment) == .overdue
        case .dueSoon:
            return !completed && assignmentDueState(for: assignment) == .dueSoon
        case .active:
            return !completed && assignmentDueState(for: assignment) == .active
        }
    }

    private enum AssignmentDueState {
        case active
        case dueSoon
        case overdue
    }

    private func assignmentDueState(for assignment: StudioAssignment) -> AssignmentDueState {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: assignment.dueAt)
        if due < today { return .overdue }
        let soonCutoff = cal.date(byAdding: .day, value: 2, to: today) ?? today
        if due <= soonCutoff { return .dueSoon }
        return .active
    }

    @ViewBuilder
    private func assignmentQuickFilterChips(
        selection: Binding<AssignmentQuickFilter>,
        countFor: @escaping (AssignmentQuickFilter) -> Int
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AssignmentQuickFilter.allCases) { filter in
                    let selected = selection.wrappedValue == filter
                    let count = countFor(filter)
                    Button {
                        selection.wrappedValue = filter
                        if selection.wrappedValue != .all {
                            showOlderTeacherAssignments = false
                            showOlderStudentAssignments = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(LocalizedStringKey(filter.titleKey))
                                .font(type.footnote)
                            Text("\(count)")
                                .font(type.footnote)
                                .monospacedDigit()
                        }
                        .foregroundStyle(selected ? Color.white : theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selected ? theme.accent : theme.surfaceAlt)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func teacherAssignmentRow(_ assignment: StudioAssignment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(assignment.title)
                .font(type.body)
                .foregroundStyle(theme.textPrimary)
            if assignment.target == .individual {
                Text(L10n.f("Individual: %@", assignment.targetStudentName ?? String(localized: "Student")))
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
            } else {
                Text("Whole Studio")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
            if !assignment.details.isEmpty {
                Text(assignment.details)
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
            HStack {
                Text(L10n.f("Due %@", assignment.dueAt.formatted(date: .abbreviated, time: .omitted)))
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text(viewModel.completionFractionText(for: assignment))
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
            }
            HStack(spacing: 8) {
                Button("Edit") {
                    beginEditing(assignment)
                }
                .buttonStyle(.bordered)
                Button("Delete", role: .destructive) {
                    assignmentPendingDelete = assignment
                    showDeleteConfirm = true
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
        .padding(10)
        .pbSurfaceCard(palette: palette)
    }

    private func beginEditing(_ assignment: StudioAssignment) {
        editingAssignment = assignment
        editTitleInput = assignment.title
        editDetailsInput = assignment.details
        editDueAt = assignment.dueAt
        editAudience = assignment.target == .studio ? .studio : .individual
        editSelectedStudentUID = assignment.targetStudentUID ?? ""
    }

    private func assignmentEditSheet(for assignment: StudioAssignment) -> some View {
        NavigationStack {
            Form {
                Section("Assignment") {
                    TextField("Title", text: $editTitleInput)
                    TextField("Details", text: $editDetailsInput, axis: .vertical)
                        .lineLimit(2...4)
                    DatePicker("Due", selection: $editDueAt, displayedComponents: .date)
                }

                Section("Target") {
                    Picker("Assign To", selection: $editAudience) {
                        ForEach(AssignmentAudience.allCases) { mode in
                            Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if editAudience == .individual {
                        Picker("Student", selection: $editSelectedStudentUID) {
                            ForEach(viewModel.studentMembers) { student in
                                Text(student.displayName).tag(student.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .navigationTitle("Edit Assignment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingAssignment = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let target: StudioAssignment.Target = (editAudience == .studio) ? .studio : .individual
                        let student = viewModel.studentMembers.first(where: { $0.id == editSelectedStudentUID })
                        Task {
                            await viewModel.updateAssignment(
                                assignmentID: assignment.id,
                                title: editTitleInput,
                                details: editDetailsInput,
                                dueAt: editDueAt,
                                target: target,
                                targetStudentUID: target == .individual ? student?.id : nil,
                                targetStudentName: target == .individual ? student?.displayName : nil
                            )
                            editingAssignment = nil
                        }
                    }
                }
            }
        }
    }
}
