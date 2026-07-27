import SwiftUI
import Combine
import FirebaseFirestore

/// A content-first inbox. It deliberately replaces the legacy List/card
/// treatment and makes every conversation row one full tap target.
struct StudioQuestMessagesView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var chat: StudioChatViewModel
    @EnvironmentObject private var buddies: BuddiesViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorScheme) private var colorScheme
    @State private var composePresented = false

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                HStack(alignment: .firstTextBaseline) {
                    StudioQuestPageTitle(title: "Messages", subtitle: "Private conversations with your accepted friends.")
                    Spacer(minLength: 12)
                    Button {
                        composePresented = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start a new message")
                }

                if chat.isLoading {
                    StudioQuestLoadingState(title: "Loading conversations…")
                } else if chat.threads.isEmpty {
                    StudioQuestEmptyState(
                        title: "No conversations yet",
                        message: "Start a private conversation with a friend from your studio circle.",
                        systemImage: "bubble.left.and.bubble.right"
                    ) {
                        composePresented = true
                    }
                } else {
                    ForEach(chat.threads) { thread in
                        StudioQuestInteractiveSurface {
                            router.navigate(
                                to: .communityMessages(friendUID: thread.friendUID, threadID: thread.id),
                                in: .community
                            )
                        } content: {
                            HStack(spacing: 12) {
                                PBAvatarView(
                                    avatarID: "avatar_note",
                                    displayName: thread.title,
                                    size: 50
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(thread.title)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Spacer(minLength: 8)
                                        if thread.lastMessageAt > .distantPast {
                                            Text(thread.lastMessageAt.formatted(.dateTime.hour().minute()))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(thread.lastMessageText.isEmpty ? "No messages yet" : thread.lastMessageText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if thread.unreadCount > 0 {
                                    Text("\(thread.unreadCount)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(StudioQuestTokens.ColorRole.cobalt, in: Capsule())
                                }
                            }
                            .padding(14)
                            .background(
                                StudioQuestTokens.ColorRole.surface(colorScheme),
                                in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous)
                            )
                        }
                        .accessibilityLabel("Open conversation with \(thread.title)")
                    }
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .task(id: firebase.currentUserID) {
            guard let uid = firebase.currentUserID, !firebase.isAnonymousUser else { return }
            chat.start(uid: uid)
        }
        .sheet(isPresented: $composePresented) {
            StudioQuestNewMessageSheet(
                friends: buddies.buddies,
                onSelect: { friend in
                    composePresented = false
                    router.navigate(to: .communityMessages(friendUID: friend.id, threadID: nil), in: .community)
                }
            )
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StudioQuestNewMessageSheet: View {
    let friends: [BuddySummary]
    let onSelect: (BuddySummary) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            StudioQuestScrollPage {
                VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
                    StudioQuestPageTitle(title: "New message", subtitle: "Choose an accepted friend.")
                    if friends.isEmpty {
                        StudioQuestEmptyState(
                            title: "No friends yet",
                            message: "Add a musician in Connections before starting a message.",
                            systemImage: "person.crop.circle.badge.plus"
                        ) { dismiss() }
                    } else {
                        ForEach(friends) { friend in
                            StudioQuestInteractiveSurface(action: { onSelect(friend) }) {
                                HStack(spacing: 12) {
                                    PBAvatarView(avatarID: friend.avatarID, displayName: friend.displayName, size: 48)
                                    Text(friend.displayName).font(.headline)
                                    Spacer()
                                }
                                .padding(14)
                                .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous))
                            }
                        }
                    }
                }
                .padding(.top, StudioQuestTokens.Spacing.lg)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

struct StudioQuestPublicProfileView: View {
    let userID: String
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var buddies: BuddiesViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = StudioQuestPublicProfileModel()
    @StateObject private var socialGraph = StudioQuestSocialGraphCoordinator()

    var body: some View {
        StudioQuestScrollPage {
            Group {
                if let profile = model.profile {
                    VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                        StudioQuestAvatarScene(
                            loadout: .starter(for: profile.avatarID),
                            layout: .init(roomID: AvatarLoadout.starter(for: profile.avatarID).roomID),
                            displayName: profile.displayName
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            Text(profile.displayName).font(StudioQuestTokens.Typography.pageTitle)
                            Text("@\(profile.handle) · \(profile.instrument)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !profile.bio.isEmpty {
                                Text(profile.bio).font(.body)
                            }
                        }
                        StudioQuestSection {
                            Label(
                                profile.isPrivate ? "Private profile" : "Public profile",
                                systemImage: profile.isPrivate ? "lock.fill" : "globe"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        relationshipActions(profile: profile)
                        Menu {
                            Button("Mute Moments", systemImage: "speaker.slash") {
                                Task { _ = await socialGraph.perform(.mute, targetUID: userID) }
                            }
                            Button("Block musician", systemImage: "hand.raised", role: .destructive) {
                                Task { _ = await socialGraph.perform(.block, targetUID: userID) }
                            }
                            Button("Report profile", systemImage: "exclamationmark.bubble", role: .destructive) {
                                Task { _ = await socialGraph.perform(.reportProfile, targetUID: userID) }
                            }
                        } label: {
                            Label("More profile actions", systemImage: "ellipsis.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous))
                        }
                        .accessibilityLabel("More actions for \(profile.displayName)")
                        if let status = socialGraph.statusMessage {
                            StudioQuestInlineStatus(text: status, kind: .warning)
                        }
                        if let error = socialGraph.errorMessage {
                            StudioQuestInlineStatus(text: error, kind: .warning)
                        }
                    }
                } else if model.isLoading {
                    StudioQuestLoadingState(title: "Loading musician…")
                } else if let errorMessage = model.errorMessage {
                    StudioQuestErrorState(
                        title: "Profile unavailable",
                        message: LocalizedStringKey(errorMessage)
                    ) {
                        Task { await loadProfileAndRelationship() }
                    }
                } else {
                    StudioQuestEmptyState(
                        title: "Profile unavailable",
                        message: "This musician may have changed their privacy or removed their profile.",
                        systemImage: "person.crop.circle.badge.questionmark"
                    ) {}
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .task(id: userID) { await loadProfileAndRelationship() }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func relationshipActions(profile: PublicProfile) -> some View {
        if !socialGraph.hasLoadedRelationship {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading relationship…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        } else {
            relationshipActionsContent(profile: profile)
        }
    }

    @ViewBuilder
    private func relationshipActionsContent(profile: PublicProfile) -> some View {
        switch buddies.relationshipState(with: userID) {
        case .me:
            profileAction(
                title: "Edit profile",
                systemImage: "pencil",
                accessibilityID: "profile.edit"
            ) {
                router.navigate(to: .profile(userID: nil), in: .you)
            }
        case .friends:
            HStack(spacing: 12) {
                profileAction(
                    title: "Message",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    accessibilityID: "profile.message",
                    isPrimary: true
                ) {
                    router.navigate(to: .communityMessages(friendUID: userID, threadID: nil), in: .community)
                }
                profileAction(
                    title: "Duel",
                    systemImage: "bolt.shield",
                    accessibilityID: "profile.duel"
                ) {
                    router.navigate(to: .duelArena(challengeID: nil), in: .quest)
                }
            }
        case .incoming(let invite):
            VStack(alignment: .leading, spacing: 12) {
                Text("\(profile.displayName) sent you a friend request.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    profileAction(
                        title: "Accept",
                        systemImage: "checkmark",
                        accessibilityID: "profile.acceptFriend",
                        isPrimary: true
                    ) {
                        Task { await buddies.acceptInvite(invite) }
                    }
                    profileAction(
                        title: "Decline",
                        systemImage: "xmark",
                        accessibilityID: "profile.declineFriend"
                    ) {
                        Task { await buddies.declineInvite(invite) }
                    }
                }
            }
        case .outgoing(let invite):
            profileAction(
                title: "Friend request sent",
                systemImage: "clock",
                accessibilityID: "profile.cancelFriendRequest"
            ) {
                Task { await buddies.cancelOutgoingInvite(invite) }
            }
        case .notFriends:
            followActions
        }
    }

    @ViewBuilder
    private var followActions: some View {
        switch socialGraph.profileRelationship {
        case .none:
            profileAction(
                title: "Follow",
                systemImage: "person.badge.plus",
                accessibilityID: "profile.follow",
                isPrimary: true,
                isEnabled: !socialGraph.isPerformingAction
            ) {
                perform(.follow)
            }
        case .requested:
            profileAction(
                title: "Requested",
                systemImage: "clock",
                accessibilityID: "profile.cancelFollowRequest",
                isEnabled: !socialGraph.isPerformingAction
            ) {
                perform(.unfollow)
            }
        case .following, .mutualFollowing:
            profileAction(
                title: "Following",
                systemImage: "checkmark",
                accessibilityID: "profile.unfollow",
                isEnabled: !socialGraph.isPerformingAction
            ) {
                perform(.unfollow)
            }
        case .followsYou:
            profileAction(
                title: "Follow back",
                systemImage: "person.badge.plus",
                accessibilityID: "profile.followBack",
                isPrimary: true,
                isEnabled: !socialGraph.isPerformingAction
            ) {
                perform(.follow)
            }
        case .blocked:
            profileAction(
                title: "Unblock musician",
                systemImage: "hand.raised.slash",
                accessibilityID: "profile.unblock",
                isEnabled: !socialGraph.isPerformingAction
            ) {
                perform(.unblock)
            }
        }
    }

    private func profileAction(
        title: LocalizedStringKey,
        systemImage: String,
        accessibilityID: String,
        isPrimary: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        StudioQuestInteractiveSurface(isEnabled: isEnabled, action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .foregroundStyle(isPrimary ? Color.white : Color.primary)
                .background(
                    isPrimary
                        ? StudioQuestTokens.ColorRole.cobalt
                        : StudioQuestTokens.ColorRole.surface(colorScheme),
                    in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous)
                )
        }
        .id(accessibilityID)
        .accessibilityIdentifier(accessibilityID)
    }

    private func perform(_ action: StudioQuestSocialAction) {
        Task { _ = await socialGraph.perform(action, targetUID: userID) }
    }

    private func loadProfileAndRelationship() async {
        async let profileLoad: Void = model.load(userID: userID)
        async let relationshipLoad: Void = socialGraph.loadRelationship(targetUID: userID)
        _ = await (profileLoad, relationshipLoad)
    }
}

@MainActor
private final class StudioQuestPublicProfileModel: ObservableObject {
    @Published var profile: PublicProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(userID: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        #if DEBUG
        if userID.hasPrefix("fixture-") {
            profile = PublicProfile(
                id: userID,
                displayName: fixtureDisplayName(for: userID),
                handle: fixtureHandle(for: userID),
                profilePhotoURL: "",
                instrument: "Violin",
                bio: "Building a thoughtful daily practice.",
                publicLevel: 18,
                avatarID: "avatar_note",
                isPrivate: userID == "fixture-requested",
                allowsMoments: true
            )
            return
        }
        #endif
        do {
            let document = try await Firestore.firestore().collection("publicProfiles").document(userID).getDocument()
            let data = document.data() ?? [:]
            guard document.exists,
                  let displayName = data["displayName"] as? String,
                  let handle = data["handle"] as? String else {
                profile = nil
                return
            }
            profile = PublicProfile(
                id: document.documentID,
                displayName: displayName,
                handle: handle,
                profilePhotoURL: data["profilePhotoURL"] as? String ?? "",
                instrument: data["instrument"] as? String ?? "Musician",
                bio: data["bio"] as? String ?? "",
                publicLevel: data["publicLevel"] as? Int ?? 1,
                avatarID: data["avatarID"] as? String ?? "avatar_note",
                isPrivate: data["isPrivate"] as? Bool ?? true,
                allowsMoments: data["allowsMoments"] as? Bool ?? false
            )
        } catch {
            profile = nil
            errorMessage = "We couldn’t load this profile. Check your connection and try again."
        }
    }

    #if DEBUG
    private func fixtureDisplayName(for userID: String) -> String {
        switch userID {
        case "fixture-aya": "Aya Chen"
        case "fixture-requested": "Lina Park"
        case "fixture-following": "Noah Williams"
        case "fixture-follower": "Maya Ortiz"
        case "fixture-mutual": "Theo Martin"
        case "fixture-blocked": "Blocked Musician"
        default: "Jordan Lee"
        }
    }

    private func fixtureHandle(for userID: String) -> String {
        userID.replacingOccurrences(of: "fixture-", with: "")
    }
    #endif
}

struct StudioQuestConnectionsView: View {
    let initialSection: CommunityConnectionsSection

    @EnvironmentObject private var buddies: BuddiesViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorScheme) private var colorScheme
    @State private var section: CommunityConnectionsSection
    @State private var selectedFriend: BuddySummary?
    @State private var inviteCode = ""
    @State private var inviteSheetPresented = false
    @StateObject private var socialGraph = StudioQuestSocialGraphCoordinator()

    init(initialSection: CommunityConnectionsSection = .friends) {
        self.initialSection = initialSection
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "Connections", subtitle: "Keep your practice circle intentional.")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        connectionActions
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        connectionActions
                    }
                }
                Picker("Connections section", selection: $section) {
                    Text("Friends").tag(CommunityConnectionsSection.friends)
                    Text("Following").tag(CommunityConnectionsSection.following)
                    Text("Followers").tag(CommunityConnectionsSection.followers)
                    Text("Requests").tag(CommunityConnectionsSection.requests)
                }
                .pickerStyle(.segmented)
                content
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .confirmationDialog(
            selectedFriend?.displayName ?? "Friend",
            isPresented: Binding(
                get: { selectedFriend != nil },
                set: { if !$0 { selectedFriend = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let friend = selectedFriend {
                Button("Message") {
                    router.navigate(to: .communityMessages(friendUID: friend.id, threadID: nil), in: .community)
                    selectedFriend = nil
                }
                Button("View profile") {
                    router.navigate(to: .publicProfile(userID: friend.id), in: .community)
                    selectedFriend = nil
                }
                Button("Start duel") {
                    router.navigate(to: .duelArena(challengeID: nil), in: .quest)
                    selectedFriend = nil
                }
                Button("Remove friend", role: .destructive) {
                    Task { await buddies.removeBuddy(friend) }
                    selectedFriend = nil
                }
            }
            Button("Cancel", role: .cancel) { selectedFriend = nil }
        }
        .sheet(isPresented: $inviteSheetPresented) {
            NavigationStack {
                StudioQuestScrollPage {
                    VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                        StudioQuestPageTitle(title: "Add a musician", subtitle: "Use their friend code to send a private connection request.")
                        StudioQuestSection {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Friend code", text: $inviteCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .padding(12)
                                    .background(StudioQuestTokens.ColorRole.raisedSurface(colorScheme), in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous))
                                Button("Send request") {
                                    let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !code.isEmpty else { return }
                                    Task {
                                        _ = await buddies.sendInvite(friendCode: code)
                                        if buddies.statusMessage == "Friend request sent." {
                                            inviteCode = ""
                                            inviteSheetPresented = false
                                        }
                                    }
                                }
                                .buttonStyle(StudioQuestPrimaryButtonStyle())
                                .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        if let status = buddies.statusMessage, !status.isEmpty {
                            StudioQuestInlineStatus(
                                title: status,
                                systemImage: status == "Friend request sent." ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                                tint: status == "Friend request sent." ? StudioQuestTokens.ColorRole.mint : StudioQuestTokens.ColorRole.coral
                            )
                        }
                    }
                    .padding(.top, StudioQuestTokens.Spacing.lg)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Done") { inviteSheetPresented = false } }
                }
            }
        }
        .task(id: section) {
            guard section != .friends else { return }
            await socialGraph.load(section: section)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var connectionActions: some View {
        StudioQuestInteractiveSurface(action: {
            router.navigate(to: .peopleSearch(query: nil), in: .community)
        }) {
            Label("Find musicians", systemImage: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous))
        }
        StudioQuestInteractiveSurface(action: { inviteSheetPresented = true }) {
            Label("Friend code", systemImage: "person.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .friends:
            if buddies.buddies.isEmpty {
                StudioQuestEmptyState(
                    title: "Your studio circle is empty",
                    message: "Use a friend code or search for a musician to make a connection.",
                    systemImage: "person.2.badge.plus"
                ) {
                    router.navigate(to: .peopleSearch(query: nil), in: .community)
                }
            } else {
                ForEach(buddies.buddies) { friend in
                    StudioQuestInteractiveSurface(action: { selectedFriend = friend }) {
                        HStack(spacing: 12) {
                            PBAvatarView(avatarID: friend.avatarID, displayName: friend.displayName, size: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(friend.displayName).font(.headline)
                                Text(friendActivityLine(friend))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous))
                    }
                    .accessibilityLabel("\(friend.displayName), \(friendActivityLine(friend))")
                }
            }
        case .requests:
            VStack(spacing: 12) {
                NavigationLink(value: AppRoute.communityRequests) {
                    StudioQuestRowSurface {
                        Label("Review friend requests", systemImage: "person.crop.circle.badge.clock")
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                socialConnectionRows
            }
        case .following:
            socialConnectionRows
        case .followers:
            socialConnectionRows
        }
    }

    @ViewBuilder
    private var socialConnectionRows: some View {
        if socialGraph.isLoading {
            StudioQuestLoadingState(title: "Loading connections…")
        } else if let error = socialGraph.errorMessage, socialGraph.rows.isEmpty {
            StudioQuestErrorState(
                title: "Connections unavailable",
                message: LocalizedStringKey(error)
            ) {
                Task { await socialGraph.load(section: section) }
            }
        } else if socialGraph.rows.isEmpty {
            relationshipEmpty(
                title: section == .following ? "You are not following anyone yet" : (section == .followers ? "No followers yet" : "No follow requests yet"),
                message: section == .following ? "Search for musicians whose practice inspires you." : "New requests will appear here."
            )
        } else {
            ForEach(socialGraph.rows) { connection in
                HStack(spacing: 12) {
                    StudioQuestInteractiveSurface {
                        router.navigate(to: .publicProfile(userID: connection.id), in: .community)
                    } content: {
                        HStack(spacing: 12) {
                        PBAvatarView(avatarID: connection.avatarID, displayName: connection.displayName, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(connection.displayName).font(.headline)
                            Text("@\(connection.handle) · \(connection.instrument)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }
                    .accessibilityLabel("View \(connection.displayName)'s profile")

                        if section == .requests {
                            HStack(spacing: 8) {
                                Button(connection.isIncoming ? "Accept" : "Cancel") {
                                    Task {
                                        let action: StudioQuestSocialAction = connection.isIncoming ? .acceptFollow : .unfollow
                                        if await socialGraph.perform(action, targetUID: connection.id) { await socialGraph.load(section: section) }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(StudioQuestTokens.ColorRole.cobalt)
                                if connection.isIncoming {
                                    Button("Decline") {
                                        Task {
                                            if await socialGraph.perform(.declineFollow, targetUID: connection.id) { await socialGraph.load(section: section) }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .buttonStyle(.bordered)
                        } else if section == .following {
                            Button("Following") {
                                Task {
                                    if await socialGraph.perform(.unfollow, targetUID: connection.id) { await socialGraph.load(section: section) }
                                }
                            }
                            .buttonStyle(.bordered)
                        } else if section == .followers {
                            Button("Remove") {
                                Task {
                                    if await socialGraph.perform(.removeFollower, targetUID: connection.id) { await socialGraph.load(section: section) }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                }
                .padding(14)
                .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous))
                }
            }
        if let status = socialGraph.statusMessage {
            StudioQuestInlineStatus(text: status, kind: .warning)
        }
    }

    private func relationshipEmpty(title: String, message: String) -> some View {
        StudioQuestEmptyState(title: LocalizedStringKey(title), message: LocalizedStringKey(message), systemImage: "person.2") {
            router.navigate(to: .peopleSearch(query: nil), in: .community)
        }
    }

    /// Reads at the granularity people actually care about. "Practiced today"
    /// collapsed everything from five minutes ago to twenty-three hours ago into
    /// one indistinguishable string, which made the list feel static.
    private func friendActivityLine(_ friend: BuddySummary) -> String {
        let presence = buddies.isBuddyOnline(friend.id) ? "Online" : "Offline"
        guard let date = friend.lastPracticedAt else { return presence }

        let elapsed = Date.now.timeIntervalSince(date)
        let recency: String
        switch elapsed {
        case ..<300:
            recency = "Practising now"
        case ..<3_600:
            recency = "Practiced \(Int(elapsed / 60))m ago"
        case ..<86_400:
            recency = "Practiced \(Int(elapsed / 3_600))h ago"
        default:
            let days = max(
                1,
                Calendar.current.dateComponents(
                    [.day],
                    from: Calendar.current.startOfDay(for: date),
                    to: Calendar.current.startOfDay(for: .now)
                ).day ?? 1
            )
            recency = days == 1 ? "Practiced yesterday" : "Practiced \(days) days ago"
        }
        return "\(presence) · \(recency)"
    }
}

struct StudioQuestPeopleSearchView: View {
    let initialQuery: String?
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = StudioQuestPeopleSearchModel()
    @State private var query: String

    init(initialQuery: String? = nil) {
        self.initialQuery = initialQuery
        _query = State(initialValue: initialQuery ?? "")
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "Find musicians", subtitle: "Search by a public handle. Private profiles stay private.")
                TextField("Search @handle", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous))
                    .onSubmit { Task { await model.search(query) } }
                if model.isLoading {
                    StudioQuestLoadingState(title: "Finding musicians…")
                } else if let error = model.errorMessage {
                    StudioQuestErrorState(
                        title: "Search unavailable",
                        message: LocalizedStringKey(error)
                    ) {
                        Task { await model.search(query) }
                    }
                } else if model.results.isEmpty, !query.isEmpty {
                    StudioQuestEmptyState(title: "No musicians found", message: "Try a different public handle.", systemImage: "magnifyingglass") {}
                } else {
                    ForEach(model.results) { profile in
                        StudioQuestInteractiveSurface(action: {
                            router.navigate(to: .publicProfile(userID: profile.id), in: .community)
                        }) {
                            HStack(spacing: 12) {
                                PBAvatarView(avatarID: profile.avatarID, displayName: profile.displayName, size: 48)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.displayName).font(.headline)
                                    Text("@\(profile.handle) · \(profile.instrument)")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(.background, in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous))
                        }
                    }
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .task(id: query) {
            guard query.count >= 2 else { return }
            try? await Task.sleep(for: .milliseconds(300))
            await model.search(query)
        }
    }
}

@MainActor
private final class StudioQuestPeopleSearchModel: ObservableObject {
    @Published var results: [PublicProfile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func search(_ raw: String) async {
        let query = StudioQuestIdentityValidator.normalizedHandle(raw)
        guard query.count >= 2 else {
            results = []
            errorMessage = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("publicProfiles")
                .order(by: "handle")
                .start(at: [query])
                .end(at: [query + "\u{f8ff}"])
                .limit(to: 20)
                .getDocuments()
            results = snapshot.documents.compactMap { document in
                let data = document.data()
                guard let displayName = data["displayName"] as? String,
                      let handle = data["handle"] as? String else { return nil }
                return PublicProfile(
                    id: document.documentID,
                    displayName: displayName,
                    handle: handle,
                    profilePhotoURL: data["profilePhotoURL"] as? String ?? "",
                    instrument: data["instrument"] as? String ?? "Musician",
                    bio: data["bio"] as? String ?? "",
                    publicLevel: max(1, data["publicLevel"] as? Int ?? 1),
                    avatarID: data["avatarID"] as? String ?? "avatar_note",
                    isPrivate: data["isPrivate"] as? Bool ?? true,
                    allowsMoments: data["allowsMoments"] as? Bool ?? false
                )
            }
        } catch {
            results = []
            errorMessage = "We couldn’t search right now. Check your connection and try again."
        }
    }
}

struct StudioQuestShareCardView: View {
    let sessionID: UUID
    @EnvironmentObject private var store: SessionStore

    private var session: PracticeSessionModel? { store.sessions.first(where: { $0.id == sessionID }) }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "Share progress", subtitle: "A polished card without private reflections.")
                if let session {
                    StudioQuestSection {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(session.noteTitle.isEmpty ? "Practice session" : session.noteTitle)
                                .font(.title2.bold())
                            Text(DurationFormatter.string(from: session.durationSeconds))
                                .font(StudioQuestTokens.Typography.timer)
                                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                            Text(session.verifiedSeconds > 0 ? "Verified practice" : "Practice complete")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    ShareLink(item: "I practiced \(DurationFormatter.string(from: session.durationSeconds)) with PractiQuest.") {
                        Label("Share card", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                } else {
                    StudioQuestEmptyState(title: "Session unavailable", message: "This session may have been removed.", systemImage: "clock.badge.xmark") {}
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
    }
}
