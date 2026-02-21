import SwiftUI
import UIKit

struct StudioManagerView: View {
    private enum AssignmentAudience: String, CaseIterable, Identifiable {
        case studio
        case individual
        var id: String { rawValue }
        var title: String {
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

    @StateObject private var viewModel = StudioManagerViewModel()
    @State private var studioNameInput: String = ""
    @State private var inviteCodeInput: String = ""
    @State private var assignmentTitleInput: String = ""
    @State private var assignmentDetailsInput: String = ""
    @State private var assignmentDueAt: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var assignmentAudience: AssignmentAudience = .studio
    @State private var selectedStudentUID: String = ""
    @State private var teacherAssignmentFilter: StudioManagerViewModel.AssignmentFilter = .all
    @State private var editingAssignment: StudioAssignment?
    @State private var showDeleteConfirm = false
    @State private var assignmentPendingDelete: StudioAssignment?

    @State private var editTitleInput: String = ""
    @State private var editDetailsInput: String = ""
    @State private var editDueAt: Date = Date()
    @State private var editAudience: AssignmentAudience = .studio
    @State private var editSelectedStudentUID: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !purchaseManager.isPro {
                    lockedCard
                } else {
                    if purchaseManager.accountType == .teacher {
                        teacherContentCard
                    } else {
                        studentContentCard
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, PBLayout.padXL)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: firebase.currentUserID) {
            guard let uid = firebase.currentUserID else { return }
            viewModel.start(for: uid, role: purchaseManager.accountType)
        }
        .onChange(of: purchaseManager.accountType) { _, newRole in
            guard let uid = firebase.currentUserID else { return }
            viewModel.start(for: uid, role: newRole)
        }
        .onChange(of: viewModel.studentMembers.map(\.id)) { _, ids in
            guard assignmentAudience == .individual else { return }
            if !ids.contains(selectedStudentUID) {
                selectedStudentUID = ids.first ?? ""
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
            Text("Delete \"\(assignment.title)\"?")
        }
    }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Studio Manager")
                .font(type.sectionTitle)
                .foregroundStyle(theme.textPrimary)

            Text("Studio tools are part of Practice Buddy Pro.")
                .font(type.body)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusCard, style: .continuous))
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
                memberList
                teacherAssignmentsSection
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create your studio to start inviting students.")
                        .font(type.body)
                        .foregroundStyle(theme.textSecondary)

                    TextField("Studio name", text: $studioNameInput)
                        .font(type.body)
                        .padding(10)
                        .background(theme.surfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))

                    Button("Create Studio") {
                        Task { await viewModel.createStudio(name: studioNameInput) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let msg = viewModel.statusMessage, !msg.isEmpty {
                Text(msg)
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusCard, style: .continuous))
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
                memberList
                studentAssignmentsSection
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
                        .background(theme.surfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))

                    Button("Join Studio") {
                        let code = inviteCodeInput
                        inviteCodeInput = ""
                        Task { await viewModel.joinStudio(inviteCode: code) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let msg = viewModel.statusMessage, !msg.isEmpty {
                Text(msg)
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusCard, style: .continuous))
    }

    @ViewBuilder
    private func studioHeader(_ studio: StudioInfo) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(studio.name)
                    .font(type.body.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("Invite link ready")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
            Button("Copy Invite Link") {
                guard let inviteURL = inviteURLString(for: studio.inviteCode) else { return }
                UIPasteboard.general.string = inviteURL
                viewModel.statusMessage = "Invite link copied."
            }
            .buttonStyle(.bordered)

            if let inviteURL = inviteURL(for: studio.inviteCode) {
                ShareLink(item: inviteURL) {
                    Text("Share")
                        .font(type.footnote)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(theme.surfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
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

    private func inviteURLString(for code: String) -> String? {
        inviteURL(for: code)?.absoluteString
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
                    .background(theme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
            } else {
                ForEach(viewModel.members) { member in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                                .font(type.body)
                                .foregroundStyle(theme.textPrimary)
                            Text(member.role.rawValue.capitalized)
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(theme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
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
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Assignment title", text: $assignmentTitleInput)
                    .font(type.body)
                    .padding(10)
                    .background(theme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))

                TextField("Details (optional)", text: $assignmentDetailsInput, axis: .vertical)
                    .font(type.body)
                    .lineLimit(2...4)
                    .padding(10)
                    .background(theme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))

                DatePicker("Due", selection: $assignmentDueAt, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .font(type.body)
                    .foregroundStyle(theme.textPrimary)

                Picker("Assign To", selection: $assignmentAudience) {
                    ForEach(AssignmentAudience.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if assignmentAudience == .individual {
                    if viewModel.studentMembers.isEmpty {
                        Text("No students in roster yet.")
                            .font(type.footnote)
                            .foregroundStyle(theme.textSecondary)
                    } else {
                        Picker("Student", selection: $selectedStudentUID) {
                            ForEach(viewModel.studentMembers) { student in
                                Text(student.displayName).tag(student.id)
                            }
                        }
                        .pickerStyle(.menu)
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
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            let filtered = viewModel.filteredAssignments(teacherAssignmentFilter)
            if filtered.isEmpty {
                Text("No assignments yet.")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
            } else {
                ForEach(filtered) { assignment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(assignment.title)
                            .font(type.body.weight(.semibold))
                            .foregroundStyle(theme.textPrimary)
                        if assignment.target == .individual {
                            Text("Individual: \(assignment.targetStudentName ?? "Student")")
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
                            Text("Due \(assignment.dueAt.formatted(date: .abbreviated, time: .omitted))")
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
                    .background(theme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
                }
            }
        }
    }

    private var studentAssignmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assignments")
                .font(type.body)
                .foregroundStyle(theme.textPrimary)

            if viewModel.visibleAssignmentsForCurrentRole.isEmpty {
                Text("No assignments yet.")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
            } else {
                ForEach(viewModel.visibleAssignmentsForCurrentRole) { assignment in
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
                                .font(type.body.weight(.semibold))
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
                        Text("Due \(assignment.dueAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(type.footnote)
                            .foregroundStyle(theme.textSecondary)
                        dueBadge(for: assignment, isCompleted: isCompleted)
                    }
                    .padding(10)
                    .background(theme.surfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
                }
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
                            Text(mode.title).tag(mode)
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
