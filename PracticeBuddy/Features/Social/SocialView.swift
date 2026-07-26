import SwiftUI

struct SocialView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var viewModel: StudioChatViewModel
    @EnvironmentObject private var adsManager: PBAdsManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @State private var showNewChatSheet = false
    @State private var searchText: String = ""
    @StateObject private var notificationStore = PBNotificationStore.shared
    @AppStorage("pb.social.chat.openFriendUID") private var openFriendUID: String = ""
    @AppStorage("pb.social.chat.openThreadID") private var openThreadID: String = ""

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        List {
            if viewModel.isLoading {
                VStack(spacing: 10) {
                    PBSkeletonCard(lines: 2)
                        .padding(PBLayout.padSM)
                        .pbSurfaceCard(palette: palette, cornerRadius: PBLayout.radiusControl)
                    PBSkeletonCard(lines: 2)
                        .padding(PBLayout.padSM)
                        .pbSurfaceCard(palette: palette, cornerRadius: PBLayout.radiusControl)
                    PBSkeletonCard(lines: 2)
                        .padding(PBLayout.padSM)
                        .pbSurfaceCard(palette: palette, cornerRadius: PBLayout.radiusControl)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if filteredThreads.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    Text("No conversations yet")
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)
                    Text("Start a friend chat or join a studio.")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Start New Chat") {
                        PBHaptics.tap()
                        showNewChatSheet = true
                    }
                    .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(filteredThreads) { thread in
                        NavigationLink {
                            SocialChatThreadView(threadID: thread.id)
                                .environmentObject(viewModel)
                        } label: {
                            threadRow(thread)
                        }
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                PBHaptics.tap()
                                viewModel.togglePin(threadID: thread.id)
                            } label: {
                                Label(
                                    viewModel.isThreadPinned(thread.id) ? "Unpin" : "Pin",
                                    systemImage: viewModel.isThreadPinned(thread.id) ? "pin.slash" : "pin"
                                )
                            }
                            .tint(.orange)

                            if thread.unreadCount > 0 {
                                Button {
                                    PBHaptics.tap()
                                    viewModel.markThreadReadManually(thread.id)
                                } label: {
                                    Label("Mark Read", systemImage: "checkmark.circle")
                                }
                                .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                PBHaptics.tap()
                                viewModel.toggleMute(threadID: thread.id)
                            } label: {
                                Label(
                                    viewModel.isThreadMuted(thread.id) ? "Unmute" : "Mute",
                                    systemImage: viewModel.isThreadMuted(thread.id) ? "bell" : "bell.slash"
                                )
                            }
                            .tint(.gray)

                            Button(role: .destructive) {
                                PBHaptics.tap()
                                viewModel.hideThreadLocally(thread.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    PBSectionHeaderLabel(title: "Conversations")
                }
            }

            if let status = viewModel.statusMessage, !status.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(palette.accent)
                    Text(LocalizedStringKey(status))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search chats")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    PBHaptics.tap()
                    showNewChatSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New chat")
            }
        }
        .task(id: firebase.currentUserID) {
            guard let uid = firebase.currentUserID else { return }
            viewModel.start(uid: uid)
            consumePendingOpenFriendUID()
            consumePendingOpenThreadID()
            syncInAppNotifications()
        }
        .onChange(of: viewModel.threads) { _, _ in
            syncInAppNotifications()
        }
        .onChange(of: viewModel.unreadCount) { _, _ in
            syncInAppNotifications()
        }
        .onChange(of: openFriendUID) { _, _ in
            consumePendingOpenFriendUID()
        }
        .onChange(of: openThreadID) { _, _ in
            consumePendingOpenThreadID()
        }
        .sheet(isPresented: $showNewChatSheet) {
            NavigationStack {
                newChatSheet
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PBAdBannerSlot(placement: .socialBottomBanner)
                .environmentObject(adsManager)
        }
    }

    private var filteredThreads: [SocialChatThread] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return viewModel.threads }
        return viewModel.threads.filter { thread in
            thread.title.localizedCaseInsensitiveContains(q)
            || thread.lastMessageText.localizedCaseInsensitiveContains(q)
            || thread.subtitle.localizedCaseInsensitiveContains(q)
        }
    }

    private func syncInAppNotifications() {
        notificationStore.syncChatThreads(viewModel.threads)
    }

    private func threadRow(_ thread: SocialChatThread) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(palette.surface)
                    .frame(width: 40, height: 40)
                Image(systemName: "person.2")
                    .foregroundStyle(palette.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(thread.title)
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                    if viewModel.isThreadPinned(thread.id) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.accent.opacity(0.85))
                    }
                    if viewModel.isThreadMuted(thread.id) {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Text(thread.lastMessageText.isEmpty ? "No messages yet" : thread.lastMessageText)
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .allowsTightening(true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                if thread.lastMessageAt > .distantPast {
                    Text(thread.lastMessageAt.formatted(date: .omitted, time: .shortened))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
                }
                if thread.unreadCount > 0 {
                    Text("\(thread.unreadCount)")
                        .font(type.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(palette.accent))
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .pbSurfaceCard(palette: palette, cornerRadius: PBLayout.radiusControl)
    }

    private var newChatSheet: some View {
        List {
            if viewModel.friendCandidates.isEmpty {
                PBEmptyState(
                    icon: "person.crop.circle.badge.plus",
                    title: "No friends yet",
                    message: "Add buddies from the Friends tab, then start a chat with them here."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(viewModel.friendCandidates) { buddy in
                        Button {
                            PBHaptics.tap()
                            viewModel.openFriendThread(friendUID: buddy.id)
                            showNewChatSheet = false
                        } label: {
                            HStack(spacing: 10) {
                                PBAvatarView(
                                    avatarID: buddy.avatarID,
                                    displayName: buddy.displayName,
                                    profilePhotoURL: buddy.profilePhotoURL,
                                    size: 30
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(buddy.displayName)
                                        .font(type.body)
                                        .foregroundStyle(palette.textPrimary)
                                    Text("Level \(buddy.publicLevel)")
                                        .font(type.footnote)
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    PBSectionHeaderLabel(title: "Practice Buddies")
                }
            }
        }
        .navigationTitle("New Chat")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func consumePendingOpenFriendUID() {
        let uid = openFriendUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { return }
        openFriendUID = ""
        viewModel.openFriendThread(friendUID: uid)
    }

    private func consumePendingOpenThreadID() {
        let threadID = openThreadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !threadID.isEmpty else { return }
        openThreadID = ""
        viewModel.openThread(threadID: threadID)
    }
}

struct SocialChatThreadView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var viewModel: StudioChatViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @FocusState private var isComposerFocused: Bool
    let threadID: String

    private var backgroundColor: Color { StudioQuestTokens.ColorRole.background(colorScheme) }
    private var surfaceColor: Color { StudioQuestTokens.ColorRole.surface(colorScheme) }

    private var thread: SocialChatThread? {
        viewModel.threads.first(where: { $0.id == threadID })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if viewModel.messages.isEmpty {
                            Text("No messages yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 24)
                        } else {
                            ForEach(viewModel.messages) { message in
                                SocialMessageBubbleView(
                                    message: message,
                                    isCurrentUser: message.senderUID == firebase.currentUserID
                                )
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastID = viewModel.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                .onTapGesture {
                    isComposerFocused = false
                }
            }

            composer
        }
        .background {
            backgroundColor.ignoresSafeArea()
        }
        .navigationTitle(thread?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .task(id: threadID) {
            viewModel.selectThread(threadID)
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let status = viewModel.statusMessage, !status.isEmpty {
                Text(LocalizedStringKey(status))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            HStack(spacing: 8) {
                TextField("Write a message…", text: $viewModel.draftMessage, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        StudioQuestTokens.ColorRole.raisedSurface(colorScheme),
                        in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous)
                    )

                Button {
                    PBHaptics.tap()
                    Task {
                        await viewModel.sendMessage()
                        isComposerFocused = false
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(StudioQuestTokens.ColorRole.cobalt, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
                .disabled(viewModel.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
        .background(surfaceColor)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
