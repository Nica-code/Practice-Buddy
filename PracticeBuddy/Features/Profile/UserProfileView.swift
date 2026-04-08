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
    @State private var avatarStatusMessage: String?
    @FocusState private var focusedField: ProfileField?

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var equippedFrameID: String? { journey.equippedRewardID(for: .profileFrame) }
    private var equippedBannerID: String? { journey.equippedRewardID(for: .profileBanner) }
    private var equippedGlowID: String? { journey.equippedRewardID(for: .profileGlow) }
    private var equippedDuelIntroID: String? { journey.equippedRewardID(for: .duelIntroCard) }
    private var equippedDuelFinisherID: String? { journey.equippedRewardID(for: .duelFinisherFX) }
    private var equippedSessionSkinID: String? { journey.equippedRewardID(for: .sessionCardSkin) }
    
    private func profileSectionCard<Content: View>(
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
        VStack(spacing: 0) {
            profileShortcutRow
            topProfileCard

            List {
                progressSection
                iconsSection
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
        .pbFlatCard(palette: palette)
        .background(profileBannerBackground)
        .overlay(profileFrameOverlay)
        .shadow(
            color: profileGlowColor.opacity(profileGlowID == nil ? 0 : 0.38),
            radius: profileGlowID == nil ? 0 : 14,
            x: 0,
            y: 4
        )
        .padding(.horizontal, PBLayout.padSM)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .offset(y: animateHeader ? 0 : 12)
        .opacity(animateHeader ? 1 : 0)
    }

    @ViewBuilder
    private var profileBannerBackground: some View {
        if equippedBannerID == "reward_profile_banner_concert" {
            RoundedRectangle(cornerRadius: PBLayout.radiusCard, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.accent.opacity(0.26),
                            palette.surface.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    @ViewBuilder
    private var profileFrameOverlay: some View {
        if equippedFrameID == "reward_profile_frame_studio" {
            RoundedRectangle(cornerRadius: PBLayout.radiusCard, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [palette.accent.opacity(0.7), palette.textSecondary.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.4
                )
        }
    }

    private var profileGlowID: String? { equippedGlowID }
    private var profileGlowColor: Color {
        if profileGlowID == "reward_profile_glow_soft" {
            return palette.accent
        }
        return .clear
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
            profileSectionCard {
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Duel cosmetics")
                        .font(type.footnote.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(equippedDuelIntroID == nil ? "Intro card: none" : "Intro card: Spotlight")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Text(equippedDuelFinisherID == nil ? "Finisher FX: none" : "Finisher FX: Resonance")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Text(equippedSessionSkinID == nil ? "Session skin: none" : "Session skin: Aurora")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var iconsSection: some View {
        Section("Icons") {
            profileSectionCard {
                HStack {
                    Text("Choose your profile icon.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Label("\(journey.tokenBalance)", systemImage: "seal.fill")
                        .font(type.footnote.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }

                avatarCarousel(title: "Free", styles: PBAvatarStyle.freeStyles)
                avatarCarousel(title: "Token Unlocks", styles: PBAvatarStyle.tokenStyles)

                if let avatarStatusMessage, !avatarStatusMessage.isEmpty {
                    Text(avatarStatusMessage)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func avatarCarousel(title: String, styles: [PBAvatarStyle]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(type.footnote.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(styles, id: \.id) { style in
                        avatarOptionCard(style: style)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func avatarOptionCard(style: PBAvatarStyle) -> some View {
        let selected = style.id == avatarID
        let unlocked = style.isFree || journey.isAvatarUnlocked(id: style.id)
        let affordable = avatarAffordable(style)
        let highlight = selected ? palette.accent.opacity(0.18) : palette.surfaceAlt

        return Button {
            handleAvatarSelection(style)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    PBAvatarView(avatarID: style.id, displayName: style.title, size: 42)
                    Spacer()
                    if selected {
                        Label("Selected", systemImage: "checkmark.circle.fill")
                            .font(type.fontChoice.headlineFont(size: 10, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    } else if !unlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                Text(LocalizedStringKey(style.title))
                    .font(type.footnote.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                Text(LocalizedStringKey(style.subtitle))
                    .font(type.fontChoice.bodyFont(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)

                Text(avatarActionLabel(style: style, unlocked: unlocked, selected: selected))
                    .font(type.fontChoice.headlineFont(size: 11, weight: .semibold))
                    .foregroundStyle(!unlocked && !affordable ? palette.textSecondary : palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 122, height: 128, alignment: .topLeading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                    .fill(highlight)
                    .overlay(
                        RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                            .stroke(
                                selected ? palette.accent.opacity(0.38) : Color.black.opacity(0.06),
                                lineWidth: selected ? 1.4 : 1
                            )
                    )
            )
            .opacity(!unlocked && !affordable ? 0.58 : 1)
        }
        .buttonStyle(.plain)
        .disabled(journey.isEconomyOperationInProgress || (!unlocked && !affordable))
        .accessibilityLabel(Text("\(style.title), \(style.subtitle)"))
        .accessibilityValue(Text(avatarActionLabel(style: style, unlocked: unlocked, selected: selected)))
    }

    private func avatarAffordable(_ style: PBAvatarStyle) -> Bool {
        guard let cost = style.tokenCost else { return true }
        return journey.tokenBalance >= cost
    }

    private func avatarActionLabel(style: PBAvatarStyle, unlocked: Bool, selected: Bool) -> String {
        if selected { return "Selected" }
        if unlocked { return "Tap to select" }
        if let cost = style.tokenCost { return "Unlock • \(cost)" }
        return "Locked"
    }

    private func handleAvatarSelection(_ style: PBAvatarStyle) {
        let unlocked = style.isFree || journey.isAvatarUnlocked(id: style.id)
        if unlocked {
            avatarID = style.id
            avatarStatusMessage = "Selected \(style.title). Tap Save Profile to apply."
            return
        }

        guard let cost = style.tokenCost else { return }
        guard journey.tokenBalance >= cost else {
            avatarStatusMessage = "Not enough tokens to unlock \(style.title)."
            return
        }

        Task {
            let didUnlock = await journey.unlockAvatar(id: style.id)
            if didUnlock {
                avatarID = style.id
                avatarStatusMessage = "Unlocked \(style.title) for \(cost) tokens. Tap Save Profile to apply."
            } else {
                avatarStatusMessage = "Could not unlock \(style.title) right now. Try again."
            }
        }
    }

    private var personalizeSection: some View {
        Section("Personalize") {
            profileSectionCard {
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
        }
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
