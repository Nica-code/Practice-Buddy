import SwiftUI

struct PublicUserProfileView: View {
    let userID: String
    let fallbackDisplayName: String

    @EnvironmentObject private var firebase: FirebaseBootstrap
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var buddiesVM = BuddiesViewModel()
    @State private var profile: FirebaseUserProfile?
    @State private var isLoadingProfile = false

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }
    
    private func publicProfileSectionCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(PBLayout.padMD)
        .pbModernCard(palette: palette)
        .listRowInsets(
            EdgeInsets(
                top: 4,
                leading: 0,
                bottom: 4,
                trailing: 0
            )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    var body: some View {
        List {
            profileSection
            friendRequestSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background {
            PBBackdropView(palette: palette)
        }
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: firebase.currentUserID) {
            guard let uid = firebase.currentUserID else { return }
            await buddiesVM.start(for: uid)
            await loadProfile()
        }
        .task(id: userID) {
            await loadProfile()
        }
    }

    private var profileSection: some View {
        Section("Public Profile") {
            publicProfileSectionCard {
                if isLoadingProfile && profile == nil {
                    PBSkeletonCard(lines: 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let profile {
                    HStack(spacing: 10) {
                        PBAvatarView(
                            avatarID: profile.avatarID,
                            displayName: profile.displayName,
                            profilePhotoURL: profile.profilePhotoURL,
                            size: 48
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName)
                                .font(type.sectionTitle)
                                .foregroundStyle(palette.textPrimary)
                            HStack(spacing: 8) {
                                PBLevelBadgeView(level: profile.publicLevel)
                                if !profile.instrument.isEmpty {
                                    Text(profile.instrument)
                                        .font(type.footnote)
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                        }
                        Spacer()
                    }

                    if !profile.bio.isEmpty {
                        Text(profile.bio)
                            .font(type.body)
                            .foregroundStyle(palette.textPrimary)
                    }
                } else {
                    Text(fallbackDisplayName)
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private var friendRequestSection: some View {
        Section("Friend") {
            publicProfileSectionCard {
                switch buddiesVM.relationshipState(with: userID) {
                case .me:
                    Text("This is your profile.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)

                case .friends:
                    Label("You are friends", systemImage: "checkmark.circle.fill")
                        .font(type.body)
                        .foregroundStyle(palette.accent)

                case .incoming(let invite):
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This user sent you a friend request.")
                            .font(type.footnote)
                            .foregroundStyle(palette.textSecondary)
                        HStack {
                            Button("Accept") {
                                Task { await buddiesVM.acceptInvite(invite) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(palette.accent)

                            Button("Reject", role: .destructive) {
                                Task { await buddiesVM.declineInvite(invite) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                case .outgoing:
                    Text("Friend request pending.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)

                case .notFriends:
                    Button {
                        Task { await buddiesVM.sendInvite(to: userID) }
                    } label: {
                        Label("Add Friend", systemImage: "person.badge.plus")
                            .font(type.button)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                }

                if let message = buddiesVM.statusMessage, !message.isEmpty {
                    Text(LocalizedStringKey(message))
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func loadProfile() async {
        guard !userID.isEmpty else { return }
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        profile = await buddiesVM.loadUserProfile(uid: userID)
    }
}
