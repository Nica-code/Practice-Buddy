import SwiftUI
import SwiftData
import FirebaseCore
import UserNotifications
import UIKit

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
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            await PushTokenManager.shared.upsertCurrentToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Non-fatal in dev and simulator contexts.
    }
}

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
