import Foundation
import os
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

struct FriendChatThread: Identifiable, Equatable {
    let id: String
    let participants: [String]
    let lastMessageText: String
    let lastMessageAt: Date
    let lastMessageSenderUID: String
}

struct FriendChatMessage: Identifiable, Equatable {
    let id: String
    let threadID: String
    let senderUID: String
    let senderName: String
    let senderAvatarID: String
    let senderLevel: Int
    let text: String
    let createdAt: Date
}

enum StudioPlannerEventType: String, CaseIterable, Identifiable {
    case lesson
    case studioClass = "studio_class"
    case recital

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lesson: return "Lesson"
        case .studioClass: return "Studio Class"
        case .recital: return "Recital"
        }
    }
}

struct StudioPlannerParticipant: Identifiable, Equatable {
    let id: String
    let displayName: String
    let pieceTitle: String
    let durationMinutes: Int
}

struct StudioPlannerEvent: Identifiable, Equatable {
    let id: String
    let type: StudioPlannerEventType
    let title: String
    let notes: String
    let location: String
    let startAt: Date
    let endAt: Date
    let createdByUID: String
    let participants: [StudioPlannerParticipant]
    let calendarSyncEnabled: Bool
    let calendarProvider: String?
    let externalEventID: String?
    let updatedAt: Date
}

struct StudioLessonTemplate: Identifiable, Equatable {
    let id: String
    let title: String
    let notes: String
    let location: String
    let weekday: Int // 1...7, Gregorian Sunday-based
    let startHour: Int
    let startMinute: Int
    let durationMinutes: Int
    let participants: [StudioPlannerParticipant]
    let updatedAt: Date
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
    case invalidPlannerTitle
    case invalidPlannerDateRange
    case invalidLessonTemplate
    case chatRequiresFriendship

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
        case .invalidPlannerTitle: return "Event title must be 2-80 characters."
        case .invalidPlannerDateRange: return "End time must be after start time."
        case .invalidLessonTemplate: return "Lesson template is invalid."
        case .chatRequiresFriendship: return "You can only chat with friends."
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

    func listenToPlannerEvents(
        studioID: String,
        onChange: @escaping @MainActor ([StudioPlannerEvent]) -> Void
    ) -> ListenerRegistration {
        db.collection("studios")
            .document(studioID)
            .collection("events")
            .order(by: "startAt", descending: false)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = (snap?.documents ?? []).compactMap(self.parsePlannerEvent)
                    onChange(rows)
                }
            }
    }

    func createPlannerEvent(
        studioID: String,
        teacherUID: String,
        type: StudioPlannerEventType,
        rawTitle: String,
        rawNotes: String,
        rawLocation: String,
        startAt: Date,
        endAt: Date,
        participants: [StudioPlannerParticipant],
        calendarSyncEnabled: Bool,
        calendarProvider: String? = nil,
        externalEventID: String? = nil
    ) async throws -> StudioPlannerEvent {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(title.count) else {
            throw FirebaseStudiosError.invalidPlannerTitle
        }
        guard endAt > startAt else {
            throw FirebaseStudiosError.invalidPlannerDateRange
        }

        let participantPayload: [[String: Any]] = participants.map {
            [
                "uid": $0.id,
                "displayName": $0.displayName,
                "pieceTitle": $0.pieceTitle,
                "durationMinutes": max(0, $0.durationMinutes)
            ]
        }

        let now = Date()
        let ref = db.collection("studios")
            .document(studioID)
            .collection("events")
            .document()

        try await ref.setData([
            "type": type.rawValue,
            "title": title,
            "notes": notes,
            "location": location,
            "startAt": Timestamp(date: startAt),
            "endAt": Timestamp(date: endAt),
            "createdByUid": teacherUID,
            "participants": participantPayload,
            "calendarSyncEnabled": calendarSyncEnabled,
            "calendarProvider": calendarProvider as Any,
            "externalEventId": externalEventID as Any,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ])

        return StudioPlannerEvent(
            id: ref.documentID,
            type: type,
            title: title,
            notes: notes,
            location: location,
            startAt: startAt,
            endAt: endAt,
            createdByUID: teacherUID,
            participants: participants,
            calendarSyncEnabled: calendarSyncEnabled,
            calendarProvider: calendarProvider,
            externalEventID: externalEventID,
            updatedAt: now
        )
    }

    func updatePlannerEventExternalID(
        studioID: String,
        eventID: String,
        externalEventID: String?
    ) async throws {
        try await db.collection("studios")
            .document(studioID)
            .collection("events")
            .document(eventID)
            .setData([
                "externalEventId": externalEventID as Any,
                "calendarProvider": externalEventID == nil ? NSNull() : "apple_calendar",
                "calendarSyncEnabled": externalEventID != nil,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    func updatePlannerEvent(
        studioID: String,
        eventID: String,
        type: StudioPlannerEventType,
        rawTitle: String,
        rawNotes: String,
        rawLocation: String,
        startAt: Date,
        endAt: Date,
        participants: [StudioPlannerParticipant],
        calendarSyncEnabled: Bool
    ) async throws {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(title.count) else {
            throw FirebaseStudiosError.invalidPlannerTitle
        }
        guard endAt > startAt else {
            throw FirebaseStudiosError.invalidPlannerDateRange
        }

        let participantPayload: [[String: Any]] = participants.map {
            [
                "uid": $0.id,
                "displayName": $0.displayName,
                "pieceTitle": $0.pieceTitle,
                "durationMinutes": max(0, $0.durationMinutes)
            ]
        }

        try await db.collection("studios")
            .document(studioID)
            .collection("events")
            .document(eventID)
            .setData([
                "type": type.rawValue,
                "title": title,
                "notes": notes,
                "location": location,
                "startAt": Timestamp(date: startAt),
                "endAt": Timestamp(date: endAt),
                "participants": participantPayload,
                "calendarSyncEnabled": calendarSyncEnabled,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    func listenToLessonTemplates(
        studioID: String,
        onChange: @escaping @MainActor ([StudioLessonTemplate]) -> Void
    ) -> ListenerRegistration {
        db.collection("studios")
            .document(studioID)
            .collection("lessonTemplates")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snap, _ in
                Task { @MainActor in
                    let rows = (snap?.documents ?? []).compactMap(self.parseLessonTemplate)
                    onChange(rows)
                }
            }
    }

    func createLessonTemplate(
        studioID: String,
        teacherUID: String,
        rawTitle: String,
        rawNotes: String,
        rawLocation: String,
        weekday: Int,
        startHour: Int,
        startMinute: Int,
        durationMinutes: Int,
        participants: [StudioPlannerParticipant]
    ) async throws {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(title.count),
              (1...7).contains(weekday),
              (0...23).contains(startHour),
              (0...59).contains(startMinute),
              durationMinutes > 0 else {
            throw FirebaseStudiosError.invalidLessonTemplate
        }

        let participantPayload: [[String: Any]] = participants.map {
            [
                "uid": $0.id,
                "displayName": $0.displayName,
                "pieceTitle": $0.pieceTitle,
                "durationMinutes": max(0, $0.durationMinutes)
            ]
        }

        try await db.collection("studios")
            .document(studioID)
            .collection("lessonTemplates")
            .document()
            .setData([
                "title": title,
                "notes": notes,
                "location": location,
                "weekday": weekday,
                "startHour": startHour,
                "startMinute": startMinute,
                "durationMinutes": durationMinutes,
                "participants": participantPayload,
                "createdByUid": teacherUID,
                "updatedAt": FieldValue.serverTimestamp(),
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    func deleteLessonTemplate(studioID: String, templateID: String) async throws {
        try await db.collection("studios")
            .document(studioID)
            .collection("lessonTemplates")
            .document(templateID)
            .delete()
    }

    func deletePlannerEvent(studioID: String, eventID: String) async throws {
        try await db.collection("studios")
            .document(studioID)
            .collection("events")
            .document(eventID)
            .delete()
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
            .addSnapshotListener { snap, error in
                if let error {
                    PBLog.firebase.error("Studio chat listen failed studio=\(studioID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
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
        PBLog.firebase.info("Studio chat sent studio=\(studioID, privacy: .public) sender=\(senderUID, privacy: .private)")
    }

    func listenToStudioLatestMessage(
        studioID: String,
        onChange: @escaping @MainActor (StudioChatMessage?) -> Void
    ) -> ListenerRegistration {
        db.collection("studios")
            .document(studioID)
            .collection("messages")
            .order(by: "createdAt", descending: true)
            .limit(to: 1)
            .addSnapshotListener { snap, error in
                if let error {
                    PBLog.firebase.error("Studio latest message listen failed studio=\(studioID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                Task { @MainActor in
                    let message = snap?.documents.first.flatMap { self.parseChatMessage(studioID: studioID, document: $0) }
                    onChange(message)
                }
            }
    }

    func listenToBuddyDirectory(
        uid: String,
        onChange: @escaping @MainActor ([StudioMemberSummary]) -> Void
    ) -> ListenerRegistration {
        db.collection("friendships")
            .document(uid)
            .collection("buddies")
            .addSnapshotListener { snap, error in
                if let error {
                    PBLog.firebase.error("Buddy directory listen failed uid=\(uid, privacy: .private): \(error.localizedDescription, privacy: .public)")
                }
                Task { @MainActor in
                    let rows: [StudioMemberSummary] = (snap?.documents ?? []).compactMap { doc in
                        let data = doc.data()
                        guard let displayName = data["displayName"] as? String else { return nil }
                        let avatarID = (data["avatarID"] as? String) ?? "avatar_note"
                        let level = max(1, (data["publicLevel"] as? Int) ?? 1)
                        let joinedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                        return StudioMemberSummary(
                            id: doc.documentID,
                            displayName: displayName,
                            role: .student,
                            joinedAt: joinedAt,
                            avatarID: avatarID,
                            publicLevel: level
                        )
                    }
                    onChange(rows.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })
                }
            }
    }

    func listenToFriendChatThreads(
        uid: String,
        onChange: @escaping @MainActor ([FriendChatThread]) -> Void
    ) -> ListenerRegistration {
        db.collection("friendChats")
            .whereField("participants", arrayContains: uid)
            .addSnapshotListener { snap, error in
                if let error {
                    PBLog.firebase.error("Friend chat thread listen failed uid=\(uid, privacy: .private): \(error.localizedDescription, privacy: .public)")
                }
                Task { @MainActor in
                    let rows = (snap?.documents ?? []).compactMap(self.parseFriendChatThread)
                        .sorted { $0.lastMessageAt > $1.lastMessageAt }
                    onChange(rows)
                }
            }
    }

    func listenToFriendMessages(
        threadID: String,
        limit: Int = 250,
        onChange: @escaping @MainActor ([FriendChatMessage]) -> Void
    ) -> ListenerRegistration {
        db.collection("friendChats")
            .document(threadID)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(to: max(20, min(limit, 500)))
            .addSnapshotListener { snap, error in
                if let error {
                    PBLog.firebase.error("Friend message listen failed thread=\(threadID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                Task { @MainActor in
                    let rows = (snap?.documents ?? []).compactMap { self.parseFriendMessage(threadID: threadID, document: $0) }
                    onChange(rows)
                }
            }
    }

    func ensureFriendThread(currentUID: String, friendUID: String) async throws {
        guard currentUID != friendUID else { return }
        let friendship = try await db.collection("friendships")
            .document(currentUID)
            .collection("buddies")
            .document(friendUID)
            .getDocument()
        guard friendship.exists else {
            throw FirebaseStudiosError.chatRequiresFriendship
        }

        let threadID = friendThreadID(uidA: currentUID, uidB: friendUID)
        try await db.collection("friendChats")
            .document(threadID)
            .setData([
                "participants": [currentUID, friendUID].sorted(),
                "lastMessageText": "",
                "lastMessageAt": FieldValue.serverTimestamp(),
                "lastMessageSenderUid": "",
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    func sendFriendMessage(
        senderUID: String,
        recipientUID: String,
        senderName: String,
        senderAvatarID: String,
        senderLevel: Int,
        rawText: String
    ) async throws {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard senderUID != recipientUID else { return }

        let friendshipA = try await db.collection("friendships")
            .document(senderUID)
            .collection("buddies")
            .document(recipientUID)
            .getDocument()
        guard friendshipA.exists else {
            throw FirebaseStudiosError.chatRequiresFriendship
        }

        let threadID = friendThreadID(uidA: senderUID, uidB: recipientUID)
        let threadRef = db.collection("friendChats").document(threadID)
        let messageRef = threadRef.collection("messages").document()
        let now = FieldValue.serverTimestamp()
        let participants = [senderUID, recipientUID].sorted()

        let batch = db.batch()
        batch.setData([
            "participants": participants,
            "lastMessageText": String(text.prefix(700)),
            "lastMessageAt": now,
            "lastMessageSenderUid": senderUID,
            "updatedAt": now
        ], forDocument: threadRef, merge: true)
        batch.setData([
            "senderUid": senderUID,
            "senderName": senderName,
            "senderAvatarID": senderAvatarID,
            "senderLevel": max(1, senderLevel),
            "text": String(text.prefix(700)),
            "createdAt": now
        ], forDocument: messageRef, merge: true)
        try await batch.commit()
        PBLog.firebase.info("Friend chat sent thread=\(threadID, privacy: .public) sender=\(senderUID, privacy: .private)")
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

    private func parsePlannerEvent(_ doc: QueryDocumentSnapshot) -> StudioPlannerEvent? {
        let data = doc.data()
        guard
            let typeRaw = data["type"] as? String,
            let type = StudioPlannerEventType(rawValue: typeRaw),
            let title = data["title"] as? String,
            let startAt = (data["startAt"] as? Timestamp)?.dateValue(),
            let endAt = (data["endAt"] as? Timestamp)?.dateValue(),
            let createdByUID = data["createdByUid"] as? String
        else {
            return nil
        }

        let notes = (data["notes"] as? String) ?? ""
        let location = (data["location"] as? String) ?? ""
        let rawParticipants = (data["participants"] as? [[String: Any]]) ?? []
        let participants: [StudioPlannerParticipant] = rawParticipants.compactMap { row in
            guard let uid = row["uid"] as? String,
                  let displayName = row["displayName"] as? String else {
                return nil
            }
            return StudioPlannerParticipant(
                id: uid,
                displayName: displayName,
                pieceTitle: (row["pieceTitle"] as? String) ?? "",
                durationMinutes: max(0, (row["durationMinutes"] as? Int) ?? 0)
            )
        }
        let calendarSyncEnabled = (data["calendarSyncEnabled"] as? Bool) ?? false
        let calendarProvider = data["calendarProvider"] as? String
        let externalEventID = data["externalEventId"] as? String
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast

        return StudioPlannerEvent(
            id: doc.documentID,
            type: type,
            title: title,
            notes: notes,
            location: location,
            startAt: startAt,
            endAt: endAt,
            createdByUID: createdByUID,
            participants: participants,
            calendarSyncEnabled: calendarSyncEnabled,
            calendarProvider: calendarProvider,
            externalEventID: externalEventID,
            updatedAt: updatedAt
        )
    }

    private func parseLessonTemplate(_ doc: QueryDocumentSnapshot) -> StudioLessonTemplate? {
        let data = doc.data()
        guard
            let title = data["title"] as? String,
            let weekday = data["weekday"] as? Int,
            let startHour = data["startHour"] as? Int,
            let startMinute = data["startMinute"] as? Int,
            let durationMinutes = data["durationMinutes"] as? Int
        else {
            return nil
        }

        let notes = (data["notes"] as? String) ?? ""
        let location = (data["location"] as? String) ?? ""
        let rawParticipants = (data["participants"] as? [[String: Any]]) ?? []
        let participants: [StudioPlannerParticipant] = rawParticipants.compactMap { row in
            guard let uid = row["uid"] as? String,
                  let displayName = row["displayName"] as? String else {
                return nil
            }
            return StudioPlannerParticipant(
                id: uid,
                displayName: displayName,
                pieceTitle: (row["pieceTitle"] as? String) ?? "",
                durationMinutes: max(0, (row["durationMinutes"] as? Int) ?? 0)
            )
        }
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
        return StudioLessonTemplate(
            id: doc.documentID,
            title: title,
            notes: notes,
            location: location,
            weekday: weekday,
            startHour: startHour,
            startMinute: startMinute,
            durationMinutes: durationMinutes,
            participants: participants,
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

    private func parseFriendChatThread(_ document: QueryDocumentSnapshot) -> FriendChatThread? {
        let data = document.data()
        guard let participants = data["participants"] as? [String],
              participants.count == 2 else {
            return nil
        }
        let lastMessageText = (data["lastMessageText"] as? String) ?? ""
        let lastMessageAt = (data["lastMessageAt"] as? Timestamp)?.dateValue() ?? .distantPast
        let lastMessageSenderUID = (data["lastMessageSenderUid"] as? String) ?? ""
        return FriendChatThread(
            id: document.documentID,
            participants: participants,
            lastMessageText: lastMessageText,
            lastMessageAt: lastMessageAt,
            lastMessageSenderUID: lastMessageSenderUID
        )
    }

    private func parseFriendMessage(threadID: String, document: QueryDocumentSnapshot) -> FriendChatMessage? {
        let data = document.data()
        guard let senderUID = data["senderUid"] as? String,
              let senderName = data["senderName"] as? String,
              let text = data["text"] as? String else {
            return nil
        }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
        return FriendChatMessage(
            id: document.documentID,
            threadID: threadID,
            senderUID: senderUID,
            senderName: senderName,
            senderAvatarID: (data["senderAvatarID"] as? String) ?? "avatar_note",
            senderLevel: max(1, (data["senderLevel"] as? Int) ?? 1),
            text: text,
            createdAt: createdAt
        )
    }

    func friendThreadID(uidA: String, uidB: String) -> String {
        [uidA, uidB].sorted().joined(separator: "__")
    }

    private func makeInviteCode() -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let numbers = Array("23456789")
        let p1 = String((0..<3).map { _ in letters.randomElement() ?? "A" })
        let p2 = String((0..<3).map { _ in numbers.randomElement() ?? "2" })
        return "\(p1)-\(p2)"
    }
}
