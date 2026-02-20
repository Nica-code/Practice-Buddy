import SwiftUI
import SwiftData
import FirebaseCore
import CoreText

@main
struct PracticeBuddyApp: App {
    @StateObject private var firebase = FirebaseBootstrap()

    // Your project already stores a theme raw string in AppStorage.
    // We won't assume exact enum cases; we'll map strings safely.
    @AppStorage("pb.settings.theme") private var themeRaw: String = "system"

    init() {
        PBFontRegistrar.registerBundledFonts()

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(mappedColorScheme(from: themeRaw))
                .task {
                    await firebase.start()
                }
        }
        .modelContainer(for: PracticeSessionModel.self)
        .environmentObject(firebase)
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

private enum PBFontRegistrar {
    static func registerBundledFonts() {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: Bundle.main.bundleURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "ttf" || ext == "otf" else { continue }

            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, &error)
        }
    }
}
