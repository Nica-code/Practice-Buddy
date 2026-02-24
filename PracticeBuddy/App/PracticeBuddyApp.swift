import SwiftUI
import SwiftData
import FirebaseCore
import CoreText
import UserNotifications
import UIKit

@main
struct PracticeBuddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var firebase: FirebaseBootstrap
    @StateObject private var purchaseManager: PurchaseManager
    @AppStorage("pb.settings.language") private var appLanguageRaw: String = AppLanguage.system.rawValue

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        _firebase = StateObject(wrappedValue: FirebaseBootstrap())
        _purchaseManager = StateObject(wrappedValue: PurchaseManager())
        PBFontRegistrar.registerBundledFonts()
        UNUserNotificationCenter.current().delegate = PBNotificationDelegate.shared
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
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return true
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
