import SwiftUI
import SwiftData
import Combine

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
    @StateObject private var duelLeagueManager = DuelLeagueManager()
    @StateObject private var assignmentLinkManager = AssignmentLinkManager()
    @StateObject private var warmupOfWeekManager = WarmupOfWeekManager()

    @State private var didInit = false
    @State private var sessionsCancellable: AnyCancellable?
    @State private var inviteJoinAlert: InviteJoinAlert?
    private let studiosRepository = FirebaseStudiosRepository()

    var body: some View {
        let fontChoice = PBFontChoice.byID(selectedFontID)
        let typography = PBTypography.forTheme(themeManager.theme, fontChoice: fontChoice)

        Group {
            if !firebase.isReady {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.background.ignoresSafeArea())
            } else if needsAccountSetup {
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
                        PBLazyView(JourneyView())
                            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tabItem { Label("Play", systemImage: "gamecontroller") }
                    .tag(1)

                    NavigationStack {
                        PBLazyView(StudioHubView())
                            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tabItem { Label("Social", systemImage: "person.2") }
                    .tag(2)

                    NavigationStack {
                        PBLazyView(ProfileTabView())
                            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                    .tag(3)

                    NavigationStack {
                        PBLazyView(SettingsView())
                            .navigationTitle("")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(4)
                }
            }
        }
        .onAppear {
            migrateTabSelectionIfNeeded()

            guard !didInit else { return }
            didInit = true

            store.configure(context: modelContext)
            sessionsCancellable = store.$sessions
                .sink { sessions in
                    journeyManager.handleSessionSnapshot(sessions)
                }
            themeManager.refresh()
            PBTabBarStyle.apply(colorScheme: colorScheme, accent: UIColor(themeManager.theme.accent))
            syncUserPipelines()
        }
        .onChange(of: colorScheme) {
            PBTabBarStyle.apply(colorScheme: colorScheme, accent: UIColor(themeManager.theme.accent))
        }
        .onChange(of: themeManager.theme.id) { _, _ in
            PBTabBarStyle.apply(colorScheme: colorScheme, accent: UIColor(themeManager.theme.accent))
        }
        .onChange(of: firebase.currentUserID) { _, newUID in
            _ = newUID
            syncUserPipelines()
        }
        .onChange(of: firebase.isAnonymousUser) { _, _ in
            syncUserPipelines()
        }
        .onChange(of: purchaseManager.accountType) { _, newType in
            guard scenePhase == .active, canRunRealtimePipelines else { return }
            assignmentLinkManager.start(
                uid: firebase.currentUserID,
                accountType: purchaseManager.hasRole(.student) ? .student : newType
            )
            warmupOfWeekManager.start(
                uid: firebase.currentUserID,
                accountType: purchaseManager.hasRole(.student) ? .student : newType,
                isPro: purchaseManager.isPro
            )
            Task { await assignmentLinkManager.flushPendingQueue() }
        }
        .onChange(of: purchaseManager.isPro) { _, isPro in
            guard scenePhase == .active, canRunRealtimePipelines else { return }
            warmupOfWeekManager.start(
                uid: firebase.currentUserID,
                accountType: purchaseManager.hasRole(.student) ? .student : purchaseManager.accountType,
                isPro: isPro
            )
            Task { await assignmentLinkManager.flushPendingQueue() }
        }
        .onChange(of: purchaseManager.enabledRoles) { _, _ in
            guard scenePhase == .active else { return }
            syncUserPipelines()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                syncUserPipelines()
            } else {
                assignmentLinkManager.pauseRealtime()
                warmupOfWeekManager.pauseRealtime()
                duelLeagueManager.pauseRealtime()
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .environmentObject(store)
        .environmentObject(journeyManager)
        .environmentObject(themeManager)
        .environmentObject(duelLeagueManager)
        .environmentObject(assignmentLinkManager)
        .environmentObject(warmupOfWeekManager)
        .pbTheme(themeManager.theme)
        .pbTypography(typography)
        .pbGlobalFontDesign(fontChoice)
        .tint(themeManager.theme.accent)
        .alert(item: $store.lastAppError) { err in
            Alert(
                title: Text(LocalizedStringKey(err.title)),
                message: Text(LocalizedStringKey(err.message)),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: $inviteJoinAlert) { state in
            Alert(
                title: Text(LocalizedStringKey(state.title)),
                message: Text(LocalizedStringKey(state.message)),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var needsAccountSetup: Bool {
        guard let uid = firebase.currentUserID, !uid.isEmpty else { return true }
        return firebase.isAnonymousUser
    }

    private var canRunRealtimePipelines: Bool {
        guard scenePhase == .active else { return false }
        guard let uid = firebase.currentUserID, !uid.isEmpty else { return false }
        guard !firebase.isAnonymousUser else { return false }
        guard !needsAccountSetup else { return false }
        return true
    }

    private var theme: PBTheme { themeManager.theme }

    private func resumeRealtimeManagers() {
        let roleForStudentPipelines: PBAccountType = purchaseManager.hasRole(.student) ? .student : purchaseManager.accountType
        assignmentLinkManager.start(uid: firebase.currentUserID, accountType: roleForStudentPipelines)
        warmupOfWeekManager.start(uid: firebase.currentUserID, accountType: roleForStudentPipelines, isPro: purchaseManager.isPro)
        Task { await assignmentLinkManager.flushPendingQueue() }
    }

    private func syncUserPipelines() {
        let linkUID: String? = {
            guard let uid = firebase.currentUserID, !uid.isEmpty, !firebase.isAnonymousUser else { return nil }
            return uid
        }()
        purchaseManager.linkToUser(uid: linkUID)

        guard canRunRealtimePipelines else {
            assignmentLinkManager.pauseRealtime()
            warmupOfWeekManager.pauseRealtime()
            duelLeagueManager.pauseRealtime()
            return
        }

        resumeRealtimeManagers()
        duelLeagueManager.start(uid: firebase.currentUserID)
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

    private func migrateTabSelectionIfNeeded() {
        let key = "pb.tab.selection.v2.migrated"
        let migrated = UserDefaults.standard.bool(forKey: key)
        guard !migrated else {
            if !(0...4).contains(selectedTab) { selectedTab = 0 }
            return
        }

        let legacyValue = selectedTab
        switch legacyValue {
        case 0: selectedTab = 0
        case 1: selectedTab = 0
        case 2: selectedTab = 2
        case 3: selectedTab = 4
        case 4, 5: selectedTab = 1
        default: selectedTab = 0
        }

        UserDefaults.standard.set(true, forKey: key)
    }
}
