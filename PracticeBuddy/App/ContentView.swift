import SwiftUI
import SwiftData

struct ContentView: View {
    private struct InviteJoinAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0
    @AppStorage(PBFontChoice.selectionKey) private var selectedFontID: String = PBFontChoice.systemDefault.id

    @StateObject private var themeManager = ThemeManager()
    @StateObject private var store = SessionStore()
    @StateObject private var journeyManager = JourneyProgressManager()
    @StateObject private var assignmentLinkManager = AssignmentLinkManager()
    @StateObject private var warmupOfWeekManager = WarmupOfWeekManager()

    @State private var didInit = false
    @State private var inviteJoinAlert: InviteJoinAlert?
    private let studiosRepository = FirebaseStudiosRepository()

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
                        PBLazyView(JourneyView())
                            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tabItem { Label("Journey", systemImage: "figure.walk") }
                    .tag(4)

                    NavigationStack {
                        PBLazyView(StudioHubView())
                            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tabItem { Label("Studio", systemImage: "person.2") }
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
            if selectedTab == 5 { selectedTab = 4 } // migrate old Journey tab index
            if !(0...4).contains(selectedTab) { selectedTab = 0 }

            guard !didInit else { return }
            didInit = true

            store.configure(context: modelContext)
            journeyManager.handleSessionSnapshot(store.sessions)
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
            resumeRealtimeManagers()
        }
        .onChange(of: firebase.currentUserID) { _, newUID in
            purchaseManager.linkToUser(uid: newUID)
            if scenePhase == .active {
                resumeRealtimeManagers()
            }
        }
        .onChange(of: purchaseManager.accountType) { _, newType in
            guard scenePhase == .active else { return }
            assignmentLinkManager.start(uid: firebase.currentUserID, accountType: newType)
            warmupOfWeekManager.start(uid: firebase.currentUserID, accountType: newType, isPro: purchaseManager.isPro)
            Task { await assignmentLinkManager.flushPendingQueue() }
        }
        .onChange(of: purchaseManager.isPro) { _, isPro in
            guard scenePhase == .active else { return }
            warmupOfWeekManager.start(uid: firebase.currentUserID, accountType: purchaseManager.accountType, isPro: isPro)
            Task { await assignmentLinkManager.flushPendingQueue() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                resumeRealtimeManagers()
            } else {
                assignmentLinkManager.pauseRealtime()
                warmupOfWeekManager.pauseRealtime()
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .environmentObject(store)
        .environmentObject(journeyManager)
        .environmentObject(themeManager)
        .environmentObject(assignmentLinkManager)
        .environmentObject(warmupOfWeekManager)
        .onReceive(store.$sessions) { sessions in
            journeyManager.handleSessionSnapshot(sessions)
        }
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
        .alert(item: $inviteJoinAlert) { state in
            Alert(
                title: Text(state.title),
                message: Text(state.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var needsAccountSetup: Bool {
        guard firebase.currentUserID != nil else { return true }
        if firebase.isAnonymousUser { return true }
        return !purchaseManager.hasCompletedInitialRoleSelection
    }

    private func resumeRealtimeManagers() {
        assignmentLinkManager.start(uid: firebase.currentUserID, accountType: purchaseManager.accountType)
        warmupOfWeekManager.start(uid: firebase.currentUserID, accountType: purchaseManager.accountType, isPro: purchaseManager.isPro)
        Task { await assignmentLinkManager.flushPendingQueue() }
    }

    private func handleIncomingURL(_ url: URL) {
        guard let inviteCode = studioInviteCode(from: url) else { return }

        guard let uid = firebase.currentUserID, !firebase.isAnonymousUser else {
            inviteJoinAlert = InviteJoinAlert(
                title: "Sign In Required",
                message: "Please sign in first, then open the studio invite link again."
            )
            return
        }

        Task {
            do {
                try await studiosRepository.joinStudio(studentUID: uid, rawInviteCode: inviteCode)
                await MainActor.run {
                    inviteJoinAlert = InviteJoinAlert(
                        title: "Joined Studio",
                        message: "You have successfully joined the studio."
                    )
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    inviteJoinAlert = InviteJoinAlert(
                        title: "Could Not Join Studio",
                        message: msg
                    )
                }
            }
        }
    }

    private func studioInviteCode(from url: URL) -> String? {
        if let scheme = url.scheme?.lowercased(), scheme == "practicebuddy" {
            guard let host = url.host?.lowercased(), host == "join-studio" else {
                return nil
            }
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
               !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return code
            }
            let pathCode = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return pathCode.isEmpty ? nil : pathCode
        }

        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return nil }
        guard let host = url.host?.lowercased() else { return nil }
        let allowedHost = AppInfo.inviteLinkBaseURL?.host?.lowercased()
        guard host == allowedHost else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard path == "join-studio" else { return nil }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value,
           !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return code.uppercased()
        }
        return nil
    }
}
