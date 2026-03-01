import Foundation
import Combine
import os
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class FirebasePresenceManager: ObservableObject {
    private let db = Firestore.firestore()
    private let usersCollection = "users"
    private let heartbeatInterval: TimeInterval = 60

    private var activeUID: String?
    private var heartbeatTask: Task<Void, Never>?

    func start(uid: String) {
        let cleanedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedUID.isEmpty else {
            stop()
            return
        }
        if activeUID == cleanedUID, heartbeatTask != nil {
            return
        }

        stop()
        activeUID = cleanedUID
        writePresence(uid: cleanedUID, isOnline: true)
        startHeartbeat(uid: cleanedUID)
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        if let uid = activeUID {
            writePresence(uid: uid, isOnline: false)
        }
        activeUID = nil
    }

    private func startHeartbeat(uid: String) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                guard self.activeUID == uid else { return }
                self.writePresence(uid: uid, isOnline: true)
            }
        }
    }

    private func writePresence(uid: String, isOnline: Bool) {
        guard let authUID = Auth.auth().currentUser?.uid, authUID == uid else {
            PBLog.firebase.warning("Skipped presence write: auth user mismatch or missing. uid=\(uid, privacy: .private)")
            return
        }
        let payload: [String: Any] = [
            "presenceState": isOnline ? "online" : "offline",
            "presenceLastChanged": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection(usersCollection).document(uid).setData(payload, merge: true)
    }
}
