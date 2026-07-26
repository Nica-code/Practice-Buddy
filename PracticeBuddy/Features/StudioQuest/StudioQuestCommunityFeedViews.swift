import SwiftUI
import Combine

struct StudioQuestCommunityFeedView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var buddies: BuddiesViewModel
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var community = CommunityCoordinator()
    @State private var signInPresented = false

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                header
                if let status = community.statusMessage {
                    StudioQuestInlineStatus(text: status, kind: .warning)
                }
                feedContent
            }
            .padding(.top, StudioQuestTokens.Spacing.sm)
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await community.refresh() }
        .task(id: firebase.currentUserID) {
            await community.configure(uid: firebase.currentUserID, isAnonymous: firebase.isAnonymousUser)
        }
        .sheet(isPresented: $signInPresented) { AccountSetupView() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            StudioQuestPageTitle(title: "Community", subtitle: "Practice alongside musicians you trust.")
            Spacer(minLength: 10)
            HStack(spacing: 4) {
                headerAction("magnifyingglass", label: "Search musicians") {
                    requireAccount { router.navigate(to: .peopleSearch(query: nil), in: .community) }
                }
                headerAction("person.2", label: "Connections") {
                    requireAccount { router.navigate(to: .communityConnections(section: .friends), in: .community) }
                }
                headerAction("bubble.left.and.bubble.right", label: "Messages") {
                    requireAccount { router.navigate(to: .communityMessages(friendUID: nil, threadID: nil), in: .community) }
                }
            }
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        if firebase.isAnonymousUser {
            StudioQuestSection {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Practice privately, then join your community.", systemImage: "lock.fill")
                        .font(.headline)
                    Text("Your practice stays available without an account. Create a permanent profile when you want Messages, connections, duels, and Moments.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Set up profile") { signInPresented = true }
                        .buttonStyle(StudioQuestPrimaryButtonStyle())
                }
            }
        } else if community.isLoading && community.moments.isEmpty {
            StudioQuestLoadingState(title: "Loading your practice world…")
        } else if community.moments.isEmpty {
            StudioQuestEmptyState(
                title: "No Moments yet",
                message: "Follow a musician or publish a five-minute practice session to begin your feed.",
                systemImage: "music.note.house"
            ) {
                router.navigate(to: .communityConnections(section: .friends), in: .community)
            }
        } else {
            ForEach(community.moments) { moment in
                momentCard(moment)
            }
        }
    }

    private func momentCard(_ moment: PracticeMoment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                router.navigate(to: .publicProfile(userID: moment.authorUID), in: .community)
            } label: {
                HStack(spacing: 10) {
                    socialIdentity(photoURL: moment.profilePhotoURL, avatarID: moment.avatarLoadout.baseID, name: moment.displayName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(moment.displayName).font(.headline)
                        Text("@\(moment.handle) · \(moment.instrument)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(moment.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                router.navigate(to: .practiceMoment(momentID: moment.id), in: .community)
            } label: {
                StudioQuestAvatarScene(
                    loadout: moment.avatarLoadout,
                    layout: moment.avatarLoadout.layout(),
                    displayName: moment.displayName
                )
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(moment.tag.title)
                            .font(.headline)
                        Text("\(moment.durationBucket) · \(moment.practiceCategory)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .top, endPoint: .bottom))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(moment.displayName)'s \(moment.tag.title) Moment")

            HStack(spacing: 8) {
                if moment.isVerified { StudioQuestVerifiedLabel(isVerified: true) }
                ForEach(MomentReactionKind.allCases) { reaction in
                    Button {
                        Task { await community.react(to: moment, kind: reaction) }
                    } label: {
                        Label(
                            "\(moment.reactions[reaction, default: 0])",
                            systemImage: reaction.systemImage
                        )
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(StudioQuestTokens.ColorRole.raisedSurface(colorScheme), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("React \(reaction.title)")
                }
            }
        }
        .padding(StudioQuestTokens.Spacing.md)
        .studioQuestSurface()
    }

    private func socialIdentity(photoURL: String, avatarID: String, name: String) -> some View {
        Group {
            if let url = URL(string: photoURL), !photoURL.isEmpty {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    PBAvatarView(avatarID: avatarID, displayName: name, size: 40)
                }
            } else {
                PBAvatarView(avatarID: avatarID, displayName: name, size: 40)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private func headerAction(_ image: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func requireAccount(_ action: @escaping () -> Void) {
        if firebase.isAnonymousUser {
            signInPresented = true
        } else {
            action()
        }
    }
}

struct StudioQuestPracticeMomentComposer: View {
    let prompt: PracticeMomentPrompt

    @EnvironmentObject private var coordinator: PracticeSessionCoordinator
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("practiquest.avatar.loadout") private var loadoutData = Data()
    @StateObject private var community = CommunityCoordinator()
    @State private var tag: MomentTag = .focusedWork
    @State private var audience: MomentAudience = .friends
    @State private var isPublishing = false

    private var session: PracticeSessionModel? {
        store.sessions.first(where: { $0.id == prompt.sessionID })
    }

    private var loadout: AvatarLoadout {
        (try? JSONDecoder().decode(AvatarLoadout.self, from: loadoutData)) ?? .starter(for: nil)
    }

    var body: some View {
        NavigationStack {
            StudioQuestScrollPage {
                VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                    StudioQuestPageTitle(title: "Share a Practice Moment", subtitle: "A generated card—never your notes, audio, or reflection.")
                    StudioQuestAvatarScene(loadout: loadout, layout: loadout.layout(), displayName: "Your musician")
                    Picker("Moment tag", selection: $tag) {
                        ForEach(MomentTag.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Picker("Audience", selection: $audience) {
                        Text("Friends").tag(MomentAudience.friends)
                        Text("Following").tag(MomentAudience.followers)
                    }
                    .pickerStyle(.segmented)
                    StudioQuestInlineStatus(
                        text: "This Moment disappears after 24 hours. Your private session remains in History.",
                        kind: .information
                    )
                    if let status = community.statusMessage {
                        StudioQuestInlineStatus(text: status, kind: .error)
                    }
                    Button(isPublishing ? "Publishing…" : "Publish Moment") {
                        publish()
                    }
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
                    .disabled(isPublishing || session == nil)
                }
                .padding(.top, StudioQuestTokens.Spacing.lg)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") {
                        coordinator.momentPrompt = nil
                        dismiss()
                    }
                }
            }
        }
    }

    private func publish() {
        guard let session else { return }
        isPublishing = true
        Task {
            let published = await community.publish(
                sessionID: session.id,
                durationSeconds: session.durationSeconds,
                // A Moment never receives user-entered reflection or note text.
                // V2 cards carry only a fixed app-owned practice category.
                category: "Focused practice",
                verified: session.verifiedSeconds > 0,
                tag: tag,
                audience: audience,
                loadout: loadout
            )
            isPublishing = false
            if published {
                coordinator.momentPrompt = nil
                dismiss()
            }
        }
    }
}

struct StudioQuestMomentDetailView: View {
    let momentID: String
    @StateObject private var repository = PracticeMomentDetailModel()
    @StateObject private var socialGraph = StudioQuestSocialGraphCoordinator()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        StudioQuestScrollPage {
            Group {
                if let moment = repository.moment {
                    VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
                        StudioQuestPageTitle(title: "Practice Moment", subtitle: "@\(moment.handle)")
                        Text(moment.tag.title)
                            .font(StudioQuestTokens.Typography.sectionTitle)
                        StudioQuestAvatarScene(
                            loadout: moment.avatarLoadout,
                            layout: moment.avatarLoadout.layout(),
                            displayName: moment.displayName
                        )
                        StudioQuestInlineStatus(
                            text: "This generated Moment expires \(moment.expiresAt.formatted(.relative(presentation: .named))).",
                            kind: .information
                        )
                        Menu {
                            Button("Report Moment", systemImage: "exclamationmark.bubble", role: .destructive) {
                                Task {
                                    _ = await socialGraph.perform(
                                        .reportMoment,
                                        targetUID: moment.authorUID,
                                        reason: ["targetID": moment.id, "kind": "other"]
                                    )
                                }
                            }
                            Button("Mute musician", systemImage: "speaker.slash") {
                                Task { _ = await socialGraph.perform(.mute, targetUID: moment.authorUID) }
                            }
                        } label: {
                            Label("Moment actions", systemImage: "ellipsis.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous))
                        }
                        if let status = socialGraph.statusMessage {
                            StudioQuestInlineStatus(text: status, kind: .warning)
                        }
                    }
                } else if repository.isLoading {
                    StudioQuestLoadingState(title: "Loading Moment…")
                } else {
                    StudioQuestEmptyState(title: "Moment unavailable", message: "It may have expired or been removed.", systemImage: "clock.badge.xmark") {}
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.lg)
        }
        .task { await repository.load(momentID: momentID) }
    }
}

@MainActor
private final class PracticeMomentDetailModel: ObservableObject {
    @Published var moment: PracticeMoment?
    @Published var isLoading = false
    private let repository = PracticeMomentRepository()

    func load(momentID: String) async {
        isLoading = true
        defer { isLoading = false }
        moment = try? await repository.fetchMoment(id: momentID)
    }
}
