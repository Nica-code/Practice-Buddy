import SwiftUI

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
