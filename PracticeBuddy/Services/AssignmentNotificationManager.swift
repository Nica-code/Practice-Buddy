import Foundation
import UserNotifications

@MainActor
final class AssignmentNotificationManager {
    static let shared = AssignmentNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let bootstrapPrefix = "pb.assignment.notify.bootstrap"
    private let seenPrefix = "pb.assignment.notify.seen"

    private init() {}

    func handleVisibleAssignmentsForStudent(
        uid: String,
        studioID: String,
        assignments: [StudioAssignment]
    ) async {
        let notificationsEnabled = defaults.object(forKey: "pb.notifications.assignments") as? Bool ?? true
        guard notificationsEnabled else { return }

        let keyBase = "\(uid)::\(studioID)"
        let bootstrapKey = "\(bootstrapPrefix).\(keyBase)"
        let seenKey = "\(seenPrefix).\(keyBase)"

        let ids = assignments.map(\.id)
        let currentSet = Set(ids)

        if !defaults.bool(forKey: bootstrapKey) {
            defaults.set(Array(currentSet), forKey: seenKey)
            defaults.set(true, forKey: bootstrapKey)
            return
        }

        let oldSet = Set(defaults.stringArray(forKey: seenKey) ?? [])
        let newIDs = currentSet.subtracting(oldSet)
        guard !newIDs.isEmpty else { return }

        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return }

        for assignment in assignments where newIDs.contains(assignment.id) {
            await scheduleNotification(for: assignment)
        }

        defaults.set(Array(currentSet), forKey: seenKey)
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            return true
        }
        if settings.authorizationStatus == .denied {
            return false
        }
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    private func scheduleNotification(for assignment: StudioAssignment) async {
        let content = UNMutableNotificationContent()
        content.title = "New Assignment"
        if assignment.target == .individual {
            content.body = "You received an individual assignment: \(assignment.title)"
        } else {
            content.body = "New studio assignment: \(assignment.title)"
        }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pb.assignment.\(assignment.id).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
