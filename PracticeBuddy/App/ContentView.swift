import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0
    @AppStorage(PBFontChoice.selectionKey) private var selectedFontID: String = PBFontChoice.systemDefault.id

    @StateObject private var themeManager = ThemeManager()
    @StateObject private var store = SessionStore()
    @StateObject private var assignmentLinkManager = AssignmentLinkManager()
    @StateObject private var warmupOfWeekManager = WarmupOfWeekManager()

    @State private var didInit = false

    var body: some View {
        let fontChoice = PBFontChoice.byID(selectedFontID)
        let typography = PBTypography.forTheme(themeManager.theme, fontChoice: fontChoice)

        Group {
            if needsAccountSetup {
                AccountSetupView()
            } else {
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
            }
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
        .onChange(of: themeManager.theme.id) { _, _ in
            PBTabBarStyle.apply(colorScheme: colorScheme, accent: UIColor(themeManager.theme.accent))
        }
        .onAppear {
            purchaseManager.linkToUser(uid: firebase.currentUserID)
            assignmentLinkManager.start(uid: firebase.currentUserID, accountType: purchaseManager.accountType)
            warmupOfWeekManager.start(
                uid: firebase.currentUserID,
                accountType: purchaseManager.accountType,
                isPro: purchaseManager.isPro
            )
            Task { await assignmentLinkManager.flushPendingQueue() }
        }
        .onChange(of: firebase.currentUserID) { _, newUID in
            purchaseManager.linkToUser(uid: newUID)
            assignmentLinkManager.start(uid: newUID, accountType: purchaseManager.accountType)
            warmupOfWeekManager.start(
                uid: newUID,
                accountType: purchaseManager.accountType,
                isPro: purchaseManager.isPro
            )
            Task { await assignmentLinkManager.flushPendingQueue() }
        }
        .onChange(of: purchaseManager.accountType) { _, newType in
            assignmentLinkManager.start(uid: firebase.currentUserID, accountType: newType)
            warmupOfWeekManager.start(
                uid: firebase.currentUserID,
                accountType: newType,
                isPro: purchaseManager.isPro
            )
            Task { await assignmentLinkManager.flushPendingQueue() }
        }
        .onChange(of: purchaseManager.isPro) { _, isPro in
            warmupOfWeekManager.start(
                uid: firebase.currentUserID,
                accountType: purchaseManager.accountType,
                isPro: isPro
            )
            Task { await assignmentLinkManager.flushPendingQueue() }
        }
        .environmentObject(store)
        .environmentObject(themeManager)
        .environmentObject(assignmentLinkManager)
        .environmentObject(warmupOfWeekManager)
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

    private var needsAccountSetup: Bool {
        guard firebase.currentUserID != nil else { return true }
        if firebase.isAnonymousUser { return true }
        return !purchaseManager.hasCompletedInitialRoleSelection
    }
}
