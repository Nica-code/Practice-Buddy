import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0
    @AppStorage(PBFontChoice.selectionKey) private var selectedFontID: String = PBFontChoice.systemDefault.id

    @StateObject private var themeManager = ThemeManager()
    @StateObject private var store = SessionStore()

    @State private var didInit = false

    var body: some View {
        let fontChoice = PBFontChoice.byID(selectedFontID)
        let typography = PBTypography.forTheme(themeManager.theme, fontChoice: fontChoice)

        TabView(selection: $selectedTab) {
            NavigationStack {
                PBLazyView(HomeView())
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(0)

            NavigationStack {
                PBLazyView(HistoryView())
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("History", systemImage: "clock") }
            .tag(1)

            NavigationStack {
                PBLazyView(FriendsView())
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
            // ✅ Tab label change
            .tabItem { Label("Buddies", systemImage: "person.2") }
            .tag(2)

            NavigationStack {
                PBLazyView(SettingsView())
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)
        }
        .onAppear {
            if !(0...3).contains(selectedTab) { selectedTab = 0 }

            guard !didInit else { return }
            didInit = true

            store.configure(context: modelContext)
            themeManager.refresh()
            PBTabBarStyle.apply(colorScheme: colorScheme, accent: UIColor(themeManager.theme.accent))
        }
        .onChange(of: colorScheme) {
            PBTabBarStyle.apply(colorScheme: colorScheme, accent: UIColor(themeManager.theme.accent))
        }
        .environmentObject(store)
        .environmentObject(themeManager)
        .pbTheme(themeManager.theme)
        .pbTypography(typography)
        .pbGlobalFontDesign(fontChoice)
        .tint(themeManager.theme.accent)
        .alert(item: $store.lastAppError) { err in
            Alert(
                title: Text(err.title),
                message: Text(err.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
