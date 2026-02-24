import SwiftUI

struct UserProfileView: View {
    @ObservedObject var buddiesVM: BuddiesViewModel

    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @State private var avatarID: String = "avatar_note"
    @State private var bio: String = ""
    @State private var instrument: String = ""
    @State private var animateHeader = false

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var chrome: Color { theme.chromeBackground(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
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
        .toolbarBackground(chrome, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
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
                            Text(LocalizedStringKey(purchaseManager.accountType.title))
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer()
                }

                HStack {
                    Text("Friend code")
                        .font(type.body)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(profile.friendCode)
                        .font(type.number)
                        .foregroundStyle(palette.textSecondary)
                        .monospacedDigit()
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

            TextField("Short bio", text: $bio, axis: .vertical)
                .font(type.body)
                .lineLimit(2...4)

            Text("Bio can be up to 160 characters.")
                .font(type.footnote)
                .foregroundStyle(palette.textSecondary)

            let columns = [GridItem(.adaptive(minimum: 74), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(PBAvatarStyle.all, id: \.id) { style in
                    let selected = style.id == avatarID
                    Button {
                        avatarID = style.id
                    } label: {
                        VStack(spacing: 6) {
                            PBAvatarView(avatarID: style.id, displayName: style.title, size: 44)
                            Text(LocalizedStringKey(style.title))
                                .font(type.footnote)
                                .foregroundStyle(palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(selected ? palette.accent.opacity(0.18) : palette.surfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                Task {
                    await buddiesVM.updateProfile(avatarID: avatarID, bio: bio, instrument: instrument)
                    await buddiesVM.syncPublicLevel(journey.level)
                }
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
}
