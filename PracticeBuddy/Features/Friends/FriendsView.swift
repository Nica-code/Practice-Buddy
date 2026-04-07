import SwiftUI
import SwiftData
import UIKit
import AuthenticationServices

struct FriendsView: View {
    private struct LeaderboardActionUser: Identifiable, Hashable {
        let id: String
        let displayName: String
    }

    private enum SocialScrollAnchor: String {
        case pendingRequests = "social.pendingRequests"
        case leaderboard = "social.leaderboard"
    }

    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var duelLeague: DuelLeagueManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var firebase: FirebaseBootstrap

    @StateObject private var buddiesVM = BuddiesViewModel()

    @State private var inviteCodeInput: String = ""
    @State private var displayNameInput: String = ""
    @State private var expandedLeaderboardUserID: String?
    @State private var profileTarget: LeaderboardActionUser?
    @State private var pendingLeaderboardRefreshTask: Task<Void, Never>?

    @AppStorage("pb.tab.selection") private var selectedTab: Int = 0
    @AppStorage("pb.social.jumpTarget") private var socialJumpTargetRaw: String = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    socialSection("Account") {
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
            .onChange(of: socialJumpTargetRaw) { _, value in
                guard !value.isEmpty else { return }
                let raw = value.split(separator: ":").first.map(String.init) ?? value
                guard let anchor = SocialScrollAnchor(rawValue: raw) else { return }
                withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                    proxy.scrollTo(anchor.rawValue, anchor: .top)
                }
            }
        }
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .task(id: firebase.currentUserID) {
            guard let uid = firebase.currentUserID else { return }
            await buddiesVM.start(for: uid)
            await buddiesVM.syncPublicLevel(journey.level)
            await buddiesVM.refreshLeaderboard()
        }
        .task(id: journey.level) {
            guard firebase.currentUserID != nil else { return }
            await buddiesVM.syncPublicLevel(journey.level)
        }
        .onChange(of: buddiesVM.buddies) { _, _ in
            queueLeaderboardRefresh()
        }
        .onChange(of: buddiesVM.myProfile?.displayName) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            displayNameInput = newValue
        }
        .onDisappear {
            pendingLeaderboardRefreshTask?.cancel()
            pendingLeaderboardRefreshTask = nil
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $profileTarget) { target in
            PublicUserProfileView(
                userID: target.id,
                fallbackDisplayName: target.displayName
            )
        }
    }

    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    private func normalizedDisplayName(_ raw: String) -> String {
        FirebaseBuddiesRepository.normalizedDisplayName(from: raw)
    }

    private func socialSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PBSectionHeaderLabel(title: title)
            content()
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let profile = buddiesVM.myProfile {
                Button {
                    selectedTab = 3
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

                    ShareLink(item: inviteShareText(for: profile)) {
                        Text("Invite")
                            .font(type.footnote)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        PBHaptics.tap()
                        buddiesVM.statusMessage = "Invite link ready to send."
                        PBGrowthMetrics.record(.buddyInviteShareClicked)
                    })
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
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
                            .onChange(of: displayNameInput) { _, newValue in
                                let normalized = normalizedDisplayName(newValue)
                                if normalized != newValue {
                                    displayNameInput = normalized
                                }
                            }

                        Button("Save") {
                            Task { await buddiesVM.saveDisplayName(displayNameInput) }
                        }
                        .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
                    }

                    Text("You can set your display name once.")
                        .font(type.footnote)
                        .foregroundStyle(theme.textSecondary)
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
            friendCodeEntryRow
            incomingRequestsSection
            outgoingRequestsSection
            circleSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
        .id(SocialScrollAnchor.pendingRequests.rawValue)
    }

    private var friendCodeEntryRow: some View {
        FriendCodeEntryRow(inviteCodeInput: $inviteCodeInput, palette: palette, type: type) { code in
            PBHaptics.tap()
            Task {
                _ = await buddiesVM.sendInvite(friendCode: code)
                await buddiesVM.refreshLeaderboard()
            }
        }
    }

    @ViewBuilder
    private var incomingRequestsSection: some View {
        if !buddiesVM.incomingInvites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Incoming Requests")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                ForEach(buddiesVM.incomingInvites) { invite in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invite.fromDisplayName)
                                .font(type.body)
                                .foregroundStyle(theme.textPrimary)
                            Text(invite.fromFriendCode)
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        Button("Accept") {
                            PBHaptics.tap()
                            Task { await buddiesVM.acceptInvite(invite) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)

                        Button("Reject", role: .destructive) {
                            PBHaptics.tap()
                            Task { await buddiesVM.declineInvite(invite) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }
            }
        }
    }

    @ViewBuilder
    private var outgoingRequestsSection: some View {
        if !buddiesVM.outgoingInvites.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pending Requests")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                ForEach(buddiesVM.outgoingInvites) { invite in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invite.toDisplayName)
                                .font(type.body)
                                .foregroundStyle(theme.textPrimary)
                            Text("Awaiting response")
                                .font(type.footnote)
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .foregroundStyle(theme.textSecondary)
                            Button("Cancel", role: .destructive) {
                                PBHaptics.tap()
                                Task { await buddiesVM.cancelOutgoingInvite(invite) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }
            }
        }
    }

    private var circleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Practice Buddies")
                .font(type.footnote)
                .foregroundStyle(theme.textSecondary)

            if buddiesVM.buddies.isEmpty {
                Text("Add friends to build your buddy list.")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pbSurfaceCard(palette: palette)
            } else {
                ForEach(Array(buddiesVM.buddies.enumerated()), id: \.element.id) { _, buddy in
                    HStack {
                        PBAvatarView(avatarID: buddy.avatarID, displayName: buddy.displayName, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(buddy.displayName)
                                .font(type.body)
                                .foregroundStyle(theme.textPrimary)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(buddiesVM.isBuddyOnline(buddy.id) ? Color.green : theme.textSecondary.opacity(0.45))
                                    .frame(width: 7, height: 7)
                                Text(buddiesVM.isBuddyOnline(buddy.id) ? "Online" : "Offline")
                                    .font(type.body)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            HStack(spacing: 8) {
                                Text(L10n.f("Level %@", "\(buddiesVM.buddyDisplayLevel(buddy.id))"))
                                    .font(type.footnote)
                                    .foregroundStyle(theme.textSecondary)
                                    .monospacedDigit()
                                Text("•")
                                    .font(type.footnote)
                                    .foregroundStyle(theme.textSecondary)
                                let league = buddiesVM.buddyDisplayLeague(buddy.id)
                                Text(league)
                                    .font(type.fontChoice.headlineFont(size: 11, weight: .semibold))
                                    .foregroundStyle(leagueChipTextColor(for: league))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(leagueChipColor(for: league).opacity(0.18))
                                    .clipShape(Capsule())
                            }
                        }
                        Spacer()
                        Button("Visit Profile") {
                            PBHaptics.tap()
                            profileTarget = LeaderboardActionUser(id: buddy.id, displayName: buddy.displayName)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .font(type.footnote)
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }
            }
        }
    }

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if buddiesVM.leaderboardRows.isEmpty {
                Text("Add buddies to see ranking.")
                    .font(type.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pbSurfaceCard(palette: palette)
            } else {
                ForEach(Array(buddiesVM.leaderboardRows.enumerated()), id: \.element.id) { idx, row in
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                expandedLeaderboardUserID = (expandedLeaderboardUserID == row.id) ? nil : row.id
                            }
                        } label: {
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
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                    .allowsTightening(true)

                                Spacer()

                                PBLevelBadgeView(level: row.publicLevel)

                                Text(L10n.f("Rating %@", "\(row.duelRating)"))
                                    .font(type.footnote)
                                    .foregroundStyle(theme.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)

                        if expandedLeaderboardUserID == row.id {
                            HStack(spacing: 8) {
                                Button("Go to Profile") {
                                    PBHaptics.tap()
                                    profileTarget = LeaderboardActionUser(id: row.id, displayName: row.name)
                                    expandedLeaderboardUserID = nil
                                }
                                .buttonStyle(.bordered)

                                Button("Duel Challenge") {
                                    PBHaptics.tap()
                                    Task {
                                        await duelLeague.inviteTargetedDuel(targetUID: row.id, source: .friend, octaves: duelLeague.activeLeagueRequirement.octaves)
                                    }
                                    expandedLeaderboardUserID = nil
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(firebase.currentUserID == row.id || firebase.isAnonymousUser)
                            }
                            .font(type.footnote)
                        }
                    }
                    .padding(10)
                    .pbSurfaceCard(palette: palette)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
        .id(SocialScrollAnchor.leaderboard.rawValue)
    }

    private func leagueChipColor(for league: String) -> Color {
        switch league.lowercased() {
        case "gold":
            return .yellow
        case "silver":
            return .gray
        default:
            return .brown
        }
    }

    private func leagueChipTextColor(for league: String) -> Color {
        switch league.lowercased() {
        case "gold":
            return .yellow
        case "silver":
            return .gray
        default:
            return .brown
        }
    }

    private func inviteShareText(for profile: FirebaseUserProfile) -> String {
        let deepLink = buddyInviteURL(for: profile.friendCode)?.absoluteString ?? ""
        return [
            "Let's practice together on PracticeBuddy.",
            "My friend code: \(profile.friendCode)",
            deepLink.isEmpty ? "" : "Open on iPhone: \(deepLink)",
            "If the link does not open, paste the code in Social -> Friends."
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private func buddyInviteURL(for friendCode: String) -> URL? {
        var components = URLComponents()
        components.scheme = "practicebuddy"
        components.host = "add-buddy"
        components.queryItems = [URLQueryItem(name: "code", value: friendCode)]
        return components.url
    }

    private func queueLeaderboardRefresh() {
        pendingLeaderboardRefreshTask?.cancel()
        pendingLeaderboardRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await buddiesVM.refreshLeaderboard()
        }
    }
}
