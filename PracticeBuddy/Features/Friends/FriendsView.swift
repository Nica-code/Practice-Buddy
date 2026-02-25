import SwiftUI
import SwiftData
import UIKit
import AuthenticationServices

struct FriendsView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var journey: JourneyProgressManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var firebase: FirebaseBootstrap

    @StateObject private var buddiesVM = BuddiesViewModel()

    @State private var inviteCodeInput: String = ""
    @State private var displayNameInput: String = ""

    @AppStorage("pb.studio.selectedBuddyIDs") private var studioBuddyIDsRaw: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                socialSection("Your Studio") {
                    accountCard
                }
                socialSection("Friends") {
                    buddiesCard
                }
                socialSection("Leaderboard") {
                    leaderboardCard
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, PBLayout.padXL)
        }
        .background {
            PBBackdropView(palette: palette)
        }
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .task(id: firebase.currentUserID) {
            guard let uid = firebase.currentUserID else { return }
            await buddiesVM.start(for: uid)
            await buddiesVM.syncPracticeTotal(minutes: myTotalMinutes)
            await buddiesVM.syncPublicLevel(journey.level)
            await buddiesVM.refreshLeaderboard(myTotalMinutes: myTotalMinutes)
        }
        .task(id: myTotalMinutes) {
            guard firebase.currentUserID != nil else { return }
            await buddiesVM.syncPracticeTotal(minutes: myTotalMinutes)
            await buddiesVM.syncPublicLevel(journey.level)
            await buddiesVM.refreshLeaderboard(myTotalMinutes: myTotalMinutes)
        }
        .task(id: journey.level) {
            guard firebase.currentUserID != nil else { return }
            await buddiesVM.syncPublicLevel(journey.level)
        }
        .onChange(of: buddiesVM.buddies) { _, latest in
            let valid = Set(latest.map { $0.id })
            let filtered = selectedStudioBuddyIDs.filter { valid.contains($0) }
            if filtered != selectedStudioBuddyIDs {
                setSelectedStudioBuddyIDs(filtered)
            }

            Task { await buddiesVM.refreshLeaderboard(myTotalMinutes: myTotalMinutes) }
        }
        .onChange(of: buddiesVM.myProfile?.displayName) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            displayNameInput = newValue
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    private var myTotalMinutes: Int {
        store.totalAllMinutes
    }

    private var selectedStudioBuddyIDs: Set<String> {
        let parts = studioBuddyIDsRaw
            .split(separator: ",")
            .map { String($0) }
            .filter { !$0.isEmpty }
        return Set(parts)
    }

    private func setSelectedStudioBuddyIDs(_ ids: Set<String>) {
        studioBuddyIDsRaw = ids.sorted().joined(separator: ",")
    }

    private func toggleStudioBuddy(_ buddyID: String) {
        var current = selectedStudioBuddyIDs
        if current.contains(buddyID) {
            current.remove(buddyID)
        } else {
            current.insert(buddyID)
        }
        setSelectedStudioBuddyIDs(current)
    }

    private var studioBuddies: [BuddySummary] {
        let ids = selectedStudioBuddyIDs
        return buddiesVM.buddies.filter { ids.contains($0.id) }
    }

    private func socialSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(type.footnote.weight(.semibold))
                .foregroundStyle(theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.3)
            content()
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let profile = buddiesVM.myProfile {
                NavigationLink {
                    PBLazyView(UserProfileView(buddiesVM: buddiesVM))
                } label: {
                    HStack(spacing: 10) {
                        PBAvatarView(avatarID: profile.avatarID, displayName: profile.displayName, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("My Profile")
                                .font(type.body)
                                .foregroundStyle(theme.textPrimary)
                            Text("Avatar, bio, instrument, level")
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        PBLevelBadgeView(level: profile.publicLevel)
                    }
                }
                .buttonStyle(.plain)
                .padding(10)
                .pbSurfaceCard(palette: palette)

                if firebase.isAnonymousUser {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Guest account")
                            .font(type.body)
                            .foregroundStyle(theme.textPrimary)

                        Text("Sign in with Apple to keep your account across devices.")
                            .font(type.footnote)
                            .foregroundStyle(theme.textSecondary)

                        SignInWithAppleButton(.continue) { request in
                            firebase.prepareAppleSignInRequest(request)
                        } onCompletion: { result in
                            firebase.handleAppleSignInCompletion(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }

                HStack(spacing: 10) {
                    Text(L10n.f("Your code: %@", profile.friendCode))
                        .font(type.body)
                        .foregroundStyle(theme.textPrimary)
                        .monospacedDigit()

                    Spacer()

                    Button("Copy") {
                        UIPasteboard.general.string = profile.friendCode
                        buddiesVM.statusMessage = "Friend code copied."
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .pbSurfaceCard(palette: palette)

                if profile.nameEditUsed {
                    HStack {
                        Text("Display name")
                            .font(type.body)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text(profile.displayName)
                            .font(type.body)
                            .foregroundStyle(theme.textPrimary)
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                } else {
                    HStack(spacing: 8) {
                        TextField("Display name", text: $displayNameInput)
                            .font(type.body)
                            .padding(10)
                            .pbSurfaceCard(palette: palette)

                        Button("Save") {
                            Task { await buddiesVM.saveDisplayName(displayNameInput) }
                        }
                        .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
                    }

                    Text("You can set your display name once.")
                        .font(type.footnote)
                        .foregroundStyle(theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Studio Friends")
                        .font(type.body)
                        .foregroundStyle(theme.textPrimary)

                    if studioBuddies.isEmpty {
                        Text("No friends in Your Studio yet.")
                            .font(type.footnote)
                            .foregroundStyle(theme.textSecondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .pbSurfaceCard(palette: palette)
                    } else {
                        ForEach(studioBuddies) { buddy in
                            HStack {
                                PBAvatarView(avatarID: buddy.avatarID, displayName: buddy.displayName, size: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(buddy.displayName)
                                        .font(type.body)
                                        .foregroundStyle(theme.textPrimary)
                                    HStack(spacing: 6) {
                                        Text(buddy.friendCode)
                                            .font(type.footnote)
                                            .foregroundStyle(theme.textSecondary)
                                            .monospacedDigit()
                                        PBLevelBadgeView(level: buddy.publicLevel)
                                    }
                                }
                                Spacer()
                                Button("Remove") {
                                    toggleStudioBuddy(buddy.id)
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(10)
                            .pbSurfaceCard(palette: palette)
                        }
                    }
                }
            } else {
                Text(LocalizedStringKey(firebase.statusMessage ?? "Preparing account…"))
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
            }

            if let msg = buddiesVM.statusMessage, !msg.isEmpty {
                Text(LocalizedStringKey(msg))
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
    }

    private var buddiesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Enter friend code (ABCD-1234)", text: $inviteCodeInput)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .font(type.body)
                    .padding(10)
                    .pbSurfaceCard(palette: palette)

                Button("Add") {
                    let code = inviteCodeInput
                    inviteCodeInput = ""
                    Task {
                        if let newBuddyID = await buddiesVM.sendInvite(friendCode: code) {
                            var ids = selectedStudioBuddyIDs
                            ids.insert(newBuddyID)
                            setSelectedStudioBuddyIDs(ids)
                        }
                        await buddiesVM.refreshLeaderboard(myTotalMinutes: myTotalMinutes, force: true)
                    }
                }
                .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
    }

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Button {
                    Task { await buddiesVM.refreshLeaderboard(myTotalMinutes: myTotalMinutes, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if buddiesVM.leaderboardRows.isEmpty {
                Text("Add buddies to see ranking.")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pbSurfaceCard(palette: palette)
            } else {
                ForEach(Array(buddiesVM.leaderboardRows.enumerated()), id: \.element.id) { idx, row in
                    HStack(spacing: 8) {
                        Text("#\(idx + 1)")
                            .font(type.footnote)
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 34, alignment: .leading)
                            .monospacedDigit()

                        PBAvatarView(avatarID: row.avatarID, displayName: row.name, size: 26)

                        Text(row.name)
                            .font(type.body)
                            .foregroundStyle(theme.textPrimary)

                        Spacer()

                        PBLevelBadgeView(level: row.publicLevel)

                        Text(L10n.f("%@ min", "\(row.minutes)"))
                            .font(type.number)
                            .foregroundStyle(theme.accent)
                            .monospacedDigit()
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
    }
}
