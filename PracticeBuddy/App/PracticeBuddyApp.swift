import SwiftUI
import SwiftData
import os
import FirebaseCore
import UserNotifications
import UIKit
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

@main
struct PracticeBuddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var firebase: FirebaseBootstrap
    @StateObject private var purchaseManager: PurchaseManager
    @AppStorage("pb.settings.language") private var appLanguageRaw: String = AppLanguage.system.rawValue

    init() {
        PBSwiftDataBootstrap.ensureApplicationSupportDirectory()
        _firebase = StateObject(wrappedValue: FirebaseBootstrap())
        _purchaseManager = StateObject(wrappedValue: PurchaseManager())
        UNUserNotificationCenter.current().delegate = PBNotificationDelegate.shared
        PBNotificationCenter.registerCategories()
    }

    var body: some Scene {
        let appLanguage = AppLanguage(rawValue: appLanguageRaw) ?? .system
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environment(\.locale, Locale(identifier: appLanguage.localeIdentifier))
                .task {
                    await firebase.start()
                }
        }
        .modelContainer(for: [PracticeSessionModel.self, LoopPracticeLogModel.self, PracticePlanLogModel.self, RhythmAccuracyTakeModel.self, RunThroughModel.self, ScaleIntonationTakeModel.self])
        .environmentObject(firebase)
        .environmentObject(purchaseManager)
    }
}

private final class PBNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PBNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let route = PBNotificationCenter.route(for: response) {
            NotificationCenter.default.post(
                name: .pbNotificationRouteRequested,
                object: route
            )
        }
        completionHandler()
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        FirebaseBootstrap.markConfiguredAtLaunch()
#if canImport(FirebaseMessaging)
        Messaging.messaging().delegate = self
#endif
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PBLog.firebase.info("APNs registration succeeded. Token length: \(token.count, privacy: .public)")
        Task { @MainActor in
            await PushTokenManager.shared.upsertCurrentToken(token, kind: .apns)
        }
#if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
#endif
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PBLog.firebase.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }
}

#if canImport(FirebaseMessaging)
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        Task { @MainActor in
            await PushTokenManager.shared.upsertCurrentToken(fcmToken, kind: .fcm)
        }
    }
}
#endif

private enum PBSwiftDataBootstrap {
    static func ensureApplicationSupportDirectory() {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            // Best-effort hardening; SwiftData/CoreData still has its own recovery path.
        }
    }
}
