import SwiftUI
import UIKit

struct SocialView: View {
    @EnvironmentObject private var firebase: FirebaseBootstrap
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var viewModel = StudioChatViewModel()
    @FocusState private var isComposerFocused: Bool

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            if let studio = viewModel.studio {
                header(studio: studio)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if viewModel.messages.isEmpty {
                                Text("No messages yet. Say hi to your studio.")
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
            } else if viewModel.isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading studio chat…")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    Text("Studio Chat")
                        .font(type.sectionTitle)
                        .foregroundStyle(palette.textPrimary)
                    Text("Join a studio to chat with your teacher and studio buddies.")
                        .font(type.body)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(chrome.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .task(id: firebase.currentUserID) {
            guard let uid = firebase.currentUserID else { return }
            viewModel.start(uid: uid, role: purchaseManager.accountType)
        }
        .onChange(of: purchaseManager.accountType) { _, newRole in
            guard let uid = firebase.currentUserID else { return }
            viewModel.start(uid: uid, role: newRole)
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private func header(studio: StudioInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Studio Chat")
                .font(type.sectionTitle)
                .foregroundStyle(palette.textPrimary)
            Text(studio.name)
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func messageBubble(_ message: StudioChatMessage) -> some View {
        let isMine = message.senderUID == firebase.currentUserID
        return HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.senderName)
                    .font(type.footnote.weight(.semibold))
                    .foregroundStyle(isMine ? palette.textPrimary : palette.textSecondary)

                Text(message.text)
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)

                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(10)
            .background(isMine ? palette.accent.opacity(0.22) : palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
            if !isMine { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let status = viewModel.statusMessage, !status.isEmpty {
                Text(status)
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
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))

                Button("Send") {
                    Task {
                        await viewModel.sendMessage()
                        isComposerFocused = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .background(chrome)
    }
}
