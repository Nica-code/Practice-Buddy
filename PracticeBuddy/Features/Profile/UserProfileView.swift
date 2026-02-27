import SwiftUI

struct UserProfileView: View {
    private enum ProfileField {
        case instrument
        case bio
    }

    @ObservedObject var buddiesVM: BuddiesViewModel

    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var duelLeague: DuelLeagueManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("pb.tab.selection") private var selectedTab: Int = 3

    @State private var avatarID: String = "avatar_note"
    @State private var bio: String = ""
    @State private var instrument: String = ""
    @State private var animateHeader = false
    @State private var showShopSheet = false
    @FocusState private var focusedField: ProfileField?

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            profileShortcutRow
            topProfileCard

            List {
                progressSection
                personalizeSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
        }
        .background {
            PBBackdropView(palette: palette)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !animateHeader {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    animateHeader = true
                }
            }
            guard let profile = buddiesVM.myProfile else { return }
            avatarID = profile.avatarID
            bio = profile.bio
            instrument = profile.instrument
        }
        .sheet(isPresented: $showShopSheet) {
            NavigationStack {
                ShopView()
            }
        }
    }

    private var profileShortcutRow: some View {
        PBShortcutBar(items: profileShortcutItems, palette: palette)
            .padding(.horizontal, PBLayout.padSM)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .offset(y: animateHeader ? 0 : 10)
            .opacity(animateHeader ? 1 : 0)
    }

    private var topProfileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profile")
                .font(type.appTitle)
                .tracking(type.heroTracking)
                .foregroundStyle(palette.textPrimary)

            Text("Manage your public profile and personal details.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

            if let profile = buddiesVM.myProfile {
                HStack(spacing: 10) {
                    PBAvatarView(avatarID: avatarID, displayName: profile.displayName, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                            .font(type.sectionTitle)
                            .foregroundStyle(palette.textPrimary)
                        HStack(spacing: 8) {
                            PBLevelBadgeView(level: max(1, profile.publicLevel))
                            Text(duelLeague.leagueTier.title)
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer()
                }

            } else {
                Text("Loading profile…")
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(PBLayout.padLG)
        .pbModernCard(palette: palette)
        .padding(.horizontal, PBLayout.padSM)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .offset(y: animateHeader ? 0 : 12)
        .opacity(animateHeader ? 1 : 0)
    }

    private var profileShortcutItems: [PBShortcutItem] {
        [
            PBShortcutItem(
                id: "profile_save",
                title: "Save",
                systemImage: "square.and.arrow.down.fill",
                action: {
                    saveProfile()
                }
            ),
            PBShortcutItem(
                id: "profile_journey",
                title: "Play",
                systemImage: "gamecontroller.fill",
                action: { selectedTab = 1 }
            ),
            PBShortcutItem(
                id: "profile_store",
                title: "Shop",
                systemImage: "bag.fill",
                action: { showShopSheet = true }
            )
        ]
    }

    private var progressSection: some View {
        Section("Progress") {
            HStack {
                Text("Current level")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(L10n.f("Lv %@", "\(journey.level)"))
                    .font(type.number)
                    .foregroundStyle(palette.accent)
                    .monospacedDigit()
            }

            HStack {
                Text("XP")
                    .font(type.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(L10n.f("%@/%@", "\(journey.xpIntoLevel)", "\(journey.xpForNextLevel)"))
                    .font(type.number)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }

            ProgressView(value: journey.xpForNextLevel == 0 ? 0 : Double(journey.xpIntoLevel) / Double(journey.xpForNextLevel))
        }
        .listRowBackground(palette.surface)
    }

    private var personalizeSection: some View {
        Section("Personalize") {
            TextField("Instrument", text: $instrument)
                .font(type.body)
                .focused($focusedField, equals: .instrument)

            TextField("Short bio", text: $bio, axis: .vertical)
                .font(type.body)
                .lineLimit(2...4)
                .focused($focusedField, equals: .bio)

            Text("Bio can be up to 160 characters.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

            let columns = [GridItem(.adaptive(minimum: 112), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(PBAvatarStyle.all, id: \.id) { style in
                    let selected = style.id == avatarID
                    Button {
                        avatarID = style.id
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                PBAvatarView(avatarID: style.id, displayName: style.title, size: 42)
                                Spacer()
                                Text(style.availability.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(selected ? palette.accent : palette.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background((selected ? palette.accent.opacity(0.18) : palette.surface).clipShape(Capsule()))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(style.title))
                                    .font(type.footnote.weight(.semibold))
                                    .foregroundStyle(palette.textPrimary)
                                Text(LocalizedStringKey(style.subtitle))
                                    .font(.caption2)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                                .fill(selected ? palette.accent.opacity(0.16) : palette.surfaceAlt)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                                        .stroke(selected ? palette.accent.opacity(0.35) : Color.black.opacity(0.04), lineWidth: selected ? 1.5 : 1)
                                )
                                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                saveProfile()
            } label: {
                Text("Save Profile")
                    .font(type.button)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)

            if let msg = buddiesVM.statusMessage, !msg.isEmpty {
                Text(LocalizedStringKey(msg))
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .listRowBackground(palette.surface)
    }

    private func saveProfile() {
        focusedField = nil
        Task {
            await buddiesVM.updateProfile(avatarID: avatarID, bio: bio, instrument: instrument)
            await buddiesVM.syncPublicLevel(journey.level)
        }
    }
}

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
            if isLoadingProfile && profile == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading profile…")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            } else if let profile {
                HStack(spacing: 10) {
                    PBAvatarView(avatarID: profile.avatarID, displayName: profile.displayName, size: 48)
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
        .listRowBackground(palette.surface)
    }

    @ViewBuilder
    private var friendRequestSection: some View {
        Section("Friend") {
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
        .listRowBackground(palette.surface)
    }

    private func loadProfile() async {
        guard !userID.isEmpty else { return }
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        profile = await buddiesVM.loadUserProfile(uid: userID)
    }
}
