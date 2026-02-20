import SwiftUI
import SwiftData

enum PBPreviewSupport {

    static func makeContainer() -> ModelContainer {
        let schema = Schema([PracticeSessionModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create preview ModelContainer: \(error)")
        }
    }

    static func seedSampleData(in context: ModelContext) {
        let now = Date()
        let cal = Calendar.current

        let samples: [(daysAgo: Int, minutes: Int, notes: String)] = [
            (0, 25, "Scales + arpeggios"),
            (0, 15, "Slow bowing"),
            (1, 40, "Etude practice"),
            (2, 30, "Repertoire run-through"),
            (4, 20, "Intonation drills"),
            (7, 60, "Full session"),
            (10, 10, "Warmup only")
        ]

        for s in samples {
            let date = cal.date(byAdding: .day, value: -s.daysAgo, to: now) ?? now
            let model = PracticeSessionModel(
                date: date,
                durationSeconds: s.minutes * 60,
                notes: s.notes
            )
            context.insert(model)
        }

        do {
            try context.save()
        } catch {
            print("Preview seed save failed: \(error)")
        }
    }

    /// A preview wrapper that matches the app's dependency injection approach.
    /// Uses `.environmentObject(store)` because SessionStore is an ObservableObject in this project.
    @MainActor
    static func contentPreview() -> some View {
        let container = makeContainer()
        seedSampleData(in: container.mainContext)

        let themeManager = ThemeManager()
        themeManager.refresh()

        let store = SessionStore()
        store.configure(context: container.mainContext)

        let fontChoice = PBFontChoice.systemDefault
        let typography = PBTypography.forTheme(themeManager.theme, fontChoice: fontChoice)

        return ContentView()
            .modelContainer(container)
            .environmentObject(store)
            .environmentObject(themeManager)
            .pbTheme(themeManager.theme)
            .pbTypography(typography)
            .pbGlobalFontDesign(fontChoice)
    }

    /// A generic helper to preview any view that expects the same environment injections.
    @MainActor
    static func wrappedPreview<Content: View>(_ view: Content) -> some View {
        let container = makeContainer()
        seedSampleData(in: container.mainContext)

        let themeManager = ThemeManager()
        themeManager.refresh()

        let store = SessionStore()
        store.configure(context: container.mainContext)

        let fontChoice = PBFontChoice.systemDefault
        let typography = PBTypography.forTheme(themeManager.theme, fontChoice: fontChoice)

        return view
            .modelContainer(container)
            .environmentObject(store)
            .environmentObject(themeManager)
            .pbTheme(themeManager.theme)
            .pbTypography(typography)
            .pbGlobalFontDesign(fontChoice)
    }
}
