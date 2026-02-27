import SwiftUI

struct SocialView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var viewModel: StudioChatViewModel
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @State private var showNewChatSheet = false
    @State private var searchText: String = ""

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
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
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section("Conversations") {
                    ForEach(filteredThreads) { thread in
                        NavigationLink {
                            SocialChatThreadView(threadID: thread.id)
                                .environmentObject(viewModel)
                        } label: {
                            threadRow(thread)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
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
                                    viewModel.markThreadReadManually(thread.id)
                                } label: {
                                    Label("Mark Read", systemImage: "checkmark.circle")
                                }
                                .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                viewModel.toggleMute(threadID: thread.id)
                            } label: {
                                Label(
                                    viewModel.isThreadMuted(thread.id) ? "Unmute" : "Mute",
                                    systemImage: viewModel.isThreadMuted(thread.id) ? "bell" : "bell.slash"
                                )
                            }
                            .tint(.gray)

                            Button(role: .destructive) {
                                viewModel.hideThreadLocally(thread.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background {
            PBBackdropView(palette: palette)
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search chats")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
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
        }
        .sheet(isPresented: $showNewChatSheet) {
            NavigationStack {
                newChatSheet
            }
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

    private func threadRow(_ thread: SocialChatThread) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(palette.surface)
                    .frame(width: 40, height: 40)
                Image(systemName: thread.kind == .studio ? "building.2" : "person.2")
                    .foregroundStyle(palette.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(thread.title)
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    if viewModel.isThreadPinned(thread.id) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
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
        .padding(.vertical, 4)
    }

    private var newChatSheet: some View {
        List {
            if viewModel.friendCandidates.isEmpty {
                Text("No friends yet.")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Section("Practice Buddies") {
                    ForEach(viewModel.friendCandidates) { buddy in
                        Button {
                            viewModel.openFriendThread(friendUID: buddy.id)
                            showNewChatSheet = false
                        } label: {
                            HStack(spacing: 10) {
                                PBAvatarView(avatarID: buddy.avatarID, displayName: buddy.displayName, size: 30)
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
                }
            }
        }
        .navigationTitle("New Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SocialChatThreadView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var viewModel: StudioChatViewModel
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @FocusState private var isComposerFocused: Bool
    let threadID: String

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

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
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .padding(.top, 24)
                        } else {
                            ForEach(viewModel.messages) { message in
                                messageBubble(message)
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
            PBBackdropView(palette: palette)
        }
        .navigationTitle(thread?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .task(id: threadID) {
            viewModel.selectThread(threadID)
        }
    }

    private func messageBubble(_ message: SocialChatMessage) -> some View {
        let isMine = message.senderUID == firebase.currentUserID
        return HStack {
            if isMine { Spacer(minLength: 40) }
            HStack(alignment: .top, spacing: 8) {
                PBAvatarView(avatarID: message.senderAvatarID, displayName: message.senderName, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(message.senderName)
                            .font(type.footnote)
                            .foregroundStyle(isMine ? palette.textPrimary : palette.textSecondary)
                        PBLevelBadgeView(level: message.senderLevel)
                    }

                    Text(message.text)
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)

                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                    .fill(isMine ? palette.accent.opacity(0.22) : palette.surface)
                    .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
            )
            if !isMine { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let status = viewModel.statusMessage, !status.isEmpty {
                Text(LocalizedStringKey(status))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            HStack(spacing: 8) {
                TextField("Write a message…", text: $viewModel.draftMessage, axis: .vertical)
                    .font(type.body)
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .padding(10)
                    .pbSurfaceCard(palette: palette, cornerRadius: PBLayout.radiusControl)

                Button("Send") {
                    Task {
                        await viewModel.sendMessage()
                        isComposerFocused = false
                    }
                }
                .buttonStyle(PBActionButtonStyle(variant: .primary, palette: palette))
                .disabled(viewModel.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .background(chrome)
    }
}
