import Foundation
import Combine
import FirebaseFirestore

@MainActor
final class StudioManagerViewModel: ObservableObject {
    @Published private(set) var studio: StudioInfo?
    @Published private(set) var members: [StudioMemberSummary] = []
    @Published private(set) var assignments: [StudioAssignment] = []
    @Published private(set) var assignmentCompletedCounts: [String: Int] = [:]
    @Published private(set) var myAssignmentCompletion: [String: Bool] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published var statusMessage: String?

    private let repository: FirebaseStudiosRepository
    private var userListener: ListenerRegistration?
    private var studioListener: ListenerRegistration?
    private var membersListener: ListenerRegistration?
    private var assignmentsListener: ListenerRegistration?
    private var assignmentSubmissionListeners: [String: ListenerRegistration] = [:]
    private var currentUID: String?
    private var currentRole: PBAccountType = .student
    private let notificationManager = AssignmentNotificationManager.shared

    init(repository: FirebaseStudiosRepository? = nil) {
        self.repository = repository ?? FirebaseStudiosRepository()
    }

    deinit {
        userListener?.remove()
        studioListener?.remove()
        membersListener?.remove()
        assignmentsListener?.remove()
        assignmentSubmissionListeners.values.forEach { $0.remove() }
    }

    func start(for uid: String, role: PBAccountType) {
        if currentUID == uid && currentRole == role { return }
        stop()

        currentUID = uid
        currentRole = role
        isLoading = true
        statusMessage = nil

        if role == .teacher {
            studioListener = repository.listenToOwnedStudio(ownerUID: uid) { [weak self] studio in
                guard let self else { return }
                self.studio = studio
                self.isLoading = false
                self.attachMembersListener(studioID: studio?.id)
                self.attachAssignmentsListener(studioID: studio?.id)
            }
        } else {
            userListener = repository.listenToUserDocument(uid: uid) { [weak self] data in
                guard let self else { return }
                let studioID = (data?["studentStudioId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let linkedID = (studioID?.isEmpty == false) ? studioID! : nil
                self.attachStudioListener(studioID: linkedID)
            }
        }
    }

    func stop() {
        userListener?.remove()
        studioListener?.remove()
        membersListener?.remove()
        assignmentsListener?.remove()
        assignmentSubmissionListeners.values.forEach { $0.remove() }
        userListener = nil
        studioListener = nil
        membersListener = nil
        assignmentsListener = nil
        assignmentSubmissionListeners = [:]
        studio = nil
        members = []
        assignments = []
        assignmentCompletedCounts = [:]
        myAssignmentCompletion = [:]
        currentUID = nil
        currentRole = .student
        isLoading = false
    }

    func createStudio(name: String) async {
        guard let uid = currentUID else {
            statusMessage = "No active account."
            return
        }
        do {
            try await repository.createStudio(ownerUID: uid, rawName: name)
            statusMessage = "Studio created."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func joinStudio(inviteCode: String) async {
        guard let uid = currentUID else {
            statusMessage = "No active account."
            return
        }
        do {
            try await repository.joinStudio(studentUID: uid, rawInviteCode: inviteCode)
            statusMessage = "Joined studio."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createStudioWideAssignment(title: String, details: String, dueAt: Date) async {
        guard let uid = currentUID else {
            statusMessage = "No active account."
            return
        }
        guard let studioID = studio?.id else {
            statusMessage = "Create a studio first."
            return
        }
        do {
            try await repository.createAssignment(
                studioID: studioID,
                teacherUID: uid,
                rawTitle: title,
                rawDetails: details,
                dueAt: dueAt,
                target: .studio,
                targetStudentUID: nil,
                targetStudentName: nil
            )
            statusMessage = "Assignment created."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createIndividualAssignment(
        title: String,
        details: String,
        dueAt: Date,
        studentUID: String,
        studentName: String
    ) async {
        guard let uid = currentUID else {
            statusMessage = "No active account."
            return
        }
        guard let studioID = studio?.id else {
            statusMessage = "Create a studio first."
            return
        }
        do {
            try await repository.createAssignment(
                studioID: studioID,
                teacherUID: uid,
                rawTitle: title,
                rawDetails: details,
                dueAt: dueAt,
                target: .individual,
                targetStudentUID: studentUID,
                targetStudentName: studentName
            )
            statusMessage = "Assignment created."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updateAssignment(
        assignmentID: String,
        title: String,
        details: String,
        dueAt: Date,
        target: StudioAssignment.Target,
        targetStudentUID: String?,
        targetStudentName: String?
    ) async {
        guard let studioID = studio?.id else {
            statusMessage = "Studio not found."
            return
        }
        do {
            try await repository.updateAssignment(
                studioID: studioID,
                assignmentID: assignmentID,
                rawTitle: title,
                rawDetails: details,
                dueAt: dueAt,
                target: target,
                targetStudentUID: targetStudentUID,
                targetStudentName: targetStudentName
            )
            statusMessage = "Assignment updated."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteAssignment(_ assignmentID: String) async {
        guard let studioID = studio?.id else {
            statusMessage = "Studio not found."
            return
        }
        do {
            try await repository.deleteAssignment(studioID: studioID, assignmentID: assignmentID)
            statusMessage = "Assignment deleted."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func publishStudioWarmup(
        title: String,
        instrument: String,
        focus: String,
        totalMinutes: Int,
        steps: [String],
        target: StudioWarmupOfWeek.Target,
        targetStudentUID: String?,
        targetStudentName: String?
    ) async {
        guard let uid = currentUID else {
            statusMessage = "No active account."
            return
        }
        guard currentRole == .teacher else {
            statusMessage = "Only teachers can publish studio warm-ups."
            return
        }
        guard let studioID = studio?.id else {
            statusMessage = "Create a studio first."
            return
        }

        do {
            try await repository.saveStudioWarmup(
                studioID: studioID,
                teacherUID: uid,
                title: title,
                instrument: instrument,
                focus: focus,
                totalMinutes: totalMinutes,
                steps: steps,
                target: target,
                targetStudentUID: targetStudentUID,
                targetStudentName: targetStudentName
            )
            statusMessage = target == .studio
                ? "Studio warm-up published."
                : "Individual warm-up published."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func setMyAssignmentCompletion(assignmentID: String, completed: Bool) async {
        guard let uid = currentUID, let studioID = studio?.id else { return }
        guard let assignment = assignments.first(where: { $0.id == assignmentID }) else { return }
        if assignment.target == .individual, assignment.targetStudentUID != uid {
            statusMessage = "This assignment is not assigned to you."
            return
        }
        do {
            try await repository.setSubmission(
                studioID: studioID,
                assignmentID: assignmentID,
                studentUID: uid,
                completed: completed
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    var studentMembers: [StudioMemberSummary] {
        members.filter { $0.role == .student }
    }

    var visibleAssignmentsForCurrentRole: [StudioAssignment] {
        guard currentRole == .student, let uid = currentUID else {
            return assignments
        }
        return assignments.filter {
            $0.target == .studio || $0.targetStudentUID == uid
        }
    }

    func completionFractionText(for assignment: StudioAssignment) -> String {
        let completed = assignmentCompletedCounts[assignment.id] ?? 0
        let denominator: Int
        if assignment.target == .individual {
            denominator = 1
        } else {
            denominator = max(1, studentMembers.count)
        }
        return "\(min(completed, denominator))/\(denominator) completed"
    }

    enum AssignmentFilter: String, CaseIterable, Identifiable {
        case all
        case studio
        case individual
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .studio: return "Studio"
            case .individual: return "Individual"
            }
        }
    }

    func filteredAssignments(_ filter: AssignmentFilter) -> [StudioAssignment] {
        switch filter {
        case .all:
            return assignments
        case .studio:
            return assignments.filter { $0.target == .studio }
        case .individual:
            return assignments.filter { $0.target == .individual }
        }
    }

    private func attachMembersListener(studioID: String?) {
        membersListener?.remove()
        membersListener = nil
        members = []

        guard let studioID else { return }
        membersListener = repository.listenToMembers(studioID: studioID) { [weak self] members in
            self?.members = members
        }
    }

    private func attachStudioListener(studioID: String?) {
        studioListener?.remove()
        studioListener = nil
        studio = nil
        isLoading = false
        guard let studioID else {
            attachMembersListener(studioID: nil)
            attachAssignmentsListener(studioID: nil)
            return
        }

        studioListener = repository.listenToStudioDocument(studioID: studioID) { [weak self] studio in
            guard let self else { return }
            self.studio = studio
            self.attachMembersListener(studioID: studio?.id)
            self.attachAssignmentsListener(studioID: studio?.id)
        }
    }

    private func attachAssignmentsListener(studioID: String?) {
        assignmentsListener?.remove()
        assignmentsListener = nil
        assignmentSubmissionListeners.values.forEach { $0.remove() }
        assignmentSubmissionListeners = [:]
        assignments = []
        assignmentCompletedCounts = [:]
        myAssignmentCompletion = [:]

        guard let studioID else { return }
        assignmentsListener = repository.listenToAssignments(studioID: studioID) { [weak self] rows in
            guard let self else { return }
            self.assignments = rows
            self.attachSubmissionListeners(studioID: studioID, assignments: rows)
            if self.currentRole == .student, let uid = self.currentUID {
                let visible = rows.filter { $0.target == .studio || $0.targetStudentUID == uid }
                Task {
                    await self.notificationManager.handleVisibleAssignmentsForStudent(
                        uid: uid,
                        studioID: studioID,
                        assignments: visible
                    )
                }
            }
        }
    }

    private func attachSubmissionListeners(studioID: String, assignments: [StudioAssignment]) {
        let activeIDs = Set(assignments.map(\.id))
        for (id, listener) in assignmentSubmissionListeners where !activeIDs.contains(id) {
            listener.remove()
            assignmentSubmissionListeners[id] = nil
            assignmentCompletedCounts[id] = nil
            myAssignmentCompletion[id] = nil
        }

        for assignment in assignments where assignmentSubmissionListeners[assignment.id] == nil {
            let listener = repository.listenToAssignmentSubmissions(
                studioID: studioID,
                assignmentID: assignment.id
            ) { [weak self] submissions in
                guard let self else { return }
                let completedCount = submissions.filter(\.completed).count
                self.assignmentCompletedCounts[assignment.id] = completedCount
                if let myUID = self.currentUID {
                    self.myAssignmentCompletion[assignment.id] =
                        submissions.first(where: { $0.studentUID == myUID })?.completed ?? false
                }
            }
            assignmentSubmissionListeners[assignment.id] = listener
        }
    }
}
