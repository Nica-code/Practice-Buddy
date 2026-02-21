import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseMessaging
import CoreText
import UserNotifications
import UIKit

@main
struct PracticeBuddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var firebase = FirebaseBootstrap()
    @StateObject private var purchaseManager = PurchaseManager()

    // Your project already stores a theme raw string in AppStorage.
    // We won't assume exact enum cases; we'll map strings safely.
    @AppStorage("pb.settings.theme") private var themeRaw: String = "system"

    init() {
        PBFontRegistrar.registerBundledFonts()
        UNUserNotificationCenter.current().delegate = PBNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(mappedColorScheme(from: themeRaw))
                .task {
                    await firebase.start()
                }
        }
        .modelContainer(for: [PracticeSessionModel.self, LoopPracticeLogModel.self, PracticePlanLogModel.self, RhythmAccuracyTakeModel.self, RunThroughModel.self])
        .environmentObject(firebase)
        .environmentObject(purchaseManager)
    }

    private func mappedColorScheme(from raw: String) -> ColorScheme? {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Accept common values: "auto", "system", "systemdefault", etc.
        if v.contains("auto") || v.contains("system") {
            return nil
        }
        if v.contains("light") {
            return .light
        }
        if v.contains("dark") {
            return .dark
        }
        return nil
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
}

final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        Messaging.messaging().delegate = self
        registerForPushNotifications(application)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // no-op
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        Task {
            await PushTokenManager.shared.upsertCurrentToken(fcmToken)
        }
    }

    private func registerForPushNotifications(_ application: UIApplication) {
        let defaults = UserDefaults.standard
        let assignmentsEnabled = defaults.object(forKey: "pb.notifications.assignments") as? Bool ?? true
        let buddiesEnabled = defaults.object(forKey: "pb.notifications.buddies") as? Bool ?? true
        if !(assignmentsEnabled || buddiesEnabled) {
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }
}

private enum PBFontRegistrar {
    private static let bundledFonts: [(name: String, ext: String)] = [
        ("PlayfairDisplay-Regular", "ttf"),
        ("Lora-Regular", "ttf"),
        ("IBMPlexMono-Regular", "ttf"),
        ("Manrope-Regular", "ttf"),
        ("RobotoMono-Regular", "ttf"),
        ("SpaceGrotesk-Regular", "ttf"),
        ("Outfit-Regular", "ttf"),
        ("SpaceMono-Regular", "ttf"),
        ("Fredoka-Regular", "ttf"),
        ("Quicksand-Regular", "ttf"),
        ("NunitoSans-VariableFont_YTLC,opsz,wdth,wght", "ttf")
    ]

    static func registerBundledFonts() {
        for font in bundledFonts {
            guard let fileURL = Bundle.main.url(
                forResource: font.name,
                withExtension: font.ext,
                subdirectory: "Fonts"
            ) else {
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, &error)
        }
    }
}
