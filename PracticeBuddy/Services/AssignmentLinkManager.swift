import Foundation
import FirebaseFirestore
import Combine

struct LinkedAssignmentItem: Identifiable, Equatable {
    let id: String
    let studioID: String
    let title: String
    let details: String
    let dueAt: Date
    let completed: Bool
}

@MainActor
final class AssignmentLinkManager: ObservableObject {
    @Published private(set) var todayAssignments: [LinkedAssignmentItem] = []
    @Published private(set) var linkedAssignmentID: String?
    @Published private(set) var statusMessage: String?

    private struct PendingSubmissionUpdate: Codable, Equatable {
        let studioID: String
        let assignmentID: String
        let studentUID: String
        let completed: Bool
        let note: String
        let attachmentPath: String
        let linkedTool: String
        let createdAtEpoch: TimeInterval
    }

    private let repository: FirebaseStudiosRepository
    private let defaults = UserDefaults.standard
    private let pendingKey = "pb.assignment.pendingSubmissionUpdates"
    private let linkedIDKey = "pb.assignment.linkedAssignmentID"

    private var userListener: ListenerRegistration?
    private var assignmentsListener: ListenerRegistration?
    private var submissionListeners: [String: ListenerRegistration] = [:]

    private var currentUID: String?
    private var currentStudioID: String?
    private var completionByAssignmentID: [String: Bool] = [:]
    private var currentAccountType: PBAccountType = .student
    private var isFlushingPendingQueue = false
    private var lastFlushAttemptAt: Date?
    private let flushCooldown: TimeInterval = 3

    init(repository: FirebaseStudiosRepository? = nil) {
        self.repository = repository ?? FirebaseStudiosRepository()
        linkedAssignmentID = defaults.string(forKey: linkedIDKey)
    }

    deinit {
        userListener?.remove()
        assignmentsListener?.remove()
        submissionListeners.values.forEach { $0.remove() }
    }

    func start(uid: String?, accountType: PBAccountType) {
        if uid == currentUID, accountType == currentAccountType, accountType == .student, userListener != nil { return }
        stop()
        currentUID = uid
        currentAccountType = accountType
        guard accountType == .student, let uid else { return }

        userListener = repository.listenToUserDocument(uid: uid) { [weak self] data in
            guard let self else { return }
            let raw = (data?["studentStudioId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let studioID = (raw?.isEmpty == false) ? raw : nil
            self.attachStudio(studioID: studioID)
        }
    }

    func stop() {
        userListener?.remove()
        assignmentsListener?.remove()
        submissionListeners.values.forEach { $0.remove() }
        userListener = nil
        assignmentsListener = nil
        submissionListeners = [:]
        todayAssignments = []
        completionByAssignmentID = [:]
        currentUID = nil
        currentStudioID = nil
        currentAccountType = .student
    }

    func pauseRealtime() {
        userListener?.remove()
        assignmentsListener?.remove()
        submissionListeners.values.forEach { $0.remove() }
        userListener = nil
        assignmentsListener = nil
        submissionListeners = [:]
    }

    var linkedAssignment: LinkedAssignmentItem? {
        guard let linkedAssignmentID else { return nil }
        return todayAssignments.first(where: { $0.id == linkedAssignmentID })
    }

    func linkAssignment(_ assignmentID: String?) {
        linkedAssignmentID = assignmentID
        defaults.set(assignmentID, forKey: linkedIDKey)
    }

    func isAssignmentLinked(_ assignmentID: String) -> Bool {
        linkedAssignmentID == assignmentID
    }

    func markAssignmentCompletion(_ assignmentID: String, completed: Bool) async {
        guard let uid = currentUID, let studioID = currentStudioID else { return }
        let note = completed ? "Completed from Home checklist." : ""
        await writeOrQueue(
            studioID: studioID,
            assignmentID: assignmentID,
            studentUID: uid,
            completed: completed,
            note: note,
            attachmentPath: "",
            linkedTool: "home_checklist"
        )
        completionByAssignmentID[assignmentID] = completed
        rebuildTodayAssignments()
    }

    func submitLinkedPracticeResult(
        tool: String,
        note: String,
        attachmentPath: String?,
        markComplete: Bool
    ) async {
        guard let linked = linkedAssignment else { return }
        guard let uid = currentUID else { return }
        let completed = markComplete ? true : (completionByAssignmentID[linked.id] ?? false)
        await writeOrQueue(
            studioID: linked.studioID,
            assignmentID: linked.id,
            studentUID: uid,
            completed: completed,
            note: note,
            attachmentPath: attachmentPath ?? "",
            linkedTool: tool
        )
        completionByAssignmentID[linked.id] = completed
        rebuildTodayAssignments()
    }

    func flushPendingQueue() async {
        guard let uid = currentUID else { return }
        if isFlushingPendingQueue { return }
        if let lastFlushAttemptAt,
           Date().timeIntervalSince(lastFlushAttemptAt) < flushCooldown {
            return
        }
        isFlushingPendingQueue = true
        lastFlushAttemptAt = Date()
        defer { isFlushingPendingQueue = false }

        var queue = pendingQueue()
        guard !queue.isEmpty else { return }

        var remaining: [PendingSubmissionUpdate] = []
        for item in queue {
            guard item.studentUID == uid else { continue }
            do {
                try await repository.setSubmission(
                    studioID: item.studioID,
                    assignmentID: item.assignmentID,
                    studentUID: item.studentUID,
                    completed: item.completed,
                    note: item.note,
                    attachmentPath: item.attachmentPath.isEmpty ? nil : item.attachmentPath,
                    linkedTool: item.linkedTool
                )
            } catch {
                remaining.append(item)
            }
        }
        queue = remaining
        savePendingQueue(queue)
    }

    private func attachStudio(studioID: String?) {
        assignmentsListener?.remove()
        assignmentsListener = nil
        submissionListeners.values.forEach { $0.remove() }
        submissionListeners = [:]
        todayAssignments = []
        completionByAssignmentID = [:]
        currentStudioID = studioID

        guard let studioID else { return }

        assignmentsListener = repository.listenToAssignments(studioID: studioID) { [weak self] rows in
            guard let self else { return }
            guard let uid = self.currentUID else { return }

            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
            let visible = rows.filter {
                ($0.target == .studio || $0.targetStudentUID == uid) &&
                $0.dueAt >= today && $0.dueAt < tomorrow
            }

            self.rebindSubmissionListeners(studioID: studioID, assignments: visible)
            self.rebuildTodayAssignments(from: visible, studioID: studioID)

            Task {
                await self.flushPendingQueue()
            }
        }
    }

    private func rebindSubmissionListeners(studioID: String, assignments: [StudioAssignment]) {
        let activeIDs = Set(assignments.map(\.id))

        for (id, listener) in submissionListeners where !activeIDs.contains(id) {
            listener.remove()
            submissionListeners[id] = nil
            completionByAssignmentID[id] = nil
        }

        for assignment in assignments where submissionListeners[assignment.id] == nil {
            let listener = repository.listenToAssignmentSubmissions(
                studioID: studioID,
                assignmentID: assignment.id
            ) { [weak self] submissions in
                guard let self else { return }
                guard let uid = self.currentUID else { return }
                let completed = submissions.first(where: { $0.studentUID == uid })?.completed ?? false
                self.completionByAssignmentID[assignment.id] = completed
                self.rebuildTodayAssignments()
            }
            submissionListeners[assignment.id] = listener
        }
    }

    private func rebuildTodayAssignments(from source: [StudioAssignment]? = nil, studioID: String? = nil) {
        let sid = studioID ?? currentStudioID
        guard let sid else { return }

        let base: [LinkedAssignmentItem]
        if let source {
            base = source.map { a in
                LinkedAssignmentItem(
                    id: a.id,
                    studioID: sid,
                    title: a.title,
                    details: a.details,
                    dueAt: a.dueAt,
                    completed: completionByAssignmentID[a.id] ?? false
                )
            }
        } else {
            base = todayAssignments.map { existing in
                LinkedAssignmentItem(
                    id: existing.id,
                    studioID: existing.studioID,
                    title: existing.title,
                    details: existing.details,
                    dueAt: existing.dueAt,
                    completed: completionByAssignmentID[existing.id] ?? false
                )
            }
        }

        todayAssignments = base.sorted(by: { $0.dueAt < $1.dueAt })

        if let linkedAssignmentID, !todayAssignments.contains(where: { $0.id == linkedAssignmentID }) {
            linkAssignment(nil)
        }
    }

    private func writeOrQueue(
        studioID: String,
        assignmentID: String,
        studentUID: String,
        completed: Bool,
        note: String,
        attachmentPath: String,
        linkedTool: String
    ) async {
        do {
            try await repository.setSubmission(
                studioID: studioID,
                assignmentID: assignmentID,
                studentUID: studentUID,
                completed: completed,
                note: note,
                attachmentPath: attachmentPath.isEmpty ? nil : attachmentPath,
                linkedTool: linkedTool
            )
            statusMessage = completed ? "Assignment updated." : "Assignment note attached."
        } catch {
            var queue = pendingQueue()
            queue.append(
                PendingSubmissionUpdate(
                    studioID: studioID,
                    assignmentID: assignmentID,
                    studentUID: studentUID,
                    completed: completed,
                    note: note,
                    attachmentPath: attachmentPath,
                    linkedTool: linkedTool,
                    createdAtEpoch: Date().timeIntervalSince1970
                )
            )
            if queue.count > 40 {
                queue = Array(queue.suffix(40))
            }
            savePendingQueue(queue)
            statusMessage = "Saved offline. Will sync when connection returns."
        }
    }

    private func pendingQueue() -> [PendingSubmissionUpdate] {
        guard let data = defaults.data(forKey: pendingKey),
              let items = try? JSONDecoder().decode([PendingSubmissionUpdate].self, from: data) else {
            return []
        }
        return items
    }

    private func savePendingQueue(_ items: [PendingSubmissionUpdate]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: pendingKey)
        }
    }
}
