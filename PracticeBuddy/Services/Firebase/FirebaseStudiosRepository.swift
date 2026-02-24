import Foundation
import FirebaseFirestore

struct StudioInfo: Identifiable, Equatable {
    let id: String
    let ownerUID: String
    let name: String
    let inviteCode: String
    let createdAt: Date
}

enum StudioMemberRole: String {
    case teacher
    case student
}

struct StudioMemberSummary: Identifiable, Equatable {
    let id: String
    let displayName: String
    let role: StudioMemberRole
    let joinedAt: Date
    let avatarID: String
    let publicLevel: Int
}

struct StudioAssignment: Identifiable, Equatable {
    enum Target: String {
        case studio
        case individual
    }

    let id: String
    let title: String
    let details: String
    let dueAt: Date
    let createdAt: Date
    let target: Target
    let targetStudentUID: String?
    let targetStudentName: String?
}

struct StudioAssignmentSubmission: Identifiable, Equatable {
    let id: String
    let studentUID: String
    let completed: Bool
    let updatedAt: Date
}

struct StudioPlanTemplate: Identifiable, Equatable {
    let id: String
    let title: String
    let targetMinutes: Int
    let goals: [String]
    let blocks: [String]
    let createdByUID: String
    let updatedAt: Date
}

struct StudioWarmupOfWeek: Identifiable, Equatable {
    enum Target: String {
        case studio
        case individual
    }

    let id: String
    let title: String
    let instrument: String
    let focus: String
    let totalMinutes: Int
    let steps: [String]
    let target: Target
    let targetStudentUID: String?
    let targetStudentName: String?
    let updatedAt: Date
}

struct StudioChatMessage: Identifiable, Equatable {
    let id: String
    let studioID: String
    let senderUID: String
    let senderName: String
    let senderAvatarID: String
    let senderLevel: Int
    let text: String
    let createdAt: Date
}

enum FirebaseStudiosError: LocalizedError {
    case missingOwner
    case invalidStudioName
    case studioAlreadyExists
    case invalidInviteCode
    case alreadyInStudio
    case invalidAssignmentTitle
    case invalidTemplateTitle
    case missingTargetStudent
    case invalidWarmupTitle

    var errorDescription: String? {
        switch self {
        case .missingOwner: return "No signed-in user found."
        case .invalidStudioName: return "Studio name must be 2-50 characters."
        case .studioAlreadyExists: return "You already have a studio."
        case .invalidInviteCode: return "Invalid studio invite code."
        case .alreadyInStudio: return "You already joined a studio."
        case .invalidAssignmentTitle: return "Assignment title must be 2-80 characters."
        case .invalidTemplateTitle: return "Template title must be 2-80 characters."
        case .missingTargetStudent: return "Select a student for individual assignment."
        case .invalidWarmupTitle: return "Warm-up title must be 2-80 characters."
        }
    }
}

final class FirebaseStudiosRepository {
    private var db: Firestore { Firestore.firestore() }

    func listenToOwnedStudio(
        ownerUID: String,
        onChange: @escaping @MainActor (StudioInfo?) -> Void
    ) -> ListenerRegistration {
        db.collection("studios")
            .whereField("ownerUid", isEqualTo: ownerUID)
            .limit(to: 1)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    guard let doc = snap?.documents.first else {
                        onChange(nil)
                        return
                    }
                    onChange(self.parseStudio(doc))
                }
            }
    }

    func listenToMembers(
        studioID: String,
        onChange: @escaping @MainActor ([StudioMemberSummary]) -> Void
    ) -> ListenerRegistration {
        db.collection("studios")
            .document(studioID)
            .collection("members")
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = (snap?.documents ?? [])
                        .compactMap(self.parseMember)
                        .sorted(by: { $0.joinedAt < $1.joinedAt })
                    onChange(rows)
                }
            }
    }

    func listenToStudioDocument(
        studioID: String,
        onChange: @escaping @MainActor (StudioInfo?) -> Void
    ) -> ListenerRegistration {
        db.collection("studios")
            .document(studioID)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    guard let snap, snap.exists, let data = snap.data() else {
                        onChange(nil)
                        return
                    }
                    onChange(self.parseStudio(documentID: snap.documentID, data: data))
                }
            }
    }

    func listenToUserDocument(
        uid: String,
        onChange: @escaping @MainActor ([String: Any]?) -> Void
    ) -> ListenerRegistration {
        db.collection("users").document(uid).addSnapshotListener { snap, _ in
            Task { @MainActor in
                onChange(snap?.data())
            }
        }
    }

    func createStudio(ownerUID: String, rawName: String) async throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...50).contains(name.count) else {
            throw FirebaseStudiosError.invalidStudioName
        }
        guard !ownerUID.isEmpty else {
            throw FirebaseStudiosError.missingOwner
        }

        let existing = try await db.collection("studios")
            .whereField("ownerUid", isEqualTo: ownerUID)
            .limit(to: 1)
            .getDocuments()
        if !existing.documents.isEmpty {
            throw FirebaseStudiosError.studioAlreadyExists
        }

        let ownerProfile = try await fetchUserPublicProfile(uid: ownerUID)

        var inviteCode = ""
        for _ in 0..<8 {
            let code = makeInviteCode()
            let collision = try await db.collection("studios")
                .whereField("inviteCode", isEqualTo: code)
                .limit(to: 1)
                .getDocuments()
            if collision.documents.isEmpty {
                inviteCode = code
                break
            }
        }
        if inviteCode.isEmpty {
            inviteCode = makeInviteCode()
        }

        let studioRef = db.collection("studios").document()
        let memberRef = studioRef.collection("members").document(ownerUID)
        let now = FieldValue.serverTimestamp()

        let batch = db.batch()
        batch.setData([
            "ownerUid": ownerUID,
            "name": name,
            "inviteCode": inviteCode,
            "createdAt": now,
            "updatedAt": now
        ], forDocument: studioRef)
        batch.setData([
            "uid": ownerUID,
            "displayName": ownerProfile.displayName,
            "role": StudioMemberRole.teacher.rawValue,
            "avatarID": ownerProfile.avatarID,
            "publicLevel": ownerProfile.publicLevel,
            "joinedAt": now
        ], forDocument: memberRef)
        batch.setData([
            "teacherStudioId": studioRef.documentID,
            "updatedAt": now
        ], forDocument: db.collection("users").document(ownerUID), merge: true)
        try await batch.commit()
    }

    func listenToAssignments(
        studioID: String,
        onChange: @escaping @MainActor ([StudioAssignment]) -> Void
    ) -> ListenerRegistration {
        db.collection("studios")
            .document(studioID)
            .collection("assignments")
            .order(by: "dueAt", descending: false)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = (snap?.documents ?? []).compactMap(self.parseAssignment)
                    onChange(rows)
                }
            }
    }

    func listenToAssignmentSubmissions(
        studioID: String,
        assignmentID: String,
        onChange: @escaping @MainActor ([StudioAssignmentSubmission]) -> Void
    ) -> ListenerRegistration {
        db.collection("studios")
            .document(studioID)
            .collection("assignments")
            .document(assignmentID)
            .collection("submissions")
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = (snap?.documents ?? []).compactMap(self.parseSubmission)
                    onChange(rows)
                }
            }
    }

    func createAssignment(
        studioID: String,
        teacherUID: String,
        rawTitle: String,
        rawDetails: String,
        dueAt: Date,
        target: StudioAssignment.Target,
        targetStudentUID: String?,
        targetStudentName: String?
    ) async throws {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = rawDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(title.count) else {
            throw FirebaseStudiosError.invalidAssignmentTitle
        }
        if target == .individual && (targetStudentUID ?? "").isEmpty {
            throw FirebaseStudiosError.missingTargetStudent
        }

        let now = FieldValue.serverTimestamp()
        let ref = db.collection("studios")
            .document(studioID)
            .collection("assignments")
            .document()

        try await ref.setData([
            "title": title,
            "details": details,
            "dueAt": Timestamp(date: dueAt),
            "createdAt": now,
            "updatedAt": now,
            "createdByUid": teacherUID,
            "target": target.rawValue,
            "targetStudentUid": targetStudentUID as Any,
            "targetStudentName": targetStudentName as Any
        ])
    }

    func setSubmission(
        studioID: String,
        assignmentID: String,
        studentUID: String,
        completed: Bool,
        note: String? = nil,
        attachmentPath: String? = nil,
        linkedTool: String? = nil
    ) async throws {
        let ref = db.collection("studios")
            .document(studioID)
            .collection("assignments")
            .document(assignmentID)
            .collection("submissions")
            .document(studentUID)

        var payload: [String: Any] = [
            "studentUid": studentUID,
            "completed": completed,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["practiceNote"] = note
        }
        if let attachmentPath, !attachmentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["attachmentPath"] = attachmentPath
        }
        if let linkedTool, !linkedTool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["linkedTool"] = linkedTool
        }

        try await ref.setData(payload, merge: true)
    }

    func updateAssignment(
        studioID: String,
        assignmentID: String,
        rawTitle: String,
        rawDetails: String,
        dueAt: Date,
        target: StudioAssignment.Target,
        targetStudentUID: String?,
        targetStudentName: String?
    ) async throws {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let details = rawDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(title.count) else {
            throw FirebaseStudiosError.invalidAssignmentTitle
        }
        if target == .individual && (targetStudentUID ?? "").isEmpty {
            throw FirebaseStudiosError.missingTargetStudent
        }

        let ref = db.collection("studios")
            .document(studioID)
            .collection("assignments")
            .document(assignmentID)

        try await ref.setData([
            "title": title,
            "details": details,
            "dueAt": Timestamp(date: dueAt),
            "target": target.rawValue,
            "targetStudentUid": targetStudentUID as Any,
            "targetStudentName": targetStudentName as Any,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func listenToPlanTemplates(
        studioID: String,
        onChange: @escaping @MainActor ([StudioPlanTemplate]) -> Void
    ) -> ListenerRegistration {
        db.collection("studios")
            .document(studioID)
            .collection("planTemplates")
            .order(by: "updatedAt", descending: true)
            .limit(to: 30)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = (snap?.documents ?? []).compactMap(self.parsePlanTemplate)
                    onChange(rows)
                }
            }
    }

    func savePlanTemplate(
        studioID: String,
        teacherUID: String,
        title rawTitle: String,
        targetMinutes: Int,
        goals: [String],
        blocks: [String]
    ) async throws {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(title.count) else {
            throw FirebaseStudiosError.invalidTemplateTitle
        }

        let now = FieldValue.serverTimestamp()
        let ref = db.collection("studios")
            .document(studioID)
            .collection("planTemplates")
            .document()

        try await ref.setData([
            "title": title,
            "targetMinutes": max(5, targetMinutes),
            "goals": goals,
            "blocks": blocks,
            "createdByUid": teacherUID,
            "updatedAt": now,
            "createdAt": now
        ], merge: true)
    }

    func listenToWarmupOfWeek(
        studioID: String,
        onChange: @escaping @MainActor (StudioWarmupOfWeek?) -> Void
    ) -> ListenerRegistration {
        listenToWarmupDocument(studioID: studioID, documentID: "warmup_of_week", onChange: onChange)
    }

    func listenToWarmupDocument(
        studioID: String,
        documentID: String,
        onChange: @escaping @MainActor (StudioWarmupOfWeek?) -> Void
    ) -> ListenerRegistration {
        db.collection("studios")
            .document(studioID)
            .collection("warmups")
            .document(documentID)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    guard let snap, snap.exists, let data = snap.data() else {
                        onChange(nil)
                        return
                    }
                    onChange(self.parseWarmupOfWeek(documentID: snap.documentID, data: data))
                }
            }
    }

    func saveWarmupOfWeek(
        studioID: String,
        teacherUID: String,
        title rawTitle: String,
        instrument: String,
        focus: String,
        totalMinutes: Int,
        steps: [String]
    ) async throws {
        try await saveStudioWarmup(
            studioID: studioID,
            teacherUID: teacherUID,
            title: rawTitle,
            instrument: instrument,
            focus: focus,
            totalMinutes: totalMinutes,
            steps: steps,
            target: .studio,
            targetStudentUID: nil,
            targetStudentName: nil
        )
    }

    func saveStudioWarmup(
        studioID: String,
        teacherUID: String,
        title rawTitle: String,
        instrument: String,
        focus: String,
        totalMinutes: Int,
        steps: [String],
        target: StudioWarmupOfWeek.Target,
        targetStudentUID: String?,
        targetStudentName: String?
    ) async throws {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(title.count) else {
            throw FirebaseStudiosError.invalidWarmupTitle
        }
        if target == .individual && (targetStudentUID ?? "").isEmpty {
            throw FirebaseStudiosError.missingTargetStudent
        }
        let trimmedSteps = steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let docID: String
        switch target {
        case .studio:
            docID = "warmup_of_week"
        case .individual:
            docID = "individual_\(targetStudentUID ?? "")"
        }

        let ref = db.collection("studios")
            .document(studioID)
            .collection("warmups")
            .document(docID)

        try await ref.setData([
            "title": title,
            "instrument": instrument,
            "focus": focus,
            "totalMinutes": max(5, totalMinutes),
            "steps": trimmedSteps,
            "target": target.rawValue,
            "targetStudentUid": targetStudentUID as Any,
            "targetStudentName": targetStudentName as Any,
            "createdByUid": teacherUID,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func deleteAssignment(studioID: String, assignmentID: String) async throws {
        let ref = db.collection("studios")
            .document(studioID)
            .collection("assignments")
            .document(assignmentID)
        try await ref.delete()
    }

    func listenToStudioMessages(
        studioID: String,
        limit: Int = 250,
        onChange: @escaping @MainActor ([StudioChatMessage]) -> Void
    ) -> ListenerRegistration {
        db.collection("studios")
            .document(studioID)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(to: max(20, min(limit, 500)))
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = (snap?.documents ?? []).compactMap { self.parseChatMessage(studioID: studioID, document: $0) }
                    onChange(rows)
                }
            }
    }

    func sendStudioMessage(
        studioID: String,
        senderUID: String,
        senderName: String,
        senderAvatarID: String,
        senderLevel: Int,
        rawText: String
    ) async throws {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        try await db.collection("studios")
            .document(studioID)
            .collection("messages")
            .document()
            .setData([
                "senderUid": senderUID,
                "senderName": senderName,
                "senderAvatarID": senderAvatarID,
                "senderLevel": max(1, senderLevel),
                "text": String(text.prefix(700)),
                "createdAt": FieldValue.serverTimestamp()
            ])
    }

    func joinStudio(studentUID: String, rawInviteCode: String) async throws {
        let inviteCode = rawInviteCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !inviteCode.isEmpty else {
            throw FirebaseStudiosError.invalidInviteCode
        }

        let userRef = db.collection("users").document(studentUID)
        let userSnap = try await userRef.getDocument()
        if let current = userSnap.data()?["studentStudioId"] as? String, !current.isEmpty {
            throw FirebaseStudiosError.alreadyInStudio
        }

        let studioQuery = try await db.collection("studios")
            .whereField("inviteCode", isEqualTo: inviteCode)
            .limit(to: 1)
            .getDocuments()
        guard let studioDoc = studioQuery.documents.first else {
            throw FirebaseStudiosError.invalidInviteCode
        }

        let studentProfile = try await fetchUserPublicProfile(uid: studentUID)
        let studioRef = studioDoc.reference
        let memberRef = studioRef.collection("members").document(studentUID)
        let now = FieldValue.serverTimestamp()

        let batch = db.batch()
        batch.setData([
            "uid": studentUID,
            "displayName": studentProfile.displayName,
            "role": StudioMemberRole.student.rawValue,
            "avatarID": studentProfile.avatarID,
            "publicLevel": studentProfile.publicLevel,
            "joinedAt": now
        ], forDocument: memberRef, merge: true)
        batch.setData([
            "studentStudioId": studioDoc.documentID,
            "updatedAt": now
        ], forDocument: userRef, merge: true)
        try await batch.commit()
    }

    private func fetchUserPublicProfile(uid: String) async throws -> (displayName: String, avatarID: String, publicLevel: Int) {
        let snap = try await db.collection("users").document(uid).getDocument()
        let fallback = "Teacher \(uid.prefix(4).uppercased())"
        let rawName = (snap.data()?["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (rawName?.isEmpty == false) ? rawName! : fallback
        let avatarID = (snap.data()?["avatarID"] as? String) ?? "avatar_note"
        let publicLevel = max(1, (snap.data()?["publicLevel"] as? Int) ?? 1)
        return (displayName, avatarID, publicLevel)
    }

    private func parseStudio(_ doc: QueryDocumentSnapshot) -> StudioInfo? {
        parseStudio(documentID: doc.documentID, data: doc.data())
    }

    private func parseStudio(documentID: String, data: [String: Any]) -> StudioInfo? {
        guard
            let ownerUID = data["ownerUid"] as? String,
            let name = data["name"] as? String,
            let inviteCode = data["inviteCode"] as? String
        else {
            return nil
        }
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
        return StudioInfo(
            id: documentID,
            ownerUID: ownerUID,
            name: name,
            inviteCode: inviteCode,
            createdAt: createdAt
        )
    }

    private func parseMember(_ doc: QueryDocumentSnapshot) -> StudioMemberSummary? {
        let data = doc.data()
        guard
            let displayName = data["displayName"] as? String,
            let roleRaw = data["role"] as? String,
            let role = StudioMemberRole(rawValue: roleRaw)
        else {
            return nil
        }
        let joinedAt = (data["joinedAt"] as? Timestamp)?.dateValue() ?? .distantPast
        return StudioMemberSummary(
            id: doc.documentID,
            displayName: displayName,
            role: role,
            joinedAt: joinedAt,
            avatarID: (data["avatarID"] as? String) ?? "avatar_note",
            publicLevel: max(1, (data["publicLevel"] as? Int) ?? 1)
        )
    }

    private func parseAssignment(_ doc: QueryDocumentSnapshot) -> StudioAssignment? {
        let data = doc.data()
        guard
            let title = data["title"] as? String,
            let targetRaw = data["target"] as? String,
            let target = StudioAssignment.Target(rawValue: targetRaw)
        else {
            return nil
        }
        let details = (data["details"] as? String) ?? ""
        let dueAt = (data["dueAt"] as? Timestamp)?.dateValue() ?? .distantFuture
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
        let targetStudentUID = data["targetStudentUid"] as? String
        let targetStudentName = data["targetStudentName"] as? String
        return StudioAssignment(
            id: doc.documentID,
            title: title,
            details: details,
            dueAt: dueAt,
            createdAt: createdAt,
            target: target,
            targetStudentUID: targetStudentUID,
            targetStudentName: targetStudentName
        )
    }

    private func parseSubmission(_ doc: QueryDocumentSnapshot) -> StudioAssignmentSubmission? {
        let data = doc.data()
        guard
            let studentUID = data["studentUid"] as? String,
            let completed = data["completed"] as? Bool
        else {
            return nil
        }
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
        return StudioAssignmentSubmission(
            id: doc.documentID,
            studentUID: studentUID,
            completed: completed,
            updatedAt: updatedAt
        )
    }

    private func parsePlanTemplate(_ doc: QueryDocumentSnapshot) -> StudioPlanTemplate? {
        let data = doc.data()
        guard
            let title = data["title"] as? String,
            let targetMinutes = data["targetMinutes"] as? Int
        else {
            return nil
        }
        let goals = (data["goals"] as? [String]) ?? []
        let blocks = (data["blocks"] as? [String]) ?? []
        let createdByUID = (data["createdByUid"] as? String) ?? ""
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
        return StudioPlanTemplate(
            id: doc.documentID,
            title: title,
            targetMinutes: targetMinutes,
            goals: goals,
            blocks: blocks,
            createdByUID: createdByUID,
            updatedAt: updatedAt
        )
    }

    private func parseWarmupOfWeek(documentID: String, data: [String: Any]) -> StudioWarmupOfWeek? {
        guard
            let title = data["title"] as? String,
            let instrument = data["instrument"] as? String,
            let focus = data["focus"] as? String,
            let totalMinutes = data["totalMinutes"] as? Int
        else {
            return nil
        }
        let steps = (data["steps"] as? [String]) ?? []
        let targetRaw = (data["target"] as? String) ?? StudioWarmupOfWeek.Target.studio.rawValue
        let target = StudioWarmupOfWeek.Target(rawValue: targetRaw) ?? .studio
        let targetStudentUID = data["targetStudentUid"] as? String
        let targetStudentName = data["targetStudentName"] as? String
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
        return StudioWarmupOfWeek(
            id: documentID,
            title: title,
            instrument: instrument,
            focus: focus,
            totalMinutes: totalMinutes,
            steps: steps,
            target: target,
            targetStudentUID: targetStudentUID,
            targetStudentName: targetStudentName,
            updatedAt: updatedAt
        )
    }

    private func parseChatMessage(studioID: String, document: QueryDocumentSnapshot) -> StudioChatMessage? {
        let data = document.data()
        guard
            let senderUID = data["senderUid"] as? String,
            let senderName = data["senderName"] as? String,
            let text = data["text"] as? String
        else {
            return nil
        }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
        return StudioChatMessage(
            id: document.documentID,
            studioID: studioID,
            senderUID: senderUID,
            senderName: senderName,
            senderAvatarID: (data["senderAvatarID"] as? String) ?? "avatar_note",
            senderLevel: max(1, (data["senderLevel"] as? Int) ?? 1),
            text: text,
            createdAt: createdAt
        )
    }

    private func makeInviteCode() -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let numbers = Array("23456789")
        let p1 = String((0..<3).map { _ in letters.randomElement() ?? "A" })
        let p2 = String((0..<3).map { _ in numbers.randomElement() ?? "2" })
        return "\(p1)-\(p2)"
    }
}
